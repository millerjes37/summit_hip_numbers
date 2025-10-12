#!/bin/bash
# Build orchestration script for Summit Hip Numbers
# Handles both development and distribution builds across platforms

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to display help
show_help() {
    echo "Summit Hip Numbers Build Orchestration Script"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --platform <platform>    Build for specific platform (macos, windows, linux, all)"
    echo "  --variant <variant>      Build variant (full, demo, all) [default: full]"
    echo "  --skip-tests            Skip running tests"
    echo "  --skip-build            Skip cargo build (use existing binaries)"
    echo "  --dist-only             Only create distribution packages"
    echo "  --help                  Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                      # Build full variant for current platform"
    echo "  $0 --platform all       # Build all platforms"
    echo "  $0 --variant demo       # Build demo variant"
    echo "  $0 --dist-only          # Create distribution packages from existing builds"
}

# Parse arguments
PLATFORM="current"
VARIANT="full"
SKIP_TESTS=false
SKIP_BUILD=false
DIST_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --platform)
            PLATFORM="$2"
            shift 2
            ;;
        --variant)
            VARIANT="$2"
            shift 2
            ;;
        --skip-tests)
            SKIP_TESTS=true
            shift
            ;;
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --dist-only)
            DIST_ONLY=true
            SKIP_BUILD=true
            SKIP_TESTS=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

# Detect current platform if needed
if [ "$PLATFORM" = "current" ]; then
    case "$(uname -s)" in
        Darwin*) PLATFORM="macos" ;;
        Linux*) PLATFORM="linux" ;;
        MINGW*|MSYS*|CYGWIN*) PLATFORM="windows" ;;
        *) 
            echo -e "${RED}Unknown platform: $(uname -s)${NC}"
            exit 1
            ;;
    esac
fi

echo -e "${BLUE}=== Summit Hip Numbers Build Orchestration ===${NC}"
echo "Platform: $PLATFORM"
echo "Variant: $VARIANT"
echo "Skip tests: $SKIP_TESTS"
echo "Skip build: $SKIP_BUILD"
echo "Distribution only: $DIST_ONLY"
echo ""

# Function to run tests
run_tests() {
    echo -e "${YELLOW}Running tests...${NC}"
    
    # Format check
    echo "Checking code format..."
    cargo fmt --all -- --check
    
    # Lint check
    echo "Running clippy..."
    cargo clippy --all-targets -- -D warnings
    
    # Run tests
    echo "Running unit tests..."
    cargo test --workspace
    
    echo -e "${GREEN}✓ All tests passed${NC}"
}

# Function to ensure config files are correct
ensure_configs() {
    echo -e "${YELLOW}Ensuring configuration files...${NC}"
    
    # Create config.dist.toml if it doesn't exist
    if [ ! -f "config.dist.toml" ]; then
        echo "Creating config.dist.toml from config.toml..."
        if [ -f "config.toml" ]; then
            # Copy config.toml and update paths
            cp config.toml config.dist.toml
            
            # Update paths for distribution
            if [[ "$OSTYPE" == "darwin"* ]]; then
                sed -i '' 's|"./assets/videos"|"./videos"|g' config.dist.toml
                sed -i '' 's|"./assets/splash"|"./splash"|g' config.dist.toml
                sed -i '' 's|"./assets/logo"|"./logo"|g' config.dist.toml
            else
                sed -i 's|"./assets/videos"|"./videos"|g' config.dist.toml
                sed -i 's|"./assets/splash"|"./splash"|g' config.dist.toml
                sed -i 's|"./assets/logo"|"./logo"|g' config.dist.toml
            fi
        fi
    fi
    
    echo -e "${GREEN}✓ Configuration files ready${NC}"
}

# Function to build for a specific platform and variant
build_platform_variant() {
    local platform=$1
    local variant=$2
    
    echo -e "${BLUE}Building $variant for $platform...${NC}"
    
    case "$platform" in
        macos)
            if [[ "$OSTYPE" != "darwin"* ]]; then
                echo -e "${YELLOW}Warning: Cross-compiling for macOS from non-macOS platform${NC}"
            fi
            
            if [ -f "scripts/build_macos.sh" ]; then
                chmod +x scripts/build_macos.sh
                ./scripts/build_macos.sh "$variant"
            else
                echo -e "${RED}macOS build script not found${NC}"
                return 1
            fi
            ;;
            
        windows)
            if [ -f "scripts/build_windows.ps1" ]; then
                if command -v powershell &> /dev/null; then
                    powershell -ExecutionPolicy Bypass -File scripts/build_windows.ps1
                elif command -v pwsh &> /dev/null; then
                    pwsh -ExecutionPolicy Bypass -File scripts/build_windows.ps1
                else
                    echo -e "${YELLOW}PowerShell not found, attempting cargo build only${NC}"
                    cargo build --release --package summit_hip_numbers
                fi
            else
                echo -e "${RED}Windows build script not found${NC}"
                return 1
            fi
            ;;
            
        linux)
            echo -e "${YELLOW}Building for Linux...${NC}"
            
            # Linux build steps
            cargo build --release --package summit_hip_numbers
            
            # Create distribution
            local dist_dir="dist/linux-$variant"
            rm -rf "$dist_dir"
            mkdir -p "$dist_dir"
            
            # Copy binary
            cp target/release/summit_hip_numbers "$dist_dir/"
            chmod +x "$dist_dir/summit_hip_numbers"
            
            # Copy resources
            mkdir -p "$dist_dir/videos" "$dist_dir/splash" "$dist_dir/logo"
            cp config.dist.toml "$dist_dir/config.toml"
            
            # Copy assets
            [ -d "assets/videos" ] && cp -r assets/videos/* "$dist_dir/videos/" 2>/dev/null || true
            [ -d "assets/splash" ] && cp -r assets/splash/* "$dist_dir/splash/" 2>/dev/null || true
            [ -d "assets/logo" ] && cp -r assets/logo/* "$dist_dir/logo/" 2>/dev/null || true
            
            # Create launch script
            cat > "$dist_dir/run.sh" << 'EOF'
#!/bin/bash
# Summit Hip Numbers launcher for Linux

# Set GStreamer plugin path if needed
export GST_PLUGIN_PATH="${GST_PLUGIN_PATH}:/usr/lib/gstreamer-1.0"

# Change to application directory
cd "$(dirname "$0")"

# Run the application
./summit_hip_numbers "$@"
EOF
            chmod +x "$dist_dir/run.sh"
            
            # Create tarball
            tar -czf "dist/summit_hip_numbers_linux_${variant}.tar.gz" -C dist "linux-$variant"
            
            echo -e "${GREEN}✓ Linux build complete${NC}"
            ;;
            
        *)
            echo -e "${RED}Unknown platform: $platform${NC}"
            return 1
            ;;
    esac
}

# Main build process
main() {
    # Ensure we're in the project root
    if [ ! -f "Cargo.toml" ]; then
        echo -e "${RED}Error: Must run from project root directory${NC}"
        exit 1
    fi
    
    # Ensure configs are ready
    ensure_configs
    
    # Run tests unless skipped
    if [ "$SKIP_TESTS" != true ]; then
        run_tests
    fi
    
    # Build variants
    local variants=()
    if [ "$VARIANT" = "all" ]; then
        variants=("full" "demo")
    else
        variants=("$VARIANT")
    fi
    
    # Build platforms
    local platforms=()
    if [ "$PLATFORM" = "all" ]; then
        platforms=("macos" "windows" "linux")
    else
        platforms=("$PLATFORM")
    fi
    
    # Build each combination
    for platform in "${platforms[@]}"; do
        for variant in "${variants[@]}"; do
            if [ "$SKIP_BUILD" != true ]; then
                build_platform_variant "$platform" "$variant"
            fi
        done
    done
    
    # Create distribution summary
    if [ -d "dist" ]; then
        echo -e "${BLUE}=== Distribution Summary ===${NC}"
        echo "Available distributions:"
        find dist -name "*.zip" -o -name "*.dmg" -o -name "*.tar.gz" | while read file; do
            size=$(du -h "$file" | cut -f1)
            echo "  - $(basename "$file") ($size)"
        done
    fi
    
    echo -e "${GREEN}=== Build Complete ===${NC}"
}

# Run main function
main