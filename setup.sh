#!/bin/bash

echo "📦 Installing Flutter..."

# Download Flutter
git clone --depth 1 --branch stable https://github.com/flutter/flutter.git flutter

# Add Flutter to PATH
export PATH="$PATH:$PWD/flutter/bin"

echo "🔧 Flutter version:"
flutter --version

# Pre-download Flutter dependencies (web only to save time)
flutter precache --web

# ─── CREATE WEB FOLDER IF MISSING ────────────────────────────────
echo "🌐 Setting up web..."
if [ ! -d "web" ]; then
    flutter create . --platforms=web
else
    echo "✅ web folder exists"
fi

# ─── GET DEPENDENCIES ─────────────────────────────────────────────
echo "📦 Getting dependencies..."
flutter pub get

# ─── BUILD WEB ─────────────────────────────────────────────────────
echo "🔨 Building Flutter Web..."
flutter config --enable-web
flutter build web --release --no-wasm-dry-run

# ─── VERIFY BUILD ──────────────────────────────────────────────────
echo "📁 Build output:"
ls -la build/web/

# Check if main.dart.js exists
if [ -f "build/web/main.dart.js" ]; then
    echo "✅ main.dart.js generated successfully!"
    echo "📄 main.dart.js size: $(du -h build/web/main.dart.js | cut -f1)"
else
    echo "❌ ERROR: main.dart.js NOT generated!"
    echo "📁 build/web contents:"
    ls -la build/web/
    exit 1
fi

# ─── COPY HTML PAGES ──────────────────────────────────────────────
echo "📄 Copying HTML pages..."
cp -f index.html build/web/ 2>/dev/null || echo "⚠️ index.html not found"
cp -f splash.html build/web/ 2>/dev/null || echo "⚠️ splash.html not found"
cp -f onboarding.html build/web/ 2>/dev/null || echo "⚠️ onboarding.html not found"

echo "📁 Final build/web contents:"
ls -la build/web/

echo "✅ Build complete!"
