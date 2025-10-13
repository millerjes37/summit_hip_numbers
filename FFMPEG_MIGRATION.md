# FFmpeg Migration Summary

This document summarizes the migration from GStreamer to FFmpeg for the Summit Hip Numbers Media Player.

## Changes Made

### Core Application

1. **Cargo.toml** (`crates/summit_hip_numbers/Cargo.toml`)
   - Removed: `gstreamer`, `gstreamer-app`, `gstreamer-video` dependencies
   - Added: `ffmpeg-next = "7.0"`
   - Removed `gstreamer` feature flag

2. **video_player.rs** (`crates/summit_hip_numbers/src/video_player.rs`)
   - Complete rewrite using FFmpeg APIs
   - Direct frame decoding and RGBA conversion
   - Proper frame timing using video stream frame rate
   - EOS (end-of-stream) checking for clean shutdown
   - Error handling through Arc<Mutex<Option<String>>>

3. **main.rs** (`crates/summit_hip_numbers/src/main.rs`)
   - Removed all GStreamer initialization code
   - Removed GStreamer plugin path setup
   - Fixed splash screen auto-hide logic for first video load

### Build System

4. **flake.nix**
   - Replaced `gst_all_1.*` packages with `ffmpeg.dev`
   - Updated `commonDeps` to use FFmpeg
   - Renamed `gstLibs` to `ffmpegLibs`
   - Updated all `buildInputs` references

5. **build_windows.ps1** (`scripts/build_windows.ps1`)
   - Changed parameters from `$SkipGStreamer` / `$GStreamerPath` to `$SkipFFmpeg` / `$FFmpegPath`
   - Updated DLL search paths for FFmpeg (C:\ffmpeg, C:\msys64\mingw64, etc.)
   - Changed critical DLL list to FFmpeg libraries:
     - `avutil-*.dll`
     - `avcodec-*.dll`
     - `avformat-*.dll`
     - `swscale-*.dll`
     - `swresample-*.dll`
   - Removed GStreamer plugin directory copying
   - Simplified launcher script (no GST_PLUGIN_PATH needed)
   - Updated README text

6. **install_windows.ps1** (`scripts/install_windows.ps1`)
   - Changed installation from GStreamer to FFmpeg
   - Added automatic download from BtbN/FFmpeg-Builds or Gyan.dev
   - Updated environment variable setup (FFMPEG_DIR instead of GSTREAMER_ROOT)
   - Changed verification to use `ffmpeg -version` instead of `gst-launch-1.0`

## Advantages of FFmpeg Over GStreamer

### Distribution Benefits
- **Simpler DLL requirements**: ~5 FFmpeg DLLs vs ~50+ GStreamer DLLs + plugins
- **No plugin discovery**: FFmpeg statically links codecs
- **Portable by default**: No need for GST_PLUGIN_PATH or registry files
- **Smaller download**: Distribution package is significantly smaller

### Development Benefits
- **Easier cross-platform**: Same API on Windows/macOS/Linux
- **Better for kiosk apps**: More predictable and reliable playback
- **Simpler debugging**: Fewer moving parts, clearer error messages
- **Standard library**: FFmpeg is the de facto standard for video processing

## Testing Performed

✅ Video playback working on macOS with nix develop
✅ Multiple videos loading and switching
✅ Proper frame timing and smooth playback
✅ Splash screen auto-hides and first video loads
✅ EOS detection and video switching

## Windows Build Instructions

### For Users

1. **Install FFmpeg**:
   ```powershell
   # Option 1: Using winget (recommended)
   winget install Gyan.FFmpeg
   
   # Option 2: Manual download
   # Download from: https://github.com/BtbN/FFmpeg-Builds/releases
   # Extract to C:\ffmpeg
   ```

2. **Run the installer**:
   ```powershell
   .\scripts\install_windows.ps1
   ```

3. **Build portable distribution**:
   ```powershell
   .\scripts\build_windows.ps1
   ```

### For Developers

The build scripts will automatically:
- Search for FFmpeg in standard locations (C:\ffmpeg, Program Files, etc.)
- Copy required FFmpeg DLLs to the dist folder
- Create a portable distribution with all dependencies

## Required FFmpeg DLLs for Windows Distribution

The following DLLs must be included in the Windows portable distribution:

- `avutil-*.dll` - Core utilities
- `avcodec-*.dll` - Video/audio codecs
- `avformat-*.dll` - Container format handling
- `swscale-*.dll` - Video scaling and color conversion
- `swresample-*.dll` - Audio resampling (optional but recommended)

Plus any additional dependency DLLs that may be required by your FFmpeg build.

## Rollback Plan

If issues arise, the GStreamer version is preserved in git history. To rollback:

```bash
git revert <commit-hash>
```

Or restore specific files:
```bash
git checkout <previous-commit> -- crates/summit_hip_numbers/Cargo.toml
git checkout <previous-commit> -- crates/summit_hip_numbers/src/video_player.rs
```

## Known Issues / TODOs

- ⚠️ "No accelerated colorspace conversion" warning on macOS - not critical, playback works fine
- 🔄 Windows builds not yet tested (scripts updated but need verification)
- 📝 Linux builds should work with updated flake.nix but need testing

## Next Steps

1. Test Windows build on actual Windows machine
2. Test Linux build in Nix environment
3. Verify portable distribution on clean Windows system
4. Update CI/CD workflows to use FFmpeg
5. Update documentation and README files
