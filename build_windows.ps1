# Build script for Windows
# Run this on a Windows machine with Rust installed

Write-Host "Building Summit Hip Numbers Media Player for Windows..." -ForegroundColor Green

# Build the application
cargo build --release

if ($LASTEXITCODE -eq 0) {
    Write-Host "Build successful!" -ForegroundColor Green
    Write-Host "Binary location: target\release\summit_hip_numbers.exe" -ForegroundColor Cyan

    # Create a simple distribution package
    $distDir = "dist"
    if (Test-Path $distDir) {
        Remove-Item $distDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $distDir

    # Copy files
    Copy-Item "target\release\summit_hip_numbers.exe" $distDir
    Copy-Item "config.toml" $distDir
    Copy-Item "videos" $distDir -Recurse

    Write-Host "Distribution package created in: $distDir" -ForegroundColor Cyan
    Write-Host "You can now zip the $distDir folder and distribute it." -ForegroundColor Cyan
} else {
    Write-Host "Build failed!" -ForegroundColor Red
    exit 1
}