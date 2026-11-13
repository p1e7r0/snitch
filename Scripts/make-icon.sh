#!/bin/bash
set -euo pipefail

project_directory="$(cd "$(dirname "$0")/.." && pwd)"
source_image="${1:-$project_directory/Resources/AppIcon-source.png}"
iconset_directory="$(mktemp -d)/AppIcon.iconset"

swift "$project_directory/Scripts/make-icon.swift" "$source_image" "$iconset_directory"
iconutil --convert icns --output "$project_directory/Resources/AppIcon.icns" "$iconset_directory"
rm -rf "$(dirname "$iconset_directory")"
echo "Creato: $project_directory/Resources/AppIcon.icns"
