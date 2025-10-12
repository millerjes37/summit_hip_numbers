#!/bin/bash
# macOS install script for Summit HIP Numbers (GStreamer dependencies)
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
    brew uninstall pkg-config gstreamer gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly gst-libav 2>/dev/null || true
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

# Install GStreamer (required for video playback)
log_info "Installing GStreamer..."
brew install gstreamer

log_info "Installing GStreamer plugins..."
brew install gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly

log_info "Installing additional GStreamer components..."
brew install gst-libav

# Set environment variables for GStreamer
export GSTREAMER_ROOT="/opt/homebrew"
export PKG_CONFIG_PATH="/opt/homebrew/lib/pkgconfig"
export DYLD_LIBRARY_PATH="/opt/homebrew/lib:$DYLD_LIBRARY_PATH"

# Verify installations
log_info "Verifying installations..."

if pkg-config --exists gstreamer-1.0; then
    GST_VERSION=$(pkg-config --modversion gstreamer-1.0)
    log_success "GStreamer installed: $GST_VERSION"
else
    log_error "GStreamer installation failed"
    exit 1
fi

if command -v gst-inspect-1.0 &>/dev/null; then
    log_success "GStreamer tools available"
else
    log_error "GStreamer tools installation failed"
    exit 1
fi

# Verify essential GStreamer plugins
log_info "Verifying GStreamer plugins..."
REQUIRED_PLUGINS=("coreelements" "playback" "typefindfunctions" "videoconvert" "videoscale" "audioresample" "autodetect")
for plugin in "${REQUIRED_PLUGINS[@]}"; do
    if gst-inspect-1.0 "$plugin" &>/dev/null; then
        log_success "Plugin $plugin: OK"
    else
        log_warn "Plugin $plugin: Missing (may affect functionality)"
    fi
done

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
echo -e "${YELLOW}Note: The application uses GStreamer for video playback.${NC}"
echo -e "${YELLOW}Make sure you have video files in the configured videos directory.${NC}"