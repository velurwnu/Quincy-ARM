#!/bin/bash
#
# Builds build/Quincy 2005.app — Objective-C + AppKit, arm64, with AStyle 2.06
# compiled straight into the binary.
#
set -euo pipefail
cd "$(dirname "$0")"

# The project lives in a file-provider-backed folder (iCloud Drive), where the
# bundle directory always carries com.apple.FinderInfo and codesign refuses to
# work.  So the bundle is staged outside it and copied in once signed.
STAGE="${TMPDIR:-/tmp}/quincy-build"
OBJ="$STAGE/obj"
APP="$STAGE/Quincy 2005.app"
BIN="$APP/Contents/MacOS/Quincy 2005"
RES="$APP/Contents/Resources"

COMMON=(-arch arm64 -mmacosx-version-min=13.0 -O2 -flto
        -Ithird_party/astyle -Isrc)
MFLAGS=("${COMMON[@]}" -fobjc-arc -fmodules -fobjc-weak -Wall
        -Wno-unused-variable -Wno-deprecated-declarations)
MMFLAGS=("${COMMON[@]}" -fobjc-arc -std=c++11 -DASTYLE_LIB -Wno-deprecated-declarations)
CXXFLAGS=("${COMMON[@]}" -std=c++11 -DASTYLE_LIB -w)
LDFLAGS=(-arch arm64 -flto -framework Cocoa -framework UniformTypeIdentifiers)

if [[ "${1:-}" == "clean" ]]; then
  rm -rf build "$STAGE"
  echo "cleaned"
  exit 0
fi

if [[ ! -f resources/toolbar.png ]] || [[ tools/mkresources.py -nt resources/toolbar.png ]]; then
  echo "  resources"
  python3 -I tools/mkresources.py
fi

mkdir -p "$OBJ" build

# App icon: the cat is drawn as SVG layers in resources/Quincy.icon (Icon
# Composer format).  With Xcode installed, actool turns it into a Liquid Glass
# Assets.car plus a flat Quincy.icns for older systems.  Both are kept in
# resources/, so the Command Line Tools alone can still build the app.
if xcrun --find actool >/dev/null 2>&1 &&
   [[ ! -f resources/Assets.car || -n "$(find resources/Quincy.icon -newer resources/Assets.car)" ]]; then
  echo "  icon"
  xcrun actool resources/Quincy.icon --compile resources --app-icon Quincy \
      --platform macosx --target-device mac --minimum-deployment-target 13.0 \
      --output-partial-info-plist "$STAGE/icon.plist" >/dev/null
fi
objects=()

compile() {  # compile <source> <compiler> <flags...>
  local f="$1" cc="$2"; shift 2
  local obj="$OBJ/$(echo "$f" | tr '/' '_').o"
  objects+=("$obj")
  if [[ -f "$obj" && "$obj" -nt "$f" && "$obj" -nt src/Quincy.h ]]; then return; fi
  echo "    $f"
  "$cc" -c "$@" "$f" -o "$obj"
}

echo "  astyle"
for f in third_party/astyle/*.cpp; do compile "$f" clang++ "${CXXFLAGS[@]}"; done

echo "  quincy"
for f in src/*.m;  do compile "$f" clang   "${MFLAGS[@]}";  done
for f in src/*.mm; do compile "$f" clang++ "${MMFLAGS[@]}"; done

echo "  link"
rm -rf "$APP"
mkdir -p "$(dirname "$BIN")" "$RES"
clang++ "${objects[@]}" "${LDFLAGS[@]}" -o "$BIN"

echo "  bundle"
cp resources/Quincy.icns resources/Assets.car "$RES/"
for p in resources/*.png; do [[ -f "$p" ]] && cp "$p" "$RES/"; done

# Help: the original HTML, shipped inside the bundle and opened in the
# user's browser, exactly as the Windows version opened it in IE.
if [[ -d reference/original/html ]]; then
  mkdir -p "$RES/help"
  cp -R reference/original/html "$RES/help/"
  cp reference/original/*.htm "$RES/help/" 2>/dev/null || true
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>                 <string>Quincy 2005</string>
  <key>CFBundleDisplayName</key>          <string>Quincy 2005</string>
  <key>CFBundleExecutable</key>           <string>Quincy 2005</string>
  <key>CFBundleIdentifier</key>           <string>org.codecutter.quincy2005</string>
  <key>CFBundleVersion</key>              <string>1.3</string>
  <key>CFBundleShortVersionString</key>   <string>1.3</string>
  <key>CFBundlePackageType</key>          <string>APPL</string>
  <key>CFBundleIconFile</key>             <string>Quincy</string>
  <key>CFBundleIconName</key>             <string>Quincy</string>
  <key>LSMinimumSystemVersion</key>       <string>13.0</string>
  <key>NSHighResolutionCapable</key>      <true/>
  <key>NSPrincipalClass</key>             <string>NSApplication</string>
  <key>NSHumanReadableCopyright</key>     <string>Al Stevens, Dr. Dobb's Journal — Mac rebuild</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key>         <string>C++ Source File</string>
      <key>CFBundleTypeExtensions</key>
      <array><string>cpp</string><string>cxx</string><string>cc</string>
             <string>c</string><string>h</string><string>hpp</string>
             <string>rc</string><string>def</string></array>
      <key>CFBundleTypeRole</key>         <string>Editor</string>
    </dict>
    <dict>
      <key>CFBundleTypeName</key>         <string>Quincy Project</string>
      <key>CFBundleTypeExtensions</key>   <array><string>prj</string></array>
      <key>CFBundleTypeRole</key>         <string>Editor</string>
    </dict>
  </array>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "  sign"
find "$APP" \( -name '._*' -o -name '.DS_Store' \) -delete
xattr -cr "$APP"
codesign --force -s - "$APP" 2>/dev/null

rm -rf "build/Quincy 2005.app"
cp -R "$APP" build/
codesign -v "build/Quincy 2005.app"

echo "built build/Quincy 2005.app"
