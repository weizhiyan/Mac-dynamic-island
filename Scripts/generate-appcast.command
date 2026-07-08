#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-1.0.1}"
REPO="${REPO:-weizhiyan/Mac-dynamic-island}"
PKG="$ROOT_DIR/Release/Mac-Dynamic-Island-$VERSION.pkg"
INTEL_PKG="$ROOT_DIR/Release/Mac-Dynamic-Island-$VERSION-intel.pkg"
APPCAST_PKG_NAME="Mac-Dynamic-Island-$VERSION-Apple-Silicon.pkg"
APPCAST_INTEL_PKG_NAME="Mac-Dynamic-Island-$VERSION-Intel.pkg"
NOTES="$ROOT_DIR/Docs/releases/v$VERSION.md"
APPCAST="$ROOT_DIR/appcast.xml"
DOWNLOAD_PREFIX="${DOWNLOAD_PREFIX:-https://github.com/$REPO/releases/download/v$VERSION/}"

cd "$ROOT_DIR"

if [[ ! -f "$PKG" ]]; then
  echo "Missing $PKG. Building it now..."
  VERSION="$VERSION" ./Scripts/build-pkg.command
fi

if [[ ! -f "$INTEL_PKG" ]]; then
  echo "Missing $INTEL_PKG. Building it now..."
  VERSION="$VERSION" BUILD_ARCH=x86_64 ./Scripts/build-pkg.command
fi

if [[ ! -f "$NOTES" ]]; then
  echo "Missing release notes: $NOTES"
  exit 1
fi

SIGN_UPDATE=""
for candidate in \
  "$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/sign_update" \
  "$ROOT_DIR/.build/checkouts/Sparkle/sign_update"; do
  if [[ -x "$candidate" ]]; then
    SIGN_UPDATE="$candidate"
    break
  fi
done

if [[ -z "$SIGN_UPDATE" ]]; then
  echo "Could not find Sparkle sign_update. Run 'swift build' first."
  exit 1
fi

sign_package() {
  local package_path="$1"
  if [[ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]]; then
    printf "%s" "$SPARKLE_ED_PRIVATE_KEY" | "$SIGN_UPDATE" --ed-key-file - "$package_path"
  else
    "$SIGN_UPDATE" "$package_path"
  fi
}

ARM_SIGNATURE_AND_LENGTH="$(sign_package "$PKG")"
INTEL_SIGNATURE_AND_LENGTH="$(sign_package "$INTEL_PKG")"
PUB_DATE="$(LC_ALL=C date '+%a, %d %b %Y %H:%M:%S %z')"
BUILD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ROOT_DIR/Build/灵动岛.app/Contents/Info.plist" 2>/dev/null || echo "$VERSION")"
RELEASE_NOTES="$(sed 's/]]>/]]]]><![CDATA[>/g' "$NOTES")"

cat > "$APPCAST" <<EOF
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
    <channel>
        <title>灵动岛</title>
        <item>
            <title>$VERSION Apple Silicon</title>
            <pubDate>$PUB_DATE</pubDate>
            <sparkle:version>$BUILD_VERSION</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>10.13</sparkle:minimumSystemVersion>
            <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
            <description sparkle:format="markdown"><![CDATA[$RELEASE_NOTES
]]></description>
            <enclosure url="${DOWNLOAD_PREFIX}${APPCAST_PKG_NAME}" $ARM_SIGNATURE_AND_LENGTH type="application/octet-stream"/>
        </item>
        <item>
            <title>$VERSION Intel</title>
            <pubDate>$PUB_DATE</pubDate>
            <sparkle:version>$BUILD_VERSION</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>10.13</sparkle:minimumSystemVersion>
            <sparkle:hardwareRequirements>x86_64</sparkle:hardwareRequirements>
            <description sparkle:format="markdown"><![CDATA[$RELEASE_NOTES
]]></description>
            <enclosure url="${DOWNLOAD_PREFIX}${APPCAST_INTEL_PKG_NAME}" $INTEL_SIGNATURE_AND_LENGTH type="application/octet-stream"/>
        </item>
    </channel>
</rss>
EOF

echo "已生成：$APPCAST"
