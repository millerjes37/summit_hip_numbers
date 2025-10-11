# Summit USB Prep Tool

A simple GUI application for preparing USB drives with Summit kiosk software.

## Features

- **Automatic USB Detection**: Monitors `/Volumes/` for inserted USB drives
- **Source Folder Selection**: Choose the `dist` folder containing the kiosk software
- **Safe Copying**: Copies all files to a `SummitHipNumbers` subdirectory on the USB drive
- **Progress Tracking**: Shows copy progress with file count
- **Error Handling**: Validates drives and provides user-friendly error messages

## Usage

1. Build the kiosk software using the main project
2. Run the USB Prep Tool: `cargo run --release`
3. Click "Select Folder" and choose your `dist` directory
4. Insert a USB drive (it will be automatically detected)
5. Select the detected drive
6. Click "Copy to Selected Drive"
7. Wait for the copy to complete

## Requirements

- macOS (for USB drive detection via `/Volumes/`)
- The tool will work on other platforms but USB detection may need adjustment

## Building

```bash
cd usb_prep_tool
cargo build --release
```

Or using the Nix flake:
```bash
nix build .#usb-prep
```