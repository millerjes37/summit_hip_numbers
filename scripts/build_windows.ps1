# Build script for Windows
# Creates a portable distribution with all dependencies
# Run this on a Windows machine with Rust and FFmpeg installed

param(
    [switch]$SkipFFmpeg,
    [switch]$SkipBuild,
    [string]$FFmpegPath = ""
)

# Enable verbose output
$VerbosePreference = "Continue"

Write-Host "=== Starting Windows Build Script ===" -ForegroundColor Cyan
Write-Host "Parameters: SkipFFmpeg=$SkipFFmpeg, FFmpegPath='$FFmpegPath'" -ForegroundColor Gray
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

# Find FFmpeg installation
if (!$SkipFFmpeg) {
    Write-Host "Looking for FFmpeg installation..." -ForegroundColor Yellow
    if (!$FFmpegPath) {
        # Try to find FFmpeg automatically
        $possiblePaths = @(
            "C:\msys64\mingw64",
            "C:\ffmpeg",
            "${env:ProgramFiles}\ffmpeg",
            "${env:ProgramFiles(x86)}\ffmpeg",
            "C:\vcpkg\installed\x64-windows"
        )

        Write-Host "Checking possible FFmpeg paths:" -ForegroundColor Gray
        foreach ($path in $possiblePaths) {
            Write-Host "  Checking: $path" -ForegroundColor Gray
            if (Test-Path $path) {
                $FFmpegPath = $path
                Write-Host "  Found at: $path" -ForegroundColor Green
                break
            } else {
                Write-Host "  Not found" -ForegroundColor Gray
            }
        }
    }

    if ($FFmpegPath -and (Test-Path $FFmpegPath)) {
        Write-Host "Using FFmpeg at: $FFmpegPath" -ForegroundColor Green

        # Copy essential FFmpeg files to dist
        Write-Host "Copying FFmpeg runtime files..." -ForegroundColor Yellow

        # Copy bin directory (FFmpeg DLLs)
        $binPath = Join-Path $FFmpegPath "bin"
        if (Test-Path $binPath) {
            Write-Host "  Copying FFmpeg DLLs from $binPath..." -ForegroundColor Gray
            Write-Host "  Source: $binPath" -ForegroundColor Gray
            Write-Host "  Destination: $distDir" -ForegroundColor Gray
            
            # Get all DLLs first
            $dllFiles = Get-ChildItem -Path $binPath -Filter "*.dll" -File
            Write-Host "  Found $($dllFiles.Count) DLL files to copy" -ForegroundColor Yellow
            
            if ($dllFiles.Count -eq 0) {
                Write-Error "No DLL files found in $binPath"
                Write-Host "Contents of bin directory:" -ForegroundColor Yellow
                Get-ChildItem -Path $binPath | Select-Object Name, Length | Format-Table
                exit 1
            }
            
            # Copy all DLLs
            $copiedCount = 0
            foreach ($dll in $dllFiles) {
                try {
                    Copy-Item $dll.FullName -Destination $distDir -Force -ErrorAction Stop
                    $copiedCount++
                    if ($copiedCount -le 5) {
                        Write-Host "    Copied: $($dll.Name)" -ForegroundColor Gray
                    }
                } catch {
                    Write-Error "Failed to copy $($dll.Name): $_"
                }
            }
            
            if ($copiedCount -gt 5) {
                Write-Host "    ... and $($copiedCount - 5) more DLLs" -ForegroundColor Gray
            }
            
            # Verify DLLs were copied
            $dllCount = (Get-ChildItem $distDir -Filter "*.dll" -File).Count
            Write-Host "  Copied $dllCount DLLs total" -ForegroundColor Green
            
            if ($dllCount -eq 0) {
                Write-Error "Failed to copy any DLLs to dist directory!"
                exit 1
            }

            # Verify critical FFmpeg DLLs are present
            $criticalDlls = @(
                "avutil-*.dll",
                "avcodec-*.dll",
                "avformat-*.dll",
                "swscale-*.dll",
                "swresample-*.dll"
            )
            
            Write-Host "  Verifying critical FFmpeg DLLs:" -ForegroundColor Yellow
            $missingDlls = @()
            foreach ($dllPattern in $criticalDlls) {
                $found = Get-ChildItem -Path $distDir -Filter $dllPattern -File
                if ($found) {
                    foreach ($dll in $found) {
                        Write-Host "    ✓ $($dll.Name)" -ForegroundColor Green
                    }
                } else {
                    Write-Host "    ✗ $dllPattern MISSING" -ForegroundColor Red
                    $missingDlls += $dllPattern
                }
            }
            
            if ($missingDlls.Count -gt 0) {
                Write-Warning "Some critical FFmpeg DLLs are missing: $($missingDlls -join ', ')"
                Write-Host "Searching for missing DLLs in FFmpeg installation..." -ForegroundColor Yellow
                
                foreach ($dllPattern in $missingDlls) {
                    # Search recursively in FFmpeg path
                    $found = Get-ChildItem -Path $FFmpegPath -Filter $dllPattern -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($found) {
                        Copy-Item $found.FullName -Destination $distDir -Force
                        Write-Host "    Found and copied: $($found.Name) from $($found.DirectoryName)" -ForegroundColor Green
                    } else {
                        Write-Warning "    Could not find: $dllPattern anywhere in FFmpeg installation"
                    }
                }
            }
        } else {
            Write-Host "  Bin directory not found at $binPath" -ForegroundColor Yellow
        }

        Write-Host "FFmpeg runtime files copied successfully" -ForegroundColor Green
    } else {
        Write-Warning "FFmpeg not found. The portable version may not work without FFmpeg DLLs."
        Write-Host "You can download FFmpeg from: https://github.com/BtbN/FFmpeg-Builds/releases" -ForegroundColor Yellow
    }
}

# Copy distribution config if exists, otherwise use regular config
if (Test-Path "config.dist.toml") {
    Write-Host "Copying distribution config as config.toml..." -ForegroundColor Gray
    Copy-Item "config.dist.toml" (Join-Path $distDir "config.toml")
    $configSize = (Get-Item (Join-Path $distDir "config.toml")).Length / 1KB
    Write-Host "Distribution config file copied ($( [math]::Round($configSize, 2)) KB)" -ForegroundColor Green
} elseif (Test-Path "config.toml") {
    Write-Host "Copying config.toml..." -ForegroundColor Gray
    Copy-Item "config.toml" $distDir
    $configSize = (Get-Item (Join-Path $distDir "config.toml")).Length / 1KB
    Write-Host "Config file copied ($( [math]::Round($configSize, 2)) KB)" -ForegroundColor Green
} else {
    Write-Host "Config file not found" -ForegroundColor Yellow
}

# Create directory structure for distribution
New-Item -ItemType Directory -Path (Join-Path $distDir "videos") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $distDir "splash") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $distDir "logo") -Force | Out-Null

# Copy videos directory - check both development and production locations
$videosSource = if (Test-Path "assets\videos") { "assets\videos" } elseif (Test-Path "videos") { "videos" } else { $null }
if ($videosSource) {
    Write-Host "Copying videos from $videosSource..." -ForegroundColor Gray
    Copy-Item "$videosSource\*" (Join-Path $distDir "videos") -Recurse -Force
    $videoFilesCount = (Get-ChildItem (Join-Path $distDir "videos") -Recurse -File).Count
    Write-Host "Videos copied ($videoFilesCount files)" -ForegroundColor Green
} else {
    Write-Host "Videos directory not found (checked assets\videos and videos)" -ForegroundColor Yellow
}

# Copy splash directory - check both development and production locations
$splashSource = if (Test-Path "assets\splash") { "assets\splash" } elseif (Test-Path "splash") { "splash" } else { $null }
if ($splashSource) {
    Write-Host "Copying splash images from $splashSource..." -ForegroundColor Gray
    Copy-Item "$splashSource\*" (Join-Path $distDir "splash") -Recurse -Force
    $splashFilesCount = (Get-ChildItem (Join-Path $distDir "splash") -Recurse -File).Count
    Write-Host "Splash images copied ($splashFilesCount files)" -ForegroundColor Green
} else {
    Write-Host "Splash directory not found (checked assets\splash and splash)" -ForegroundColor Yellow
}

# Copy logo directory - check both development and production locations
$logoSource = if (Test-Path "assets\logo") { "assets\logo" } elseif (Test-Path "logo") { "logo" } else { $null }
if ($logoSource) {
    Write-Host "Copying logo from $logoSource..." -ForegroundColor Gray
    Copy-Item "$logoSource\*" (Join-Path $distDir "logo") -Recurse -Force
    $logoFilesCount = (Get-ChildItem (Join-Path $distDir "logo") -Recurse -File).Count
    Write-Host "Logo copied ($logoFilesCount files)" -ForegroundColor Green
} else {
    Write-Host "Logo directory not found (checked assets\logo and logo)" -ForegroundColor Yellow
}

# Create a launcher script for better compatibility
Write-Host "Creating launcher script..." -ForegroundColor Yellow
$launcherScript = @"
@echo off
REM Summit Hip Numbers Media Player Launcher
REM This script sets up the environment for the portable version

echo Starting Summit Hip Numbers Media Player...

REM Set PATH to include FFmpeg DLLs
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
- *.dll files: FFmpeg runtime libraries
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

# Final verification before zipping
Write-Host "Final verification of dist directory before zipping:" -ForegroundColor Yellow
$finalDllCount = (Get-ChildItem $distDir -Filter "*.dll" -File).Count
Write-Host "  DLLs in dist: $finalDllCount" -ForegroundColor $(if ($finalDllCount -gt 0) { "Green" } else { "Red" })

if ($finalDllCount -eq 0) {
    Write-Error "CRITICAL: No DLLs found in dist directory before zipping! Aborting."
    Write-Host "Contents of dist directory:" -ForegroundColor Yellow
    Get-ChildItem $distDir -Recurse | Select-Object FullName, Length | Format-Table
    exit 1
}

Write-Host "  Files in dist:" -ForegroundColor Yellow
Get-ChildItem $distDir -File | ForEach-Object {
    Write-Host "    - $($_.Name) ($([math]::Round($_.Length / 1MB, 2)) MB)"
}

if (Test-Path $zipPath) {
    Write-Host "Removing existing zip file..." -ForegroundColor Gray
    Remove-Item $zipPath -Force
}

Write-Host "Compressing archive..." -ForegroundColor Yellow
Compress-Archive -Path "$($distDir)\*" -DestinationPath $zipPath -Force
$zipSize = (Get-Item $zipPath).Length / 1MB
Write-Host "Zip archive created: $zipPath ($( [math]::Round($zipSize, 2)) MB)" -ForegroundColor Green

# Verify zip contents
Write-Host "Verifying zip contents..." -ForegroundColor Yellow
$tempVerify = "temp_verify_zip"
if (Test-Path $tempVerify) { Remove-Item $tempVerify -Recurse -Force }
Expand-Archive -Path $zipPath -DestinationPath $tempVerify
$zipDllCount = (Get-ChildItem $tempVerify -Filter "*.dll" -File).Count
Write-Host "  DLLs in zip: $zipDllCount" -ForegroundColor $(if ($zipDllCount -gt 0) { "Green" } else { "Red" })
Remove-Item $tempVerify -Recurse -Force

if ($zipDllCount -eq 0) {
    Write-Error "CRITICAL: No DLLs found in created zip file!"
    exit 1
}

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