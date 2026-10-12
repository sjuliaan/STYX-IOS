// ============================================================================
// STYX-iOS — CODM Garena 1.6.58 (build 5940) offset table, arm64 Mach-O
// Source: Rodroid dump of decrypted 1.6.58 `codm` + global-metadata.dat
//   methods: class-confirmed RVAs from dump.cs (see tools/ios_offset_table.py)
//   fields : carried from Android 1.6.57 dump, declaration ORDER validated
//            identical iOS-vs-Android (Pawn 1314/1314, PlayerInfo 316/316,
//            BaseGame 109/109, AttackableTarget 22/22, ATInfo 17/17)
// Address math (static Mach-O main executable):
//   runtime = (uintptr_t)_dyld_get_image_header(0) + FILE_OFFSET
//   (file offset = RVA - 0x100000000; all targets verified inside __TEXT)
// Legend: [OK] dump-resolved | [VERIFY] confirm in IDA before shipping
// ============================================================================
#pragma once
#include <cstdint>
#include <mach-o/dyld.h>

inline uintptr_t StyxiOSBase() {
    return (uintptr_t)_dyld_get_image_header(0);
}
// NOTE: m_unity equivalent = StyxiOSBase(); add FILE offsets below.

// ---------------------------------------------------------------------------
// ESP + aimbot core — methods [OK]
// ---------------------------------------------------------------------------
// --- Unity engine exports ---
#define IOS_Camera__get_main              0x8A66D44
#define IOS_Camera__WorldToScreenPoint    0x8A667E4   // (Vector3)->Vector3 overload
#define IOS_Component__get_transform      0x8A6CD94
#define IOS_Transform__get_position       0x8AC72C4
#define IOS_Transform__set_position       0x8A62908
#define IOS_Transform__set_localPosition  0x8AC5DA0
#define IOS_Transform__set_localScale     0x8AEF3B4
#define IOS_Input__get_touchCount         0x8A9D358
#define IOS_Input__GetTouch               0x8A9D36C
#define IOS_Input__get_mousePosition      0x8A9CC70
#define IOS_Input__get_touchSupported     0x8A9D474
#define IOS_Screen__get_width             0x8A94EEC
#define IOS_Screen__get_height            0x8A94F60
#define IOS_Screen__get_dpi               0x8AD3F48
#define IOS_Time__get_timeScale           0x8A629B0
#define IOS_Time__set_timeScale           0x8AEDB04
#define IOS_GameObject__SetActive         0x8A7AEC4
#define IOS_Object__get_name              0x8A97B34   // UnityEngine.Object (TypeDefIndex 1685)
// --- Gameplay singletons (note: class is GamePlay, capital P, on iOS) ---
#define IOS_Gameplay__get_MatchGame       0x23979D4
#define IOS_Gameplay__get_LocalPawn       0x2398AC8
// --- Pawn ---
#define IOS_Pawn__get_IsFiring            0x1863CB8
#define IOS_Pawn__set_AimRotation         0x186F3B0   // virtual, Quaternion
#define IOS_Pawn__IsAiming                0x1856AC8
#define IOS_Pawn__get_CurrentWeapon       0x1846B64
#define IOS_Pawn__get_LastPawnPos         0x18741B0
#define IOS_Pawn__get_HeadPosition        0x1873B28   // virtual
#define IOS_Pawn__get_PlayerName          0x1874048   // virtual, returns C# string
#define IOS_Pawn__get_TeamSeatId          0x1873E44
#define IOS_Pawn__StopFire                0x191DA20   // virtual base (Pkg: verify vs overrides)
#define IOS_Pawn__TryChangeClip           0x191F4F0   // virtual base
// --- Weapon / vehicle ---
#define IOS_Weapon__GetWeaponId           0x1E1A268
#define IOS_Weapon__get_CarriedAmmoCount  0x1DECB44
#define IOS_PhysicsVehicle__get_Health    0x25BE22C   // [VERIFY] override in PhysicsVehicle
// --- MatchGame ---
#define IOS_MatchGame__get_DroppedPickUpMgr 0x16F68F0 // (unused in MVP)

// ---------------------------------------------------------------------------
// Port-feature hooks — methods [OK] address / [VERIFY] semantics
// ---------------------------------------------------------------------------
#define IOS_BRProfessionChipConfig__ctor    0x79759D8
#define IOS_BRProfessionChipConfig__getName 0x7976578  // get_Name (instance)
#define IOS_WeaponProjectile__Tick          0x29A79CC  // override in class
// NOTE: WeaponProjectile has NO Position getter on iOS — read fields instead:
//   m_TartgetPosition 0xF4 / m_SourcePosition 0x100 (REAL iOS offsets from dump)
#define IOS_Spectate__ProcessForDelay     0x1851190   // ObserverDelayManager (byte[] sig ✓)
#define IOS_Spectate__NeedDelayProcess    0x18510E8   // returns int (hook: return 0)
#define IOS_Water__GetCurrentDistToWaterSurface 0x188E83C // returns float (sig differs from Android!)
#define IOS_Water__IsUnderWaterSurface    0x18ABB50   // takes float distance
#define IOS_Water__get_CurrentWaterSurfaceHeight 0x186E83C // returns float
#define IOS_POV__GetMainCameraFov_3p      0x2433B10   // InputSettingWestConfig
#define IOS_Grass__SetGrassShowState      0x7FEBBCC   // EnvironmentSwitch (static)
#define IOS_Grass__SetGrassLODBias        0x473317C   // BRTowerGameUIScene (static)
#define IOS_Unlock__IsUnlocked            0x2F0AD1C   // [VERIFY] BlueprintWeaponInfo — confirm blueprint semantics
#define IOS_Unlock__IsWeaponAttachmentUnlock 0x1F6EE2C // [VERIFY] WeaponPromotionAgent — confirm semantics

// ---------------------------------------------------------------------------
// Fields — proof levels: [OK] = disasm-proven or real dump offset;
// [CARRY] = order-identical carry-over from Android 1.6.57 (IDA-optional).
// Disasm proofs: NickName ldr #0x160 (via 0x26E5AA8); IsAlive ldrb #0x548
// (0x1873020); IsBot ldrb #0x5B9; HeadBone ldr #0x308 x3; PlayerInfo ldr
// #0x5C0 x2; AttackableInfo ldr #0x78 x2; EnemyPawns ldr #0x178 x2;
// LastPawnPos inline Vector3 at Pawn+0x5C8 (leaf, no hook needed).
// ---------------------------------------------------------------------------
#define IOS_Pawn__m_HeadBone              0x308   // [OK]
#define IOS_Pawn__m_IsAlive               0x548   // [OK]
#define IOS_Pawn__m_IsBot                 0x5B9   // [OK]
#define IOS_Pawn__m_PlayerInfo            0x5C0   // [OK]
#define IOS_Pawn__m_Mesh                  0x628   // [OK] real iOS dump offset
#define IOS_Pawn__m_LastPawnPosDirect     0x5C8   // [OK] inline Vector3 (S0-S2), hook-free
#define IOS_Pawn__get_IsAlive             0x1873020 // [OK] bool leaf (hook-free alive check)
#define IOS_PlayerInfo__m_NickName        0x160   // [OK]
#define IOS_PlayerInfo__m_ProfessionChipID   0x1E8   // [CARRY]
#define IOS_PlayerInfo__m_PreProfessionChipID 0xC4   // [CARRY]
#define IOS_PlayerInfo__m_ChipSkinID      0x3F0   // [CARRY]
#define IOS_BRProfessionChipConfig__m_ItemID 0x24 // [CARRY]
#define IOS_AttackableTarget__m_AttackableInfo 0x78  // [OK]
#define IOS_AttackableTargetInfo__m_Health     0x34  // [CARRY]
#define IOS_AttackableTargetInfo__m_MaxHealth  0x38  // [CARRY]
#define IOS_BaseGame__EnemyPawns          0x178   // [OK]
#define IOS_BaseGame__m_AllVehicles       0x1A0   // [CARRY]
#define IOS_PhysicsVehicle__vehicleType   0x164   // [CARRY] layout not order-checked
#define IOS_WeaponProjectile__m_TargetPos 0xF4    // [OK] real iOS offset (m_TartgetPosition sic)
#define IOS_WeaponProjectile__m_SourcePos 0x100   // [OK] real iOS offset
// Skeleton bone-map chain (Pawn+0xA8 ...) — [VERIFY] iOS Pawn bone layout in IDA
// (CLOUD 1.6.57 mod may reveal equivalents; compare during IDA pass)
