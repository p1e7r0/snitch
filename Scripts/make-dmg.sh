#!/bin/bash
set -euo pipefail

project_directory="$(cd "$(dirname "$0")/.." && pwd)"
application_bundle="$project_directory/build/Snitch.app"

"$project_directory/Scripts/build-app.sh"

version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$application_bundle/Contents/Info.plist")"
disk_image="$project_directory/build/Snitch-$version.dmg"
staging_directory="$(mktemp -d)"

cp -R "$application_bundle" "$staging_directory/Snitch.app"
ln -s /Applications "$staging_directory/Applications"

rm -f "$disk_image"
hdiutil create \
    -volname "Snitch" \
    -srcfolder "$staging_directory" \
    -fs HFS+ \
    -format UDZO \
    -quiet \
    "$disk_image"
rm -rf "$staging_directory"

signature_details="$(codesign --display --verbose=2 "$application_bundle" 2>&1)"
signing_identity="$(awk -F= '/^Authority=Apple Development/ { print $2; exit }' <<< "$signature_details")"
if [ -n "$signing_identity" ]; then
    codesign --force --sign "$signing_identity" "$disk_image" 2>/dev/null || true
fi

hdiutil verify -quiet "$disk_image"
echo "Creato: $disk_image"
