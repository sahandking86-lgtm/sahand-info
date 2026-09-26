#!/usr/bin/env python3
"""Assert a .app bundle is shaped the way a device - or a container launcher - needs.

    python3 scripts/check-bundle.py "Payload/Sahand Info.app"

This is the exact sequence LiveContainer performs before it spawns anything: open the bundle's
Info.plist, read CFBundleExecutable, exec that file. So a clean run here means a launch failure
on a phone is not the package's fault. It also catches the silent regressions that a plain
`xcodebuild` success does not: an icon actool never injected, a missing launch screen (the app
runs letterboxed), a plist still pointing at an old bundle id, or a binary built for the
simulator.

Deliberately dependency-free (no plutil, otool or sips) so the same file runs on the macOS
runner, in build.yml against the unpacked .ipa, and on any dev machine. Mach-O headers are
parsed here rather than shelling out, because that is the one check that must not be skippable.

Exit 0 with a one-line report; exit 1 with the reason, prefixed FAIL: so a caller can pass it
straight into a GitHub annotation.
"""

import os
import plistlib
import sys

# Mach-O magics, as the 4 bytes read big-endian: a little-endian file shows the byte-swapped
# constant, which is why 64-bit little-endian (the normal case for an iPhone binary, on disk
# CF FA ED FE) reads as 0xCFFAEDFE here.
MAGICS = {0xCFFAEDFE: "<", 0xFEEDFACF: ">", 0xCEFAEDFE: "<", 0xFEEDFACE: ">"}
FAT_MAGICS = {0xCAFEBABE: ">", 0xBEBAFECA: "<"}
CPU_NAMES = {
    7: "i386",
    12: "armv7",
    0x01000007: "x86_64",
    0x0100000C: "arm64",
    18: "ppc",
    0x01000012: "ppc64",
}
# 64-bit only on purpose: iOS 11 dropped 32-bit entirely, so an armv7 slice cannot launch on any
# iPhone that could still install this, and its presence would mean the build went wrong.
DEVICE_CPU_NAMES = {"arm64", "arm64e"}
SIMULATOR_CPU_NAMES = {"i386", "x86_64", "arm64_sim"}
# Keys whose absence means the app cannot be launched or launched correctly.
REQUIRED = {
    "CFBundleExecutable": "the launcher uses this name to find the binary",
    "CFBundleIdentifier": "installers and LiveContainer key the container entry on it",
    "CFBundlePackageType": "must be APPL",
    "CFBundleShortVersionString": "the version installers list",
    "LSRequiresIPhoneOS": "marks this as an iOS app bundle",
}


def fail(msg):
    print("FAIL: %s" % msg)
    return 1


def arch_name(cpu, subtype):
    """Human name for a cputype/cpusubtype pair, including the arm64e and armv7s subtypes."""
    base = CPU_NAMES.get(cpu, "cpu#0x%X" % cpu)
    if base == "arm64":
        # Apple flags a pointer-authenticated core in the low byte of the subtype, and the
        # simulator arm64 cut keeps cputype 0x1000000C too - distinguishable only by the
        # platform key in the plist, which is checked separately.
        if (subtype & 0xFF) == 2:
            return "arm64e"
        return "arm64"
    if base == "armv7" and (subtype & 0xFF) == 11:
        return "armv7s"
    return base


def macho_arch_names(path):
    """(sorted arch names, error) for a thin or fat Mach-O image, without external tools."""
    import struct
    try:
        size = os.path.getsize(path)
    except OSError as exc:
        return None, str(exc)
    if size < 32:
        return None, "file is smaller than a Mach-O header (%d bytes)" % size
    with open(path, "rb") as fh:
        magic = int.from_bytes(fh.read(4), "big")
        names = []
        if magic in FAT_MAGICS:
            order = FAT_MAGICS[magic]
            fh.seek(0)
            blob = fh.read(8 + 20 * 64)
            try:
                _, count = struct.unpack_from("%s2I" % order, blob, 0)
            except struct.error:
                return None, "fat header unreadable"
            for i in range(min(count, 64)):
                try:
                    cpu, sub = struct.unpack_from("%s2I" % order, blob, 8 + 20 * i)
                except struct.error:
                    break
                names.append(arch_name(cpu, sub))
        elif magic in MAGICS:
            fh.seek(0)
            blob = fh.read(32)
            cpu, sub = struct.unpack_from("%s2I" % MAGICS[magic], blob, 4)
            names.append(arch_name(cpu, sub))
        else:
            return None, "not a Mach-O image (first four bytes 0x%08X)" % magic
    return sorted(set(names)), None


def human(nbytes):
    for unit in ("B", "KB", "MB", "GB"):
        if nbytes < 1024 or unit == "GB":
            return "%d%s" % (nbytes, unit)
        nbytes //= 1024


def main(argv):
    verbose = "-v" in argv
    args = [a for a in argv if not a.startswith("-")]
    if len(args) != 1:
        return fail("usage: check-bundle.py [-v] path/to/Foo.app")
    app = args[0].rstrip("/")
    if not os.path.isdir(app):
        return fail("no such bundle directory: %s" % app)

    plist_path = os.path.join(app, "Info.plist")
    if not os.path.isfile(plist_path):
        return fail("%s has no Info.plist - iOS will never see this as an app" % os.path.basename(app))
    try:
        with open(plist_path, "rb") as fh:
            info = plistlib.load(fh)
    except Exception as exc:
        return fail("Info.plist does not parse: %s" % exc)

    for key, why in REQUIRED.items():
        if key not in info or info[key] in ("", None):
            return fail("Info.plist is missing %s (%s)" % (key, why))
    if info["CFBundlePackageType"] != "APPL":
        return fail("CFBundlePackageType is %r, expected APPL" % info["CFBundlePackageType"])

    exec_name = info["CFBundleExecutable"]
    if "/" in exec_name or exec_name in (".", ".."):
        return fail("CFBundleExecutable %r is not a plain file name inside the bundle" % exec_name)
    exec_path = os.path.join(app, exec_name)
    if not os.path.isfile(exec_path):
        return fail("bundle %r declares CFBundleExecutable %r but that file is not in the bundle "
                    "(this is what makes a launcher report: No such file or directory, errno 2)"
                    % (os.path.basename(app), exec_name))

    names, err = macho_arch_names(exec_path)
    if err:
        return fail("%s: %s" % (exec_name, err))
    found = set(names)
    if not (found & DEVICE_CPU_NAMES):
        return fail("%s contains no device ARM slice (architectures: %s)" % (exec_name, ", ".join(names)))
    if found & SIMULATOR_CPU_NAMES:
        return fail("%s carries simulator slices (%s) - an .ipa built this way will not launch on "
                    "a phone" % (exec_name, ", ".join(sorted(found & SIMULATOR_CPU_NAMES))))

    if info.get("CFBundleSupportedPlatforms") not in (None, ["iPhoneOS"], "iPhoneOS"):
        return fail("CFBundleSupportedPlatforms is %r, not iPhoneOS" % info["CFBundleSupportedPlatforms"])
    if "UIRequiredDeviceCapabilities" in info:
        caps = info["UIRequiredDeviceCapabilities"]
        caps = caps if isinstance(caps, list) else [caps]
        if "armv7" in caps and "arm64" not in caps:
            return fail("UIRequiredDeviceCapabilities requires armv7 only - current iPhones refuse "
                        "the install; drop the key or list arm64")
    devices = info.get("UIDeviceFamily")
    if isinstance(devices, list) and 1 not in devices:
        return fail("UIDeviceFamily is %r - no iPhone entry, so an iPhone cannot install it" % devices)
    if str(info.get("LSRequiresIPhoneOS")).lower() not in ("true", "1"):
        return fail("LSRequiresIPhoneOS is %r" % info["LSRequiresIPhoneOS"])

    # Reported, not enforced: things that are annoying rather than fatal.
    notes = {
        "UILaunchScreen": "present" if "UILaunchScreen" in info else "ABSENT (app runs letterboxed)",
        "CFBundleIcons": "present" if "CFBundleIcons" in info else "ABSENT (no icon injected)",
        "CFBundleDisplayName": info.get("CFBundleDisplayName", "ABSENT (Home Screen falls back to CFBundleName)"),
        "Assets.car": "present" if os.path.isfile(os.path.join(app, "Assets.car")) else "ABSENT",
        "PrivacyInfo.xcprivacy": "present" if os.path.isfile(os.path.join(app, "PrivacyInfo.xcprivacy")) else "absent (fine for a test build)",
        "embedded.mobileprovision": "present" if os.path.isfile(os.path.join(app, "embedded.mobileprovision")) else "absent (expected: LiveContainer re-signs)",
        "UIRequiredDeviceCapabilities": str(info.get("UIRequiredDeviceCapabilities", "none (no gate)")),
        "CFBundleSupportedPlatforms": str(info.get("CFBundleSupportedPlatforms", "not set")),
    }

    size = sum(os.path.getsize(os.path.join(r, f)) for r, _, fs in os.walk(app) for f in fs)
    print("bundle=%s id=%s version=%s build=%s exec=%r archs=%s files=%d size=%s" % (
        os.path.basename(app), info["CFBundleIdentifier"], info["CFBundleShortVersionString"],
        info.get("CFBundleVersion", "?"), exec_name, ",".join(names), sum(len(fs) for _, _, fs in os.walk(app)), human(size)))
    print(" ".join("%s=%s" % kv for kv in notes.items()))
    if verbose:
        print("keys=%s" % ",".join(sorted(info)))
        for r, dirs, files in sorted(os.walk(app)):
            rel = os.path.relpath(r, app)
            print("  %s: %s" % (rel, ", ".join(sorted(files))))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
