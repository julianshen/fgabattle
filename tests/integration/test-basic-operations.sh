#!/bin/bash
#
# Basic OpenFGA Operations Test Suite
#
# Tests check, list-objects, write, and batch operations using the HTTP API
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
API_BASE="${OPENFGA_URL:-http://localhost:8080}"
STORE_ID="${STORE_ID}"
MODEL_ID="${MODEL_ID}"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Helper functions
log_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++))
    ((TESTS_RUN++))
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++))
    ((TESTS_RUN++))
}

# Check if required variables are set
if [ -z "$STORE_ID" ] || [ -z "$MODEL_ID" ]; then
    echo "Error: STORE_ID and MODEL_ID environment variables are required"
    echo "Usage: STORE_ID=<store-id> MODEL_ID=<model-id> $0"
    exit 1
fi

log_info "Testing against: $API_BASE"
log_info "Store ID: $STORE_ID"
log_info "Model ID: $MODEL_ID"
echo ""

#
# Test 1: Check Operation - Simple Authorization Check
#
log_info "Test 1: Check operation - user can read S3 bucket"
RESPONSE=$(curl -s -X POST "$API_BASE/stores/$STORE_ID/check" \
  -H "Content-Type: application/json" \
  -d "{
    \"tuple_key\": {
      \"user\": \"user:user-0000-00042\",
      \"relation\": \"can_read\",
      \"object\": \"s3_bucket:bucket-0000-00005\"
    },
    \"authorization_model_id\": \"$MODEL_ID\"
  }")

if echo "$RESPONSE" | jq -e '.allowed != null' > /dev/null 2>&1; then
    ALLOWED=$(echo "$RESPONSE" | jq -r '.allowed')
    log_success "Check returned: allowed=$ALLOWED"
else
    log_error "Check failed: $RESPONSE"
fi

#
# Test 2: Check Operation - Deny Case
#
log_info "Test 2: Check operation - verify denial"
RESPONSE=$(curl -s -X POST "$API_BASE/stores/$STORE_ID/check" \
  -H "Content-Type: application/json" \
  -d "{
    \"tuple_key\": {
      \"user\": \"user:nonexistent-user\",
      \"relation\": \"can_delete\",
      \"object\": \"s3_bucket:bucket-0000-00005\"
    },
    \"authorization_model_id\": \"$MODEL_ID\"
  }")

if echo "$RESPONSE" | jq -e '.allowed == false' > /dev/null 2>&1; then
    log_success "Check correctly denied access"
else
    log_error "Check should have denied access: $RESPONSE"
fi

#
# Test 3: List Objects - Find accessible S3 buckets
#
log_info "Test 3: List objects - find accessible S3 buckets"
RESPONSE=$(curl -s -X POST "$API_BASE/stores/$STORE_ID/list-objects" \
  -H "Content-Type: application/json" \
  -d "{
    \"authorization_model_id\": \"$MODEL_ID\",
    \"type\": \"s3_bucket\",
    \"relation\": \"can_read\",
    \"user\": \"user:user-0000-00042\"
  }")

if echo "$RESPONSE" | jq -e '.objects' > /dev/null 2>&1; then
    OBJECT_COUNT=$(echo "$RESPONSE" | jq '.objects | length')
    log_success "List-objects returned $OBJECT_COUNT objects"
else
    log_error "List-objects failed: $RESPONSE"
fi

#
# Test 4: List Objects - Group member access
#
log_info "Test 4: List objects - group member accessing EC2 instances"
RESPONSE=$(curl -s -X POST "$API_BASE/stores/$STORE_ID/list-objects" \
  -H "Content-Type: application/json" \
  -d "{
    \"authorization_model_id\": \"$MODEL_ID\",
    \"type\": \"ec2_instance\",
    \"relation\": \"can_describe\",
    \"user\": \"group:group-0000-000#member\"
  }")

if echo "$RESPONSE" | jq -e '.objects' > /dev/null 2>&1; then
    OBJECT_COUNT=$(echo "$RESPONSE" | jq '.objects | length')
    log_success "Group member can access $OBJECT_COUNT EC2 instances"
else
    log_error "List-objects for group member failed: $RESPONSE"
fi

#
# Test 5: Write Operation - Add new tuple
#
log_info "Test 5: Write operation - add test tuple"
TEST_USER="user:integration-test-user-$$"
TEST_BUCKET="s3_bucket:test-bucket-$$"

RESPONSE=$(curl -s -X POST "$API_BASE/stores/$STORE_ID/write" \
  -H "Content-Type: application/json" \
  -d "{
    \"writes\": {
      \"tuple_keys\": [
        {
          \"user\": \"$TEST_USER\",
          \"relation\": \"identity_based_read\",
          \"object\": \"$TEST_BUCKET\"
        }
      ]
    }
  }")

if [ $? -eq 0 ]; then
    log_success "Write succeeded"

    # Verify the write
    log_info "Test 5b: Verify written tuple"
    RESPONSE=$(curl -s -X POST "$API_BASE/stores/$STORE_ID/check" \
      -H "Content-Type: application/json" \
      -d "{
        \"tuple_key\": {
          \"user\": \"$TEST_USER\",
          \"relation\": \"can_read\",
          \"object\": \"$TEST_BUCKET\"
        },
        \"authorization_model_id\": \"$MODEL_ID\"
      }")

    if echo "$RESPONSE" | jq -e '.allowed == true' > /dev/null 2>&1; then
        log_success "Verified: Written tuple is accessible"
    else
        log_error "Verification failed: $RESPONSE"
    fi
else
    log_error "Write failed: $RESPONSE"
fi

#
# Test 6: Write Operation - Batch write
#
log_info "Test 6: Write operation - batch write multiple tuples"
RESPONSE=$(curl -s -X POST "$API_BASE/stores/$STORE_ID/write" \
  -H "Content-Type: application/json" \
  -d "{
    \"writes\": {
      \"tuple_keys\": [
        {
          \"user\": \"$TEST_USER\",
          \"relation\": \"identity_based_write\",
          \"object\": \"$TEST_BUCKET\"
        },
        {
          \"user\": \"$TEST_USER\",
          \"relation\": \"identity_based_invoke\",
          \"object\": \"lambda_function:test-function-$$\"
        }
      ]
    }
  }")

if [ $? -eq 0 ]; then
    log_success "Batch write succeeded (2 tuples)"
else
    log_error "Batch write failed: $RESPONSE"
fi

#
# Test 7: Batch Check Operation
#
log_info "Test 7: Batch check operation"
RESPONSE=$(curl -s -X POST "$API_BASE/stores/$STORE_ID/batch-check" \
  -H "Content-Type: application/json" \
  -d "{
    \"checks\": [
      {
        \"correlation_id\": \"check-1\",
        \"tuple_key\": {
          \"user\": \"$TEST_USER\",
          \"relation\": \"can_read\",
          \"object\": \"$TEST_BUCKET\"
        },
        \"authorization_model_id\": \"$MODEL_ID\"
      },
      {
        \"correlation_id\": \"check-2\",
        \"tuple_key\": {
          \"user\": \"$TEST_USER\",
          \"relation\": \"can_write\",
          \"object\": \"$TEST_BUCKET\"
        },
        \"authorization_model_id\": \"$MODEL_ID\"
      }
    ]
  }")

if echo "$RESPONSE" | jq -e '.result | keys | length == 2' > /dev/null 2>&1; then
    RESULT=$(echo "$RESPONSE" | jq -c '.result')
    log_success "Batch check returned 2 results: $RESULT"
else
    log_error "Batch check failed: $RESPONSE"
fi

#
# Test 8: Cleanup - Delete test tuples
#
log_info "Test 8: Cleanup - delete test tuples"
RESPONSE=$(curl -s -X POST "$API_BASE/stores/$STORE_ID/write" \
  -H "Content-Type: application/json" \
  -d "{
    \"deletes\": {
      \"tuple_keys\": [
        {
          \"user\": \"$TEST_USER\",
          \"relation\": \"identity_based_read\",
          \"object\": \"$TEST_BUCKET\"
        },
        {
          \"user\": \"$TEST_USER\",
          \"relation\": \"identity_based_write\",
          \"object\": \"$TEST_BUCKET\"
        },
        {
          \"user\": \"$TEST_USER\",
          \"relation\": \"identity_based_invoke\",
          \"object\": \"lambda_function:test-function-$$\"
        }
      ]
    }
  }")

if [ $? -eq 0 ]; then
    log_success "Cleanup succeeded"
else
    log_error "Cleanup failed: $RESPONSE"
fi

#
# Summary
#
echo ""
echo "======================================"
echo "Test Summary"
echo "======================================"
echo "Total tests run: $TESTS_RUN"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed${NC}"
    exit 1
fi
