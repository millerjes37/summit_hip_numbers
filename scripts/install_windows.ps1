# Windows PowerShell install script for Summit Hip Numbers Media Player
# Downloads source code and installs dependencies
# Requires: PowerShell 5.1+, Windows 10/11 with winget

param(
    [switch]$SkipBuild,
    [switch]$Clean,
    [string]$RepoUrl = "https://github.com/millerjes37/summit_hip_numbers.git"
)

Write-Host "Installing Summit Hip Numbers Media Player on Windows..." -ForegroundColor Green

# Check if we're in the project directory, if not, clone the repository
$currentDir = Split-Path -Path (Get-Location) -Leaf
if ($currentDir -ne "summit_hip_numbers") {
    Write-Host "Cloning repository..." -ForegroundColor Yellow

    # Check if directory already exists
    if (Test-Path "summit_hip_numbers") {
        Write-Host "Project directory already exists. Using existing directory." -ForegroundColor Green
        Set-Location "summit_hip_numbers"
    } else {
        try {
            & git clone $RepoUrl
            if ($LASTEXITCODE -eq 0) {
                Set-Location "summit_hip_numbers"
                Write-Host "Repository cloned successfully" -ForegroundColor Green
            } else {
                Write-Error "Failed to clone repository (exit code: $LASTEXITCODE)"
                exit 1
            }
        } catch {
            Write-Error "Failed to clone repository: $_"
            Write-Host "Troubleshooting:" -ForegroundColor Yellow
            Write-Host "- Ensure internet connection is available" -ForegroundColor Yellow
            Write-Host "- Check if git is properly installed and configured" -ForegroundColor Yellow
            Write-Host "- Try running: git clone $RepoUrl manually" -ForegroundColor Yellow
            exit 1
        }
    }
} else {
    Write-Host "Already in project directory" -ForegroundColor Green
}

# Verify we're in the correct directory with the right files
if (!(Test-Path "Cargo.toml")) {
    Write-Error "Cargo.toml not found. This doesn't appear to be the summit_hip_numbers project directory."
    exit 1
}

Write-Host "Installing dependencies..." -ForegroundColor Green

# Check if required tools are available
if (!(Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Error "winget is required but not available. Please update to Windows 10/11 or install winget manually."
    exit 1
}

if (!(Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error "git is required but not available. Please install Git from https://git-scm.com/downloads"
    exit 1
}

# Configure git if not already configured
Write-Host "Checking git configuration..." -ForegroundColor Yellow
$gitUserName = & git config --global user.name 2>$null
$gitUserEmail = & git config --global user.email 2>$null

if (!$gitUserName -or !$gitUserEmail) {
    Write-Host "Git not configured. Setting up basic configuration..." -ForegroundColor Yellow
    try {
        & git config --global user.name "Summit Hip Numbers User" 2>$null
        & git config --global user.email "user@localhost" 2>$null
        Write-Host "Git configured with default settings" -ForegroundColor Green
    } catch {
        Write-Warning "Could not configure git. Clone might fail if git is not properly configured."
    }
} else {
    Write-Host "Git already configured" -ForegroundColor Green
}

# Clean previous installations if requested
if ($Clean) {
    Write-Host "Cleaning previous installations..."
    if (Test-Path "target") {
        Remove-Item "target" -Recurse -Force
    }
    if (Test-Path "Cargo.lock") {
        Remove-Item "Cargo.lock" -Force
    }
}

# Install Rust if not present
if (!(Get-Command cargo -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Rust..." -ForegroundColor Yellow
    try {
        winget install Rustlang.Rust --accept-source-agreements --accept-package-agreements
        # Refresh environment
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
    } catch {
        Write-Error "Failed to install Rust: $_"
        exit 1
    }
} else {
    Write-Host "Rust already installed" -ForegroundColor Green
}

# Install FFmpeg
Write-Host "Installing FFmpeg..." -ForegroundColor Yellow
try {
    # Try winget first
    winget install Gyan.FFmpeg --accept-source-agreements --accept-package-agreements
    Write-Host "FFmpeg installed via winget" -ForegroundColor Green
} catch {
    Write-Host "Winget installation failed, trying manual download..." -ForegroundColor Yellow
    # Download FFmpeg build from BtbN/FFmpeg-Builds
    $ffmpegUrl = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl-shared.zip"
    $zipPath = "$env:TEMP\ffmpeg.zip"
    $extractPath = "C:\ffmpeg"
    
    try {
        Write-Host "Downloading FFmpeg..." -ForegroundColor Yellow
        Invoke-WebRequest -Uri $ffmpegUrl -OutFile $zipPath -UseBasicParsing
        Write-Host "Downloaded FFmpeg archive" -ForegroundColor Green
        
        # Extract archive
        Write-Host "Extracting FFmpeg..." -ForegroundColor Yellow
        if (!(Test-Path $extractPath)) {
            New-Item -ItemType Directory -Path $extractPath | Out-Null
        }
        Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
        
        # Find the extracted folder (it has a version name)
        $extractedFolder = Get-ChildItem -Path $extractPath -Directory | Select-Object -First 1
        if ($extractedFolder) {
            # Move contents to C:\ffmpeg
            Move-Item -Path "$($extractedFolder.FullName)\*" -Destination $extractPath -Force
            Remove-Item -Path $extractedFolder.FullName -Recurse -Force
        }
        
        Write-Host "FFmpeg extracted to $extractPath" -ForegroundColor Green
    } catch {
        Write-Error "Failed to download/install FFmpeg: $_"
        Write-Host "Please manually download from https://github.com/BtbN/FFmpeg-Builds/releases" -ForegroundColor Yellow
        Write-Host "Or from: https://www.gyan.dev/ffmpeg/builds/" -ForegroundColor Yellow
        exit 1
    }
}

# Set environment variables for FFmpeg
Write-Host "Setting environment variables..." -ForegroundColor Yellow

# Possible FFmpeg installation paths (check in order of preference)
$ffmpegPaths = @(
    "C:\ffmpeg",  # Manual installation
    "${env:ProgramFiles}\ffmpeg",  # Program Files
    "C:\ProgramData\chocolatey\lib\ffmpeg\tools\ffmpeg",  # Chocolatey
    "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Gyan.FFmpeg*"  # Winget
)

$ffmpegFound = $false
foreach ($pathPattern in $ffmpegPaths) {
    $paths = Get-Item $pathPattern -ErrorAction SilentlyContinue
    foreach ($path in $paths) {
        if (Test-Path $path) {
            $binPath = if (Test-Path "$path\bin") { "$path\bin" } else { $path }
            $env:FFMPEG_DIR = $path
            $env:PATH = "$binPath;" + $env:PATH
            
            # Set PKG_CONFIG_PATH if pkgconfig exists
            $pkgConfigPath = "$path\lib\pkgconfig"
            if (Test-Path $pkgConfigPath) {
                $env:PKG_CONFIG_PATH = $pkgConfigPath
            }
            
            Write-Host "FFmpeg found at: $path" -ForegroundColor Green
            $ffmpegFound = $true
            break
        }
    }
    if ($ffmpegFound) { break }
}

if (!$ffmpegFound) {
    Write-Warning "FFmpeg installation not found in standard locations."
    Write-Host "Please ensure FFmpeg is installed and set FFMPEG_DIR and PATH manually." -ForegroundColor Yellow
    Write-Host "Typical installation path: C:\ffmpeg" -ForegroundColor Yellow
}

# Check for Visual Studio Build Tools (required for linking)
Write-Host "Checking for Visual Studio Build Tools..." -ForegroundColor Yellow
$vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vsWhere) {
    $vsPath = & $vsWhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($vsPath) {
        Write-Host "Visual Studio Build Tools found" -ForegroundColor Green
    } else {
        Write-Warning "Visual Studio Build Tools not found. You may need to install 'Desktop development with C++' workload."
        Write-Host "Download from: https://visualstudio.microsoft.com/downloads/" -ForegroundColor Yellow
    }
} else {
    Write-Warning "Cannot verify Visual Studio installation. Ensure you have Visual Studio Build Tools installed."
}

# Verify installations
Write-Host "Verifying installations..." -ForegroundColor Yellow
$rustVersion = & cargo --version 2>&1
if ($rustVersion) {
    Write-Host "Rust installed: $rustVersion" -ForegroundColor Green
} else {
    Write-Warning "Rust verification failed"
}

$ffmpegVersion = & ffmpeg -version 2>&1 | Select-String "ffmpeg version"
if ($ffmpegVersion) {
    Write-Host "FFmpeg installed: $($ffmpegVersion.Line)" -ForegroundColor Green
    
    # Check for FFmpeg libraries
    Write-Host "Checking FFmpeg libraries..." -ForegroundColor Yellow
    $ffprobeCheck = Get-Command ffprobe -ErrorAction SilentlyContinue
    if ($ffprobeCheck) {
        Write-Host "✓ ffprobe available" -ForegroundColor Green
    } else {
        Write-Warning "✗ ffprobe not found"
    }
} else {
    Write-Warning "FFmpeg verification failed"
}

# Build the Rust project if not skipped
if (!$SkipBuild) {
    Write-Host "Building Rust project..." -ForegroundColor Yellow

    # Ensure we're using the correct Rust target for Windows
    $rustTarget = & rustc --print host-tuple
    Write-Host "Rust target: $rustTarget" -ForegroundColor Cyan

    try {
        & cargo build --release
        Write-Host "Build completed successfully!" -ForegroundColor Green
    } catch {
        Write-Error "Build failed: $_"
        Write-Host "If build fails due to linking issues, ensure:" -ForegroundColor Yellow
        Write-Host "1. Visual Studio Build Tools are installed" -ForegroundColor Yellow
        Write-Host "2. FFmpeg is properly installed" -ForegroundColor Yellow
        Write-Host "3. Environment variables are set correctly" -ForegroundColor Yellow
        exit 1
    }

    # Use the build_windows.ps1 script for portable distribution
    Write-Host "`nCreating portable distribution..." -ForegroundColor Yellow
    Write-Host "Running build_windows.ps1 script..." -ForegroundColor Yellow
    
    $buildScriptPath = "scripts\build_windows.ps1"
    if (Test-Path $buildScriptPath) {
        & $buildScriptPath -SkipBuild -FFmpegPath $(if ($ffmpegFound -and $env:FFMPEG_DIR) { $env:FFMPEG_DIR } else { "" })
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Portable distribution created successfully!" -ForegroundColor Green
        } else {
            Write-Warning "Portable distribution creation had issues (exit code: $LASTEXITCODE)"
        }
    } else {
        Write-Warning "Build script not found at $buildScriptPath"
        Write-Host "You can manually run: .\scripts\build_windows.ps1" -ForegroundColor Yellow
    }
}

Write-Host "`nInstallation complete!" -ForegroundColor Green
Write-Host "The Summit Hip Numbers Media Player has been installed successfully!" -ForegroundColor Green
Write-Host "To run the application: cargo run --release" -ForegroundColor Cyan
if (Test-Path "summit_hip_numbers_portable.zip") {
    Write-Host "Portable version created: summit_hip_numbers_portable.zip" -ForegroundColor Cyan
}

Write-Host "`nImportant Notes:" -ForegroundColor Yellow
Write-Host "- Visual Studio Build Tools with C++ support are required for compilation" -ForegroundColor Yellow
Write-Host "- FFmpeg is required for video playback (much simpler than GStreamer!)" -ForegroundColor Yellow
Write-Host "- Portable builds only need ~5 FFmpeg DLLs (vs 50+ with GStreamer)" -ForegroundColor Yellow
Write-Host "- You may need to restart your PowerShell session for environment changes to take effect" -ForegroundColor Yellow

# Set persistent environment variables for future sessions
Write-Host "`nTo make environment variables persistent, add to your PowerShell profile:" -ForegroundColor Cyan
if ($ffmpegFound) {
    Write-Host "`$env:FFMPEG_DIR = '$env:FFMPEG_DIR'" -ForegroundColor Cyan
    Write-Host "`$env:PATH = '$(Split-Path $env:FFMPEG_DIR)\bin;' + `$env:PATH" -ForegroundColor Cyan
}

Write-Host "`nNext Steps:" -ForegroundColor Cyan
Write-Host "1. Add your video files to the 'assets/videos' directory" -ForegroundColor Cyan
Write-Host "2. Configure settings in 'config.toml' if needed" -ForegroundColor Cyan
Write-Host "3. Run 'cargo run --release' to start the application" -ForegroundColor Cyan
if (Test-Path "dist") {
    Write-Host "4. Or use the portable distribution in the 'dist' folder" -ForegroundColor Cyan
}