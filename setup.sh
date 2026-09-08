#!/bin/bash

echo "🚀 AURA Chat Web - Build Setup"

# ─── CREATE ASSET DIRECTORIES ──────────────────────────────────────
echo "📁 Creating asset directories..."
mkdir -p assets/images
mkdir -p assets/emojis
mkdir -p assets/audio

# ─── CREATE API CONFIG ─────────────────────────────────────────────
echo "🔑 Creating API config..."
cat > lib/services/api_config.dart << 'EOF' 2>/dev/null || echo "⚠️ No Dart folder found"
class ApiConfig {
  static const String geminiApiKey = 'YOUR_GEMINI_API_KEY';
}
EOF

# ─── CREATE CLOUDINARY CONFIG ──────────────────────────────────────
echo "☁️ Creating Cloudinary config..."
cat > lib/services/cloudinary_config.dart << 'EOF' 2>/dev/null || echo "⚠️ No Dart folder found"
class CloudinaryConfig {
  static const String cloudName = 'YOUR_CLOUDINARY_NAME';
  static const String apiKey = 'YOUR_CLOUDINARY_API_KEY';
  static const String apiSecret = 'YOUR_CLOUDINARY_API_SECRET';
}
EOF

# ─── COPY HTML FILES TO BUILD FOLDER ──────────────────────────────
echo "📄 Copying HTML files..."
mkdir -p build
cp -f index.html build/ 2>/dev/null || echo "⚠️ index.html not found"
cp -f splash.html build/ 2>/dev/null || echo "⚠️ splash.html not found"
cp -f onboarding.html build/ 2>/dev/null || echo "⚠️ onboarding.html not found"
cp -f email_verification.html build/ 2>/dev/null || echo "⚠️ email_verification.html not found"
cp -f setup_profile.html build/ 2>/dev/null || echo "⚠️ setup_profile.html not found"
cp -f chats.html build/ 2>/dev/null || echo "⚠️ chats.html not found"
cp -f chat.html build/ 2>/dev/null || echo "⚠️ chat.html not found"
cp -f channel_chat.html build/ 2>/dev/null || echo "⚠️ channel_chat.html not found"
cp -f create_channel.html build/ 2>/dev/null || echo "⚠️ create_channel.html not found"
cp -f channel_info.html build/ 2>/dev/null || echo "⚠️ channel_info.html not found"

# ─── COPY ASSETS ────────────────────────────────────────────────────
echo "📁 Copying assets..."
cp -r assets build/ 2>/dev/null || echo "⚠️ assets folder not found"

echo "✅ Build complete!"
echo "📁 Output: build/"
ls -la build/
