#!/bin/zsh
# Builds build/CheCavo.app (release, ad-hoc signed) without Xcode.
set -e
cd "${0:A:h}/.."
# Universale (arm64 + x86_64) senza Xcode: `swift build --arch a --arch b` lo richiede,
# quindi due build separate (una per architettura, scratch-path distinti) unite con lipo.
SLICES=()
for ARCH in arm64 x86_64; do
  ARGS=(-c release --triple $ARCH-apple-macosx14.0 --scratch-path .build/$ARCH)
  swift build $ARGS --product CheCavo
  swift build $ARGS --product usbc-dump
  SLICES+=("$(swift build $ARGS --show-bin-path)")
done
APP=build/CheCavo.app
rm -rf $APP
mkdir -p $APP/Contents/MacOS
lipo -create -output $APP/Contents/MacOS/CheCavo ${^SLICES}/CheCavo
lipo -create -output build/usbc-dump ${^SLICES}/usbc-dump
cp Resources/Info.plist $APP/Contents/
mkdir -p $APP/Contents/Resources
ICONTMP=$(mktemp -d)
ICONSET=$ICONTMP/AppIcon.iconset
mkdir $ICONSET
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/AppIcon.png --out $ICONSET/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) Resources/AppIcon.png --out $ICONSET/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns $ICONSET -o $APP/Contents/Resources/AppIcon.icns
rm -rf $ICONTMP
cp Resources/Credits.rtf $APP/Contents/Resources/
codesign --force --sign - $APP
echo "Pronta: $PWD/$APP"
