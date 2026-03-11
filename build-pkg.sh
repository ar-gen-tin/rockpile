#!/bin/bash
# Rockpile .pkg installer build script
# Usage: ./build-pkg.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DIST_DIR="$SCRIPT_DIR/dist"
PKG_ROOT="$DIST_DIR/pkg-root"
SCRIPTS_DIR="$DIST_DIR/scripts"
COMPONENT_PKG="$DIST_DIR/Rockpile-component.pkg"
FINAL_PKG="$DIST_DIR/Rockpile-Installer.pkg"
DISTRIBUTION_XML="$DIST_DIR/distribution.xml"

echo "=== Rockpile Installer Build ==="

# Read version from project.yml (single source of truth)
VERSION=$(grep 'MARKETING_VERSION:' "$SCRIPT_DIR/project.yml" | head -1 | sed 's/.*: *"\(.*\)"/\1/')
if [ -z "$VERSION" ]; then
  echo "ERROR: Could not read MARKETING_VERSION from project.yml"
  exit 1
fi
echo "   Version: $VERSION"

# Step 1: Generate Xcode project
echo "[1/5] Generating Xcode project..."
cd "$SCRIPT_DIR"
xcodegen generate 2>/dev/null

# Step 2: Build Release
echo "[2/5] Building Release..."
xcodebuild -project Rockpile.xcodeproj \
  -scheme Rockpile \
  -configuration Release \
  clean build 2>&1 | grep -E "(error:|BUILD)" || true

APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/Rockpile-*/Build/Products/Release -name "Rockpile.app" -maxdepth 1 -type d 2>/dev/null | head -1)

if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
  echo "ERROR: Rockpile.app not found in Release build products"
  exit 1
fi

echo "   Found: $APP_PATH ($(du -sh "$APP_PATH" | cut -f1))"

# Step 2.5: Generate complete .icns (Xcode only generates partial sizes)
ICON_SRC="$SCRIPT_DIR/Rockpile/Assets.xcassets/AppIcon.appiconset/icon_1024.png"
if [ -f "$ICON_SRC" ]; then
    echo "[2.5/5] Generating complete .icns..."
    ICONSET_DIR="/tmp/Rockpile.iconset"
    rm -rf "$ICONSET_DIR" && mkdir -p "$ICONSET_DIR"
    sips -z 16 16     "$ICON_SRC" --out "$ICONSET_DIR/icon_16x16.png"      >/dev/null
    sips -z 32 32     "$ICON_SRC" --out "$ICONSET_DIR/icon_16x16@2x.png"   >/dev/null
    sips -z 32 32     "$ICON_SRC" --out "$ICONSET_DIR/icon_32x32.png"      >/dev/null
    sips -z 64 64     "$ICON_SRC" --out "$ICONSET_DIR/icon_32x32@2x.png"   >/dev/null
    sips -z 128 128   "$ICON_SRC" --out "$ICONSET_DIR/icon_128x128.png"    >/dev/null
    sips -z 256 256   "$ICON_SRC" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
    sips -z 256 256   "$ICON_SRC" --out "$ICONSET_DIR/icon_256x256.png"    >/dev/null
    sips -z 512 512   "$ICON_SRC" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
    sips -z 512 512   "$ICON_SRC" --out "$ICONSET_DIR/icon_512x512.png"    >/dev/null
    sips -z 1024 1024 "$ICON_SRC" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
    iconutil -c icns "$ICONSET_DIR" -o "${APP_PATH}/Contents/Resources/AppIcon.icns"
    rm -rf "$ICONSET_DIR"
fi

# Step 3: Stage files
echo "[3/5] Staging..."
rm -rf "$PKG_ROOT" "$SCRIPTS_DIR" "$COMPONENT_PKG" "$FINAL_PKG" "$DISTRIBUTION_XML"
mkdir -p "$PKG_ROOT/Applications" "$SCRIPTS_DIR"
cp -R "$APP_PATH" "$PKG_ROOT/Applications/Rockpile.app"

# Post-install: remove quarantine
cat > "$SCRIPTS_DIR/postinstall" << 'POSTINSTALL'
#!/bin/bash
xattr -cr /Applications/Rockpile.app 2>/dev/null || true
exit 0
POSTINSTALL
chmod +x "$SCRIPTS_DIR/postinstall"

# Step 4: Build component package
echo "[4/5] Building component package..."
pkgbuild \
  --root "$PKG_ROOT" \
  --identifier "com.rockpile.app" \
  --version "$VERSION" \
  --install-location "/" \
  --scripts "$SCRIPTS_DIR" \
  "$COMPONENT_PKG" >/dev/null 2>&1

# Distribution XML
cat > "$DISTRIBUTION_XML" << DISTXML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>Rockpile</title>
    <welcome mime-type="text/html"><![CDATA[
        <html>
        <body style="font-family: -apple-system, Helvetica; margin: 20px;">
        <h2>Rockpile</h2>
        <p>Rockpile Notch companion - animated pixel crayfish for your MacBook.</p>
        <p>This will install Rockpile.app to /Applications.</p>
        </body>
        </html>
    ]]></welcome>
    <conclusion mime-type="text/html"><![CDATA[
        <html>
        <body style="font-family: -apple-system, Helvetica; margin: 20px;">
        <h2>Installation Complete!</h2>
        <p>Open Rockpile from Applications, follow the setup wizard, then restart Rockpile.</p>
        </body>
        </html>
    ]]></conclusion>
    <options customize="never" require-scripts="false" hostArchitectures="arm64"/>
    <domains enable_anywhere="true" enable_currentUserHome="false" enable_localSystem="true"/>
    <os-version min="15.0"/>
    <choices-outline>
        <line choice="default">
            <line choice="com.rockpile.app"/>
        </line>
    </choices-outline>
    <choice id="default"/>
    <choice id="com.rockpile.app" visible="false">
        <pkg-ref id="com.rockpile.app"/>
    </choice>
    <pkg-ref id="com.rockpile.app" version="$VERSION" onConclusion="none">Rockpile-component.pkg</pkg-ref>
</installer-gui-script>
DISTXML

# Step 5: Build final product package
echo "[5/5] Building installer package..."
productbuild \
  --distribution "$DISTRIBUTION_XML" \
  --package-path "$DIST_DIR" \
  "$FINAL_PKG" >/dev/null 2>&1

# Clean up intermediates
rm -f "$COMPONENT_PKG" "$DISTRIBUTION_XML"
rm -rf "$PKG_ROOT" "$SCRIPTS_DIR"

echo ""
echo "=== Done ==="
PKG_SIZE=$(du -sh "$FINAL_PKG" | cut -f1)
echo "Installer: $FINAL_PKG ($PKG_SIZE)"
echo ""
echo "Note: This package is unsigned. Recipients need to:"
echo "  Right-click .pkg -> Open, or"
echo "  System Settings -> Privacy & Security -> Open Anyway"
