# Summit Hip Numbers Kiosk Deployment Guide

## Overview
This application is designed for fully offline operation on kiosk systems. No internet connectivity is required or assumed during deployment or runtime.

## Bundle Structure
The portable ZIP contains all necessary components:
- `summit_hip_numbers.exe` - Main application
- `config.toml` - Configuration file
- `videos/` - Directory containing video files (named with 3-digit hip prefixes)
- `splash/` - Directory containing splash screen images
- `logo/` - Directory containing company logo
- `lib/` - GStreamer runtime libraries
- `*.dll` - Required Windows DLLs
- `VERSION.txt` - Build information for troubleshooting

## Kiosk Setup
1. Extract the ZIP to a directory on the target system
2. Ensure the directory is writable (for logging)
3. Run `summit_hip_numbers.exe` (or use the provided batch file)
4. The application will start in fullscreen kiosk mode by default

## Configuration
Edit `config.toml` to customize:
- Video directory path
- Splash screen settings
- UI colors and labels
- Kiosk mode (fullscreen, no window decorations)

## Troubleshooting
- Check `summit_hip_numbers.log` for error messages
- Verify all required directories exist
- Ensure video files are named with 3-digit prefixes (001.mp4, 002.mp4, etc.)
- For demo version: Only hip numbers 001-005 are available

## Mass Deployment
For deploying to multiple systems:
1. Prepare the ZIP bundle
2. Copy to each system via USB drive or local network share
3. Extract and run on each kiosk
4. Use Task Scheduler for auto-start on boot if needed

## Offline Requirements
- Windows 10/11
- No internet connection required
- All dependencies bundled in the ZIP
- Videos and assets stored locally