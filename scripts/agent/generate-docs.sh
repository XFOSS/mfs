#!/bin/bash

# MFS Engine - Agent Documentation Generation Script

echo "📚 Generating documentation..."

# Create docs directory if it doesn't exist
mkdir -p docs/generated

# Generate API documentation
echo "Generating API documentation..."
zig build docs

# Generate README updates
echo "Updating README..."
# Add README generation logic here

# Generate changelog
echo "Generating changelog..."
git log --oneline --since="1 week ago" > docs/generated/recent-changes.md

echo "✅ Documentation generated"
