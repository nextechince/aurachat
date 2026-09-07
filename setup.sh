#!/bin/bash

# ─── INSTALL FLUTTER ──────────────────────────────────────────────
echo "📦 Installing Flutter..."

# Download Flutter
git clone --depth 1 --branch stable https://github.com/flutter/flutter.git flutter

# Add Flutter to PATH
export PATH="$PATH:$PWD/flutter/bin"

# Pre-download Flutter dependencies
flutter precache

# ─── BUILD WEB ─────────────────────────────────────────────────────
echo "🔨 Building Flutter Web..."

flutter pub get
flutter config --enable-web
flutter build web --release

echo "✅ Build complete!"
