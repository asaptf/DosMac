#!/usr/bin/env python3
"""Assemble a local macOS developer app with QEMU, firmware, and non-system dylibs.

Not a notarized release pipeline. Audit licenses/source obligations before redistribution.
"""
import argparse
import hashlib
import json
import shutil
import subprocess
from pathlib import Path


def command(*args):
    return subprocess.check_output(args, text=True)


def dependencies(path):
    return [line.strip().split(" (compatibility", 1)[0] for line in command("otool", "-L", str(path)).splitlines()[1:]]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--qemu", default=shutil.which("qemu-system-i386"), type=Path)
    parser.add_argument("--win9x-firmware", default=Path("build/firmware"), type=Path)
    samba = next((p for p in [shutil.which("samba-dot-org-smbd"),
                              "/opt/homebrew/sbin/samba-dot-org-smbd", "/usr/local/sbin/samba-dot-org-smbd"]
                  if p and Path(p).is_file()), None)
    parser.add_argument("--samba", default=samba, type=Path)
    args = parser.parse_args()
    if not (args.win9x_firmware / "bios-win9x.bin").is_file():
        parser.error("Build Windows 9x firmware first: python3 scripts/build-win9x-bios.py")
    if not args.qemu or not args.qemu.exists():
        parser.error("A developer QEMU installation is required to build the bundled app.")
    app = args.app.resolve()
    if not (app / "Contents" / "Info.plist").exists():
        parser.error("Build the macOS application before bundling its engine.")
    prefix = args.qemu.parent.parent
    destination = app / "Contents/Resources/QEMU"
    if destination.exists():
        shutil.rmtree(destination)
    (destination / "bin").mkdir(parents=True)
    (destination / "lib").mkdir()
    (destination / "share/qemu").mkdir(parents=True)
    copied = {}
    names = {}

    def copy_binary(original, target):
        original = original.resolve()
        if original in copied:
            return copied[original]
        if target.name in names and names[target.name] != original:
            raise RuntimeError(f"Conflicting library basenames: {target.name}")
        names[target.name] = original
        shutil.copy2(original, target)
        target.chmod(0o755)
        copied[original] = target
        for dependency in dependencies(original):
            if dependency.startswith(("/usr/lib/", "/System/Library/")):
                continue
            if dependency.startswith("@loader_path/"):
                source = original.parent / dependency.removeprefix("@loader_path/")
            elif dependency.startswith("@rpath/"):
                source = prefix / "lib" / Path(dependency).name
                if not source.exists() and args.samba:
                    samba_prefix = args.samba.resolve().parent.parent
                    source = next((p for p in [samba_prefix / "lib" / Path(dependency).name,
                                               samba_prefix / "lib/private" / Path(dependency).name]
                                   if p.exists()), source)
            else:
                source = Path(dependency)
            if source.resolve() == original:
                continue  # dylib's own install name
            if not source.exists():
                raise RuntimeError(f"Cannot resolve dependency {dependency} of {original.name}")
            library = copy_binary(source, destination / "lib" / source.name)
            relative = "@loader_path/" + library.name if target.parent.name == "lib" else "@executable_path/../lib/" + library.name
            subprocess.run(["install_name_tool", "-change", dependency, relative, str(target)], check=True, capture_output=True)
        if target.parent.name == "lib":
            subprocess.run(["install_name_tool", "-id", "@rpath/" + target.name, str(target)], check=True, capture_output=True)
        return target

    for name in ["qemu-system-i386", "qemu-img"]:
        copy_binary(prefix / "bin" / name, destination / "bin" / name)
    if args.samba:
        copy_binary(args.samba, destination / "bin/smbd")
        shutil.copy2(args.samba.resolve().parent.parent / "COPYING", destination / "SAMBA-COPYING.txt")
    firmware = ["bios-256k.bin", "bios.bin", "vgabios-cirrus.bin", "vgabios-stdvga.bin", "kvmvapic.bin", "efi-pcnet.rom"]
    for name in firmware:
        shutil.copy2(prefix / "share/qemu" / name, destination / "share/qemu" / name)
    for name in ["bios-win9x.bin", "SEABIOS-COPYING.txt", "seabios.config", "seabios-source.tar.gz", "seabios-build.json"]:
        target = destination / "share/qemu" / name if name == "bios-win9x.bin" else destination / name
        shutil.copy2(args.win9x_firmware / name, target)
    shutil.copytree(prefix / "share/qemu/keymaps", destination / "share/qemu/keymaps")
    for target in sorted(copied.values(), key=lambda p: p.parent.name != "lib"):
        for dependency in dependencies(target):
            if dependency.startswith(("/opt/", "/usr/local/")):
                raise RuntimeError(f"Unbundled dependency remains: {dependency}")
        subprocess.run(["codesign", "--force", "--sign", "-", str(target)], check=True, capture_output=True)
    version = command(str(destination / "bin/qemu-system-i386"), "--version").splitlines()[0]
    manifest = {"version": version, "purpose": "local developer build", "upstream": "https://www.qemu.org/", "files": {str(p.relative_to(destination)): hashlib.sha256(p.read_bytes()).hexdigest() for p in destination.rglob("*") if p.is_file()}}
    (destination / "build-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (destination / "DEVELOPER-NOTICE.txt").write_text("Local development bundle only. QEMU, SeaBIOS, VGA BIOS, and linked libraries retain their respective licenses. A redistributable build must include their notices and required corresponding source. This script does not establish distribution compliance or notarization.\n")
    subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True, capture_output=True)
    print(f"Bundled {version}: {len(copied)} binaries/libraries; no Homebrew dylib paths remain.")


if __name__ == "__main__":
    main()
