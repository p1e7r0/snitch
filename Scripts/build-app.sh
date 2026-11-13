#!/bin/bash
set -euo pipefail

project_directory="$(cd "$(dirname "$0")/.." && pwd)"
application_bundle="$project_directory/build/Snitch.app"
installed_bundle="/Applications/Snitch.app"

cd "$project_directory"
swift build --configuration release --product Snitch
binary_directory="$(swift build --configuration release --show-bin-path)"

rm -rf "$application_bundle"
mkdir -p "$application_bundle/Contents/MacOS" "$application_bundle/Contents/Resources"
cp "$binary_directory/Snitch" "$application_bundle/Contents/MacOS/Snitch"
cp "$project_directory/Resources/Info.plist" "$application_bundle/Contents/Info.plist"
cp "$project_directory/Resources/AppIcon.icns" "$application_bundle/Contents/Resources/AppIcon.icns"
cp -R "$project_directory"/Resources/*.lproj "$application_bundle/Contents/Resources/"

signing_identity="${SNITCH_SIGNING_IDENTITY:--}"
codesign --force --sign "$signing_identity" "$application_bundle"
codesign --verify "$application_bundle"
if [ "$signing_identity" = "-" ]; then
    echo "Ad-hoc signature without an identity: system permissions must be granted again after every rebuild."
fi

if [ "${1:-}" = "--install" ]; then
    pkill -x Snitch || true
    while pgrep -x Snitch >/dev/null; do
        sleep 0.2
    done
    rm -rf "$installed_bundle"
    cp -R "$application_bundle" "$installed_bundle"
    open "$installed_bundle"
    echo "Installed and launched: $installed_bundle"
else
    echo "Created: $application_bundle"
fi
