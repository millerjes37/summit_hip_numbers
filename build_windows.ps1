# Build script for Windows
# Creates a portable distribution with all dependencies
# Run this on a Windows machine with Rust and GStreamer installed

param(
    [switch]$SkipGStreamer,
    [switch]$SkipBuild,
    [string]$GStreamerPath = ""
)

# Enable verbose output
$VerbosePreference = "Continue"

Write-Host "=== Starting Windows Build Script ===" -ForegroundColor Cyan
Write-Host "Parameters: SkipGStreamer=$SkipGStreamer, GStreamerPath='$GStreamerPath'" -ForegroundColor Gray
Write-Host "Current directory: $(Get-Location)" -ForegroundColor Gray
Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)" -ForegroundColor Gray
Write-Host "Building Portable Summit Hip Numbers Media Player for Windows..." -ForegroundColor Green

# Build the application (unless skipped)
if (!$SkipBuild) {
    Write-Host "Running cargo build with verbose output..." -ForegroundColor Yellow
    cargo build --release --verbose
    if ($LASTEXITCODE -ne 0) {
        Write-Host "=== Build Failed ===" -ForegroundColor Red
        Write-Host "Cargo build exited with code: $LASTEXITCODE" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "Skipping build step (already built)..." -ForegroundColor Yellow
}

# Find the built exe
$exePath = "target\release\summit_hip_numbers.exe"
if (!(Test-Path $exePath)) {
    Write-Host "Exe not found at $exePath! Build might have failed." -ForegroundColor Red
    exit 1
}

Write-Host "Build successful!" -ForegroundColor Green

# Create portable distribution package
$distDir = "dist"
Write-Host "Creating dist directory: $distDir" -ForegroundColor Yellow
if (Test-Path $distDir) {
    Write-Host "Removing existing dist directory..." -ForegroundColor Yellow
    Remove-Item $distDir -Recurse -Force
}
New-Item -ItemType Directory -Path $distDir | Out-Null
Write-Host "Dist directory created" -ForegroundColor Green

# Copy exe
Write-Host "Copying executable..." -ForegroundColor Gray
Copy-Item $exePath (Join-Path $distDir "summit_hip_numbers.exe")
$exeSize = (Get-Item (Join-Path $distDir "summit_hip_numbers.exe")).Length / 1MB
Write-Host "Copied executable ($( [math]::Round($exeSize, 2)) MB)" -ForegroundColor Green

# Find GStreamer installation
if (!$SkipGStreamer) {
    Write-Host "Looking for GStreamer installation..." -ForegroundColor Yellow
    if (!$GStreamerPath) {
        # Try to find GStreamer automatically
        $possiblePaths = @(
            "C:\msys64\mingw64",
            "C:\gstreamer\1.0\msvc_x86_64\",
            "C:\gstreamer\1.0\mingw_x86_64\",
            "C:\gstreamer\1.0\x86_64\",
            "${env:ProgramFiles}\gstreamer\1.0\x86_64\",
            "${env:ProgramFiles(x86)}\gstreamer\1.0\x86_64\"
        )

        Write-Host "Checking possible GStreamer paths:" -ForegroundColor Gray
        foreach ($path in $possiblePaths) {
            Write-Host "  Checking: $path" -ForegroundColor Gray
            if (Test-Path $path) {
                $GStreamerPath = $path
                Write-Host "  Found at: $path" -ForegroundColor Green
                break
            } else {
                Write-Host "  Not found" -ForegroundColor Gray
            }
        }
    }

    if ($GStreamerPath -and (Test-Path $GStreamerPath)) {
        Write-Host "Using GStreamer at: $GStreamerPath" -ForegroundColor Green

        # Copy essential GStreamer files to dist
        Write-Host "Copying GStreamer runtime files..." -ForegroundColor Yellow

        # Copy bin directory (ALL DLLs - don't be selective)
        $binPath = Join-Path $GStreamerPath "bin"
        if (Test-Path $binPath) {
            Write-Host "  Copying ALL DLLs from $binPath..." -ForegroundColor Gray
            
            # Copy all DLLs without filtering
            Get-ChildItem -Path $binPath -Filter "*.dll" | ForEach-Object {
                Copy-Item $_.FullName -Destination $distDir -Force
                Write-Host "    Copied: $($_.Name)" -ForegroundColor Gray
            }
            
            $dllCount = (Get-ChildItem $distDir -Filter "*.dll").Count
            Write-Host "  Copied $dllCount DLLs total" -ForegroundColor Green

            # Verify critical DLLs are present
            $criticalDlls = @(
                "libglib-2.0-0.dll",
                "libgobject-2.0-0.dll",
                "libgio-2.0-0.dll",
                "libgstapp-1.0-0.dll",
                "libgstreamer-1.0-0.dll",
                "libgstvideo-1.0-0.dll",
                "libgstbase-1.0-0.dll",
                "libgstpbutils-1.0-0.dll",
                "libgmodule-2.0-0.dll",
                "libintl-8.dll",
                "libffi-8.dll",
                "libpcre2-8-0.dll",
                "libwinpthread-1.dll",
                "zlib1.dll"
            )
            
            Write-Host "  Verifying critical DLLs:" -ForegroundColor Yellow
            $missingDlls = @()
            foreach ($dll in $criticalDlls) {
                $dllPath = Join-Path $distDir $dll
                if (Test-Path $dllPath) {
                    Write-Host "    ✓ $dll" -ForegroundColor Green
                } else {
                    Write-Host "    ✗ $dll MISSING" -ForegroundColor Red
                    $missingDlls += $dll
                }
            }
            
            if ($missingDlls.Count -gt 0) {
                Write-Warning "Some critical DLLs are missing: $($missingDlls -join ', ')"
                Write-Host "Searching for missing DLLs in GStreamer installation..." -ForegroundColor Yellow
                
                foreach ($dll in $missingDlls) {
                    # Search recursively in GStreamer path
                    $found = Get-ChildItem -Path $GStreamerPath -Filter $dll -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($found) {
                        Copy-Item $found.FullName -Destination $distDir -Force
                        Write-Host "    Found and copied: $dll from $($found.DirectoryName)" -ForegroundColor Green
                    } else {
                        Write-Warning "    Could not find: $dll anywhere in GStreamer installation"
                    }
                }
            }
        } else {
            Write-Host "  Bin directory not found at $binPath" -ForegroundColor Yellow
        }

        # Copy lib\gstreamer-1.0 directory (plugins)
        $pluginPath = Join-Path $GStreamerPath "lib\gstreamer-1.0"
        if (Test-Path $pluginPath) {
            Write-Host "  Copying plugins from $pluginPath..." -ForegroundColor Gray
            $pluginDest = Join-Path $distDir "lib\gstreamer-1.0"
            Copy-Item $pluginPath $pluginDest -Recurse -Force
            $pluginFileCount = (Get-ChildItem $pluginDest -Recurse -File).Count
            Write-Host "  Copied $pluginFileCount plugin files" -ForegroundColor Green
        } else {
            Write-Host "  Plugin directory not found at $pluginPath" -ForegroundColor Yellow
        }

        # Copy share directory (schemas and other data)
        $sharePath = Join-Path $GStreamerPath "share"
        if (Test-Path $sharePath) {
            Write-Host "  Copying share directory from $sharePath..." -ForegroundColor Gray
            $shareDest = Join-Path $distDir "share"
            Copy-Item $sharePath $shareDest -Recurse -Force
            $shareFileCount = (Get-ChildItem $shareDest -Recurse -File).Count
            Write-Host "  Share directory copied ($shareFileCount files)" -ForegroundColor Green
        } else {
            Write-Host "  Share directory not found at $sharePath" -ForegroundColor Yellow
        }

        # Copy any additional lib files that might be needed
        $libPath = Join-Path $GStreamerPath "lib"
        if (Test-Path $libPath) {
            Write-Host "  Copying additional lib files..." -ForegroundColor Gray
            $libDest = Join-Path $distDir "lib"
            if (!(Test-Path $libDest)) {
                New-Item -ItemType Directory -Path $libDest | Out-Null
            }
            
            # Copy .a files and other library files (excluding gstreamer-1.0 which we already copied)
            Get-ChildItem -Path $libPath -Filter "*.a" -File | ForEach-Object {
                Copy-Item $_.FullName -Destination $libDest -Force
            }
        }

        Write-Host "GStreamer runtime files copied successfully" -ForegroundColor Green
    } else {
        Write-Warning "GStreamer not found. The portable version may not work without GStreamer installed on the target system."
    }
}

# Copy config.toml if exists
if (Test-Path "config.toml") {
    Write-Host "Copying config.toml..." -ForegroundColor Gray
    Copy-Item "config.toml" $distDir
    $configSize = (Get-Item (Join-Path $distDir "config.toml")).Length / 1KB
    Write-Host "Config file copied ($( [math]::Round($configSize, 2)) KB)" -ForegroundColor Green
} else {
    Write-Host "Config file not found" -ForegroundColor Yellow
}

# Copy videos directory if it exists
if (Test-Path "videos") {
    Write-Host "Copying videos directory..." -ForegroundColor Gray
    Copy-Item "videos" $distDir -Recurse
    $videoFilesCount = (Get-ChildItem (Join-Path $distDir "videos") -Recurse).Count
    Write-Host "Videos directory copied ($videoFilesCount files)" -ForegroundColor Green
} else {
    Write-Host "Videos directory not found" -ForegroundColor Yellow
}

# Copy splash directory if it exists
if (Test-Path "splash") {
    Write-Host "Copying splash directory..." -ForegroundColor Gray
    Copy-Item "splash" $distDir -Recurse
    $splashFilesCount = (Get-ChildItem (Join-Path $distDir "splash") -Recurse).Count
    Write-Host "Splash directory copied ($splashFilesCount files)" -ForegroundColor Green
} else {
    Write-Host "Splash directory not found" -ForegroundColor Yellow
}

# Create a launcher script for better compatibility
Write-Host "Creating launcher script..." -ForegroundColor Yellow
$launcherScript = @"
@echo off
REM Summit Hip Numbers Media Player Launcher
REM This script sets up the environment for the portable version

echo Starting Summit Hip Numbers Media Player...

REM Set GStreamer environment variables for portable version
set GST_PLUGIN_PATH=%~dp0lib\gstreamer-1.0
set GST_PLUGIN_SYSTEM_PATH=%~dp0lib\gstreamer-1.0
set PATH=%~dp0;%PATH%

REM Change to the application directory
cd /d "%~dp0"

REM Run the application
"%~dp0summit_hip_numbers.exe"

pause
"@

$launcherScript | Out-File -FilePath (Join-Path $distDir "run.bat") -Encoding ASCII
Write-Host "Launcher script created" -ForegroundColor Green

# Create a README for the portable version
Write-Host "Creating README file..." -ForegroundColor Yellow
$readmeContent = @"
Summit Hip Numbers Media Player - Portable Version
===============================================

This is a portable version of the Summit Hip Numbers Media Player that includes all necessary dependencies.

To run the application:
1. Double-click "run.bat" (Windows batch file)

Files:
- summit_hip_numbers.exe: Main application
- config.toml: Configuration file
- videos/: Directory for your video files
- splash/: Directory for splash images
- lib/, share/, and *.dll files: GStreamer runtime
- run.bat: Launcher script

Configuration:
Edit config.toml to customize settings like video directory path and splash screen options.

Adding Videos:
Place your MP4 video files in the "videos" directory. Files will be automatically sorted alphabetically and assigned hip numbers (001, 002, etc.).

Requirements:
- Windows 10 or later

For more information, visit: https://github.com/millerjes37/summit_hip_numbers
"@

$readmeContent | Out-File -FilePath (Join-Path $distDir "README.txt") -Encoding UTF8
Write-Host "README file created" -ForegroundColor Green

Write-Host "Portable distribution package created in: $distDir" -ForegroundColor Green
Write-Host "Contents:" -ForegroundColor Cyan
Get-ChildItem $distDir | ForEach-Object {
    $size = if ($_.PSIsContainer) { "DIR" } else { "$([math]::Round($_.Length / 1MB, 2)) MB" }
    Write-Host "  - $($_.Name) ($size)" -ForegroundColor Cyan
}

# Create a zip file for easy distribution
$zipPath = "summit_hip_numbers_portable.zip"
Write-Host "Creating zip archive: $zipPath" -ForegroundColor Yellow
if (Test-Path $zipPath) {
    Write-Host "Removing existing zip file..." -ForegroundColor Gray
    Remove-Item $zipPath -Force
}

Compress-Archive -Path "$($distDir)\*" -DestinationPath $zipPath -Force
$zipSize = (Get-Item $zipPath).Length / 1MB
Write-Host "Zip archive created: $zipPath ($( [math]::Round($zipSize, 2)) MB)" -ForegroundColor Green

# Create Inno Setup installer
Write-Host "Checking for Inno Setup..." -ForegroundColor Yellow
if (Get-Command "iscc" -ErrorAction SilentlyContinue) {
    Write-Host "Inno Setup found, creating installer..." -ForegroundColor Green
    & iscc installer.iss
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Installer created successfully" -ForegroundColor Green
    } else {
        Write-Warning "Failed to create installer (exit code: $LASTEXITCODE)"
    }
} else {
    Write-Host "Inno Setup not found, skipping installer creation" -ForegroundColor Yellow
}

Write-Host "`n=== Build Complete ===" -ForegroundColor Green
Write-Host "Portable distribution ready!" -ForegroundColor Green
Write-Host "Files created:" -ForegroundColor Cyan
Write-Host "  - Dist folder: $distDir" -ForegroundColor Cyan
Write-Host "  - Zip archive: $zipPath" -ForegroundColor Cyan
if (Test-Path "dist\summit_hip_numbers_installer.exe") {
    Write-Host "  - Installer: dist\summit_hip_numbers_installer.exe" -ForegroundColor Cyan
}
Write-Host "`nTo deploy:" -ForegroundColor Yellow
Write-Host "1. Copy the '$distDir' folder to a flash drive" -ForegroundColor White
Write-Host "2. Double-click 'run.bat' to start the application" -ForegroundColor White