#!/usr/bin/env python3
"""Collect checksum-pinned primary source archives from the bundled keg recipes.

This is evidence collection, not a claim of complete corresponding source or
App Store license compatibility. Remote patches/resources require separate review.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
from urllib.parse import urlsplit

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', required=True, type=Path)
parser.add_argument('--output', required=True, type=Path)
args = parser.parse_args()
engine = args.app / 'Contents/Resources/QEMU'
components = json.loads((engine / 'components.json').read_text())
locks = json.loads((Path(__file__).resolve().parent.parent / 'Configuration/EngineSourceInputs.json').read_text())
args.output.mkdir(parents=True, exist_ok=True)

def collect(component):
    key = component['name'] + '@' + component['version']
    result = {'name': component['name'], 'version': component['version'], 'completeCorrespondingSourceReviewed': False}
    try:
        recipe = engine / 'Licenses' / key / (component['name'] + '.rb')
        text = recipe.read_text()
        # Only the primary stable source at class scope; do not mistake livecheck,
        # platform branches, resources or test fixtures for the main source.
        url = re.search(r'^  url "([^"]+)"', text, re.M)
        digest = re.search(r'^  sha256 "([0-9a-f]{64})"', text, re.M)
        if not url or not digest:
            raise ValueError('Primary source cannot be resolved without recipe review')
        address, expected = url.group(1), digest.group(1)
        if urlsplit(address).scheme != 'https' or '#{' in address:
            raise ValueError('Primary URL needs manual resolution')
        folder = args.output / key
        folder.mkdir(exist_ok=True)
        shutil.copy2(recipe, folder / recipe.name)
        source = folder / 'source.archive'
        result.update({'sourceURL': address, 'sha256': expected, 'recipeSHA256': hashlib.sha256(recipe.read_bytes()).hexdigest(),
                       'additionalRecipeInputsNeedReview': bool(re.search(r'^\s*(resource\s|patch\s)', text, re.M))})
        if not source.is_file() or hashlib.sha256(source.read_bytes()).hexdigest() != expected:
            partial = folder / 'source.partial'
            try:
                subprocess.run(['curl', '--fail', '--location', '--silent', '--show-error', '--proto', '=https', '--proto-redir', '=https', '--retry', '2', '--max-time', '600', '--max-filesize', '1073741824', '--output', str(partial), address], check=True, capture_output=True)
                if hashlib.sha256(partial.read_bytes()).hexdigest() != expected:
                    raise ValueError('Source archive failed its recipe SHA-256')
                partial.replace(source)
            finally:
                partial.unlink(missing_ok=True)
        extra = []
        expression = r'(?m)^(?P<indent> +)url "(?P<url>https://[^"\n]+)"\n(?P=indent)sha256 "(?P<sha>[0-9a-f]{64})"'
        for index, match in enumerate(re.finditer(expression, text)):
            if match['url'] == address:
                continue
            if '#{' in match['url']:
                raise ValueError('An additional source URL needs manual resolution')
            target = folder / f'input-{index}.archive'
            if not target.is_file() or hashlib.sha256(target.read_bytes()).hexdigest() != match['sha']:
                partial = folder / f'input-{index}.partial'
                try:
                    subprocess.run(['curl', '--fail', '--location', '--silent', '--show-error', '--proto', '=https', '--proto-redir', '=https', '--retry', '2', '--max-time', '180', '--max-filesize', '1073741824', '--output', str(partial), match['url']], check=True, capture_output=True)
                    if hashlib.sha256(partial.read_bytes()).hexdigest() != match['sha']:
                        raise ValueError('Additional source input failed SHA-256')
                    partial.replace(target)
                finally:
                    partial.unlink(missing_ok=True)
            extra.append({'url': match['url'], 'sha256': match['sha'], 'archive': str(target.relative_to(args.output))})
        unresolved = []
        locked = locks.get(key, {})
        for local in re.findall(r'^\s+file "([^"\n]+)"', text, re.M):
            pin = next((p for p in locked.get('files', []) if p['relativePath'] == local), None)
            if not pin or locked.get('recipeSHA256') != result['recipeSHA256']:
                unresolved.append(local)
                continue
            relative = Path(local)
            if relative.is_absolute() or '..' in relative.parts or urlsplit(pin['url']).scheme != 'https':
                raise ValueError('Unsafe pinned recipe input')
            target = folder / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            if not target.is_file() or hashlib.sha256(target.read_bytes()).hexdigest() != pin['sha256']:
                partial = target.with_suffix('.partial')
                try:
                    subprocess.run(['curl', '--fail', '--location', '--silent', '--show-error', '--proto', '=https', '--proto-redir', '=https', '--max-time', '60', '--max-filesize', '10485760', '--output', str(partial), pin['url']], check=True, capture_output=True)
                    if hashlib.sha256(partial.read_bytes()).hexdigest() != pin['sha256']:
                        raise ValueError('Pinned recipe input failed SHA-256')
                    partial.replace(target)
                finally:
                    partial.unlink(missing_ok=True)
            extra.append({'url': pin['url'], 'sha256': pin['sha256'], 'archive': str(target.relative_to(args.output)), 'recipePath': local})
        result['additionalInputs'] = extra
        result['unresolvedLocalRecipeFiles'] = unresolved
        result['primaryArchiveVerified'] = True
        result['bytes'] = source.stat().st_size
        result['archive'] = str(source.relative_to(args.output))
    except Exception as error:
        result['primaryArchiveVerified'] = False
        result['error'] = str(error)
    print(key + ': ' + ('verified' if result.get('primaryArchiveVerified') else result['error']), flush=True)
    return result

with ThreadPoolExecutor(max_workers=3) as pool:
    results = list(pool.map(collect, components))
manifest = {'purpose': 'Source evidence collection; legal and complete-source review pending', 'components': results}
(args.output / 'sources.json').write_text(json.dumps(manifest, indent=2) + '\n')
raise SystemExit(0 if all(c.get('primaryArchiveVerified') for c in results) else 1)
