# STYX-iOS — Install Guide

CODM Garena **1.6.58** (build 5940), arm64, **no jailbreak required**.

## What you need

| Item | Notes |
|---|---|
| iPhone on iOS 15–17.x | 17.6.1 confirmed working path |
| Stock 1.6.58 IPA | `com.garena.game.codm_1.6.58_und3fined 2.ipa` (decrypted) |
| `StyxMenu.dylib` | CI artifact (see below) |
| Free Apple ID | for signing; 7-day refresh cycle |
| SideStore (or Sideloadly/ESign) | sideloading on Windows |

## 1. Build the dylib

Push the repo to GitHub, then either wait for the Actions run or trigger it
manually (**Actions → Build STYX-iOS → Run workflow**). Download the
`StyxMenu.dylib` artifact from the run.

## 2. Inject into the IPA

```powershell
pip install lief
python tools\inject.py "com.garena.game.codm_1.6.58_und3fined 2.ipa" StyxMenu.dylib "CODM-STYX-1.6.58.ipa"
```

This produces `CODM-STYX-1.6.58.ipa` — the installable mod IPA.

## 3. Install

1. Install **SideStore** on your iPhone and pair it with your PC (their guide:
   SideStore + WireGuard).
2. Connect the iPhone, open SideStore → **My Apps → +** → pick
   `CODM-STYX-1.6.58.ipa`.
3. Sign in with your **free Apple ID** when prompted.
4. Trust the developer profile: **Settings → General → VPN & Device Management**.
5. Launch CODM.

## 4. Use the mod

- A floating **"S"** button appears over the game. Drag it anywhere.
- Tap it to open the panel.
- **ESP** → Box / Name / Distance / Health
- **Aim Assist** → on/off + **Strength** slider (1–20). This amplifies the
  game's own aim assist; it does not write aim rotations itself.

## 5. Maintenance

- **Every 7 days** the free-Apple-ID signature expires. Re-open SideStore and
  re-install (or use AltStore/Sideloadly to refresh).
- If Garena forces a version update, the offsets in `StyxOffsets.h` must be
  re-taken against the new build. The menu/UI code carries over unchanged.

## Troubleshooting

| Symptom | Fix |
|---|---|
| App won't install | Re-trust the developer profile; re-sign |
| App crashes on launch | Check the dylib is the CI artifact, not a local build |
| Floating button never appears | The game UI wasn't ready at load; the menu retries every second — wait a few seconds after the lobby loads |
| ESP draws nothing | Make sure you're in a match (EnemyPawns is empty in the lobby) |
| Aim assist feels wrong | Lower the Strength slider; 1.0 ≈ stock behavior |
