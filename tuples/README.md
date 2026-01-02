# Test Tuples

This directory contains tuple data for testing OpenFGA authorization models.

## Generating Test Data

**Important**: Tuple files are not committed to Git to keep repository size small.

To generate test data, run:

```bash
# Generate all scale datasets
./scripts/setup-test-data.sh

# Or generate specific scales
python3 scripts/generate-aws-iam-tuples.py mini    # ~350 tuples
python3 scripts/generate-aws-iam-tuples.py mid     # ~16K tuples
python3 scripts/generate-aws-iam-tuples.py large   # ~533K tuples
python3 scripts/generate-aws-iam-tuples.py huge    # ~507K tuples
```

## Directory Structure

```
tuples/
├── aws-iam-style/
│   ├── scale/
│   │   ├── mini-tuples.json      (generated)
│   │   ├── mid-tuples.json       (generated)
│   │   ├── large-tuples.json     (generated)
│   │   └── huge-tuples.json      (generated)
│   └── tuples.json               (small example, committed)
├── document-simple/
│   ├── scale/                     (generated datasets)
│   └── tuples.json               (small example, committed)
├── space-page-hierarchy/
│   └── tuples.json               (small example, committed)
├── team-based/
│   └── tuples.json               (small example, committed)
├── github-style/
│   └── tuples.json               (small example, committed)
└── folder-hierarchy/
    └── tuples.json               (small example, committed)
```

## Scale Datasets

The scale datasets are generated dynamically and provide different sizes for performance testing:

| Scale | Tuples | File Size | Purpose |
|-------|--------|-----------|---------|
| Mini  | ~350   | ~49 KB    | Quick tests, CI/CD |
| Mid   | ~16K   | ~2.2 MB   | Integration tests |
| Large | ~533K  | ~74 MB    | Production-like |
| Huge  | ~507K  | ~71 MB    | Load testing |

See [SCALE_TESTING.md](../SCALE_TESTING.md) for detailed usage.

## Example Tuples

Small example tuple files (in each model directory) are committed to Git for quick testing and demonstrations. These contain 5-10 tuples each and show the basic structure of relationships for each model.
