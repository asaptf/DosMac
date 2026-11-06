#!/usr/bin/env python3
"""Copy license texts from verified primary archives into the local app.

Does not extract executable source, follow archive links, or certify release rights.
Run before the final app signature and bundle integrity manifest are produced.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import tarfile
import zipfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--sources', required=True, type=Path)
parser.add_argument('--app', required=True, type=Path)
args = parser.parse_args()
engine = args.app / 'Contents/Resources/QEMU'
manifest = json.loads((args.sources / 'sources.json').read_text())
count = 0
for component in manifest['components']:
    if not component.get('primaryArchiveVerified'):
        raise SystemExit('An unverified source component cannot supply notices')
    source = (args.sources / component['archive']).resolve()
    if not source.is_relative_to(args.sources.resolve()) or hashlib.sha256(source.read_bytes()).hexdigest() != component['sha256']:
        raise SystemExit('Source archive identity mismatch')
    key = component['name'] + '@' + component['version']
    if '/' in key or '..' in key: raise SystemExit('Invalid component identity')
    output = engine / 'Licenses' / key / 'source'
    def save(name, size, data):
        global count
        path = PurePosixPath(name)
        if path.is_absolute() or '..' in path.parts or '\\' in name or '\n' in name or size > 1_048_576:
            return
        if not path.name.upper().startswith(('LICENSE','LICENCE','COPYING','COPYRIGHT','NOTICE','AUTHORS')):
            return
        target = output.joinpath(*path.parts)
        if not target.resolve().is_relative_to(output.resolve()): raise SystemExit('Unsafe output path')
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data())
        count += 1
    if zipfile.is_zipfile(source):
        with zipfile.ZipFile(source) as archive:
            for item in archive.infolist():
                if not item.is_dir() and (item.external_attr >> 16) & 0o170000 != 0o120000:
                    save(item.filename, item.file_size, lambda item=item: archive.read(item))
    else:
        with tarfile.open(source) as archive:
            for item in archive:
                if item.isfile(): save(item.name, item.size, lambda item=item: archive.extractfile(item).read())
print(f'Copied {count} source license/notice texts. Re-sign the app and refresh its integrity manifest before use.')
