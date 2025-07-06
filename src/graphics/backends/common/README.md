# Graphics Backend Common Modules

This directory contains common utilities and base implementations that can be shared across different graphics backends. The goal is to reduce code duplication and make it easier to maintain multiple backend implementations.

## Module Overview

- `common.zig` - Main module that re-exports all common functionality
- `backend_base.zig` - Base implementation for graphics backends with common functionality
- `errors.zig` - Common error handling and reporting utilities
- `memory.zig` - Memory management utilities for graphics resources
- `profiling.zig` - Performance profiling and metrics tracking
- `resources.zig` - Resource management and tracking utilities
- `shader_utils.zig` - Shader compilation, reflection, and management utilities
- `test.zig` - Testing utilities for backend implementations

## Usage

Backend implementations should import the common module and use its functionality to reduce code duplication:

```zig
const common = @import("common/common.zig");

pub const MyBackend = struct {
    base: common.BackendBase,
    // Backend-specific fields...
    
    pub fn init(allocator: std.mem.Allocator) !MyBackend {
        return MyBackend{
            .base = try common.BackendBase.init(allocator, debug_mode),
            // Initialize backend-specific fields...
        };
    }
    
    pub fn deinit(self: *MyBackend) void {
        self.base.deinit();
        // Clean up backend-specific resources...
    }
    
    // Implement backend-specific methods...
};
```

## Refactoring Approach

The refactoring approach extracts common functionality from existing backend implementations into shared modules. This includes:

1. **Error handling** - Common error types, context, and logging
2. **Memory management** - Allocation strategies, memory blocks, and pools
3. **Resource tracking** - Registration and lookup of graphics resources
4. **Profiling** - Performance metrics and markers
5. **Shader utilities** - Common shader operations across backends

Each backend implementation can now focus on the platform-specific code while reusing common functionality.

## Benefits

- **Reduced code duplication** - Common functionality is defined once and reused
- **Easier maintenance** - Changes to common code only need to be made in one place
- **Consistent behavior** - All backends use the same implementation for common operations
- **Simplified testing** - Common functionality can be tested independently
- **Easier to add new backends** - New implementations can reuse existing common code

## Future Improvements

- Add more common utilities for pipeline management
- Implement shared command buffer abstraction
- Create common texture and buffer format conversion utilities
- Add more comprehensive testing utilities
