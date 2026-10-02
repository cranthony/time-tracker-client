#!/usr/bin/env bash
# Makes sure the Flutter SDK has its Material fonts (Roboto and Material
# Icons), which the visual tests draw text with; see "Visual tests" in
# README.md. The SDK downloads them only for a build or `flutter precache`.
#
#     tool/fetch_material_fonts.sh
set -eu

root=${FLUTTER_ROOT:-$(dirname "$(dirname "$(command -v flutter)")")}
fonts="$root/bin/cache/artifacts/material_fonts"

if [ ! -f "$fonts/Roboto-Regular.ttf" ]; then
  flutter precache --universal
fi
if [ ! -f "$fonts/Roboto-Regular.ttf" ]; then
  echo "::error::No Material fonts in $fonts after flutter precache" >&2
  ls -la "$fonts" >&2 || true
  exit 1
fi
echo "Material fonts are in $fonts"
