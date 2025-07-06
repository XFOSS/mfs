//! MFS Engine - Render Module
//! High-level rendering system built on top of the graphics backend
//! Provides scene rendering, lighting, post-processing, and rendering utilities
//! @thread-safe Rendering commands are thread-safe within render passes
//! @performance Optimized for modern rendering techniques

const std = @import("std");
const builtin = @import("builtin");

// Core rendering components
pub const render = @import("render.zig");
pub const opengl_cube = @import("opengl_cube.zig");
pub const software_cube = @import("software_cube.zig");

// Re-export main render types
pub const Renderer = render.Renderer;
pub const RenderConfig = render.RenderConfig;
pub const RenderPass = render.RenderPass;
pub const RenderTarget = render.RenderTarget;

// Rendering techniques
pub const RenderTechnique = enum {
    forward,
    deferred,
    forward_plus,
    clustered,
};

// Lighting models
pub const LightingModel = enum {
    phong,
    blinn_phong,
    pbr,
    unlit,
};

// Render configuration
pub const RendererConfig = struct {
    technique: RenderTechnique = .forward,
    lighting_model: LightingModel = .pbr,
    enable_shadows: bool = true,
    enable_post_processing: bool = true,
    enable_hdr: bool = true,
    enable_bloom: bool = true,
    enable_ssao: bool = false,
    enable_fxaa: bool = true,
    shadow_map_size: u32 = 1024,
    max_lights: u32 = 64,

    pub fn validate(self: RendererConfig) !void {
        if (self.shadow_map_size == 0 or self.shadow_map_size > 4096) {
            return error.InvalidParameter;
        }
        if (self.max_lights == 0 or self.max_lights > 256) {
            return error.InvalidParameter;
        }
    }
};

// Initialize renderer
pub fn init(allocator: std.mem.Allocator, config: RendererConfig) !*Renderer {
    try config.validate();
    return try Renderer.init(allocator, config);
}

// Cleanup renderer
pub fn deinit(renderer: *Renderer) void {
    renderer.deinit();
}

test "render module" {
    std.testing.refAllDecls(@This());
}
