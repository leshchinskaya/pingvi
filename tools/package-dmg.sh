#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
case "${1:---release}" in
    --release) mode=release ;;
    --local) mode=local ;;
    --adhoc) mode=adhoc; export SIGNING_IDENTITY=- ;;
    *) echo 'Usage: bash tools/package-dmg.sh [--release|--local|--adhoc]' >&2; exit 2 ;;
esac
python3 tools/distribution.py "$mode"
bash tools/build.sh
if [[ "$mode" == release ]]; then
    # Staple the app itself so the copy in Applications carries its own ticket.
    notary_stage=$(mktemp -d "$PWD/.build/notarize.XXXXXX")
    archive="$notary_stage/Pingvi.zip"
    ditto -c -k --keepParent dist/Pingvi.app "$archive"
    xcrun notarytool submit "$archive" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple dist/Pingvi.app
    xcrun stapler validate dist/Pingvi.app
    spctl --assess --type execute --verbose=2 dist/Pingvi.app
fi
stage=$(mktemp -d "$PWD/.build/dmg.XXXXXX")
# Keep staging directories for inspection; no user data is included.
ditto dist/Pingvi.app "$stage/Pingvi.app"
ln -s /Applications "$stage/Applications"
cp docs/PILOT.txt "$stage/Прочитайте перед запуском.txt"
arch=$(uname -m)
output="$PWD/dist/Pingvi-0.7.0-beta.11-$arch.dmg"
if [[ "$mode" != release ]]; then output="${output%.dmg}-$mode.dmg"; fi
hdiutil create -volname Pingvi -srcfolder "$stage" -ov -format UDZO "$output"
hdiutil verify "$output"
if [[ "$mode" == release ]]; then
    codesign --timestamp --sign "$SIGNING_IDENTITY" "$output"
fi
if [[ "$mode" == release ]]; then
    : "${SIGNING_IDENTITY:?Notarization requires SIGNING_IDENTITY}"
    xcrun notarytool submit "$output" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$output"
    xcrun stapler validate "$output"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$output"
fi
(cd dist && shasum -a 256 "$(basename "$output")") > "$output.sha256"
printf '%s\n' "$output"
