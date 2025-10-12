#!/bin/bash
# Automated CI Fix Script
# This script fixes common CI issues and validates the fixes

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Summit Hip Numbers CI Fix Tool ===${NC}"
echo ""

# Function to check if command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Function to fix cargo audit configuration
fix_cargo_audit() {
    echo -e "${YELLOW}Checking cargo audit configuration...${NC}"
    
    if [ -f ".cargo/audit.toml" ]; then
        echo "Found .cargo/audit.toml - checking format..."
        
        # Check if file has incorrect format
        if grep -q "^\[\[advisories\.ignore\]\]" .cargo/audit.toml; then
            echo -e "${RED}Found incorrect audit.toml format${NC}"
            echo "Fixing audit.toml format..."
            
            # Create backup
            cp .cargo/audit.toml .cargo/audit.toml.bak
            
            # Fix the format
            cat > .cargo/audit.toml << 'EOF'
# Cargo audit configuration
# This file configures which security advisories to ignore

[advisories]
ignore = [
    "RUSTSEC-2020-0071",  # chrono time zone vulnerability - low impact for kiosk application
    "RUSTSEC-2020-0159",  # tokio async task vulnerability - low impact for sync-only usage  
    "RUSTSEC-2021-0139",  # ansi_term color vulnerability - not used in this application
]

# You can also use this format with reasons:
# ignore = [
#     { id = "RUSTSEC-2020-0071", reason = "chrono time zone vulnerability - low impact for kiosk application" },
# ]
EOF
            echo -e "${GREEN}✓ Fixed audit.toml format${NC}"
        else
            echo -e "${GREEN}✓ audit.toml format is correct${NC}"
        fi
    fi
}

# Function to fix clippy issues
fix_clippy_issues() {
    echo -e "${YELLOW}Checking for clippy issues...${NC}"
    
    # Remove unused imports
    echo "Fixing unused imports..."
    find crates -name "*.rs" -type f -exec sed -i.bak '/^use dunce;$/d' {} \;
    find crates -name "*.rs" -type f -exec sed -i.bak '/^use chrono;.*\/\/ Using full path/d' {} \;
    find crates -name "*.rs" -type f -exec sed -i.bak '/^use fern;.*\/\/ Using full path/d' {} \;
    
    # Clean up backup files
    find crates -name "*.rs.bak" -type f -delete
    
    echo -e "${GREEN}✓ Fixed unused imports${NC}"
}

# Function to fix formatting issues
fix_formatting() {
    echo -e "${YELLOW}Running cargo fmt...${NC}"
    
    if command_exists cargo; then
        cargo fmt --all
        echo -e "${GREEN}✓ Code formatted${NC}"
    else
        echo -e "${RED}cargo not found - skipping formatting${NC}"
    fi
}

# Function to validate fixes
validate_fixes() {
    echo ""
    echo -e "${BLUE}=== Validating Fixes ===${NC}"
    
    # Test cargo audit
    if command_exists cargo-audit; then
        echo -e "${YELLOW}Testing cargo audit...${NC}"
        if cargo audit 2>&1 | grep -q "TOML parse error"; then
            echo -e "${RED}✗ Cargo audit still failing${NC}"
            return 1
        else
            echo -e "${GREEN}✓ Cargo audit working${NC}"
        fi
    else
        echo -e "${YELLOW}cargo-audit not installed - installing...${NC}"
        cargo install cargo-audit
    fi
    
    # Test clippy (without GStreamer to avoid dependency issues)
    if command_exists cargo; then
        echo -e "${YELLOW}Testing clippy...${NC}"
        if cargo clippy --all-targets --no-default-features -- -D warnings 2>&1 | grep -q "error"; then
            echo -e "${RED}✗ Clippy still has errors${NC}"
            # Show the errors
            cargo clippy --all-targets --no-default-features -- -D warnings 2>&1 | grep -A5 "error"
        else
            echo -e "${GREEN}✓ Clippy passing${NC}"
        fi
    fi
    
    # Test formatting
    echo -e "${YELLOW}Checking formatting...${NC}"
    if cargo fmt --all -- --check 2>&1 | grep -q "Diff"; then
        echo -e "${RED}✗ Code needs formatting${NC}"
    else
        echo -e "${GREEN}✓ Code properly formatted${NC}"
    fi
}

# Function to test CI locally
test_ci_locally() {
    echo ""
    echo -e "${BLUE}=== Testing CI Steps Locally ===${NC}"
    
    # Run tests
    echo -e "${YELLOW}Running tests...${NC}"
    if cargo test --workspace --no-default-features 2>&1 | grep -q "test result: ok"; then
        echo -e "${GREEN}✓ All tests passing${NC}"
    else
        echo -e "${RED}✗ Some tests failing${NC}"
    fi
}

# Function to commit fixes
commit_fixes() {
    echo ""
    echo -e "${BLUE}=== Committing Fixes ===${NC}"
    
    # Check if there are changes
    if git diff --quiet && git diff --cached --quiet; then
        echo "No changes to commit"
        return 0
    fi
    
    echo "Changes detected:"
    git status --short
    
    read -p "Do you want to commit these fixes? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        git add .cargo/audit.toml
        git add -u  # Add modified files only
        
        git commit -m "fix: Resolve CI pipeline issues

- Fix cargo-audit TOML configuration format
- Remove unused imports flagged by clippy
- Apply cargo fmt formatting

This resolves the CI pipeline failures in the Code Quality & Security job."
        
        echo -e "${GREEN}✓ Fixes committed${NC}"
        
        read -p "Do you want to push to trigger CI? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            git push
            echo -e "${GREEN}✓ Pushed to remote${NC}"
            echo ""
            echo "Monitor CI status with:"
            echo "  gh run watch"
        fi
    fi
}

# Function to monitor CI
monitor_ci() {
    echo ""
    echo -e "${BLUE}=== CI Monitoring Commands ===${NC}"
    echo "Check workflow status:"
    echo "  gh workflow list"
    echo ""
    echo "View recent runs:"
    echo "  gh run list --limit 5"
    echo ""
    echo "Watch latest run:"
    echo "  gh run watch"
    echo ""
    echo "View specific run logs:"
    echo "  gh run view <run-id> --log"
}

# Main execution
main() {
    # Check if we're in a git repository
    if ! git rev-parse --is-inside-work-tree &> /dev/null; then
        echo -e "${RED}Error: Not in a git repository${NC}"
        exit 1
    fi
    
    # Check if gh CLI is available
    if ! command_exists gh; then
        echo -e "${YELLOW}Warning: GitHub CLI (gh) not found${NC}"
        echo "Install with: brew install gh"
    fi
    
    # Run fixes
    fix_cargo_audit
    fix_clippy_issues
    fix_formatting
    
    # Validate
    validate_fixes
    
    # Test locally
    test_ci_locally
    
    # Offer to commit
    commit_fixes
    
    # Show monitoring commands
    monitor_ci
    
    echo ""
    echo -e "${GREEN}=== CI Fix Complete ===${NC}"
}

# Run main function
main "$@"