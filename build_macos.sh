#!/bin/bash

# Build script for macOS
# Creates a DMG bundle with all dependencies
# Run this on a macOS machine with Rust and GStreamer installed

echo "Building Summit Hip Numbers Media Player for macOS..."

# Build the application bundle
cargo bundle --release

if [ $? -eq 0 ]; then
    echo "Bundle build successful!"

    # Find the bundle
    BUNDLE_PATH="target/release/bundle/macos/Summit Hip Numbers.app"
    if [ ! -d "$BUNDLE_PATH" ]; then
        echo "Bundle not found!"
        exit 1
    fi

    echo "Bundle location: $BUNDLE_PATH"

    # Create dist directory
    DIST_DIR="dist/macos"
    mkdir -p "$DIST_DIR"

    # Copy bundle to dist
    cp -r "$BUNDLE_PATH" "$DIST_DIR/"

    # Copy config and videos if they exist
    if [ -f "config.toml" ]; then
        cp "config.toml" "$DIST_DIR/Summit Hip Numbers.app/Contents/Resources/"
    fi

    if [ -d "videos" ]; then
        cp -r "videos" "$DIST_DIR/Summit Hip Numbers.app/Contents/Resources/"
    fi

    # Create DMG
    DMG_NAME="summit_hip_numbers_macos.dmg"
    hdiutil create -volname "Summit Hip Numbers" -srcfolder "$DIST_DIR" -ov -format UDZO "$DIST_DIR/$DMG_NAME"

    echo "DMG created: $DIST_DIR/$DMG_NAME"

    echo ""
    echo "macOS distribution ready!"
    echo "DMG: $DIST_DIR/$DMG_NAME"
else
    echo "Build failed!"
    exit 1
fi