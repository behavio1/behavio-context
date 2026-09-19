#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

configuration="${1:-release}"
if [ "$#" -gt 0 ]; then shift; fi
swift build "$@" -c "$configuration" --product BehavioContext -Xswiftc -enable-upcoming-feature -Xswiftc ConciseMagicFile -Xswiftc -debug-prefix-map -Xswiftc "$PWD=." -Xswiftc -file-prefix-map -Xswiftc "$PWD=."

build_dir="$(swift build "$@" -c "$configuration" --show-bin-path)"
app_root="$PWD/.build/app"
app="$app_root/UI Screen Context.app"
contents="$app/Contents"

rm -rf "$app"
mkdir -p "$contents/MacOS" "$contents/Resources"
cp "$build_dir/BehavioContext" "$contents/MacOS/BehavioContext"
cp Configuration/BehavioContextApp.plist "$contents/Info.plist"
cp -R "$build_dir/BehavioContext_BehavioContext.bundle" "$contents/Resources/"
cp -R "$build_dir/BehavioContext_BehavioContextCore.bundle" "$contents/Resources/"
if [ "$configuration" = release ]; then
    strip -S "$contents/MacOS/BehavioContext"
fi

signing_identity="${BEHAVIO_CONTEXT_SIGNING_IDENTITY:-}"
if [ -z "$signing_identity" ] \
    && security find-identity -v -p codesigning 2>/dev/null \
        | grep -Fq '"Behavio Context Local Development"'; then
    signing_identity="Behavio Context Local Development"
fi

./script/package_resources.sh "$contents" "${signing_identity:--}"

if [ -n "$signing_identity" ]; then
    codesign --force --sign "$signing_identity" \
        --entitlements BehavioContext.entitlements "$app"
    echo "Signed with stable identity: $signing_identity"
else
    codesign --force --sign - --entitlements BehavioContext.entitlements "$app"
    echo "Warning: ad-hoc signing changes the macOS privacy identity after each rebuild." >&2
    echo "Set BEHAVIO_CONTEXT_SIGNING_IDENTITY or install the local development identity." >&2
fi
codesign --verify --deep --strict "$app"
codesign -d --entitlements :- "$contents/Helpers/whisper-cli" 2>/dev/null | python3 -c 'import plistlib,sys; e=plistlib.loads(sys.stdin.buffer.read()); assert e == {"com.apple.security.app-sandbox": True, "com.apple.security.inherit": True}, "Whisper helper must inherit the app sandbox"'
if [ "$configuration" = release ]; then python3 script/verify_bundle.py "$app"; fi
echo "$app"
