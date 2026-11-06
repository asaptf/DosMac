#!/usr/bin/env python3
"""Check the local store candidate's execution boundaries, not Apple approval.

This deliberately does not certify license compatibility, provisioning, native
privacy declarations, or complete corresponding source. Those are release gates.
"""
import argparse
import json
import plistlib
import re
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', required=True, type=Path)
args = parser.parse_args()
app = args.app.resolve()
errors = []
def require(condition, message):
    if not condition: errors.append(message)
def entitlement(path):
    result = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(path)], capture_output=True)
    if result.returncode:
        errors.append(f'Cannot inspect entitlements: {path.name}')
        return {}
    try: return plistlib.loads(result.stdout)
    except Exception:
        errors.append(f'Invalid entitlement data: {path.name}')
        return {}

info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
require(info.get('DosMacDistribution') == 'app-store', 'Store policy is missing from Info.plist')
main = entitlement(app)
require(main.get('com.apple.security.app-sandbox') is True, 'App Sandbox is disabled')
require(not main.get('com.apple.security.cs.disable-library-validation'), 'Library validation is disabled')
require(not main.get('com.apple.security.cs.allow-unsigned-executable-memory'), 'Unsigned executable memory is allowed')
def team(path):
    result = subprocess.run(['codesign', '-dvv', str(path)], capture_output=True, text=True)
    match = re.search(r'^TeamIdentifier=(.+)$', result.stderr, re.M)
    return match.group(1) if match else None
root_team = team(app)
require(root_team not in (None, 'not set'), 'A real signing identity is required for this candidate check')
magic = {b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xce', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca'}
for path in (app / 'Contents').rglob('*'):
    if not path.is_file(): continue
    with path.open('rb') as file:
        if file.read(4) not in magic: continue
    require(str(path.relative_to(app)).startswith(('Contents/MacOS/', 'Contents/Helpers/', 'Contents/Frameworks/')), f'Native code is outside a standard code location: {path.name}')
    require(team(path) == root_team, f'Native code has a different signing team: {path.name}')
verification = subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], capture_output=True)
require(verification.returncode == 0, 'Nested signatures failed verification')
engine = app / 'Contents/Resources/QEMU'
require((engine / 'components.json').is_file(), 'Native component inventory is missing')
for name in ['qemu-system-i386','qemu-img','smbd']:
    helper = app / 'Contents/Helpers' / name
    require(helper.is_file(), f'Embedded helper missing: {name}')
    if helper.is_file():
        values = entitlement(helper)
        require(values.get('com.apple.security.app-sandbox') is True and values.get('com.apple.security.inherit') is True, f'Helper lacks sandbox inheritance: {name}')
        require(not values.get('com.apple.security.cs.disable-library-validation'), f'Helper disables library validation: {name}')
        require(not values.get('com.apple.security.cs.allow-unsigned-executable-memory'), f'Helper allows unsigned executable memory: {name}')
        if name != 'qemu-system-i386':
            require(not values.get('com.apple.security.cs.allow-jit'), f'Unnecessary JIT exception: {name}')
for helper in (app / 'Contents/Helpers').glob('*'):
    linkage = subprocess.run(['otool', '-L', str(helper)], capture_output=True, text=True)
    require(not any(line.strip().startswith(('/opt/', '/usr/local/')) for line in linkage.stdout.splitlines()[1:]), f'External developer dependency: {helper.name}')
require(not (app / 'Contents/Resources/Emulator').exists(), 'Unexpected legacy emulator in candidate')
print(json.dumps({'executionBoundaryChecksPassed': not errors, 'errors': errors,
                  'releaseGatesStillRequired': ['complete corresponding source and license terms', 'privacy audit of native libraries', 'App Store provisioning and upload validation', 'clean-machine and guest acceptance', 'App Review']}, indent=2))
raise SystemExit(1 if errors else 0)
