#!/bin/bash

# MFS Engine - Agent Code Review Script

echo "🔍 Running agent code review..."

# Check for Zig files
ZIG_FILES=$(find . -name "*.zig" -not -path "./build/*" -not -path "./zig-cache/*")

if [ -z "$ZIG_FILES" ]; then
    echo "No Zig files found to review"
    exit 0
fi

echo "Found $(echo "$ZIG_FILES" | wc -l) Zig files to review"

# Run basic checks
echo "Running style checks..."
zig fmt --check $ZIG_FILES

echo "Running build checks..."
zig build

echo "Running test checks..."
zig build test

echo "✅ Code review completed"
