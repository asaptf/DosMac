#!/usr/bin/env python3
"""Inventory required-reason API imports. Call-site and purpose review is separate."""
import argparse
import json
from pathlib import Path
import re
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', required=True, type=Path)
args = parser.parse_args()
app = args.app.resolve()
magic = {b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xce', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca'}
patterns = {
    'NSPrivacyAccessedAPICategoryFileTimestamp': re.compile(r'^(?:[fl]?stat(?:64)?|[f]?getattrlist(?:bulk)?|NSURLContentModificationDateKey|NSURLCreationDateKey|NSFileCreationDate|NSFileModificationDate)$'),
    'NSPrivacyAccessedAPICategorySystemBootTime': re.compile(r'^(?:mach_absolute_time|mach_continuous_time|systemUptime)$'),
    'NSPrivacyAccessedAPICategoryDiskSpace': re.compile(r'^(?:[f]?statfs(?:64)?|[f]?statvfs|NSURLVolumeAvailableCapacity(?:ForImportantUsage|ForOpportunisticUsage)?Key|NSURLVolumeTotalCapacityKey)$'),
    'NSPrivacyAccessedAPICategoryUserDefaults': re.compile(r'NSUserDefaults|UserDefaultsC'),
}
results = []
for file in (app / 'Contents').rglob('*'):
    if not file.is_file(): continue
    with file.open('rb') as stream:
        if stream.read(4) not in magic: continue
    process = subprocess.run(['nm', '-u', '-j', str(file)], capture_output=True, text=True)
    if process.returncode: raise SystemExit(f'Cannot inspect native imports: {file.name}')
    raw_symbols = {line.strip().lstrip('_') for line in process.stdout.splitlines()}
    symbols = {symbol if symbol.startswith(('$s', 'OBJC_')) else symbol.split('$')[0] for symbol in raw_symbols}
    matches = {category: sorted(symbol for symbol in symbols if pattern.search(symbol)) for category, pattern in patterns.items()}
    matches = {category: values for category, values in matches.items() if values}
    if matches: results.append({'file': str(file.relative_to(app)), 'apiImports': matches})
print(json.dumps({'purpose': 'Symbol inventory; not a complete privacy or data-collection audit', 'nativeFiles': results}, indent=2))
