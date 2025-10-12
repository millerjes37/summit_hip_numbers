#!/bin/bash
# Test CI Pipeline Locally
# This script runs all CI checks locally before pushing

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Testing CI Pipeline Locally ===${NC}"
echo ""

# Track failures
FAILURES=0

# Function to run a check
run_check() {
    local name=$1
    local command=$2
    
    echo -e "${YELLOW}Running: $name${NC}"
    if eval "$command" > /tmp/ci_test_$$.log 2>&1; then
        echo -e "${GREEN}✓ $name passed${NC}"
    else
        echo -e "${RED}✗ $name failed${NC}"
        echo "Error output:"
        tail -20 /tmp/ci_test_$$.log
        ((FAILURES++))
    fi
    rm -f /tmp/ci_test_$$.log
}

# 1. Format check
run_check "Format Check" "cargo fmt --all -- --check"

# 2. Clippy check (with all features)
run_check "Clippy (all features)" "cargo clippy --all-targets --all-features -- -D warnings"

# 3. Clippy check (no default features)
run_check "Clippy (no features)" "cargo clippy --all-targets --no-default-features -- -D warnings"

# 4. Tests (all features)
run_check "Tests (all features)" "cargo test --workspace --all-features"

# 5. Tests (no default features)
run_check "Tests (no features)" "cargo test --workspace --no-default-features"

# 6. Security audit
if command -v cargo-audit &> /dev/null; then
    run_check "Security Audit" "cargo audit"
else
    echo -e "${YELLOW}Skipping security audit (cargo-audit not installed)${NC}"
fi

# 7. Build check (all platforms)
run_check "Build (default)" "cargo build --release"
run_check "Build (demo)" "cargo build --release --features demo"

# 8. Documentation check
run_check "Documentation" "cargo doc --no-deps --all-features"

# Summary
echo ""
echo -e "${BLUE}=== Summary ===${NC}"
if [ $FAILURES -eq 0 ]; then
    echo -e "${GREEN}All checks passed! Safe to push.${NC}"
else
    echo -e "${RED}$FAILURES checks failed. Fix issues before pushing.${NC}"
    exit 1
fi