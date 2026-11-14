#!/bin/zsh
# Builds build/CheCavo-<versione>.dmg (app + collegamento ad Applicazioni + Leggimi.txt).
set -e
cd "${0:A:h}/.."
MNT=/Volumes/CheCavo
# the Finder lays out the window by volume name, so no other CheCavo volume may be open
[[ -e $MNT ]] && { echo "Espelli prima il disco CheCavo già aperto."; exit 1 }
./scripts/build-app.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
STAGE=$(mktemp -d)
WORK=$(mktemp -d)
trap 'hdiutil detach $MNT -quiet 2>/dev/null; rm -rf "$STAGE" "$WORK"' EXIT
ditto build/CheCavo.app $STAGE/CheCavo.app
ln -s /Applications $STAGE/Applications
cat > $STAGE/Leggimi.txt <<'TXT'
CheCavo

Che cos'è
CheCavo dice se un cavo USB-C va bene per la ricarica, il video, l'audio e i dati. Si apre in una finestra con tutte le risposte.

Come installarlo
Trascina CheCavo nella cartella Applicazioni.

La prima apertura
L'app non è firmata da uno sviluppatore registrato da Apple, quindi macOS la blocca la prima volta.
Apri Impostazioni di Sistema › Privacy e sicurezza e premi «Apri comunque».
(Su macOS 15 e successivi il clic destro › Apri non basta più.)

Requisiti
macOS 14 o successivo. Funziona sui Mac con chip Apple. Sui Mac Intel si apre, ma per ora non legge i cavi.

Crediti
CheCavo è un programma gratuito e si può ridistribuire gratuitamente. Creato da Francesco Renzo con Claude Code.
TXT
# window background (1x + Retina in one TIFF), drawn by dmg-background.swift
mkdir $STAGE/.background
swift scripts/dmg-background.swift $WORK/sfondo.png 1
swift scripts/dmg-background.swift $WORK/sfondo@2x.png 2
tiffutil -cathidpicheck $WORK/sfondo.png $WORK/sfondo@2x.png -out $STAGE/.background/sfondo.tiff

# a writable image first: the Finder saves the layout (.DS_Store) on the disk itself
hdiutil create -volname CheCavo -srcfolder $STAGE -ov -format UDRW $WORK/rw.dmg
hdiutil attach $WORK/rw.dmg -mountpoint $MNT -noautoopen -quiet
# positions and size must match dmg-background.swift (640×460 points)
osascript <<'APPLESCRIPT'
tell application "Finder"
  tell disk "CheCavo"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set pathbar visible of container window to false
    -- 460 points of background + 68 for the top bar, which macOS 27 always shows
    set bounds of container window to {200, 120, 840, 648}
    set opts to icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 100
    set text size of opts to 13
    set background picture of opts to file ".background:sfondo.tiff"
    set position of item "CheCavo.app" of container window to {170, 170}
    set position of item "Applications" of container window to {470, 170}
    set position of item "Leggimi.txt" of container window to {320, 350}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT
sync
sleep 1
hdiutil detach $MNT -quiet

DMG=$PWD/build/CheCavo-$VERSION.dmg
hdiutil convert $WORK/rw.dmg -format UDZO -ov -o $DMG -quiet
echo "Pronto: $DMG"
