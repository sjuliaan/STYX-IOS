// ============================================================================
// STYX-iOS — aim assist
//
// WHY THIS WRITES A FIELD INSTEAD OF HOOKING A RETURN VALUE
//
// The Android mod (Main.cpp:2701) hooks GetAssitAimSpeed and returns a bigger
// number. That works on Android. It does nothing on iOS, because on iOS the
// assist magnitude is a plain float field the game reads directly, and
// GetAssitAimSpeed's return value is not the number the assist math consumes.
// That function has ZERO direct BL call sites in the 1.6.58 binary -- it is
// reached only through the vtable.
//
// Verified against the real binary:
//
//   0x2663D9C  get_AimAssistanceSpeed       ldr s0, [x0, #0x1C8] ; ret
//   0x2663DAC  OverrideAimAssistanceSpeed   str s8, [x19, #0x1C8]
//   0x2663E10  ReloadInitAimAssistanceSpeed ldr s0,[x19,#0x1D0]
//                                           str s0,[x19,#0x1C8]
//   0x2665E04  config apply                 ldr s0,[x20,#0x14]
//                                           str s0,[x19,#0x1C8]
//                                           str s0,[x19,#0x1D0]
//   0x2665EA4  consumption                  ldr s8,[x19,#0x1C8]
//                                           str s8,[x20,#0x14]
//
// So the game's own assist speed lives at PlayerController+0x1C8, and 0x1D0 is
// the "initial" value that reload copies back into 0x1C8. We therefore write
// BOTH fields: writing only 0x1C8 gets clobbered on the next reload.
//
// The GetAssitAimSpeed hook is still installed (requested: always hooked), but
// it is a pass-through. Keeping it costs nothing and avoids leaving the game's
// assist path patched with a value it ignores.
// ============================================================================
#import <Foundation/Foundation.h>
#import "StyxConfig.h"
#import "StyxOffsets.h"
#import "StyxTypes.h"
#import "StyxHook.h"

StyxAimStats_t StyxAimStats;

// How often we re-assert the field. The game can rewrite it on spawn, on
// weapon change and via ReloadInitAimAssistanceSpeed; 250ms is fast enough to
// look continuous and cheap enough to be invisible.
#define STYX_AIM_TICK_SEC   0.25

typedef void *(*GetLocalPCFn)(void);
static GetLocalPCFn fnLocalPC = NULL;

static void *StyxResolveLocalPC(void) {
    if (fnLocalPC) return fnLocalPC();
    uintptr_t b = StyxBase();
    // vtable-safe: only patch if the target looks like code we expect.
    if (b == 0) return NULL;
    fnLocalPC = (GetLocalPCFn)(b + IOS_Gameplay__get_LocalPC);
    return fnLocalPC();
}

// The pass-through hook. Installed at boot per the "always hooked" request, but
// it deliberately does NOT alter the return value: iOS consumes the field, not
// this return. Hooking the field would be wrong; the field is the real state.
typedef float (*AssitSpeedFn)(void *self,
                             Styxi_Vector3 assistCentorPos,
                             float assistDis,
                             float dis,
                             float angle,
                             bool isPVE,
                             bool gamepadInput);

static AssitSpeedFn g_origAssitSpeed = NULL;
static BOOL g_aimHookInstalled = NO;

static float Hooked_AssitSpeed(void *self,
                               Styxi_Vector3 assistCentorPos,
                               float assistDis,
                               float dis,
                               float angle,
                               bool isPVE,
                               bool gamepadInput) {
    return g_origAssitSpeed
         ? g_origAssitSpeed(self, assistCentorPos, assistDis, dis, angle, isPVE, gamepadInput)
         : 0.0f;
}

void StyxInstallAimHook(void) {
    if (g_aimHookInstalled) return;

    void *target = (void *)(StyxBase() + IOS_PC__GetAssitAimSpeed);
    // PC-relative form: anogs screens for the Substrate literal-jump prologue
    // (0x58000050) by dlopen/dlsym/ldr of a resolved symbol, so we avoid
    // emitting that byte pattern into the game binary.
    int rc = StyxHookFunctionRel(target, (void *)Hooked_AssitSpeed, (void **)&g_origAssitSpeed);
    if (rc == 0) {
        g_aimHookInstalled = YES;
        StyxAimStats.hookInstalled = YES;
        NSLog(@"[STYX] aim pass-through hook installed @ %p (PC-relative)", target);
    } else {
        NSLog(@"[STYX] aim pass-through hook FAILED rc=%d @ %p", rc, target);
    }

    // Warm the controller accessor so the first tick does not race.
    StyxResolveLocalPC();
}

// One pass: resolve the controller, then write or restore the two fields.
void StyxAimApplyNow(void) {
    void *pc = StyxResolveLocalPC();
    uintptr_t p = (uintptr_t)pc;

    if (p < 0x1000 || p >= 0x7FFFFFFFFFFFULL) {
        StyxAimStats.haveController = NO;
        return;
    }
    StyxAimStats.haveController = YES;

    float *live = (float *)(p + IOS_PC__m_AimAssistanceSpeed);      // 0x1C8
    float *init = (float *)(p + IOS_PC__m_AimAssistanceSpeedInit);  // 0x1D0

    // Capture the game's own value the first time we see a controller so we can
    // restore it exactly when the feature is switched off.
    if (!StyxAimStats.captured) {
        StyxAimStats.originalValue = *live;
        StyxAimStats.captured = YES;
        NSLog(@"[STYX] aim assist original speed captured: %.3f", StyxAimStats.originalValue);
    }

    if (StyxCfg.aimOn) {
        float v = StyxCfg.aimStrength;
        if (v < 0.0f) v = 0.0f;
        if (v > 100.0f) v = 100.0f;
        *live = v;
        *init = v;              // survive ReloadInitAimAssistanceSpeed
        StyxAimStats.writtenValue = v;
        StyxAimStats.writes++;
        StyxAimStats.writing = YES;
    } else if (StyxAimStats.writing) {
        // Put the game back the way we found it.
        *live = StyxAimStats.originalValue;
        *init = StyxAimStats.originalValue;
        StyxAimStats.writing = NO;
        StyxAimStats.restoreCount++;
    }
}

static void StyxAimTick(void) {
    StyxAimApplyNow();
}

// Repeating writer on the main queue.
static dispatch_source_t g_aimTimer = NULL;

void StyxAimStart(void) {
    if (g_aimTimer) return;
    dispatch_queue_t q = dispatch_get_main_queue();
    g_aimTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, q);
    uint64_t iv = (uint64_t)(STYX_AIM_TICK_SEC * NSEC_PER_SEC);
    dispatch_source_set_timer(g_aimTimer,
                              dispatch_time(DISPATCH_TIME_NOW, (int64_t)iv),
                              iv,
                              iv / 10);
    dispatch_source_set_event_handler(g_aimTimer, ^{ StyxAimTick(); });
    dispatch_resume(g_aimTimer);
    NSLog(@"[STYX] aim field writer started (%.0f Hz)",
          1.0 / STYX_AIM_TICK_SEC);
}