#!/usr/bin/env python3
"""Run the signed test-only sandbox app with an existing outside marker."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', required=True, type=Path)
parser.add_argument('--windows98-disk', type=Path, help="Optional stopped, licensed Windows 98 fixture; never a running disk")
parser.add_argument('--check-floppy-swap', action='store_true', help='Additionally check a second support floppy in the private Windows fixture')
parser.add_argument('--reuse-private-windows98', action='store_true', help="Reuse a fixture previously imported inside the probe; no outside container access")
args = parser.parse_args()
if args.windows98_disk and args.reuse_private_windows98: parser.error("Choose import or reuse")
executable = args.app.resolve() / 'Contents/MacOS/DosMacProbe'
results = []
fixture = None
if args.windows98_disk:
    if not args.windows98_disk.is_file(): raise SystemExit('The supplied fixture is missing')
    fixture = args.windows98_disk.resolve()
with tempfile.NamedTemporaryFile(prefix='dosmac-sandbox-probe-', dir='/tmp') as marker:
    marker.write(b'Original disposable DosMac sandbox test marker.\n')
    marker.flush()
    windows = fixture is not None or args.reuse_private_windows98
    for sharing in ([True] if windows else [False, True]):
        command = [str(executable), '--outside-marker', marker.name]
        if sharing: command += ['--sharing']
        if args.check_floppy_swap:
            if not windows: parser.error('--check-floppy-swap requires a private Windows fixture')
            command += ['--check-floppy-swap']
        if fixture: command += ['--windows98', '--choose-windows98-fixture', str(fixture)]
        if args.reuse_private_windows98: command += ['--windows98', '--reuse-private-fixture']
        environment = dict(os.environ)
        # Valid host engines are available, and an invalid override must still
        # be ignored: this exercises the store policy in a signed real process.
        environment['DOSMAC_QEMU_PATH'] = marker.name
        environment['DOSMAC_SMBD_PATH'] = marker.name
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=None, text=True, timeout=600 if windows else 90, env=environment)
        try: report = json.loads(result.stdout)
        except json.JSONDecodeError:
            raise SystemExit('Sandbox probe produced no JSON report: ' + (result.stderr or 'Inspect the probe stderr output.')[-2000:])
        results.append(report)
        if result.returncode or report.get('success') is not True or report.get('outsideFileReadBlocked') is not True:
            print(json.dumps(results, indent=2))
            raise SystemExit(1)
print(json.dumps(results, indent=2))
