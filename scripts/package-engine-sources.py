#!/usr/bin/env python3
"""Package verified source evidence, recipes and build instructions; never guest disks."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import subprocess
import tarfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--sources', required=True, type=Path)
parser.add_argument('--app', required=True, type=Path, help='The exported app whose component inventory must match')
parser.add_argument('--firmware', type=Path, default=Path('build/firmware'))
parser.add_argument('--output', required=True, type=Path)
args = parser.parse_args()
repo = Path(__file__).resolve().parent.parent
root = args.sources.resolve()
manifest = json.loads((root / 'sources.json').read_text())
files = {}
engine = args.app / 'Contents/Resources/QEMU'
components = json.loads((engine / 'components.json').read_text())
expected = {(c['name'], c['version'], c['recipeSHA256']) for c in components}
actual = {(c['name'], c['version'], c['recipeSHA256']) for c in manifest['components']}
if actual != expected:
    raise SystemExit('Source inventory does not match the candidate components')

def include(file, name, expected=None):
    file = file.resolve(strict=True)
    digest = hashlib.sha256(file.read_bytes()).hexdigest()
    if expected and digest != expected:
        raise SystemExit('Source identity mismatch: ' + name)
    if name in files:
        raise SystemExit('Duplicate source-package member: ' + name)
    files[name] = (file, digest)

def source(relative, expected):
    path = (root / relative).resolve(strict=True)
    if not path.is_relative_to(root) or not path.is_file():
        raise SystemExit('Source path leaves the verified directory')
    include(path, 'components/' + relative, expected)

for component in manifest['components']:
    if not component.get('primaryArchiveVerified') or component.get('unresolvedLocalRecipeFiles'):
        raise SystemExit('Complete source evidence is unavailable')
    source(component['archive'], component['sha256'])
    for item in component.get('additionalInputs', []):
        source(item['archive'], item['sha256'])
    directory = Path(component['archive']).parent
    source(str(directory / component.get('recipeFile', component['name'] + '.rb')), component['recipeSHA256'])
    for metadata in component.get('metadataFiles', []):
        source(metadata['archive'], metadata['sha256'])
include(root / 'sources.json', 'components/sources.json')
firmware = args.firmware.resolve()
firmware_manifest = json.loads((firmware / 'seabios-build.json').read_text())
include(firmware / 'seabios-source.tar.gz', 'firmware/seabios-source.tar.gz', firmware_manifest['sourceSHA256'])
if hashlib.sha256((engine / 'share/qemu/bios-win9x.bin').read_bytes()).hexdigest() != firmware_manifest['biosSHA256']:
    raise SystemExit('Custom firmware does not match its source build manifest')
for name in ['seabios.config', 'seabios-build.json', 'SEABIOS-COPYING.txt']:
    include(firmware / name, 'firmware/' + name)
for relative in ['LICENSE', 'NOTICE', 'THIRD_PARTY_NOTICES.md',
                 'Configuration/EngineSourceInputs.json', 'Configuration/ThirdParty/Homebrew-LICENSE.txt',
                 'scripts/build-store-qemu.py', 'scripts/build-win9x-bios.py', 'scripts/build-guest-agent.py', 'scripts/bundle-qemu.py',
                 'scripts/collect-engine-sources.py', 'scripts/collect-source-notices.py',
                 'scripts/package-engine-sources.py', 'scripts/build-store-candidate.sh',
                 'GuestTools/Agent/agent.c', 'GuestTools/Agent/win32.h', 'GuestTools/Agent/LICENSE',
                 'GuestTools/Agent/README.md', 'docs/app-store/source-delivery.md',
                 'Sources/DosMacApp/Resources/GuestTools/dmagent.json', 'Sources/DosMacApp/Resources/GuestTools/qemouse-source.tar.gz',
                 'Sources/DosMacApp/Resources/GuestTools/QEMouse-LICENSE.txt',
                 'Sources/DosMacApp/Resources/GuestTools/QEMouse-NOTICE.txt']:
    include(repo / relative, 'project/' + relative)
revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip()
index = {'purpose': 'Source evidence package; complete-source and distribution-term review remain separate',
         'projectRevision': revision, 'workingTreeMayContainChanges': bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=repo, text=True).strip()),
         'sha256': {name: digest for name, (_, digest) in sorted(files.items())}}
args.output.parent.mkdir(parents=True, exist_ok=True)
with tarfile.open(args.output, 'w:gz') as archive:
    for name, (file, _) in sorted(files.items()):
        archive.add(file, arcname='dosmac-source-evidence/' + name, recursive=False)
    data = (json.dumps(index, indent=2) + '\n').encode()
    item = tarfile.TarInfo('dosmac-source-evidence/package-index.json')
    item.size = len(data); item.mode = 0o644
    archive.addfile(item, io.BytesIO(data))
print(json.dumps({'file': str(args.output), 'sha256': hashlib.sha256(args.output.read_bytes()).hexdigest(),
                  'files': len(files) + 1, 'bytes': args.output.stat().st_size}, indent=2))
