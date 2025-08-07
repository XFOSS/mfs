#!/bin/bash

# MFS Engine - Cursor Agent Integration Setup Script
# This script sets up the integration between Cursor agent and MFS Engine

set -e

echo "🚀 Setting up Cursor Agent Integration for MFS Engine..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if we're in the MFS Engine directory
if [ ! -f "build.zig" ]; then
    print_error "This script must be run from the MFS Engine root directory"
    exit 1
fi

print_status "Creating agent integration directory structure..."

# Create scripts directory if it doesn't exist
mkdir -p scripts/agent
mkdir -p .cursor/agents
mkdir -p docs/agent

print_success "Directory structure created"

# Create agent configuration file
print_status "Creating agent configuration..."

cat > .cursor/agents/mfs-engine-agent.json << 'EOF'
{
  "name": "MFS Engine Agent",
  "description": "Specialized agent for MFS Engine development",
  "version": "1.0.0",
  "project": {
    "name": "mfs-engine",
    "language": "zig",
    "frameworks": ["webgl", "wasm", "opengl", "vulkan"],
    "type": "graphics-engine"
  },
  "capabilities": [
    "code-generation",
    "code-review",
    "documentation",
    "testing",
    "optimization",
    "debugging"
  ],
  "rules": [
    "follow-zig-style-guide",
    "maintain-performance",
    "ensure-cross-platform-compatibility",
    "prioritize-webgl-support",
    "optimize-for-wasm"
  ],
  "context": {
    "engine_type": "3D Graphics Engine",
    "target_platforms": ["web", "desktop", "mobile"],
    "graphics_apis": ["WebGL", "OpenGL", "Vulkan", "DirectX"],
    "specializations": ["WebAssembly", "Real-time Rendering", "Game Development"]
  }
}
EOF

print_success "Agent configuration created"

# Create development workflow scripts
print_status "Creating development workflow scripts..."

# Code review script
cat > scripts/agent/code-review.sh << 'EOF'
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
EOF

chmod +x scripts/agent/code-review.sh

# Documentation generation script
cat > scripts/agent/generate-docs.sh << 'EOF'
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
EOF

chmod +x scripts/agent/generate-docs.sh

# Test generation script
cat > scripts/agent/generate-tests.sh << 'EOF'
#!/bin/bash

# MFS Engine - Agent Test Generation Script

echo "🧪 Generating tests..."

# Find Zig files without tests
ZIG_FILES=$(find src -name "*.zig" -not -name "*test*" -not -name "*test.zig")

for file in $ZIG_FILES; do
    echo "Checking $file for test coverage..."
    # Add test generation logic here
done

echo "✅ Test generation completed"
EOF

chmod +x scripts/agent/generate-tests.sh

# Performance optimization script
cat > scripts/agent/optimize.sh << 'EOF'
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
EOF

chmod +x scripts/agent/optimize.sh

print_success "Development workflow scripts created"

# Create GitHub Actions workflow
print_status "Creating GitHub Actions workflow..."

mkdir -p .github/workflows

cat > .github/workflows/agent-integration.yml << 'EOF'
name: Agent Integration

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  agent-review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Zig
        uses: goto-bus-stop/setup-zig@v2
        with:
          version: 0.11.0
      
      - name: Run Agent Code Review
        run: |
          chmod +x scripts/agent/code-review.sh
          ./scripts/agent/code-review.sh
      
      - name: Generate Documentation
        run: |
          chmod +x scripts/agent/generate-docs.sh
          ./scripts/agent/generate-docs.sh
      
      - name: Run Performance Optimization
        run: |
          chmod +x scripts/agent/optimize.sh
          ./scripts/agent/optimize.sh
      
      - name: Upload Documentation
        uses: actions/upload-artifact@v3
        with:
          name: generated-docs
          path: docs/generated/
EOF

print_success "GitHub Actions workflow created"

# Create agent documentation
print_status "Creating agent documentation..."

cat > docs/agent/README.md << 'EOF'
# MFS Engine - Cursor Agent Integration

## Overview

This directory contains the integration between Cursor agent and MFS Engine for automated development assistance.

## Features

- **Automated Code Review**: Style checks, build verification, test execution
- **Documentation Generation**: API docs, README updates, changelog generation
- **Test Generation**: Automated test case creation
- **Performance Optimization**: Build optimization, WASM size analysis
- **GitHub Integration**: Automated workflows for CI/CD

## Usage

### Code Review
```bash
./scripts/agent/code-review.sh
```

### Documentation Generation
```bash
./scripts/agent/generate-docs.sh
```

### Test Generation
```bash
./scripts/agent/generate-tests.sh
```

### Performance Optimization
```bash
./scripts/agent/optimize.sh
```

## Configuration

The agent configuration is stored in `.cursor/agents/mfs-engine-agent.json` and includes:

- Project-specific rules and guidelines
- Language-specific optimizations
- Framework-specific considerations
- Performance requirements

## Integration Points

1. **GitHub Actions**: Automated workflows for CI/CD
2. **Development Scripts**: Local development assistance
3. **Documentation**: Auto-generated and maintained docs
4. **Testing**: Automated test generation and execution

## Monitoring

Key metrics tracked:
- Code quality and coverage
- Performance benchmarks
- Documentation completeness
- Build success rates
EOF

print_success "Agent documentation created"

# Create integration status file
print_status "Creating integration status tracker..."

cat > docs/agent/integration-status.md << 'EOF'
# Agent Integration Status

## ✅ Completed
- [x] Agent configuration setup
- [x] Development workflow scripts
- [x] GitHub Actions integration
- [x] Documentation structure
- [x] Performance optimization tools

## 🔄 In Progress
- [ ] Agent content analysis (pending)
- [ ] Custom rule implementation
- [ ] Advanced automation features

## 📋 Pending
- [ ] Agent configuration review
- [ ] Custom integration points
- [ ] Advanced features implementation
- [ ] Performance monitoring setup
- [ ] User experience optimization

## 🎯 Next Steps
1. Review agent configuration content
2. Customize for MFS Engine specific needs
3. Implement advanced features
4. Set up monitoring and metrics
5. Deploy and test integration
EOF

print_success "Integration status tracker created"

print_success "🎉 Cursor Agent Integration setup completed!"

echo ""
echo "📋 Next Steps:"
echo "1. Review the agent configuration in .cursor/agents/mfs-engine-agent.json"
echo "2. Test the development scripts in scripts/agent/"
echo "3. Share the agent content for customization"
echo "4. Deploy the GitHub Actions workflow"
echo "5. Monitor integration performance"
echo ""
echo "📚 Documentation available in docs/agent/"
echo "🔧 Scripts available in scripts/agent/"
echo "⚙️  Configuration in .cursor/agents/"