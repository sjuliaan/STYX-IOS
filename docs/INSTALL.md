# STYX-iOS — Install Guide

CODM Garena **1.6.58** (build 5940), arm64, **no jailbreak required**.

## What you need

| Item | Notes |
|---|---|
| iPhone on iOS 15–17.x | 17.6.1 confirmed working path |
| Stock 1.6.58 IPA | `com.garena.game.codm_1.6.58_und3fined 2.ipa` (decrypted) |
| `StyxMenu.dylib` | CI artifact (see below) |
| Free Apple ID | for signing; 7-day refresh cycle |
| Sideloadly **or** ESign **or** SideStore | pick one (see §3) |

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

## 3. Sign & install

**Do not sign the IPA by hand.** On a non-jailbroken device iOS rejects an
ad-hoc (`ldid`) signature; what is needed is a provisioning profile, which only
a tool holding your Apple ID can obtain. The IPA from step 2 is intentionally
left unsigned so any sideload tool can re-sign every Mach-O in the bundle —
including our patched `APMDeviceInfoSupport_dylib` and added `Cloud.framework`.

Pick one:

- **Sideloadly** (easiest, Windows). Download → enter Apple ID → plug in the
  iPhone and pick it → choose the IPA → **Start**. Over USB; fastest option.
- **ESign** (on-device). Install ESign, open the IPA from Files, sign with your
  Apple ID, install.
- **SideStore** (best long-term, auto-refresh). Install and pair with your PC,
  then **My Apps → +** → pick the IPA. Refreshes before the 7-day expiry, but
  the WireGuard pairing setup is the fiddliest of the three.

After installing, **trust the profile**: Settings → General → VPN & Device
Management → your Apple ID → Trust. Then launch CODM.

## 4. Use the mod

- A floating **"S"** button appears over the game. Drag it anywhere.
- Tap it to open the panel.
- **ESP** → Box / Distance / Health
- **Aim Assist** → on/off + **Strength** slider (1–20). This amplifies the
  game's own aim assist; it does not write aim rotations itself.
- **Anti-Cheat** → the anogs (Tencent TSS) bypass on/off, plus a live line
  showing how many pointers were hooked and how many probes were blocked.
  If it reads "not loaded / not hooked", the bypass did not find the
  framework.

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
