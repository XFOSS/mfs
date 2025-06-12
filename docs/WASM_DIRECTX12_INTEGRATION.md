# WASM and DirectX 12 Integration Guide

## Overview

This document describes the integration of WebAssembly (WASM) support with DirectX 12 as the primary graphics backend on Windows, along with OpenGL fallback support. The MFS Engine now supports multi-platform deployment including web browsers through WebAssembly.

## Architecture Changes

### Platform Priority Matrix

| Platform | Primary Backend | Fallback 1 | Fallback 2 | Notes |
|----------|----------------|------------|------------|--------|
| Windows | DirectX 12 | OpenGL | DirectX 11 | Vulkan disabled due to linking issues |
| macOS | Metal | Vulkan | OpenGL | Native Metal preferred |
| iOS | Metal | OpenGL ES | - | Mobile-optimized |
| Linux Desktop | Vulkan | OpenGL | - | Standard Linux support |
| Android | Vulkan | OpenGL ES | - | Modern Android devices |
| Web (WASM) | WebGPU | OpenGL ES | - | Browser-based rendering |

### Key Changes

1. **DirectX 12 Primary on Windows**: Replaced Vulkan as primary backend due to linking reliability issues
2. **WASM Support**: Complete WebAssembly compilation target with Emscripten
3. **WebGPU Backend**: New graphics backend for modern web browsers
4. **OpenGL ES Web**: Fallback support for older browsers
5. **Improved Build System**: Enhanced build.zig with web target support

## DirectX 12 Implementation

### Features

- **Modern D3D12 API**: Full DirectX 12 implementation with command lists and descriptor heaps
- **Multi-frame Buffering**: Triple buffering for optimal performance
- **Debug Layer Support**: Automatic debug layer enabling in debug builds
- **Efficient Resource Management**: Proper descriptor heap management and GPU synchronization
- **Hardware Acceleration**: Full GPU acceleration with compute shader support

### Technical Details

```zig
// D3D12 Backend Configuration
const FRAME_COUNT = 3;  // Triple buffering
const D3D12_COMMAND_LIST_TYPE_DIRECT = 0;
const D3D12_DESCRIPTOR_HEAP_TYPE_RTV = 0;
const D3D12_DESCRIPTOR_HEAP_TYPE_DSV = 1;
const D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV = 2;
```

### Capabilities

- **Raytracing**: Hardware-accelerated ray tracing support
- **Mesh Shaders**: Modern geometry pipeline
- **Variable Rate Shading**: Performance optimization features
- **Compute Shaders**: GPU compute capability
- **Multiple Render Targets**: Up to 8 simultaneous render targets

## WebAssembly Implementation

### Build Configuration

The build system now supports WASM compilation:

```bash
# Build for web
zig build web

# Standard native build
zig build

# DirectX 12 specific build (Windows)
zig build -Dd3d12=true -Dvulkan=false
```

### Web Target Features

1. **WebGPU Backend**: Modern web graphics API
2. **OpenGL ES Fallback**: Compatibility with older browsers
3. **Emscripten Integration**: C/JavaScript bridge for browser APIs
4. **Canvas Integration**: Direct HTML5 Canvas rendering
5. **Input Handling**: Mouse, keyboard, and touch input support

### Emscripten Configuration

```c
// Key Emscripten flags
-sUSE_WEBGL2=1          // WebGL 2.0 support
-sUSE_GLFW=3            // GLFW for window management
-sFULL_ES3=1            // Full OpenGL ES 3.0
-sASYNCIFY              // Asynchronous operation support
-sEXPORTED_FUNCTIONS    // Exported C functions for JS
```

## WebGPU Backend

### Implementation Highlights

- **Modern Web Graphics**: WebGPU API bindings for high-performance web rendering
- **Shader Compilation**: WGSL shader support
- **Command Buffer Management**: Efficient command recording and submission
- **Resource Management**: Textures, buffers, and pipeline state objects
- **Debug Support**: WebGPU validation layer integration

### WebGPU Features

```zig
// WebGPU Context Configuration
attrs.majorVersion = 2;
attrs.minorVersion = 0;
attrs.powerPreference = EM_WEBGL_POWER_PREFERENCE_HIGH_PERFORMANCE;
attrs.antialias = EM_TRUE;
attrs.depth = EM_TRUE;
```

## Build System Enhancements

### New Build Options

```zig
// Platform detection improvements
const is_web = is_wasm;
const is_desktop = is_windows or is_macos or (is_linux and !is_android);

// Backend availability
if (is_windows) {
    d3d12_available = enable_d3d12;      // Primary
    opengl_available = enable_opengl;    // Fallback
    vulkan_available = false;            // Disabled
} else if (is_web) {
    webgpu_available = enable_webgpu;    // Primary
    opengles_available = enable_opengles; // Fallback
}
```

### Web Deployment

```bash
# Complete web build process
zig build web
# Generates:
# - mfs-web.wasm    (WebAssembly module)
# - mfs-web.js      (Emscripten glue code)
# - index.html      (Demo page)
```

## Performance Considerations

### DirectX 12 Optimizations

1. **Command List Reuse**: Efficient command buffer recycling
2. **Descriptor Heap Management**: Optimized descriptor allocation
3. **GPU Timeline**: Proper CPU/GPU synchronization
4. **Memory Management**: Efficient resource creation and destruction

### WebAssembly Optimizations

1. **Size Optimization**: Minimal WASM binary size through selective features
2. **Memory Management**: Efficient heap usage within browser constraints
3. **Async Operations**: Non-blocking rendering loop
4. **Asset Streaming**: Progressive loading of resources

## API Usage Examples

### DirectX 12 Initialization

```zig
// Create D3D12 backend
var backend = try D3D12Backend.init(allocator);

// Create swap chain
const swap_chain = try backend.createSwapChain(.{
    .width = 1920,
    .height = 1080,
    .format = .rgba8_unorm_srgb,
    .buffer_count = 3,
    .vsync = true,
    .window_handle = window_handle,
});
```

### WebGPU Usage

```zig
// Create WebGPU backend
var backend = try WebGPUBackend.init(allocator);

// Initialize for web
try backend.initializeAsync();

// Create swap chain for canvas
const swap_chain = try backend.createSwapChain(.{
    .width = canvas_width,
    .height = canvas_height,
    .format = .bgra8_unorm_srgb,
    .buffer_count = 2,
    .vsync = true,
    .window_handle = 0, // Not used for web
});
```

## Deployment Guide

### Windows Deployment

1. **DirectX 12 Runtime**: Ensure Windows 10/11 with D3D12 support
2. **Graphics Drivers**: Updated GPU drivers required
3. **Visual C++ Redistributable**: Runtime dependencies included

### Web Deployment

1. **HTTPS Required**: WebGPU requires secure context
2. **Modern Browser**: Chrome 94+, Firefox 97+, Safari 16+
3. **WebAssembly Support**: All modern browsers supported
4. **Canvas Element**: HTML5 Canvas with WebGL context

### Hosting Requirements

```html
<!-- Required headers for WASM -->
Cross-Origin-Embedder-Policy: require-corp
Cross-Origin-Opener-Policy: same-origin

<!-- MIME type for .wasm files -->
application/wasm
```

## Debug and Development

### DirectX 12 Debugging

- **Debug Layer**: Automatically enabled in debug builds
- **PIX Integration**: Support for Microsoft PIX debugging
- **GPU Validation**: Enhanced debugging with GPU-based validation

### WebAssembly Debugging

- **Browser DevTools**: Console logging and performance profiling
- **Source Maps**: Debug information for WASM debugging
- **Memory Profiling**: Heap usage monitoring

## Migration Notes

### From Vulkan to DirectX 12

1. **Command Buffer Differences**: D3D12 command lists vs Vulkan command buffers
2. **Resource States**: Explicit resource state management
3. **Descriptor Management**: Descriptor heaps vs descriptor sets
4. **Synchronization**: Fences and events vs semaphores

### Platform-Specific Considerations

- **Windows**: DirectX 12 provides better driver stability than Vulkan
- **Web**: WebGPU offers more features than WebGL but requires modern browsers
- **Mobile**: OpenGL ES remains the most compatible option

## Future Enhancements

### Planned Features

1. **DirectX 12 Ultimate**: Advanced features like mesh shaders and raytracing
2. **WebGPU Compute**: Compute shader support for web
3. **Progressive Web App**: Full PWA support with offline capabilities
4. **WebXR Integration**: Virtual and augmented reality support

### Performance Roadmap

1. **GPU Memory Management**: Advanced allocation strategies
2. **Command Buffer Optimization**: Better batching and submission
3. **Asset Pipeline**: Optimized resource loading and caching
4. **Multi-threading**: Improved parallelization across platforms

## Troubleshooting

### Common Issues

1. **DirectX 12 Not Available**: Fallback to OpenGL automatic
2. **WebGPU Not Supported**: Automatic fallback to OpenGL ES
3. **WASM Loading Failures**: Check HTTPS and CORS headers
4. **Performance Issues**: Monitor browser console for WebGL warnings

### Debugging Commands

```bash
# Verify backend availability
zig build check-capabilities

# Test specific backend
zig build test-d3d12
zig build test-webgpu

# Web development server
zig build web && python -m http.server 8080
```

This integration provides a robust, multi-platform graphics engine with optimal performance on each target platform while maintaining a unified API across all backends.