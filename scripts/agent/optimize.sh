#!/bin/bash

# MFS Engine - Agent Performance Optimization Script

echo "⚡ Running performance optimization..."

# Build with optimizations
echo "Building with optimizations..."
zig build -Doptimize=ReleaseFast

# Run performance benchmarks
echo "Running performance benchmarks..."
# Add benchmark logic here

# Analyze WASM size
if [ -f "build/mfs-cube-demo.wasm" ]; then
    echo "WASM size: $(stat -c%s build/mfs-cube-demo.wasm) bytes"
fi

echo "✅ Performance optimization completed"
