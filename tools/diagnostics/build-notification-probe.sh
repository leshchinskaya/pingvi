#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
probe="$PWD/.build/icon-probe/Pingvi Icon Test.app"
mkdir -p "$probe/Contents/MacOS" "$probe/Contents/Resources"
swiftc tools/diagnostics/NotificationProbe.swift -o "$probe/Contents/MacOS/IconProbe"
cp dist/Pingvi.app/Contents/Resources/AppIcon.icns "$probe/Contents/Resources/"
cp dist/Pingvi.app/Contents/Resources/Assets.car "$probe/Contents/Resources/"
/usr/bin/python3 - "$probe" <<'PY'
import plistlib,sys
from pathlib import Path
p=Path(sys.argv[1])/'Contents/Info.plist'
p.write_bytes(plistlib.dumps(dict(CFBundleIdentifier='local.pingvi.icon-test',CFBundleName='Pingvi Icon Test',CFBundleDisplayName='Pingvi Icon Test',CFBundleExecutable='IconProbe',CFBundleIconFile='AppIcon',CFBundleIconName='AppIcon',CFBundlePackageType='APPL',CFBundleVersion='1',NSPrincipalClass='NSApplication',LSMinimumSystemVersion='14.0')))
PY
codesign --force --deep --sign - "$probe"
