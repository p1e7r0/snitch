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

if [ -n "${SNITCH_SIGNING_IDENTITY:-}" ]; then
    candidate_identities="$SNITCH_SIGNING_IDENTITY"
else
    candidate_identities="$(security find-identity -v -p codesigning | awk '/Apple Development/ { print $2 }')"
fi

signed_identity=""
for candidate_identity in $candidate_identities; do
    if codesign --force --sign "$candidate_identity" "$application_bundle" 2>/dev/null; then
        signed_identity="$candidate_identity"
        break
    fi
done
if [ -z "$signed_identity" ]; then
    codesign --force --sign - "$application_bundle"
    echo "Attenzione: firma locale senza identità stabile; i permessi di sistema andranno ridati a ogni ricompilazione."
fi
codesign --verify "$application_bundle"

if [ "${1:-}" = "--install" ]; then
    pkill -x Snitch || true
    while pgrep -x Snitch >/dev/null; do
        sleep 0.2
    done
    rm -rf "$installed_bundle"
    cp -R "$application_bundle" "$installed_bundle"
    open "$installed_bundle"
    echo "Installato e avviato: $installed_bundle"
else
    echo "Creato: $application_bundle"
fi
