# Build Assets

This directory contains pre-staged FFmpeg binaries and resources for cross-platform builds.

## Directory Structure

```
build-assets/
├── linux-x64/          # Linux x86_64 FFmpeg binaries
│   ├── bin/           # Executables
│   ├── lib/           # Libraries
│   └── include/       # Headers
├── macos-x64/         # macOS x86_64 FFmpeg binaries
│   ├── bin/
│   ├── lib/
│   └── include/
└── windows-x64/       # Windows x86_64 FFmpeg binaries
    ├── bin/
    ├── lib/
    └── include/
```

## Purpose

These assets enable "batteries-included" distributions where FFmpeg libraries are bundled with the application, eliminating external dependencies.

## Build Process

The `xtask` build system will:
1. Download FFmpeg binaries to `.ffmpeg/` during builds
2. Bundle required libraries into distribution packages
3. Create portable applications that work without system FFmpeg installation

## Updating FFmpeg

To update FFmpeg versions:
1. Update download URLs in `xtask/src/main.rs`
2. Test builds on all platforms
3. Update this README with new version information