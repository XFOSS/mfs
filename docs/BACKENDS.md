# MFS Engine Rendering Backends

This document provides an overview of the various graphics backends supported by the MFS Engine.

## Supported Backends

MFS Engine supports multiple rendering backends to ensure cross-platform compatibility and leverage platform-specific optimizations:

| Backend | Platforms | Features | Status |
|---------|-----------|----------|--------|
| **Vulkan** | Windows, Linux, Android | High performance, low overhead | Complete |
| **DirectX 12** | Windows 10+ | Modern GPU features, raytracing | Complete |
| **DirectX 11** | Windows 7+ | Wide compatibility | Complete |
| **Metal** | macOS, iOS | Native Apple performance | Beta |
| **OpenGL** | Windows, Linux, macOS | Cross-platform compatibility | Complete |
| **OpenGL ES** | Android, iOS | Mobile support | Beta |
| **WebGPU** | Web browsers | Modern web standard | Alpha |
| **Software** | All platforms | Fallback renderer | Basic |

## Backend Selection

The engine will automatically choose the most performant backend available on the current platform. You can also explicitly select a backend:

```zig
// Using the Config struct
var config = mfs.Config{
    .renderer_backend = .vulkan,
    // other configuration...
};

// Or at runtime
app.setGraphicsBackend(.dx12) catch |err| {
    // Handle error if backend is not available
};
```

## Backend-Specific Features

### Vulkan

The Vulkan backend provides:
- Compute shader support
- Advanced memory management
- Multi-threaded command buffer recording
- Full validation layer integration
- Explicit synchronization control

File location: `src/graphics/backends/vulkan_backend.zig`

### DirectX 12

The DirectX 12 backend provides:
- DirectX Raytracing (DXR) integration
- DirectStorage API support
- Variable Rate Shading (VRS)
- Mesh shaders
- DirectML for hardware accelerated machine learning

File location: `src/graphics/backends/d3d12_backend.zig`

### DirectX 11

The DirectX 11 backend provides:
- Wide compatibility with Windows systems
- Feature level targeting
- Legacy hardware support
- Mature tooling integration

File location: `src/graphics/backends/d3d11_backend.zig`

### Metal

The Metal backend provides:
- Native performance on Apple platforms
- Metal shader language compilation
- Metal Performance Shaders integration
- Dynamic resource management

File location: `src/graphics/backends/metal_backend.zig`

### OpenGL

The OpenGL backend provides:
- Maximum cross-platform compatibility
- Legacy hardware support
- Simpler API for learning and debugging

File location: `src/graphics/backends/opengl_backend.zig`

### WebGPU

The WebGPU backend provides:
- Modern web standard support
- Cross-browser compatibility
- Web worker integration

File location: `src/graphics/backends/webgpu_backend.zig`

## Shader System

MFS uses a unified shader system that compiles to each backend's native format:

1. Write shaders in a high-level shader language (HLSL/GLSL-like syntax)
2. The engine shader compiler converts to backend-specific formats
3. Shader reflection generates appropriate bindings for each backend
4. Hot reloading is supported across all backends

Example shader definition:

```zig
const standard_shader = mfs.shader.define(.{
    .vertex = @embedFile("shaders/standard.vert"),
    .fragment = @embedFile("shaders/standard.frag"),
    .reflection = true, // Enable automatic binding reflection
});
```

## Feature Compatibility

The following table shows feature support across backends:

| Feature | Vulkan | DX12 | DX11 | Metal | OpenGL | WebGPU |
|---------|--------|------|------|-------|--------|--------|
| Compute | ✅ | ✅ | ✅ | ✅ | ✅* | ✅ |
| Raytracing | ✅ | ✅ | ❌ | ✅* | ❌ | ❌ |
| Mesh Shaders | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| VRS | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ |
| Bindless | ✅ | ✅ | ✅* | ✅ | ✅* | ❌ |
| Async Compute | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ |
| HDR Output | ✅ | ✅ | ✅ | ✅ | ✅* | ✅* |
| GPU Timeline | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ |

\* Limited support or extension dependent

## Backend Implementation Details

Each backend implements the core `GraphicsDevice` interface:

```zig
pub const GraphicsDevice = struct {
    // Interface functions implemented by each backend
    initFn: fn (allocator: std.mem.Allocator, options: Options) !*GraphicsDevice,
    deinitFn: fn (self: *GraphicsDevice) void,
    beginFrameFn: fn (self: *GraphicsDevice) !void,
    endFrameFn: fn (self: *GraphicsDevice) !void,
    createBufferFn: fn (self: *GraphicsDevice, desc: BufferDesc) !ResourceHandle,
    createTextureFn: fn (self: *GraphicsDevice, desc: TextureDesc) !ResourceHandle,
    // ... and many more functions
};
```

## Adding Custom Backends

The engine supports adding custom rendering backends by implementing the `GraphicsDevice` interface:

1. Create a new file in `src/graphics/backends/my_backend.zig`
2. Implement the required interface functions
3. Register your backend with the engine

See `src/graphics/backends/template_backend.zig` for a starting point.

## Debugging and Profiling

Each backend includes specialized debugging and profiling capabilities:

- **Vulkan**: Debug markers, validation layers, RenderDoc integration
- **DirectX**: PIX integration, debug layers, GPU-based validation
- **Metal**: Frame capture, shader debugging, Metal System Trace
- **OpenGL**: KHR_debug extension, ARB_debug_output

Use the common API for cross-backend debugging:

```zig
renderer.beginDebugGroup("Shadow pass");
defer renderer.endDebugGroup();
// Rendering operations here
```

## Performance Considerations

Different backends have different performance characteristics:

- **Vulkan/DX12**: Require more explicit management but offer highest performance
- **Metal**: Best performance on Apple platforms
- **DX11**: Good balance of simplicity and performance on Windows
- **OpenGL**: Simpler API with potentially higher driver overhead
- **WebGPU**: Performance constrained by browser environment

## Limitations and Known Issues

- **Feature Availability**: Not all features are available on all backends
- **Extension Support**: Some features rely on optional extensions
- **API Differences**: Subtle differences in behavior may exist between backends
- **WebGPU**: Still evolving, more limited than native backends

## Testing Backend Compatibility

Use the built-in testing system to verify your code works across backends:

```bash
# Test all backends
zig build test

# Test specific backends
zig build test-vulkan
zig build test-d3d12
zig build test-opengl
```