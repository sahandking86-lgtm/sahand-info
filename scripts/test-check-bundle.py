#!/usr/bin/env python3
"""Self-test for scripts/check-bundle.py.

    python3 scripts/test-check-bundle.py

The whole reason CI can say "the package is fine, look on the device" is this checker, so the
checker needs its own tests: a verifier that silently passes everything is worse than none. Each
case builds a synthetic bundle in a temp dir - real Info.plist, real Mach-O headers - and asserts
the exit status. Synthetic Mach-O files are just headers: the parser only reads the magic and the
cputype, which is exactly what a real one would put there.
"""

import os
import plistlib
import shutil
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
CHECK = os.path.join(HERE, "check-bundle.py")
ARM64, ARMV7, X86_64 = 0x0100000C, 12, 0x01000007

GOOD = {
    "CFBundleExecutable": "Sahand Info",
    "CFBundleIdentifier": "com.sahandinfo.notes",
    "CFBundleName": "Sahand Info",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": "2.1",
    "CFBundleVersion": "1",
    "LSRequiresIPhoneOS": True,
    "UIDeviceFamily": [1],
    "UILaunchScreen": {},
    "CFBundleIcons": {"CFBundlePrimaryIcon": {"CFBundleIconName": "AppIcon"}},
    "CFBundleDisplayName": "Sahand Info",
}


def macho(cpus, fat=False):
    """A Mach-O header (plus padding) for the given (cputype, cpusubtype) list."""
    def header(cpu, sub):
        return struct.pack("<IIIIII", 0xFEEDFACF, cpu, sub, 2, 0, 0) + b"\0" * 8
    if not fat:
        return header(*cpus[0]) + b"\0" * 4096
    entries, body, offset = b"", b"", 32 + 20 * len(cpus)
    for cpu, sub in cpus:
        head = header(cpu, sub)
        entries += struct.pack(">IIIII", cpu, sub, offset, len(head) + 2048, 14)
        body += head + b"\0" * 2048
        offset += len(head) + 2048
    return struct.pack(">II", 0xCAFEBABE, len(cpus)) + entries + body


def bundle(root, info, binary):
    app = os.path.join(root, "Sahand Info.app")
    os.makedirs(app)
    if info is not None:
        with open(os.path.join(app, "Info.plist"), "wb") as fh:
            plistlib.dump(info, fh, fmt=plistlib.FMT_XML)
    if binary is not None:
        # Always the canonical name, so a plist pointing elsewhere really has no matching file.
        with open(os.path.join(app, GOOD["CFBundleExecutable"]), "wb") as fh:
            fh.write(binary)
    for name in ("Assets.car", "PrivacyInfo.xcprivacy"):
        with open(os.path.join(app, name), "wb") as fh:
            fh.write(b"\0")
    return app


def run(app):
    proc = subprocess.run([sys.executable, CHECK, app], capture_output=True, text=True)
    return proc.returncode, (proc.stdout + proc.stderr).strip()


def main():
    good_bin = macho([(ARM64, 0)])
    cases = []

    def passing(label, info=None, binary=None):
        cases.append((label, True, info, binary))

    def failing(label, info=None, binary=None):
        cases.append((label, False, info, binary))

    passing("a normal bundle")
    passing("arm64e", binary=macho([(ARM64, 2)]))
    passing("fat arm64 + arm64e", binary=macho([(ARM64, 0), (ARM64, 2)], fat=True))
    failing("fat arm64 + x86_64 (simulator leftovers)", binary=macho([(ARM64, 0), (X86_64, 0)], fat=True))
    failing("x86_64 only", binary=macho([(X86_64, 0)]))
    failing("armv7 only (32-bit cannot run on modern iOS)", binary=macho([(ARMV7, 0)]))
    failing("not a Mach-O at all", binary=b"#!/bin/sh\necho hi\n" * 40)
    failing("shorter than a header", binary=b"\xcf\xfa\xed")
    failing("no Info.plist", info=None)
    failing("no CFBundleExecutable", binary=good_bin, info={k: v for k, v in GOOD.items() if k != "CFBundleExecutable"})
    failing("CFBundleExecutable with a path separator", binary=good_bin,
            info={**GOOD, "CFBundleExecutable": "../evil"})
    failing("CFBundleExecutable naming a missing file", binary=good_bin,
            info={**GOOD, "CFBundleExecutable": "WrongName"})
    failing("CFBundlePackageType not APPL", binary=good_bin, info={**GOOD, "CFBundlePackageType": "????"})
    failing("armv7-only device capability", binary=good_bin, info={**GOOD, "UIRequiredDeviceCapabilities": ["armv7"]})
    failing("CFBundleSupportedPlatforms is iPhoneSimulator", binary=good_bin,
            info={**GOOD, "CFBundleSupportedPlatforms": ["iPhoneSimulator"]})
    failing("UIDeviceFamily without iPhone", binary=good_bin, info={**GOOD, "UIDeviceFamily": [2]})
    failing("LSRequiresIPhoneOS false", binary=good_bin, info={**GOOD, "LSRequiresIPhoneOS": False})
    failing("empty CFBundleShortVersionString", binary=good_bin, info={**GOOD, "CFBundleShortVersionString": ""})
    # Reported, not enforced: a missing launch screen still launches, just letterboxed.
    passing("no UILaunchScreen (reported, not fatal)", binary=good_bin,
            info={k: v for k, v in GOOD.items() if k != "UILaunchScreen"})

    root = tempfile.mkdtemp(prefix="check-bundle-selftest-")
    failures = 0
    try:
        for index, (label, want_ok, info, binary) in enumerate(cases):
            case_dir = os.path.join(root, "case%02d" % index)
            os.makedirs(case_dir)
            app = bundle(case_dir, GOOD if info is None and label != "no Info.plist" else info,
                         good_bin if binary is None else binary)
            code, out = run(app)
            ok = (code == 0) == want_ok
            if not ok:
                failures += 1
            detail = out.splitlines()[0] if out else ""
            print("%s %-52s exit=%d %s" % ("ok  " if ok else "FAIL", label, code,
                                           "" if ok else "-> wanted %s, said: %s" % ("pass" if want_ok else "fail", detail[:120])))
        missing_code, missing_out = run(os.path.join(root, "does-not-exist.app"))
        if missing_code == 0:
            failures += 1
            print("FAIL a path that is not a bundle at all -> wanted a failure, got pass")
        else:
            print("ok   a path that is not a bundle at all")
    finally:
        shutil.rmtree(root, ignore_errors=True)

    total = len(cases) + 1
    print("\n%s (%d/%d cases behaved as expected)" % ("check-bundle.py self-test: PASS" if not failures
          else "check-bundle.py self-test: FAILED", total - failures, total))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
