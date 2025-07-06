const std = @import("std");
const builtin = @import("builtin");

pub const GraphicsBackend = enum {
    vulkan,
    d3d11,
    d3d12,
    metal,
    opengl,
    opengles,
    webgpu,
    software,
};

pub const PlatformCapabilities = struct {
    // Graphics backend availability
    vulkan_available: bool = false,
    d3d11_available: bool = false,
    d3d12_available: bool = false,
    metal_available: bool = false,
    opengl_available: bool = false,
    opengles_available: bool = false,
    webgpu_available: bool = false,
    software_available: bool = true, // Always available

    // Hardware features
    supports_compute_shaders: bool = false,
    supports_geometry_shaders: bool = false,
    supports_tessellation: bool = false,
    supports_mesh_shaders: bool = false,
    supports_raytracing: bool = false,
    supports_variable_rate_shading: bool = false,
    unified_memory: bool = false,

    // Limits
    max_texture_size: u32 = 1024,
    max_render_targets: u32 = 1,
    max_compute_work_group_size: [3]u32 = .{ 1, 1, 1 },

    const Self = @This();

    pub fn detect() Self {
        var caps = Self{};

        // Platform-specific detection
        switch (builtin.target.os.tag) {
            .windows => caps.detectWindows(),
            .macos => caps.detectMacOS(),
            .linux => caps.detectLinux(),
            .emscripten => caps.detectWeb(),
            else => caps.detectGeneric(),
        }

        return caps;
    }

    fn detectWindows(self: *Self) void {
        // Windows supports DirectX and potentially Vulkan/OpenGL
        self.d3d11_available = true;
        self.d3d12_available = true;
        self.vulkan_available = true;
        self.opengl_available = true;
        self.setModernFeatures();
    }

    fn detectMacOS(self: *Self) void {
        // macOS supports Metal and potentially Vulkan (via MoltenVK)
        self.metal_available = true;
        self.vulkan_available = true; // Via MoltenVK
        self.opengl_available = true; // Legacy support
        self.unified_memory = true;
        self.setModernFeatures();
    }

    fn detectLinux(self: *Self) void {
        // Linux primarily supports Vulkan and OpenGL
        self.vulkan_available = true;
        self.opengl_available = true;
        self.setModernFeatures();
    }

    fn detectWeb(self: *Self) void {
        // Web supports WebGPU and WebGL (OpenGL ES)
        self.webgpu_available = true;
        self.opengles_available = true;
        self.setWebFeatures();
    }

    fn detectGeneric(self: *Self) void {
        // Fallback to software rendering
        self.software_available = true;
        self.setSoftwareFeatures();
    }

    fn setModernFeatures(self: *Self) void {
        self.supports_compute_shaders = true;
        self.supports_geometry_shaders = true;
        self.supports_tessellation = true;
        self.supports_mesh_shaders = true;
        self.supports_raytracing = true;
        self.supports_variable_rate_shading = true;
        self.max_texture_size = 16384;
        self.max_render_targets = 8;
        self.max_compute_work_group_size = .{ 1024, 1024, 64 };
    }

    fn setWebFeatures(self: *Self) void {
        self.supports_compute_shaders = true;
        self.max_texture_size = 8192;
        self.max_render_targets = 8;
        self.max_compute_work_group_size = .{ 256, 256, 64 };
    }

    fn setSoftwareFeatures(self: *Self) void {
        // Software renderer has minimal features
        self.max_texture_size = 4096;
        self.max_render_targets = 1;
    }

    pub fn getBestBackend(self: *const Self) GraphicsBackend {
        // Priority order based on performance and features
        const backends = [_]struct { backend: GraphicsBackend, available: bool }{
            .{ .backend = .d3d12, .available = self.d3d12_available },
            .{ .backend = .vulkan, .available = self.vulkan_available },
            .{ .backend = .metal, .available = self.metal_available },
            .{ .backend = .webgpu, .available = self.webgpu_available },
            .{ .backend = .d3d11, .available = self.d3d11_available },
            .{ .backend = .opengl, .available = self.opengl_available },
            .{ .backend = .opengles, .available = self.opengles_available },
            .{ .backend = .software, .available = self.software_available },
        };

        for (backends) |item| {
            if (item.available) return item.backend;
        }

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
            .software => self.software_available,
        };
    }

    pub fn getBackendName(backend: GraphicsBackend) []const u8 {
        return switch (backend) {
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

    pub fn printCapabilities(self: *const Self) void {
        std.log.info("Graphics Backend Capabilities:", .{});
        std.log.info("  Best backend: {s}", .{getBackendName(self.getBestBackend())});

        inline for (std.meta.fields(GraphicsBackend)) |field| {
            const backend = @as(GraphicsBackend, @enumFromInt(field.value));
            if (self.isBackendAvailable(backend)) {
                std.log.info("  {s}: Available", .{getBackendName(backend)});
            }
        }

        std.log.info("Hardware Features:", .{});
        std.log.info("  Compute shaders: {}", .{self.supports_compute_shaders});
        std.log.info("  Geometry shaders: {}", .{self.supports_geometry_shaders});
        std.log.info("  Tessellation: {}", .{self.supports_tessellation});
        std.log.info("  Ray tracing: {}", .{self.supports_raytracing});
        std.log.info("  Max texture size: {}", .{self.max_texture_size});
        std.log.info("  Max render targets: {}", .{self.max_render_targets});
    }
};

// Global capabilities instance
var global_capabilities: ?PlatformCapabilities = null;

pub fn getCapabilities() *const PlatformCapabilities {
    if (global_capabilities == null) {
        global_capabilities = PlatformCapabilities.detect();
    }
    return &global_capabilities.?;
}

pub fn refreshCapabilities() void {
    global_capabilities = PlatformCapabilities.detect();
}
