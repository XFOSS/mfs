//! MFS Graphics - Build Options
//! Generated build configuration for graphics module
//! @auto-generated This file is generated by the build system

/// Graphics build features configuration
pub const Features = struct {
    pub const enable_validation = @import("../build_options.zig").enable_validation;
    pub const enable_ray_tracing = @import("../build_options.zig").enable_ray_tracing;
    pub const enable_compute_shaders = @import("../build_options.zig").enable_compute_shaders;
    pub const enable_mesh_shaders = @import("../build_options.zig").enable_mesh_shaders;
    pub const enable_variable_rate_shading = @import("../build_options.zig").enable_variable_rate_shading;
    pub const enable_hardware_occlusion = @import("../build_options.zig").enable_hardware_occlusion;
    pub const enable_gpu_profiling = @import("../build_options.zig").enable_gpu_profiling;
    pub const enable_debug_markers = @import("../build_options.zig").enable_debug_markers;
};

/// Graphics backend configuration
pub const Backends = struct {
    pub const vulkan_enabled = @import("../build_options.zig").vulkan_enabled;
    pub const d3d11_enabled = @import("../build_options.zig").d3d11_enabled;
    pub const d3d12_enabled = @import("../build_options.zig").d3d12_enabled;
    pub const opengl_enabled = @import("../build_options.zig").opengl_enabled;
    pub const opengles_enabled = @import("../build_options.zig").opengles_enabled;
    pub const metal_enabled = @import("../build_options.zig").metal_enabled;
    pub const webgpu_enabled = @import("../build_options.zig").webgpu_enabled;
    pub const software_enabled = @import("../build_options.zig").software_enabled;
};

/// Platform-specific graphics configuration
pub const Platform = struct {
    pub const target_os = @import("../build_options.zig").target_os;
    pub const target_arch = @import("../build_options.zig").target_arch;
    pub const is_debug = @import("../build_options.zig").is_debug;
    pub const is_web = @import("../build_options.zig").is_web;
    pub const is_mobile = @import("../build_options.zig").is_mobile;
};
