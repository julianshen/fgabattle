# FGABattle Tests

Comprehensive test suite for OpenFGA operations including integration tests and load tests.

## Quick Start

```bash
# Run all integration tests
./scripts/run-all-tests.sh

# Run with load tests
RUN_LOAD_TESTS=true ./scripts/run-all-tests.sh
```

## Test Types

### Integration Tests

Shell-based tests using curl to verify basic OpenFGA operations.

**Location**: `tests/integration/`

**What's tested**:
- ✅ Check operation (authorization checks)
- ✅ List-objects operation
- ✅ Write operation (single and batch)
- ✅ Batch check operation
- ✅ Delete operation (cleanup)

**Run individually**:
```bash
# Setup first
STORE_ID=<id> MODEL_ID=<id> ./tests/integration/test-basic-operations.sh
```

### K6 Load Tests

Performance and load testing using K6.

**Location**: `tests/k6/`

**Available tests**:

#### 1. Check Load Test (`check-load-test.js`)
Tests authorization check performance under load.

**Usage**:
```bash
STORE_ID=<id> MODEL_ID=<id> k6 run tests/k6/check-load-test.js
```

**Load profile**:
- Ramp: 10 → 50 → 100 users
- Duration: 3 minutes
- Target: p95 < 200ms, p99 < 500ms

#### 2. List-Objects Load Test (`list-objects-load-test.js`)
Tests list-objects performance (heavier operation).

**Usage**:
```bash
STORE_ID=<id> MODEL_ID=<id> k6 run tests/k6/list-objects-load-test.js
```

**Load profile**:
- Ramp: 5 → 20 → 50 users
- Duration: 3 minutes
- Target: p95 < 2s, p99 < 5s

#### 3. Write Load Test (`write-load-test.js`)
Tests write performance with optional cleanup.

**Usage**:
```bash
STORE_ID=<id> MODEL_ID=<id> CLEANUP=true k6 run tests/k6/write-load-test.js
```

**Load profile**:
- Ramp: 5 → 10 → 20 users
- Duration: 2.5 minutes
- Target: p95 < 500ms, p99 < 1s

**Environment variables**:
- `CLEANUP=true` - Delete tuples after writing (recommended)

#### 4. Batch Check Load Test (`batch-check-load-test.js`)
Tests batch check performance.

**Usage**:
```bash
STORE_ID=<id> MODEL_ID=<id> k6 run tests/k6/batch-check-load-test.js
```

**Load profile**:
- Ramp: 5 → 15 → 30 users
- Duration: 3 minutes
- Batch size: 2-10 checks per request
- Target: p95 < 1s, p99 < 2s

## Environment Variables

All tests support these environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `OPENFGA_URL` | `http://localhost:8080` | OpenFGA API endpoint |
| `STORE_ID` | *required* | OpenFGA store ID |
| `MODEL_ID` | *required* | Authorization model ID |
| `CLEANUP` | `false` | Delete test data after write tests |
| `MAX_BATCH_SIZE` | `10` | Maximum batch size for batch tests |

## Prerequisites

### For Integration Tests
```bash
brew install jq  # JSON processor
```

### For Load Tests
```bash
brew install k6  # Load testing tool
```

### OpenFGA Running
```bash
cd docker/openfga
docker-compose up -d
```

### Test Data Generated
```bash
./scripts/setup-test-data.sh
```

## Test Workflow

### 1. One-Time Setup
```bash
# Start OpenFGA
cd docker/openfga && docker-compose up -d

# Generate test data
./scripts/setup-test-data.sh

# Install dependencies
brew install jq k6
```

### 2. Create Test Store
```bash
# Create store
STORE_RESPONSE=$(curl -s -X POST http://localhost:8080/stores \
  -H "Content-Type: application/json" \
  -d '{"name": "test-store"}')

STORE_ID=$(echo $STORE_RESPONSE | jq -r '.id')

# Upload model (requires JSON format)
# ... upload model and get MODEL_ID ...
```

### 3. Load Test Data
```bash
# Load mini dataset for quick tests
curl -X POST "http://localhost:8080/stores/$STORE_ID/write" \
  -H "Content-Type: application/json" \
  -d @tuples/aws-iam-style/scale/mini-tuples.json
```

### 4. Run Tests
```bash
# Integration tests
STORE_ID=$STORE_ID MODEL_ID=$MODEL_ID \
  ./tests/integration/test-basic-operations.sh

# Load tests
STORE_ID=$STORE_ID MODEL_ID=$MODEL_ID \
  k6 run tests/k6/check-load-test.js
```

## Test Scenarios

### Scenario 1: Quick Smoke Test
```bash
# Just integration tests, no load
./scripts/run-all-tests.sh
```

### Scenario 2: Full Test Suite
```bash
# Integration + load tests
RUN_LOAD_TESTS=true ./scripts/run-all-tests.sh
```

### Scenario 3: Individual Load Test
```bash
# Test specific operation at scale
STORE_ID=$STORE_ID MODEL_ID=$MODEL_ID \
  k6 run --vus 100 --duration 5m \
  tests/k6/check-load-test.js
```

### Scenario 4: Custom Load Profile
```bash
# Override K6 options
STORE_ID=$STORE_ID MODEL_ID=$MODEL_ID \
  k6 run \
  --stage 1m:50 \
  --stage 5m:100 \
  --stage 1m:0 \
  tests/k6/batch-check-load-test.js
```

## Interpreting Results

### K6 Metrics

**Key metrics to watch**:
- `http_req_duration`: Request latency (p95, p99)
- `http_req_failed`: Failed request rate
- `check_errors`: Test assertion failures
- `iterations`: Total requests completed

**Example output**:
```
checks.........................: 100.00% ✓ 5234      ✗ 0
http_req_duration..............: avg=45ms  p(95)=120ms p(99)=250ms
http_req_failed................: 0.00%   ✓ 0         ✗ 5234
iterations.....................: 5234    87/s
```

### Integration Test Output

```
[PASS] Check returned: allowed=true
[PASS] List-objects returned 10 objects
[PASS] Write succeeded
====================================
Total tests run: 8
Passed: 8
Failed: 0
```

## Troubleshooting

### OpenFGA Not Running
```bash
cd docker/openfga
docker-compose up -d
curl http://localhost:8080/healthz
```

### Store/Model Not Found
```bash
# List stores
curl http://localhost:8080/stores | jq .

# Check model
curl http://localhost:8080/stores/$STORE_ID/authorization-models
```

### Test Data Missing
```bash
./scripts/setup-test-data.sh
```

### K6 Thresholds Failing
- Reduce load (fewer VUs or shorter duration)
- Check OpenFGA logs: `docker-compose logs openfga`
- Increase database resources
- Enable caching in OpenFGA config

## CI/CD Integration

### GitHub Actions Example
```yaml
name: Test
on: [push]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Start OpenFGA
        run: cd docker/openfga && docker-compose up -d
      - name: Generate test data
        run: ./scripts/setup-test-data.sh
      - name: Run tests
        run: ./scripts/run-all-tests.sh
```

## Performance Baselines

Expected performance with mini dataset (~350 tuples):

| Operation | p95 | p99 | Notes |
|-----------|-----|-----|-------|
| Check | < 50ms | < 100ms | Single authorization check |
| List-objects | < 200ms | < 500ms | ~10 objects returned |
| Write | < 100ms | < 200ms | Single tuple write |
| Batch check | < 500ms | < 1s | 5-10 checks per batch |

Performance degrades with larger datasets - see SCALE_TESTING.md for details.
