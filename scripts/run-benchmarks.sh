#!/bin/bash
#
# Run K6 Benchmarks
#
# This script runs all K6 load tests and generates a comprehensive benchmark report
#

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

cd "$PROJECT_ROOT"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
OPENFGA_URL="${OPENFGA_URL:-http://localhost:8080}"
SCALE="${SCALE:-mid}"  # mini, mid, large, huge
REPORT_FILE="test-results/benchmark-report-$(date +%Y%m%d-%H%M%S).md"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_section() {
    echo ""
    echo "======================================="
    echo "$1"
    echo "======================================="
    echo ""
}

# Initialize report
init_report() {
    mkdir -p test-results

    cat > "$REPORT_FILE" <<EOF
# OpenFGA Benchmark Report

**Date**: $(date)
**Scale**: $SCALE
**OpenFGA URL**: $OPENFGA_URL

## Test Configuration

- Dataset: aws-iam-style
- Scale: $SCALE
- Load testing tool: K6

---

EOF
}

# Add to report
report() {
    echo "$1" >> "$REPORT_FILE"
}

# Main
main() {
    log_section "OpenFGA K6 Benchmark Suite"

    log_info "Configuration:"
    log_info "  Scale: $SCALE"
    log_info "  OpenFGA URL: $OPENFGA_URL"
    echo ""

    # Check if OpenFGA is running
    if ! curl -s "$OPENFGA_URL/healthz" > /dev/null 2>&1; then
        log_error "OpenFGA is not running at $OPENFGA_URL"
        exit 1
    fi
    log_success "OpenFGA is running"

    # Check if test data exists
    if [ ! -f "tuples/aws-iam-style/scale/${SCALE}-tuples.json" ]; then
        log_error "Test data not found for scale: $SCALE"
        log_info "Run: ./scripts/setup-test-data.sh"
        exit 1
    fi
    log_success "Test data found for scale: $SCALE"

    # Check if K6 is installed
    if ! command -v k6 &> /dev/null; then
        log_error "k6 is required but not installed. Install with: brew install k6"
        exit 1
    fi
    log_success "k6 is installed"

    # Initialize report
    init_report

    # Create test store
    log_info "Creating test store..."
    STORE_RESPONSE=$(curl -s -X POST "$OPENFGA_URL/stores" \
      -H "Content-Type: application/json" \
      -d "{\"name\": \"benchmark-test-$SCALE-$(date +%s)\"}")

    STORE_ID=$(echo "$STORE_RESPONSE" | jq -r '.id')
    log_success "Created store: $STORE_ID"

    # Upload model
    log_info "Uploading authorization model..."
    MODEL_RESPONSE=$(curl -s -X POST "$OPENFGA_URL/stores/$STORE_ID/authorization-models" \
      -H "Content-Type: application/json" \
      -d @models/aws-iam-style.json)

    MODEL_ID=$(echo "$MODEL_RESPONSE" | jq -r '.authorization_model_id')

    if [ -z "$MODEL_ID" ] || [ "$MODEL_ID" = "null" ]; then
        log_error "Failed to upload model"
        curl -s -X DELETE "$OPENFGA_URL/stores/$STORE_ID" > /dev/null
        exit 1
    fi

    log_success "Uploaded model: $MODEL_ID"

    # Load test data
    log_info "Loading test data ($SCALE scale)..."
    local LOAD_START=$(date +%s)

    if [ "$SCALE" = "large" ] || [ "$SCALE" = "huge" ]; then
        log_info "Large dataset detected - loading in batches..."

        jq -c '.writes.tuple_keys | _nwise(10000) | {writes: {tuple_keys: .}}' \
          "tuples/aws-iam-style/scale/${SCALE}-tuples.json" | \
          while IFS= read -r batch; do
            curl -s -X POST "$OPENFGA_URL/stores/$STORE_ID/write" \
              -H "Content-Type: application/json" \
              -d "$batch" > /dev/null
            echo -n "."
          done
        echo ""
    else
        curl -s -X POST "$OPENFGA_URL/stores/$STORE_ID/write" \
          -H "Content-Type: application/json" \
          -d @"tuples/aws-iam-style/scale/${SCALE}-tuples.json" > /dev/null
    fi

    LOAD_TIME=$(($(date +%s) - LOAD_START))
    log_success "Test data loaded (${LOAD_TIME}s)"

    report "## Data Loading"
    report "- Time to load: ${LOAD_TIME}s"
    report ""
    report "---"
    report ""

    # Export for K6 tests
    export STORE_ID
    export MODEL_ID
    export OPENFGA_URL

    # Run K6 tests
    log_section "Running K6 Load Tests"

    # Test 1: Check Load Test
    log_info "Running check load test..."
    report "## Test 1: Check Load Test"
    report ""
    k6 run --out json=test-results/check-results.json tests/k6/check-load-test.js | tee test-results/check-output.txt

    # Extract metrics
    if [ -f test-results/check-output.txt ]; then
        report '```'
        grep -A 20 "checks\|http_req" test-results/check-output.txt >> "$REPORT_FILE" || true
        report '```'
    fi
    report ""
    report "---"
    report ""

    # Test 2: List Objects Load Test
    log_info "Running list-objects load test..."
    report "## Test 2: List Objects Load Test"
    report ""
    k6 run --out json=test-results/list-objects-results.json tests/k6/list-objects-load-test.js | tee test-results/list-objects-output.txt

    if [ -f test-results/list-objects-output.txt ]; then
        report '```'
        grep -A 20 "checks\|http_req" test-results/list-objects-output.txt >> "$REPORT_FILE" || true
        report '```'
    fi
    report ""
    report "---"
    report ""

    # Test 3: Write Load Test
    log_info "Running write load test..."
    report "## Test 3: Write Load Test"
    report ""
    CLEANUP=true k6 run --out json=test-results/write-results.json tests/k6/write-load-test.js | tee test-results/write-output.txt

    if [ -f test-results/write-output.txt ]; then
        report '```'
        grep -A 20 "checks\|http_req" test-results/write-output.txt >> "$REPORT_FILE" || true
        report '```'
    fi
    report ""
    report "---"
    report ""

    # Test 4: Batch Check Load Test
    log_info "Running batch check load test..."
    report "## Test 4: Batch Check Load Test"
    report ""
    k6 run --out json=test-results/batch-check-results.json tests/k6/batch-check-load-test.js | tee test-results/batch-check-output.txt

    if [ -f test-results/batch-check-output.txt ]; then
        report '```'
        grep -A 20 "checks\|http_req" test-results/batch-check-output.txt >> "$REPORT_FILE" || true
        report '```'
    fi
    report ""
    report "---"
    report ""

    # Cleanup
    log_info "Cleaning up test store..."
    curl -s -X DELETE "$OPENFGA_URL/stores/$STORE_ID" > /dev/null
    log_success "Test store deleted"

    # Summary
    report "## Summary"
    report ""
    report "All K6 load tests completed successfully."
    report ""
    report "### Files Generated"
    report "- \`test-results/check-results.json\` - Check operation metrics"
    report "- \`test-results/list-objects-results.json\` - List objects metrics"
    report "- \`test-results/write-results.json\` - Write operation metrics"
    report "- \`test-results/batch-check-results.json\` - Batch check metrics"
    report ""

    log_section "Benchmark Complete!"
    log_success "Report saved to: $REPORT_FILE"
}

# Run main
main
