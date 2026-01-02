# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Quick Start for New Users

1. **Clone and setup**:
```bash
git clone <repo-url>
cd fgabattle
./scripts/setup-test-data.sh  # Generate test data
```

2. **Start OpenFGA**:
```bash
cd docker/openfga
docker-compose up -d
```

3. **Run tests** (see SCALE_TESTING.md for details)

## Project Overview

FGABattle is a comprehensive testing suite for OpenFGA (https://openfga.dev/) and compatible implementations. The project includes:
- Authorization model examples and tuple data covering various use cases
- Integration tests using the FGA CLI
- Performance/load tests written in K6
- Docker Compose configurations for local deployments

## Project Structure

```
fgabattle/
├── models/           # OpenFGA authorization models (.fga files)
├── tuples/           # Test data tuples organized by model
├── tests/
│   ├── cli/         # FGA CLI integration tests
│   └── k6/          # K6 load tests
├── docker/          # Docker Compose configurations
└── scripts/         # Helper scripts for setup and testing
```

## Key Commands

### Environment Setup
```bash
# Start OpenFGA server locally
docker-compose up -d

# Stop services
docker-compose down

# View logs
docker-compose logs -f openfga
```

### FGA CLI Operations
```bash
# Create a store
fga store create --name="test-store"

# Write an authorization model
fga model write --file=models/<model-name>.fga

# Write tuples
fga tuple write --file=tuples/<model-name>/tuples.json

# Test authorization check
fga query check --user=<user> --relation=<relation> --object=<object>

# List objects
fga query list-objects --type=<type> --relation=<relation> --user=<user>
```

### Running Tests
```bash
# Run all CLI integration tests
./scripts/run-cli-tests.sh

# Run K6 load tests for check operations
k6 run tests/k6/check-load-test.js

# Run K6 load tests for list-objects operations
k6 run tests/k6/list-objects-load-test.js

# Run K6 load tests for write operations
k6 run tests/k6/write-load-test.js

# Run all K6 tests and generate report
./scripts/run-k6-tests.sh
```

## Authorization Model Design

### Model Organization
- Each `.fga` file in `models/` represents a distinct use case or pattern
- Models should cover:
  - Basic hierarchical relationships (organizations, teams, users)
  - Document-based permissions (viewer, editor, owner)
  - Complex inheritance patterns
  - Conditional relationships
  - Union and intersection semantics
  - Public access patterns
  - Contextual relationships (time-based, location-based)

### Tuple Organization
- Tuples in `tuples/<model-name>/` correspond to their authorization model
- Include both:
  - Baseline data for integration testing
  - Large datasets for load testing
- Use JSON format compatible with `fga tuple write`

## K6 Load Testing Architecture

### Test Structure
Each K6 test should:
1. Import the OpenFGA client/SDK
2. Set up test data (store ID, model ID, tuples)
3. Define scenarios with different load profiles
4. Implement test functions for specific operations
5. Configure thresholds for performance requirements
6. Export metrics for reporting

### Operations to Test
- **check**: Authorization checks with various user-object-relation combinations
- **list-objects**: Listing objects accessible by users
- **write**: Writing tuples (relationship data)

### Test Scenarios
- Steady-state load
- Ramp-up/ramp-down
- Spike testing
- Stress testing

### Metrics to Collect
- Request duration (p95, p99)
- Requests per second
- Error rates
- Database query performance

## Docker Compose Configuration

### Services
- **openfga**: Main OpenFGA server
- **postgres**: Database backend for OpenFGA
- (Optional) Additional compatible implementations for comparison testing

### Ports
- OpenFGA HTTP: 8080
- OpenFGA gRPC: 8081
- Postgres: 5432

## Compatibility Testing Strategy

When testing multiple OpenFGA-compatible implementations:
1. Define the same authorization model across implementations
2. Write identical tuple data
3. Run the same test queries (check, list-objects)
4. Compare results for consistency
5. Run load tests to compare performance characteristics
6. Document any behavioral differences or incompatibilities

## Test Report Generation

Reports should include:
- Implementation version being tested
- Model complexity metrics (types, relations, depth)
- Functional test results (pass/fail for each scenario)
- Performance metrics from K6 tests
- Comparison tables when testing multiple implementations

## Development Workflow

1. Design authorization model in `models/`
2. Create corresponding test tuples in `tuples/`
3. Write CLI integration tests to verify correctness
4. Develop K6 load tests for performance benchmarking
5. Document results and update compatibility matrix
6. Iterate on models to cover additional edge cases
