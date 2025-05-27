const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");

/// Platform-specific graphics capabilities detection and management
pub const GraphicsCapabilities = struct {
    // Available graphics APIs
    vulkan_available: bool = false,
    d3d11_available: bool = false,
    d3d12_available: bool = false,
    metal_available: bool = false,
    opengl_available: bool = false,
    opengles_available: bool = false,
    webgpu_available: bool = false,

    // Vulkan details
    vulkan_version: u32 = 0,
    vulkan_device_count: u32 = 0,
    vulkan_discrete_gpu: bool = false,

    // DirectX details
    d3d11_feature_level: u32 = 0,
    d3d12_feature_level: u32 = 0,

    // Metal details
    metal_version: u32 = 0,
    metal_gpu_family: u32 = 0,

    // OpenGL details
    opengl_version_major: u32 = 0,
    opengl_version_minor: u32 = 0,
    opengl_core_profile: bool = false,

    // Hardware capabilities
    max_texture_size: u32 = 0,
    max_texture_layers: u32 = 0,
    max_render_targets: u32 = 1,
    max_samples: u32 = 1,
    unified_memory: bool = false,
    dedicated_video_memory: u64 = 0,
    shared_system_memory: u64 = 0,

    // Feature support
    supports_compute_shaders: bool = false,
    supports_geometry_shaders: bool = false,
    supports_tessellation: bool = false,
    supports_multiview: bool = false,
    supports_raytracing: bool = false,
    supports_mesh_shaders: bool = false,
    supports_variable_rate_shading: bool = false,

    // Extensions and features
    extensions: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .extensions = std.ArrayList([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.extensions.items) |ext| {
            self.allocator.free(ext);
        }
        self.extensions.deinit();
    }

    pub fn detect(self: *Self) !void {
        self.detectPlatformCapabilities();

        if (comptime build_options.vulkan_available) {
            self.detectVulkanCapabilities();
        }

        if (comptime build_options.d3d11_available) {
            self.detectD3D11Capabilities();
        }

        if (comptime build_options.d3d12_available) {
            self.detectD3D12Capabilities();
        }

        if (comptime build_options.metal_available) {
            self.detectMetalCapabilities();
        }

        if (comptime build_options.opengl_available) {
            self.detectOpenGLCapabilities();
        }

        if (comptime build_options.opengles_available) {
            self.detectOpenGLESCapabilities();
        }

        if (comptime build_options.webgpu_available) {
            self.detectWebGPUCapabilities();
        }
    }

    fn detectPlatformCapabilities(self: *Self) void {
        switch (builtin.os.tag) {
            .windows => {
                self.d3d11_available = build_options.d3d11_available;
                self.d3d12_available = build_options.d3d12_available;
                self.opengl_available = build_options.opengl_available;
                self.vulkan_available = build_options.vulkan_available;
            },
            .macos => {
                self.metal_available = build_options.metal_available;
                self.opengl_available = build_options.opengl_available;
                self.vulkan_available = build_options.vulkan_available;
            },
            .ios => {
                self.metal_available = build_options.metal_available;
                self.opengles_available = build_options.opengles_available;
            },
            .linux => {
                if (build_options.is_mobile) {
                    // Android
                    self.opengles_available = build_options.opengles_available;
                    self.vulkan_available = build_options.vulkan_available;
                } else {
                    // Desktop Linux
                    self.opengl_available = build_options.opengl_available;
                    self.vulkan_available = build_options.vulkan_available;
                }
            },
            .emscripten, .wasi => {
                self.webgpu_available = build_options.webgpu_available;
                self.opengles_available = build_options.opengles_available;
            },
            else => {
                // Unknown platform - try OpenGL as fallback
                self.opengl_available = true;
            },
        }
    }

    fn detectVulkanCapabilities(self: *Self) void {
        // Platform-specific Vulkan detection
        if (self.vulkan_available) {
            // Try to initialize Vulkan and query capabilities
            if (self.tryVulkanInit()) {
                self.vulkan_version = self.queryVulkanVersion();
                self.vulkan_device_count = self.queryVulkanDeviceCount();
                self.vulkan_discrete_gpu = self.queryVulkanDiscreteGPU();
                self.queryVulkanFeatures();
            } else {
                self.vulkan_available = false;
            }
        }
    }

    fn detectD3D11Capabilities(self: *Self) void {
        if (builtin.os.tag != .windows) return;

        if (self.d3d11_available) {
            if (self.tryD3D11Init()) {
                self.d3d11_feature_level = self.queryD3D11FeatureLevel();
                self.queryD3D11Features();
            } else {
                self.d3d11_available = false;
            }
        }
    }

    fn detectD3D12Capabilities(self: *Self) void {
        if (builtin.os.tag != .windows) return;

        if (self.d3d12_available) {
            if (self.tryD3D12Init()) {
                self.d3d12_feature_level = self.queryD3D12FeatureLevel();
                self.queryD3D12Features();
            } else {
                self.d3d12_available = false;
            }
        }
    }

    fn detectMetalCapabilities(self: *Self) void {
        if (builtin.os.tag != .macos and builtin.os.tag != .ios) return;

        if (self.metal_available) {
            if (self.tryMetalInit()) {
                self.metal_version = self.queryMetalVersion();
                self.metal_gpu_family = self.queryMetalGPUFamily();
                self.queryMetalFeatures();
            } else {
                self.metal_available = false;
            }
        }
    }

    fn detectOpenGLCapabilities(self: *Self) void {
        if (self.opengl_available) {
            if (self.tryOpenGLInit()) {
                const version = self.queryOpenGLVersion();
                self.opengl_version_major = version.major;
                self.opengl_version_minor = version.minor;
                self.opengl_core_profile = self.queryOpenGLCoreProfile();
                self.queryOpenGLFeatures();
            } else {
                self.opengl_available = false;
            }
        }
    }

    fn detectOpenGLESCapabilities(self: *Self) void {
        if (self.opengles_available) {
            if (self.tryOpenGLESInit()) {
                const version = self.queryOpenGLESVersion();
                self.opengl_version_major = version.major;
                self.opengl_version_minor = version.minor;
                self.queryOpenGLESFeatures();
            } else {
                self.opengles_available = false;
            }
        }
    }

    fn detectWebGPUCapabilities(self: *Self) void {
        if (self.webgpu_available) {
            if (self.tryWebGPUInit()) {
                self.queryWebGPUFeatures();
            } else {
                self.webgpu_available = false;
            }
        }
    }

    // Vulkan implementation stubs
    fn tryVulkanInit(self: *Self) bool {
        _ = self;
        // TODO: Implement actual Vulkan initialization
        return true;
    }

    fn queryVulkanVersion(self: *Self) u32 {
        _ = self;
        // TODO: Query actual Vulkan version
        return 0x00401000; // Vulkan 1.0
    }

    fn queryVulkanDeviceCount(self: *Self) u32 {
        _ = self;
        // TODO: Query actual device count
        return 1;
    }

    fn queryVulkanDiscreteGPU(self: *Self) bool {
        _ = self;
        // TODO: Check for discrete GPU
        return false;
    }

    fn queryVulkanFeatures(self: *Self) void {
        // TODO: Query Vulkan features and extensions
        self.supports_compute_shaders = true;
        self.supports_geometry_shaders = true;
        self.supports_tessellation = true;
        self.max_texture_size = 16384;
        self.max_render_targets = 8;
    }

    // DirectX 11 implementation stubs
    fn tryD3D11Init(self: *Self) bool {
        _ = self;
        // TODO: Implement actual D3D11 initialization
        return true;
    }

    fn queryD3D11FeatureLevel(self: *Self) u32 {
        _ = self;
        // TODO: Query actual feature level
        return 0xB000; // D3D_FEATURE_LEVEL_11_0
    }

    fn queryD3D11Features(self: *Self) void {
        // TODO: Query DirectX 11 features
        self.supports_compute_shaders = true;
        self.supports_geometry_shaders = true;
        self.supports_tessellation = true;
        self.max_texture_size = 16384;
        self.max_render_targets = 8;
    }

    // DirectX 12 implementation stubs
    fn tryD3D12Init(self: *Self) bool {
        _ = self;
        // TODO: Implement actual D3D12 initialization
        return true;
    }

    fn queryD3D12FeatureLevel(self: *Self) u32 {
        _ = self;
        // TODO: Query actual feature level
        return 0xC000; // D3D_FEATURE_LEVEL_12_0
    }

    fn queryD3D12Features(self: *Self) void {
        // TODO: Query DirectX 12 features
        self.supports_compute_shaders = true;
        self.supports_geometry_shaders = true;
        self.supports_tessellation = true;
        self.supports_mesh_shaders = true;
        self.supports_raytracing = true;
        self.supports_variable_rate_shading = true;
        self.max_texture_size = 16384;
        self.max_render_targets = 8;
    }

    // Metal implementation stubs
    fn tryMetalInit(self: *Self) bool {
        _ = self;
        // TODO: Implement actual Metal initialization
        return true;
    }

    fn queryMetalVersion(self: *Self) u32 {
        _ = self;
        // TODO: Query Metal version
        return 3; // Metal 3
    }

    fn queryMetalGPUFamily(self: *Self) u32 {
        _ = self;
        // TODO: Query GPU family
        return 1; // MTLGPUFamilyApple1
    }

    // fn queryMetalFeatures<comptime T: Self>(self: *T) T {
    //     const T = self;
    //     // TODO: Query Metal features
    //     self.supports_compute_shaders = true;
    //     self.supports_tessellation = true;
    //     self.unified_memory = true;
    //     self.max_texture_size = 16384;
    //     self.max_render_targets = 8;

    //     return T;
    // }

    // // OpenGL implementation stubs
    // fn tryOpenGLInit(self: *Self) bool {
    //     _ = self;
    //     // TODO: Implement actual OpenGL initialization
    //     return true;
    // }

    fn queryOpenGLVersion(self: *Self) struct { major: u32, minor: u32 } {
        _ = self;
        // TODO: Query actual OpenGL version
        return .{ .major = 4, .minor = 6 };
    }

    fn queryOpenGLCoreProfile(self: *Self) bool {
        _ = self;
        // TODO: Check if core profile
        return true;
    }

    fn queryOpenGLFeatures(self: *Self) void {
        // TODO: Query OpenGL features and extensions
        self.supports_compute_shaders = true;
        self.supports_geometry_shaders = true;
        self.supports_tessellation = true;
        self.max_texture_size = 16384;
        self.max_render_targets = 8;
    }

    fn querySoftwareFeatures(self: *Self) void {
        // Software renderer has limited features
        self.supports_compute_shaders = false;
        self.supports_geometry_shaders = false;
        self.supports_tessellation = false;
        self.max_texture_size = 4096;
        self.max_render_targets = 1;
    }

    // OpenGL ES implementation stubs
    fn tryOpenGLESInit(self: *Self) bool {
        // TODO: Implement actual OpenGL ES initialization
        _ = self;
        return true;
    }

    fn queryOpenGLESVersion(self: *Self) struct { major: u32, minor: u32 } {
        // TODO: Query actual OpenGL ES version
        _ = self;
        return .{ .major = 3, .minor = 2 };
    }

    fn queryOpenGLESFeatures(self: *Self) void {
        // TODO: Query OpenGL ES extensions and features
        self.supports_compute_shaders = true;
        self.max_texture_size = 4096;
        self.max_render_targets = 4;
    }

    // WebGPU implementation stubs
    fn tryWebGPUInit(self: *Self) bool {
        // TODO: Implement actual WebGPU initialization
        _ = self;
        return true;
    }

    fn queryWebGPUFeatures(self: *Self) void {
        // TODO: Query WebGPU features
        self.supports_compute_shaders = true;
        self.max_texture_size = 8192;
        self.max_render_targets = 8;
    }

    pub fn getBestBackend(self: *const Self) GraphicsBackend {
        // Priority order based on performance and features
        if (self.d3d12_available) return .d3d12;
        if (self.vulkan_available) return .vulkan;
        if (self.metal_available) return .metal;
        if (self.d3d11_available) return .d3d11;
        if (self.opengl_available) return .opengl;
        if (self.opengles_available) return .opengles;
        if (self.webgpu_available) return .webgpu;
        return .software;
    }

    pub fn isBackendAvailable(self: *const Self, backend: GraphicsBackend) bool {
        return switch (backend) {
            .vulkan => self.vulkan_available,
            .d3d11 => self.d3d11_available,
            .d3d12 => self.d3d12_available,
            .metal => self.metal_available,
            .opengl => self.opengl_available,
            .opengles => self.opengles_available,
            .webgpu => self.webgpu_available,
            .software => true,
        };
    }

    pub fn addExtension(self: *Self, extension: []const u8) !void {
        const owned_ext = try self.allocator.dupe(u8, extension);
        try self.extensions.append(owned_ext);
    }

    pub fn hasExtension(self: *const Self, extension: []const u8) bool {
        for (self.extensions.items) |ext| {
            if (std.mem.eql(u8, ext, extension)) return true;
        }
        return false;
    }

    pub fn printCapabilities(self: *const Self) void {
        std.log.info("=== Graphics Capabilities ===", .{});
        std.log.info("Platform: {s} ({s})", .{ @tagName(builtin.os.tag), @tagName(builtin.cpu.arch) });
        std.log.info("Best backend: {s}", .{@tagName(self.getBestBackend())});

        std.log.info("Available backends:", .{});
        if (self.vulkan_available) std.log.info("  ✓ Vulkan {d}.{d}", .{ self.vulkan_version >> 22, (self.vulkan_version >> 12) & 0x3FF });
        if (self.d3d11_available) std.log.info("  ✓ DirectX 11 (Feature Level: 0x{X})", .{self.d3d11_feature_level});
        if (self.d3d12_available) std.log.info("  ✓ DirectX 12 (Feature Level: 0x{X})", .{self.d3d12_feature_level});
        if (self.metal_available) std.log.info("  ✓ Metal {d} (GPU Family: {d})", .{ self.metal_version, self.metal_gpu_family });
        if (self.opengl_available) std.log.info("  ✓ OpenGL {d}.{d} {s}", .{ self.opengl_version_major, self.opengl_version_minor, if (self.opengl_core_profile) "(Core)" else "(Compatibility)" });
        if (self.opengles_available) std.log.info("  ✓ OpenGL ES {d}.{d}", .{ self.opengl_version_major, self.opengl_version_minor });
        if (self.webgpu_available) std.log.info("  ✓ WebGPU", .{});

        std.log.info("Hardware capabilities:", .{});
        std.log.info("  Max texture size: {d}x{d}", .{ self.max_texture_size, self.max_texture_size });
        std.log.info("  Max render targets: {d}", .{self.max_render_targets});
        std.log.info("  Max MSAA samples: {d}", .{self.max_samples});
        if (self.dedicated_video_memory > 0) {
            std.log.info("  Video memory: {d} MB", .{self.dedicated_video_memory / 1024 / 1024});
        }

        std.log.info("Feature support:", .{});
        if (self.supports_compute_shaders) std.log.info("  ✓ Compute shaders", .{});
        if (self.supports_geometry_shaders) std.log.info("  ✓ Geometry shaders", .{});
        if (self.supports_tessellation) std.log.info("  ✓ Tessellation", .{});
        if (self.supports_raytracing) std.log.info("  ✓ Ray tracing", .{});
        if (self.supports_mesh_shaders) std.log.info("  ✓ Mesh shaders", .{});
        if (self.supports_variable_rate_shading) std.log.info("  ✓ Variable rate shading", .{});

        if (self.extensions.items.len > 0) {
            std.log.info("Extensions: {d} loaded", .{self.extensions.items.len});
        }
    }
};

pub const GraphicsBackend = enum {
    vulkan,
    d3d11,
    d3d12,
    metal,
    opengl,
    opengles,
    webgpu,
    software,

    pub fn getName(self: GraphicsBackend) []const u8 {
        return switch (self) {
            .vulkan => "Vulkan",
            .d3d11 => "DirectX 11",
            .d3d12 => "DirectX 12",
            .metal => "Metal",
            .opengl => "OpenGL",
            .opengles => "OpenGL ES",
            .webgpu => "WebGPU",
            .software => "Software",
        };
    }

    pub fn isHardwareAccelerated(self: GraphicsBackend) bool {
        return self != .software;
    }

    pub fn supportsCompute(self: GraphicsBackend) bool {
        return switch (self) {
            .vulkan, .d3d11, .d3d12, .metal, .webgpu => true,
            .opengl => true, // OpenGL 4.3+
            .opengles => true, // OpenGL ES 3.1+
            .software => false,
        };
    }

    pub fn supportsRayTracing(self: GraphicsBackend) bool {
        return switch (self) {
            .vulkan, .d3d12 => true,
            .metal => true, // Metal 3+
            else => false,
        };
    }
};

/// Global capabilities instance
var g_capabilities: ?GraphicsCapabilities = null;

pub fn getCapabilities() *GraphicsCapabilities {
    return &g_capabilities.?;
}

pub fn initCapabilities(allocator: std.mem.Allocator) !void {
    g_capabilities = GraphicsCapabilities.init(allocator);
    try g_capabilities.?.detect();
}

pub fn deinitCapabilities() void {
    if (g_capabilities) |*caps| {
        caps.deinit();
        g_capabilities = null;
    }
}
