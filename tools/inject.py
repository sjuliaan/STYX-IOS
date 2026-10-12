#!/usr/bin/env python3
"""
STYX-iOS — IPA injection tool (LIEF, runs on Windows)

Replicates the loader chain proven by the CLOUD v1.0 mod:
    codm (main exe)
      -> APMDeviceInfoSupport_dylib   (Tencent APM framework)
           -> @rpath/Cloud.framework/Cloud   (the mod dylib)

Steps:
  1. Extract the stock 1.6.58 IPA
  2. Rewrite our dylib's LC_ID_DYLIB to @rpath/Cloud.framework/Cloud
  3. Patch APMDeviceInfoSupport_dylib: strip sig, add LC_LOAD_DYLIB
  4. Drop our dylib into Frameworks/Cloud.framework/Cloud
  5. Re-zip as the installable mod IPA

Usage:
  python inject.py <stock.ipa> <StyxMenu.dylib> <out.ipa>
"""
import os
import shutil
import sys
import zipfile

import lief

RPATH = "@rpath/Cloud.framework/Cloud"
APM_REL = "Payload/codm.app/Frameworks/APMDeviceInfoSupport_dylib.framework/APMDeviceInfoSupport_dylib"
CLOUD_DIR_REL = "Payload/codm.app/Frameworks/Cloud.framework"
CLOUD_BIN_REL = CLOUD_DIR_REL + "/Cloud"

CLOUD_INFO_PLIST = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>Cloud</string>
    <key>CFBundleIdentifier</key><string>com.cloud.styx</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>Cloud</string>
    <key>CFBundlePackageType</key><string>FMWK</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>MinimumOSVersion</key><string>15.0</string>
</dict>
</plist>
"""


def log(msg):
    print(f"[inject] {msg}", flush=True)


def load_macho(path):
    """Parse a Mach-O (thin or fat) and return the first thin Binary."""
    parsed = lief.MachO.parse(path)
    if parsed is None:
        raise RuntimeError(f"LIEF could not parse {path}")
    if isinstance(parsed, lief.MachO.FatBinary):
        return parsed.at(0)
    return parsed


def fix_dylib_id(dylib_path):
    """Rewrite LC_ID_DYLIB so the loader can resolve @rpath/Cloud.framework/Cloud."""
    b = load_macho(dylib_path)
    cmd = b.dylib_command
    if cmd is None:
        log("WARNING: no LC_ID_DYLIB found in dylib; leaving as-is")
        return
    old = cmd.name
    cmd.name = RPATH
    b.write(dylib_path)
    log(f"dylib LC_ID_DYLIB: {old!r} -> {RPATH!r}")


def patch_apm(apm_path):
    """Add LC_LOAD_DYLIB @rpath/Cloud.framework/Cloud to the APM framework."""
    b = load_macho(apm_path)

    # Already patched?
    for lc in b.load_commands:
        if lc.command == lief.MachO.LoadCommand.TYPE.DYLIB:
            try:
                if RPATH in str(lc.name):
                    log("APM already patched, skipping")
                    return
            except Exception:
                pass

    b.remove_signature()
    b.add_library(RPATH)
    b.write(apm_path)
    log(f"APM patched: added LC_LOAD_DYLIB {RPATH}")


def extract_ipa(ipa_path, workdir):
    log(f"extracting {ipa_path} -> {workdir}")
    with zipfile.ZipFile(ipa_path, "r") as z:
        z.extractall(workdir)


def rezip(workdir, out_path):
    log(f"re-zipping -> {out_path}")
    if os.path.exists(out_path):
        os.remove(out_path)
    with zipfile.ZipFile(out_path, "w", zipfile.ZIP_DEFLATED) as z:
        for root, _dirs, files in os.walk(workdir):
            for f in files:
                full = os.path.join(root, f)
                rel = os.path.relpath(full, workdir)
                z.write(full, rel)


def main():
    if len(sys.argv) != 4:
        print(__doc__)
        sys.exit(1)

    stock_ipa, dylib_path, out_ipa = sys.argv[1], sys.argv[2], sys.argv[3]

    for p in (stock_ipa, dylib_path):
        if not os.path.exists(p):
            log(f"ERROR: not found: {p}")
            sys.exit(1)

    workdir = os.path.join(os.path.dirname(os.path.abspath(out_ipa)), "_styx_work")
    if os.path.isdir(workdir):
        shutil.rmtree(workdir)
    os.makedirs(workdir)

    try:
        extract_ipa(stock_ipa, workdir)

        # 1) fix our dylib's install name
        fix_dylib_id(dylib_path)

        # 2) patch the APM loader
        apm = os.path.join(workdir, APM_REL)
        if not os.path.exists(apm):
            log(f"ERROR: APM framework not found at {APM_REL}")
            sys.exit(1)
        patch_apm(apm)

        # 3) place the dylib as Cloud.framework/Cloud
        cloud_dir = os.path.join(workdir, CLOUD_DIR_REL)
        os.makedirs(cloud_dir, exist_ok=True)
        with open(os.path.join(cloud_dir, "Info.plist"), "w", encoding="utf-8") as f:
            f.write(CLOUD_INFO_PLIST)
        shutil.copyfile(dylib_path, os.path.join(cloud_dir, "Cloud"))
        log(f"placed dylib at {CLOUD_BIN_REL}")

        # 4) re-zip
        rezip(workdir, out_ipa)

        # 5) sanity check
        b = load_macho(os.path.join(workdir, APM_REL))
        names = []
        for lc in b.load_commands:
            if lc.command == lief.MachO.LoadCommand.TYPE.DYLIB:
                try:
                    names.append(str(lc.name))
                except Exception:
                    pass
        log(f"APM dylib commands now: {names}")
        log(f"DONE: {out_ipa}")
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


if __name__ == "__main__":
    main()
