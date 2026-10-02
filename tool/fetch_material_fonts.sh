#!/usr/bin/env bash
# Makes sure the Flutter SDK has its Material fonts (Roboto and Material
# Icons), which the visual tests draw text with; see "Visual tests" in
# README.md. The SDK downloads them only for a build or `flutter precache`,
# and a cached SDK in CI can have the stamp that says they're downloaded
# without the fonts themselves, so `precache` alone skips them.
#
#     tool/fetch_material_fonts.sh
set -eu

root=${FLUTTER_ROOT:-$(dirname "$(dirname "$(command -v flutter)")")}
fonts="$root/bin/cache/artifacts/material_fonts"

if [ ! -f "$fonts/roboto-regular.ttf" ]; then
  rm -f "$root/bin/cache/material_fonts.stamp"
  flutter precache --universal
fi
if [ ! -f "$fonts/roboto-regular.ttf" ]; then
  echo "::error::No Material fonts in $fonts after flutter precache" >&2
  exit 1
fi
echo "Material fonts are in $fonts"
