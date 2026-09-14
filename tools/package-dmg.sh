#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash tools/build.sh
stage=$(mktemp -d "$PWD/.build/dmg.XXXXXX")
# Keep staging directories for inspection; no user data is included.
ditto dist/Pingvi.app "$stage/Pingvi.app"
ln -s /Applications "$stage/Applications"
cp docs/PILOT.txt "$stage/Прочитайте перед запуском.txt"
arch=$(uname -m)
output="$PWD/dist/Pingvi-0.7.0-beta.3-$arch.dmg"
hdiutil create -volname Pingvi -srcfolder "$stage" -ov -format UDZO "$output"
hdiutil verify "$output"
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
    codesign --timestamp --sign "$SIGNING_IDENTITY" "$output"
fi
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    : "${SIGNING_IDENTITY:?Notarization requires SIGNING_IDENTITY}"
    xcrun notarytool submit "$output" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$output"
    xcrun stapler validate "$output"
fi
shasum -a 256 "$output" > "$output.sha256"
printf '%s\n' "$output"
