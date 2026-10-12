#!/usr/bin/env python3
"""
STYX-iOS — IPA injection tool (LIEF 0.17.x, runs on Windows)

Replicates the loader chain proven by the CLOUD v1.0 mod:

    codm  (main exe; LC_RPATH contains @executable_path/Frameworks)
      -> APMDeviceInfoSupport_dylib            (Tencent APM framework)
           -> @rpath/Cloud.framework/Cloud     (our dylib)

Instead of extracting the whole ~2.7 GB IPA, this streams the archive and
substitutes only the three entries we care about. Every untouched entry keeps
its original external_attr (POSIX mode bits) and compress_type, which matters:
the main executable is stored as mode 0755 and iOS will not launch an app whose
executable loses its execute bit.

Usage:
    python inject.py <stock.ipa> <StyxMenu.dylib> <out.ipa>
"""
import os
import shutil
import sys
import tempfile
import zipfile

import lief

RPATH = "@rpath/Cloud.framework/Cloud"
APM_REL = ("Payload/codm.app/Frameworks/"
           "APMDeviceInfoSupport_dylib.framework/APMDeviceInfoSupport_dylib")
CLOUD_DIR_REL = "Payload/codm.app/Frameworks/Cloud.framework"
CLOUD_BIN_REL = CLOUD_DIR_REL + "/Cloud"
CLOUD_PLIST_REL = CLOUD_DIR_REL + "/Info.plist"

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

MODE_FILE_EXEC = 0o100755 << 16
MODE_FILE = 0o100644 << 16
MODE_DIR = (0o040755 << 16) | 0x10


def log(msg):
    print("[inject] " + msg, flush=True)


# LIEF 0.17 moved these out of Binary; keep one place to reference them.
LC_ID_DYLIB = lief.MachO.LoadCommand.TYPE.ID_DYLIB
LC_LOAD_DYLIB = lief.MachO.LoadCommand.TYPE.LOAD_DYLIB


def load_macho(path):
    """Parse a Mach-O (thin or fat) and return the first thin Binary."""
    parsed = lief.MachO.parse(path)
    if parsed is None:
        raise RuntimeError("LIEF could not parse " + path)
    # LIEF 0.17 returns a FatBinary even for a thin file.
    if isinstance(parsed, lief.MachO.FatBinary):
        return parsed.at(0)
    return parsed


def dylib_commands(binary, kind):
    """All DylibCommands of the given LoadCommand kind."""
    return [c for c in binary.commands
            if isinstance(c, lief.MachO.DylibCommand) and c.command == kind]


def build_cloud_binary(dylib_path, workdir):
    """Return our dylib with LC_ID_DYLIB rewritten to the @rpath install name."""
    src = os.path.join(workdir, "StyxMenu.in.dylib")
    out = os.path.join(workdir, "Cloud.out.dylib")
    shutil.copyfile(dylib_path, src)

    b = load_macho(src)
    ids = dylib_commands(b, LC_ID_DYLIB)
    if not ids:
        raise RuntimeError("no LC_ID_DYLIB in " + dylib_path)
    log("Cloud LC_ID_DYLIB: %r -> %r" % (str(ids[0].name), RPATH))
    ids[0].name = RPATH

    # The edit invalidates the signature; the IPA re-sign pass replaces it.
    b.remove_signature()
    b.write(out)

    check = load_macho(out)
    now = [str(c.name) for c in dylib_commands(check, LC_ID_DYLIB)]
    if now != [RPATH]:
        raise RuntimeError("LC_ID_DYLIB rewrite failed, got " + repr(now))
    if int(check.header.file_type) != 6:
        raise RuntimeError("Cloud is not an MH_DYLIB after rewrite")
    with open(out, "rb") as f:
        return f.read()


def build_apm(ipa_path, workdir):
    """Return APMDeviceInfoSupport_dylib with LC_LOAD_DYLIB @rpath/... added."""
    src = os.path.join(workdir, "APM.in")
    out = os.path.join(workdir, "APM.out")
    with zipfile.ZipFile(ipa_path, "r") as z:
        raw = z.read(APM_REL)
    with open(src, "wb") as f:
        f.write(raw)

    b = load_macho(src)
    before = [str(c.name) for c in dylib_commands(b, LC_LOAD_DYLIB)]
    if any(RPATH in n for n in before):
        raise RuntimeError("APM already references " + RPATH + "; refusing to double-patch")
    log("APM deps before: %d" % len(before))

    b.remove_signature()
    if not b.add_library(RPATH):
        raise RuntimeError("LIEF failed to add LC_LOAD_DYLIB")
    b.write(out)

    check = load_macho(out)
    after = [str(c.name) for c in dylib_commands(check, LC_LOAD_DYLIB)]
    if RPATH not in after:
        raise RuntimeError("LC_LOAD_DYLIB add did not stick")
    log("APM deps after : %d (added %s)" % (len(after), RPATH))

    with open(out, "rb") as f:
        return f.read()


def new_entry(name, data, mode):
    zi = zipfile.ZipInfo(name, date_time=(2024, 1, 1, 0, 0, 0))
    zi.external_attr = mode
    zi.create_system = 3  # Unix, so the mode bits above are honoured
    zi.compress_type = zipfile.ZIP_DEFLATED
    return zi, data


def rewrite_zip(src_ipa, dst_ipa, replacements):
    """Stream src -> dst, substituting and adding the given entries."""
    pending = dict(replacements)
    copied = replaced = added = 0
    with zipfile.ZipFile(src_ipa, "r") as zin, \
            zipfile.ZipFile(dst_ipa, "w", allowZip64=True) as zout:
        for item in zin.infolist():
            data = pending.pop(item.filename, None)
            if data is not None:
                zi = zipfile.ZipInfo(item.filename, date_time=item.date_time)
                zi.external_attr = item.external_attr
                zi.compress_type = item.compress_type
                zi.create_system = item.create_system
                zout.writestr(zi, data)
                replaced += 1
                continue
            if item.is_dir():
                zout.writestr(item, b"")
                copied += 1
                continue
            with zin.open(item, "r") as fsrc, zout.open(item, "w") as fdst:
                shutil.copyfileobj(fsrc, fdst, 1024 * 1024)
            copied += 1
        for name, (zi, data) in pending.items():
            zout.writestr(zi, data)
            added += 1
            log("added entry: " + name)
    log("entries: copied=%d replaced=%d added=%d" % (copied, replaced, added))


def verify(out_ipa):
    with zipfile.ZipFile(out_ipa, "r") as z:
        names = set(z.namelist())
        for req in (APM_REL, CLOUD_BIN_REL, CLOUD_PLIST_REL):
            if req not in names:
                raise RuntimeError("missing from output IPA: " + req)
        apm = z.read(APM_REL)
        cloud = z.read(CLOUD_BIN_REL)

    tmp = tempfile.mkdtemp()
    try:
        apm_p = os.path.join(tmp, "apm")
        with open(apm_p, "wb") as f:
            f.write(apm)
        b = load_macho(apm_p)
        deps = [str(c.name) for c in dylib_commands(b, LC_LOAD_DYLIB)]
        if RPATH not in deps:
            raise RuntimeError("APM in output does not load " + RPATH)
        log("verified APM loads: " + RPATH)

        cloud_p = os.path.join(tmp, "Cloud")
        with open(cloud_p, "wb") as f:
            f.write(cloud)
        c = load_macho(cloud_p)
        if int(c.header.file_type) != 6:
            raise RuntimeError("Cloud is not MH_DYLIB")
        if str(dylib_commands(c, LC_ID_DYLIB)[0].name) != RPATH:
            raise RuntimeError("Cloud LC_ID_DYLIB wrong")
        log("verified Cloud: MH_DYLIB, install name %s, %d bytes"
            % (RPATH, len(cloud)))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main():
    if len(sys.argv) != 4:
        print(__doc__)
        sys.exit(1)

    stock_ipa, dylib_path, out_ipa = sys.argv[1], sys.argv[2], sys.argv[3]

    for p in (stock_ipa, dylib_path):
        if not os.path.exists(p):
            log("ERROR: not found: " + p)
            sys.exit(1)

    workdir = tempfile.mkdtemp(prefix="styx_inject_")
    try:
        log("stock : " + stock_ipa)
        log("dylib : " + dylib_path)

        with zipfile.ZipFile(stock_ipa, "r") as z:
            if APM_REL not in z.namelist():
                log("ERROR: " + APM_REL + " not present in stock IPA")
                sys.exit(1)

        cloud = build_cloud_binary(dylib_path, workdir)
        apm = build_apm(stock_ipa, workdir)

        repl = {
            APM_REL: apm,
            CLOUD_DIR_REL + "/": new_entry(CLOUD_DIR_REL + "/", b"", MODE_DIR),
            CLOUD_BIN_REL: new_entry(CLOUD_BIN_REL, cloud, MODE_FILE_EXEC),
            CLOUD_PLIST_REL: new_entry(CLOUD_PLIST_REL,
                                       CLOUD_INFO_PLIST.encode("utf-8"), MODE_FILE),
        }

        if os.path.exists(out_ipa):
            os.remove(out_ipa)
        rewrite_zip(stock_ipa, out_ipa, repl)
        verify(out_ipa)

        log("DONE: " + out_ipa + " (%.2f GB)"
            % (os.path.getsize(out_ipa) / (1024 ** 3)))
        log("NOTE: the IPA is still signed with the ORIGINAL signature.")
        log("      Re-sign it (ldid / ESign / SideStore) before installing.")
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


if __name__ == "__main__":
    main()
