//! Build options for MFS Engine
//! This file is generated by the build system

const std = @import("std");
const builtin = @import("builtin");

// Platform detection
pub const is_windows: bool = builtin.os.tag == .windows;
pub const is_linux: bool = builtin.os.tag == .linux;
pub const is_macos: bool = builtin.os.tag == .macos;
pub const is_web: bool = builtin.os.tag == .emscripten or builtin.os.tag == .wasi;
pub const is_mobile: bool = false;

// Composite platform categories
pub const is_desktop: bool = is_windows or is_linux or is_macos;

// Graphics backend availability
pub const vulkan_available: bool = builtin.os.tag == .windows or builtin.os.tag == .linux;
pub const d3d11_available: bool = builtin.os.tag == .windows;
pub const d3d12_available: bool = builtin.os.tag == .windows;
pub const metal_available: bool = builtin.os.tag == .macos;
pub const opengl_available: bool = !is_web;
pub const webgpu_available: bool = is_web;
pub const opengles_available: bool = is_web or is_mobile;

// Core feature flags
pub const Features = struct {
    pub const enable_validation = builtin.mode == .Debug;
    pub const enable_tracy = false;
    pub const enable_hot_reload = builtin.mode == .Debug;
    pub const enable_ray_tracing = true;
    pub const enable_audio = true;
    pub const enable_compute_shaders = true;
    pub const enable_3d_audio = true;
    pub const enable_physics = true;
    pub const enable_neural = true;
    pub const enable_voxels = true;
    pub const enable_mesh_shaders = true;
    pub const enable_variable_rate_shading = true;
    pub const enable_bindless_textures = true;
};

// Graphics configuration
pub const Graphics = struct {
    // Backend availability
    pub const d3d11_available = is_windows;
    pub const d3d12_available = is_windows;
    pub const d3d12_supported = is_windows;
    pub const vulkan_available = is_windows or is_linux;
    pub const metal_available = is_macos;
    pub const opengl_available = !is_web;
    pub const webgpu_available = is_web;
    pub const opengles_available = is_web or is_mobile;

    // Default backend selection
    pub const default_backend = if (is_windows and d3d12_supported)
        Backend.d3d12
    else if ((is_windows or is_linux) and Graphics.vulkan_available)
        Backend.vulkan
    else if (is_macos and Graphics.metal_available)
        Backend.metal
    else if (is_web and Graphics.webgpu_available)
        Backend.webgpu
    else if (Graphics.opengl_available)
        Backend.opengl
    else if (Graphics.opengles_available)
        Backend.opengles
    else
        Backend.software;

    // Default surface dimensions
    pub const default_width: u32 = 1280;
    pub const default_height: u32 = 720;
    pub const default_vsync: bool = true;
};

// Performance configuration
pub const Performance = struct {
    pub const target_frame_rate: u32 = 60;
    pub const enable_vsync = true;
    pub const enable_triple_buffering = true;
    pub const enable_adaptive_sync = true;
};

// Version information
pub const Version = struct {
    pub const engine_name = "MFS Engine";
    pub const engine_version = "1.0.0";
    pub const major = 1;
    pub const minor = 0;
    pub const patch = 0;

    pub fn getFullVersionString() []const u8 {
        return engine_name ++ " v" ++ engine_version;
    }
};

// Platform utilities
pub const Platform = struct {
    pub fn getName() []const u8 {
        return @tagName(builtin.os.tag);
    }

    pub fn getArchName() []const u8 {
        return @tagName(builtin.cpu.arch);
    }

    pub const is_desktop = switch (builtin.os.tag) {
        .windows, .linux, .macos => true,
        else => false,
    };

    pub const is_mobile = switch (builtin.os.tag) {
        .ios, .android => true,
        else => false,
    };

    pub const is_web = switch (builtin.os.tag) {
        .emscripten, .wasi, .freestanding => true,
        else => false,
    };

    pub const is_windows = builtin.os.tag == .windows;
    pub const is_linux = builtin.os.tag == .linux;
    pub const is_macos = builtin.os.tag == .macos;
};

// Backend type enum
pub const Backend = enum {
    auto,
    d3d11,
    d3d12,
    vulkan,
    metal,
    opengl,
    opengl_es,
    software,
    webgpu,
    opengles,

    pub fn getName(self: Backend) []const u8 {
        return switch (self) {
            .auto => "Auto",
            .d3d11 => "D3D11",
            .d3d12 => "D3D12",
            .vulkan => "Vulkan",
            .metal => "Metal",
            .opengl => "OpenGL",
            .opengl_es => "OpenGL ES",
            .software => "Software",
            .webgpu => "WebGPU",
            .opengles => "OpenGL ES",
        };
    }

    pub fn isAvailable(self: Backend) bool {
        return switch (self) {
            .auto => true,
            .d3d11 => Graphics.d3d11_available,
            .d3d12 => Graphics.d3d12_available,
            .vulkan => Graphics.vulkan_available,
            .metal => Graphics.metal_available,
            .opengl => Graphics.opengl_available,
            .opengl_es => Graphics.opengles_available,
            .software => true,
            .webgpu => Graphics.webgpu_available,
            .opengles => Graphics.opengles_available,
        };
    }

    /// Check if backend is available at build time (platform support)
    /// Note: This only checks if the platform supports the backend,
    /// not if it's actually functional at runtime (e.g., drivers installed)
    pub fn isBuildTimeAvailable(self: Backend) bool {
        return self.isAvailable();
    }

    /// Check if backend might be functional at runtime
    /// This provides a more conservative estimate based on common availability
    pub fn isLikelyFunctional(self: Backend) bool {
        return switch (self) {
            .auto => true,
            .software => true, // Always functional as CPU fallback
            .opengl => Graphics.opengl_available, // Usually functional on desktop
            .d3d11 => Graphics.d3d11_available, // Usually functional on Windows
            .vulkan => false, // Conservative: requires drivers and SDK
            .d3d12 => false, // Conservative: requires newer Windows and drivers
            .metal => Graphics.metal_available, // Usually functional on macOS
            .opengl_es => Graphics.opengles_available,
            .webgpu => Graphics.webgpu_available,
            .opengles => Graphics.opengles_available,
        };
    }
};
