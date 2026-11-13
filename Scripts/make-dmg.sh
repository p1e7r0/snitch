#!/bin/bash
set -euo pipefail

project_directory="$(cd "$(dirname "$0")/.." && pwd)"
application_bundle="$project_directory/build/Snitch.app"

"$project_directory/Scripts/build-app.sh"

version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$application_bundle/Contents/Info.plist")"
disk_image="$project_directory/build/Snitch-$version.dmg"
icon_file="$project_directory/Resources/AppIcon.icns"
staging_directory="$(mktemp -d)"
working_directory="$(mktemp -d)"
writable_image="$working_directory/Snitch.dmg"
mount_point="$working_directory/volume"
custom_icon_finder_information="0000000000000000040000000000000000000000000000000000000000000000"
mkdir "$mount_point"

cp -R "$application_bundle" "$staging_directory/Snitch.app"
ln -s /Applications "$staging_directory/Applications"
cp "$icon_file" "$staging_directory/.VolumeIcon.icns"

hdiutil create \
    -volname "Snitch" \
    -srcfolder "$staging_directory" \
    -fs HFS+ \
    -format UDRW \
    -quiet \
    "$writable_image"
rm -rf "$staging_directory"

hdiutil attach "$writable_image" -mountpoint "$mount_point" -nobrowse -quiet
xattr -wx com.apple.FinderInfo "$custom_icon_finder_information" "$mount_point"
hdiutil detach "$mount_point" -quiet

rm -f "$disk_image"
hdiutil convert "$writable_image" -format UDZO -o "$disk_image" -quiet
rm -rf "$working_directory"

signing_identity="${SNITCH_SIGNING_IDENTITY:--}"
if [ "$signing_identity" != "-" ]; then
    codesign --force --sign "$signing_identity" "$disk_image"
fi

hdiutil verify -quiet "$disk_image"

osascript -l JavaScript -e 'ObjC.import("AppKit"); function run(argumentList) { const icon = $.NSImage.alloc.initWithContentsOfFile(argumentList[0]); $.NSWorkspace.sharedWorkspace.setIconForFileOptions(icon, argumentList[1], 0); }' "$icon_file" "$disk_image"
echo "Created: $disk_image"
