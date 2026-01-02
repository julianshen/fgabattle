#!/bin/bash

set -e

# Create test store
STORE_RESPONSE=$(curl -s -X POST http://localhost:8080/stores \
  -H "Content-Type: application/json" \
  -d '{"name": "debug-test"}')
STORE_ID=$(echo "$STORE_RESPONSE" | jq -r '.id')
echo "Store ID: $STORE_ID"

# Upload model
MODEL_RESPONSE=$(curl -s -X POST "http://localhost:8080/stores/$STORE_ID/authorization-models" \
  -H "Content-Type: application/json" \
  -d @models/aws-iam-style.json)
MODEL_ID=$(echo "$MODEL_RESPONSE" | jq -r '.authorization_model_id')
echo "Model ID: $MODEL_ID"

# Try batch check
echo ""
echo "Testing batch-check endpoint..."
BATCH_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "http://localhost:8080/stores/$STORE_ID/batch-check" \
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

HTTP_CODE=$(echo "$BATCH_RESPONSE" | tail -n1)
BODY=$(echo "$BATCH_RESPONSE" | sed '$d')
echo "HTTP Code: $HTTP_CODE"
echo "Response:"
echo "$BODY" | jq .

# Check if result field exists
if echo "$BODY" | jq -e '.result' > /dev/null 2>&1; then
    echo "✓ Response has .result field"
    RESULT_LENGTH=$(echo "$BODY" | jq '.result | length')
    echo "Result length: $RESULT_LENGTH"
else
    echo "✗ Response does NOT have .result field"
fi

# Cleanup
curl -s -X DELETE "http://localhost:8080/stores/$STORE_ID" > /dev/null
echo ""
echo "Cleaned up test store"
