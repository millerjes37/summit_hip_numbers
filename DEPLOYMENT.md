# Summit Hip Numbers Deployment Guide

## Overview

Summit Hip Numbers uses a dual configuration system to support both development and production/distribution environments. This guide explains how to build, configure, and deploy the application across different platforms.

## Configuration Management

### Development Configuration (`config.toml`)
- Uses nested `assets/` directory structure
- Convenient for organized development
- Example paths:
  ```toml
  [video]
  directory = "./assets/videos"
  
  [splash]
  directory = "./assets/splash"
  ```

### Distribution Configuration (`config.dist.toml`)
- Uses flat directory structure for portability
- Automatically used by build scripts for distribution
- Example paths:
  ```toml
  [video]
  directory = "./videos"
  
  [splash]
  directory = "./splash"
  ```

## Quick Start

### Development
```bash
# Enter development environment
nix develop

# Run the application
cargo run --release --bin summit_hip_numbers

# Run with configuration GUI
cargo run --release --bin summit_hip_numbers -- --config
```

### Build for Distribution
```bash
# Build for current platform
./scripts/build_all.sh

# Build for all platforms
./scripts/build_all.sh --platform all

# Build demo version
./scripts/build_all.sh --variant demo

# Create distribution from existing build
./scripts/build_all.sh --dist-only
```

## Platform-Specific Instructions

### Windows

#### Development
```bash
# Uses config.toml with assets/ directory
cargo run --release --bin summit_hip_numbers
```

#### Distribution Build
```powershell
# Run from project root
.\scripts\build_windows.ps1

# Creates dist/ folder with:
# - summit_hip_numbers.exe
# - config.toml (from config.dist.toml)
# - run.bat launcher
# - videos/, splash/, logo/ directories
# - All required GStreamer DLLs
```

#### Deployment
1. Copy the entire `dist/` folder to target machine
2. Place video files in `videos/` directory
3. Place splash images in `splash/` directory
4. Double-click `run.bat` to launch

### macOS

#### Development
```bash
# Uses config.toml with assets/ directory
cargo run --release --bin summit_hip_numbers
```

#### Distribution Build
```bash
# Run from project root
./scripts/build_macos.sh

# Creates .app bundle and .dmg installer
```

#### Deployment
1. Distribute the .dmg file
2. Users drag the app to Applications folder
3. First launch may require right-click → Open due to signing

### Linux

#### Development
```bash
# Uses config.toml with assets/ directory
cargo run --release --bin summit_hip_numbers
```

#### Distribution Build
```bash
# Run from project root
./scripts/build_all.sh --platform linux

# Creates tarball with portable application
```

#### Deployment
1. Extract the tarball to desired location
2. Ensure GStreamer is installed on target system
3. Run `./run.sh` to launch

## Directory Structure

### Development Structure
```
summit_hip_numbers/
├── config.toml              # Development configuration
├── config.dist.toml         # Distribution template
├── assets/
│   ├── videos/             # Video files
│   │   ├── 001_horse1.mp4
│   │   ├── 001_horse1_detail.mp4
│   │   └── 002_horse2.mp4
│   ├── splash/             # Splash screen images
│   │   ├── splash1.png
│   │   └── splash2.jpg
│   └── logo/               # Logo files
│       └── logo.svg
```

### Distribution Structure
```
summit_hip_numbers/
├── summit_hip_numbers.exe   # Main executable
├── config.toml             # Configuration (from config.dist.toml)
├── run.bat                 # Windows launcher
├── videos/                 # Video files (flat structure)
├── splash/                 # Splash images (flat structure)  
├── logo/                   # Logo files (flat structure)
└── [DLLs/libs]            # Platform dependencies
```

## Configuration Updates

### For End Users
1. Edit `config.toml` in the distribution folder
2. Restart the application for changes to take effect
3. Key settings:
   - `kiosk_mode`: Enable/disable fullscreen
   - `splash.interval`: Control splash screen frequency
   - `ui.window_width/height`: Set window dimensions

### For Developers
1. Update `config.toml` for development changes
2. Update `config.dist.toml` for distribution defaults
3. Build scripts automatically use the appropriate config

## Hip Number System

Videos are organized by "hip numbers" - 3-digit identifiers:

### Naming Convention
```
NNN_description.mp4
```
Where NNN is a 3-digit number (e.g., 001, 002, 003)

### Multiple Videos per Hip Number
- Multiple videos can share the same hip number
- They will play sequentially when that hip is selected
- Example:
  ```
  001_introduction.mp4
  001_details.mp4
  001_conclusion.mp4
  ```

## Troubleshooting

### Videos Not Loading
1. Check video directory path in config.toml
2. Ensure videos are in supported format (MP4 recommended)
3. Verify video files have proper hip number prefix (001_, 002_, etc.)

### GStreamer Issues (Windows)
1. Ensure all DLLs are in the distribution folder
2. Run from `run.bat` instead of directly executing .exe
3. Check that Visual C++ Redistributables are installed

### Splash Screen Issues
1. Verify splash directory contains image files
2. Supported formats: PNG, JPG, JPEG, BMP
3. Check splash.enabled = true in config.toml

## Build Automation

The project includes comprehensive build automation:

### Master Build Script
```bash
# scripts/build_all.sh
./scripts/build_all.sh [options]

Options:
  --platform <platform>    macos, windows, linux, all
  --variant <variant>      full, demo, all
  --skip-tests            Skip test execution
  --dist-only             Package existing builds
```

### CI/CD Integration
GitHub Actions automatically build and test:
- On push to main branch
- On pull requests
- For releases (creates artifacts)

## Demo Mode

The demo variant has these restrictions:
- Maximum 5 videos
- 5-minute timeout
- Hip numbers limited to 001-005
- Fixed window size (1920x1080)
- Watermark displayed

Build demo version:
```bash
cargo build --release --features demo
```

## Security Considerations

1. **Code Signing**
   - Windows: Sign with Authenticode certificate
   - macOS: Sign with Developer ID
   - Linux: Consider AppImage signing

2. **Configuration**
   - Don't store sensitive data in config.toml
   - Use appropriate file permissions

3. **Updates**
   - No auto-update mechanism included
   - Manual replacement of binaries required

## Support

For issues or questions:
1. Check logs in `summit_hip_numbers.log`
2. Verify configuration in `config.toml`
3. Ensure all dependencies are present
4. Submit issues to project repository