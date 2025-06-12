const std = @import("std");
const types = @import("../../types.zig");

/// Get the number of bytes per pixel for a given TextureFormat.
pub fn getBytesPerPixel(format: types.TextureFormat) u32 {
    return switch (format) {
        .rgba8, .bgra8, .depth24_stencil8, .depth32f => 4,
        .rgb8 => 3,
        .rg8 => 2,
        .r8 => 1,
    };
}

/// Get the number of color components for a given TextureFormat.
pub fn getComponentCount(format: types.TextureFormat) u32 {
    return switch (format) {
        .rgba8, .bgra8 => 4,
        .rgb8 => 3,
        .rg8 => 2,
        .r8 => 1,
        .depth24_stencil8 => 2,
        .depth32f => 1,
    };
}

/// Check if a texture format has a depth component
pub fn hasDepthComponent(format: types.TextureFormat) bool {
    return switch (format) {
        .depth24_stencil8, .depth32f => true,
        else => false,
    };
}

/// Check if a texture format has a stencil component
pub fn hasStencilComponent(format: types.TextureFormat) bool {
    return switch (format) {
        .depth24_stencil8 => true,
        else => false,
    };
}

/// Convert a generic TextureFormat to a backend-specific format (to be implemented by backends).
pub fn convertTextureFormat(format: types.TextureFormat) u32 {
    return switch (format) {
        .rgba8 => 0,
        .rgb8 => 1,
        .bgra8 => 2,
        .r8 => 3,
        .rg8 => 4,
        .depth24_stencil8 => 5,
        .depth32f => 6,
    };
}

/// Convert a generic vertex format to a backend-specific format (to be implemented by backends).
pub fn convertVertexFormat(format: types.VertexFormat) u32 {
    return switch (format) {
        .float1 => 0,
        .float2 => 1,
        .float3 => 2,
        .float4 => 3,
        .int1 => 4,
        .int2 => 5,
        .int3 => 6,
        .int4 => 7,
        .uint1 => 8,
        .uint2 => 9,
        .uint3 => 10,
        .uint4 => 11,
        .byte4_norm => 12,
        .ubyte4_norm => 13,
        .short2_norm => 14,
        .ushort2_norm => 15,
        .half2 => 16,
        .half4 => 17,
    };
}

/// Get the size in bytes of a vertex format
pub fn getVertexFormatSize(format: types.VertexFormat) u32 {
    return switch (format) {
        .float1 => 4,
        .float2 => 8,
        .float3 => 12,
        .float4 => 16,
        .int1 => 4,
        .int2 => 8,
        .int3 => 12,
        .int4 => 16,
        .uint1 => 4,
        .uint2 => 8,
        .uint3 => 12,
        .uint4 => 16,
        .byte4_norm => 4,
        .ubyte4_norm => 4,
        .short2_norm => 4,
        .ushort2_norm => 4,
        .half2 => 4,
        .half4 => 8,
    };
}
