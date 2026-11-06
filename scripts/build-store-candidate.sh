#!/bin/bash
# Build and inspect a self-contained Mac store candidate. Does not submit it.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -gt 1 || ($# -eq 1 && "$1" != "--export") ]]; then
  printf 'Usage: %s [--export]\n' "$0" >&2
  exit 2
fi
: "${DOSMAC_TEAM_ID:?Set DOSMAC_TEAM_ID to your Apple Developer team}"
: "${DOSMAC_SIGN_IDENTITY:?Set DOSMAC_SIGN_IDENTITY to your Apple Development identity}"
: "${DOSMAC_SOURCE_DIR:?Set DOSMAC_SOURCE_DIR to your verified engine source directory}"
: "${DOSMAC_QEMU_PATH:?Set DOSMAC_QEMU_PATH to your project-built minimal qemu-system-i386}"
: "${DOSMAC_QEMU_BUILD_MANIFEST:?Set DOSMAC_QEMU_BUILD_MANIFEST to its source-build.json}"
dosmac_build_number="${DOSMAC_BUILD_NUMBER:-1}"
if [[ ! "$dosmac_build_number" =~ ^[1-9][0-9]*$ ]]; then
  printf 'DOSMAC_BUILD_NUMBER must be a positive integer.\n' >&2
  exit 2
fi
candidate="$(pwd)/build/store-candidates/$(date -u +%Y%m%dT%H%M%SZ)-$$"
mkdir -p "$candidate"
xcodegen generate
xcodebuild -project DosMac.xcodeproj -scheme DosMac-AppStore \
  -configuration Release -destination 'generic/platform=macOS' \
  -archivePath "$candidate/DosMac.xcarchive" -allowProvisioningUpdates \
  "DEVELOPMENT_TEAM=$DOSMAC_TEAM_ID" "CURRENT_PROJECT_VERSION=$dosmac_build_number" CODE_SIGN_STYLE=Automatic archive \
  > "$candidate/archive.log" 2>&1
application="$candidate/DosMac.xcarchive/Products/Applications/DosMac.app"
python3 scripts/bundle-qemu.py --app "$application" --sandbox --qemu "$DOSMAC_QEMU_PATH" --qemu-build "$DOSMAC_QEMU_BUILD_MANIFEST" \
  --sign-identity "$DOSMAC_SIGN_IDENTITY" --sources "$DOSMAC_SOURCE_DIR" \
  > "$candidate/bundle.log" 2>&1
python3 scripts/verify-store-bundle.py --app "$application" > "$candidate/boundaries.json"
python3 scripts/audit-required-apis.py --app "$application" > "$candidate/api-imports.json"
python3 - "$candidate" "$DOSMAC_TEAM_ID" <<'PY'
import plistlib
from pathlib import Path
import sys
root = Path(sys.argv[1])
(root / 'ExportOptions.plist').write_bytes(plistlib.dumps({
    'method': 'app-store-connect', 'destination': 'export',
    'teamID': sys.argv[2], 'signingStyle': 'automatic'}))
PY
printf 'Candidate prepared: %s\n' "$candidate"
printf 'Review acceptance, licensing, privacy and exported signatures before upload.\n'
if [[ "${1:-}" == "--export" ]]; then
  xcodebuild -exportArchive -archivePath "$candidate/DosMac.xcarchive" \
    -exportOptionsPlist "$candidate/ExportOptions.plist" \
    -exportPath "$candidate/export" -allowProvisioningUpdates \
    > "$candidate/export.log" 2>&1
  pkgutil --check-signature "$candidate/export/DosMac.pkg" > "$candidate/installer-signature.txt"
  pkgutil --expand-full "$candidate/export/DosMac.pkg" "$candidate/export-expanded"
  exported="$(python3 - "$candidate/export-expanded" <<'PYAPP'
from pathlib import Path
import sys
matches = list(Path(sys.argv[1]).glob('*/Payload/DosMac.app'))
if len(matches) != 1:
    raise SystemExit('Expected one exported DosMac application')
print(matches[0])
PYAPP
)"
  python3 scripts/verify-store-bundle.py --app "$exported" --distribution > "$candidate/exported-boundaries.json"
  python3 scripts/audit-required-apis.py --app "$exported" > "$candidate/exported-api-imports.json"
  printf 'Export prepared: %s/export\n' "$candidate"
fi
