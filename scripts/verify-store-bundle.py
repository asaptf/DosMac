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
parser.add_argument('--distribution', action='store_true', help='Also require an exported App Store identity and matching profile')
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
require(not main.get('com.apple.security.get-task-allow'), 'Debug attachment is enabled')
require(not main.get('com.apple.security.cs.disable-library-validation'), 'Library validation is disabled')
require(not main.get('com.apple.security.cs.allow-unsigned-executable-memory'), 'Unsigned executable memory is allowed')
def team(path):
    result = subprocess.run(['codesign', '-dvv', str(path)], capture_output=True, text=True)
    match = re.search(r'^TeamIdentifier=(.+)$', result.stderr, re.M)
    return match.group(1) if match else None
def version(value):
    parts = [int(v) for v in str(value).split('.')]
    return tuple((parts + [0,0,0])[:3])
minimum_os = info.get('LSMinimumSystemVersion')
require(bool(minimum_os), 'The minimum macOS version is missing')
native_dependencies = {}
root_team = team(app)
require(root_team not in (None, 'not set'), 'A real signing identity is required for this candidate check')
if args.distribution:
    metadata = subprocess.run(['codesign', '-dvv', str(app)], capture_output=True, text=True).stderr
    require('Authority=Apple Distribution:' in metadata or 'Authority=3rd Party Mac Developer Application:' in metadata, 'An App Store application distribution identity is required')
    profile_file = app / 'Contents/embedded.provisionprofile'
    require(profile_file.is_file(), 'The exported App Store profile is missing')
    if profile_file.is_file():
        decoded = subprocess.run(['security', 'cms', '-D', '-i', str(profile_file)], capture_output=True)
        try:
            profile = plistlib.loads(decoded.stdout)
            values = profile.get('Entitlements', {})
            expected = root_team + '.' + info['CFBundleIdentifier']
            require(values.get('com.apple.application-identifier') == expected, 'The profile does not match this application')
            require(root_team in profile.get('TeamIdentifier', []), 'The profile has a different team')
            require(not values.get('com.apple.security.get-task-allow') and not values.get('get-task-allow'), 'The profile permits debug attachment')
        except Exception:
            errors.append('Cannot inspect the exported App Store profile')
magic = {b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xce', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca'}
for path in (app / 'Contents').rglob('*'):
    if not path.is_file(): continue
    with path.open('rb') as file:
        if file.read(4) not in magic: continue
    require(str(path.relative_to(app)).startswith(('Contents/MacOS/', 'Contents/Helpers/', 'Contents/Frameworks/')), f'Native code is outside a standard code location: {path.name}')
    require(team(path) == root_team, f'Native code has a different signing team: {path.name}')
    linkage = subprocess.run(['otool', '-L', str(path)], capture_output=True, text=True)
    native_dependencies[path.resolve()] = [line.strip().split(' (compatibility',1)[0] for line in linkage.stdout.splitlines()[1:]]
    require(linkage.returncode == 0, f'Cannot inspect native linkage: {path.name}')
    require(not any(line.strip().startswith(('/opt/', '/usr/local/')) for line in linkage.stdout.splitlines()[1:]), f'External developer dependency: {path.name}')
    load_commands = subprocess.run(['otool', '-l', str(path)], capture_output=True, text=True)
    rpaths = re.findall(r'cmd LC_RPATH\n.*?\n\s*path (.*?) \(offset', load_commands.stdout)
    native_minimum = re.search(r'cmd LC_BUILD_VERSION\n(?:.*\n){0,5}?\s*minos ([0-9.]+)', load_commands.stdout)
    if not native_minimum:
        native_minimum = re.search(r'cmd LC_VERSION_MIN_MACOSX\n.*\n\s*version ([0-9.]+)', load_commands.stdout)
    if native_minimum and minimum_os:
        require(version(native_minimum.group(1)) <= version(minimum_os), f'{path.name} requires macOS {native_minimum.group(1)}, above the app minimum {minimum_os}')
    require(not any(value.startswith(('/opt/', '/usr/local/')) for value in rpaths), f'External developer search path: {path.name}')
verification = subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], capture_output=True)
require(verification.returncode == 0, 'Nested signatures failed verification')
engine = app / 'Contents/Resources/QEMU'
require((engine / 'components.json').is_file(), 'Native component inventory is missing')
if (engine / 'components.json').is_file():
    inventory = json.loads((engine / 'components.json').read_text())
    qemu_component = next((c for c in inventory if c['name'] == 'qemu'), {})
    build = qemu_component.get('sourceBuild', {})
    require(build.get('format') == 'dosmac-qemu-source-build-v1', 'The store candidate must use the pinned project-built minimal QEMU')
    require('--disable-libssh' in build.get('configureArguments', []), 'The unnecessary QEMU SSH backend is enabled')

def qemu_closure(path, seen):
    path = path.resolve()
    if path in seen: return
    seen.add(path)
    for dependency in native_dependencies.get(path, []):
        if dependency.startswith(('/usr/lib/', '/System/Library/')): continue
        if dependency.startswith('@loader_path/'):
            child = path.parent / dependency.removeprefix('@loader_path/')
        elif dependency.startswith('@executable_path/'):
            child = app / 'Contents/Helpers' / dependency.removeprefix('@executable_path/')
        elif dependency.startswith('@rpath/') and Path(dependency).name == path.name:
            continue  # dylib install ID
        else:
            errors.append('Unresolved dependency in QEMU graph: ' + Path(dependency).name)
            continue
        require(child.resolve() in native_dependencies, 'Missing QEMU dependency: ' + child.name)
        qemu_closure(child, seen)
qemu_files = set()
qemu_closure(app / 'Contents/Helpers/qemu-system-i386', qemu_files)
require(not any(p.name.startswith(('libssh.', 'libcrypto.', 'libssl.')) for p in qemu_files), 'Unnecessary SSH/OpenSSL dependency remains in the QEMU graph')
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
require(not (app / 'Contents/Resources/Emulator').exists(), 'Unexpected legacy emulator in candidate')
print(json.dumps({'executionBoundaryChecksPassed': not errors, 'declaredMinimumMacOS': minimum_os, 'errors': errors,
                  'releaseGatesStillRequired': ['complete corresponding source and license terms', 'privacy audit of native libraries', 'App Store provisioning and upload validation', 'clean-machine and guest acceptance', 'App Review']}, indent=2))
raise SystemExit(1 if errors else 0)
