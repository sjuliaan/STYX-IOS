# STYX-iOS

Mod menu + ESP + aim-assist amplifier for **Call of Duty: Mobile (Garena) 1.6.58**
on iOS, arm64, **no jailbreak required**.

> Companion to the Android mod in `../STYX_WORK`. Same feature philosophy,
> iOS-native implementation.

## Repository layout

This folder is the **source-only** repo. The reverse-engineering artifacts
(the Rodroid dump, the extracted IPA binaries, the framework folder) live in
the sibling `../STYX-iOS/` folder and are git-ignored — they are large and
copyrighted. Only the dylib source, the injector, and docs are tracked here.

## How it works

```
codm (main executable)
  └─ APMDeviceInfoSupport_dylib        (Tencent APM framework)
       └─ @rpath/Cloud.framework/Cloud (this dylib)
```

The loader chain is the same one the CLOUD v1.0 mod uses. We add a single
`LC_LOAD_DYLIB` to the APM framework and drop our dylib at
`Frameworks/Cloud.framework/Cloud`. No binary patching of the game itself.

## Features

| Feature | Implementation |
|---|---|
| **Mod menu** | UIKit overlay — floating draggable button, panel with `UISwitch` rows + slider |
| **ESP** | Box / Name / Distance / Health, drawn in a full-screen overlay view via CoreGraphics |
| **Aim assist** | Amplifies the game's *own* `GetAssitAimSpeed` (virtual slot 80) by returning the slider value. No external aim rotation writes — far less detectable. |

## Files

```
Makefile              Theos build (arm64, iOS 15+)
control               package metadata
StyxOffsets.h         verified iOS 1.6.58 offsets
StyxTypes.h          Vector3 / il2cpp layouts
StyxConfig.h/.mm      shared config struct
StyxHook.h            minimal ARM64 inline hook (vm_protect trampoline)
StyxAim.mm            aim-assist amplifier hook
StyxOverlay.mm        ESP renderer
StyxMenu.mm           menu UI
StyxMain.xm           dylib entry point (constructor)
tools/inject.py       LIEF IPA injector
docs/INSTALL.md       install walkthrough
.github/workflows/     CI: builds StyxMenu.dylib on macos-14
```

## Build

```bash
# locally (macOS + Theos)
make

# or via CI: push to GitHub, download the StyxMenu.dylib artifact
```

## Install

See `docs/INSTALL.md`. One-line version:

```powershell
python tools\inject.py stock.ipa StyxMenu.dylib out.ipa
# then sideload out.ipa with SideStore + a free Apple ID
```

## Offset provenance

All offsets in `StyxOffsets.h` come from a Rodroid dump of the decrypted
1.6.58 `codm` + `global-metadata.dat`, with field values either
disassembly-proven or carried from Android 1.6.57 where the field
declaration order was verified identical. See `StyxOffsets.h` comments for
the `[OK]` / `[CARRY]` markers.

## Roadmap

- [x] M1 — dylib builds, injects, menu appears
- [x] M2 — ESP renders
- [x] M3 — aim-assist amplifier
- [ ] M4 — anogs bypass (image hiding, debugger filter, dladdr masking)
- [ ] M5 — vehicle ESP, skeleton ESP, unlock hooks
