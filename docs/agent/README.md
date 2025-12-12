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
