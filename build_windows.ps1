# Build script for Windows
# Creates a portable distribution with all dependencies
# Run this on a Windows machine with Rust and GStreamer installed

param(
    [switch]$SkipGStreamer,
    [string]$GStreamerPath = ""
)

Write-Host "Building Portable Summit Hip Numbers Media Player for Windows..." -ForegroundColor Green

# Build the application bundle
cargo bundle --release

if ($LASTEXITCODE -eq 0) {
    Write-Host "Bundle build successful!" -ForegroundColor Green

    # Find the bundle directory
    $bundleDir = "target\release\bundle\windows\summit_hip_numbers.exe"
    if (!(Test-Path $bundleDir)) {
        $bundleDir = "target\release\bundle\msvc\summit_hip_numbers.exe"
    }
    if (!(Test-Path $bundleDir)) {
        Write-Host "Bundle exe not found!" -ForegroundColor Red
        exit 1
    }

    Write-Host "Bundle location: $bundleDir" -ForegroundColor Cyan

    # Create portable distribution package
    $distDir = "dist"
    if (Test-Path $distDir) {
        Remove-Item $distDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $distDir

    # Copy bundle exe
    Copy-Item $bundleDir (Join-Path $distDir "summit_hip_numbers.exe")

    # Find GStreamer installation
    if (!$SkipGStreamer) {
        if (!$GStreamerPath) {
            # Try to find GStreamer automatically
            $possiblePaths = @(
                "C:\gstreamer\1.0\x86_64\",
                "C:\gstreamer\1.0\mingw_x86_64\",
                "${env:ProgramFiles}\gstreamer\1.0\x86_64\",
                "${env:ProgramFiles(x86)}\gstreamer\1.0\x86_64\"
            )

            foreach ($path in $possiblePaths) {
                if (Test-Path $path) {
                    $GStreamerPath = $path
                    break
                }
            }
        }

        if ($GStreamerPath -and (Test-Path $GStreamerPath)) {
            Write-Host "Found GStreamer at: $GStreamerPath" -ForegroundColor Green

            # Copy essential GStreamer files to dist
            Write-Host "Copying GStreamer runtime..." -ForegroundColor Yellow

            # Copy bin directory (DLLs)
            if (Test-Path (Join-Path $GStreamerPath "bin")) {
                Copy-Item (Join-Path $GStreamerPath "bin\*") $distDir
            }

            # Copy lib directory (additional libraries)
            if (Test-Path (Join-Path $GStreamerPath "lib")) {
                Copy-Item (Join-Path $GStreamerPath "lib") $distDir -Recurse
            }

            # Copy share directory (plugins, etc.)
            if (Test-Path (Join-Path $GStreamerPath "share")) {
                Copy-Item (Join-Path $GStreamerPath "share") $distDir -Recurse
            }

            Write-Host "GStreamer runtime copied" -ForegroundColor Green
        } else {
            Write-Warning "GStreamer not found. The portable version may not work without GStreamer installed on the target system."
        }
    }

    # Copy config.toml if exists
    if (Test-Path "config.toml") {
        Copy-Item "config.toml" $distDir
    }

    # Copy videos directory if it exists
    if (Test-Path "videos") {
        Copy-Item "videos" $distDir -Recurse
    }

    # Copy splash directory if it exists
    if (Test-Path "splash") {
        Copy-Item "splash" $distDir -Recurse
    }

    # Create a launcher script for better compatibility
    $launcherScript = @"
@echo off
REM Summit Hip Numbers Media Player Launcher
REM This script sets up the environment for the portable version

echo Starting Summit Hip Numbers Media Player...

REM Set GStreamer environment variables for portable version
if exist "%~dp0gstreamer" (
    set GSTREAMER_ROOT=%~dp0gstreamer
    set PATH=%~dp0gstreamer\bin;%PATH%
    set GST_PLUGIN_PATH=%~dp0gstreamer\lib\gstreamer-1.0
)

REM Change to the application directory
cd /d "%~dp0"

REM Run the application
"%~dp0summit_hip_numbers.exe"

pause
"@

    $launcherScript | Out-File -FilePath (Join-Path $distDir "run.bat") -Encoding ASCII

    # Create a README for the portable version
    $readmeContent = @"
Summit Hip Numbers Media Player - Portable Version
===============================================

This is a portable version of the Summit Hip Numbers Media Player that includes all necessary dependencies.

To run the application:
1. Double-click "run.bat" (Windows batch file)
2. Or run "summit_hip_numbers.exe" directly if GStreamer is installed system-wide

Files:
- summit_hip_numbers.exe: Main application
- config.toml: Configuration file
- videos/: Directory for your video files
- splash/: Directory for splash images
- gstreamer/: GStreamer runtime (if included)
- run.bat: Launcher script

Configuration:
Edit config.toml to customize settings like video directory path and splash screen options.

Adding Videos:
Place your MP4 video files in the "videos" directory. Files will be automatically sorted alphabetically and assigned hip numbers (001, 002, etc.).

Requirements:
- Windows 10 or later
- If gstreamer/ folder is not included, GStreamer must be installed system-wide

For more information, visit: https://github.com/millerjes37/summit_hip_numbers
"@

    $readmeContent | Out-File -FilePath (Join-Path $distDir "README.txt") -Encoding UTF8

    Write-Host "Portable distribution package created in: $distDir" -ForegroundColor Green
    Write-Host "Contents:" -ForegroundColor Cyan
    Get-ChildItem $distDir | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Cyan }

    # Create a zip file for easy distribution
    $zipPath = "summit_hip_numbers_portable.zip"
    if (Test-Path $zipPath) {
        Remove-Item $zipPath -Force
    }

    Write-Host "Creating zip archive..." -ForegroundColor Yellow
    Compress-Archive -Path $distDir -DestinationPath $zipPath
    Write-Host "Zip archive created: $zipPath" -ForegroundColor Green

    # Create Inno Setup installer
    if (Get-Command "iscc" -ErrorAction SilentlyContinue) {
        Write-Host "Creating Inno Setup installer..." -ForegroundColor Yellow
        & iscc installer.iss
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Installer created: dist\summit_hip_numbers_installer.exe" -ForegroundColor Green
        } else {
            Write-Warning "Failed to create installer. Inno Setup may not be installed."
        }
    } else {
        Write-Warning "Inno Setup not found. Skipping installer creation."
    }

    Write-Host "`nPortable distribution ready!" -ForegroundColor Green
    Write-Host "You can now copy the '$distDir' folder or '$zipPath' to any Windows computer and run it." -ForegroundColor Cyan
    Write-Host "Double-click 'run.bat' to start the application." -ForegroundColor Cyan
    Write-Host "Or run the installer 'summit_hip_numbers_installer.exe' for a full installation." -ForegroundColor Cyan
} else {
    Write-Host "Build failed!" -ForegroundColor Red
    exit 1
}