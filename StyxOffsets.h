// ============================================================================
// STYX-iOS — verified offsets, CODM Garena 1.6.58 (build 5940), arm64 Mach-O
// Source: Rodroid dump of the decrypted 1.6.58 `codm` + global-metadata.dat
// Fields disasm-verified where noted; see docs/VERIFICATION.md
// ============================================================================
#pragma once
#include <stdint.h>
#include <mach-o/dyld.h>

// Main executable is a static Mach-O mapped at 0x100000000.
static inline uintptr_t StyxBase(void) {
    return (uintptr_t)_dyld_get_image_header(0);
}

#define IOS_BASE StyxBase()

// ---- Unity engine exports ----
#define IOS_Camera__get_main              0x8A66D44
#define IOS_Camera__WorldToScreenPoint    0x8A667E4
#define IOS_Component__get_transform      0x8A6CD94
#define IOS_Transform__get_position       0x8AC72C4
#define IOS_Time__get_timeScale           0x8A629B0
#define IOS_Time__set_timeScale           0x8AEDB04
#define IOS_Screen__get_width             0x8A94EEC
#define IOS_Screen__get_height            0x8A94F60

// ---- Gameplay singletons (class is GamePlay on iOS) ----
#define IOS_Gameplay__get_MatchGame       0x23979D4
#define IOS_Gameplay__get_LocalPawn       0x2398AC8
// static, zero-arg: returns the live GameEngine_PlayerController instance.
// Verified by disassembly -- it never reads its incoming x0.
#define IOS_Gameplay__get_LocalPC         0x2398960

// ---- PlayerController: native aim assist ----
//
// IMPORTANT (verified against the 1.6.58 binary, not guessed):
//
// The Android mod hooks GetAssitAimSpeed and returns a bigger number. That
// does NOT work on iOS. On iOS the assist magnitude is a plain FLOAT FIELD that
// the game reads directly, and GetAssitAimSpeed's *return value* is not the
// number the assist math consumes -- it has zero direct BL call sites and is
// reached only through the vtable.
//
// The real path, from disassembly:
//
//   0x2663D9C  get_AimAssistanceSpeed      ldr s0, [x0, #0x1C8] ; ret
//   0x2663DAC  OverrideAimAssistanceSpeed  str s8, [x19, #0x1C8]
//   0x2663E10  ReloadInitAimAssistanceSpeed
//                                       ldr s0,[x19,#0x1D0]
//                                       str s0,[x19,#0x1C8]
//   0x2665E04  (config apply)          ldr s0,[x20,#0x14]
//                                       str s0,[x19,#0x1C8]
//                                       str s0,[x19,#0x1D0]
//   0x2665EA4  (consumption)           ldr s8,[x19,#0x1C8] ; str s8,[x20,#0x14]
//
// So: 0x1C8 is the LIVE value, 0x1D0 is the "initial" value that reload copies
// back into 0x1C8. Writing only 0x1C8 gets clobbered on every reload, so we
// must write BOTH.
#define IOS_PC__GetAssitAimSpeed          0x26753E4  // virtual, vtable-dispatched
#define IOS_PC__get_AimAssistanceSpeed    0x2663D9C
#define IOS_PC__get_CurrentAssistAimTarget 0x26751A8

// PlayerController instance fields (float).
#define IOS_PC__m_AimAssistanceSpeed      0x1C8   // live assist speed
#define IOS_PC__m_AimAssistanceSpeedInit  0x1D0   // reload source for 0x1C8

// ---- Pawn fields (dump + disasm verified) ----
#define IOS_Pawn__m_HeadBone              0x308
#define IOS_Pawn__m_IsAlive               0x548
#define IOS_Pawn__m_IsBot                 0x5B9
#define IOS_Pawn__m_PlayerInfo            0x5C0
#define IOS_Pawn__m_Mesh                  0x628
#define IOS_Pawn__m_LastPawnPos           0x5C8   // inline Vector3 (x,y,z)
                                       // (dump field name is m_LastPawnPos; there
                                       //  is no "m_LastPawnPosDirect" in 1.6.58)

// AttackableTargetInfo is an EMBEDDED struct at Pawn+0x78 on iOS.
// (Android derefs it as a pointer — do NOT copy that pattern here.)
#define IOS_AT__m_AttackableInfo          0x78
#define IOS_ATI__m_Health                 0x34
#define IOS_ATI__m_MaxHealth              0x38
// Convenience: absolute offsets from the Pawn
#define IOS_Pawn__m_Health                (IOS_AT__m_AttackableInfo + IOS_ATI__m_Health)     // 0xAC
#define IOS_Pawn__m_MaxHealth             (IOS_AT__m_AttackableInfo + IOS_ATI__m_MaxHealth)  // 0xB0

// NOTE: PlayerInfo.m_NickName is intentionally absent. The 1.6.58 dump reports
// it as the unresolved sentinel 0x7FFFFFFF, and no such field exists on
// PlayerInfo or its base (AttackableTargetInfo), so any read would be garbage.
// ESP therefore draws no names; bots are distinguished by box colour.

#define IOS_BaseGame__EnemyPawns          0x178