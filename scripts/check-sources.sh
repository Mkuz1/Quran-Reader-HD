#!/usr/bin/env bash
# Checks the online sources the apps depend on but can't be tested offline: every reciter folder on
# EveryAyah (first and last ayah), that the macOS and Windows/Android reciter lists match, and the shape of
# the quranenc.com tafsir response. Run by .github/workflows/release.yml before anything is published.
set -euo pipefail
cd "$(dirname "$0")/.."

dart_ids=$(grep -oE "Reciter\('[^']+'" flutter_app/lib/audio/reciters.dart | sed -E "s/Reciter\('//; s/'$//")
swift_ids=$(grep -oE 'Reciter\(id: "[^"]+"' Sources/MushafMac/AudioController.swift | sed -E 's/Reciter\(id: "//; s/"$//')
if [ "$dart_ids" != "$swift_ids" ]; then
  echo "::error::The reciter lists in reciters.dart and AudioController.swift differ"
  diff <(echo "$dart_ids") <(echo "$swift_ids") || true
  exit 1
fi

failed=0
for id in $dart_ids; do
  for file in 001001 114006; do
    code=$(curl -s -o /dev/null -I -L --retry 3 --retry-delay 2 -w '%{http_code}' "https://everyayah.com/data/$id/$file.mp3")
    if [ "$code" != 200 ]; then
      echo "::error::Reciter $id: $file.mp3 returned HTTP $code"
      failed=1
    fi
  done
  echo "ok  $id"
done

# French tafsir (Al-Mukhtasar): result[] with aya (number or string) and translation, one per ayah.
curl -fsS --retry 3 https://quranenc.com/api/v1/translation/sura/french_mokhtasar/1 \
  | jq -e '(.result | length) == 7 and ((.result[0].aya | tostring) == "1") and ((.result[6].translation | length) > 20)' >/dev/null \
  || { echo "::error::quranenc.com french_mokhtasar response has an unexpected shape"; failed=1; }
echo "ok  quranenc french_mokhtasar"

exit $failed
