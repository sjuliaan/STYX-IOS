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

// ---- PlayerController: native aim assist (the amplifier target) ----
#define IOS_PC__GetAssitAimSpeed          0x26753E4  // virtual Slot 80
#define IOS_PC__get_AimAssistanceSpeed    0x2663D9C  // virtual Slot 45
#define IOS_PC__CalcAssistAim             0x26691C8
#define IOS_PC__get_CurrentAssistAimTarget 0x26751A8

// ---- Pawn fields (dump + disasm verified) ----
#define IOS_Pawn__m_HeadBone              0x308
#define IOS_Pawn__m_IsAlive               0x548
#define IOS_Pawn__m_IsBot                 0x5B9
#define IOS_Pawn__m_PlayerInfo            0x5C0
#define IOS_Pawn__m_Mesh                  0x628
#define IOS_Pawn__m_LastPawnPosDirect     0x5C8   // inline Vector3 (x,y,z)

// AttackableTargetInfo is an EMBEDDED struct at Pawn+0x78 on iOS.
// (Android derefs it as a pointer — do NOT copy that pattern here.)
#define IOS_AT__m_AttackableInfo          0x78
#define IOS_ATI__m_Health                 0x34
#define IOS_ATI__m_MaxHealth              0x38
// Convenience: absolute offsets from the Pawn
#define IOS_Pawn__m_Health                (IOS_AT__m_AttackableInfo + IOS_ATI__m_Health)     // 0xAC
#define IOS_Pawn__m_MaxHealth             (IOS_AT__m_AttackableInfo + IOS_ATI__m_MaxHealth)  // 0xB0

#define IOS_PlayerInfo__m_NickName        0x160
#define IOS_BaseGame__EnemyPawns          0x178