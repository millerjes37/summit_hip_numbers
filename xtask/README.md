# xtask - Unified Build System

This is a Rust-based build automation tool for Summit HIP Numbers that replaces the complex multi-platform shell scripts with a single, unified solution.

## Features

- ✅ **Cross-platform builds** - Build for Windows, Linux, and macOS from any platform
- ✅ **Unified interface** - One command builds everything
- ✅ **FFmpeg management** - Automatic setup of FFmpeg libraries
- ✅ **Distribution packaging** - Creates ready-to-ship archives
- ✅ **CI/CD friendly** - Simple integration with GitHub Actions

## Usage

### Build Everything

```bash
# Build all platforms and variants
cargo xtask dist --all

# Build specific platform
cargo xtask dist --platform linux
cargo xtask dist --platform windows
cargo xtask dist --platform macos

# Build specific variant
cargo xtask dist --platform linux --variant demo
cargo xtask dist --platform linux --variant full
```

### Setup Commands

```bash
# Set up FFmpeg libraries
cargo xtask ffmpeg-setup

# Set up cross-compilation tools
cargo xtask cross-setup

# Clean build artifacts
cargo xtask clean
cargo xtask clean --all  # Also remove FFmpeg libraries
```

### Quick Aliases

```bash
# Using cargo aliases from .cargo/config.toml
cargo dist              # Same as: cargo xtask dist
cargo dist-all          # Same as: cargo xtask dist --all
```

## How It Works

### 1. Cross-Compilation

- **Linux**: Uses `cross` with Docker to build from any platform
- **Windows**: Uses `cross` with MinGW toolchain
- **macOS**: Requires native macOS for building (XCode limitations)

### 2. FFmpeg Handling

- **Windows**: Downloads pre-built FFmpeg DLLs (or uses MSYS2)
- **Linux**: Uses system FFmpeg in Docker via `cross`
- **macOS**: Uses Homebrew FFmpeg

### 3. Distribution Creation

For each platform, xtask:
1. Builds the release binary with cargo/cross
2. Copies assets (videos, splash, logo, config)
3. Bundles platform-specific dependencies
4. Creates distribution archives (zip/tar.gz)

## Directory Structure

```
xtask/
├── src/
│   ├── main.rs         # CLI and command handling
│   ├── ffmpeg.rs       # FFmpeg library management
│   ├── cross.rs        # Cross-compilation setup
│   └── dist.rs         # Distribution packaging
├── Cargo.toml          # Dependencies
└── README.md           # This file

.ffmpeg/                # Downloaded FFmpeg libraries (gitignored)
├── windows-x64/
├── linux-x64/
└── macos-arm64/

dist/                   # Build outputs (gitignored)
├── windows-full/
├── windows-demo/
├── linux-full/
├── linux-demo/
├── macos-full/
└── macos-demo/
```

## CI/CD Integration

The new GitHub Actions workflow (`.github/workflows/build-xtask.yml`) uses xtask:

```yaml
- name: Build with xtask
  run: cargo xtask dist --platform ${{ matrix.platform }} --variant ${{ matrix.variant }}
```

This replaces hundreds of lines of platform-specific CI configuration.

## Requirements

### All Platforms
- Rust 1.70+ (stable)
- Git

### For Cross-Compilation (Linux/Windows from other platforms)
- Docker (for `cross`)
- `cross` tool (auto-installed by xtask)

### For macOS Native Builds
- macOS 10.13+
- Xcode Command Line Tools
- Homebrew
- FFmpeg via Homebrew: `brew install ffmpeg`

## Comparison: Old vs New

### Old System (shell scripts + platform-specific CI)

❌ **932 lines** of CI YAML
❌ **400+ lines** of shell scripts across 3 platforms
❌ **Complex dependencies**: Nix, MSYS2, Homebrew, custom bindgen configs
❌ **Fragile**: bindgen path issues, environment variable conflicts
❌ **Hard to debug**: Errors spread across multiple steps

### New System (xtask)

✅ **~200 lines** of CI YAML
✅ **~700 lines** of Rust code (type-safe, maintainable)
✅ **Unified interface**: One command builds everything
✅ **Better error messages**: Rust's error handling
✅ **Easier to extend**: Add new platforms/features in Rust

## Troubleshooting

### "cross not found"
```bash
cargo install cross --git https://github.com/cross-rs/cross
```

### "FFmpeg libraries not found" (macOS)
```bash
brew install ffmpeg pkg-config
```

### "Docker not running" (for cross-compilation)
Start Docker Desktop or Docker daemon.

### Build fails with FFmpeg errors
```bash
# Force re-download FFmpeg libraries
cargo xtask ffmpeg-setup --force

# Or clean everything and start fresh
cargo xtask clean --all
cargo xtask dist --platform linux
```

## Development

To modify or extend xtask:

1. Edit files in `xtask/src/`
2. Test locally: `cargo xtask <command>`
3. Commit changes - no separate compilation needed

Since xtask is part of the workspace, cargo automatically compiles it when needed.

## Future Enhancements

- [ ] Automatic FFmpeg download for Windows (avoid manual 7z extraction)
- [ ] macOS DMG creation with background images
- [ ] Windows MSI installer generation
- [ ] Linux AppImage support
- [ ] Code signing automation
- [ ] Parallel builds for multiple platforms
- [ ] Build caching with sccache

## License

Same as the main project.
