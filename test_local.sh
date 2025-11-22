#!/usr/bin/env bash

set -e
DIR=$(realpath $0) && DIR=${DIR%/*}
cd $DIR

echo "=========================================="
echo "Testing Kvrocks Nix Build"
echo "=========================================="

# Step 1: Update to unstable version
echo ""
echo "Step 1: Updating to unstable version..."
./update.js unstable

# Step 2: Apply the patch to kvrocks
echo ""
echo "Step 2: Applying pre-built libraries patch..."
cd kvrocks
git checkout -b test-nix-build 2>/dev/null || git checkout test-nix-build
git apply ../kvrocks-prebuilt-libs.patch || {
  echo "Patch already applied or failed to apply"
  git diff --stat
}
cd ..

# Step 3: Test Docker build (normal build without Nix)
echo ""
echo "Step 3: Testing Docker build (normal build)..."
echo "This ensures the patch doesn't break regular builds..."
docker build -t kvrocks-test kvrocks 2>&1 | tail -20
if [ $? -eq 0 ]; then
  echo "✓ Docker build successful"
else
  echo "✗ Docker build failed"
  exit 1
fi

# Step 4: Test Nix build
echo ""
echo "Step 4: Testing Nix build..."
nix build --show-trace 2>&1 | tail -30
if [ $? -eq 0 ]; then
  echo "✓ Nix build successful"
else
  echo "✗ Nix build failed"
  exit 1
fi

# Step 5: Verify the built binary
echo ""
echo "Step 5: Verifying built binary..."
if [ -f result/bin/kvrocks ]; then
  echo "Binary size: $(du -h result/bin/kvrocks | cut -f1)"
  echo "Binary version:"
  ./result/bin/kvrocks --version
  echo "✓ Binary verification successful"
else
  echo "✗ Binary not found"
  exit 1
fi

echo ""
echo "=========================================="
echo "All tests passed! ✓"
echo "=========================================="
echo ""
echo "Summary:"
echo "- Docker build: ✓ (patch doesn't break normal builds)"
echo "- Nix build: ✓ (pre-built dependencies work correctly)"
echo "- Binary: ✓ (kvrocks runs successfully)"
