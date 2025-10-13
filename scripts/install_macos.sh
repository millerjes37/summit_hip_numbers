#!/bin/bash
# macOS install script for Summit HIP Numbers (FFmpeg dependencies)
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

log_info "Installing dependencies for Summit HIP Numbers on macOS..."

# Check macOS version
if [[ "$OSTYPE" != "darwin"* ]]; then
    log_error "This script is for macOS only."
    exit 1
fi

# Clean previous installations if requested
if [ "$CLEAN" = true ]; then
    log_info "Cleaning previous installations..."
    brew uninstall pkg-config ffmpeg 2>/dev/null || true
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

# Install pkg-config (required for dependency detection)
log_info "Installing pkg-config..."
brew install pkg-config

# Install FFmpeg (required for video playback)
log_info "Installing FFmpeg..."
brew install ffmpeg

# Set environment variables for FFmpeg
export PKG_CONFIG_PATH="/opt/homebrew/lib/pkgconfig"
export DYLD_LIBRARY_PATH="/opt/homebrew/lib:$DYLD_LIBRARY_PATH"

# Verify installations
log_info "Verifying FFmpeg installation..."

if pkg-config --exists libavutil libavcodec libavformat; then
    FFMPEG_VERSION=$(ffmpeg -version | head -n1)
    log_success "FFmpeg installed: $FFMPEG_VERSION"
else
    log_error "FFmpeg installation failed"
    exit 1
fi

if command -v ffmpeg &>/dev/null; then
    log_success "FFmpeg tools available"
else
    log_error "FFmpeg tools installation failed"
    exit 1
fi

# Verify essential FFmpeg libraries
log_info "Verifying FFmpeg libraries..."
REQUIRED_LIBS=("libavutil" "libavcodec" "libavformat" "libswscale" "libswresample")
for lib in "${REQUIRED_LIBS[@]}"; do
    if pkg-config --exists "$lib"; then
        LIB_VERSION=$(pkg-config --modversion "$lib")
        log_success "Library available: $lib ($LIB_VERSION)"
    else
        log_error "Library missing: $lib"
        MISSING_LIBS+=("$lib")
    fi
done

if [ ${#MISSING_LIBS[@]} -ne 0 ]; then
    log_error "Missing FFmpeg libraries: ${MISSING_LIBS[*]}"
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
echo "  cargo run --release --package summit_hip_numbers"
echo
echo -e "${BLUE}To run with demo features:${NC}"
echo "  cargo run --release --package summit_hip_numbers --features demo"
echo
echo -e "${YELLOW}Note: The application uses FFmpeg for video playback.${NC}"
echo -e "${YELLOW}Make sure you have video files in the configured videos directory.${NC}"