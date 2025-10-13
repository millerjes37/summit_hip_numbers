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
export PKG_CONFIG_PATH="/mingw64/lib/pkgconfig:/mingw64/share/pkgconfig"
export RUSTFLAGS="-L native=/mingw64/lib"

# FFmpeg bindgen configuration (for ffmpeg-sys-next crate)
# These settings help bindgen (used by ffmpeg-sys-next) find the correct headers
export LIBCLANG_PATH="${LIBCLANG_PATH:-/mingw64/bin}"

# Configure clang arguments for bindgen to properly parse MinGW headers
# --sysroot tells clang to use /mingw64 as the root, preventing /usr/include lookups
if [ -z "${BINDGEN_EXTRA_CLANG_ARGS:-}" ]; then
    export BINDGEN_EXTRA_CLANG_ARGS="-I/mingw64/include -I/mingw64/x86_64-w64-mingw32/include --target=x86_64-w64-mingw32 --sysroot=/mingw64 -D__MINGW64__ -fms-extensions"
fi

export FFMPEG_INCLUDE_DIR="${FFMPEG_INCLUDE_DIR:-/mingw64/include}"
export FFMPEG_LIB_DIR="${FFMPEG_LIB_DIR:-/mingw64/lib}"
export FFMPEG_PKG_CONFIG="${FFMPEG_PKG_CONFIG:-1}"

log "MSYSTEM: $MSYSTEM"
log "MSYSTEM_PREFIX: $MSYSTEM_PREFIX"
log "PKG_CONFIG_PATH: $PKG_CONFIG_PATH"
log "LIBCLANG_PATH: $LIBCLANG_PATH"
log "BINDGEN_EXTRA_CLANG_ARGS: $BINDGEN_EXTRA_CLANG_ARGS"
log "FFMPEG_INCLUDE_DIR: $FFMPEG_INCLUDE_DIR"
log "FFMPEG_LIB_DIR: $FFMPEG_LIB_DIR"
log "FFMPEG_PKG_CONFIG: $FFMPEG_PKG_CONFIG"

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
            local size=$(stat -c%s "$source_path" 2>/dev/null || stat --format=%s "$source_path" 2>/dev/null || echo "unknown")
            log "  ✓ $dll_name ($size bytes)"
            return 0
        else
            log "  ⚠ Failed to copy $dll_name"
            return 1
        fi
    else
        # Try alternative names for certain DLLs
        case "$dll_name" in
            libxml2-2.dll)
                # Try libxml2.dll without version suffix
                if [ -f "/mingw64/bin/libxml2.dll" ]; then
                    if cp "/mingw64/bin/libxml2.dll" "$dest_path" 2>/dev/null; then
                        local size=$(stat -c%s "/mingw64/bin/libxml2.dll" 2>/dev/null || echo "unknown")
                        log "  ✓ $dll_name (found as libxml2.dll, $size bytes)"
                        return 0
                    fi
                fi
                ;;
        esac
        
        log "  ⚠ $dll_name not found"
        return 1
    fi
}

# Copy all required DLLs to root directory (Windows standard)
log "${YELLOW}=== Copying runtime dependencies ===${NC}"

# Core GLib/GObject DLLs (required for UI)
GLIB_DLLS=(
    "libglib-2.0-0.dll"
    "libgobject-2.0-0.dll"
    "libgio-2.0-0.dll"
    "libffi-8.dll"
    "libintl-8.dll"
    "libiconv-2.dll"
    "libpcre2-8-0.dll"
    "libwinpthread-1.dll"
    "zlib1.dll"
)

# Core FFmpeg DLLs (required for audio/video)
FFMPEG_DLLS=(
    "avutil-*.dll"
    "avcodec-*.dll"
    "avformat-*.dll"
    "swscale-*.dll"
    "swresample-*.dll"
)

# System DLLs (recommended for full functionality)
SYSTEM_DLLS=(
    "libgcc_s_seh-1.dll"
    "libstdc++-6.dll"
    "libbz2-1.dll"
    "liblzma-5.dll"
)

# Additional codec/format DLLs (optional but recommended)
MEDIA_DLLS=(
    "libx264-*.dll"
    "libx265-*.dll"
    "libvpx-*.dll"
    "libopus-0.dll"
    "libvorbis-0.dll"
    "libogg-0.dll"
)

# Copy all DLLs with error handling
log "Copying essential GLib/GObject DLLs..."
failed_critical_dlls=()
for dll in "${GLIB_DLLS[@]}"; do
    if ! copy_dll_safe "$dll"; then
        failed_critical_dlls+=("$dll")
    fi
done

log "Copying FFmpeg DLLs..."
for dll_pattern in "${FFMPEG_DLLS[@]}"; do
    # Handle wildcard patterns
    found=false
    for dll_file in /mingw64/bin/$dll_pattern; do
        if [ -f "$dll_file" ]; then
            dll_name=$(basename "$dll_file")
            if cp "$dll_file" "$DIST_DIR/$dll_name" 2>/dev/null; then
                local size=$(stat -c%s "$dll_file" 2>/dev/null || stat --format=%s "$dll_file" 2>/dev/null || echo "unknown")
                log "  ✓ $dll_name ($size bytes)"
                found=true
            fi
        fi
    done
    if [ "$found" = false ]; then
        log "  ✗ $dll_pattern NOT FOUND"
        failed_critical_dlls+=("$dll_pattern")
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
for dll_pattern in "${MEDIA_DLLS[@]}"; do
    # Handle wildcard patterns
    for dll_file in /mingw64/bin/$dll_pattern; do
        if [ -f "$dll_file" ]; then
            dll_name=$(basename "$dll_file")
            cp "$dll_file" "$DIST_DIR/$dll_name" 2>/dev/null && log "  ✓ $dll_name" || failed_optional_dlls+=("$dll_name")
        fi
    done
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

# Note: FFmpeg handles codecs internally, no plugin directory needed
log "${YELLOW}=== FFmpeg Configuration ===${NC}"
log "FFmpeg libraries provide built-in codec support"
log "No separate plugin directory required"

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

REM Add current directory to PATH for DLL resolution
set PATH=%~dp0;%PATH%

REM Change to the application directory
cd /d "%~dp0"

REM Display environment info
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
- FFmpeg audio/video playback
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
   
   IMPORTANT: When editing config.toml, always use forward slashes (/) in paths!
   - CORRECT:   directory = "./videos"  or  "C:/path/to/videos"
   - INCORRECT: directory = ".\videos"  or  "C:\path\to\videos"
   
   Windows accepts forward slashes and they work correctly. Backslashes (\) 
   are escape characters in TOML and will cause "invalid escape sequence" errors.

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
- Verify FFmpeg DLLs (avutil, avcodec, avformat, swscale, swresample) are present
- Verify video files are in supported formats
- Check config.toml for correct paths (use forward slashes, not backslashes!)
- Look for "invalid escape sequence" errors if you edited config.toml

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
- RUST_LOG=debug: Increase application debug output

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
REQUIRED_DIRS=("videos" "splash" "logo")
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

# Ensure empty directories have at least a placeholder file for ZIP preservation
for dir in "$DIST_DIR/splash" "$DIST_DIR/videos" "$DIST_DIR/logo"; do
    if [ -d "$dir" ] && [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then
        touch "$dir/.gitkeep"
        log "  Created .gitkeep in empty directory: $(basename "$dir")"
    fi
done

cd "dist"
zip -r "../summit_hip_numbers_${VARIANT}_portable.zip" "$VARIANT" >/dev/null 2>&1
cd ..

if [ -f "summit_hip_numbers_${VARIANT}_portable.zip" ]; then
    ZIP_SIZE=$(stat -c%s "summit_hip_numbers_${VARIANT}_portable.zip" 2>/dev/null || stat --format=%s "summit_hip_numbers_${VARIANT}_portable.zip" 2>/dev/null || echo "0")
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
    size=$(stat -c%s "$file" 2>/dev/null || stat --format=%s "$file" 2>/dev/null || echo "?")
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