const std = @import("std");
const Allocator = std.mem.Allocator;
const working_vulkan = @import("./vulkan/working_vulkan.zig");
const vulkan_config = @import("./graphics/vulkan_config.zig");

pub const RendererError = error{
    InitializationFailed,
    VulkanNotSupported,
    OpenGLNotSupported,
    RenderFailed,
    OutOfMemory,
    AllBackendsFailed,
    WindowHandleRequired,
};

pub const RendererBackend = enum {
    auto,
    vulkan,
    opengl,
    software,
};

pub const RendererConfig = struct {
    backend: RendererBackend = .auto,
    width: u32 = 1280,
    height: u32 = 720,
    vsync: bool = true,
    enable_validation: bool = false,
    window_handle: ?WindowHandle = null,
};

pub const WindowHandle = struct {
    hwnd: ?*anyopaque = null,
    hinstance: ?*anyopaque = null,
};

pub const SimpleOpenGLRenderer = struct {
    width: u32,
    height: u32,
    frame_count: u64 = 0,
    initialized: bool = false,

    pub fn init(width: u32, height: u32) SimpleOpenGLRenderer {
        return SimpleOpenGLRenderer{
            .width = width,
            .height = height,
            .initialized = true,
        };
    }

    pub fn deinit(self: *SimpleOpenGLRenderer) void {
        self.initialized = false;
    }

    pub fn render(self: *SimpleOpenGLRenderer) !void {
        if (!self.initialized) return RendererError.RenderFailed;

        self.frame_count += 1;

        // Simulate OpenGL rendering operations
        std.log.debug("OpenGL Frame {}: Clear(0.1, 0.1, 0.3, 1.0)", .{self.frame_count});
        std.log.debug("OpenGL Frame {}: DrawTriangles(vertices=3)", .{self.frame_count});
        std.log.debug("OpenGL Frame {}: SwapBuffers()", .{self.frame_count});
    }

    pub fn resize(self: *SimpleOpenGLRenderer, width: u32, height: u32) void {
        if (!self.initialized) return;

        self.width = width;
        self.height = height;
        std.log.info("OpenGL viewport resized to {}x{}", .{ width, height });
    }

    pub fn getFrameCount(self: *const SimpleOpenGLRenderer) u64 {
        return self.frame_count;
    }
};

pub const SoftwareRenderer = struct {
    width: u32,
    height: u32,
    frame_count: u64 = 0,
    initialized: bool = false,

    pub fn init(width: u32, height: u32) SoftwareRenderer {
        return SoftwareRenderer{
            .width = width,
            .height = height,
            .initialized = true,
        };
    }

    pub fn deinit(self: *SoftwareRenderer) void {
        self.initialized = false;
    }

    pub fn render(self: *SoftwareRenderer) !void {
        if (!self.initialized) return RendererError.RenderFailed;

        self.frame_count += 1;
        std.log.debug("Software Frame {}: CPU rasterization {}x{}", .{ self.frame_count, self.width, self.height });
    }

    pub fn resize(self: *SoftwareRenderer, width: u32, height: u32) void {
        if (!self.initialized) return;

        self.width = width;
        self.height = height;
        std.log.info("Software renderer resized to {}x{}", .{ width, height });
    }

    pub fn getFrameCount(self: *const SoftwareRenderer) u64 {
        return self.frame_count;
    }
};

pub const EnhancedRenderer = struct {
    allocator: Allocator,
    backend: RendererBackend,
    width: u32,
    height: u32,
    initialized: bool = false,
    fallback_attempted: bool = false,

    // Backend-specific renderers
    vulkan_renderer: ?*working_vulkan.WorkingVulkanRenderer = null,
    opengl_renderer: ?SimpleOpenGLRenderer = null,
    software_renderer: ?SoftwareRenderer = null,

    const Self = @This();

    pub fn init(allocator: Allocator, config: RendererConfig) !*Self {
        var renderer = try allocator.create(Self);
        renderer.* = Self{
            .allocator = allocator,
            .backend = config.backend,
            .width = config.width,
            .height = config.height,
        };

        const selected_backend = if (config.backend == .auto)
            renderer.selectBestBackend()
        else
            config.backend;

        if (renderer.initializeBackend(selected_backend, config)) |_| {
            renderer.backend = selected_backend;
            renderer.initialized = true;
            std.log.info("Renderer initialized with {s} backend", .{@tagName(selected_backend)});
            return renderer;
        } else |err| {
            std.log.warn("Primary backend {s} failed: {s}", .{ @tagName(selected_backend), @errorName(err) });

            if (!renderer.fallback_attempted and config.backend == .auto) {
                if (renderer.attemptFallback(config)) |fallback_backend| {
                    renderer.backend = fallback_backend;
                    renderer.fallback_attempted = true;
                    renderer.initialized = true;
                    std.log.info("Successfully fell back to {s} backend", .{@tagName(fallback_backend)});
                    return renderer;
                }
            }

            allocator.destroy(renderer);
            return RendererError.AllBackendsFailed;
        }
    }

    pub fn deinit(self: *Self) void {
        if (!self.initialized) return;

        switch (self.backend) {
            .vulkan => {
                if (self.vulkan_renderer) |vulkan| {
                    vulkan.deinit();
                    self.vulkan_renderer = null;
                }
            },
            .opengl => {
                if (self.opengl_renderer) |*opengl| {
                    opengl.deinit();
                    self.opengl_renderer = null;
                }
            },
            .software => {
                if (self.software_renderer) |*software| {
                    software.deinit();
                    self.software_renderer = null;
                }
            },
            .auto => {},
        }

        self.initialized = false;
        self.allocator.destroy(self);
    }

    pub fn render(self: *Self) !void {
        if (!self.initialized) return RendererError.RenderFailed;

        switch (self.backend) {
            .vulkan => {
                if (self.vulkan_renderer) |vulkan| {
                    try vulkan.render();
                } else {
                    return RendererError.RenderFailed;
                }
            },
            .opengl => {
                if (self.opengl_renderer) |*opengl| {
                    try opengl.render();
                } else {
                    return RendererError.RenderFailed;
                }
            },
            .software => {
                if (self.software_renderer) |*software| {
                    try software.render();
                } else {
                    return RendererError.RenderFailed;
                }
            },
            .auto => {
                std.log.warn("Auto backend should be resolved during init", .{});
                return RendererError.RenderFailed;
            },
        }
    }

    pub fn resize(self: *Self, width: u32, height: u32) void {
        if (!self.initialized) return;

        self.width = width;
        self.height = height;

        switch (self.backend) {
            .vulkan => {
                if (self.vulkan_renderer) |vulkan| {
                    vulkan.resize(width, height) catch |err| {
                        std.log.warn("Vulkan resize failed: {s}", .{@errorName(err)});
                    };
                }
            },
            .opengl => {
                if (self.opengl_renderer) |*opengl| {
                    opengl.resize(width, height);
                }
            },
            .software => {
                if (self.software_renderer) |*software| {
                    software.resize(width, height);
                }
            },
            .auto => {},
        }
    }

    pub fn getBackend(self: *const Self) RendererBackend {
        return self.backend;
    }

    pub fn getSize(self: *const Self) struct { width: u32, height: u32 } {
        return .{ .width = self.width, .height = self.height };
    }

    pub fn getFrameCount(self: *const Self) u64 {
        switch (self.backend) {
            .vulkan => {
                if (self.vulkan_renderer) |vulkan| {
                    return vulkan.getFrameCount();
                }
            },
            .opengl => {
                if (self.opengl_renderer) |*opengl| {
                    return opengl.getFrameCount();
                }
            },
            .software => {
                if (self.software_renderer) |*software| {
                    return software.getFrameCount();
                }
            },
            .auto => {},
        }
        return 0;
    }

    fn selectBestBackend(self: *Self) RendererBackend {
        // Prefer Vulkan for performance, then OpenGL, then software
        if (isVulkanSupported(self.allocator)) {
            return .vulkan;
        } else if (isOpenGLSupported()) {
            return .opengl;
        }
        return .software;
    }

    fn initializeBackend(self: *Self, backend: RendererBackend, config: RendererConfig) !void {
        switch (backend) {
            .vulkan => {
                if (!isVulkanSupported(self.allocator)) {
                    return RendererError.VulkanNotSupported;
                }
                if (config.window_handle == null) {
                    std.log.warn("Vulkan requires window handle, falling back", .{});
                    return RendererError.WindowHandleRequired;
                }
                self.vulkan_renderer = working_vulkan.WorkingVulkanRenderer.init(
                    self.allocator,
                    self.width,
                    self.height,
                    config.window_handle.?.hwnd,
                    config.window_handle.?.hinstance,
                    config.enable_validation,
                ) catch |err| {
                    std.log.warn("Vulkan initialization failed: {s}", .{@errorName(err)});
                    return err;
                };
            },
            .opengl => {
                if (!isOpenGLSupported()) {
                    return RendererError.OpenGLNotSupported;
                }
                self.opengl_renderer = SimpleOpenGLRenderer.init(self.width, self.height);
            },
            .software => {
                self.software_renderer = SoftwareRenderer.init(self.width, self.height);
            },
            .auto => unreachable, // Should be resolved before calling this function
        }
    }

    fn attemptFallback(self: *Self, config: RendererConfig) ?RendererBackend {
        // Try OpenGL first
        if (self.initializeBackend(.opengl, config)) |_| {
            std.log.info("Fallback to OpenGL successful", .{});
            return .opengl;
        } else |_| {
            std.log.info("OpenGL fallback failed, trying software renderer", .{});
        }

        // Try software as last resort
        if (self.initializeBackend(.software, config)) |_| {
            std.log.info("Fallback to software renderer successful", .{});
            return .software;
        } else |_| {
            std.log.err("All fallback attempts failed", .{});
        }

        return null;
    }
};

// Utility functions
pub fn isVulkanSupported(allocator: Allocator) bool {
    const config = vulkan_config.detectVulkanAvailability(allocator);
    const runtime_available = vulkan_config.isVulkanRuntimeAvailable();

    if (config.available and runtime_available) {
        std.log.info("Vulkan is fully available (SDK + Runtime)", .{});
        return true;
    } else if (runtime_available) {
        std.log.info("Vulkan runtime available but SDK incomplete", .{});
        return false;
    } else {
        std.log.info("Vulkan not available", .{});
        return false;
    }
}

pub fn isOpenGLSupported() bool {
    // In a real implementation, this would try to create an OpenGL context
    return true; // OpenGL is widely supported
}

// Test function
pub fn testEnhancedRenderer(allocator: Allocator) !void {
    std.log.info("Testing Enhanced Renderer with OpenGL fallback...", .{});

    const config = RendererConfig{
        .backend = .auto,
        .width = 1280,
        .height = 720,
    };

    var renderer = try EnhancedRenderer.init(allocator, config);
    defer renderer.deinit();

    std.log.info("Active backend: {s}", .{@tagName(renderer.getBackend())});

    // Render some frames
    for (0..3) |frame| {
        std.log.info("Rendering frame {}", .{frame});
        try renderer.render();
    }

    // Test resize
    renderer.resize(1920, 1080);
    try renderer.render();

    std.log.info("Enhanced renderer test completed. Total frames: {}", .{renderer.getFrameCount()});
}
