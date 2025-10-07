# Summit Hip Numbers Media Player

A native GUI media player built with Rust, egui, and GStreamer for passive video playback with hip number input switching.

## Features

- **Reproducible Builds**: Uses Nix Flakes for consistent development and build environments across platforms
- Passive cycling through video files in directory order
- 3-digit hip number input for instant video switching
- Fullscreen layout: 92% display area, 8% status bar
- Configurable via `config.toml`
- Splash screen on startup
- Support for MP4 and other GStreamer-supported video formats
- Cross-platform: Windows (via WSL2), macOS, Linux

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

Edit `config.toml` to customize:

- Video directory path
- Splash screen settings (enabled, duration, text, colors)

## Building

### macOS/Linux

```bash
# Enter Nix shell
nix develop

# Build for current platform
cargo build --release
```

The resulting binary will be in `target/release/summit_hip_numbers`.

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

```bash
# From Nix shell
cargo run --release
```

Or run the compiled binary directly:

```bash
./target/release/summit_hip_numbers
```

The application will look for a `config.toml` file in the current directory and videos in the configured directory.

## Usage

- Video files are loaded from the configured directory
- Hip numbers are automatically assigned based on alphabetical file order (001, 002, 003, etc.)
- Type 3-digit numbers to switch videos instantly
- Videos play automatically in sequence when not manually switched
- Supports MP4 and other GStreamer-compatible formats

## Development

- GUI built with egui for native performance
- Video playback via GStreamer with Rust bindings
- Reproducible builds with Nix Flakes
- Configuration via TOML files
- Cross-platform: Windows (WSL2), macOS, Linux support

## Troubleshooting

### Build Issues

- Ensure Nix is installed and Flakes are enabled
- Enter the Nix shell: `nix develop`
- If GStreamer fails, check that Nix can access system packages

### Runtime Issues

- **Videos not loading**: Check that video files are in the configured directory and supported by GStreamer
- **Performance issues**: Always run in `--release` mode for optimal performance
- **Config not loading**: Ensure `config.toml` is in the same directory as the executable

### File Support

- **Videos**: MP4, and other formats supported by GStreamer
- Ensure GStreamer plugins are available in the Nix environment

## Project Structure

```
summit_hip_numbers/
├── src/
│   ├── main.rs          # Main application logic
│   ├── file_scanner.rs  # File discovery
│   └── video_player.rs  # GStreamer video playback
├── videos/              # Place your video files here
├── flake.nix            # Nix Flakes configuration
├── shell.nix            # Nix shell for dependencies
├── config.toml          # Configuration file
└── Cargo.toml           # Rust dependencies
```

## Distribution

The application can be distributed as a single binary. To distribute:

### macOS/Linux
1. Build with `nix build`
2. Copy the binary from `result/bin/`
3. Include `config.toml` and your videos directory
4. The Nix-built executable is self-contained

### Windows
1. Build with `.\build_windows.ps1`
2. The script creates a `dist` folder with the executable, config, and videos
3. Zip the `dist` folder for distribution
4. Ensure GStreamer DLLs are available (installed via vcpkg in the build process)