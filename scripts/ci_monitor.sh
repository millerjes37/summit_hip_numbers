#!/bin/bash
# CI Monitoring and Auto-Fix Tool
# This script monitors CI runs and can automatically fix common issues

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to get latest run ID
get_latest_run() {
    gh run list --limit 1 --json databaseId --jq '.[0].databaseId'
}

# Function to monitor a specific run
monitor_run() {
    local run_id=$1
    echo -e "${BLUE}Monitoring run $run_id...${NC}"
    
    # Watch the run
    gh run watch "$run_id" &
    local watch_pid=$!
    
    # Wait for completion
    while true; do
        local status=$(gh run view "$run_id" --json status --jq '.status')
        local conclusion=$(gh run view "$run_id" --json conclusion --jq '.conclusion')
        
        if [[ "$status" == "completed" ]]; then
            kill $watch_pid 2>/dev/null || true
            
            if [[ "$conclusion" == "success" ]]; then
                echo -e "${GREEN}✓ CI run succeeded!${NC}"
                return 0
            else
                echo -e "${RED}✗ CI run failed with conclusion: $conclusion${NC}"
                return 1
            fi
        fi
        
        sleep 10
    done
}

# Function to analyze failure
analyze_failure() {
    local run_id=$1
    echo -e "${YELLOW}Analyzing failure for run $run_id...${NC}"
    
    # Get failed jobs
    local failed_jobs=$(gh run view "$run_id" --json jobs --jq '.jobs[] | select(.conclusion == "failure") | .name')
    
    echo -e "${RED}Failed jobs:${NC}"
    echo "$failed_jobs"
    
    # Common error patterns
    local errors=""
    
    # Check for cargo audit errors
    if gh run view "$run_id" --log 2>/dev/null | grep -q "cargo-audit fatal error"; then
        errors="${errors}cargo-audit configuration error\n"
    fi
    
    # Check for clippy errors
    if gh run view "$run_id" --log 2>/dev/null | grep -q "error: .* clippy"; then
        errors="${errors}Clippy linting errors\n"
    fi
    
    # Check for format errors
    if gh run view "$run_id" --log 2>/dev/null | grep -q "Diff in .* at line"; then
        errors="${errors}Code formatting errors\n"
    fi
    
    # Check for test failures
    if gh run view "$run_id" --log 2>/dev/null | grep -q "test result: FAILED"; then
        errors="${errors}Test failures\n"
    fi
    
    # Check for build errors
    if gh run view "$run_id" --log 2>/dev/null | grep -q "error\[E[0-9]\+\]"; then
        errors="${errors}Rust compilation errors\n"
    fi
    
    if [[ -n "$errors" ]]; then
        echo -e "${YELLOW}Detected issues:${NC}"
        echo -e "$errors"
    fi
}

# Function to show detailed logs
show_logs() {
    local run_id=$1
    local job_name=$2
    
    if [[ -n "$job_name" ]]; then
        echo -e "${CYAN}Logs for job '$job_name':${NC}"
        gh run view "$run_id" --log | grep -A10 -B10 "$job_name" | tail -50
    else
        echo -e "${CYAN}Recent error logs:${NC}"
        gh run view "$run_id" --log | grep -E "(error:|Error:|FAILED|failed)" | tail -20
    fi
}

# Function to trigger re-run
trigger_rerun() {
    local run_id=$1
    echo -e "${YELLOW}Triggering re-run for $run_id...${NC}"
    gh run rerun "$run_id"
}

# Main monitoring loop
main() {
    echo -e "${BLUE}=== Summit Hip Numbers CI Monitor ===${NC}"
    echo ""
    
    # Check if gh CLI is available
    if ! command -v gh &> /dev/null; then
        echo -e "${RED}Error: GitHub CLI (gh) not found${NC}"
        echo "Install with: brew install gh"
        exit 1
    fi
    
    # Get command
    local command=${1:-watch}
    
    case "$command" in
        watch)
            # Monitor latest run
            local run_id=$(get_latest_run)
            echo -e "${CYAN}Latest run ID: $run_id${NC}"
            
            if monitor_run "$run_id"; then
                echo -e "${GREEN}CI passed successfully!${NC}"
            else
                analyze_failure "$run_id"
                echo ""
                echo -e "${YELLOW}Options:${NC}"
                echo "  1. View detailed logs"
                echo "  2. Run fix_ci.sh"
                echo "  3. Trigger re-run"
                echo "  4. Exit"
                
                read -p "Select option (1-4): " option
                
                case "$option" in
                    1)
                        show_logs "$run_id"
                        ;;
                    2)
                        ./scripts/fix_ci.sh
                        ;;
                    3)
                        trigger_rerun "$run_id"
                        ;;
                    *)
                        exit 0
                        ;;
                esac
            fi
            ;;
            
        status)
            # Show current status
            echo -e "${CYAN}Recent CI runs:${NC}"
            gh run list --limit 5
            ;;
            
        logs)
            # Show logs for specific run
            local run_id=${2:-$(get_latest_run)}
            show_logs "$run_id" "$3"
            ;;
            
        analyze)
            # Analyze specific run
            local run_id=${2:-$(get_latest_run)}
            analyze_failure "$run_id"
            ;;
            
        rerun)
            # Re-run specific run
            local run_id=${2:-$(get_latest_run)}
            trigger_rerun "$run_id"
            ;;
            
        *)
            echo "Usage: $0 [command] [options]"
            echo ""
            echo "Commands:"
            echo "  watch    - Monitor latest CI run (default)"
            echo "  status   - Show recent CI runs"
            echo "  logs     - Show logs for a run"
            echo "  analyze  - Analyze a failed run"
            echo "  rerun    - Trigger re-run"
            echo ""
            echo "Examples:"
            echo "  $0 watch"
            echo "  $0 logs 12345678"
            echo "  $0 analyze 12345678"
            ;;
    esac
}

# Run main function
main "$@"