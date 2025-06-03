# MFS Graphics System

## Overview

The MFS Graphics System provides a unified API for rendering graphics across multiple backends. It abstracts away the complexity of different graphics APIs (Vulkan, DirectX, Metal, etc.) and provides a simple, consistent interface for application developers.

## Architecture

The graphics system is organized into several layers:

1. **High-level API (`gpu.zig`)**: The main entry point for applications, providing a unified interface to all graphics functionality.
2. **Resource Management**: Specialized modules for managing specific resource types:
   - `texture.zig`: Texture and image handling
   - `shader.zig`: Shader management and compilation
   - `buffer.zig`: Vertex, index, and uniform buffer management
3. **Backend Interface (`interface.zig`)**: Defines common structures and interfaces for all backends
4. **Backend Implementations**:
   - Vulkan
   - Direct3D 11/12
   - Metal
   - OpenGL/OpenGL ES
   - WebGPU
   - Software (fallback)
5. **Backend Manager**: Handles backend selection, initialization, and fallbacks

## Core Modules

### gpu.zig

The main entry point for the graphics system. It provides functions for:
- Initialization and shutdown
- Resource creation (textures, buffers, shaders)
- Render pass management
- Drawing commands
- Backend selection and information

### texture.zig

Provides abstractions for working with textures:
- `Texture2D`: Standard 2D textures
- `RenderTexture`: Textures that can be rendered to
- `TextureArray`: Arrays of textures

### shader.zig

Handles shader management:
- Shader compilation and linking
- Uniform binding
- Shader reflection
- Includes a preprocessor for #include directives and defines

### buffer.zig

Manages GPU buffers:
- `Buffer`: Generic buffer for any purpose
- `VertexBuffer`: Specialized for vertex data
- `IndexBuffer`: Specialized for index data
- `UniformBuffer`: For shader uniform data

## Backend System

The backend system is designed to be extensible and adaptive:

- **Automatic Backend Selection**: The system automatically chooses the best available backend for the current platform
- **Fallback Chain**: If a preferred backend is unavailable or fails, the system falls back to the next best option
- **Runtime Backend Switching**: Backends can be switched at runtime to adapt to different conditions
- **Performance Monitoring**: The system can monitor performance and switch to more appropriate backends as needed

## Getting Started

```zig
const std = @import("std");
const gpu = @import("graphics/gpu.zig");

pub fn main() !void {
    // Initialize with preferred backend
    try gpu.init(std.heap.page_allocator, .{
        .preferred_backend = .vulkan,
        .auto_fallback = true,
    });
    defer gpu.deinit();
    
    // Print backend info
    const info = gpu.getBackendInfo();
    std.debug.print("Using: {s} on {s}\n", .{info.name, info.device_name});
    
    // Create resources, set up rendering, etc.
    // ...
}
```

See `examples/simple_triangle.zig` for a complete example of drawing a basic triangle.

## Contributing

When adding support for a new graphics backend:

1. Create a new file in `backends/` following the naming convention `xxx_backend.zig`
2. Implement the required interface functions from `interface.zig`
3. Add detection code to `backend_manager.zig`

## Future Improvements

- Add compute shader support
- Improve shader reflection capabilities
- Add pipeline state caching
- Support for more texture formats and compression
- More sophisticated resource management with aliasing and pooling