#!/bin/sh
# Shared by the command-line packager and the Xcode app target.
set -eu
cd "$(dirname "$0")/.."
contents="$1"
identity="${2:--}"
./script/build_whisper.sh
mkdir -p "$contents/Helpers" "$contents/Resources"
cp .build/whisper-native/build/bin/whisper-cli "$contents/Helpers/"
cp .build/whisper-native/source/LICENSE "$contents/Resources/Whisper-LICENSE"
cp LICENSE NOTICE "$contents/Resources/"
python3 script/export_localizations.py "$contents/Resources"
# SwiftPM without Xcode copies the source catalog and plugin stamp as resources.
rm -f "$contents/Resources/BehavioContext_BehavioContext.bundle/Localizable.xcstrings" "$contents/Resources/BehavioContext_BehavioContext.bundle/translations.valid"
iconset="$(mktemp -d "${TMPDIR:-/tmp}/behavio-icon.XXXXXX")/BehavioContext.iconset"
trap 'rm -rf "${iconset%/*}"' EXIT
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Sources/BehavioContext/Resources/BehavioContextIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
    doubled=$((size * 2))
    sips -z "$doubled" "$doubled" Sources/BehavioContext/Resources/BehavioContextIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$contents/Resources/BehavioContext.icns"
codesign --force --sign "$identity" --entitlements Configuration/WhisperHelper.entitlements "$contents/Helpers/whisper-cli"
