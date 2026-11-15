#!/usr/bin/env bash
set -euo pipefail

echo "==> Building Palle in Release mode..."
swift build -c release

APP_DIR="build/Palle.app"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp ".build/release/Palle" "$APP_DIR/Contents/MacOS/Palle"
cp "Info.plist" "$APP_DIR/Contents/Info.plist"

echo "==> Successfully created macOS App Bundle at: $APP_DIR"
echo "==> Run it with: open $APP_DIR"
