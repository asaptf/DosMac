#!/usr/bin/env python3
"""Assemble a local macOS developer app with QEMU, firmware, and non-system dylibs.

Not a notarized release pipeline. Audit licenses/source obligations before redistribution.
"""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path


def command(*args):
    return subprocess.check_output(args, text=True)


def dependencies(path):
    return [line.strip().split(" (compatibility", 1)[0] for line in command("otool", "-L", str(path)).splitlines()[1:]]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--qemu-build", type=Path, help="Source-build manifest for the project-built minimal QEMU")
    parser.add_argument("--sources", type=Path, help="Verified source evidence directory; include source license texts before signing")
    parser.add_argument("--sandbox", action="store_true", help="Sign embedded executable helpers for sandbox inheritance")
    parser.add_argument("--sign-identity", default="-", help="Code-signing identity; ad-hoc by default for local checks")
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
    source_build = json.loads(args.qemu_build.read_text()) if args.qemu_build else None
    build_script = Path(__file__).resolve().parent / "build-store-qemu.py"
    if source_build:
        if source_build.get("format") != "dosmac-qemu-source-build-v1" or source_build.get("buildScript") != build_script.name or source_build.get("buildScriptSHA256") != hashlib.sha256(build_script.read_bytes()).hexdigest():
            raise RuntimeError("QEMU source-build provenance does not match its build script")
        for name in ["bin/qemu-system-i386", "bin/qemu-img"]:
            if hashlib.sha256((prefix / name).read_bytes()).hexdigest() != source_build.get("files", {}).get(name):
                raise RuntimeError("The supplied QEMU binary does not match its source-build manifest")
    destination = app / "Contents/Resources/QEMU"
    previous = destination / "build-manifest.json"
    if previous.is_file():
        for relative in json.loads(previous.read_text()).get("nativeFiles", []):
            file = app / relative
            if not relative.startswith(("Contents/Helpers/", "Contents/Frameworks/", "Contents/Resources/QEMU/bin/", "Contents/Resources/QEMU/lib/")) or not file.resolve().is_relative_to(app):
                raise RuntimeError("Unsafe previous native-code inventory")
            if file.is_file():
                file.unlink()
    if destination.exists():
        shutil.rmtree(destination)
    binaries = app / "Contents/Helpers" if args.sandbox else destination / "bin"
    libraries = app / "Contents/Frameworks" if args.sandbox else destination / "lib"
    binaries.mkdir(parents=True, exist_ok=True)
    libraries.mkdir(parents=True, exist_ok=True)
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
            library = copy_binary(source, libraries / source.name)
            relative = "@loader_path/" + library.name if target.parent == libraries else ("@executable_path/../Frameworks/" if args.sandbox else "@executable_path/../lib/") + library.name
            subprocess.run(["install_name_tool", "-change", dependency, relative, str(target)], check=True, capture_output=True)
        if target.parent == libraries:
            subprocess.run(["install_name_tool", "-id", "@rpath/" + target.name, str(target)], check=True, capture_output=True)
        # Every non-system dependency now uses an explicit bundle-relative path.
        # Do not retain search paths into the builder's Homebrew installation.
        load_commands = command("otool", "-l", str(target))
        for rpath in re.findall(r"cmd LC_RPATH\n.*?\n\s*path (.*?) \(offset", load_commands):
            if rpath.startswith(("/opt/", "/usr/local/")):
                subprocess.run(["install_name_tool", "-delete_rpath", rpath, str(target)], check=True, capture_output=True)
        return target

    for name in ["qemu-system-i386", "qemu-img"]:
        copy_binary(prefix / "bin" / name, binaries / name)
    if args.samba:
        copy_binary(args.samba, binaries / "smbd")
        shutil.copy2(args.samba.resolve().parent.parent / "COPYING", destination / "SAMBA-COPYING.txt")
    firmware = ["bios-256k.bin", "bios.bin", "vgabios-cirrus.bin", "vgabios-stdvga.bin", "kvmvapic.bin", "efi-pcnet.rom"]
    for name in firmware:
        shutil.copy2(prefix / "share/qemu" / name, destination / "share/qemu" / name)
    for name in ["bios-win9x.bin", "SEABIOS-COPYING.txt", "seabios.config", "seabios-source.tar.gz", "seabios-build.json"]:
        target = destination / "share/qemu" / name if name == "bios-win9x.bin" else destination / name
        shutil.copy2(args.win9x_firmware / name, target)
    shutil.copytree(prefix / "share/qemu/keymaps", destination / "share/qemu/keymaps")
    for target in sorted(copied.values(), key=lambda p: p.parent != libraries):
        for dependency in dependencies(target):
            if dependency.startswith(("/opt/", "/usr/local/")):
                raise RuntimeError(f"Unbundled dependency remains: {dependency}")
        signing = ["codesign", "--force", "--sign", args.sign_identity]
        if args.sandbox:
            signing += ["--options", "runtime"]
            if target.parent == binaries:
                entitlement = "QEMUHelper.entitlements" if target.name == "qemu-system-i386" else "InheritedHelper.entitlements"
                signing += ["--entitlements", str(Path(__file__).resolve().parent.parent / "Configuration" / entitlement)]
        subprocess.run(signing + [str(target)], check=True, capture_output=True)
    version = command(str(args.qemu), "--version").splitlines()[0]
    components = {}
    for original, target in copied.items():
        parts = original.parts
        if source_build and original.is_relative_to(prefix.resolve()):
            name = str(original.relative_to(prefix.resolve()))
            if name not in source_build["files"]:
                raise RuntimeError("Untracked native file in custom QEMU prefix")
            key = source_build["name"] + "@" + source_build["version"]
            item = components.setdefault(key, {"name": source_build["name"], "version": source_build["version"], "files": [],
                                              "recipeSHA256": source_build["buildScriptSHA256"], "recipeFile": build_script.name, "sourceBuild": source_build})
            item["files"].append(str(target.relative_to(app)))
            license_dir = destination / "Licenses" / key
            license_dir.mkdir(parents=True, exist_ok=True)
            shutil.copy2(build_script, license_dir / build_script.name)
            shutil.copy2(args.qemu_build, license_dir / "source-build.json")
            continue
        if "Cellar" not in parts:
            continue
        index = parts.index("Cellar")
        component, installed_version = parts[index + 1:index + 3]
        key = component + "@" + installed_version
        keg = Path(*parts[:index + 3])
        recipe = keg / ".brew" / (component + ".rb")
        receipt = keg / "INSTALL_RECEIPT.json"
        known = key in components
        item = components.setdefault(key, {"name": component, "version": installed_version, "files": []})
        item["files"].append(str(target.relative_to(app)))
        if known:
            continue
        license_dir = destination / "Licenses" / key
        license_dir.mkdir(parents=True, exist_ok=True)
        for source_file in [recipe, receipt]:
            if source_file.is_file():
                shutil.copy2(source_file, license_dir / source_file.name)
        # Installed license texts supplement, and do not replace, corresponding source.
        for license_file in keg.rglob("*"):
            if license_file.is_file() and not license_file.is_symlink() and license_file.name.upper().startswith(("COPYING", "LICENSE", "LICENCE", "COPYRIGHT", "AUTHORS", "NOTICE")):
                relative = license_file.relative_to(keg)
                target_file = license_dir / "installed" / relative
                target_file.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(license_file, target_file)
        item["recipeSHA256"] = hashlib.sha256(recipe.read_bytes()).hexdigest() if recipe.is_file() else None
    shutil.copy2(Path(__file__).resolve().parent.parent / "Configuration/ThirdParty/Homebrew-LICENSE.txt", destination / "Licenses/Homebrew-LICENSE.txt")
    (destination / "components.json").write_text(json.dumps(sorted(components.values(), key=lambda c: c["name"]), indent=2) + "\n")
    if args.sources:
        if sum(len(c["files"]) for c in components.values()) != len(copied):
            raise RuntimeError("Some native binaries lack source provenance. Supply reviewed source metadata for custom engines before assembling a candidate.")
        evidence = json.loads((args.sources / "sources.json").read_text())
        expected_sources = {(c["name"], c["version"], c["recipeSHA256"]) for c in components.values()}
        supplied_sources = {(c["name"], c["version"], c["recipeSHA256"]) for c in evidence["components"]}
        if expected_sources != supplied_sources:
            raise RuntimeError("Source evidence does not match the bundled component versions and build recipes")
        subprocess.run([sys.executable, str(Path(__file__).resolve().parent / "collect-source-notices.py"), "--sources", str(args.sources), "--app", str(app)], check=True)
        shutil.copy2(args.sources / "sources.json", destination / "source-evidence.json")
    manifest = {"version": version, "purpose": "sandboxed store preparation" if args.sandbox else "local developer build", "upstream": "https://www.qemu.org/", "nativeFiles": [str(p.relative_to(app)) for p in copied.values()], "assemblyNativeSHA256": {str(p.relative_to(app)): hashlib.sha256(p.read_bytes()).hexdigest() for p in copied.values()}, "files": {str(p.relative_to(destination)): hashlib.sha256(p.read_bytes()).hexdigest() for p in destination.rglob("*") if p.is_file()}}
    (destination / "build-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (destination / "DEVELOPER-NOTICE.txt").write_text("Local development bundle only. QEMU, SeaBIOS, VGA BIOS, and linked libraries retain their respective licenses. A redistributable build must include their notices and required corresponding source. This script does not establish distribution compliance or notarization.\n")
    # Xcode Debug can split the app into an executable and a debug dylib.
    # Keep every remaining Mach-O on the same team before enabling validation.
    if args.sandbox:
        magic = {b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xce", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"}
        already_signed = set(copied.values())
        for nested in (app / "Contents").rglob("*"):
            if not nested.is_file() or nested in already_signed:
                continue
            with nested.open("rb") as file:
                if file.read(4) not in magic:
                    continue
            subprocess.run(["codesign", "--force", "--sign", args.sign_identity, "--options", "runtime", str(nested)], check=True, capture_output=True)
    signing = ["codesign", "--force", "--sign", args.sign_identity]
    if args.sandbox:
        signing += ["--options", "runtime", "--entitlements", str(Path(__file__).resolve().parent.parent / "Configuration/AppStore.entitlements")]
    subprocess.run(signing + [str(app)], check=True, capture_output=True)
    print(f"Bundled {version}: {len(copied)} binaries/libraries; no Homebrew dylib paths remain.")


if __name__ == "__main__":
    main()
