#!/bin/bash
# Build script for Windows using MSYS2 - FIXED VERSION
# This script runs entirely within MSYS2 environment where all paths work correctly

set -e  # Exit on error

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Summit Hip Numbers Windows Build (MSYS2 - Fixed) ===${NC}"
echo "Current directory: $(pwd)"
echo ""

# Configuration
VARIANT="${1:-full}"  # Default to full if no argument provided
DIST_DIR="dist/$VARIANT"
EXE_NAME="summit_hip_numbers.exe"
TARGET_DIR="target/release"
ZIP_NAME="summit_hip_numbers_${VARIANT}_portable.zip"
BUILD_LOG_DIR="build-logs"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="$BUILD_LOG_DIR/build_${VARIANT}_${TIMESTAMP}.log"

# Create directories
mkdir -p "$BUILD_LOG_DIR"

# Set build flags based on variant
if [ "$VARIANT" = "demo" ]; then
    CARGO_FLAGS="--features demo"
    EXE_OUTPUT_NAME="summit_hip_numbers_demo.exe"
else
    CARGO_FLAGS=""
    EXE_OUTPUT_NAME="$EXE_NAME"
fi

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

# Step 0: Set up MSYS2 environment properly
log ""
log "${YELLOW}=== Setting up MSYS2 environment ===${NC}"

# Ensure we're using the right MSYS2 environment
if [ -z "$MSYSTEM" ]; then
    export MSYSTEM=MINGW64
fi

# Set proper paths
export MSYSTEM_PREFIX="/mingw64"
export PATH="$MSYSTEM_PREFIX/bin:$PATH"
export PKG_CONFIG_PATH="$MSYSTEM_PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH"

log "MSYSTEM: $MSYSTEM"
log "MSYSTEM_PREFIX: $MSYSTEM_PREFIX"
log "PKG_CONFIG_PATH: $PKG_CONFIG_PATH"

# Step 1: Create clean dist directory
log ""
log "${YELLOW}=== Creating distribution directory ===${NC}"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"
log "${GREEN}✓ Created $DIST_DIR${NC}"

# Step 2: Build application
log ""
log "${YELLOW}=== Building application ($VARIANT) ===${NC}"
if [ "$VARIANT" = "demo" ]; then
    log "Building with demo features..."
    cargo build --release --features demo --verbose 2>&1 | tee -a "$LOG_FILE"
else
    log "Building full version..."
    cargo build --release --verbose 2>&1 | tee -a "$LOG_FILE"
fi

if [ $? -ne 0 ]; then
    log "${RED}ERROR: Build failed${NC}"
    exit 1
fi

# Step 3: Copy executable
log ""
log "${YELLOW}=== Copying executable ===${NC}"
if [ -f "$TARGET_DIR/$EXE_NAME" ]; then
    cp "$TARGET_DIR/$EXE_NAME" "$DIST_DIR/$EXE_OUTPUT_NAME"
    exe_size=$(du -h "$DIST_DIR/$EXE_OUTPUT_NAME" | cut -f1)
    log "${GREEN}✓ Copied $EXE_OUTPUT_NAME ($exe_size)${NC}"

# Create version file
log ""
log "${YELLOW}=== Creating version file ===${NC}"
VERSION_FILE="$DIST_DIR/VERSION.txt"
echo "Build: $(date -u +'%Y-%m-%d %H:%M:%S UTC')" > "$VERSION_FILE"
echo "Git Commit: $(git rev-parse HEAD 2>/dev/null || echo 'unknown')" >> "$VERSION_FILE"
echo "Variant: $VARIANT" >> "$VERSION_FILE"
log "${GREEN}✓ Created version file${NC}"
else
    log "${RED}ERROR: Executable not found at $TARGET_DIR/$EXE_NAME${NC}"
    exit 1
fi

# Step 4: Copy GStreamer DLLs (comprehensive)
log ""
log "${YELLOW}=== Copying GStreamer DLLs ===${NC}"

# Create bin directory for DLLs
mkdir -p "$DIST_DIR/bin"

# Function to copy DLL if it exists
copy_dll() {
    local dll_path="$1"
    local dest_dir="$2"
    if [ -f "$dll_path" ]; then
        cp "$dll_path" "$dest_dir/" 2>/dev/null || true
        return 0
    fi
    return 1
}

# Copy all DLLs from mingw64/bin that we need
log "Copying essential DLLs..."
dll_count=0

# Use a more comprehensive approach - copy all potentially needed DLLs
for dll in "$MSYSTEM_PREFIX/bin/"*.dll; do
    if [ -f "$dll" ]; then
        filename=$(basename "$dll")
        # Filter for essential DLLs
        case "$filename" in
            libgst*.dll|libglib*.dll|libgobject*.dll|libgio*.dll|libgmodule*.dll|\
            libwinpthread*.dll|libgcc*.dll|libstdc++*.dll|libiconv*.dll|libintl*.dll|\
            zlib*.dll|libffi*.dll|libpcre*.dll|libbz2*.dll|libfreetype*.dll|\
            libharfbuzz*.dll|libpng*.dll|liborc*.dll|libopus*.dll|libvorbis*.dll|\
            libogg*.dll)
                if copy_dll "$dll" "$DIST_DIR/bin"; then
                    ((dll_count++))
                fi
                ;;
        esac
    fi
done

log "${GREEN}✓ Copied $dll_count essential DLLs${NC}"

# Step 5: Copy GStreamer plugins
log ""
log "${YELLOW}=== Copying GStreamer plugins ===${NC}"

PLUGIN_DIR="$DIST_DIR/lib/gstreamer-1.0"
mkdir -p "$PLUGIN_DIR"

PLUGIN_COUNT=0
PLUGIN_SRC="$MSYSTEM_PREFIX/lib/gstreamer-1.0"

if [ -d "$PLUGIN_SRC" ]; then
    for plugin in "$PLUGIN_SRC/"*.dll; do
        if [ -f "$plugin" ]; then
            cp "$plugin" "$PLUGIN_DIR/" 2>/dev/null || true
            ((PLUGIN_COUNT++))
        fi
    done
    log "${GREEN}✓ Copied $PLUGIN_COUNT GStreamer plugins${NC}"
else
    log "${YELLOW}Warning: GStreamer plugin directory not found at $PLUGIN_SRC${NC}"
fi

# Step 6: Copy config and assets
log ""
log "${YELLOW}=== Copying configuration and assets ===${NC}"

# Copy config file
if [ -f "config.toml" ]; then
    cp "config.toml" "$DIST_DIR/"
    log "  ✓ config.toml"
elif [ -f "assets/config.toml" ]; then
    cp "assets/config.toml" "$DIST_DIR/"
    log "  ✓ config.toml (from assets)"
fi

# Copy asset directories
for dir in videos splash logo; do
    if [ -d "assets/$dir" ]; then
        mkdir -p "$DIST_DIR/$dir"
        cp -r "assets/$dir"/* "$DIST_DIR/$dir/" 2>/dev/null || true
        log "  ✓ $dir/"
    elif [ -d "$dir" ]; then
        mkdir -p "$DIST_DIR/$dir"
        cp -r "$dir"/* "$DIST_DIR/$dir/" 2>/dev/null || true
        log "  ✓ $dir/"
    fi
done

# Step 7: Create launcher script
log ""
log "${YELLOW}=== Creating launcher script ===${NC}"
cat > "$DIST_DIR/run.bat" << EOF
@echo off
REM Summit Hip Numbers Media Player Launcher

echo Starting Summit Hip Numbers Media Player...

REM Set GStreamer environment variables for portable version
set GST_PLUGIN_PATH=%~dp0lib\\gstreamer-1.0
set GST_PLUGIN_SYSTEM_PATH=%~dp0lib\\gstreamer-1.0
set PATH=%~dp0bin;%~dp0;%PATH%

REM Change to the application directory
cd /d "%~dp0"

REM Run the application
"%~dp0$EXE_OUTPUT_NAME"

if errorlevel 1 (
    echo.
    echo Application exited with error code %errorlevel%
    pause
)
EOF
log "${GREEN}✓ Created run.bat${NC}"

# Step 8: Create README
log ""
log "${YELLOW}=== Creating README ===${NC}"
cat > "$DIST_DIR/README.txt" << EOF
Summit Hip Numbers Media Player - $VARIANT Version
===============================================

This is a portable version of the Summit Hip Numbers Media Player that includes all necessary dependencies.

To run the application:
1. Double-click "run.bat" (Windows batch file)
   OR
2. Run $EXE_OUTPUT_NAME directly

Files:
- $EXE_OUTPUT_NAME: Main application
- config.toml: Configuration file
- videos/: Directory for your video files
- splash/: Directory for splash images
- bin/: GStreamer runtime DLLs
- lib/gstreamer-1.0/: GStreamer plugins
- run.bat: Launcher script

Configuration:
Edit config.toml to customize settings like video directory path and splash screen options.
Run with --config flag to open configuration GUI.

Adding Videos:
Place your MP4 video files in the "videos" directory. Files will be automatically sorted alphabetically and assigned hip numbers (001, 002, 003...).

System Requirements:
- Windows 10 or later (64-bit)
- 4GB RAM minimum
- DirectX 11 compatible graphics

For support: support@example.com
For more information: https://github.com/millerjes37/summit_hip_numbers
EOF
log "${GREEN}✓ Created README.txt${NC}"

# Step 9: Summary and verification
log ""
log "${YELLOW}=== Build Summary ===${NC}"

# Count files and size
TOTAL_FILES=$(find "$DIST_DIR" -type f | wc -l)
TOTAL_SIZE=$(du -sh "$DIST_DIR" | cut -f1)

log "${GREEN}✓ Distribution created successfully${NC}"
log "  Location: $DIST_DIR"
log "  Total files: $TOTAL_FILES"
log "  Total size: $TOTAL_SIZE"
log "  DLLs bundled: $dll_count"
log "  Plugins bundled: $PLUGIN_COUNT"

# List contents
log ""
log "Distribution contents:"
ls -la "$DIST_DIR" | head -20

log ""
log "${GREEN}================================${NC}"
log "${GREEN}  Build Complete!${NC}"
log "${GREEN}================================${NC}"
log "Distribution ready at: $DIST_DIR"
log "To create ZIP: cd dist && zip -r summit_hip_numbers_${VARIANT}_portable.zip $VARIANT"

exit 0