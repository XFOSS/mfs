# MFS Engine - Ray Tracing Documentation

## Overview

The MFS Engine now includes comprehensive ray tracing support across multiple graphics backends, with particular emphasis on Vulkan 1.3 KHR ray tracing and DirectX Ray Tracing (DXR). This implementation follows modern ray tracing best practices and supports hardware-accelerated ray tracing on compatible GPUs.

## Supported Backends

### Vulkan 1.3 Ray Tracing (VK_KHR_ray_tracing)
- **Primary backend** for cross-platform ray tracing
- Supports the latest Vulkan 1.3 ray tracing extensions
- Hardware-accelerated on RTX, RDNA2+, and Intel Arc GPUs
- HLSL to SPIR-V shader compilation via DXC

### DirectX Ray Tracing (DXR)
- **Windows-native** ray tracing implementation
- Supports DXR 1.0 and DXR 1.1 features
- Direct HLSL shader support
- Optimized for Windows gaming and enterprise applications

### Metal Ray Tracing
- **macOS-native** ray tracing implementation
- Supports Metal Performance Shaders ray tracing
- Hardware-accelerated on Apple Silicon and modern AMD GPUs

### Software Fallback
- **CPU-based** ray tracing for compatibility
- Embree-based high-performance software ray tracing
- Automatic fallback when hardware acceleration is unavailable

## Architecture

### Core Components

```zig
// Main ray tracing context
const RayTracingContext = struct {
    allocator: std.mem.Allocator,
    backend_type: BackendType,
    capabilities: RayTracingCapabilities,
    device_handle: *anyopaque,
};

// Acceleration structures
const AccelerationStructure = struct {
    handle: *anyopaque,
    backend_type: BackendType,
    as_type: AccelerationStructureType, // BLAS or TLAS
    size: u64,
    device_address: u64,
};

// Ray tracing pipeline
const RayTracingPipelineState = struct {
    raygen_shader: *anyopaque,
    miss_shaders: []*anyopaque,
    hit_groups: []HitGroup,
    callable_shaders: []*anyopaque,
    max_recursion_depth: u32,
};
```

### Shader Compilation

The engine supports HLSL ray tracing shaders compiled to SPIR-V for Vulkan using Microsoft's DXC compiler:

```bash
# Compile HLSL ray tracing shader to SPIR-V
dxc.exe -T lib_6_4 raytrace.rchit.hlsl -spirv -Fo raytrace.rchit.spv -fvk-use-scalar-layout -fspv-extension="SPV_KHR_ray_tracing"
```

## Usage Examples

### Basic Ray Tracing Setup

```zig
const std = @import("std");
const mfs = @import("mfs");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Initialize engine with ray tracing
    const engine_config = mfs.EngineConfig{
        .graphics = .{
            .preferred_backend = .vulkan,
            .enable_ray_tracing = true,
        },
    };
    
    const engine = try mfs.init(allocator, engine_config);
    defer mfs.deinit(engine);
    
    // Initialize ray tracing
    const rt_config = mfs.graphics.RayTracingConfig{
        .enable_hardware_acceleration = true,
        .max_recursion_depth = 8,
    };
    
    const rt_context = try mfs.graphics.ray_tracing.init(
        allocator,
        rt_config,
        engine.graphics.getDeviceHandle(),
    );
    defer mfs.graphics.ray_tracing.deinit(rt_context);
    
    // Create geometry
    const vertices = [_]Vertex{
        .{ .position = .{ -1, -1, 0 }, .normal = .{ 0, 0, 1 } },
        .{ .position = .{  1, -1, 0 }, .normal = .{ 0, 0, 1 } },
        .{ .position = .{  0,  1, 0 }, .normal = .{ 0, 0, 1 } },
    };
    
    const indices = [_]u32{ 0, 1, 2 };
    
    // Create geometry description
    const geometry_desc = mfs.graphics.GeometryDesc{
        .geometry_type = .triangles,
        .flags = .{ .opaque = true },
        .vertex_buffer = &vertices,
        .vertex_stride = @sizeOf(Vertex),
        .vertex_format = .float3,
        .vertex_count = vertices.len,
        .index_buffer = &indices,
        .index_format = .uint32,
        .index_count = indices.len,
    };
    
    // Build bottom-level acceleration structure
    const build_flags = mfs.graphics.BuildFlags{
        .prefer_fast_trace = true,
    };
    
    const blas = try rt_context.createBottomLevelAS(
        &[_]mfs.graphics.GeometryDesc{geometry_desc},
        build_flags,
    );
    defer blas.deinit(allocator);
    
    // Create instance for top-level acceleration structure
    const instance_desc = mfs.graphics.InstanceDesc{
        .transform = mfs.math.Mat4.identity(),
        .instance_id = 0,
        .acceleration_structure_reference = blas.device_address,
    };
    
    // Build top-level acceleration structure
    const tlas = try rt_context.createTopLevelAS(
        &[_]mfs.graphics.InstanceDesc{instance_desc},
        build_flags,
    );
    defer tlas.deinit(allocator);
    
    std.log.info("Ray tracing setup complete!", .{});
}
```

### Ray Tracing Shaders

#### Ray Generation Shader (HLSL)

```hlsl
#include "raycommon.hlsl"

[[vk::binding(0, 0)]] RaytracingAccelerationStructure topLevelAS;
[[vk::binding(1, 0)]] RWTexture2D<float4> image;

struct RayPayload {
    float3 color;
    int depth;
};

[shader("raygeneration")]
void RayGenMain() {
    const float2 pixelCenter = float2(DispatchRaysIndex().xy) + float2(0.5, 0.5);
    const float2 inUV = pixelCenter / float2(DispatchRaysDimensions().xy);
    float2 d = inUV * 2.0 - 1.0;
    
    float4 origin = float4(0, 0, -2, 1);
    float4 target = float4(d.x, d.y, 0, 1);
    float4 direction = normalize(target - origin);
    
    RayDesc ray;
    ray.Origin = origin.xyz;
    ray.Direction = direction.xyz;
    ray.TMin = 0.001;
    ray.TMax = 10000.0;
    
    RayPayload payload;
    payload.color = float3(0, 0, 0);
    payload.depth = 0;
    
    TraceRay(topLevelAS, RAY_FLAG_CULL_BACK_FACING_TRIANGLES, 0xFF, 0, 0, 0, ray, payload);
    
    image[DispatchRaysIndex().xy] = float4(payload.color, 1.0);
}
```

#### Miss Shader (HLSL)

```hlsl
#include "raycommon.hlsl"

struct RayPayload {
    float3 color;
    int depth;
};

[shader("miss")]
void MissMain(inout RayPayload payload) {
    // Sky color gradient
    float3 unitDirection = normalize(WorldRayDirection());
    float t = 0.5 * (unitDirection.y + 1.0);
    payload.color = (1.0 - t) * float3(1.0, 1.0, 1.0) + t * float3(0.5, 0.7, 1.0);
}
```

#### Closest Hit Shader (HLSL)

```hlsl
#include "raycommon.hlsl"

struct RayPayload {
    float3 color;
    int depth;
};

struct Attributes {
    float2 bary;
};

[shader("closesthit")]
void ClosestHitMain(inout RayPayload payload, in Attributes attr) {
    const float3 barycentrics = float3(1.0 - attr.bary.x - attr.bary.y, attr.bary.x, attr.bary.y);
    
    // Simple diffuse material
    payload.color = float3(0.8, 0.8, 0.8) * barycentrics.x;
}
```

## Performance Considerations

### Hardware Requirements

**Minimum Requirements:**
- NVIDIA RTX 20-series or newer
- AMD RDNA2 (RX 6000 series) or newer
- Intel Arc A-series
- Apple Silicon M1/M2 (for Metal backend)

**Recommended:**
- NVIDIA RTX 30-series or newer
- AMD RDNA3 (RX 7000 series) or newer
- 8GB+ VRAM for complex scenes

### Optimization Guidelines

1. **Acceleration Structure Optimization**
   - Use `prefer_fast_trace` for static geometry
   - Use `prefer_fast_build` for dynamic geometry
   - Enable compaction for memory-constrained scenarios

2. **Shader Optimization**
   - Minimize ray recursion depth (≤8 levels)
   - Use early ray termination when possible
   - Optimize shader binding table layout

3. **Memory Management**
   - Batch acceleration structure builds
   - Reuse scratch buffers when possible
   - Monitor VRAM usage for large scenes

## Cross-Platform Compatibility

### Vulkan 1.3 Extensions Required

```cpp
VK_KHR_acceleration_structure
VK_KHR_ray_tracing_pipeline
VK_KHR_ray_query
VK_KHR_deferred_host_operations
VK_KHR_buffer_device_address
VK_KHR_spirv_1_4
VK_KHR_shader_float_controls
```

### DirectX Requirements

- Windows 10 version 1903 or later
- DirectX 12 Ultimate compatible driver
- DXR 1.1 support recommended

### Metal Requirements

- macOS 12.0 or later
- Metal 3.0 compatible hardware
- Apple Silicon or AMD RDNA2+ GPU

## Future Enhancements

### Planned Features

1. **Ray Query Support**
   - Inline ray tracing in compute shaders
   - Hybrid rasterization + ray tracing techniques

2. **Mesh Shaders Integration**
   - Modern geometry pipeline support
   - Optimized culling and LOD

3. **Variable Rate Shading**
   - Adaptive quality for VR/AR applications
   - Performance scaling for mobile platforms

4. **Real-Time Global Illumination**
   - Multi-bounce lighting
   - Temporal accumulation
   - Denoising integration

### Advanced Techniques

- **ReSTIR** (Reservoir-based Spatiotemporal Importance Resampling)
- **RTXGI** integration for dynamic global illumination
- **Hardware-accelerated denoising** (DLSS, FSR)
- **Mesh shaders** for modern geometry processing

## Troubleshooting

### Common Issues

1. **Driver Compatibility**
   - Ensure latest GPU drivers are installed
   - Verify ray tracing support in device capabilities

2. **Memory Issues**
   - Monitor acceleration structure sizes
   - Use memory debugging tools for leaks

3. **Performance Problems**
   - Profile shader execution times
   - Optimize acceleration structure builds
   - Reduce ray recursion depth

### Debug Tools

- **NVIDIA Nsight Graphics** for RTX debugging
- **AMD Radeon GPU Profiler** for RDNA debugging
- **Vulkan Validation Layers** for API validation
- **PIX** for DirectX ray tracing debugging

## References

- [Vulkan Ray Tracing Specification](https://www.khronos.org/registry/vulkan/specs/1.3-extensions/man/html/VK_KHR_ray_tracing_pipeline.html)
- [DirectX Ray Tracing Documentation](https://docs.microsoft.com/en-us/windows/win32/direct3d12/direct3d-12-raytracing)
- [NVIDIA Ray Tracing Best Practices](https://developer.nvidia.com/blog/bringing-hlsl-ray-tracing-to-vulkan/)
- [Metal Ray Tracing Guide](https://developer.apple.com/documentation/metalperformanceshaders/metal_for_accelerating_ray_tracing)

## Examples

The `examples/ray_tracing_demo/` directory contains a comprehensive ray tracing demonstration that showcases:

- Multi-backend ray tracing support
- Cornell box scene rendering
- HLSL shader compilation
- Real-time ray tracing pipeline
- Performance monitoring and debugging

Run the demo with:

```bash
zig build run-ray-tracing-demo
```

This implementation represents a state-of-the-art ray tracing system that leverages the latest GPU hardware capabilities while maintaining broad compatibility across different platforms and graphics APIs. 