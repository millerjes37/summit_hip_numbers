# Windows PowerShell install script for Summit Hip Numbers Media Player dependencies
# Requires: PowerShell 5.1+, Windows 10/11 with winget

param(
    [switch]$SkipBuild,
    [switch]$Clean
)

Write-Host "Installing dependencies for Summit Hip Numbers Media Player on Windows..." -ForegroundColor Green

# Check if winget is available
if (!(Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Error "winget is required but not available. Please update to Windows 10/11 or install winget manually."
    exit 1
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

# Install GStreamer with all plugins
Write-Host "Installing GStreamer (full)..." -ForegroundColor Yellow
try {
    # Install the full GStreamer package which includes all plugins
    winget install GStreamer.GStreamer --accept-source-agreements --accept-package-agreements
} catch {
    Write-Error "Failed to install GStreamer: $_"
    Write-Host "Note: If installation fails, you can manually download from https://gstreamer.freedesktop.org/download/" -ForegroundColor Yellow
    exit 1
}

# Set environment variables for pkg-config and linking
Write-Host "Setting environment variables..." -ForegroundColor Yellow

# Possible GStreamer installation paths (check in order of preference)
$gstreamerPaths = @(
    "C:\gstreamer\1.0\x86_64\",  # winget/msi default
    "C:\gstreamer\1.0\mingw_x86_64\",  # mingw variant
    "${env:ProgramFiles}\gstreamer\1.0\x86_64\",  # Program Files
    "${env:ProgramFiles(x86)}\gstreamer\1.0\x86_64\"  # Program Files (x86)
)

$gstreamerFound = $false
foreach ($path in $gstreamerPaths) {
    if (Test-Path $path) {
        $env:PKG_CONFIG_PATH = "$path\lib\pkgconfig"
        $env:GSTREAMER_ROOT = $path
        $env:PATH = "$path\bin;" + $env:PATH
        # Also add lib path for linking
        $env:LIB = "$path\lib;" + $env:LIB
        Write-Host "GStreamer found at: $path" -ForegroundColor Green
        $gstreamerFound = $true
        break
    }
}

if (!$gstreamerFound) {
    Write-Warning "GStreamer installation not found in standard locations."
    Write-Host "Please ensure GStreamer is installed and set GSTREAMER_ROOT, PKG_CONFIG_PATH, and PATH manually." -ForegroundColor Yellow
    Write-Host "Typical installation path: C:\gstreamer\1.0\x86_64\" -ForegroundColor Yellow
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

$gstreamerVersion = & gst-launch-1.0 --version 2>&1 | Select-String "GStreamer"
if ($gstreamerVersion) {
    Write-Host "GStreamer installed: $($gstreamerVersion.Line)" -ForegroundColor Green

    # Check for required plugins
    Write-Host "Checking GStreamer plugins..." -ForegroundColor Yellow
    $plugins = @("videoconvert", "autoaudiosink", "appsink", "playbin")
    foreach ($plugin in $plugins) {
        $pluginCheck = & gst-inspect-1.0 $plugin 2>&1 | Select-String "Plugin Details"
        if ($pluginCheck) {
            Write-Host "✓ $plugin plugin available" -ForegroundColor Green
        } else {
            Write-Warning "✗ $plugin plugin not found"
        }
    }
} else {
    Write-Warning "GStreamer verification failed"
}

# Build the Rust project if not skipped
if (!$SkipBuild) {
    Write-Host "Building Rust project..." -ForegroundColor Yellow

    # Ensure we're using the correct Rust target for Windows
    $rustTarget = & rustc --print host
    Write-Host "Rust target: $rustTarget" -ForegroundColor Cyan

    try {
        & cargo build --release
        Write-Host "Build completed successfully!" -ForegroundColor Green
    } catch {
        Write-Error "Build failed: $_"
        Write-Host "If build fails due to linking issues, ensure:" -ForegroundColor Yellow
        Write-Host "1. Visual Studio Build Tools are installed" -ForegroundColor Yellow
        Write-Host "2. GStreamer is properly installed with all plugins" -ForegroundColor Yellow
        Write-Host "3. Environment variables are set correctly" -ForegroundColor Yellow
        exit 1
    }
}

Write-Host "`nInstallation complete!" -ForegroundColor Green
Write-Host "To run the application: cargo run --release" -ForegroundColor Cyan

Write-Host "`nImportant Notes:" -ForegroundColor Yellow
Write-Host "- Visual Studio Build Tools with C++ support are required for compilation" -ForegroundColor Yellow
Write-Host "- If GStreamer plugins are missing, download the full MSI installer from:" -ForegroundColor Yellow
Write-Host "  https://gstreamer.freedesktop.org/download/" -ForegroundColor Yellow
Write-Host "- The application requires GStreamer plugins: videoconvert, autoaudiosink, appsink, playbin" -ForegroundColor Yellow
Write-Host "- You may need to restart your PowerShell session for environment changes to take effect" -ForegroundColor Yellow

# Set persistent environment variables for future sessions
Write-Host "`nTo make environment variables persistent, add to your PowerShell profile:" -ForegroundColor Cyan
if ($gstreamerFound) {
    Write-Host "`$env:PKG_CONFIG_PATH = '$env:PKG_CONFIG_PATH'" -ForegroundColor Cyan
    Write-Host "`$env:GSTREAMER_ROOT = '$env:GSTREAMER_ROOT'" -ForegroundColor Cyan
    Write-Host "`$env:PATH = '$gstreamerPath\bin;' + `$env:PATH" -ForegroundColor Cyan
}