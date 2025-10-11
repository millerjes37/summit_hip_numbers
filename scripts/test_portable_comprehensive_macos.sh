#!/bin/bash
# scripts/test_portable_comprehensive_macos.sh
# Comprehensive testing framework for macOS .app bundles

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'

# Test results
declare -a PASSED_TESTS=()
declare -a FAILED_TESTS=()
declare -a WARNINGS=()

# Helper functions
section() {
    echo -e "\n${CYAN}========================================"
    echo -e "  $1"
    echo -e "========================================${NC}"
}

step() { echo -e "\n${YELLOW}[TEST] $1${NC}"; }
success() { echo -e "  ${GREEN}✓ $1${NC}"; PASSED_TESTS+=("$1"); }
failure() { echo -e "  ${RED}✗ $1${NC}"; FAILED_TESTS+=("$1"); }
info() { echo -e "  ${GRAY}→ $1${NC}"; }
warning() { echo -e "  ${YELLOW}⚠ $1${NC}"; WARNINGS+=("$1"); }

# Parse arguments
APP_PATH="${1:-}"
VARIANT="${2:-full}"
RUNTIME_SECONDS="${3:-10}"

if [ -z "$APP_PATH" ]; then
    echo -e "${RED}Usage: $0 <app_bundle_path> [variant] [runtime_seconds]${NC}"
    echo "Example: $0 'Summit HIP Numbers.app' full 10"
    exit 1
fi

section "MACOS APPLICATION BUNDLE TEST"
info "App Bundle: $APP_PATH"
info "Variant: $VARIANT"
info "Test Started: $(date '+%Y-%m-%d %H:%M:%S')"

# ============================================================================
# TEST 1: Bundle Structure Validation
# ============================================================================
step "1. Application Bundle Structure"

if [ ! -d "$APP_PATH" ]; then
    failure "App Bundle Exists: Not found: $APP_PATH"
    exit 1
else
    success "App Bundle Exists"
fi

# Check bundle structure
REQUIRED_DIRS=(
    "$APP_PATH/Contents"
    "$APP_PATH/Contents/MacOS"
    "$APP_PATH/Contents/Resources"
)

for dir in "${REQUIRED_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        success "Required Directory: $(basename "$dir")"
    else
        failure "Required Directory Missing: $(basename "$dir")"
    fi
done

# Display bundle size
BUNDLE_SIZE=$(du -sh "$APP_PATH" | cut -f1)
info "Bundle size: $BUNDLE_SIZE"

# List contents
info "Bundle structure:"
find "$APP_PATH" -maxdepth 3 -print | head -n 40 | while read line; do
    echo "    $(basename "$line")"
done

# ============================================================================
# TEST 2: Info.plist Validation
# ============================================================================
step "2. Info.plist Validation"

PLIST_PATH="$APP_PATH/Contents/Info.plist"

if [ ! -f "$PLIST_PATH" ]; then
    failure "Info.plist Not Found"
else
    success "Info.plist Present"
    
    # Validate plist format
    if plutil -lint "$PLIST_PATH" > /dev/null 2>&1; then
        success "Info.plist Format Valid"
    else
        failure "Info.plist Format Invalid"
    fi
    
    # Extract key information
    info "Bundle information:"
    
    BUNDLE_ID=$(plutil -extract CFBundleIdentifier raw "$PLIST_PATH" 2>/dev/null || echo "Not set")
    info "  Bundle ID: $BUNDLE_ID"
    
    BUNDLE_NAME=$(plutil -extract CFBundleName raw "$PLIST_PATH" 2>/dev/null || echo "Not set")
    info "  Name: $BUNDLE_NAME"
    
    BUNDLE_VERSION=$(plutil -extract CFBundleShortVersionString raw "$PLIST_PATH" 2>/dev/null || echo "Not set")
    info "  Version: $BUNDLE_VERSION"
    
    EXECUTABLE=$(plutil -extract CFBundleExecutable raw "$PLIST_PATH" 2>/dev/null || echo "Not set")
    info "  Executable: $EXECUTABLE"
    
    # Check minimum OS version
    MIN_OS=$(plutil -extract LSMinimumSystemVersion raw "$PLIST_PATH" 2>/dev/null || echo "Not specified")
    info "  Minimum macOS: $MIN_OS"
    
    # Current OS version
    CURRENT_OS=$(sw_vers -productVersion)
    info "  Current macOS: $CURRENT_OS"
fi

# ============================================================================
# TEST 3: Executable Detection & Validation
# ============================================================================
step "3. Executable Binary Validation"

# Find main executable
if [ -n "$EXECUTABLE" ] && [ "$EXECUTABLE" != "Not set" ]; then
    BINARY_PATH="$APP_PATH/Contents/MacOS/$EXECUTABLE"
else
    # Try to find any executable
    BINARY_PATH=$(find "$APP_PATH/Contents/MacOS" -type f -perm +111 | head -n 1)
fi

if [ -z "$BINARY_PATH" ] || [ ! -f "$BINARY_PATH" ]; then
    failure "Executable Not Found"
    exit 1
else
    success "Executable Found: $(basename "$BINARY_PATH")"
    
    # Check file type
    FILE_TYPE=$(file "$BINARY_PATH")
    info "File type: $FILE_TYPE"
    
    if echo "$FILE_TYPE" | grep -q "Mach-O.*executable"; then
        success "Valid Mach-O Executable"
    else
        failure "Invalid Binary Format"
    fi
    
    # Check architecture
    ARCHS=$(lipo -info "$BINARY_PATH" 2>/dev/null | sed 's/.*: //' || echo "Unknown")
    info "Architectures: $ARCHS"
    
    # Check if universal binary
    if echo "$ARCHS" | grep -q "arm64.*x86_64\|x86_64.*arm64"; then
        success "Universal Binary (Apple Silicon + Intel)"
    elif echo "$ARCHS" | grep -q "arm64"; then
        info "Apple Silicon only binary"
    elif echo "$ARCHS" | grep -q "x86_64"; then
        info "Intel only binary"
    fi
    
    # Binary size
    SIZE=$(stat -f%z "$BINARY_PATH")
    SIZE_MB=$(echo "scale=2; $SIZE / 1048576" | bc)
    info "Binary size: ${SIZE_MB} MB"
    
    # Check execute permissions
    if [ -x "$BINARY_PATH" ]; then
        success "Execute Permission Set"
    else
        failure "Execute Permission Missing"
    fi
fi

# ============================================================================
# TEST 4: Code Signature Validation
# ============================================================================
step "4. Code Signature Validation"

# Check code signature
if codesign -dv "$APP_PATH" > /dev/null 2>&1; then
    success "App is Code Signed"
    
    # Get signature details
    info "Signature details:"
    codesign -dvvv "$APP_PATH" 2>&1 | grep -E "Authority|TeamIdentifier|Identifier" | while read line; do
        echo "    $line"
    done
    
    # Verify signature
    if codesign --verify --deep --strict "$APP_PATH" 2>&1; then
        success "Signature Verification Passed"
    else
        warning "Signature verification issues detected"
    fi
    
    # Check for hardened runtime
    if codesign -dvvv "$APP_PATH" 2>&1 | grep -q "runtime"; then
        success "Hardened Runtime Enabled"
    else
        info "Hardened runtime not enabled"
    fi
    
    # Check for notarization
    if spctl -a -vv "$APP_PATH" 2>&1 | grep -q "accepted"; then
        success "App is Notarized"
    else
        warning "App is not notarized (required for distribution)"
    fi
else
    warning "App is Not Code Signed"
    info "Ad-hoc signing for testing..."
    codesign --force --deep --sign - "$APP_PATH" 2>&1 || true
fi

# ============================================================================
# TEST 5: Framework & Library Dependencies
# ============================================================================
step "5. Framework & Library Dependencies"

info "Analyzing dynamic dependencies..."

# Get library dependencies
OTOOL_OUTPUT=$(otool -L "$BINARY_PATH" 2>&1)

# Count dependencies
DEP_COUNT=$(echo "$OTOOL_OUTPUT" | grep -c "dylib\|framework" || echo "0")
info "Total dependencies: $DEP_COUNT"

# Check critical frameworks
CRITICAL_FRAMEWORKS=(
    "CoreFoundation"
    "Foundation"
    "AppKit"
    "AVFoundation"
)

info "Checking system frameworks:"
for framework in "${CRITICAL_FRAMEWORKS[@]}"; do
    if echo "$OTOOL_OUTPUT" | grep -q "$framework"; then
        success "$framework linked"
    else
        info "$framework not linked (may not be required)"
    fi
done

# Check for bundled frameworks
FRAMEWORKS_DIR="$APP_PATH/Contents/Frameworks"
if [ -d "$FRAMEWORKS_DIR" ]; then
    BUNDLED_COUNT=$(find "$FRAMEWORKS_DIR" -name "*.framework" -o -name "*.dylib" | wc -l)
    if [ "$BUNDLED_COUNT" -gt 0 ]; then
        success "Bundled Frameworks: $BUNDLED_COUNT found"
        info "Bundled frameworks:"
        find "$FRAMEWORKS_DIR" -depth 1 | while read fw; do
            echo "    $(basename "$fw")"
        done
    fi
else
    info "No bundled frameworks directory"
fi

# Check for GStreamer
if echo "$OTOOL_OUTPUT" | grep -q -i "gstreamer\|glib\|gobject"; then
    success "GStreamer Libraries Detected"
    
    # Find GStreamer plugins
    PLUGIN_DIRS=(
        "$APP_PATH/Contents/Resources/lib/gstreamer-1.0"
        "$APP_PATH/Contents/Frameworks/GStreamer.framework/Versions/Current/lib/gstreamer-1.0"
    )
    
    for plugin_dir in "${PLUGIN_DIRS[@]}"; do
        if [ -d "$plugin_dir" ]; then
            PLUGIN_COUNT=$(find "$plugin_dir" -name "*.so" -o -name "*.dylib" | wc -l)
            success "GStreamer Plugins: $PLUGIN_COUNT in $(basename "$(dirname "$plugin_dir")")"
            break
        fi
    done
else
    info "No GStreamer dependencies detected"
fi

# Check for broken links
info "Checking for broken library references..."
BROKEN_LIBS=$(echo "$OTOOL_OUTPUT" | grep "@rpath\|@executable_path\|@loader_path" | awk '{print $1}')
if [ -n "$BROKEN_LIBS" ]; then
    info "Dynamic library paths found (checking resolution):"
    echo "$BROKEN_LIBS" | while read lib; do
        echo "    $lib"
    done
else
    success "No Relative Library Paths (fully resolved)"
fi

# Save dependency report
DEP_REPORT="$APP_PATH/Contents/test-dependencies.txt"
cat > "$DEP_REPORT" << EOF
Framework & Library Dependencies Report
Generated: $(date '+%Y-%m-%d %H:%M:%S')
Binary: $BINARY_PATH

Dynamic Dependencies:
----------------------------------------
$OTOOL_OUTPUT

EOF

# ============================================================================
# TEST 6: Resources Validation
# ============================================================================
step "6. Application Resources"

RESOURCES_DIR="$APP_PATH/Contents/Resources"

if [ -d "$RESOURCES_DIR" ]; then
    RESOURCE_COUNT=$(find "$RESOURCES_DIR" -type f | wc -l)
    info "Resource files: $RESOURCE_COUNT"
    
    # Check for common resources
    declare -A RESOURCE_TYPES=(
        ["*.icns"]="Icon"
        ["*.nib"]="Interface"
        ["*.xib"]="Interface"
        ["*.strings"]="Localization"
        ["*.lproj"]="Localization Bundle"
    )
    
    for pattern in "${!RESOURCE_TYPES[@]}"; do
        COUNT=$(find "$RESOURCES_DIR" -name "$pattern" | wc -l)
        if [ "$COUNT" -gt 0 ]; then
            info "${RESOURCE_TYPES[$pattern]}: $COUNT files"
        fi
    done
    
    # Check for icon
    if [ -f "$RESOURCES_DIR/AppIcon.icns" ] || find "$RESOURCES_DIR" -name "*.icns" | grep -q .; then
        success "App Icon Present"
    else
        warning "No app icon found"
    fi
fi

# ============================================================================
# TEST 7: Gatekeeper & Security Assessment
# ============================================================================
step "7. Gatekeeper & Security Assessment"

# Check quarantine attribute
if xattr -l "$APP_PATH" | grep -q "com.apple.quarantine"; then
    warning "Quarantine attribute present (downloaded from internet)"
    info "Attempting to remove quarantine for testing..."
    xattr -dr com.apple.quarantine "$APP_PATH" 2>&1 || true
else
    info "No quarantine attribute"
fi

# Check Gatekeeper assessment
info "Running Gatekeeper assessment..."
SPCTL_OUTPUT=$(spctl -a -t execute -vv "$APP_PATH" 2>&1 || true)
echo "$SPCTL_OUTPUT" | while read line; do
    echo "    $line"
done

if echo "$SPCTL_OUTPUT" | grep -q "accepted"; then
    success "Gatekeeper Assessment: Passed"
elif echo "$SPCTL_OUTPUT" | grep -q "rejected"; then
    warning "Gatekeeper Assessment: Rejected (app may not run on other systems)"
else
    info "Gatekeeper Assessment: Unknown status"
fi

# ============================================================================
# TEST 8: Runtime Execution Test
# ============================================================================
step "8. Runtime Execution Test"

LOG_FILE="$APP_PATH/Contents/test-runtime.log"
ERROR_FILE="$APP_PATH/Contents/test-runtime-error.log"

# Clean old logs
rm -f "$LOG_FILE" "$ERROR_FILE"

info "Attempting runtime execution..."

# Try --version flag first
info "Testing --version flag..."
if timeout 5s "$BINARY_PATH" --version > "$LOG_FILE" 2>&1; then
    success "Version Check Passed"
    cat "$LOG_FILE"
else
    info "Version check timed out or not supported"
fi

# Full runtime test
info "Starting full runtime test (${RUNTIME_SECONDS}s)..."

# Open app in background
open -a "$APP_PATH" 2> "$ERROR_FILE" &
OPEN_PID=$!

sleep 2

# Check if app opened
APP_NAME=$(basename "$APP_PATH" .app)
if pgrep -f "$APP_NAME" > /dev/null; then
    PID=$(pgrep -f "$APP_NAME" | head -n 1)
    success "Application Launched (PID: $PID)"
    
    # Monitor for stability
    sleep 3
    
    if pgrep -f "$APP_NAME" > /dev/null; then
        success "Application Stable After 3 Seconds"
        
        # Get memory usage
        MEM_USAGE=$(ps -p "$PID" -o rss= | awk '{print $1/1024}')
        info "Memory usage: ${MEM_USAGE} MB"
        
        # Wait remaining time
        WAIT_TIME=$((RUNTIME_SECONDS - 5))
        if [ $WAIT_TIME -gt 0 ]; then
            sleep $WAIT_TIME
        fi
        
        # Final check
        if pgrep -f "$APP_NAME" > /dev/null; then
            success "Application Stable After Full Runtime"
            info "Terminating application..."
            killall "$APP_NAME" 2>/dev/null || true
        else
            warning "Application exited during runtime test"
        fi
    else
        failure "Application Crashed Shortly After Launch"
    fi
else
    failure "Application Failed to Launch"
    
    # Check system log for errors
    info "Checking system log for errors..."
    log show --predicate 'process == "'"$APP_NAME"'"' --last 1m --style compact 2>/dev/null | tail -n 20
fi

# Check crash reports
CRASH_REPORTS=~/Library/Logs/DiagnosticReports/"$APP_NAME"*.crash
if ls $CRASH_REPORTS > /dev/null 2>&1; then
    failure "Crash Report Generated"
    info "Latest crash report:"
    ls -t $CRASH_REPORTS | head -n 1 | xargs tail -n 50
else
    success "No Crash Reports Found"
fi

# Display error log if exists
if [ -f "$ERROR_FILE" ] && [ -s "$ERROR_FILE" ]; then
    echo -e "\n${YELLOW}--- STDERR ---${NC}"
    cat "$ERROR_FILE"
fi

# ============================================================================
# TEST 9: Accessibility & Permissions
# ============================================================================
step "9. Accessibility & Permissions"

# Check for required entitlements
info "Checking entitlements..."
ENTITLEMENTS=$(codesign -d --entitlements - "$APP_PATH" 2>&1 || echo "None")

if echo "$ENTITLEMENTS" | grep -q "com.apple.security"; then
    info "Security entitlements found:"
    echo "$ENTITLEMENTS" | grep "com.apple.security" | while read line; do
        echo "    $line"
    done
else
    info "No special entitlements detected"
fi

# Check for camera/microphone usage descriptions
if plutil -extract NSCameraUsageDescription raw "$PLIST_PATH" > /dev/null 2>&1; then
    CAM_DESC=$(plutil -extract NSCameraUsageDescription raw "$PLIST_PATH")
    info "Camera usage: $CAM_DESC"
fi

if plutil -extract NSMicrophoneUsageDescription raw "$PLIST_PATH" > /dev/null 2>&1; then
    MIC_DESC=$(plutil -extract NSMicrophoneUsageDescription raw "$PLIST_PATH")
    info "Microphone usage: $MIC_DESC"
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
REPORT_PATH="$APP_PATH/Contents/TEST_REPORT.txt"
cat > "$REPORT_PATH" << EOF
========================================
MACOS APPLICATION BUNDLE TEST REPORT
========================================
Test Date: $(date '+%Y-%m-%d %H:%M:%S')
App Bundle: $APP_PATH
Variant: $VARIANT
macOS Version: $(sw_vers -productVersion)
Hardware: $(uname -m)

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