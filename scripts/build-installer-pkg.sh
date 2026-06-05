#!/usr/bin/env bash
# Build macOS release artefacts for the MRT2 AUv3 host app:
#   - .pkg installer (installs to /Applications and registers the AU extension)
#   - .dmg disk image (drag MRT2 (AU).app to Applications — no zip)
#
# Run from repo root after:
#   cmake --build build --target package_mrt2_au
#
# Usage:
#   ./scripts/build-installer-pkg.sh [--version 0.1.0] [--app path/to/MRT2\ \(AU\).app]
#   ./scripts/build-installer-pkg.sh --sign-app
#
# Output (under release-artifacts/ by default):
#   MRT2-AU3-<version>-macOS-Installer.pkg
#   MRT2-AU3-<version>-macOS.dmg

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

APP_BUNDLE_NAME="MRT2 (AU).app"
PKG_ID="com.audiohacking.mrt2-au3"
OUT_DIR="${OUT_DIR:-release-artifacts}"
SIGN_APP=false
PKG_VERSION=""
APP_PATH=""

while [ $# -gt 0 ]; do
  case "$1" in
    --sign-app)  SIGN_APP=true; shift ;;
    --version)   PKG_VERSION="$2"; shift 2 ;;
    --app)       APP_PATH="$2"; shift 2 ;;
    --out-dir)   OUT_DIR="$2"; shift 2 ;;
    -h|--help)
      sed -n '1,18p' "$0"
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [ -z "$PKG_VERSION" ]; then
  if git describe --tags --abbrev=0 >/dev/null 2>&1; then
    PKG_VERSION="$(git describe --tags --abbrev=0)"
  else
    PKG_VERSION="0.0.0-dev"
  fi
fi
# pkgbuild requires a numeric dotted version (strip leading v).
PKG_VERSION="${PKG_VERSION#v}"

if [ -z "$APP_PATH" ]; then
  APP_PATH="${REPO_ROOT}/build/dist/${APP_BUNDLE_NAME}"
fi

if [ ! -d "$APP_PATH" ]; then
  echo "Error: app bundle not found at: $APP_PATH" >&2
  echo "Build first:" >&2
  echo "  cmake --build build --target package_mrt2_au" >&2
  exit 1
fi

PKG_FILE="${OUT_DIR}/MRT2-AU3-${PKG_VERSION}-macOS-Installer.pkg"
DMG_FILE="${OUT_DIR}/MRT2-AU3-${PKG_VERSION}-macOS.dmg"
STAGING_APP="${OUT_DIR}/${APP_BUNDLE_NAME}"

mkdir -p "$OUT_DIR"
rm -rf "$STAGING_APP"
ditto "$APP_PATH" "$STAGING_APP"

if [ "$SIGN_APP" = true ]; then
  echo "Ad-hoc signing app bundle (including mlx.metallib)..."
  METALLIB="$(find "$STAGING_APP" -name mlx.metallib -print -quit || true)"
  if [ -n "$METALLIB" ]; then
    xcrun codesign --force --sign - "$METALLIB"
  fi
  APPEX="${STAGING_APP}/Contents/PlugIns/MRT2_AU.appex"
  if [ -d "$APPEX" ]; then
    xcrun codesign --force --sign - --entitlements "${REPO_ROOT}/Entitlements.plist" --generate-entitlement-der "$APPEX"
  fi
  xcrun codesign --force --sign - "$STAGING_APP"
fi

echo "Building .dmg: $DMG_FILE"
rm -f "$DMG_FILE"
hdiutil create \
  -volname "MRT2 AU3" \
  -srcfolder "$STAGING_APP" \
  -ov \
  -format UDZO \
  "$DMG_FILE"

echo "Building .pkg: $PKG_FILE"
PAYLOAD_DIR="$(mktemp -d)"
SCRIPTS_DIR="$(mktemp -d)"
trap 'rm -rf "$PAYLOAD_DIR" "$SCRIPTS_DIR"' EXIT

mkdir -p "${PAYLOAD_DIR}/Applications"
ditto "$STAGING_APP" "${PAYLOAD_DIR}/Applications/${APP_BUNDLE_NAME}"
cp "${SCRIPT_DIR}/pkg-postinstall" "${SCRIPTS_DIR}/postinstall"
chmod +x "${SCRIPTS_DIR}/postinstall"

pkgbuild \
  --root "$PAYLOAD_DIR" \
  --scripts "$SCRIPTS_DIR" \
  --identifier "$PKG_ID" \
  --version "$PKG_VERSION" \
  --install-location / \
  "$PKG_FILE"

echo ""
echo "Created:"
echo "  ${DMG_FILE}"
echo "  ${PKG_FILE} (version ${PKG_VERSION})"
echo ""
echo "Install with GUI: open \"${PKG_FILE}\""
echo "Install with CLI: sudo installer -pkg \"${PKG_FILE}\" -target /"
echo "Manual install:   open \"${DMG_FILE}\" and drag ${APP_BUNDLE_NAME} to Applications"
