#!/bin/bash
set -euo pipefail

# macOS Build Wrapper Script
# Fixes bindgen time_t header issue by setting BINDGEN_EXTRA_CLANG_ARGS
# before cargo runs. This is necessary because libclang (used by bindgen)
# doesn't read environment variables like C_INCLUDE_PATH or CFLAGS.

# Get macOS SDK path
SDKROOT=$(xcrun --show-sdk-path)

# Export for bindgen - this MUST be set before cargo runs
# -isysroot: Tells clang where the SDK is
# -I$SDKROOT/usr/include: Adds system headers directory (where time.h is)
export BINDGEN_EXTRA_CLANG_ARGS="-isysroot $SDKROOT -I$SDKROOT/usr/include"

# Also set for any code that uses clang-sys directly
export LIBCLANG_PATH="/Library/Developer/CommandLineTools/usr/lib"
export CLANG_PATH="/Library/Developer/CommandLineTools/usr/bin/clang"

echo "🔧 macOS Build Environment:"
echo "  SDKROOT: $SDKROOT"
echo "  BINDGEN_EXTRA_CLANG_ARGS: $BINDGEN_EXTRA_CLANG_ARGS"
echo ""

# Run cargo with all args passed to script
cargo "$@"
