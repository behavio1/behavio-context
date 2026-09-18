#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

configuration="${1:-debug}"
swift build -c "$configuration" --product BehavioContext

build_dir="$(swift build -c "$configuration" --show-bin-path)"
app_root="$PWD/.build/app"
app="$app_root/UI Screen Context.app"
contents="$app/Contents"

rm -rf "$app"
mkdir -p "$contents/MacOS" "$contents/Resources"
cp "$build_dir/BehavioContext" "$contents/MacOS/BehavioContext"
cp Configuration/BehavioContextApp.plist "$contents/Info.plist"
cp -R "$build_dir/BehavioContext_BehavioContext.bundle" "$contents/Resources/"
cp -R "$build_dir/BehavioContext_BehavioContextCore.bundle" "$contents/Resources/"

python3 script/export_localizations.py "$contents/Resources"

iconset="$app_root/BehavioContext.iconset"
rm -rf "$iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    magick Assets/BehavioContextIcon-v2.png -filter Lanczos -resize "${size}x${size}" "$iconset/icon_${size}x${size}.png"
    doubled=$((size * 2))
    magick Assets/BehavioContextIcon-v2.png -filter Lanczos -resize "${doubled}x${doubled}" "$iconset/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$iconset" -o "$contents/Resources/BehavioContext.icns"
rm -rf "$iconset"

signing_identity="${BEHAVIO_CONTEXT_SIGNING_IDENTITY:-}"
if [ -z "$signing_identity" ] \
    && security find-identity -v -p codesigning 2>/dev/null \
        | grep -Fq '"Behavio Context Local Development"'; then
    signing_identity="Behavio Context Local Development"
fi

if [ -n "$signing_identity" ]; then
    codesign --force --deep --sign "$signing_identity" \
        --entitlements BehavioContext.entitlements "$app"
    echo "Signed with stable identity: $signing_identity"
else
    codesign --force --deep --sign - --entitlements BehavioContext.entitlements "$app"
    echo "Warning: ad-hoc signing changes the macOS privacy identity after each rebuild." >&2
    echo "Set BEHAVIO_CONTEXT_SIGNING_IDENTITY or install the local development identity." >&2
fi
codesign --verify --deep --strict "$app"
echo "$app"
