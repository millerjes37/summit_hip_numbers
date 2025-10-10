#!/bin/bash
# Build script for Windows using MSYS2
# This script runs entirely within MSYS2 environment where all paths work correctly

set -e  # Exit on error

echo "=== Summit Hip Numbers Windows Build (MSYS2) ==="
echo "Current directory: $(pwd)"
echo ""

# Configuration
DIST_DIR="dist"
EXE_NAME="summit_hip_numbers.exe"
TARGET_DIR="target/release"
ZIP_NAME="summit_hip_numbers_portable.zip"

# Step 1: Create clean dist directory
echo "=== Creating distribution directory ==="
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"
echo "✓ Created $DIST_DIR"

# Step 2: Copy executable
echo ""
echo "=== Copying executable ==="
if [ -f "$TARGET_DIR/$EXE_NAME" ]; then
    cp "$TARGET_DIR/$EXE_NAME" "$DIST_DIR/"
    exe_size=$(du -h "$DIST_DIR/$EXE_NAME" | cut -f1)
    echo "✓ Copied $EXE_NAME ($exe_size)"
else
    echo "ERROR: Executable not found at $TARGET_DIR/$EXE_NAME"
    exit 1
fi

# Step 3: Copy GStreamer DLLs
echo ""
echo "=== Copying GStreamer DLLs ==="
if [ -d /mingw64/bin ]; then
    dll_count=0
    for dll in /mingw64/bin/*.dll; do
        if [ -f "$dll" ]; then
            cp "$dll" "$DIST_DIR/"
            dll_count=$((dll_count + 1))
            if [ $dll_count -le 5 ]; then
                echo "  Copied: $(basename $dll)"
            fi
        fi
    done
    
    if [ $dll_count -gt 5 ]; then
        echo "  ... and $((dll_count - 5)) more DLLs"
    fi
    
    echo "✓ Copied $dll_count DLL files"
    
    if [ $dll_count -eq 0 ]; then
        echo "ERROR: No DLLs found in /mingw64/bin"
        exit 1
    fi
else
    echo "ERROR: /mingw64/bin directory does not exist"
    exit 1
fi

# Step 4: Verify critical DLLs
echo ""
echo "=== Verifying critical DLLs ==="
critical_dlls=(
    "libglib-2.0-0.dll"
    "libgobject-2.0-0.dll"
    "libgio-2.0-0.dll"
    "libgstapp-1.0-0.dll"
    "libgstreamer-1.0-0.dll"
    "libgstvideo-1.0-0.dll"
    "libgstbase-1.0-0.dll"
)

missing_dlls=()
for dll in "${critical_dlls[@]}"; do
    if [ -f "$DIST_DIR/$dll" ]; then
        echo "  ✓ $dll"
    else
        echo "  ✗ $dll MISSING"
        missing_dlls+=("$dll")
    fi
done

if [ ${#missing_dlls[@]} -gt 0 ]; then
    echo "ERROR: Missing critical DLLs: ${missing_dlls[*]}"
    exit 1
fi

# Step 5: Copy GStreamer plugins
echo ""
echo "=== Copying GStreamer plugins ==="
if [ -d /mingw64/lib/gstreamer-1.0 ]; then
    mkdir -p "$DIST_DIR/lib/gstreamer-1.0"
    cp -r /mingw64/lib/gstreamer-1.0/* "$DIST_DIR/lib/gstreamer-1.0/"
    plugin_count=$(find "$DIST_DIR/lib/gstreamer-1.0" -type f | wc -l)
    echo "✓ Copied $plugin_count plugin files"
else
    echo "WARNING: Plugin directory not found"
fi

# Step 6: Copy share directory
echo ""
echo "=== Copying share directory ==="
if [ -d /mingw64/share ]; then
    cp -r /mingw64/share "$DIST_DIR/"
    share_count=$(find "$DIST_DIR/share" -type f | wc -l)
    echo "✓ Copied share directory ($share_count files)"
else
    echo "WARNING: Share directory not found"
fi

# Step 7: Copy config and other files
echo ""
echo "=== Copying additional files ==="

if [ -f "config.toml" ]; then
    cp "config.toml" "$DIST_DIR/"
    echo "  ✓ config.toml"
fi

if [ -d "videos" ]; then
    cp -r "videos" "$DIST_DIR/"
    echo "  ✓ videos directory"
fi

if [ -d "splash" ]; then
    cp -r "splash" "$DIST_DIR/"
    echo "  ✓ splash directory"
fi

# Step 8: Create launcher script
echo ""
echo "=== Creating launcher script ==="
cat > "$DIST_DIR/run.bat" << 'EOF'
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
"%~dp0summit_hip_numbers.exe"

pause
EOF
echo "✓ Created run.bat"

# Step 9: Create README
echo ""
echo "=== Creating README ==="
cat > "$DIST_DIR/README.txt" << 'EOF'
Summit Hip Numbers Media Player - Portable Version
===============================================

This is a portable version of the Summit Hip Numbers Media Player that includes all necessary dependencies.

To run the application:
1. Double-click "run.bat" (Windows batch file)

Files:
- summit_hip_numbers.exe: Main application
- config.toml: Configuration file
- videos/: Directory for your video files
- splash/: Directory for splash images
- lib/, share/, and *.dll files: GStreamer runtime
- run.bat: Launcher script

Configuration:
Edit config.toml to customize settings like video directory path and splash screen options.

Adding Videos:
Place your MP4 video files in the "videos" directory. Files will be automatically sorted alphabetically and assigned hip numbers (001, 002, etc.).

Requirements:
- Windows 10 or later

For more information, visit: https://github.com/millerjes37/summit_hip_numbers
EOF
echo "✓ Created README.txt"

# Step 10: Create zip archive
echo ""
echo "=== Creating portable zip archive ==="
rm -f "$ZIP_NAME"
cd "$DIST_DIR"
zip -r "../$ZIP_NAME" . > /dev/null
cd ..
zip_size=$(du -h "$ZIP_NAME" | cut -f1)
echo "✓ Created $ZIP_NAME ($zip_size)"

# Step 11: Verify zip contents
echo ""
echo "=== Verifying zip contents ==="
temp_dir="temp_verify"
rm -rf "$temp_dir"
unzip -q "$ZIP_NAME" -d "$temp_dir"
zip_dll_count=$(find "$temp_dir" -name "*.dll" -type f | wc -l)
echo "DLLs in zip: $zip_dll_count"

if [ $zip_dll_count -eq 0 ]; then
    echo "ERROR: No DLLs found in zip file!"
    exit 1
fi

# Verify critical DLLs in zip
echo "Verifying critical DLLs in zip:"
missing_in_zip=()
for dll in "${critical_dlls[@]}"; do
    if [ -f "$temp_dir/$dll" ]; then
        echo "  ✓ $dll"
    else
        echo "  ✗ $dll MISSING"
        missing_in_zip+=("$dll")
    fi
done

rm -rf "$temp_dir"

if [ ${#missing_in_zip[@]} -gt 0 ]; then
    echo "ERROR: Missing critical DLLs in zip: ${missing_in_zip[*]}"
    exit 1
fi

# Summary
echo ""
echo "=== Build Summary ==="
echo "Distribution directory: $DIST_DIR/"
echo "Portable archive: $ZIP_NAME"
echo "DLLs bundled: $dll_count"
echo "✓ Build completed successfully!"