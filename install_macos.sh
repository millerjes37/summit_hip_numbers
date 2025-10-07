#!/bin/bash
# macOS install script for egui-video dependencies
# Requires: Xcode Command Line Tools, internet connection

set -e

# Color output functions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Parse command line arguments
SKIP_BUILD=false
CLEAN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --clean)
            CLEAN=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Usage: $0 [--skip-build] [--clean]"
            exit 1
            ;;
    esac
done

log_info "Installing dependencies for egui-video on macOS..."

# Check macOS version
if [[ "$OSTYPE" != "darwin"* ]]; then
    log_error "This script is for macOS only."
    exit 1
fi

# Clean previous installations if requested
if [ "$CLEAN" = true ]; then
    log_info "Cleaning previous installations..."
    brew uninstall ffmpeg@7 sdl2 2>/dev/null || true
    rm -rf target Cargo.lock
fi

# Install Xcode Command Line Tools if not present
if ! xcode-select -p &>/dev/null; then
    log_info "Installing Xcode Command Line Tools..."
    xcode-select --install

    # Wait for installation to complete
    log_warn "Please complete the Xcode Command Line Tools installation, then press Enter to continue..."
    read -r
fi

# Install Homebrew if not present
if ! command -v brew &>/dev/null; then
    log_info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add brew to PATH for this session
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# Update Homebrew
log_info "Updating Homebrew..."
brew update

# Install ffmpeg 7.x (required version for egui-video)
log_info "Installing ffmpeg@7..."
brew install ffmpeg@7

# Install SDL2
log_info "Installing SDL2..."
brew install sdl2

# Set environment variables
export FFMPEG_DIR="/opt/homebrew/opt/ffmpeg@7"
export LDFLAGS="-L/opt/homebrew/opt/ffmpeg@7/lib -L/opt/homebrew/lib"
export CPPFLAGS="-I/opt/homebrew/opt/ffmpeg@7/include -I/opt/homebrew/include"
export PKG_CONFIG_PATH="/opt/homebrew/opt/ffmpeg@7/lib/pkgconfig:/opt/homebrew/lib/pkgconfig"

# Verify installations
log_info "Verifying installations..."

if command -v ffmpeg &>/dev/null; then
    FFMPEG_VERSION=$(ffmpeg -version 2>&1 | head -n 1)
    log_success "FFmpeg installed: $FFMPEG_VERSION"
else
    log_error "FFmpeg installation failed"
    exit 1
fi

if pkg-config --exists sdl2; then
    SDL2_VERSION=$(pkg-config --modversion sdl2)
    log_success "SDL2 installed: $SDL2_VERSION"
else
    log_error "SDL2 installation failed"
    exit 1
fi

# Build the Rust project if not skipped
if [ "$SKIP_BUILD" = false ]; then
    log_info "Building Rust project..."
    if cargo build --release; then
        log_success "Build completed successfully!"
    else
        log_error "Build failed"
        exit 1
    fi
fi

log_success "Installation complete!"
echo
echo -e "${BLUE}To run the application:${NC}"
echo "  cargo run --release"
echo
echo -e "${YELLOW}Note: The application uses native video playback via ffmpeg and SDL2.${NC}"
echo -e "${YELLOW}Make sure you have video files in the 'videos/' directory.${NC}"