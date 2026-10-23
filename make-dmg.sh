#!/bin/zsh
# Builds build/QuranReaderHD.dmg: the app and an Applications shortcut. The mushaf pages are NOT included;
# the app offers to download them from the GitHub release on first run, or reads them online.
set -euo pipefail
cd "$(dirname "$0")"
./make-app.sh
STAGE="$(mktemp -d)/Quran Reader HD"
mkdir -p "$STAGE"
cp -R build/Mushaf.app "$STAGE/Quran Reader HD.app"
ln -s /Applications "$STAGE/Applications"
rm -f build/QuranReaderHD.dmg
hdiutil create -volname "Quran Reader HD" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov build/QuranReaderHD.dmg >/dev/null
echo "Built $PWD/build/QuranReaderHD.dmg ($(du -h build/QuranReaderHD.dmg | cut -f1))"
