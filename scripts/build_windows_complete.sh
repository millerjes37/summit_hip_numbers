#!/bin/bash
# Complete Windows Build Script for Summit Hip Numbers
# Builds a fully portable Windows distribution with correct directory structure

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
VARIANT="${1:-full}"
DIST_DIR="dist/$VARIANT"
BUILD_LOG="build_${VARIANT}_$(date +%Y%m%d_%H%M%S).log"
ERROR_LOG="build_${VARIANT}_errors.log"

# Logging functions
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$BUILD_LOG"
}

error_exit() {
    echo -e "${RED}[ERROR] $*${NC}" | tee -a "$ERROR_LOG"
    exit 1
}

log "${BLUE}=== Summit Hip Numbers Windows Complete Build ===${NC}"
log "Variant: $VARIANT"
log "Build log: $BUILD_LOG"

# Validate variant
if [[ "$VARIANT" != "full" && "$VARIANT" != "demo" ]]; then
    error_exit "Invalid variant '$VARIANT'. Use 'full' or 'demo'."
fi

# Environment setup
log "${YELLOW}=== Setting up MSYS2 environment ===${NC}"
export MSYSTEM=MINGW64
export MSYSTEM_PREFIX=/mingw64
export PATH="$MSYSTEM_PREFIX/bin:$PATH"
export PKG_CONFIG_PATH="/mingw64/lib/pkgconfig:$PKG_CONFIG_PATH"
export RUSTFLAGS="-L native=/mingw64/lib"

log "MSYSTEM: $MSYSTEM"
log "MSYSTEM_PREFIX: $MSYSTEM_PREFIX"
log "PKG_CONFIG_PATH: $PKG_CONFIG_PATH"

# Verify MSYS2 installation
if [ ! -d "$MSYSTEM_PREFIX/bin" ]; then
    error_exit "MSYS2 not found at $MSYSTEM_PREFIX. Please ensure MSYS2 is properly installed."
fi

# Create distribution directory
log "${YELLOW}=== Creating distribution directory ===${NC}"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"
log "Created: $DIST_DIR"

# Build application
log "${YELLOW}=== Building application ===${NC}"
if [ "$VARIANT" = "demo" ]; then
    log "Building demo version with restricted features..."
    cargo build --release --package summit_hip_numbers --features demo 2>&1 | tee -a "$BUILD_LOG"
    BINARY_NAME="summit_hip_numbers_demo.exe"
    SOURCE_BINARY="target/release/summit_hip_numbers.exe"
else
    log "Building full version..."
    cargo build --release --package summit_hip_numbers 2>&1 | tee -a "$BUILD_LOG"
    BINARY_NAME="summit_hip_numbers.exe"
    SOURCE_BINARY="target/release/summit_hip_numbers.exe"
fi

# Verify build success
if [ ! -f "$SOURCE_BINARY" ]; then
    error_exit "Build failed: $SOURCE_BINARY not found"
fi

# Copy main executable
log "${YELLOW}=== Copying main executable ===${NC}"
cp "$SOURCE_BINARY" "$DIST_DIR/$BINARY_NAME"
exe_size=$(du -h "$DIST_DIR/$BINARY_NAME" | cut -f1)
log "✓ Copied $BINARY_NAME ($exe_size)"

# Function to safely copy DLL with verification
copy_dll_safe() {
    local dll_name="$1"
    local source_path="/mingw64/bin/$dll_name"
    local dest_path="$DIST_DIR/$dll_name"
    
    if [ -f "$source_path" ]; then
        if cp "$source_path" "$dest_path" 2>/dev/null; then
            local size=$(stat -c%s "$source_path" 2>/dev/null || echo "unknown")
            log "  ✓ $dll_name ($size bytes)"
            return 0
        else
            log "  ⚠ Failed to copy $dll_name"
            return 1
        fi
    else
        log "  ⚠ $dll_name not found"
        return 1
    fi
}

# Copy all required DLLs to root directory (Windows standard)
log "${YELLOW}=== Copying runtime dependencies ===${NC}"

# Core GLib/GObject DLLs (required)
GLIB_DLLS=(
    "libglib-2.0-0.dll"
    "libgmodule-2.0-0.dll"
    "libgobject-2.0-0.dll"
    "libgio-2.0-0.dll"
    "libgthread-2.0-0.dll"
    "libffi-8.dll"
    "libintl-8.dll"
    "libiconv-2.dll"
    "libpcre2-8-0.dll"
    "libwinpthread-1.dll"
    "zlib1.dll"
)

# Core GStreamer DLLs (required)
GSTREAMER_DLLS=(
    "libgstreamer-1.0-0.dll"
    "libgstbase-1.0-0.dll"
    "libgstcontroller-1.0-0.dll"
    "libgstnet-1.0-0.dll"
    "libgstapp-1.0-0.dll"
    "libgstvideo-1.0-0.dll"
    "libgstaudio-1.0-0.dll"
    "libgstpbutils-1.0-0.dll"
    "libgsttag-1.0-0.dll"
    "libgstriff-1.0-0.dll"
    "libgstfft-1.0-0.dll"
    "libgstrtp-1.0-0.dll"
    "libgstrtsp-1.0-0.dll"
    "libgstsdp-1.0-0.dll"
    "libgstallocators-1.0-0.dll"
    "libgstgl-1.0-0.dll"
)

# System DLLs (recommended but optional for basic functionality)
SYSTEM_DLLS=(
    "libgcc_s_seh-1.dll"
    "libstdc++-6.dll"
    "liborc-0.4-0.dll"
    "libbz2-1.dll"
    "libfreetype-6.dll"
    "libharfbuzz-0.dll"
    "libpng16-16.dll"
    "libxml2-2.dll"
    "liblzma-5.dll"
)

# Additional media format DLLs (optional but recommended)
MEDIA_DLLS=(
    "libopus-0.dll"
    "libvorbis-0.dll"
    "libvorbisenc-2.dll"
    "libogg-0.dll"
    "libflac-12.dll"
    "libmpg123-0.dll"
    "libx264-164.dll"
    "libx265-199.dll"
)

# Copy all DLLs with error handling
log "Copying essential GLib/GObject DLLs..."
failed_critical_dlls=()
for dll in "${GLIB_DLLS[@]}"; do
    if ! copy_dll_safe "$dll"; then
        failed_critical_dlls+=("$dll")
    fi
done

log "Copying GStreamer DLLs..."
for dll in "${GSTREAMER_DLLS[@]}"; do
    if ! copy_dll_safe "$dll"; then
        failed_critical_dlls+=("$dll")
    fi
done

log "Copying system DLLs..."
failed_optional_dlls=()
for dll in "${SYSTEM_DLLS[@]}"; do
    if ! copy_dll_safe "$dll"; then
        failed_optional_dlls+=("$dll")
    fi
done

log "Copying media format DLLs..."
for dll in "${MEDIA_DLLS[@]}"; do
    if ! copy_dll_safe "$dll"; then
        failed_optional_dlls+=("$dll")
    fi
done

# Check for critical failures
if [ ${#failed_critical_dlls[@]} -gt 5 ]; then
    error_exit "Too many critical DLLs missing: ${failed_critical_dlls[*]}"
elif [ ${#failed_critical_dlls[@]} -gt 0 ]; then
    log "⚠ Warning: Some critical DLLs missing (${failed_critical_dlls[*]}). Build may have reduced functionality."
fi

if [ ${#failed_optional_dlls[@]} -gt 0 ]; then
    log "ℹ Optional DLLs not found (${failed_optional_dlls[*]}). This is normal and won't affect core functionality."
fi

# Copy GStreamer plugins
log "${YELLOW}=== Copying GStreamer plugins ===${NC}"
PLUGIN_DIR="$DIST_DIR/lib/gstreamer-1.0"
mkdir -p "$PLUGIN_DIR"

# Essential plugins for video playback
ESSENTIAL_PLUGINS=(
    "libgstcoreelements.dll"
    "libgstplayback.dll"
    "libgsttypefindfunctions.dll"
    "libgstapp.dll"
    "libgstvideoconvert.dll"
    "libgstvideoscale.dll"
    "libgstvideofilter.dll"
    "libgstautodetect.dll"
    "libgstdirectsound.dll"
    "libgstwasapi.dll"
    "libgstdeinterlace.dll"
    "libgstinterleave.dll"
    "libgstaudioconvert.dll"
    "libgstaudioresample.dll"
    "libgstvolume.dll"
    "libgstaudiotestsrc.dll"
    "libgstvideotestsrc.dll"
)

# MP4/H.264 support plugins
MP4_PLUGINS=(
    "libgstisomp4.dll"
    "libgstlibav.dll"
    "libgstmatroska.dll"
    "libgstavi.dll"
    "libgstqtdemux.dll"
    "libgstmpeg2dec.dll"
    "libgstmpegdemux.dll"
    "libgstmpegpsmux.dll"
)

# Copy plugins with fallback
SOURCE_PLUGIN_DIR="/mingw64/lib/gstreamer-1.0"
COPIED_PLUGINS=0

if [ -d "$SOURCE_PLUGIN_DIR" ]; then
    log "Copying essential plugins..."
    for plugin in "${ESSENTIAL_PLUGINS[@]}" "${MP4_PLUGINS[@]}"; do
        source_plugin="$SOURCE_PLUGIN_DIR/$plugin"
        if [ -f "$source_plugin" ]; then
            cp "$source_plugin" "$PLUGIN_DIR/"
            log "  ✓ $plugin"
            ((COPIED_PLUGINS++))
        else
            log "  ⚠ $plugin not found"
        fi
    done
    
    # Copy any remaining plugins (with size limit to avoid huge files)
    log "Copying additional plugins..."
    while IFS= read -r -d $'\0' plugin_file; do
        if [ -f "$plugin_file" ]; then
            plugin_name=$(basename "$plugin_file")
            # Skip if already copied
            if [ ! -f "$PLUGIN_DIR/$plugin_name" ]; then
                # Check file size (skip if > 10MB)
                size=$(stat -c%s "$plugin_file" 2>/dev/null || echo "0")
                if [ "$size" -lt 10485760 ]; then  # 10MB
                    cp "$plugin_file" "$PLUGIN_DIR/" 2>/dev/null && ((COPIED_PLUGINS++))
                fi
            fi
        fi
    done < <(find "$SOURCE_PLUGIN_DIR" -name "*.dll" -type f -print0 2>/dev/null || true)
    
    log "✓ Copied $COPIED_PLUGINS total GStreamer plugins"
else
    error_exit "GStreamer plugin directory not found: $SOURCE_PLUGIN_DIR"
fi

if [ $COPIED_PLUGINS -lt 5 ]; then
    error_exit "Too few plugins copied ($COPIED_PLUGINS). Build may not work correctly."
elif [ $COPIED_PLUGINS -lt 10 ]; then
    log "⚠ Warning: Only $COPIED_PLUGINS plugins copied. Some features may not work."
fi

# Create directory structure and copy assets
log "${YELLOW}=== Creating directory structure and copying assets ===${NC}"

# Create required subdirectories
mkdir -p "$DIST_DIR/videos"
mkdir -p "$DIST_DIR/splash"
mkdir -p "$DIST_DIR/logo"

# Copy configuration file based on variant
if [ "$VARIANT" = "demo" ]; then
    if [ -f "config.dist.toml" ]; then
        cp "config.dist.toml" "$DIST_DIR/config.toml"
        log "✓ Copied config.dist.toml as config.toml"
    elif [ -f "config.toml" ]; then
        cp "config.toml" "$DIST_DIR/"
        log "✓ Copied config.toml"
    fi
else
    if [ -f "config.dist.toml" ]; then
        cp "config.dist.toml" "$DIST_DIR/config.toml"
        log "✓ Copied config.dist.toml as config.toml"
    elif [ -f "config.toml" ]; then
        cp "config.toml" "$DIST_DIR/"
        log "✓ Copied config.toml"
    fi
fi

# Copy assets if they exist
if [ -d "assets/videos" ] && [ "$VARIANT" = "demo" ]; then
    cp -r assets/videos/* "$DIST_DIR/videos/" 2>/dev/null || true
    video_count=$(find "$DIST_DIR/videos" -name "*.mp4" -o -name "*.mkv" -o -name "*.avi" | wc -l)
    log "✓ Copied demo videos ($video_count files)"
fi

if [ -d "assets/splash" ]; then
    cp -r assets/splash/* "$DIST_DIR/splash/" 2>/dev/null || true
    splash_count=$(find "$DIST_DIR/splash" -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" | wc -l)
    log "✓ Copied splash images ($splash_count files)"
fi

if [ -d "assets/logo" ]; then
    cp -r assets/logo/* "$DIST_DIR/logo/" 2>/dev/null || true
    log "✓ Copied logo assets"
elif [ -f "assets/logo.svg" ]; then
    cp "assets/logo.svg" "$DIST_DIR/logo/"
    log "✓ Copied logo.svg"
fi

# Create run.bat launcher script
log "${YELLOW}=== Creating launcher script ===${NC}"
cat > "$DIST_DIR/run.bat" << EOF
@echo off
REM Summit Hip Numbers Media Player - Portable Launcher
REM This script sets up the environment and launches the application

echo ========================================
echo Summit Hip Numbers Media Player
echo Variant: $VARIANT
echo ========================================
echo.

REM Set GStreamer environment for portable distribution
set GST_PLUGIN_PATH=%~dp0lib\\gstreamer-1.0
set GST_PLUGIN_SYSTEM_PATH=%~dp0lib\\gstreamer-1.0
set GST_DEBUG=2
set GST_DEBUG_NO_COLOR=1

REM Add current directory to PATH for DLL resolution
set PATH=%~dp0;%PATH%

REM Change to the application directory
cd /d "%~dp0"

REM Display environment info
echo GStreamer Plugin Path: %GST_PLUGIN_PATH%
echo Current Directory: %CD%
echo.

REM Check if main executable exists
if not exist "$BINARY_NAME" (
    echo ERROR: $BINARY_NAME not found!
    echo Please ensure all files are present.
    pause
    exit /b 1
)

REM Launch the application
echo Starting Summit Hip Numbers Media Player...
echo.
"$BINARY_NAME" %*

REM Handle exit codes
set EXIT_CODE=%errorlevel%
if %EXIT_CODE% neq 0 (
    echo.
    echo ========================================
    echo Application exited with code: %EXIT_CODE%
    echo ========================================
    echo.
    if %EXIT_CODE% equ 1 (
        echo This may indicate a configuration or media file issue.
        echo Check the config.toml file and ensure video files are present.
    )
    echo.
    echo Press any key to close this window...
    pause >nul
)

exit /b %EXIT_CODE%
EOF

log "✓ Created run.bat launcher"

# Create version file
log "${YELLOW}=== Creating version and info files ===${NC}"
cat > "$DIST_DIR/VERSION.txt" << EOF
Summit HIP Numbers - $VARIANT Version
====================================

Build Information:
- Build Date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
- Git Commit: $(git rev-parse HEAD 2>/dev/null || echo "unknown")
- Git Branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
- Variant: $VARIANT
- Builder: MSYS2/MinGW64
- Platform: Windows x86_64

Features:
$(if [ "$VARIANT" = "demo" ]; then
echo "- Demo mode: Limited to 5 videos, 5-minute timeout"
echo "- Hip numbers: 001-005 only"
else
echo "- Full version: Unlimited videos and features"
echo "- Hip numbers: 001-999"
fi)
- GStreamer video playback
- Kiosk mode support
- 3-digit hip number navigation
- Splash screen support
- Configuration GUI (run with --config)

Directory Structure:
- $BINARY_NAME: Main application executable
- run.bat: Launcher script (recommended)
- config.toml: Configuration file
- videos/: Place MP4 video files here
- splash/: Splash screen images
- logo/: Application logo assets
- lib/gstreamer-1.0/: GStreamer plugins
- *.dll: Runtime libraries

System Requirements:
- Windows 10 or later (64-bit)
- 4GB RAM minimum, 8GB recommended
- DirectX 11 compatible graphics
- 1GB free disk space

Usage:
1. Place your MP4 video files in the 'videos' directory
2. Double-click 'run.bat' to start the application
3. Use 3-digit numbers (001, 002, etc.) to navigate
4. Use arrow keys for sequential navigation
5. Press Esc to exit

For configuration, run: $BINARY_NAME --config

Support: https://github.com/millerjes37/summit_hip_numbers
EOF

log "✓ Created VERSION.txt"

# Create detailed README
cat > "$DIST_DIR/README.txt" << EOF
Summit Hip Numbers Media Player - Portable Distribution
=====================================================

Thank you for using Summit Hip Numbers Media Player!

QUICK START:
1. Double-click "run.bat" to launch the application
2. Place your video files in the "videos" folder
3. Use 3-digit numbers to navigate (001, 002, 003...)

DETAILED SETUP:

1. Video Files:
   - Supported formats: MP4, MKV, AVI
   - Place files in the "videos" directory
   - Files are sorted alphabetically and assigned hip numbers
   - Multiple videos per hip number supported (e.g., 001_part1.mp4, 001_part2.mp4)

2. Configuration:
   - Edit config.toml to customize settings
   - Run "$BINARY_NAME --config" for GUI configuration
   - Key settings: video directory, window size, fullscreen mode

3. Splash Screens:
   - Place PNG/JPG images in the "splash" directory
   - Images display while videos load
   - Configurable timing and behavior

4. Navigation:
   - Type 3-digit hip numbers (001-999) for direct access
   - Use Up/Down arrow keys for sequential navigation
   - Videos auto-advance when complete
   - Press Esc to exit

TROUBLESHOOTING:

If the application won't start:
- Ensure all DLL files are present in the main directory
- Check that GStreamer plugins exist in lib/gstreamer-1.0/
- Verify video files are in supported formats
- Check config.toml for correct paths

If videos won't play:
- Verify video files are valid MP4/MKV/AVI format
- Check that video codecs are supported
- Ensure sufficient disk space and memory
- Try different video files to isolate the issue

If performance is poor:
- Close other applications to free memory
- Ensure graphics drivers are up to date
- Consider using lower resolution video files
- Disable fullscreen mode if needed

ADVANCED USAGE:

Command Line Options:
- $BINARY_NAME --config: Open configuration GUI
- $BINARY_NAME --version: Show version information
- $BINARY_NAME --help: Display help information

Environment Variables:
- GST_DEBUG=3: Increase GStreamer debug output
- GST_DEBUG_FILE=debug.log: Log debug info to file

Configuration File (config.toml):
The configuration file controls all application behavior including:
- Video directory path
- Window dimensions and fullscreen settings
- Splash screen timing and images
- Hip number ranges and restrictions
- Logging levels and file locations

For more information and updates:
https://github.com/millerjes37/summit_hip_numbers

Technical Support:
For technical issues, please include:
- VERSION.txt contents
- config.toml file
- Any error messages or log files
- Description of the issue and steps to reproduce

EOF

log "✓ Created README.txt"

# Build verification
log "${YELLOW}=== Verifying build integrity ===${NC}"

# Check main executable
if [ ! -f "$DIST_DIR/$BINARY_NAME" ]; then
    error_exit "Main executable missing: $BINARY_NAME"
fi

# Count DLLs
DLL_COUNT=$(find "$DIST_DIR" -name "*.dll" -type f | wc -l)
if [ $DLL_COUNT -lt 10 ]; then
    error_exit "Too few DLLs found ($DLL_COUNT). Build incomplete."
elif [ $DLL_COUNT -lt 15 ]; then
    log "⚠ Warning: Only $DLL_COUNT DLLs found. Some features may not work."
fi

# Check for essential files
ESSENTIAL_FILES=("$BINARY_NAME" "run.bat" "config.toml" "VERSION.txt" "README.txt")
for file in "${ESSENTIAL_FILES[@]}"; do
    if [ ! -f "$DIST_DIR/$file" ]; then
        error_exit "Essential file missing: $file"
    fi
done

# Check directory structure
REQUIRED_DIRS=("videos" "splash" "logo" "lib/gstreamer-1.0")
for dir in "${REQUIRED_DIRS[@]}"; do
    if [ ! -d "$DIST_DIR/$dir" ]; then
        error_exit "Required directory missing: $dir"
    fi
done

log "✓ Build verification passed"
log "  - Executable: $BINARY_NAME"
log "  - DLLs: $DLL_COUNT"
log "  - Plugins: $COPIED_PLUGINS"
log "  - Directory structure: Complete"

# Create portable ZIP archive
log "${YELLOW}=== Creating portable archive ===${NC}"
cd "dist"
zip -r "../summit_hip_numbers_${VARIANT}_portable.zip" "$VARIANT" >/dev/null 2>&1
cd ..

if [ -f "summit_hip_numbers_${VARIANT}_portable.zip" ]; then
    ZIP_SIZE=$(stat -c%s "summit_hip_numbers_${VARIANT}_portable.zip")
    ZIP_SIZE_MB=$((ZIP_SIZE / 1024 / 1024))
    log "✓ Created portable ZIP: summit_hip_numbers_${VARIANT}_portable.zip (${ZIP_SIZE_MB} MB)"
else
    error_exit "Failed to create portable ZIP"
fi

# Final summary
log ""
log "${GREEN}============================================${NC}"
log "${GREEN}    BUILD COMPLETED SUCCESSFULLY!${NC}"
log "${GREEN}============================================${NC}"
log ""
log "Distribution: $DIST_DIR"
log "Archive: summit_hip_numbers_${VARIANT}_portable.zip"
log ""
log "Directory structure:"
find "$DIST_DIR" -type f | head -20 | while read file; do
    rel_path=$(echo "$file" | sed "s|^$DIST_DIR/||")
    size=$(stat -c%s "$file" 2>/dev/null || echo "?")
    log "  $rel_path ($size bytes)"
done

TOTAL_FILES=$(find "$DIST_DIR" -type f | wc -l)
TOTAL_SIZE=$(du -sh "$DIST_DIR" | cut -f1)
log ""
log "Summary: $TOTAL_FILES files, $TOTAL_SIZE total"
log ""
log "To test: cd $DIST_DIR && ./run.bat"
log "To distribute: Use summit_hip_numbers_${VARIANT}_portable.zip"

log "${GREEN}Build completed successfully!${NC}"
exit 0