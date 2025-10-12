#!/bin/bash
# Script to prepare distribution directory for Summit Hip Numbers

set -e

echo "Preparing Summit Hip Numbers distribution..."

# Get the project root directory
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$PROJECT_ROOT/dist"

# Clean and create dist directory
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# Create subdirectories
mkdir -p "$DIST_DIR/videos"
mkdir -p "$DIST_DIR/splash"
mkdir -p "$DIST_DIR/logo"

# Copy the distribution config as the main config
cp "$PROJECT_ROOT/config.dist.toml" "$DIST_DIR/config.toml"

# Copy assets
if [ -d "$PROJECT_ROOT/assets/videos" ]; then
    echo "Copying video files..."
    cp -r "$PROJECT_ROOT/assets/videos/"* "$DIST_DIR/videos/" 2>/dev/null || echo "No video files to copy"
fi

if [ -d "$PROJECT_ROOT/assets/splash" ]; then
    echo "Copying splash images..."
    cp -r "$PROJECT_ROOT/assets/splash/"* "$DIST_DIR/splash/" 2>/dev/null || echo "No splash images to copy"
fi

if [ -d "$PROJECT_ROOT/assets/logo" ]; then
    echo "Copying logo..."
    cp -r "$PROJECT_ROOT/assets/logo/"* "$DIST_DIR/logo/" 2>/dev/null || echo "No logo to copy"
fi

# Copy the release binary (if it exists)
if [ -f "$PROJECT_ROOT/target/release/summit_hip_numbers" ]; then
    echo "Copying release binary..."
    cp "$PROJECT_ROOT/target/release/summit_hip_numbers" "$DIST_DIR/"
elif [ -f "$PROJECT_ROOT/target/release/summit_hip_numbers.exe" ]; then
    echo "Copying Windows release binary..."
    cp "$PROJECT_ROOT/target/release/summit_hip_numbers.exe" "$DIST_DIR/"
else
    echo "Warning: Release binary not found. Run 'cargo build --release' first."
fi

# Create a README for the distribution
cat > "$DIST_DIR/README.txt" << EOF
Summit Hip Numbers Media Player
===============================

To run the application:
- Windows: Double-click summit_hip_numbers.exe
- macOS/Linux: Run ./summit_hip_numbers

Directory Structure:
- videos/    : Place your video files here (MP4 format recommended)
- splash/    : Place splash screen images here (PNG, JPG, JPEG, BMP)
- logo/      : Logo files
- config.toml: Configuration file (edit to customize behavior)

Video Naming:
Name your videos with a 3-digit prefix for the hip number:
- 001_horse_name.mp4
- 002_another_horse.mp4
- etc.

Controls:
- Enter 3-digit hip number and press Enter to switch videos
- Up/Down arrows to navigate through videos
- ESC to exit (if not in kiosk mode)
EOF

echo "Distribution prepared in: $DIST_DIR"
echo ""
echo "Directory structure:"
tree "$DIST_DIR" -L 2 2>/dev/null || ls -la "$DIST_DIR"