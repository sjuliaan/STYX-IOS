// ============================================================================
// STYX-iOS — aim assist amplifier
//
// CODM ships its own aim assist (PlayerController::GetAssitAimSpeed,
// virtual slot 80). We do NOT write aim rotations ourselves; we hook the
// game's own assist-speed function and return the slider value. The game
// then performs the assist through its normal code path — same target
// selection, same smoothing — only faster. Far less detectable than an
// external aimbot, and 1:1 with the AimAssistSize hook in the Android mod.
//
// Signature (matches il2cpp codegen for
//   float GetAssitAimSpeed(Vector3 assistCentorPos, float assistDis,
//                          float dis, float angle, bool isPVE, bool gamepadInput) ):
//   float (this, Vector3, float, float, float, bool, bool)
// ============================================================================
#import <Foundation/Foundation.h>
#import "StyxConfig.h"
#import "StyxOffsets.h"
#import "StyxTypes.h"
#import "StyxHook.h"

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
    if (StyxCfg.aimOn && self != NULL) {
        float s = StyxCfg.aimStrength;
        if (s <= 0.0f) return 0.0001f;   // fully off -> snap assist
        if (s > 20.0f) s = 20.0f;
        return s;
    }
    if (!g_origAssitSpeed) return 1.0f;
    return g_origAssitSpeed(self, assistCentorPos, assistDis, dis, angle, isPVE, gamepadInput);
}

void StyxInstallAimHook(void) {
    if (g_aimHookInstalled) return;

    void *target = (void *)(StyxBase() + IOS_PC__GetAssitAimSpeed);
    int rc = StyxHookFunction(target, (void *)Hooked_AssitSpeed, (void **)&g_origAssitSpeed);
    if (rc == 0) {
        g_aimHookInstalled = YES;
        NSLog(@"[STYX] aim-assist amplifier installed @ %p", target);
    } else {
        NSLog(@"[STYX] aim-assist hook FAILED rc=%d @ %p", rc, target);
    }
}