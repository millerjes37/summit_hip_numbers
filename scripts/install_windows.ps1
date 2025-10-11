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

# Install GStreamer with all plugins
Write-Host "Installing GStreamer (full)..." -ForegroundColor Yellow
try {
    # Try winget first
    winget install GStreamer.GStreamer --accept-source-agreements --accept-package-agreements
} catch {
    Write-Host "Winget installation failed, trying manual download..." -ForegroundColor Yellow
    # Download GStreamer MSI if winget fails
    $gstreamerUrl = "https://gstreamer.freedesktop.org/data/pkg/windows/1.24.12/msvc/gstreamer-1.0-msvc-x86_64-1.24.12.msi"
    $msiPath = "$env:TEMP\gstreamer.msi"
    try {
        Invoke-WebRequest -Uri $gstreamerUrl -OutFile $msiPath
        Write-Host "Downloaded GStreamer MSI" -ForegroundColor Green
        # Install MSI silently
        Start-Process msiexec.exe -ArgumentList "/i `"$msiPath`" /quiet /norestart" -Wait
        Write-Host "Installed GStreamer MSI" -ForegroundColor Green
    } catch {
        Write-Error "Failed to download/install GStreamer: $_"
        Write-Host "Please manually download from https://gstreamer.freedesktop.org/download/" -ForegroundColor Yellow
        exit 1
    }
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
    $rustTarget = & rustc --print host-tuple
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

    # Bundle GStreamer DLLs for portability
    Write-Host "Bundling GStreamer DLLs for portable distribution..." -ForegroundColor Yellow
    if ($gstreamerFound) {
        $targetDir = "target\release"
        $gstreamerBin = "$gstreamerPath\bin"

        # Copy required GStreamer DLLs
        $requiredDlls = @(
            "libgstreamer-1.0-0.dll",
            "libgstbase-1.0-0.dll",
            "libgstvideo-1.0-0.dll",
            "libgstapp-1.0-0.dll",
            "libgstplay-1.0-0.dll",
            "libgstaudio-1.0-0.dll",
            "libgstpbutils-1.0-0.dll",
            "libgobject-2.0-0.dll",
            "libglib-2.0-0.dll",
            "libintl-8.dll",
            "libffi-8.dll",
            "libpcre2-8-0.dll",
            "libz-1.dll",
            "libbz2-1.dll",
            "libwinpthread-1.dll",
            "libgcc_s_seh-1.dll",
            "libstdc++-6.dll"
        )

        foreach ($dll in $requiredDlls) {
            $sourcePath = Join-Path $gstreamerBin $dll
            if (Test-Path $sourcePath) {
                Copy-Item $sourcePath $targetDir -Force
                Write-Host "Copied $dll" -ForegroundColor Green
            } else {
                Write-Warning "DLL not found: $dll"
            }
        }

        # Create portable zip
        Write-Host "Creating portable zip package..." -ForegroundColor Yellow
        $zipName = "summit_hip_numbers_portable.zip"
        $exeName = "summit_hip_numbers.exe"
        $exePath = Join-Path $targetDir $exeName

        if (Test-Path $exePath) {
            # Create a temporary directory for zipping
            $tempDir = "$env:TEMP\summit_portable"
            if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
            New-Item -ItemType Directory -Path $tempDir | Out-Null

            # Copy exe and dlls
            Copy-Item $exePath $tempDir
            Get-ChildItem "$targetDir\*.dll" | Copy-Item -Destination $tempDir

            # Also copy config files if they exist
            if (Test-Path "config.toml") { Copy-Item "config.toml" $tempDir }
            if (Test-Path "config.toml.example") { Copy-Item "config.toml.example" $tempDir }

            # Create zip
            Compress-Archive -Path "$tempDir\*" -DestinationPath $zipName -Force
            Write-Host "Created portable zip: $zipName" -ForegroundColor Green

            # Clean up temp dir
            Remove-Item $tempDir -Recurse -Force
        } else {
            Write-Warning "Executable not found, skipping zip creation"
        }
    } else {
        Write-Warning "GStreamer not found, cannot create portable bundle"
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

Write-Host "`nNext Steps:" -ForegroundColor Cyan
Write-Host "1. Add your video files to the 'videos' directory" -ForegroundColor Cyan
Write-Host "2. Configure settings in 'config.toml' if needed" -ForegroundColor Cyan
Write-Host "3. Run 'cargo run --release' to start the application" -ForegroundColor Cyan
if (Test-Path "summit_hip_numbers_portable.zip") {
    Write-Host "4. Or distribute the portable zip to other machines" -ForegroundColor Cyan
}