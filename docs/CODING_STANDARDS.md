# MFS Engine - Coding Standards and Style Guide

## Overview

This document defines the coding standards and best practices for the MFS Engine codebase. Following these guidelines ensures consistency, maintainability, and quality across all modules.

## Zig Language Standards

### 1. Naming Conventions

#### Files
- Use `snake_case` for file names: `ray_tracing.zig`, `asset_manager.zig`
- Module index files should be named `mod.zig`
- Test files should end with `_test.zig` or be in a `tests/` directory

#### Types and Structs
```zig
// ✅ Good - PascalCase for types
const RenderContext = struct { ... };
const GraphicsBackend = enum { ... };

// ❌ Bad
const render_context = struct { ... };
const GRAPHICS_BACKEND = enum { ... };
```

#### Functions and Variables
```zig
// ✅ Good - camelCase for functions and variables
pub fn createWindow(config: WindowConfig) !Window { ... }
const maxVertexCount = 65536;

// ❌ Bad
pub fn CreateWindow(config: WindowConfig) !Window { ... }
const MAX_VERTEX_COUNT = 65536;
```

#### Constants
```zig
// ✅ Good - Use const with descriptive names
const default_window_width = 1280;
const max_texture_size = 4096;

// For compile-time constants that act like enums
const VK_SUCCESS = 0;
const GL_TEXTURE_2D = 0x0DE1;
```

### 2. Error Handling

#### Always Prefer Error Unions
```zig
// ✅ Good - Return error unions
pub fn loadTexture(path: []const u8) !Texture {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    // ...
}

// ❌ Bad - Using catch unreachable
pub fn loadTexture(path: []const u8) Texture {
    const file = std.fs.cwd().openFile(path, .{}) catch unreachable;
    defer file.close();
    // ...
}
```

#### Error Logging
```zig
// ✅ Good - Log errors with context
allocator.alloc(u8, size) catch |err| {
    std.log.err("Failed to allocate {} bytes: {}", .{ size, err });
    return error.OutOfMemory;
};

// ❌ Bad - Silent failure
allocator.alloc(u8, size) catch return null;
```

### 3. Memory Management

#### Always Use Allocators Explicitly
```zig
// ✅ Good - Pass allocator explicitly
pub fn init(allocator: std.mem.Allocator, config: Config) !Self {
    return Self{
        .allocator = allocator,
        .buffer = try allocator.alloc(u8, config.buffer_size),
    };
}

// ❌ Bad - Hidden allocation
var global_buffer: [1024]u8 = undefined;
```

#### Cleanup Resources
```zig
// ✅ Good - Proper cleanup with errdefer
pub fn createPipeline(allocator: std.mem.Allocator) !Pipeline {
    const shaders = try allocator.alloc(Shader, 2);
    errdefer allocator.free(shaders);
    
    const pipeline = try allocator.create(Pipeline);
    errdefer allocator.destroy(pipeline);
    
    // Initialize...
    return pipeline;
}
```

### 4. Documentation

#### Module Documentation
```zig
//! Graphics Backend Interface
//! 
//! This module provides a unified interface for different graphics APIs
//! including Vulkan, DirectX 12, Metal, and OpenGL.
//!
//! ## Example
//! ```zig
//! const backend = try GraphicsBackend.init(allocator, .vulkan);
//! defer backend.deinit();
//! ```

const std = @import("std");
```

#### Function Documentation
```zig
/// Creates a new render pass with the specified configuration.
/// 
/// Parameters:
///   - config: Render pass configuration including attachments and dependencies
/// 
/// Returns:
///   - RenderPass on success
///   - Error.InvalidConfig if configuration is invalid
///   - Error.OutOfMemory if allocation fails
/// 
/// Example:
/// ```zig
/// const pass = try createRenderPass(.{
///     .color_attachment = .{ .format = .rgba8_unorm },
///     .depth_attachment = .{ .format = .d32_float },
/// });
/// ```
pub fn createRenderPass(config: RenderPassConfig) !RenderPass {
    // Implementation
}
```

### 5. Code Organization

#### Module Structure
```
src/graphics/
├── mod.zig              # Module interface
├── types.zig            # Common types
├── buffer.zig           # Buffer management
├── texture.zig          # Texture management
├── pipeline.zig         # Pipeline management
├── backends/            # Backend implementations
│   ├── mod.zig
│   ├── vulkan/
│   ├── directx/
│   └── opengl/
└── tests/               # Module tests
    ├── buffer_test.zig
    └── texture_test.zig
```

#### Import Organization
```zig
// 1. Standard library imports
const std = @import("std");
const builtin = @import("builtin");

// 2. External dependencies
const vk = @import("vulkan");

// 3. Internal imports (absolute from src/)
const math = @import("math/mod.zig");
const core = @import("core/mod.zig");

// 4. Local imports (relative)
const types = @import("types.zig");
const utils = @import("utils.zig");

// 5. Type aliases
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
```

### 6. Testing

#### Test Organization
```zig
// In the same file for unit tests
test "Buffer.init creates buffer with correct size" {
    const allocator = std.testing.allocator;
    const buffer = try Buffer.init(allocator, 1024);
    defer buffer.deinit();
    
    try std.testing.expect(buffer.size == 1024);
}

// In separate test files for integration tests
// tests/graphics_integration_test.zig
test "Graphics pipeline integration" {
    // Complex integration test
}
```

#### Test Naming
```zig
// ✅ Good - Descriptive test names
test "Matrix4x4.multiply produces correct result for identity matrices" { }
test "TextureLoader.load returns error for missing file" { }

// ❌ Bad - Vague test names  
test "multiply" { }
test "load error" { }
```

### 7. Performance Guidelines

#### Prefer Stack Allocation
```zig
// ✅ Good - Stack allocation for small, fixed-size data
var vertices: [4]Vertex = undefined;

// ❌ Bad - Heap allocation for small, fixed-size data
const vertices = try allocator.alloc(Vertex, 4);
defer allocator.free(vertices);
```

#### Use Appropriate Data Structures
```zig
// ✅ Good - Use ArrayList for dynamic arrays
var vertices = ArrayList(Vertex).init(allocator);

// ✅ Good - Use StaticBitSet for fixed-size bit flags
var flags = std.StaticBitSet(32).initEmpty();

// ✅ Good - Use HashMap for key-value lookups
var texture_cache = std.HashMap(u32, Texture, std.hash_map.AutoContext(u32), 80).init(allocator);
```

### 8. Platform-Specific Code

#### Use Build Options
```zig
const build_options = @import("build_options");

pub fn createWindow() !Window {
    if (build_options.Platform.is_windows) {
        return createWindowsWindow();
    } else if (build_options.Platform.is_linux) {
        return createLinuxWindow();
    } else {
        return error.UnsupportedPlatform;
    }
}
```

#### Compile-Time Platform Checks
```zig
pub fn init() !void {
    if (comptime builtin.os.tag == .windows) {
        // Windows-specific initialization
    } else if (comptime builtin.os.tag == .linux) {
        // Linux-specific initialization
    } else {
        @compileError("Unsupported platform");
    }
}
```

### 9. Concurrency

#### Thread Safety Documentation
```zig
/// TextureCache manages texture resources.
/// 
/// Thread Safety: This struct is NOT thread-safe. 
/// Use external synchronization when accessing from multiple threads.
pub const TextureCache = struct {
    // ...
};

/// ThreadSafeQueue provides a thread-safe FIFO queue.
/// 
/// Thread Safety: All methods are thread-safe and can be called
/// concurrently from multiple threads.
pub const ThreadSafeQueue = struct {
    mutex: std.Thread.Mutex,
    // ...
};
```

### 10. Code Review Checklist

Before submitting code for review, ensure:

- [ ] All public functions have documentation comments
- [ ] Error handling uses proper error unions (no `catch unreachable`)
- [ ] Resources are properly cleaned up (defer/errdefer)
- [ ] Tests are included for new functionality
- [ ] No compiler warnings
- [ ] Code follows naming conventions
- [ ] Complex algorithms have explanatory comments
- [ ] Platform-specific code is properly isolated
- [ ] Performance-critical paths are optimized
- [ ] Thread safety is documented

## Git Commit Standards

### Commit Message Format
```
<type>(<scope>): <subject>

<body>

<footer>
```

### Types
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, etc.)
- `refactor`: Code refactoring
- `perf`: Performance improvements
- `test`: Test additions or modifications
- `build`: Build system changes
- `ci`: CI configuration changes

### Examples
```
feat(graphics): add Vulkan ray tracing support

Implemented hardware-accelerated ray tracing using Vulkan RT extensions.
Includes BLAS/TLAS management and shader binding table generation.

Closes #123
```

```
fix(physics): correct collision detection for rotated boxes

The previous implementation didn't account for object rotation when
calculating SAT projections. This fix properly transforms vertices
before projection.
```

## Conclusion

Following these standards ensures that the MFS Engine codebase remains:
- **Consistent**: Easy to read and understand
- **Maintainable**: Easy to modify and extend
- **Reliable**: Proper error handling and resource management
- **Performant**: Efficient use of resources
- **Portable**: Clean platform abstractions

All contributors should familiarize themselves with these guidelines and apply them consistently throughout the codebase. 