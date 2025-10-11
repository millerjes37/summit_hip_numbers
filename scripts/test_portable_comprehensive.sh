#!/bin/bash
# scripts/test_portable_comprehensive.sh
# Comprehensive testing framework for Linux portable distributions

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# Test results tracking
declare -a PASSED_TESTS=()
declare -a FAILED_TESTS=()
declare -a WARNINGS=()

# Helper functions
section() {
    echo -e "\n${CYAN}========================================"
    echo -e "  $1"
    echo -e "========================================${NC}"
}

step() {
    echo -e "\n${YELLOW}[TEST] $1${NC}"
}

success() {
    echo -e "  ${GREEN}✓ $1${NC}"
    PASSED_TESTS+=("$1")
}

failure() {
    echo -e "  ${RED}✗ $1${NC}"
    FAILED_TESTS+=("$1")
}

info() {
    echo -e "  ${GRAY}→ $1${NC}"
}

warning() {
    echo -e "  ${YELLOW}⚠ $1${NC}"
    WARNINGS+=("$1")
}

# Parse arguments
DIST_PATH="${1:-}"
VARIANT="${2:-full}"
RUNTIME_SECONDS="${3:-10}"

if [ -z "$DIST_PATH" ]; then
    echo -e "${RED}Usage: $0 <dist_path> [variant] [runtime_seconds]${NC}"
    echo "Example: $0 dist/linux-full full 10"
    exit 1
fi

# Main test execution
section "COMPREHENSIVE PORTABLE DISTRIBUTION TEST"
info "Distribution: $DIST_PATH"
info "Variant: $VARIANT"
info "Test Started: $(date '+%Y-%m-%d %H:%M:%S')"

# ============================================================================
# TEST 1: Directory Structure Validation
# ============================================================================
step "1. Directory Structure Validation"

if [ ! -d "$DIST_PATH" ]; then
    failure "Directory Exists: Path not found: $DIST_PATH"
    exit 1
else
    success "Directory Exists"
fi

# Catalog all files
FILE_COUNT=$(find "$DIST_PATH" -type f | wc -l)
TOTAL_SIZE=$(du -sh "$DIST_PATH" | cut -f1)
info "Total files: $FILE_COUNT"
info "Total size: $TOTAL_SIZE"

# Display directory tree
if command -v tree &> /dev/null; then
    info "Directory structure:"
    tree -L 3 "$DIST_PATH" | head -n 30 | while read line; do
        echo "    $line"
    done
else
    info "Directory structure (install 'tree' for better visualization):"
    find "$DIST_PATH" -maxdepth 3 | head -n 30 | while read line; do
        echo "    $line"
    done
fi

# Check for manifest
if [ -f "$DIST_PATH/BUILD_MANIFEST.txt" ]; then
    success "Build Manifest Present"
    info "Manifest contents (first 20 lines):"
    head -n 20 "$DIST_PATH/BUILD_MANIFEST.txt" | while read line; do
        echo -e "    ${GRAY}$line${NC}"
    done
else
    warning "Build manifest not found"
fi

# ============================================================================
# TEST 2: Binary Detection
# ============================================================================
step "2. Binary Detection"

# Find executable
BINARY_NAME="summit_hip_numbers"
if [ "$VARIANT" = "demo" ]; then
    BINARY_NAME="summit_hip_numbers_demo"
fi

BINARY=$(find "$DIST_PATH" -name "$BINARY_NAME" -type f -executable 2>/dev/null | head -n 1)

if [ -n "$BINARY" ]; then
    success "Binary Found: $BINARY"
    
    # Get binary info
    SIZE=$(stat -f%z "$BINARY" 2>/dev/null || stat -c%s "$BINARY")
    SIZE_MB=$(echo "scale=2; $SIZE / 1048576" | bc)
    info "Size: ${SIZE_MB} MB"
    
    MODIFIED=$(stat -f%Sm -t '%Y-%m-%d %H:%M:%S' "$BINARY" 2>/dev/null || stat -c%y "$BINARY" | cut -d'.' -f1)
    info "Modified: $MODIFIED"
    
    # Check ELF header
    if file "$BINARY" | grep -q "ELF.*executable"; then
        success "Valid ELF Binary"
    else
        failure "Valid ELF Binary: Not a valid ELF file"
    fi
    
    # Check if stripped
    if file "$BINARY" | grep -q "not stripped"; then
        warning "Binary not stripped (larger size, debug symbols included)"
    else
        info "Binary is stripped (optimized)"
    fi
else
    failure "Binary Found: Expected binary: $BINARY_NAME"
    exit 1
fi

WORKING_DIR=$(dirname "$BINARY")

# ============================================================================
# TEST 3: Library Dependency Verification
# ============================================================================
step "3. Library Dependency Verification"

# Check ldd
if ! command -v ldd &> /dev/null; then
    warning "ldd not available, skipping dependency check"
else
    info "Analyzing dynamic dependencies..."
    
    # Get dependencies
    LDD_OUTPUT=$(ldd "$BINARY" 2>&1)
    
    # Count dependencies
    DEP_COUNT=$(echo "$LDD_OUTPUT" | grep -c "=>" || true)
    info "Total dynamic dependencies: $DEP_COUNT"
    
    # Check for missing libraries
    MISSING=$(echo "$LDD_OUTPUT" | grep "not found" || true)
    if [ -n "$MISSING" ]; then
        failure "Missing Libraries Detected"
        echo -e "${RED}$MISSING${NC}"
    else
        success "All Libraries Found"
    fi
    
    # Critical libraries check
    CRITICAL_LIBS=(
        "libglib-2.0"
        "libgobject-2.0"
        "libgio-2.0"
        "libgstreamer-1.0"
        "libgstapp-1.0"
        "libgstbase-1.0"
    )
    
    info "Checking critical libraries:"
    for lib in "${CRITICAL_LIBS[@]}"; do
        if echo "$LDD_OUTPUT" | grep -q "$lib"; then
            LIB_PATH=$(echo "$LDD_OUTPUT" | grep "$lib" | awk '{print $3}' | head -n 1)
            success "$lib found at $LIB_PATH"
        else
            warning "$lib not found in dependencies (may be statically linked)"
        fi
    done
    
    # Save dependency report
    DEP_REPORT="$WORKING_DIR/test-dependencies.txt"
    cat > "$DEP_REPORT" << EOF
Library Dependency Report
Generated: $(date '+%Y-%m-%d %H:%M:%S')
Binary: $BINARY

Dynamic Dependencies:
----------------------------------------
$LDD_OUTPUT

EOF
    info "Dependency report saved: $DEP_REPORT"
fi

# ============================================================================
# TEST 4: GStreamer Plugin Verification
# ============================================================================
step "4. GStreamer Plugin Verification"

# Possible plugin locations
PLUGIN_DIRS=(
    "$DIST_PATH/lib/gstreamer-1.0"
    "$DIST_PATH/gstreamer-1.0"
    "$WORKING_DIR/lib/gstreamer-1.0"
    "$WORKING_DIR/../lib/gstreamer-1.0"
)

FOUND_PLUGINS=false
PLUGIN_COUNT=0

for PLUGIN_DIR in "${PLUGIN_DIRS[@]}"; do
    if [ -d "$PLUGIN_DIR" ]; then
        PLUGIN_COUNT=$(find "$PLUGIN_DIR" -name "*.so" -o -name "libgst*.so" | wc -l)
        
        if [ $PLUGIN_COUNT -gt 0 ]; then
            success "GStreamer Plugins Found: $PLUGIN_COUNT plugins in $PLUGIN_DIR"
            FOUND_PLUGINS=true
            
            # List key plugins
            KEY_PLUGINS=("coreelements" "playback" "typefindfunctions" "audioconvert" "videoconvert")
            info "Checking for key plugins:"
            for key in "${KEY_PLUGINS[@]}"; do
                if find "$PLUGIN_DIR" -name "*$key*" | grep -q .; then
                    echo -e "    ${GREEN}✓ $key plugin present${NC}"
                else
                    warning "Optional plugin missing: $key"
                fi
            done
            break
        fi
    fi
done

if [ "$FOUND_PLUGINS" = false ]; then
    failure "GStreamer Plugins Not Found"
    warning "Media playback may not work without plugins"
fi

# ============================================================================
# TEST 5: Configuration & Asset Files
# ============================================================================
step "5. Configuration & Asset Files"

# Expected files
declare -A EXPECTED_ASSETS=(
    ["config.toml"]="Configuration"
    ["README.txt"]="Documentation"
    ["README.md"]="Documentation"
    ["LICENSE"]="License"
)

for asset in "${!EXPECTED_ASSETS[@]}"; do
    ASSET_PATH=$(find "$DIST_PATH" -name "$asset" -type f | head -n 1)
    if [ -n "$ASSET_PATH" ]; then
        success "${EXPECTED_ASSETS[$asset]}: $asset"
    else
        warning "${EXPECTED_ASSETS[$asset]} file not found: $asset"
    fi
done

# ============================================================================
# TEST 6: Binary Capabilities Check
# ============================================================================
step "6. Binary Capabilities & Permissions"

# Check execute permissions
if [ -x "$BINARY" ]; then
    success "Execute Permission Set"
else
    failure "Execute Permission Missing"
    info "Attempting to fix..."
    chmod +x "$BINARY"
fi

# Check for required capabilities (if getcap available)
if command -v getcap &> /dev/null; then
    CAPS=$(getcap "$BINARY" 2>/dev/null || true)
    if [ -n "$CAPS" ]; then
        info "Binary capabilities: $CAPS"
    else
        info "No special capabilities required"
    fi
fi

# File type analysis
FILE_INFO=$(file "$BINARY")
info "Binary type: $FILE_INFO"

# ============================================================================
# TEST 7: Runtime Execution Test
# ============================================================================
step "7. Runtime Execution Test"

LOG_FILE="$WORKING_DIR/test-runtime.log"
ERROR_FILE="$WORKING_DIR/test-runtime-error.log"

# Clean old logs
rm -f "$LOG_FILE" "$ERROR_FILE"

info "Attempting runtime execution..."

# Set environment for GStreamer if needed
export GST_PLUGIN_SYSTEM_PATH="$DIST_PATH/lib/gstreamer-1.0:$WORKING_DIR/lib/gstreamer-1.0"
export LD_LIBRARY_PATH="$DIST_PATH/lib:$WORKING_DIR/lib:$LD_LIBRARY_PATH"

# Try --version flag first
info "Testing --version flag..."
if timeout 5s "$BINARY" --version > "$LOG_FILE" 2>&1; then
    success "Version Check Passed"
    cat "$LOG_FILE"
else
    EXIT_CODE=$?
    if [ $EXIT_CODE -eq 124 ]; then
        info "Version check timed out (may not support --version)"
    else
        warning "Version check returned code: $EXIT_CODE"
    fi
fi

# Full runtime test
info "Starting full runtime test (${RUNTIME_SECONDS}s)..."

# Run in background
"$BINARY" > "$LOG_FILE" 2> "$ERROR_FILE" &
PID=$!

sleep 1

# Check if process started
if ps -p $PID > /dev/null 2>&1; then
    success "Process Started (PID: $PID)"
    
    # Monitor process
    sleep 2
    
    if ps -p $PID > /dev/null 2>&1; then
        success "Process Stable after 2 seconds"
        
        # Simulate some events (if X11 available)
        if [ -n "$DISPLAY" ] && command -v xdotool &> /dev/null; then
            info "Simulating keyboard input..."
            sleep 1
            xdotool key Down 2>/dev/null || true
            sleep 1
            xdotool key Up 2>/dev/null || true
            sleep 1
            xdotool key Return 2>/dev/null || true
            success "Interactive Simulation Complete"
        else
            info "X11/xdotool not available, skipping keyboard simulation"
        fi
        
        # Wait remaining time
        WAIT_TIME=$((RUNTIME_SECONDS - 4))
        if [ $WAIT_TIME -gt 0 ]; then
            sleep $WAIT_TIME
        fi
        
        # Final check
        if ps -p $PID > /dev/null 2>&1; then
            success "Process Stable After Full Runtime"
            info "Terminating process..."
            kill $PID 2>/dev/null || true
            wait $PID 2>/dev/null || true
        else
            warning "Process exited during runtime test"
        fi
    else
        failure "Process Exited Prematurely"
    fi
else
    failure "Process Failed to Start"
fi

# Display logs
echo -e "\n${GRAY}--- STDOUT ---${NC}"
if [ -f "$LOG_FILE" ]; then
    cat "$LOG_FILE" | while read line; do
        echo -e "${GRAY}$line${NC}"
    done
else
    echo -e "${GRAY}(no output)${NC}"
fi

if [ -f "$ERROR_FILE" ] && [ -s "$ERROR_FILE" ]; then
    echo -e "\n${YELLOW}--- STDERR ---${NC}"
    cat "$ERROR_FILE" | while read line; do
        echo -e "${YELLOW}$line${NC}"
    done
fi

# ============================================================================
# TEST 8: Memory & Resource Analysis
# ============================================================================
step "8. Post-Execution Validation"

# Check log file sizes
if [ -f "$LOG_FILE" ]; then
    LOG_SIZE=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE")
    success "Log Generation: $LOG_SIZE bytes"
fi

# Check for core dumps
if [ -f "core" ] || [ -f "$WORKING_DIR/core" ]; then
    failure "Core Dump Detected: Application crashed"
else
    success "No Core Dumps Found"
fi

# ============================================================================
# TEST 9: Security Checks
# ============================================================================
step "9. Security Validation"

# Check for RPATH/RUNPATH
if command -v readelf &> /dev/null; then
    RPATH=$(readelf -d "$BINARY" | grep -E "RPATH|RUNPATH" || true)
    if [ -n "$RPATH" ]; then
        info "Runtime paths configured:"
        echo "$RPATH" | while read line; do
            echo "    $line"
        done
    else
        info "No RPATH/RUNPATH set (using LD_LIBRARY_PATH)"
    fi
fi

# Check for PIE (Position Independent Executable)
if file "$BINARY" | grep -q "pie executable"; then
    success "PIE Enabled (Enhanced security)"
else
    warning "PIE not enabled (consider enabling for security)"
fi

# Check for stack canary
if readelf -s "$BINARY" 2>/dev/null | grep -q "__stack_chk_fail"; then
    success "Stack Canary Enabled (Buffer overflow protection)"
else
    info "Stack canary status unknown"
fi

# ============================================================================
# FINAL REPORT
# ============================================================================
section "TEST SUMMARY"

TOTAL_TESTS=$((${#PASSED_TESTS[@]} + ${#FAILED_TESTS[@]}))
if [ $TOTAL_TESTS -gt 0 ]; then
    PASS_RATE=$(echo "scale=1; ${#PASSED_TESTS[@]} * 100 / $TOTAL_TESTS" | bc)
else
    PASS_RATE=0
fi

echo -e "\nResults:"
echo -e "  ${GREEN}Passed:   ${#PASSED_TESTS[@]}${NC}"
echo -e "  ${RED}Failed:   ${#FAILED_TESTS[@]}${NC}"
echo -e "  ${YELLOW}Warnings: ${#WARNINGS[@]}${NC}"

if [ "${PASS_RATE%.*}" -eq 100 ]; then
    echo -e "  ${GREEN}Success Rate: ${PASS_RATE}%${NC}"
elif [ "${PASS_RATE%.*}" -ge 75 ]; then
    echo -e "  ${YELLOW}Success Rate: ${PASS_RATE}%${NC}"
else
    echo -e "  ${RED}Success Rate: ${PASS_RATE}%${NC}"
fi

# List failures
if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
    echo -e "\n${RED}Failed Tests:${NC}"
    for test in "${FAILED_TESTS[@]}"; do
        echo -e "  ${RED}- $test${NC}"
    done
fi

# List warnings
if [ ${#WARNINGS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Warnings:${NC}"
    for warn in "${WARNINGS[@]}"; do
        echo -e "  ${YELLOW}- $warn${NC}"
    done
fi

# Generate test report
REPORT_PATH="$WORKING_DIR/TEST_REPORT.txt"
cat > "$REPORT_PATH" << EOF
========================================
PORTABLE DISTRIBUTION TEST REPORT
========================================
Test Date: $(date '+%Y-%m-%d %H:%M:%S')
Distribution: $DIST_PATH
Variant: $VARIANT
Hostname: $(hostname)
OS: $(uname -s) $(uname -r)

RESULTS SUMMARY
----------------------------------------
Total Tests: $TOTAL_TESTS
Passed: ${#PASSED_TESTS[@]}
Failed: ${#FAILED_TESTS[@]}
Warnings: ${#WARNINGS[@]}
Success Rate: ${PASS_RATE}%

PASSED TESTS
----------------------------------------
EOF

for test in "${PASSED_TESTS[@]}"; do
    echo "✓ $test" >> "$REPORT_PATH"
done

cat >> "$REPORT_PATH" << EOF

FAILED TESTS
----------------------------------------
EOF

for test in "${FAILED_TESTS[@]}"; do
    echo "✗ $test" >> "$REPORT_PATH"
done

cat >> "$REPORT_PATH" << EOF

WARNINGS
----------------------------------------
EOF

for warn in "${WARNINGS[@]}"; do
    echo "⚠ $warn" >> "$REPORT_PATH"
done

echo "========================================" >> "$REPORT_PATH"

echo -e "\n${CYAN}Test report saved: $REPORT_PATH${NC}"

# Exit with appropriate code
if [ ${#FAILED_TESTS[@]} -eq 0 ]; then
    echo -e "\n${GREEN}✓ ALL TESTS PASSED${NC}"
    exit 0
else
    echo -e "\n${RED}✗ TESTS FAILED${NC}"
    exit 1
fi