#!/bin/bash
#
# Run All FGABattle Tests
#
# This script runs integration tests and optionally K6 load tests
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
NC='\033[0m'

# Configuration
RUN_INTEGRATION="${RUN_INTEGRATION:-true}"
RUN_LOAD_TESTS="${RUN_LOAD_TESTS:-false}"
OPENFGA_URL="${OPENFGA_URL:-http://localhost:8080}"

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
    echo "======================================"
    echo "$1"
    echo "======================================"
    echo ""
}

# Check prerequisites
check_prerequisites() {
    log_section "Checking Prerequisites"

    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        log_error "jq is required but not installed. Install with: brew install jq"
        exit 1
    fi
    log_success "jq is installed"

    # Check if K6 is installed (if load tests requested)
    if [ "$RUN_LOAD_TESTS" = "true" ]; then
        if ! command -v k6 &> /dev/null; then
            log_error "k6 is required for load tests but not installed."
            log_info "Install with: brew install k6"
            exit 1
        fi
        log_success "k6 is installed"
    fi

    # Check if OpenFGA is running
    if ! curl -s "$OPENFGA_URL/healthz" > /dev/null 2>&1; then
        log_error "OpenFGA is not running at $OPENFGA_URL"
        log_info "Start OpenFGA with: cd docker/openfga && docker-compose up -d"
        exit 1
    fi
    log_success "OpenFGA is running at $OPENFGA_URL"
}

# Setup test environment
setup_test_env() {
    log_section "Setting Up Test Environment"

    # Generate test data if needed
    if [ ! -f "tuples/aws-iam-style/scale/mini-tuples.json" ]; then
        log_info "Test data not found. Generating..."
        ./scripts/setup-test-data.sh
    fi
    log_success "Test data ready"

    # Create a test store
    log_info "Creating test store..."
    STORE_RESPONSE=$(curl -s -X POST "$OPENFGA_URL/stores" \
      -H "Content-Type: application/json" \
      -d '{"name": "fgabattle-test"}')

    STORE_ID=$(echo "$STORE_RESPONSE" | jq -r '.id')
    log_success "Created store: $STORE_ID"

    # Upload test model
    log_info "Uploading authorization model..."
    # Note: This assumes you have JSON version of the model
    # For now, we'll use the small dataset's model
    MODEL_RESPONSE=$(curl -s -X POST "$OPENFGA_URL/stores/$STORE_ID/authorization-models" \
      -H "Content-Type: application/json" \
      -d @models/aws-iam-style.json 2>/dev/null || echo '{}')

    MODEL_ID=$(echo "$MODEL_RESPONSE" | jq -r '.authorization_model_id' 2>/dev/null || echo "")

    if [ -z "$MODEL_ID" ] || [ "$MODEL_ID" = "null" ]; then
        log_error "Failed to upload model. Using JSON API format required."
        log_info "Trying alternative approach..."
        # You'll need to implement model upload or use FGA CLI
    fi

    # Load test data
    log_info "Loading test tuples..."
    curl -s -X POST "$OPENFGA_URL/stores/$STORE_ID/write" \
      -H "Content-Type: application/json" \
      -d @tuples/aws-iam-style/scale/mini-tuples.json > /dev/null

    log_success "Test environment ready"

    # Export for tests
    export STORE_ID
    export MODEL_ID
    export OPENFGA_URL
}

# Run integration tests
run_integration_tests() {
    if [ "$RUN_INTEGRATION" != "true" ]; then
        return
    fi

    log_section "Running Integration Tests"

    STORE_ID=$STORE_ID MODEL_ID=$MODEL_ID \
      ./tests/integration/test-basic-operations.sh

    if [ $? -eq 0 ]; then
        log_success "Integration tests passed"
    else
        log_error "Integration tests failed"
        exit 1
    fi
}

# Run K6 load tests
run_load_tests() {
    if [ "$RUN_LOAD_TESTS" != "true" ]; then
        return
    fi

    log_section "Running K6 Load Tests"

    mkdir -p test-results

    # Run check load test
    log_info "Running check load test..."
    STORE_ID=$STORE_ID MODEL_ID=$MODEL_ID OPENFGA_URL=$OPENFGA_URL \
      k6 run --out json=test-results/check-results.json \
      tests/k6/check-load-test.js

    # Run list-objects load test
    log_info "Running list-objects load test..."
    STORE_ID=$STORE_ID MODEL_ID=$MODEL_ID OPENFGA_URL=$OPENFGA_URL \
      k6 run --out json=test-results/list-objects-results.json \
      tests/k6/list-objects-load-test.js

    # Run write load test
    log_info "Running write load test..."
    STORE_ID=$STORE_ID MODEL_ID=$MODEL_ID OPENFGA_URL=$OPENFGA_URL CLEANUP=true \
      k6 run --out json=test-results/write-results.json \
      tests/k6/write-load-test.js

    # Run batch check load test
    log_info "Running batch check load test..."
    STORE_ID=$STORE_ID MODEL_ID=$MODEL_ID OPENFGA_URL=$OPENFGA_URL \
      k6 run --out json=test-results/batch-check-results.json \
      tests/k6/batch-check-load-test.js

    log_success "Load tests completed"
    log_info "Results saved to test-results/"
}

# Cleanup
cleanup() {
    log_section "Cleaning Up"

    if [ -n "$STORE_ID" ]; then
        log_info "Deleting test store $STORE_ID..."
        curl -s -X DELETE "$OPENFGA_URL/stores/$STORE_ID" > /dev/null
        log_success "Test store deleted"
    fi
}

# Main
main() {
    log_section "FGABattle Test Suite"

    log_info "Configuration:"
    log_info "  OpenFGA URL: $OPENFGA_URL"
    log_info "  Run integration tests: $RUN_INTEGRATION"
    log_info "  Run load tests: $RUN_LOAD_TESTS"

    check_prerequisites
    setup_test_env
    run_integration_tests
    run_load_tests
    cleanup

    log_section "All Tests Completed Successfully!"
}

# Handle script interruption
trap cleanup EXIT

# Run main
main
