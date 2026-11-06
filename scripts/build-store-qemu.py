#!/usr/bin/env python3
"""Build the pinned, minimal Mac QEMU used by DosMac; does not replace host QEMU."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile

VERSION = '11.1.3'
SOURCE_URL = 'https://download.qemu.org/qemu-11.1.3.tar.xz'
SOURCE_SHA256 = '5a8289c7940dc77d3873c81a6c29ba3afe1446fc9d36e77fa1658cdbecb84b22'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--python', type=Path, help='Build Python with setuptools installed')
parser.add_argument('--source', required=True, type=Path, help='Verified upstream QEMU source archive')
parser.add_argument('--output', type=Path, default=Path('build/store-engine'))
args = parser.parse_args()
if hashlib.sha256(args.source.read_bytes()).hexdigest() != SOURCE_SHA256:
    raise SystemExit('QEMU source archive identity mismatch')
for tool in ['ninja', 'pkg-config', 'clang']:
    if not shutil.which(tool): raise SystemExit('Missing build tool: ' + tool)
python = args.python
if python is None and shutil.which('brew'):
    brew_python = Path(subprocess.check_output(['brew', '--prefix', 'python@3.15'], text=True).strip()) / 'bin/python3.15'
    if brew_python.is_file(): python = brew_python
python = python or Path(sys.executable)
if subprocess.run([str(python), '-c', 'import setuptools'], capture_output=True).returncode:
    raise SystemExit('The build Python needs setuptools. For Homebrew Python: brew install python-setuptools')
root = args.output.resolve()
root.mkdir(parents=True, exist_ok=True)
source = root / ('qemu-' + VERSION)
marker = root / 'source.sha256'
if source.exists():
    if not marker.is_file() or marker.read_text().strip() != SOURCE_SHA256:
        raise SystemExit('Choose a fresh build directory; existing source is not owned by this build')
else:
    skipped = []
    def source_filter(member, destination):
        try:
            return tarfile.data_filter(member, destination)
        except (tarfile.AbsoluteLinkError, tarfile.LinkOutsideDestinationError):
            # Unneeded EDK2 host-header links must not point outside the build.
            if member.issym() or member.islnk():
                skipped.append(member.name)
                return None
            raise
    with tarfile.open(args.source) as archive:
        archive.extractall(root, filter=source_filter)
    (root / 'skipped-source-links.json').write_text(json.dumps(skipped) + '\n')
    marker.write_text(SOURCE_SHA256 + '\n')
# Same build-only compatibility adjustment used by the installed Homebrew recipe:
# Python 3.15 no longer supplies wheel; modern setuptools builds do not need it.
deps = source / 'pythondeps.toml'
text = deps.read_text()
import re
text = re.sub(r'^"wheel" = .*\n', '', text, flags=re.M)
deps.write_text(text)
build = root / 'build'
build.mkdir(exist_ok=True)
prefix = root / 'prefix'
flags = [
    '--without-default-features', '--target-list=i386-softmmu',
    '--enable-system', '--enable-tcg', '--enable-tools',
    '--enable-vnc', '--enable-pixman', '--enable-coreaudio', '--enable-slirp',
    '--enable-zstd', '--disable-fdt',
    '--disable-libssh', '--disable-gnutls', '--disable-curl',
    '--disable-cocoa', '--disable-user', '--disable-docs', '--disable-guest-agent',
    '--disable-download', '--with-pkgversion=DosMac-minimal-1',
]
build_environment = dict(os.environ)
build_environment['MACOSX_DEPLOYMENT_TARGET'] = '14.0'
subprocess.run([str(source / 'configure'), '--prefix=' + str(prefix), '--python=' + str(python)] + flags, cwd=build, check=True, env=build_environment)
subprocess.run(['ninja', '-j', str(min(os.cpu_count() or 2, 8))], cwd=build, check=True, env=build_environment)
subprocess.run(['ninja', 'install'], cwd=build, check=True, env=build_environment)
files = {name: hashlib.sha256((prefix / name).read_bytes()).hexdigest()
         for name in ['bin/qemu-system-i386', 'bin/qemu-img']}
manifest = {
    'format': 'dosmac-qemu-source-build-v1', 'name': 'qemu', 'version': VERSION + '-dosmac.1',
    'sourceURL': SOURCE_URL, 'sourceSHA256': SOURCE_SHA256,
    'buildScript': Path(__file__).name,
    'buildScriptSHA256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    'deploymentTarget': '14.0', 'configureArguments': flags, 'skippedUnsafeSourceLinks': json.loads((root / 'skipped-source-links.json').read_text()), 'buildOnlyAdjustment': 'Remove obsolete wheel requirement from pythondeps.toml for Python 3.15',
    'files': files,
}
(root / 'source-build.json').write_text(json.dumps(manifest, indent=2) + '\n')
print('Built pinned minimal QEMU:', prefix)
