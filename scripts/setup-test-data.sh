#!/bin/bash
#
# Setup Test Data for FGABattle
#
# This script generates tuple datasets at different scales for testing OpenFGA.
# Run this script once before running tests to create the necessary test data.
#

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

cd "$PROJECT_ROOT"

echo "======================================"
echo "FGABattle Test Data Setup"
echo "======================================"
echo ""

# Check if Python 3 is available
if ! command -v python3 &> /dev/null; then
    echo "Error: python3 is required but not found"
    exit 1
fi

# Create scale directories
echo "Creating directories..."
mkdir -p tuples/aws-iam-style/scale
mkdir -p tuples/document-simple/scale

# Generate AWS IAM style tuples at different scales
echo ""
echo "Generating AWS IAM-style tuples..."
echo "This may take a few minutes for larger datasets."
echo ""

echo "[1/4] Generating mini scale (~350 tuples)..."
python3 scripts/generate-aws-iam-tuples.py mini

echo ""
echo "[2/4] Generating mid scale (~16K tuples)..."
python3 scripts/generate-aws-iam-tuples.py mid

echo ""
echo "[3/4] Generating large scale (~533K tuples)..."
python3 scripts/generate-aws-iam-tuples.py large

echo ""
echo "[4/4] Generating huge scale (~507K tuples)..."
python3 scripts/generate-aws-iam-tuples.py huge

echo ""
echo "======================================"
echo "Setup Complete!"
echo "======================================"
echo ""
echo "Generated datasets:"
ls -lh tuples/aws-iam-style/scale/
echo ""
echo "You can now run tests using these datasets."
echo "See SCALE_TESTING.md for usage examples."
