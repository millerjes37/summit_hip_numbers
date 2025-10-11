#!/bin/bash
# scripts/build_all.sh
# Build all variants for local development

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default options
RUN_TESTS=true
BUILD_DEMO=true
BUILD_FULL=true
ARCHIVE=true
VERBOSE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-tests)
            RUN_TESTS=false
            shift
            ;;
        --demo-only)
            BUILD_FULL=false
            shift
            ;;
        --full-only)
            BUILD_DEMO=false
            shift
            ;;
        --no-archives)
            ARCHIVE=false
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --no-tests      Skip running tests"
            echo "  --demo-only     Build only demo variant"
            echo "  --full-only     Build only full variant"
            echo "  --no-archives   Skip creating ZIP/TAR archives"
            echo "  --verbose       Enable verbose output"
            echo "  --help          Show this help message"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Function to print colored output
log() {
    echo -e "${BLUE}[BUILD]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to detect platform
detect_platform() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
        echo "windows"
    else
        echo "unknown"
    fi
}

# Function to build for a variant
build_variant() {
    local variant=$1
    local platform=$2
    
    log "Building $variant variant for $platform..."
    
    case $platform in
        "windows")
            if [ -f "scripts/build_windows_msys2.sh" ]; then
                ./scripts/build_windows_msys2.sh $variant
            else
                error "Windows build script not found"
                return 1
            fi
            ;;
        "macos")
            if [ -f "scripts/build_macos.sh" ]; then
                ./scripts/build_macos.sh $variant
            else
                error "macOS build script not found"
                return 1
            fi
            ;;
        "linux")
            log "Building with Nix..."
            if command -v nix &> /dev/null; then
                if [ "$variant" = "demo" ]; then
                    nix build .#demo --print-build-logs
                else
                    nix build . --print-build-logs
                fi
                
                # Create dist directory
                mkdir -p "dist/linux-$variant"
                if [ -d "result" ]; then
                    cp -rL result/* "dist/linux-$variant/"
                fi
            else
                warning "Nix not found, falling back to cargo build"
                if [ "$variant" = "demo" ]; then
                    cargo build --release --package summit_hip_numbers --features demo
                else
                    cargo build --release --package summit_hip_numbers
                fi
                
                # Create dist directory
                mkdir -p "dist/linux-$variant/bin"
                cp "target/release/summit_hip_numbers" "dist/linux-$variant/bin/"
            fi
            ;;
        *)
            error "Unsupported platform: $platform"
            return 1
            ;;
    esac
}

# Function to run tests
run_tests() {
    local variant=$1
    local platform=$2
    
    log "Running tests for $variant variant on $platform..."
    
    case $platform in
        "windows")
            if [ -f "scripts/test_portable_comprehensive.ps1" ]; then
                powershell -ExecutionPolicy Bypass -File "scripts/test_portable_comprehensive.ps1" -DistPath "dist/$variant" -Variant "$variant"
            else
                warning "Windows test script not found, skipping tests"
            fi
            ;;
        "macos")
            if [ -f "scripts/test_portable_comprehensive_macos.sh" ]; then
                local app_name="Summit HIP Numbers"
                if [ "$variant" = "demo" ]; then
                    app_name="Summit HIP Numbers Demo"
                fi
                ./scripts/test_portable_comprehensive_macos.sh "dist/macos-$variant/$app_name.app" "$variant"
            else
                warning "macOS test script not found, skipping tests"
            fi
            ;;
        "linux")
            if [ -f "scripts/test_portable_comprehensive.sh" ]; then
                ./scripts/test_portable_comprehensive.sh "dist/linux-$variant" "$variant"
            else
                warning "Linux test script not found, skipping tests"
            fi
            ;;
    esac
}

# Function to create archives
create_archives() {
    local variant=$1
    local platform=$2
    
    log "Creating archives for $variant variant on $platform..."
    
    # Get version
    local version=$(git describe --tags --always 2>/dev/null || echo "dev")
    
    case $platform in
        "windows")
            if [ -d "dist/$variant" ]; then
                cd dist
                local archive_name="summit_hip_numbers_${variant}_portable_${version}.zip"
                zip -r "$archive_name" "$variant" > /dev/null
                cd ..
                success "Created: dist/$archive_name"
            fi
            ;;
        "macos")
            if [ -d "dist/macos-$variant" ]; then
                cd dist
                local archive_name="summit_hip_numbers_macos_${variant}_${version}.zip"
                zip -r "$archive_name" "macos-$variant" > /dev/null
                cd ..
                success "Created: dist/$archive_name"
            fi
            ;;
        "linux")
            if [ -d "dist/linux-$variant" ]; then
                cd dist
                local archive_tar="summit_hip_numbers_linux_${variant}_${version}.tar.gz"
                local archive_zip="summit_hip_numbers_linux_${variant}_${version}.zip"
                tar -czf "$archive_tar" "linux-$variant"
                zip -r "$archive_zip" "linux-$variant" > /dev/null
                cd ..
                success "Created: dist/$archive_tar"
                success "Created: dist/$archive_zip"
            fi
            ;;
    esac
}

# Main execution
echo -e "${CYAN}================================${NC}"
echo -e "${CYAN}  Summit HIP Numbers Build All${NC}"
echo -e "${CYAN}================================${NC}"

# Detect platform
PLATFORM=$(detect_platform)
log "Detected platform: $PLATFORM"

# Check prerequisites
log "Checking prerequisites..."

if ! command -v cargo &> /dev/null; then
    error "Rust/Cargo not found. Please install Rust first."
    exit 1
fi

if ! command -v git &> /dev/null; then
    error "Git not found. Please install Git first."
    exit 1
fi

# Create build-logs directory
mkdir -p build-logs

# Start build process
START_TIME=$(date +%s)

# Track results
BUILDS_SUCCEEDED=0
BUILDS_FAILED=0
TESTS_PASSED=0
TESTS_FAILED=0

# Build full variant
if [ "$BUILD_FULL" = true ]; then
    log ""
    log "===== Building FULL variant ====="
    if build_variant "full" "$PLATFORM"; then
        ((BUILDS_SUCCEEDED++))
        success "Full variant built successfully"
        
        if [ "$RUN_TESTS" = true ]; then
            if run_tests "full" "$PLATFORM"; then
                ((TESTS_PASSED++))
                success "Full variant tests passed"
            else
                ((TESTS_FAILED++))
                warning "Full variant tests failed"
            fi
        fi
        
        if [ "$ARCHIVE" = true ]; then
            create_archives "full" "$PLATFORM"
        fi
    else
        ((BUILDS_FAILED++))
        error "Full variant build failed"
    fi
fi

# Build demo variant
if [ "$BUILD_DEMO" = true ]; then
    log ""
    log "===== Building DEMO variant ====="
    if build_variant "demo" "$PLATFORM"; then
        ((BUILDS_SUCCEEDED++))
        success "Demo variant built successfully"
        
        if [ "$RUN_TESTS" = true ]; then
            if run_tests "demo" "$PLATFORM"; then
                ((TESTS_PASSED++))
                success "Demo variant tests passed"
            else
                ((TESTS_FAILED++))
                warning "Demo variant tests failed"
            fi
        fi
        
        if [ "$ARCHIVE" = true ]; then
            create_archives "demo" "$PLATFORM"
        fi
    else
        ((BUILDS_FAILED++))
        error "Demo variant build failed"
    fi
fi

# Calculate elapsed time
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
MINUTES=$((ELAPSED / 60))
SECONDS=$((ELAPSED % 60))

# Summary
echo ""
echo -e "${CYAN}================================${NC}"
echo -e "${CYAN}  Build Summary${NC}"
echo -e "${CYAN}================================${NC}"
echo -e "Platform: $PLATFORM"
echo -e "Time elapsed: ${MINUTES}m ${SECONDS}s"
echo ""
echo -e "Builds:"
echo -e "  Succeeded: ${GREEN}$BUILDS_SUCCEEDED${NC}"
echo -e "  Failed:    ${RED}$BUILDS_FAILED${NC}"

if [ "$RUN_TESTS" = true ]; then
    echo ""
    echo -e "Tests:"
    echo -e "  Passed:    ${GREEN}$TESTS_PASSED${NC}"
    echo -e "  Failed:    ${RED}$TESTS_FAILED${NC}"
fi

# List created files
echo ""
echo -e "${CYAN}Created files:${NC}"
if [ "$ARCHIVE" = true ]; then
    find dist -name "*.zip" -o -name "*.tar.gz" -o -name "*.dmg" | while read file; do
        SIZE=$(du -h "$file" | cut -f1)
        echo -e "  $(basename "$file") ($SIZE)"
    done
else
    find dist -type d -maxdepth 1 -name "*-*" | while read dir; do
        SIZE=$(du -sh "$dir" | cut -f1)
        echo -e "  $(basename "$dir")/ ($SIZE)"
    done
fi

# Exit with appropriate code
if [ $BUILDS_FAILED -gt 0 ]; then
    exit 1
elif [ "$RUN_TESTS" = true ] && [ $TESTS_FAILED -gt 0 ]; then
    exit 2
else
    echo ""
    success "All builds completed successfully!"
    exit 0
fi