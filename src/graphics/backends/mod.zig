//! MFS Engine - Graphics Backends Module
//! Provides access to all graphics backend implementations
//! Supports multiple graphics APIs with automatic fallback selection
//! @thread-safe Backend operations are thread-safe within command buffers
//! @performance Optimized for modern GPU architectures

const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("../../build_options.zig");

// =============================================================================
// Common Backend Utilities
// =============================================================================

pub const common = @import("common/mod.zig");
pub const interface = @import("interface.zig");

// Re-export common types for convenience
pub const BackendInterface = interface.GraphicsBackend;
pub const GraphicsBackend = interface.GraphicsBackend;
pub const BackendError = common.BackendError;
pub const BackendCapabilities = common.BackendCapabilities;
pub const BackendInfo = common.BackendInfo;
pub const BackendConfig = interface.BackendConfig;

// =============================================================================
// Backend Implementations
// =============================================================================

// Vulkan backend (cross-platform, modern)
pub const vulkan = if (build_options.Graphics.vulkan_available)
    @import("vulkan/old/mod.zig")
else
    struct {};

// DirectX backends (Windows only) - temporarily disabled due to C import issues
pub const d3d11 = struct {};
pub const d3d12 = struct {};

// Metal backend (macOS/iOS only)
pub const metal = if (build_options.Graphics.metal_available)
    @import("metal_backend.zig")
else
    struct {};

// OpenGL backends - disabled due to missing headers
pub const opengl = struct {
    pub fn create(_: std.mem.Allocator, _: anytype) !*interface.GraphicsBackend {
        return error.BackendNotAvailable;
    }
};

pub const opengles = if (build_options.Graphics.opengles_available)
    @import("opengles_backend.zig")
else
    struct {};

// WebGPU backend (Web only)
pub const webgpu = if (build_options.Graphics.webgpu_available)
    @import("webgpu/mod.zig")
else
    struct {};

// Software backend (always available as fallback)
pub const software = @import("software/mod.zig");

// =============================================================================
// Backend Management
// =============================================================================

pub const BackendType = build_options.Backend;

/// Backend set for managing multiple backends
pub const BackendSet = struct {
    backends: u32 = 0,

    pub fn init() BackendSet {
        return BackendSet{};
    }

    pub fn initWithAll() BackendSet {
        var set = BackendSet{};
        inline for (@typeInfo(BackendType).Enum.fields) |field| {
            const backend = @as(BackendType, @enumFromInt(field.value));
            if (backend.isAvailable()) {
                set.add(backend);
            }
        }
        return set;
    }

    pub fn add(self: *BackendSet, backend: BackendType) void {
        self.backends |= @as(u32, 1) << @intFromEnum(backend);
    }

    pub fn remove(self: *BackendSet, backend: BackendType) void {
        self.backends &= ~(@as(u32, 1) << @intFromEnum(backend));
    }

    pub fn contains(self: BackendSet, backend: BackendType) bool {
        return (self.backends & (@as(u32, 1) << @intFromEnum(backend))) != 0;
    }

    pub fn count(self: BackendSet) u32 {
        return @popCount(self.backends);
    }

    pub fn isEmpty(self: BackendSet) bool {
        return self.backends == 0;
    }
};

/// Get all available backends
pub fn getAvailableBackends() BackendSet {
    return BackendSet.initWithAll();
}

/// Get the preferred backend for the current platform
pub fn getPreferredBackend() BackendType {
    if (build_options.Platform.is_windows) {
        // DirectX backends temporarily disabled due to missing C headers
        if (build_options.Graphics.opengl_available) return .opengl;
        if (build_options.Graphics.vulkan_available) return .vulkan;
    } else if (build_options.Platform.is_macos) {
        if (build_options.Graphics.metal_available) return .metal;
        if (build_options.Graphics.vulkan_available) return .vulkan;
    } else if (build_options.Platform.is_linux) {
        if (build_options.Graphics.vulkan_available) return .vulkan;
        if (build_options.Graphics.opengl_available) return .opengl;
    } else if (build_options.Platform.is_web) {
        if (build_options.Graphics.webgpu_available) return .webgpu;
        if (build_options.Graphics.opengles_available) return .opengles;
    }

    // Fallback to software renderer
    return .software;
}

/// Check if a specific backend is available
pub fn isBackendAvailable(backend: BackendType) bool {
    return backend.isAvailable();
}

/// Check if backend is supported (alias for consistency)
pub fn isBackendSupported(backend: BackendType) bool {
    return backend.isAvailable();
}

/// Get backend information
pub fn getBackendInfo(backend: BackendType) BackendInfo {
    return switch (backend) {
        .vulkan => if (build_options.Graphics.vulkan_available) vulkan.getInfo() else BackendInfo.unavailable("Vulkan"),
        .d3d11 => if (build_options.Graphics.d3d11_available) d3d11.getInfo() else BackendInfo.unavailable("D3D11"),
        .d3d12 => BackendInfo.unavailable("D3D12"), // Disabled due to missing C headers
        .metal => if (build_options.Graphics.metal_available) metal.getInfo() else BackendInfo.unavailable("Metal"),
        .opengl => if (build_options.Graphics.opengl_available) opengl.getInfo() else BackendInfo.unavailable("OpenGL"),
        .opengl_es => if (build_options.Graphics.opengles_available) opengles.getInfo() else BackendInfo.unavailable("OpenGL ES"),
        .opengles => if (build_options.Graphics.opengles_available) opengles.getInfo() else BackendInfo.unavailable("OpenGL ES"),
        .webgpu => if (build_options.Graphics.webgpu_available) webgpu.getInfo() else BackendInfo.unavailable("WebGPU"),
        .software => software.getInfo(),
        .auto => BackendInfo.auto(),
    };
}

/// Create a graphics backend based on the given configuration
pub fn createBackend(allocator: std.mem.Allocator, config: interface.BackendConfig) !*interface.GraphicsBackend {
    // Get preferred backend type, with fallback logic
    const backend_type = if (config.backend_type == .auto)
        build_options.Graphics.default_backend
    else
        config.backend_type;

    return switch (backend_type) {
        .vulkan => if (build_options.Graphics.vulkan_available)
            try vulkan.create(allocator, config)
        else
            try software.create(allocator, config),

        .d3d11 => if (build_options.Graphics.d3d11_available)
            try software.create(allocator, config) // Fallback to software since d3d11 is disabled
        else
            try software.create(allocator, config),

        .d3d12 => if (build_options.Graphics.d3d12_available)
            try software.create(allocator, config) // Fallback to software since d3d12 is disabled
        else
            try software.create(allocator, config),

        .metal => if (build_options.Graphics.metal_available)
            try metal.create(allocator, config)
        else
            try software.create(allocator, config),

        .opengl => if (build_options.Graphics.opengl_available)
            try opengl.create(allocator, config)
        else
            try software.create(allocator, config),

        .opengl_es => if (build_options.Graphics.opengles_available)
            try opengles.create(allocator, config)
        else
            try software.create(allocator, config),

        .opengles => if (build_options.Graphics.opengles_available)
            try opengles.create(allocator, config)
        else
            try software.create(allocator, config),

        .webgpu => if (build_options.Graphics.webgpu_available)
            try webgpu.create(allocator, config)
        else
            try software.create(allocator, config),

        .software => try software.create(allocator, config),

        .auto => unreachable, // Handled above
    };
}

/// Destroy a backend instance
pub fn destroyBackend(backend_instance: *interface.GraphicsBackend) void {
    const allocator = backend_instance.allocator;
    const vtable = backend_instance.vtable;

    // Call the backend's deinit method (this cleans up resources but doesn't free memory)
    backend_instance.deinit();

    // Clean up the implementation data based on backend type
    switch (backend_instance.backend_type) {
        .software => {
            const impl = @as(*software.SoftwareBackend, @ptrCast(@alignCast(backend_instance.impl_data)));
            allocator.destroy(impl);
        },
        else => {
            // For other backends, we'd need similar type-specific cleanup
            // For now, just log that cleanup is needed
            std.log.warn("Backend type {} cleanup not fully implemented", .{backend_instance.backend_type});
        },
    }

    // Clean up the vtable
    allocator.destroy(vtable);

    // Clean up the backend instance
    allocator.destroy(backend_instance);
}

// =============================================================================
// Backend Feature Detection
// =============================================================================

pub const Features = struct {
    pub fn supportsRayTracing(backend: BackendType) bool {
        return switch (backend) {
            .vulkan => build_options.Graphics.vulkan_available and build_options.Features.enable_ray_tracing,
            .d3d12 => build_options.Graphics.d3d12_available and build_options.Features.enable_ray_tracing,
            else => false,
        };
    }

    pub fn supportsMeshShaders(backend: BackendType) bool {
        return switch (backend) {
            .vulkan => build_options.Graphics.vulkan_available and build_options.Features.enable_mesh_shaders,
            .d3d12 => build_options.Graphics.d3d12_available and build_options.Features.enable_mesh_shaders,
            else => false,
        };
    }

    pub fn supportsComputeShaders(backend: BackendType) bool {
        return switch (backend) {
            .vulkan, .d3d11, .d3d12, .metal, .webgpu => true,
            .opengl, .opengles => true, // Modern versions
            .software => false,
            .auto => true,
        };
    }

    pub fn supportsGeometryShaders(backend: BackendType) bool {
        return switch (backend) {
            .vulkan, .d3d11, .d3d12, .opengl => true,
            .metal, .opengles, .webgpu => false,
            .software => false,
            .auto => true,
        };
    }

    pub fn supportsTessellation(backend: BackendType) bool {
        return switch (backend) {
            .vulkan, .d3d11, .d3d12, .opengl => true,
            .metal, .opengles, .webgpu => false,
            .software => false,
            .auto => true,
        };
    }

    pub fn getMaxTextureSize(backend: BackendType) u32 {
        return switch (backend) {
            .vulkan, .d3d12 => 16384,
            .d3d11, .metal => 8192,
            .opengl, .opengles => 4096,
            .webgpu => 8192,
            .software => 2048,
            .auto => 8192,
        };
    }
};

// =============================================================================
// Utility Functions
// =============================================================================

/// Print information about all available backends
pub fn printBackendInfo() void {
    std.log.info("=== Graphics Backends Information ===", .{});
    std.log.info("Preferred Backend: {s}", .{getPreferredBackend().getName()});

    const available = getAvailableBackends();
    std.log.info("Available Backends: {}", .{available.count()});

    inline for (@typeInfo(BackendType).Enum.fields) |field| {
        const backend = @as(BackendType, @enumFromInt(field.value));
        if (backend != .auto) {
            const info = getBackendInfo(backend);
            std.log.info("  {s}: {s}", .{ backend.getName(), if (backend.isAvailable()) "Available" else "Not Available" });
            _ = info;
        }
    }
}

/// Get backend performance tier (0 = lowest, 3 = highest)
pub fn getBackendPerformanceTier(backend: BackendType) u8 {
    return switch (backend) {
        .vulkan, .d3d12 => 3, // Modern, high-performance APIs
        .metal => 3, // Apple's optimized API
        .d3d11 => 2, // Mature, well-optimized
        .webgpu => 2, // Modern web standard
        .opengl => 1, // Legacy but functional
        .opengles => 1, // Mobile/embedded
        .software => 0, // CPU fallback
        .auto => 3, // Will select best available
    };
}

// =============================================================================
// Ray Tracing Support
// =============================================================================

/// Ray tracing context for backends that support it
pub const RayTracingContext = struct {
    backend: *BackendInterface,
    enabled: bool = false,

    pub fn init(backend: *BackendInterface) RayTracingContext {
        return RayTracingContext{
            .backend = backend,
            .enabled = Features.supportsRayTracing(backend.getType()),
        };
    }

    pub fn isEnabled(self: RayTracingContext) bool {
        return self.enabled;
    }

    pub fn deinit(self: *RayTracingContext) void {
        _ = self;
        // Ray tracing cleanup if needed
    }
};

test "graphics backends module" {
    const testing = std.testing;

    // Test backend availability
    const available = getAvailableBackends();
    try testing.expect(available.count() > 0);

    // Test preferred backend
    const preferred = getPreferredBackend();
    try testing.expect(preferred.isAvailable());

    // Test backend features
    try testing.expect(Features.supportsComputeShaders(.auto));
}
