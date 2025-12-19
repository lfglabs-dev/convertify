#!/usr/bin/env bash

# Build script for Convertify.app
# Uses Xcode build pipeline so AppIcon.icon is used directly (Liquid Glass).

set -euo pipefail

APP_NAME="Convertify"
APP_BUNDLE="$APP_NAME.app"
DERIVED_DATA_DIR=".build/xcode-deriveddata"
CONFIGURATION="Release"

echo "🔨 Building $APP_NAME ($CONFIGURATION) via xcodebuild..."

xcodebuild \
  -project "Convertify.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  build

BUILT_APP="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/$APP_BUNDLE"

if [ ! -d "$BUILT_APP" ]; then
  echo "❌ Build succeeded but app not found at: $BUILT_APP" >&2
  exit 1
fi

echo "📦 Copying app bundle..."

# Remove old bundle if exists
if [ -e "$APP_BUNDLE" ]; then
  rm -rf "$APP_BUNDLE"
fi

# Copy the built app locally
cp -R "$BUILT_APP" "$APP_BUNDLE"

echo "✅ App bundle created: $APP_BUNDLE"
echo "🚀 Launching $APP_NAME..."
open "$APP_BUNDLE"
