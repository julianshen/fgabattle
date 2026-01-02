#!/bin/bash
#
# Test All Models with Different Scales
#
# Tests all authorization models with different dataset scales
# and generates a comprehensive report
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
SCALE="${SCALE:-large}"  # mini, mid, large, huge
REPORT_FILE="test-results/multi-model-test-report-$(date +%Y%m%d-%H%M%S).md"

# Test results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Timing
START_TIME=$(date +%s)

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_test() {
    echo -e "${CYAN}[TEST]${NC} $1"
}

# Initialize report
init_report() {
    mkdir -p test-results

    cat > "$REPORT_FILE" <<EOF
# Multi-Model Integration Test Report

**Date**: $(date)
**Scale**: $SCALE
**OpenFGA URL**: $OPENFGA_URL

## Test Configuration

- Dataset: aws-iam-style
- Scale: $SCALE
- Models tested: AWS IAM Style

---

EOF
}

# Add to report
report() {
    echo "$1" >> "$REPORT_FILE"
}

# Test a specific model
test_model() {
    local MODEL_NAME=$1
    local STORE_ID=$2
    local MODEL_ID=$3

    log_test "Testing model: $MODEL_NAME"

    report "## Model: $MODEL_NAME"
    report ""
    report "- **Store ID**: \`$STORE_ID\`"
    report "- **Model ID**: \`$MODEL_ID\`"
    report ""

    local MODEL_START=$(date +%s)

    # Test 1: Check operation
    log_info "  → Test 1: Check operation"
    local CHECK_START=$(date +%s)

    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$OPENFGA_URL/stores/$STORE_ID/check" \
      -H "Content-Type: application/json" \
      -d "{
        \"tuple_key\": {
          \"user\": \"user:user-0000-00042\",
          \"relation\": \"can_read\",
          \"object\": \"s3_bucket:bucket-0000-00005\"
        },
        \"authorization_model_id\": \"$MODEL_ID\"
      }")

    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    CHECK_TIME=$(($(date +%s) - CHECK_START))

    if [ "$HTTP_CODE" = "200" ] && echo "$BODY" | jq -e '.allowed != null' > /dev/null 2>&1; then
        ALLOWED=$(echo "$BODY" | jq -r '.allowed')
        log_success "  ✓ Check operation: allowed=$ALLOWED (${CHECK_TIME}s)"
        report "### Test 1: Check Operation ✅"
        report "- Result: \`allowed=$ALLOWED\`"
        report "- Time: ${CHECK_TIME}s"
        ((PASSED_TESTS++))
    else
        log_error "  ✗ Check operation failed"
        report "### Test 1: Check Operation ❌"
        report "- Error: $BODY"
        ((FAILED_TESTS++))
    fi
    ((TOTAL_TESTS++))
    report ""

    # Test 2: List objects
    log_info "  → Test 2: List objects"
    local LIST_START=$(date +%s)

    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$OPENFGA_URL/stores/$STORE_ID/list-objects" \
      -H "Content-Type: application/json" \
      -d "{
        \"authorization_model_id\": \"$MODEL_ID\",
        \"type\": \"s3_bucket\",
        \"relation\": \"can_read\",
        \"user\": \"user:user-0000-00042\"
      }")

    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    LIST_TIME=$(($(date +%s) - LIST_START))

    if [ "$HTTP_CODE" = "200" ] && echo "$BODY" | jq -e '.objects' > /dev/null 2>&1; then
        OBJECT_COUNT=$(echo "$BODY" | jq '.objects | length')
        log_success "  ✓ List objects: found $OBJECT_COUNT objects (${LIST_TIME}s)"
        report "### Test 2: List Objects ✅"
        report "- Objects found: $OBJECT_COUNT"
        report "- Time: ${LIST_TIME}s"
        ((PASSED_TESTS++))
    else
        log_error "  ✗ List objects failed"
        report "### Test 2: List Objects ❌"
        report "- Error: $BODY"
        ((FAILED_TESTS++))
    fi
    ((TOTAL_TESTS++))
    report ""

    # Test 3: Write operation
    log_info "  → Test 3: Write operation"
    local WRITE_START=$(date +%s)

    TEST_USER="user:test-$$-$(date +%s)"
    TEST_RESOURCE="s3_bucket:test-bucket-$$"

    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$OPENFGA_URL/stores/$STORE_ID/write" \
      -H "Content-Type: application/json" \
      -d "{
        \"writes\": {
          \"tuple_keys\": [{
            \"user\": \"$TEST_USER\",
            \"relation\": \"identity_based_read\",
            \"object\": \"$TEST_RESOURCE\"
          }]
        }
      }")

    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    WRITE_TIME=$(($(date +%s) - WRITE_START))

    if [ "$HTTP_CODE" = "200" ]; then
        log_success "  ✓ Write operation (${WRITE_TIME}s)"
        report "### Test 3: Write Operation ✅"
        report "- Time: ${WRITE_TIME}s"
        ((PASSED_TESTS++))

        # Cleanup
        curl -s -X POST "$OPENFGA_URL/stores/$STORE_ID/write" \
          -H "Content-Type: application/json" \
          -d "{
            \"deletes\": {
              \"tuple_keys\": [{
                \"user\": \"$TEST_USER\",
                \"relation\": \"identity_based_read\",
                \"object\": \"$TEST_RESOURCE\"
              }]
            }
          }" > /dev/null
    else
        log_error "  ✗ Write operation failed"
        report "### Test 3: Write Operation ❌"
        ((FAILED_TESTS++))
    fi
    ((TOTAL_TESTS++))
    report ""

    # Test 4: Batch check
    log_info "  → Test 4: Batch check"
    local BATCH_START=$(date +%s)

    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$OPENFGA_URL/stores/$STORE_ID/batch-check" \
      -H "Content-Type: application/json" \
      -d "{
        \"checks\": [
          {
            \"correlation_id\": \"check-1\",
            \"tuple_key\": {
              \"user\": \"user:user-0000-00042\",
              \"relation\": \"can_read\",
              \"object\": \"s3_bucket:bucket-0000-00001\"
            },
            \"authorization_model_id\": \"$MODEL_ID\"
          },
          {
            \"correlation_id\": \"check-2\",
            \"tuple_key\": {
              \"user\": \"user:user-0000-00042\",
              \"relation\": \"can_write\",
              \"object\": \"s3_bucket:bucket-0000-00001\"
            },
            \"authorization_model_id\": \"$MODEL_ID\"
          }
        ]
      }")

    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    BATCH_TIME=$(($(date +%s) - BATCH_START))

    if [ "$HTTP_CODE" = "200" ] && echo "$BODY" | jq -e '.result | keys | length == 2' > /dev/null 2>&1; then
        log_success "  ✓ Batch check: 2 checks completed (${BATCH_TIME}s)"
        report "### Test 4: Batch Check ✅"
        report "- Checks: 2"
        report "- Time: ${BATCH_TIME}s"
        ((PASSED_TESTS++))
    else
        log_error "  ✗ Batch check failed"
        report "### Test 4: Batch Check ❌"
        report "- Error: $BODY"
        ((FAILED_TESTS++))
    fi
    ((TOTAL_TESTS++))
    report ""

    MODEL_TIME=$(($(date +%s) - MODEL_START))
    report "**Total model test time**: ${MODEL_TIME}s"
    report ""
    report "---"
    report ""
}

# Main test execution
main() {
    echo ""
    echo "======================================"
    echo "Multi-Model Integration Test Suite"
    echo "======================================"
    echo ""

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

    # Initialize report
    init_report

    # Create test store
    log_info "Creating test store..."
    STORE_RESPONSE=$(curl -s -X POST "$OPENFGA_URL/stores" \
      -H "Content-Type: application/json" \
      -d "{\"name\": \"fgabattle-test-$SCALE-$(date +%s)\"}")

    STORE_ID=$(echo "$STORE_RESPONSE" | jq -r '.id')
    log_success "Created store: $STORE_ID"

    # Upload model
    log_info "Uploading authorization model..."

    # Note: This requires JSON format model
    if [ ! -f "models/aws-iam-style.json" ]; then
        log_error "JSON model file not found: models/aws-iam-style.json"
        log_info "The FGA DSL (.fga) files need to be converted to JSON format"
        log_info "Or use the FGA CLI to upload the model"

        # Cleanup and exit
        curl -s -X DELETE "$OPENFGA_URL/stores/$STORE_ID" > /dev/null
        exit 1
    fi

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

    # For large datasets, load in batches
    if [ "$SCALE" = "large" ] || [ "$SCALE" = "huge" ]; then
        log_info "Large dataset detected - loading in batches..."

        # Split into 10K tuple batches
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

    # Run tests
    echo ""
    test_model "AWS IAM Style" "$STORE_ID" "$MODEL_ID"

    # Cleanup
    log_info "Cleaning up test store..."
    curl -s -X DELETE "$OPENFGA_URL/stores/$STORE_ID" > /dev/null
    log_success "Test store deleted"

    # Generate summary
    TOTAL_TIME=$(($(date +%s) - START_TIME))

    report "## Summary"
    report ""
    report "| Metric | Value |"
    report "|--------|-------|"
    report "| Total Tests | $TOTAL_TESTS |"
    report "| Passed | $PASSED_TESTS |"
    report "| Failed | $FAILED_TESTS |"
    report "| Success Rate | $(echo "scale=2; $PASSED_TESTS * 100 / $TOTAL_TESTS" | bc)% |"
    report "| Total Time | ${TOTAL_TIME}s |"
    report ""

    if [ $FAILED_TESTS -eq 0 ]; then
        report "✅ **All tests passed!**"
    else
        report "❌ **Some tests failed**"
    fi

    # Console summary
    echo ""
    echo "======================================"
    echo "Test Summary"
    echo "======================================"
    echo "Total tests: $TOTAL_TESTS"
    echo -e "${GREEN}Passed: $PASSED_TESTS${NC}"
    echo -e "${RED}Failed: $FAILED_TESTS${NC}"
    echo "Total time: ${TOTAL_TIME}s"
    echo ""
    echo "Report saved to: $REPORT_FILE"
    echo ""

    if [ $FAILED_TESTS -eq 0 ]; then
        log_success "All tests passed!"
        exit 0
    else
        log_error "Some tests failed"
        exit 1
    fi
}

# Run main
main
