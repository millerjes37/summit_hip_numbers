# Summit Hip Numbers Configuration Guide

## Directory Structure

### Development Structure
When developing, we use an organized assets directory:
```
summit_hip_numbers/
├── config.toml          # Development configuration
├── config.dist.toml     # Distribution configuration template
├── assets/
│   ├── videos/          # Video files (MP4, etc.)
│   ├── splash/          # Splash screen images
│   └── logo/            # Logo files
│       └── logo.svg
```

### Distribution Structure
For Windows portable distribution:
```
summit_hip_numbers/
├── summit_hip_numbers.exe
├── config.toml          # Copied from config.dist.toml
├── run.bat              # Launcher script
├── videos/              # Video files directory
├── splash/              # Splash screen images
├── logo/                # Logo files
│   └── logo.svg
└── [GStreamer DLLs]     # Required runtime libraries
```

## Configuration Files

### config.toml (Development)
- Used during development
- References paths with `./assets/` prefix
- Example: `directory = "./assets/videos"`

### config.dist.toml (Distribution Template)
- Template for production/distribution builds
- References paths relative to executable
- Example: `directory = "./videos"`
- Gets copied as `config.toml` in distribution

## Path Resolution

The application automatically detects its environment:

1. **Development Mode** (when running from `target/` directory):
   - Uses `./assets/videos`, `./assets/splash`, `./assets/logo`
   - Allows for organized development structure

2. **Production Mode** (when running from distribution):
   - Uses `./videos`, `./splash`, `./logo`
   - Expects flat directory structure for portability

## Building for Distribution

### Windows
```powershell
# Build the application
cargo build --release

# Create distribution package
.\scripts\build_windows.ps1
```

This will:
1. Build the release executable
2. Copy the executable to `dist/`
3. Use `config.dist.toml` as `config.toml`
4. Copy videos, splash images, and logo from `assets/`
5. Copy all required GStreamer DLLs
6. Create a `run.bat` launcher

### Manual Distribution Preparation
```bash
# Unix/macOS
./scripts/prepare_dist.sh

# Windows
scripts\prepare_dist.bat
```

## Configuration Options

### Video Settings
- `directory`: Path to video files
- Videos should be named with 3-digit prefix: `001_name.mp4`

### Splash Screen Settings
- `enabled`: Show splash screen (true/false)
- `duration_seconds`: How long to show splash
- `interval`: Show splash every N videos (0 = only at startup)
- `rotation_mode`: How to select splash images
  - `"cycle"`: Sequential order
  - `"random"`: Random selection
  - `"static"`: Always show same image (set `static_splash_path`)
- `directory`: Path to splash images

### UI Settings
- `kiosk_mode`: Full screen without window decorations
- `window_width`/`window_height`: Window dimensions
- Colors in hex format (#RRGGBB)

## Hip Number System

Videos are organized by "hip numbers" - 3-digit identifiers:
- Multiple videos can share the same hip number
- Videos with same hip number play sequentially
- Example: `001_intro.mp4` and `001_detail.mp4` both belong to hip 001

## Troubleshooting

1. **Videos not found**: Check that video directory path in config.toml matches your structure
2. **Splash not showing**: Verify splash directory contains image files (PNG, JPG, JPEG, BMP)
3. **Logo missing**: Ensure logo.svg is in the logo directory
4. **GStreamer errors**: On Windows, ensure all DLLs are in the distribution folder