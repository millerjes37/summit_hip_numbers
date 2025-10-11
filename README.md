# Summit Hip Numbers Media Player

A native GUI media player built with Rust, egui, and GStreamer for passive video playback with hip number input switching.

## Applications

This repository contains two applications:

### Summit Hip Numbers Media Player
The main media player application with all the features listed below.

### USB Prep Tool
A utility for preparing USB drives with the media player and video content. See `crates/usb_prep_tool/README.md` for details.

## Features

- **Reproducible Builds**: Uses Nix Flakes for consistent development and build environments across platforms
- **Demo Mode**: Hardcoded settings for consistent demo experience (5-minute timeout, max 5 videos, hip numbers 1-5)
- Passive cycling through video files in directory order
- 3-digit hip number input for instant video switching
- Arrow key navigation (up/down for previous/next video)
- Highly configurable UI: window size, fonts, colors, layout ratios, timeouts
- Fullscreen kiosk mode with customizable layout (default: 92% display area, 8% status bar)
- Configuration GUI application for easy setup
- Splash screen with image/text support and configurable intervals
- Support for MP4 and other GStreamer-supported video formats
- Cross-platform: Windows, macOS, Linux
- Portable Windows distribution with bundled GStreamer runtime

## Requirements

### System Dependencies

- **Nix**: For managing system dependencies and reproducible builds
- **GStreamer**: Video playback framework (automatically managed by Nix)

### Rust Dependencies

All Rust dependencies are managed via Cargo.toml and will be installed automatically.

## Installation

### Prerequisites

1. Install Nix: https://nixos.org/download.html
2. Enable Flakes: Add `experimental-features = nix-command flakes` to `~/.config/nix/nix.conf`

### All Platforms

```bash
# Clone the repository
git clone <repository-url>
cd summit_hip_numbers

# Enter the development shell (installs all dependencies)
nix develop

# Build the application
cargo build --release
```

### Windows

On Windows 10/11, use the provided PowerShell script to download the source code and install all dependencies:

```powershell
# Download source and install everything (recommended)
iwr -useb https://raw.githubusercontent.com/millerjes37/summit_hip_numbers/main/install_windows.ps1 | iex

# Or if you have the repository cloned already:
.\install_windows.ps1

# Install dependencies only (skip build)
.\install_windows.ps1 -SkipBuild

# Then build separately
.\build_windows.ps1
```

This automatically clones the repository and uses winget to install Rust and GStreamer.

## Configuration

The application can be configured in two ways:

### Configuration GUI (Recommended)

Run the application with the `--config` flag to launch the configuration GUI:

```bash
./summit_hip_numbers --config
```

This provides an easy-to-use interface for all configuration options.

### Manual Configuration

Edit `config.toml` to customize:

#### Video Settings
- `video.directory`: Path to video files directory

#### UI Layout & Appearance
- `ui.window_width/window_height`: Application window dimensions
- `ui.video_height_ratio/bar_height_ratio`: Layout proportions (0.0-1.0)
- `ui.splash_font_size/placeholder_font_size/demo_watermark_font_size`: Font sizes
- `ui.input_field_width/input_max_length`: Input field settings
- `ui.demo_watermark_x_offset/y_offset/width/height`: Demo watermark positioning
- `ui.ui_spacing/stroke_width`: UI element spacing and stroke widths

#### UI Colors & Labels
- `ui.input_label/now_playing_label/company_label`: Text labels
- `ui.input_text_color/input_stroke_color/label_color/background_color`: Colors (hex format)
- `ui.kiosk_mode`: Enable fullscreen kiosk mode
- `ui.enable_arrow_nav`: Enable arrow key navigation

#### Splash Screen
- `splash.enabled/duration_seconds/interval`: Splash screen behavior
- `splash.text/background_color/text_color`: Splash screen appearance
- `splash.directory`: Directory for splash images

#### Demo Mode Settings
- `demo.timeout_seconds`: Demo mode timeout duration
- `demo.max_videos`: Maximum videos shown in demo mode
- `demo.hip_number_limit`: Maximum hip number allowed in demo mode

#### Logging
- `logging.file/max_lines`: Log file configuration

### Demo Mode Behavior

When built with `--features demo`, the application uses hardcoded settings for consistent demo experience:

- Window: 1920x1080 fullscreen
- Kiosk mode: Enabled
- Arrow navigation: Enabled
- Timeout: 5 minutes
- Max videos: 5
- Hip numbers: 1-5 only
- Splash screen: Always enabled
- Video directory: Forced to bundled `./videos` folder

These settings override any configuration file values.

## Building

### All Applications

```bash
# Enter Nix shell
nix develop

# Build all applications
cargo build --release

# Build specific application
cargo build --release --package summit_hip_numbers
cargo build --release --package usb_prep_tool

# Build demo version
cargo build --release --package summit_hip_numbers --features demo
```

### macOS/Linux

The resulting binaries will be in:
- `target/release/summit_hip_numbers` (media player)
- `target/release/usb_prep_tool` (USB preparation utility)

### Windows

```powershell
# Install dependencies and build (recommended - clones repo automatically)
iwr -useb https://raw.githubusercontent.com/millerjes37/summit_hip_numbers/main/install_windows.ps1 | iex

# Or if you have the repository cloned:
.\install_windows.ps1
```

Or use the build script after installing dependencies:

```powershell
.\build_windows.ps1
```

The install script automatically clones the repository and uses winget to install Rust and GStreamer.

### Cross-Compilation

Build Windows executable from macOS/Linux (experimental):

```bash
nix build .#windows
```

The Windows binary will be in `result/bin/summit_hip_numbers.exe`.

## Running

### Media Player

```bash
# Run from Nix shell
cargo run --release --package summit_hip_numbers

# Run demo version
cargo run --release --package summit_hip_numbers --features demo

# Launch configuration GUI
cargo run --release --package summit_hip_numbers -- --config
```

Or run the compiled binary directly:

```bash
./target/release/summit_hip_numbers
./target/release/summit_hip_numbers --config  # Configuration GUI
```

### USB Prep Tool

```bash
# Run from Nix shell
cargo run --release --package usb_prep_tool

# Run compiled binary
./target/release/usb_prep_tool
```

The media player will look for a `config.toml` file in the current directory and videos in the configured directory.

## Usage

### Basic Operation

- **Configuration**: Run `./summit_hip_numbers --config` to launch the configuration GUI
- **Video Loading**: Video files are loaded from the configured directory
- **Hip Numbers**: Automatically assigned based on alphabetical file order (001, 002, 003, etc.)
- **Manual Switching**: Type 3-digit numbers to switch videos instantly
- **Auto Playback**: Videos play automatically in sequence when not manually switched
- **Arrow Navigation**: Use ↑/↓ arrow keys to navigate to previous/next video (if enabled)
- **Supported Formats**: MP4 and other GStreamer-compatible video formats

### Demo Mode

When running the demo version:
- Limited to 5 videos maximum
- Only hip numbers 001-005 are available
- 5-minute timeout before automatic exit
- Fixed UI layout and settings for consistent experience

## Development

### Technologies

- **GUI**: Built with egui for native performance and cross-platform compatibility
- **Video Playback**: GStreamer with Rust bindings for robust media support
- **Build System**: Reproducible builds with Nix Flakes
- **Configuration**: TOML-based configuration with GUI editor
- **Architecture**: Cargo workspace with multiple applications
- **Cross-platform**: Windows, macOS, Linux support

### Workspace Structure

- `summit_hip_numbers`: Main media player application
- `usb_prep_tool`: USB drive preparation utility
- Shared assets and build scripts in workspace root

## Troubleshooting

### Build Issues

- Ensure Nix is installed and Flakes are enabled
- Enter the Nix shell: `nix develop`
- If GStreamer fails, check that Nix can access system packages

### Runtime Issues

- **Videos not loading**: Check that video files are in the configured directory and supported by GStreamer
- **Demo mode restrictions**: Demo version limits videos to 5 and hip numbers to 001-005
- **Configuration not applying**: Demo mode overrides many settings - check if running demo version
- **Performance issues**: Always run in `--release` mode for optimal performance
- **Config not loading**: Ensure `config.toml` is in the same directory as the executable

### File Support

- **Videos**: MP4, and other formats supported by GStreamer
- Ensure GStreamer plugins are available in the Nix environment

## Project Structure

This is a Cargo workspace containing two applications:

### Summit Hip Numbers Media Player

```
crates/summit_hip_numbers/
├── src/
│   ├── main.rs          # Main application logic and UI
│   ├── file_scanner.rs  # Video file discovery and hip number assignment
│   └── video_player.rs  # GStreamer video playback integration
├── Cargo.toml           # Rust dependencies for media player
```

### USB Prep Tool

```
crates/usb_prep_tool/
├── src/
│   └── main.rs          # USB drive preparation utility
├── logo/                # Application logo assets
├── Cargo.toml           # Rust dependencies for USB tool
└── README.md            # USB tool documentation
```

### Workspace Files

```
├── assets/              # Shared assets (videos, logos, config)
├── scripts/             # Build and installation scripts
├── tests/               # Integration tests
├── flake.nix            # Nix Flakes configuration
├── shell.nix            # Nix shell for dependencies
├── config.toml          # Default configuration file
├── Cargo.toml           # Workspace configuration
└── Cargo.lock           # Dependency lock file
```

## Distribution

### Portable Distribution (Windows)

The Windows build script creates a fully portable version that can be distributed as a drag-and-drop folder:

```powershell
# Create portable distribution
.\build_windows.ps1
```

This creates:
- `dist/` folder with all files
- `summit_hip_numbers_portable.zip` for easy distribution

The portable version includes:
- Application executable
- GStreamer runtime (all DLLs and plugins)
- Configuration file
- Sample videos
- Launcher script (`run.bat`)

**To use the portable version:**
1. Extract the zip file to any Windows 10+ computer
2. Double-click `run.bat` to start
3. Add your videos to the `videos/` folder
4. Edit `config.toml` for customization

### Platform-Specific Distribution

#### macOS/Linux
1. Build with `nix build`
2. Copy the binary from `result/bin/`
3. Include `config.toml` and your videos directory
4. The Nix-built executable is self-contained

#### Windows (Alternative)
1. Build with `.\build_windows.ps1 -SkipGStreamer`
2. Requires GStreamer installed on target systems
3. Smaller distribution but less portable