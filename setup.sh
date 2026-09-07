#!/bin/bash

echo "📦 Installing Flutter..."

# Download Flutter
git clone --depth 1 --branch stable https://github.com/flutter/flutter.git flutter

# Add Flutter to PATH
export PATH="$PATH:$PWD/flutter/bin"

# Pre-download Flutter dependencies
flutter precache

# Skip Android to save time
flutter config --no-android

# ─── WEB CONFIGURATION ──────────────────────────────────────────────
echo "🌐 Configuring Flutter for Web..."

# ✅ FIX: Create web platform if it doesn't exist
if [ ! -d "web" ]; then
    echo "Creating web folder..."
    flutter create . --platforms=web
fi

# ─── BUILD WEB ─────────────────────────────────────────────────────
echo "🔨 Building Flutter Web..."

flutter pub get
flutter config --enable-web
flutter build web --release --verbose

echo "✅ Build complete!"
