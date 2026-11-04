#!/usr/bin/env python3
"""Build pinned SeaBIOS without PnP BIOS to allow Windows 9x PCI enumeration."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile

REVISION = "b52ca86e094d19b58e2304417787e96b940e39c6"  # SeaBIOS rel-1.17.0
SOURCE = f"https://codeload.github.com/qemu/seabios/tar.gz/{REVISION}"
SHA256 = "8b7082d885be6f5e11fc6570c0913165649ddbec8aa9af254ab081735edca8e5"
CONFIG = "CONFIG_QEMU=y\n# CONFIG_PNPBIOS is not set\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("build/firmware"))
    args = parser.parse_args()
    if not shutil.which("i686-elf-gcc") or not shutil.which("i686-elf-ld"):
        parser.error("Install the developer toolchain: brew install i686-elf-gcc i686-elf-binutils")
    args.output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="dosmac-seabios-") as temporary:
        root = Path(temporary)
        archive = root / "source.tar.gz"
        subprocess.run(["curl", "--fail", "--location", "--proto", "=https", "--proto-redir", "=https",
                        "--max-time", "120", "--max-filesize", "2097152", "--output", str(archive), SOURCE], check=True)
        if hashlib.sha256(archive.read_bytes()).hexdigest() != SHA256:
            raise RuntimeError("SeaBIOS source failed its pinned SHA-256 check")
        with tarfile.open(archive) as source:
            source.extractall(root, filter="data")
        source = root / f"seabios-{REVISION}"
        (source / ".version").write_text("rel-1.17.0\n")
        (source / ".config").write_text(CONFIG)
        command = ["make", "CROSS_PREFIX=i686-elf-", "PYTHON=python3", "EXTRAVERSION=-DosMac-win9x"]
        subprocess.run(command + ["olddefconfig"], cwd=source, check=True)
        subprocess.run(command + [f"-j{min(os.cpu_count() or 2, 8)}"], cwd=source, check=True)
        config = (source / ".config").read_text()
        if "# CONFIG_PNPBIOS is not set" not in config:
            raise RuntimeError("SeaBIOS unexpectedly enabled PnP BIOS")
        output = args.output / "bios-win9x.bin"
        shutil.copy2(source / "out/bios.bin", output)
        shutil.copy2(source / "COPYING", args.output / "SEABIOS-COPYING.txt")
        (args.output / "seabios.config").write_text(config)
        # Include the exact corresponding source in the developer bundle.
        shutil.copy2(archive, args.output / "seabios-source.tar.gz")
        manifest = {"revision": REVISION, "source": SOURCE, "sourceSHA256": SHA256,
                    "biosSHA256": hashlib.sha256(output.read_bytes()).hexdigest(),
                    "configuration": "CONFIG_PNPBIOS=n", "version": "1.17.0-DosMac-win9x"}
        (args.output / "seabios-build.json").write_text(json.dumps(manifest, indent=2) + "\n")
        print(f"Built Windows 9x firmware: {output}")


if __name__ == "__main__":
    main()
