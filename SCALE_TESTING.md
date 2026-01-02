# Scale Testing Guide

This guide explains how to perform scale testing with OpenFGA using the generated tuple datasets at different scales.

## Quick Start

**First time setup**: Generate test data before running tests:

```bash
# Run the setup script to generate all datasets
./scripts/setup-test-data.sh
```

This will create tuple files in `tuples/aws-iam-style/scale/` at four different scales.

## Dataset Scales

We provide four different scale datasets for comprehensive performance testing:

| Scale | Tuple Count | File Size | Use Case |
|-------|-------------|-----------|----------|
| **Mini** | ~348 | 49 KB | Quick testing, development, CI/CD |
| **Mid** | ~15,665 | 2.2 MB | Integration testing, staging environments |
| **Large** | ~533,320 | 74 MB | Production-like testing, performance baselines |
| **Huge** | ~506,920 | 71 MB | Load testing, 500K+ tuple scale validation |

> **Note**: All datasets are sized to fit within GitHub's file size limits. For extreme scale testing (1M+ tuples), regenerate locally using the generation script with custom parameters.

## Dataset Composition (AWS IAM Style)

Each dataset contains a realistic distribution of AWS IAM relationships:

### Mini Scale (348 tuples)
- 2 Accounts
- 10 Users per account
- 3 Groups per account
- 5 Roles per account
- 10 S3 Buckets per account
- 8 EC2 Instances per account
- 5 DynamoDB Tables per account
- 7 Lambda Functions per account

### Mid Scale (15,665 tuples)
- 5 Accounts
- 100 Users per account
- 20 Groups per account
- 30 Roles per account
- 50 S3 Buckets per account
- 40 EC2 Instances per account
- 30 DynamoDB Tables per account
- 25 Lambda Functions per account

### Large Scale (533,320 tuples)
- 10 Accounts
- 500 Users per account
- 100 Groups per account
- 200 Roles per account
- 200 S3 Buckets per account
- 150 EC2 Instances per account
- 100 DynamoDB Tables per account
- 100 Lambda Functions per account

### Huge Scale (506,920 tuples)
- 8 Accounts
- 600 Users per account
- 100 Groups per account
- 200 Roles per account
- 200 S3 Buckets per account
- 150 EC2 Instances per account
- 100 DynamoDB Tables per account
- 100 Lambda Functions per account

## Generating Custom Datasets

To generate datasets at different scales:

```bash
# Generate Mini scale
python3 scripts/generate-aws-iam-tuples.py mini

# Generate Mid scale
python3 scripts/generate-aws-iam-tuples.py mid

# Generate Large scale
python3 scripts/generate-aws-iam-tuples.py large

# Generate Huge scale
python3 scripts/generate-aws-iam-tuples.py huge
```

## Loading Data into OpenFGA

### 1. Create a Store

```bash
STORE_RESPONSE=$(curl -s -X POST http://localhost:8080/stores \
  -H "Content-Type: application/json" \
  -d '{"name": "scale-test"}')

STORE_ID=$(echo $STORE_RESPONSE | jq -r '.id')
echo "Store ID: $STORE_ID"
```

### 2. Upload Authorization Model

First, you need to convert the .fga model to JSON or use the FGA CLI:

```bash
# Using curl (requires JSON model)
curl -X POST "http://localhost:8080/stores/$STORE_ID/authorization-models" \
  -H "Content-Type: application/json" \
  -d @models/aws-iam-style.json

# Or using FGA CLI
fga model write --store-id=$STORE_ID --file=models/aws-iam-style.fga
```

Save the model ID:
```bash
MODEL_ID="<your-model-id>"
```

### 3. Load Tuples

#### Mini/Mid Scale (Fast)
```bash
# Load mini dataset (~348 tuples)
curl -X POST "http://localhost:8080/stores/$STORE_ID/write" \
  -H "Content-Type: application/json" \
  -d @tuples/aws-iam-style/scale/mini-tuples.json

# Load mid dataset (~15K tuples)
curl -X POST "http://localhost:8080/stores/$STORE_ID/write" \
  -H "Content-Type: application/json" \
  -d @tuples/aws-iam-style/scale/mid-tuples.json
```

#### Large Scale (Batch Loading Recommended)
For large datasets, use batch loading to avoid timeouts:

```bash
# Split large file into batches
jq -c '.writes.tuple_keys | _nwise(1000) | {writes: {tuple_keys: .}}' \
  tuples/aws-iam-style/scale/large-tuples.json > /tmp/large-batches.jsonl

# Load in batches
while IFS= read -r batch; do
  curl -s -X POST "http://localhost:8080/stores/$STORE_ID/write" \
    -H "Content-Type: application/json" \
    -d "$batch" > /dev/null
  echo "Batch loaded..."
done < /tmp/large-batches.jsonl
```

#### Huge Scale (Batch Loading)
For the huge dataset (500K+ tuples), use batch loading for better performance:

```bash
# Option 1: Use jq to split into 10K tuple batches
jq -c '.writes.tuple_keys | _nwise(10000) | {writes: {tuple_keys: .}}' \
  tuples/aws-iam-style/scale/huge-tuples.json | \
  while IFS= read -r batch; do
    curl -s -X POST "http://localhost:8080/stores/$STORE_ID/write" \
      -H "Content-Type: application/json" \
      -d "$batch" > /dev/null
    echo "10K tuples loaded..."
  done

# Option 2: Create a Python batch loader
# (See scripts/batch-load-tuples.py)
```

## Performance Testing Scenarios

### Test 1: Authorization Check Latency

Test how long authorization checks take with different dataset sizes:

```bash
# Test user accessing S3 bucket
time curl -s -X POST "http://localhost:8080/stores/$STORE_ID/check" \
  -H "Content-Type: application/json" \
  -d '{
    "tuple_key": {
      "user": "user:user-0000-00042",
      "relation": "can_read",
      "object": "s3_bucket:bucket-0000-00005"
    },
    "authorization_model_id": "'$MODEL_ID'"
  }' | jq .
```

**Expected Metrics**:
- Mini: < 10ms
- Mid: < 50ms
- Large: < 100ms
- Huge: < 200ms (depending on index optimization)

### Test 2: List Objects Performance

Test how long it takes to list accessible objects:

```bash
# List all S3 buckets a user can read
time curl -s -X POST "http://localhost:8080/stores/$STORE_ID/list-objects" \
  -H "Content-Type: application/json" \
  -d '{
    "authorization_model_id": "'$MODEL_ID'",
    "type": "s3_bucket",
    "relation": "can_read",
    "user": "user:user-0000-00042"
  }' | jq .
```

**Expected Metrics**:
- Mini: < 50ms, ~10 objects
- Mid: < 200ms, ~50 objects
- Large: < 500ms, ~200 objects
- Huge: < 1000ms, ~500 objects

### Test 3: Hierarchical Permission Resolution

Test group membership and role assumption:

```bash
# Test group member accessing resource
time curl -s -X POST "http://localhost:8080/stores/$STORE_ID/check" \
  -H "Content-Type: application/json" \
  -d '{
    "tuple_key": {
      "user": "user:user-0001-00123",
      "relation": "can_describe",
      "object": "ec2_instance:instance-0001-00042"
    },
    "authorization_model_id": "'$MODEL_ID'"
  }' | jq .
```

### Test 4: Write Performance

Test how long it takes to write new tuples:

```bash
# Write a single tuple
time curl -s -X POST "http://localhost:8080/stores/$STORE_ID/write" \
  -H "Content-Type: application/json" \
  -d '{
    "writes": {
      "tuple_keys": [{
        "user": "user:test-user",
        "relation": "identity_based_read",
        "object": "s3_bucket:test-bucket"
      }]
    }
  }' | jq .

# Write batch of tuples (100)
# ... generate batch JSON ...
```

## K6 Load Testing

Create K6 tests for sustained load:

```javascript
import http from 'k6/http';
import { check } from 'k6';

export let options = {
  stages: [
    { duration: '30s', target: 10 },  // Ramp up
    { duration: '1m', target: 50 },   // Sustained load
    { duration: '30s', target: 0 },   // Ramp down
  ],
};

const STORE_ID = __ENV.STORE_ID;
const MODEL_ID = __ENV.MODEL_ID;

export default function() {
  const userId = Math.floor(Math.random() * 2000);
  const bucketId = Math.floor(Math.random() * 500);

  const payload = JSON.stringify({
    tuple_key: {
      user: `user:user-0000-${userId.toString().padStart(5, '0')}`,
      relation: 'can_read',
      object: `s3_bucket:bucket-0000-${bucketId.toString().padStart(5, '0')}`
    },
    authorization_model_id: MODEL_ID
  });

  const res = http.post(
    `http://localhost:8080/stores/${STORE_ID}/check`,
    payload,
    { headers: { 'Content-Type': 'application/json' } }
  );

  check(res, {
    'status is 200': (r) => r.status === 200,
    'response time < 200ms': (r) => r.timings.duration < 200,
  });
}
```

Run the K6 test:
```bash
STORE_ID=<your-store-id> MODEL_ID=<your-model-id> k6 run tests/k6/check-load-test.js
```

## Performance Benchmarks

Expected performance characteristics with default PostgreSQL backend:

### Authorization Checks (p95 latency)
| Scale | Check Latency | Notes |
|-------|---------------|-------|
| Mini | < 10ms | All data in memory |
| Mid | < 50ms | Most lookups indexed |
| Large | < 150ms | Some disk I/O |
| Huge | < 300ms | Significant disk I/O, consider tuning |

### List Objects (p95 latency)
| Scale | List Latency | Max Results |
|-------|--------------|-------------|
| Mini | < 100ms | ~10 objects |
| Mid | < 500ms | ~50 objects |
| Large | < 2s | ~200 objects |
| Huge | < 5s | ~500 objects |

### Database Size
| Scale | Tuples | Approx DB Size |
|-------|--------|----------------|
| Mini | 348 | ~50 KB |
| Mid | 15,665 | ~5 MB |
| Large | 533,320 | ~150 MB |
| Huge | 506,920 | ~140 MB |

### Custom Extreme Scale Testing

For testing beyond the included datasets (1M+ tuples), modify the generation script:

```python
# In scripts/generate-aws-iam-tuples.py, add custom scale:
"extreme": {
    "accounts": 20,
    "users_per_account": 2000,
    "groups_per_account": 500,
    "roles_per_account": 1000,
    # ... adjust as needed
}
```

Then generate locally (will create multi-GB files):
```bash
python3 scripts/generate-aws-iam-tuples.py extreme
```

**Note**: Datasets over 100MB are not committed to Git to keep repository size manageable.

## Optimization Tips

### For Large/Huge Datasets:

1. **Database Tuning**:
   ```sql
   -- Increase shared buffers
   ALTER SYSTEM SET shared_buffers = '4GB';

   -- Increase work memory
   ALTER SYSTEM SET work_mem = '256MB';

   -- Enable parallel queries
   ALTER SYSTEM SET max_parallel_workers_per_gather = 4;
   ```

2. **OpenFGA Configuration**:
   ```yaml
   datastore:
     maxOpenConns: 100
     maxIdleConns: 25

   checkCache:
     limit: 100000

   checkIteratorCache:
     enabled: true
     maxResults: 10000
   ```

3. **Indexing**:
   - Ensure proper indexes on tuple table
   - Monitor slow query log
   - Consider partitioning for huge datasets

4. **Horizontal Scaling**:
   - Use read replicas for check/list-objects
   - Consider sharding by account ID
   - Use connection pooling (pgBouncer)

## Monitoring

Key metrics to track:

1. **Request Latency**:
   - p50, p95, p99 for check/list-objects/write
2. **Throughput**:
   - Requests per second
3. **Database Metrics**:
   - Connection pool usage
   - Query latency
   - Cache hit ratio
4. **Resource Usage**:
   - CPU utilization
   - Memory usage
   - Disk I/O

## Cleanup

To delete test data:

```bash
# Delete the store (removes all data)
curl -X DELETE "http://localhost:8080/stores/$STORE_ID"
```

## Next Steps

1. Run performance tests at each scale
2. Document actual latencies in your environment
3. Identify bottlenecks and optimize
4. Compare different OpenFGA implementations
5. Test with different database backends (MySQL, SQLite)
6. Implement caching strategies
7. Test horizontal scaling configurations
