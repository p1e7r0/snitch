#!/bin/bash
set -uo pipefail

project_directory="$(cd "$(dirname "$0")/.." && pwd)"
bundle_identifier="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$project_directory/Resources/Info.plist")"
installed_bundle="/Applications/Snitch.app"
data_directory="$HOME/Library/Application Support/Snitch"
queue_directory="$data_directory/Queue"
keychain_service="$bundle_identifier.confluence"

pending_count=0
if [ -d "$queue_directory" ]; then
    pending_count="$(find "$queue_directory" -mindepth 2 -maxdepth 2 -name report.json | wc -l | tr -d ' ')"
fi

if [ "$pending_count" -gt 0 ] && [ "${1:-}" != "--force" ]; then
    echo "Ci sono $pending_count segnalazioni in coda non ancora inviate: verranno cancellate con i loro screenshot."
    read -r -p "Disinstallare comunque? [s/N] " answer
    if [ "$answer" != "s" ] && [ "$answer" != "S" ]; then
        echo "Disinstallazione annullata."
        exit 1
    fi
fi

pkill -x Snitch && echo "Snitch chiuso."

if [ -d "$installed_bundle" ]; then
    rm -rf "$installed_bundle" && echo "Rimosso: $installed_bundle"
fi

if [ -d "$data_directory" ]; then
    rm -rf "$data_directory" && echo "Rimossi coda e screenshot locali: $data_directory"
fi

removed_token_count=0
while security delete-generic-password -s "$keychain_service" >/dev/null 2>&1; do
    removed_token_count=$((removed_token_count + 1))
done
if [ "$removed_token_count" -gt 0 ]; then
    echo "Rimossi $removed_token_count token dal Portachiavi."
fi

if defaults delete "$bundle_identifier" >/dev/null 2>&1; then
    echo "Rimosse le preferenze."
fi

if tccutil reset ScreenCapture "$bundle_identifier" >/dev/null 2>&1; then
    echo "Revocato il permesso di registrazione dello schermo."
fi

echo "Disinstallazione completata."
