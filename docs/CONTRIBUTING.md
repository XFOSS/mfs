# Contributing to MFS Engine

Thank you for your interest in contributing to MFS Engine! This document outlines the process and guidelines for contributing to the project.

## Code of Conduct

By participating in this project, you agree to abide by our Code of Conduct, which expects all participants to be respectful, inclusive, and considerate towards others.

## Getting Started

1. Fork the repository on GitHub
2. Clone your fork to your local machine
3. Set up the development environment
4. Create a new branch for your changes

## Development Environment

To set up the development environment:

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/mfs.git
cd mfs

# Build the project
zig build

# Run tests to ensure everything works
zig build test
```

## Making Changes

1. **Create a feature branch**:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Follow the coding style**:
   - Use `zig fmt` to format your code
   - Follow the existing patterns in the codebase
   - Keep functions small and focused
   - Write clear comments for complex logic

3. **Add tests**:
   - Add tests for new features
   - Ensure all tests pass with `zig build test`

4. **Commit your changes**:
   ```bash
   git commit -m "Clear, descriptive commit message"
   ```

## Pull Request Process

1. Update your fork to the latest upstream master
   ```bash
   git remote add upstream https://github.com/ORIGINAL_OWNER/mfs.git
   git fetch upstream
   git rebase upstream/master
   ```

2. Push your changes to your fork
   ```bash
   git push origin feature/your-feature-name
   ```

3. Open a Pull Request (PR) on GitHub
   - Provide a clear description of the changes
   - Link any related issues
   - Fill out the PR template if provided

4. Address feedback from maintainers
   - Make requested changes
   - Squash commits if asked
   - Rebase if necessary

5. Once approved, your PR will be merged

## Coding Standards

- **Follow Zig idioms**: Write code that is idiomatic to Zig
- **Error handling**: All errors should be properly handled
- **Memory management**: Be mindful of allocations and ensure proper cleanup
- **Documentation**: Document public APIs and complex functionality
- **Performance**: Consider performance implications of your code

## Testing

- **Unit tests**: Write tests for individual functions and components
- **Integration tests**: Ensure components work together correctly
- **Performance tests**: For performance-sensitive code, include benchmarks

## Documentation

- Update documentation when changing functionality
- Document new features
- Improve existing documentation where needed

## Issue Reporting

When reporting issues:

1. Check if the issue already exists
2. Use the issue template if provided
3. Include:
   - Steps to reproduce
   - Expected behavior
   - Actual behavior
   - Environment details (OS, Zig version, etc.)
   - Screenshots or logs if relevant

## Feature Requests

When requesting features:

1. Clearly describe the feature and its benefits
2. Explain use cases
3. Consider implementation complexity and compatibility

## License

By contributing to MFS Engine, you agree that your contributions will be licensed under the project's MIT license.

## Questions?

If you have questions or need help, feel free to:

- Open an issue with the "question" tag
- Contact the maintainers
- Ask in the community chat or forum

Thank you for contributing to MFS Engine!