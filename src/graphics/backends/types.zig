//! Graphics Backend Types
//! Common type definitions for graphics backends
//! @symbol Graphics backend types and structures

const std = @import("std");
const interface = @import("interface.zig");
const build_options = @import("../../build_options.zig");

/// Texture resource
/// @thread-safe Thread-compatible data structure
pub const Texture = struct {
    handle: *anyopaque,
    width: u32,
    height: u32,
    depth: u32 = 1,
    format: TextureFormat,
    usage: TextureUsage,
    mip_levels: u32 = 1,
    sample_count: u32 = 1,

    pub const TextureFormat = enum {
        rgba8_unorm,
        rgba8_srgb,
        bgra8_unorm,
        r32_float,
        rg32_float,
        rgb32_float,
        rgba32_float,
        depth32_float,
        depth24_stencil8,
    };

    pub const TextureUsage = packed struct(u32) {
        copy_src: bool = false,
        copy_dst: bool = false,
        texture_binding: bool = false,
        storage_binding: bool = false,
        render_attachment: bool = false,
        _: u27 = 0,
    };
};

/// Buffer resource
/// @thread-safe Thread-compatible data structure
pub const Buffer = struct {
    handle: *anyopaque,
    size: u64,
    usage: BufferUsage,

    pub const BufferUsage = packed struct(u32) {
        map_read: bool = false,
        map_write: bool = false,
        copy_src: bool = false,
        copy_dst: bool = false,
        index: bool = false,
        vertex: bool = false,
        uniform: bool = false,
        storage: bool = false,
        indirect: bool = false,
        query_resolve: bool = false,
        _: u22 = 0,
    };
};

/// Shader resource
/// @thread-safe Thread-compatible data structure
pub const Shader = struct {
    handle: *anyopaque,
    shader_type: ShaderType,
    source: []const u8,

    pub const ShaderType = enum {
        vertex,
        fragment,
        compute,
        geometry,
        tessellation_control,
        tessellation_evaluation,
    };
};

/// Render target resource
/// @thread-safe Thread-compatible data structure
pub const RenderTarget = struct {
    handle: *anyopaque,
    color_targets: []const Texture,
    depth_target: ?*Texture,
    width: u32,
    height: u32,
};

/// Viewport structure
/// @thread-safe Thread-compatible data structure
pub const Viewport = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    min_depth: f32 = 0.0,
    max_depth: f32 = 1.0,
};

/// Scissor rectangle
/// @thread-safe Thread-compatible data structure
pub const ScissorRect = struct {
    x: i32,
    y: i32,
    width: u32,
    height: u32,
};
