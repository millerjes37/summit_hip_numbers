#!/bin/bash
# Build script for macOS
# Creates a DMG bundle with all dependencies
# Run this on a macOS machine with Rust and FFmpeg installed

set -e  # Exit on error

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Summit Hip Numbers macOS Build ===${NC}"
echo "Current directory: $(pwd)"
echo ""

# Configuration
VARIANT="${1:-full}"  # Default to full if no argument provided
DIST_DIR="dist/macos-$VARIANT"
BUILD_LOG_DIR="build-logs"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="$BUILD_LOG_DIR/build_macos_${VARIANT}_${TIMESTAMP}.log"

# Create directories
mkdir -p "$BUILD_LOG_DIR"
mkdir -p "$DIST_DIR"

# Validate variant
if [[ "$VARIANT" != "full" && "$VARIANT" != "demo" ]]; then
    echo -e "${RED}Error: Invalid variant '$VARIANT'. Use 'full' or 'demo'.${NC}"
    exit 1
fi

# Function to log and display
log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

log "${YELLOW}Build log: $LOG_FILE${NC}"

# Get version
VERSION=$(if git describe --tags --exact-match 2>/dev/null; then 
    git describe --tags --exact-match | sed 's/^v//'
else 
    echo "dev-$(git rev-parse --short HEAD)"
fi)
log "${GREEN}Version: $VERSION${NC}"

# Step 1: Check dependencies
log ""
log "${YELLOW}[1/8] Checking dependencies...${NC}"

# Check for required tools
for tool in cargo rustc pkg-config; do
    if ! command -v $tool &> /dev/null; then
        log "${RED}Error: $tool not found${NC}"
        exit 1
    fi
done

# Check for FFmpeg
if ! pkg-config --exists libavutil libavcodec libavformat; then
    log "${RED}Error: FFmpeg not found. Install with: brew install ffmpeg${NC}"
    exit 1
fi

log "${GREEN}✓ All dependencies found${NC}"

# Step 2: Clean previous builds
log ""
log "${YELLOW}[2/8] Cleaning previous builds...${NC}"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"
log "${GREEN}✓ Created clean build directory${NC}"

# Step 3: Build application
log ""
log "${YELLOW}[3/8] Building application ($VARIANT)...${NC}"

# Set build command based on variant
if [ "$VARIANT" = "demo" ]; then
    APP_NAME="Summit HIP Numbers Demo"
    FEATURES="--features demo"
    log "Building demo version..."
else
    APP_NAME="Summit HIP Numbers"
    FEATURES=""
    log "Building full version..."
fi

# Configure bindgen to prevent looking in /usr/include
log "Configuring bindgen environment..."

# Find FFmpeg installation via pkg-config
FFMPEG_INCLUDE_DIR=$(pkg-config --variable=includedir libavutil)
if [ -z "$FFMPEG_INCLUDE_DIR" ]; then
    FFMPEG_INCLUDE_DIR="/opt/homebrew/include"
fi
log "FFmpeg headers: $FFMPEG_INCLUDE_DIR"

# Find clang builtin headers
CLANG_BUILTIN_INCLUDE=$(find /Library/Developer/CommandLineTools/usr/lib/clang /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/clang -type d -name include 2>/dev/null | head -n1)
if [ -z "$CLANG_BUILTIN_INCLUDE" ]; then
    # Try homebrew clang
    CLANG_BUILTIN_INCLUDE=$(find /opt/homebrew/opt/llvm/lib/clang -type d -name include 2>/dev/null | head -n1)
fi
log "Clang builtin headers: $CLANG_BUILTIN_INCLUDE"

# Configure bindgen environment
# Find the macOS SDK path
MACOS_SDK_PATH=""
if [ -d "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk" ]; then
    MACOS_SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
elif [ -d "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk" ]; then
    MACOS_SDK_PATH="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
fi

log "macOS SDK: $MACOS_SDK_PATH"

# Configure bindgen to use macOS SDK with system headers
# The order is important: clang builtins first, then SDK, then FFmpeg
export BINDGEN_EXTRA_CLANG_ARGS=""
if [ -n "$CLANG_BUILTIN_INCLUDE" ]; then
    export BINDGEN_EXTRA_CLANG_ARGS="-I$CLANG_BUILTIN_INCLUDE"
fi
if [ -n "$MACOS_SDK_PATH" ]; then
    export BINDGEN_EXTRA_CLANG_ARGS="$BINDGEN_EXTRA_CLANG_ARGS -isysroot $MACOS_SDK_PATH"
fi
export BINDGEN_EXTRA_CLANG_ARGS="$BINDGEN_EXTRA_CLANG_ARGS -I$FFMPEG_INCLUDE_DIR"

log "BINDGEN_EXTRA_CLANG_ARGS=$BINDGEN_EXTRA_CLANG_ARGS"

# Build with cargo
cargo build --release --package summit_hip_numbers $FEATURES 2>&1 | tee -a "$LOG_FILE"

if [ ! -f "target/release/summit_hip_numbers" ]; then
    log "${RED}Error: Build failed - binary not found${NC}"
    exit 1
fi

log "${GREEN}✓ Build completed successfully${NC}"

# Step 4: Create app bundle structure
log ""
log "${YELLOW}[4/8] Creating app bundle...${NC}"

BUNDLE_PATH="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$BUNDLE_PATH/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"

# Create directories
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"
mkdir -p "$FRAMEWORKS_DIR"

# Copy binary
cp "target/release/summit_hip_numbers" "$MACOS_DIR/summit_hip_numbers"
chmod +x "$MACOS_DIR/summit_hip_numbers"
log "${GREEN}✓ Copied binary${NC}"

# Step 5: Create Info.plist
log ""
log "${YELLOW}[5/8] Creating Info.plist...${NC}"

cat > "$CONTENTS_DIR/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>summit_hip_numbers</string>
    <key>CFBundleIdentifier</key>
    <string>com.summit.hip-numbers$([ "$VARIANT" = "demo" ] && echo "-demo")</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.13</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.video</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSCameraUsageDescription</key>
    <string>This app needs camera access for video playback.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>This app needs microphone access for audio recording.</string>
</dict>
</plist>
EOF

log "${GREEN}✓ Created Info.plist${NC}"

# Step 6: Copy resources
log ""
log "${YELLOW}[6/8] Copying resources...${NC}"

# Copy configuration
if [ -f "config.toml" ]; then
    cp "config.toml" "$RESOURCES_DIR/"
    log "  ✓ config.toml"
elif [ -f "assets/config.toml" ]; then
    cp "assets/config.toml" "$RESOURCES_DIR/"
    log "  ✓ config.toml (from assets)"
fi

# Copy asset directories
for dir in videos splash logo; do
    if [ -d "assets/$dir" ]; then
        cp -r "assets/$dir" "$RESOURCES_DIR/"
        log "  ✓ $dir/"
    elif [ -d "$dir" ]; then
        cp -r "$dir" "$RESOURCES_DIR/"
        log "  ✓ $dir/"
    fi
done

# Create icon (placeholder if not exists)
if [ -f "assets/icon.icns" ]; then
    cp "assets/icon.icns" "$RESOURCES_DIR/AppIcon.icns"
    log "  ✓ AppIcon.icns"
else
    # Create a basic icon file
    touch "$RESOURCES_DIR/AppIcon.icns"
    log "  ✓ Created placeholder AppIcon.icns"
fi

# Step 7: Bundle FFmpeg frameworks (optional)
log ""
log "${YELLOW}[7/8] Checking FFmpeg dependencies...${NC}"

# Get FFmpeg location from pkg-config
FFMPEG_PREFIX=$(pkg-config --variable=prefix libavutil)
if [ -n "$FFMPEG_PREFIX" ]; then
    log "FFmpeg found at: $FFMPEG_PREFIX"
    
    # Note: Full framework embedding would require more complex bundling
    # For now, we'll rely on system FFmpeg installation
    log "${YELLOW}Note: This build requires FFmpeg to be installed on the target system${NC}"
    log "To create a fully portable bundle, consider using dylibbundler with embedded frameworks"
fi

# Step 8: Sign the bundle (if certificates available)
log ""
log "${YELLOW}[8/8] Code signing...${NC}"

if security find-identity -p codesigning -v | grep -q "Developer ID Application"; then
    # Sign the bundle
    codesign --force --deep --sign - "$BUNDLE_PATH" 2>&1 | tee -a "$LOG_FILE"
    log "${GREEN}✓ Bundle signed${NC}"
else
    log "${YELLOW}Warning: No signing identity found. Bundle will not be signed.${NC}"
    log "For distribution, you'll need to sign with: codesign --force --deep --sign 'Developer ID' '$BUNDLE_PATH'"
fi

# Create DMG (optional)
log ""
log "${YELLOW}Creating DMG...${NC}"

DMG_NAME="summit_hip_numbers_macos_${VARIANT}_${VERSION}.dmg"

# Try to use create-dmg if available
if command -v create-dmg &> /dev/null; then
    create-dmg \
        --volname "$APP_NAME" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "$APP_NAME.app" 150 150 \
        --hide-extension "$APP_NAME.app" \
        --app-drop-link 450 150 \
        --no-internet-enable \
        "$DIST_DIR/$DMG_NAME" \
        "$DIST_DIR" 2>&1 | tee -a "$LOG_FILE"
else
    # Fallback to hdiutil
    hdiutil create -volname "$APP_NAME" -srcfolder "$DIST_DIR" -ov -format UDZO "$DIST_DIR/$DMG_NAME" 2>&1 | tee -a "$LOG_FILE"
fi

if [ -f "$DIST_DIR/$DMG_NAME" ]; then
    DMG_SIZE=$(du -h "$DIST_DIR/$DMG_NAME" | cut -f1)
    log "${GREEN}✓ Created DMG: $DMG_NAME ($DMG_SIZE)${NC}"
else
    log "${YELLOW}Warning: DMG creation failed${NC}"
fi

# Create build manifest
log ""
log "${YELLOW}Creating build manifest...${NC}"

cat > "$DIST_DIR/BUILD_MANIFEST.txt" << EOF
================================
Summit HIP Numbers - macOS Build
================================
Variant: $VARIANT
Version: $VERSION
Build Date: $(date +"%Y-%m-%d %H:%M:%S")
Commit: $(git rev-parse HEAD 2>/dev/null || echo 'unknown')
Architecture: $(uname -m)

================================
Build Contents
================================
EOF

find "$BUNDLE_PATH" -type f | while read file; do
    echo "$(basename "$file") ($(stat -f%z "$file") bytes)" >> "$DIST_DIR/BUILD_MANIFEST.txt"
done

log "${GREEN}✓ Created build manifest${NC}"

# Summary
log ""
log "${GREEN}================================${NC}"
log "${GREEN}  Build Complete!${NC}"
log "${GREEN}================================${NC}"
log "Application: $BUNDLE_PATH"
if [ -f "$DIST_DIR/$DMG_NAME" ]; then
    log "DMG: $DIST_DIR/$DMG_NAME"
fi
log ""
log "To run: open '$BUNDLE_PATH'"
log "To distribute: Share the DMG file"

exit 0