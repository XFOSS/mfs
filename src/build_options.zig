// MFS Build Options Module
// Provides compile-time configuration options for the engine

const builtin = @import("builtin");

// Platform detection
pub const target_os = @tagName(builtin.os.tag);
pub const is_windows = builtin.os.tag == .windows;
pub const is_macos = builtin.os.tag == .macos;
pub const is_linux = builtin.os.tag == .linux;
pub const is_web = builtin.os.tag == .wasi or builtin.os.tag == .emscripten;
pub const is_mobile = false; // Set by build system for iOS/Android targets
pub const is_desktop = true; // Default to desktop

// Backend availability - defaults will be overridden by build system
pub const vulkan_available = true;
pub const d3d11_available = is_windows;
pub const d3d12_available = is_windows;
pub const metal_available = is_macos;
pub const opengl_available = true;
pub const opengles_available = is_mobile;
pub const webgpu_available = is_web;

// Feature toggles
pub const enable_tracy = false;
pub const enable_hot_reload = builtin.mode == .Debug;
pub const enable_validation = builtin.mode == .Debug;
pub const enable_diagnostics = true;
pub const enable_logging = true;
pub const log_level = if (builtin.mode == .Debug) "debug" else "info";
pub const max_frame_rate = 250;

// Rendering settings
pub const default_width = 1280;
pub const default_height = 720;
pub const use_vsync = true;
pub const multisampling = 4; // MSAA: 1, 2, 4, 8
pub const anisotropic_filtering = 16;

// Memory management
pub const memory_budget_mb = 512;
pub const asset_cache_size_mb = 128;

// Version information
pub const engine_version = "0.1.0";
pub const engine_name = "MFS Engine";
pub const engine_author = "MFS Team";
