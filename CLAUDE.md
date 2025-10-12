# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Summit Hip Numbers is a native GUI media player built with Rust, featuring kiosk-style passive video playback with quick switching via 3-digit "hip numbers". The project uses a Cargo workspace structure containing two applications:

- `summit_hip_numbers`: Main media player with GStreamer video playback
- `usb_prep_tool`: USB drive preparation utility for deployment

## Build and Development Commands

### Essential Commands

```bash
# Enter development environment (required first)
nix develop

# Build all applications
cargo build --release

# Build specific application
cargo build --release --package summit_hip_numbers
cargo build --release --package usb_prep_tool

# Build demo version (limited features)
cargo build --release --package summit_hip_numbers --features demo

# Run the media player
cargo run --release --package summit_hip_numbers

# Run configuration GUI
cargo run --release --package summit_hip_numbers -- --config

# Run tests
cargo test --workspace

# Run a single test
cargo test test_hip_number_validation

# Format code
cargo fmt --all

# Lint code
cargo clippy --all-targets -- -D warnings

# Security audit
cargo audit
```

### Platform-Specific Build Scripts

**All Platforms:**
```bash
./scripts/build_all.sh          # Build for current platform
./scripts/build_all.sh --platform all  # Build for all platforms
./scripts/build_all.sh --variant demo  # Build demo version
```

**Windows:**
```powershell
.\install_windows.ps1  # Install all dependencies and build
.\scripts\build_windows.ps1    # Build only (requires dependencies)
```

**macOS:**
```bash
./scripts/install_macos.sh --skip-build  # Install dependencies only
./scripts/build_macos.sh                 # Build application
```

## Architecture Overview

### Core Components

**Main Application (`crates/summit_hip_numbers/src/`):**

- `main.rs`: Application entry point, egui UI implementation, event handling, and core state management. Key features:
  - Configuration loading (TOML-based)
  - Splash screen management
  - Hip number input validation (3-digit format)
  - Demo mode restrictions when built with `--features demo`
  - Video playback control and navigation
  
- `file_scanner.rs`: Video file discovery and hip number assignment
  - Scans directories for MP4, PNG, JPG, JPEG files
  - Assigns hip numbers based on sorted filenames (001, 002, 003...)
  - Creates mapping between hip numbers and file indices
  
- `video_player.rs`: GStreamer video playback integration (optional feature)
  - Creates GStreamer pipeline for video rendering
  - Handles video state management
  - Renders frames to egui textures

**USB Prep Tool (`crates/usb_prep_tool/src/main.rs`):**
- GUI application for copying media player to USB drives
- Auto-detects USB drives on macOS via `/Volumes/`
- Creates `SummitHipNumbers` directory structure

### Configuration System

The application uses a dual configuration system for development and distribution:

1. **Development Configuration** (`config.toml`):
   - Uses `assets/` directory structure
   - Example: `directory = "./assets/videos"`
   - Convenient for organized development

2. **Distribution Configuration** (`config.dist.toml`):
   - Uses flat directory structure for portability
   - Example: `directory = "./videos"`
   - Automatically used by build scripts for distribution

3. **Demo Mode Override**: Hardcoded settings when built with `--features demo`

Key configuration sections:
- `video`: Directory path for video files
- `ui`: Window dimensions, colors, labels, layout ratios
- `splash`: Splash screen settings and image directory
- `logging`: Log file location and size limits
- `demo`: Timeout and video count restrictions

**Multiple Videos per Hip Number**: The application supports multiple videos per hip number (horse). Videos with the same 3-digit prefix are grouped together and play sequentially. For example:
- `001_introduction.mp4`
- `001_details.mp4`
- `001_conclusion.mp4`

### Demo Mode Behavior

When built with `--features demo`, the following restrictions apply:
- Maximum 5 videos loaded
- Hip numbers limited to 001-005
- 5-minute timeout before application exit
- Fixed window size (1920x1080)
- Forced fullscreen kiosk mode
- Videos must be in `./videos` directory

### Build System

The project uses multiple build systems:

1. **Nix Flakes**: Provides reproducible build environment with all system dependencies (GStreamer, GUI libraries)
2. **Cargo**: Standard Rust build system
3. **Platform Scripts**: PowerShell (Windows) and Bash (macOS/Linux) scripts for automated builds

### Testing Strategy

- **Unit Tests**: Located within source files using `#[cfg(test)]` modules
- **Integration Tests**: `tests/integration_tests.rs` covering end-to-end scenarios
- **CI/CD**: GitHub Actions workflows for multi-platform builds and testing

Key test areas:
- Configuration loading and serialization
- Video file scanning and hip number assignment
- Input validation and navigation
- Demo mode restrictions
- Splash screen logic
- Log file management

### Video Playback Architecture

The application supports two video playback modes:

1. **GStreamer Mode** (default): Full video playback with hardware acceleration
2. **Mock Mode** (when GStreamer unavailable): Displays placeholder for development

Video switching occurs through:
- 3-digit hip number input (e.g., "001", "002")
- Arrow key navigation (up/down)
- Automatic progression after video completion

### Development Notes

When making changes:

1. **Always enter Nix shell first**: `nix develop` ensures correct dependencies
2. **Test on target platform**: GStreamer behavior varies across platforms
3. **Check demo mode**: Test both regular and demo builds
4. **Validate configuration**: Ensure new settings work with existing config files
5. **Update tests**: Add tests for new functionality in `tests/integration_tests.rs`

### Common Development Tasks

**Adding a new configuration option:**
1. Update struct in `src/main.rs` (Config, UiConfig, etc.)
2. Add default value in `Default` implementation
3. Update `config.toml` with new option
4. Add demo mode override if applicable

**Adding a new video format:**
1. Update `SUPPORTED_EXTENSIONS` in `src/file_scanner.rs`
2. Ensure GStreamer supports the format
3. Add test case with mock file

**Debugging video playback:**
1. Check `application.log` for GStreamer errors
2. Verify video codec support: `gst-inspect-1.0 | grep -i codec`
3. Test with known working MP4 file first

### Important File Locations

**Development:**
- Configuration: `config.toml` (project root)
- Distribution Template: `config.dist.toml` (project root)
- Videos: `assets/videos/` (configurable)
- Splash images: `assets/splash/` (configurable)
- Logo: `assets/logo/logo.svg`
- Logs: `summit_hip_numbers.log` (configurable)

**Distribution:**
- Configuration: `config.toml` (same directory as executable)
- Videos: `videos/` (next to executable)
- Splash images: `splash/` (next to executable)
- Logo: `logo/logo.svg` (next to executable)
- Logs: `summit_hip_numbers.log` (next to executable)