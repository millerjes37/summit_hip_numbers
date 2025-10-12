#!/bin/bash
# Build script for Windows using MSYS2
# This script runs entirely within MSYS2 environment where all paths work correctly

set -e  # Exit on error
set +o pipefail  # Don't fail on pipe errors (for grep)

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Summit Hip Numbers Windows Build (MSYS2) ===${NC}"
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

# Step 1: Create clean dist directory
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

# Step 4: Copy GStreamer DLLs (selective)
log ""
log "${YELLOW}=== Copying essential DLLs ===${NC}"

# Debug: Show environment
log "Debug: MSYSTEM=$MSYSTEM"
log "Debug: MSYSTEM_PREFIX=$MSYSTEM_PREFIX"
log "Debug: PATH=$PATH"
log "Debug: Current directory: $(pwd)"

# Workaround for GStreamer PATH regression in MSYS2
export PYTHONLEGACYWINDOWSDLLLOADING=1

# Verify GStreamer packages are installed
log "Debug: Verifying GStreamer packages:"
pacman -Qs mingw-w64-x86_64-gstreamer | head -10 || true

# List available GStreamer DLLs for debugging
log "Debug: Available DLL files:"
for search_path in "/mingw64/bin" "$MSYSTEM_PREFIX/bin" "/c/msys64/mingw64/bin" "/usr/bin"; do
    if [ -d "$search_path" ]; then
        log "  Checking $search_path:"
        # First show GStreamer executables
        log "    GStreamer executables:"
        ls -la "$search_path"/gst-*.exe 2>/dev/null | head -5 || log "      No gst-*.exe found"
        
        # Show all libgst* DLLs (this catches libgstreamer-1.0-0.dll)
        log "    GStreamer DLLs (libgst*):"
        ls -la "$search_path"/libgst*.dll 2>/dev/null | head -10 || log "      No libgst*.dll found"
        
        # Show GLib DLLs
        log "    GLib DLLs:"
        ls -la "$search_path"/libglib*.dll 2>/dev/null | head -5 || log "      No libglib*.dll found"
        ls -la "$search_path"/libgobject*.dll 2>/dev/null | head -5 || log "      No libgobject*.dll found"
        
        # Count total DLLs in directory
        dll_count=$(ls "$search_path"/*.dll 2>/dev/null | wc -l)
        log "    Total DLLs in directory: $dll_count"
    fi
done

# Use pacman to find where GStreamer DLLs are installed
log "Debug: Files installed by gstreamer package:"
if command -v pacman >/dev/null 2>&1; then
    # Temporarily disable exit on error for this command
    set +e
    pacman_output=$(pacman -Ql mingw-w64-x86_64-gstreamer 2>/dev/null | grep "\.dll$" | head -10)
    pacman_exit_code=$?
    set -e
    
    if [ $pacman_exit_code -eq 0 ] && [ -n "$pacman_output" ]; then
        echo "$pacman_output" | while IFS= read -r line; do
            log "  $line"
        done
    else
        log "  Could not query package files (exit code: $pacman_exit_code)"
    fi
else
    log "  pacman command not found, skipping package query"
fi

# Define essential DLLs
ESSENTIAL_DLLS=(
    # GLib/GObject
    "libglib-2.0-0.dll"
    "libgobject-2.0-0.dll"
    "libgio-2.0-0.dll"
    "libgmodule-2.0-0.dll"
    
    # GStreamer core
    "libgstreamer-1.0-0.dll"
    "libgstbase-1.0-0.dll"
    "libgstapp-1.0-0.dll"
    "libgstvideo-1.0-0.dll"
    "libgstaudio-1.0-0.dll"
    "libgsttag-1.0-0.dll"
    "libgstpbutils-1.0-0.dll"
    "libgstrtp-1.0-0.dll"
    "libgstrtsp-1.0-0.dll"
    "libgstsdp-1.0-0.dll"
    "libgstnet-1.0-0.dll"
    "libgstcontroller-1.0-0.dll"
    
    # System dependencies
    "libintl-8.dll"
    "libwinpthread-1.dll"
    "libiconv-2.dll"
    "libffi-*.dll"
    "libpcre2-8-0.dll"
    "zlib1.dll"
    
    # C++ runtime
    "libgcc_s_seh-1.dll"
    "libstdc++-6.dll"
    
    # Additional media libraries
    "liborc-0.4-0.dll"
    "libopus-0.dll"
    "libvorbis-0.dll"
    "libvorbisenc-2.dll"
    "libogg-0.dll"
)

# Copy essential DLLs
dll_count=0
# Search in multiple locations
DLL_SEARCH_PATHS=(
    "/mingw64/bin"
    "$MSYSTEM_PREFIX/bin"
    "/c/msys64/mingw64/bin"
    "/usr/bin"
)

for dll in "${ESSENTIAL_DLLS[@]}"; do
    dll_found=false
    for search_path in "${DLL_SEARCH_PATHS[@]}"; do
        if [ -d "$search_path" ]; then
            # Handle wildcards properly - use find for better wildcard support
            if [[ "$dll" == *"*"* ]]; then
                # Contains wildcard
                while IFS= read -r file; do
                    if [ -f "$file" ]; then
                        cp "$file" "$DIST_DIR/" 2>/dev/null || true
                        ((dll_count++))
                        log "  Copied: $(basename "$file") from $search_path"
                        dll_found=true
                        break
                    fi
                done < <(find "$search_path" -maxdepth 1 -name "$dll" -type f 2>/dev/null)
                if [ "$dll_found" = true ]; then
                    break
                fi
            else
                # No wildcard - direct check
                if [ -f "$search_path/$dll" ]; then
                    cp "$search_path/$dll" "$DIST_DIR/" 2>/dev/null || true
                    ((dll_count++))
                    log "  Copied: $dll from $search_path"
                    dll_found=true
                    break
                fi
            fi
        fi
    done
    if [ "$dll_found" = false ]; then
        log "  ${YELLOW}Warning: $dll not found in any search path${NC}"
    fi
done

log "${GREEN}✓ Copied $dll_count essential DLLs${NC}"

# Step 5: Verify critical DLLs
log ""
log "${YELLOW}=== Verifying critical DLLs ===${NC}"
critical_dlls=(
    "libglib-2.0-0.dll"
    "libgobject-2.0-0.dll"
    "libgio-2.0-0.dll"
    "libgstapp-1.0-0.dll"
    "libgstreamer-1.0-0.dll"
    "libgstvideo-1.0-0.dll"
    "libgstbase-1.0-0.dll"
    "libgstaudio-1.0-0.dll"
)

missing_dlls=()
for dll in "${critical_dlls[@]}"; do
    if [ -f "$DIST_DIR/$dll" ]; then
        log "  ${GREEN}✓ $dll${NC}"
    else
        log "  ${RED}✗ $dll MISSING${NC}"
        missing_dlls+=("$dll")
    fi
done

if [ ${#missing_dlls[@]} -gt 0 ]; then
    log "${YELLOW}WARNING: Missing critical DLLs: ${missing_dlls[*]}${NC}"
    log "${YELLOW}Attempting fallback: copying all DLLs from /mingw64/bin${NC}"
    
    # Fallback: If critical DLLs are missing, copy ALL DLLs from mingw64/bin
    # This is more aggressive but ensures we don't miss renamed or version-specific DLLs
    fallback_dll_count=0
    if [ -d "/mingw64/bin" ]; then
        for dll_file in /mingw64/bin/*.dll; do
            if [ -f "$dll_file" ]; then
                filename=$(basename "$dll_file")
                # Skip if already exists
                if [ ! -f "$DIST_DIR/$filename" ]; then
                    cp "$dll_file" "$DIST_DIR/" 2>/dev/null || true
                    ((fallback_dll_count++))
                fi
            fi
        done
        log "  Copied $fallback_dll_count additional DLLs as fallback"
        
        # Re-check critical DLLs after fallback
        log "  Re-checking critical DLLs after fallback..."
        still_missing=()
        for dll in "${critical_dlls[@]}"; do
            if [ ! -f "$DIST_DIR/$dll" ]; then
                still_missing+=("$dll")
            fi
        done
        
        if [ ${#still_missing[@]} -eq 0 ]; then
            log "${GREEN}✓ All critical DLLs found after fallback${NC}"
        else
            log "${YELLOW}Still missing after fallback: ${still_missing[*]}${NC}"
            log "${YELLOW}The application may not run properly without these DLLs.${NC}"
        fi
    fi
    # Don't exit - continue with the build
fi

# Step 6: Copy GStreamer plugins (selective)
log ""
log "${YELLOW}=== Copying GStreamer plugins ===${NC}"

PLUGIN_DIR="$DIST_DIR/lib/gstreamer-1.0"
mkdir -p "$PLUGIN_DIR"

# Essential plugins
ESSENTIAL_PLUGINS=(
    # Core elements
    "libgstcoreelements.dll"
    "libgsttypefindfunctions.dll"
    
    # Playback
    "libgstplayback.dll"
    "libgstautodetect.dll"
    
    # Video
    "libgstvideoconvert.dll"
    "libgstvideoscale.dll"
    "libgstvideorate.dll"
    "libgstvideoparsersbad.dll"
    
    # Audio
    "libgstaudioconvert.dll"
    "libgstaudioresample.dll"
    "libgstvolume.dll"
    
    # Containers & Codecs
    "libgstmatroska.dll"
    "libgstisomp4.dll"
    "libgstavi.dll"
    "libgstlibav.dll"
    
    # Windows specific
    "libgstd3d.dll"
    "libgstd3d11.dll"
    "libgstwasapi.dll"
)

PLUGIN_COUNT=0
PLUGIN_SEARCH_PATHS=(
    "/mingw64/lib/gstreamer-1.0"
    "/usr/lib/gstreamer-1.0"
    "/c/msys64/mingw64/lib/gstreamer-1.0"
    "$MSYSTEM_PREFIX/lib/gstreamer-1.0"
)

for plugin in "${ESSENTIAL_PLUGINS[@]}"; do
    plugin_found=false
    for search_path in "${PLUGIN_SEARCH_PATHS[@]}"; do
        if [ -f "$search_path/$plugin" ]; then
            cp "$search_path/$plugin" "$PLUGIN_DIR/"
            ((PLUGIN_COUNT++))
            log "  Plugin: $plugin from $search_path"
            plugin_found=true
            break
        fi
    done
    if [ "$plugin_found" = false ]; then
        log "  ${YELLOW}Warning: Plugin not found: $plugin${NC}"
    fi
done

log "${GREEN}✓ Copied $PLUGIN_COUNT GStreamer plugins${NC}"

# Step 7: Copy config and assets
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
for dir in videos splash logo assets; do
    if [ -d "assets/$dir" ]; then
        cp -r "assets/$dir" "$DIST_DIR/"
        log "  ✓ $dir/"
    elif [ -d "$dir" ]; then
        cp -r "$dir" "$DIST_DIR/"
        log "  ✓ $dir/"
    fi
done

# Step 8: Create launcher script
log ""
log "${YELLOW}=== Creating launcher script ===${NC}"
cat > "$DIST_DIR/run.bat" << EOF
@echo off
REM Summit Hip Numbers Media Player Launcher
REM This script sets up the environment for the portable version

echo Starting Summit Hip Numbers Media Player...

REM Set GStreamer environment variables for portable version
set GST_PLUGIN_PATH=%~dp0lib\gstreamer-1.0
set GST_PLUGIN_SYSTEM_PATH=%~dp0lib\gstreamer-1.0
set PATH=%~dp0;%PATH%

REM Change to the application directory
cd /d "%~dp0"

REM Run the application
"%~dp0$EXE_OUTPUT_NAME"

pause
EOF
log "${GREEN}✓ Created run.bat${NC}"

# Step 9: Create README
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
- lib/, share/, and *.dll files: GStreamer runtime
- run.bat: Launcher script

Configuration:
Edit config.toml to customize settings like video directory path and splash screen options.
Run with --config flag to open configuration GUI.

Adding Videos:
Place your MP4 video files in the "videos" directory. Files will be automatically sorted alphabetically and assigned hip numbers (001, 002, etc.).

System Requirements:
- Windows 10 or later (64-bit)
- 4GB RAM minimum
- DirectX 11 compatible graphics

For support: support@example.com
For more information: https://github.com/millerjes37/summit_hip_numbers
EOF
log "${GREEN}✓ Created README.txt${NC}"

# Step 10: Summary and verification
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
# Avoid subshell issues with while loop
ls -la "$DIST_DIR" | tail -n +2 | head -20 > "${DIST_DIR}_contents.tmp"
while IFS= read -r line; do
    log "  $line"
done < "${DIST_DIR}_contents.tmp"
rm -f "${DIST_DIR}_contents.tmp"

if [ $TOTAL_FILES -gt 20 ]; then
    log "  ... and $((TOTAL_FILES - 20)) more files"
fi

log ""
log "${GREEN}================================${NC}"
log "${GREEN}  Build Complete!${NC}"
log "${GREEN}================================${NC}"
log "Distribution ready at: $DIST_DIR"
log "To create ZIP: cd dist && zip -r summit_hip_numbers_${VARIANT}_portable_\$(git describe --tags --always).zip $VARIANT"

exit 0