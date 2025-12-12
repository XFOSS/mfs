# MFS Engine - Agent Integration Guide

## Build/Test Commands
- `zig build` - Debug build
- `zig build -Doptimize=ReleaseFast` - Release build
- `zig build test` - Run all tests
- `zig test src/tests/test_math.zig` - Run single test file
- `zig run scripts/run_tests.zig --filter "Math"` - Run filtered tests
- `zig run scripts/run_tests.zig --verbose` - Verbose test output
- `zig run scripts/code_quality_check.zig` - Code quality analysis
- `.\scripts\run_all_checks.ps1` - Comprehensive checks (Windows)

## Code Style Guidelines
- **Files**: snake_case (`ray_tracing.zig`)
- **Types/Structs**: PascalCase (`RenderContext`)
- **Functions/Variables**: camelCase (`createWindow`, `maxVertexCount`)
- **Constants**: ALL_CAPS (`GRAVITY`, `MAX_VELOCITY`)
- **Error Handling**: Use error unions, avoid `catch unreachable`
- **Memory**: Pass allocators explicitly, use `defer`/`errdefer` for cleanup
- **Documentation**: `//!` doc comments for public APIs with `@thread-safe`, `@platform` tags
- **Imports**: Group std lib, external deps, internal imports
- **Testing**: Descriptive test names, good coverage
- **Formatting**: 4-space indentation, consistent spacing

## Commit Standards
- Format: `type(scope): description`
- Types: feat, fix, docs, style, refactor, perf, test, build
- Examples: `feat(graphics): add Vulkan ray tracing`, `fix(physics): correct collision detection`</content>
<parameter name="filePath">C:\Users\donald\mfs\AGENTS.md