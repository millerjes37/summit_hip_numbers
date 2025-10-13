#!/bin/bash
# Test script to verify Windows distribution structure
# This script validates that the Windows build creates the correct directory structure

set -e

VARIANT="${1:-full}"
DIST_DIR="dist/$VARIANT"

echo "========================================="
echo "Testing Windows Distribution Structure"
echo "Variant: $VARIANT"
echo "Directory: $DIST_DIR"
echo "========================================="

# Check if distribution directory exists
if [ ! -d "$DIST_DIR" ]; then
    echo "❌ Distribution directory not found: $DIST_DIR"
    exit 1
fi

echo "✅ Distribution directory exists"

# Define expected files and directories
if [ "$VARIANT" = "demo" ]; then
    EXPECTED_EXE="summit_hip_numbers_demo.exe"
else
    EXPECTED_EXE="summit_hip_numbers.exe"
fi

REQUIRED_FILES=(
    "$EXPECTED_EXE"
    "run.bat"
    "config.toml"
    "VERSION.txt"
    "README.txt"
)

REQUIRED_DIRS=(
    "videos"
    "splash"
    "logo"
    "lib/gstreamer-1.0"
)

REQUIRED_DLLS=(
    "libglib-2.0-0.dll"
    "libgobject-2.0-0.dll"
    "libgio-2.0-0.dll"
    "libgstreamer-1.0-0.dll"
    "libgstbase-1.0-0.dll"
    "libgstapp-1.0-0.dll"
    "libgstvideo-1.0-0.dll"
)

# Test required files
echo ""
echo "Checking required files..."
for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$DIST_DIR/$file" ]; then
        size=$(stat -f%z "$DIST_DIR/$file" 2>/dev/null || stat -c%s "$DIST_DIR/$file" 2>/dev/null || echo "unknown")
        echo "✅ $file ($size bytes)"
    else
        echo "❌ Missing: $file"
        exit 1
    fi
done

# Test required directories
echo ""
echo "Checking required directories..."
for dir in "${REQUIRED_DIRS[@]}"; do
    if [ -d "$DIST_DIR/$dir" ]; then
        count=$(find "$DIST_DIR/$dir" -type f | wc -l | tr -d ' ')
        echo "✅ $dir/ ($count files)"
    else
        echo "❌ Missing directory: $dir"
        exit 1
    fi
done

# Test critical DLLs
echo ""
echo "Checking critical DLLs..."
missing_dlls=()
for dll in "${REQUIRED_DLLS[@]}"; do
    if [ -f "$DIST_DIR/$dll" ]; then
        size=$(stat -f%z "$DIST_DIR/$dll" 2>/dev/null || stat -c%s "$DIST_DIR/$dll" 2>/dev/null || echo "unknown")
        echo "✅ $dll ($size bytes)"
    else
        echo "❌ Missing DLL: $dll"
        missing_dlls+=("$dll")
    fi
done

if [ ${#missing_dlls[@]} -gt 0 ]; then
    echo "❌ Critical DLLs missing: ${missing_dlls[*]}"
    exit 1
fi

# Count total DLLs
dll_count=$(find "$DIST_DIR" -name "*.dll" -type f | wc -l | tr -d ' ')
echo ""
echo "Total DLLs found: $dll_count"
if [ "$dll_count" -lt 15 ]; then
    echo "⚠️  Warning: Low DLL count ($dll_count), expected at least 15"
fi

# Count GStreamer plugins
plugin_count=$(find "$DIST_DIR/lib/gstreamer-1.0" -name "*.dll" -type f 2>/dev/null | wc -l | tr -d ' ')
echo "GStreamer plugins: $plugin_count"
if [ "$plugin_count" -lt 10 ]; then
    echo "⚠️  Warning: Low plugin count ($plugin_count), expected at least 10"
fi

# Test run.bat content
echo ""
echo "Checking run.bat content..."
if grep -q "$EXPECTED_EXE" "$DIST_DIR/run.bat"; then
    echo "✅ run.bat references correct executable"
else
    echo "❌ run.bat does not reference $EXPECTED_EXE"
    exit 1
fi

if grep -q "GST_PLUGIN_PATH" "$DIST_DIR/run.bat"; then
    echo "✅ run.bat sets GStreamer environment"
else
    echo "❌ run.bat missing GStreamer environment setup"
    exit 1
fi

# Test config.toml
echo ""
echo "Checking config.toml..."
if [ -f "$DIST_DIR/config.toml" ]; then
    if grep -q "directory.*=.*\"./videos\"" "$DIST_DIR/config.toml"; then
        echo "✅ config.toml uses portable video directory"
    else
        echo "⚠️  config.toml may not use portable video directory"
    fi
else
    echo "❌ config.toml not found"
    exit 1
fi

# Calculate total distribution size
echo ""
echo "Distribution summary:"
total_size=$(du -sh "$DIST_DIR" 2>/dev/null | cut -f1)
total_files=$(find "$DIST_DIR" -type f | wc -l | tr -d ' ')
echo "Total size: $total_size"
echo "Total files: $total_files"

# List top-level contents
echo ""
echo "Top-level contents:"
ls -la "$DIST_DIR" | while read line; do
    echo "  $line"
done

echo ""
echo "========================================="
echo "✅ Windows distribution structure test PASSED"
echo "========================================="
echo ""
echo "Distribution ready for:"
echo "1. ZIP compression (summit_hip_numbers_${VARIANT}_portable.zip)"
echo "2. Direct execution (cd $DIST_DIR && ./run.bat)"
echo "3. Distribution to end users"

exit 0