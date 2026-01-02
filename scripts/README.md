# Scripts

Helper scripts for FGABattle testing and data generation.

## Available Scripts

### setup-test-data.sh

Generates all test tuple datasets at different scales.

**Usage**:
```bash
./scripts/setup-test-data.sh
```

**What it does**:
- Creates scale directories
- Generates mini, mid, large, and huge datasets
- Provides summary of generated files

**When to run**:
- First time setup
- After pulling fresh code
- When you need to regenerate test data

### generate-aws-iam-tuples.py

Python script to generate AWS IAM-style tuple datasets.

**Usage**:
```bash
python3 scripts/generate-aws-iam-tuples.py <scale>
```

**Scales**:
- `mini` - ~350 tuples (49 KB)
- `mid` - ~16K tuples (2.2 MB)
- `large` - ~533K tuples (74 MB)
- `huge` - ~507K tuples (71 MB)

**Custom configuration**:
Edit the `scale_config` dictionary in the script to create custom scales.

## Why Generate Instead of Commit?

Large tuple files (>100MB) are not committed to Git to:
- Keep repository size small
- Speed up cloning
- Avoid GitHub file size limits
- Allow custom scale generation

All datasets can be regenerated quickly using the provided scripts.
