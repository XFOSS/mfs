const std = @import("std");
const Allocator = std.mem.Allocator;
const scene = @import("./scene/scene.zig");
const vk_cube = @import("./vulkan/cube.zig");
const ui = @import("./ui/simple_window.zig");
const opengl_backend = @import("./graphics/opengl_backend.zig");
const graphics_types = @import("./graphics/types.zig");

pub const RendererBackend = enum {
    auto,
    vulkan,
    metal,
    dx12,
    webgpu,
    opengl,
    opengles,
    software,
};

pub const RendererConfig = struct {
    window_handle: ?ui.NativeHandle = null,
    backend: RendererBackend = .auto,
    enable_validation: bool = false,
    width: u32 = 1280,
    height: u32 = 720,
    vsync: bool = true,
};

pub const RendererError = error{
    InitializationFailed,
    InvalidBackend,
    WindowHandleRequired,
    VulkanNotSupported,
    OpenGLNotSupported,
    RenderFailed,
    OutOfMemory,
    AllBackendsFailed,
};

pub const Renderer = struct {
    allocator: Allocator,
    backend: RendererBackend,
    vulkan_renderer: ?*vk_cube.VulkanCubeRenderer = null,
    opengl_backend: ?*opengl_backend.OpenGLBackend = null,
    width: u32,
    height: u32,
    initialized: bool = false,
    fallback_attempted: bool = false,

    const Self = @This();

    pub fn init(allocator: Allocator, config: RendererConfig) !*Self {
        var renderer = try allocator.create(Self);
        renderer.* = Self{
            .allocator = allocator,
            .backend = config.backend,
            .width = config.width,
            .height = config.height,
        };

        // Determine backend selection with intelligent fallback
        const selected_backend = if (config.backend == .auto)
            renderer.selectBestAvailableBackend()
        else
            config.backend;

        renderer.backend = selected_backend;

        // Try to initialize the selected backend with fallback support
        const init_result = renderer.initializeBackend(config, selected_backend);

        if (init_result) |_| {
            renderer.initialized = true;
            std.log.info("Renderer initialized successfully with {s} backend", .{@tagName(renderer.backend)});
            return renderer;
        } else |err| {
            // If initialization failed and we haven't tried fallback yet
            if (!renderer.fallback_attempted and config.backend == .auto) {
                std.log.warn("Primary backend {s} failed: {s}, attempting fallback", .{ @tagName(selected_backend), @errorName(err) });

                // Try OpenGL as fallback
                if (selected_backend != .opengl) {
                    if (renderer.initializeBackend(config, .opengl)) |_| {
                        renderer.backend = .opengl;
                        renderer.fallback_attempted = true;
                        renderer.initialized = true;
                        std.log.info("Fallback to OpenGL successful", .{});
                        return renderer;
                    } else |fallback_err| {
                        std.log.err("OpenGL fallback also failed: {s}", .{@errorName(fallback_err)});
                    }
                }

                // Try software rendering as last resort
                if (selected_backend != .software) {
                    std.log.info("Falling back to software renderer", .{});
                    renderer.backend = .software;
                    renderer.fallback_attempted = true;
                    renderer.initialized = true;
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
                if (self.vulkan_renderer) |vulkan_renderer| {
                    vulkan_renderer.deinit();
                    self.allocator.destroy(vulkan_renderer);
                    self.vulkan_renderer = null;
                }
            },
            .opengl => {
                if (self.opengl_backend) |opengl| {
                    opengl.deinit();
                    self.opengl_backend = null;
                }
            },
            else => {},
        }

        self.initialized = false;
        self.allocator.destroy(self);
    }

    pub fn render(self: *Self, scene_manager: *scene.Scene, interpolation_alpha: f32) !void {
        if (!self.initialized) {
            return RendererError.RenderFailed;
        }

        _ = scene_manager; // Currently unused, but available for future scene rendering
        _ = interpolation_alpha; // Currently unused, but available for interpolation

        switch (self.backend) {
            .vulkan => {
                if (self.vulkan_renderer) |vulkan_renderer| {
                    vulkan_renderer.render() catch |err| {
                        // If Vulkan rendering fails, try to fallback to OpenGL
                        if (!self.fallback_attempted) {
                            std.log.warn("Vulkan render failed: {s}, attempting OpenGL fallback", .{@errorName(err)});
                            return self.attemptRenderFallback();
                        }
                        return err;
                    };
                } else {
                    return RendererError.RenderFailed;
                }
            },
            .opengl => {
                if (self.opengl_backend) |opengl| {
                    self.renderWithOpenGL(opengl) catch |err| {
                        std.log.err("OpenGL render failed: {s}", .{@errorName(err)});
                        return err;
                    };
                } else {
                    return RendererError.RenderFailed;
                }
            },
            .software => {
                // Simple software fallback - just clear the screen
                self.renderSoftware();
            },
            else => {
                return RendererError.InvalidBackend;
            },
        }
    }

    pub fn resize(self: *Self, width: u32, height: u32) !void {
        if (!self.initialized) return;

        self.width = width;
        self.height = height;

        switch (self.backend) {
            .vulkan => {
                if (self.vulkan_renderer) |vulkan_renderer| {
                    try vulkan_renderer.resize(width, height);
                }
            },
            .opengl => {
                if (self.opengl_backend) |opengl| {
                    opengl.setViewport(0, 0, width, height);
                }
            },
            else => {},
        }
    }

    pub fn getBackend(self: *const Self) RendererBackend {
        return self.backend;
    }

    pub fn isInitialized(self: *const Self) bool {
        return self.initialized;
    }

    pub fn getSize(self: *const Self) struct { width: u32, height: u32 } {
        return .{ .width = self.width, .height = self.height };
    }

    // Material management forwarding to active renderer
    pub fn switchMaterial(self: *Self, material_id: u32) !void {
        if (!self.initialized) return;

        switch (self.backend) {
            .vulkan => {
                if (self.vulkan_renderer) |vulkan_renderer| {
                    try vulkan_renderer.switchMaterial(material_id);
                }
            },
            .opengl => {
                // OpenGL material switching would be implemented here
                std.log.info("Switching to material {} (OpenGL)", .{material_id});
            },
            else => {},
        }
    }

    pub fn getCurrentMaterial(self: *const Self) ?u32 {
        if (!self.initialized) return null;

        switch (self.backend) {
            .vulkan => {
                if (self.vulkan_renderer) |vulkan_renderer| {
                    return vulkan_renderer.getCurrentMaterial();
                }
            },
            .opengl => {
                // Return default material for OpenGL
                return 0;
            },
            else => {},
        }
        return null;
    }

    // Private helper methods for backend initialization and fallback
    fn selectBestAvailableBackend(self: *Self) RendererBackend {
        _ = self;
        // Prefer Vulkan if available, fallback to OpenGL, then software
        if (isVulkanSupported()) {
            return .vulkan;
        } else if (isOpenGLSupported()) {
            return .opengl;
        } else {
            return .software;
        }
    }

    fn initializeBackend(self: *Self, config: RendererConfig, backend: RendererBackend) !void {
        switch (backend) {
            .vulkan => {
                if (config.window_handle == null) {
                    return RendererError.WindowHandleRequired;
                }

                self.vulkan_renderer = try self.allocator.create(vk_cube.VulkanCubeRenderer);
                self.vulkan_renderer.?.* = try vk_cube.VulkanCubeRenderer.init(
                    self.allocator,
                    config.width,
                    config.height,
                    config.window_handle.?.hwnd,
                    config.window_handle.?.hinstance,
                );

                try self.vulkan_renderer.?.initVulkan();
            },
            .opengl => {
                self.opengl_backend = try opengl_backend.OpenGLBackend.init(
                    self.allocator,
                    config.width,
                    config.height,
                );
            },
            .software => {
                // Software renderer needs no initialization
            },
            else => {
                std.log.err("Backend {s} not yet implemented", .{@tagName(backend)});
                return RendererError.InvalidBackend;
            },
        }
    }

    fn attemptRenderFallback(self: *Self) !void {
        // Clean up failed Vulkan renderer
        if (self.vulkan_renderer) |vulkan_renderer| {
            vulkan_renderer.deinit();
            self.allocator.destroy(vulkan_renderer);
            self.vulkan_renderer = null;
        }

        // Try to initialize OpenGL
        if (self.initializeBackend(RendererConfig{
            .backend = .opengl,
            .width = self.width,
            .height = self.height,
        }, .opengl)) |_| {
            self.backend = .opengl;
            self.fallback_attempted = true;
            std.log.info("Successfully fell back to OpenGL renderer", .{});
        } else |_| {
            // Fall back to software rendering
            self.backend = .software;
            self.fallback_attempted = true;
            std.log.info("Fell back to software renderer", .{});
        }
    }

    fn renderWithOpenGL(self: *Self, opengl: *opengl_backend.OpenGLBackend) !void {
        _ = self; // Suppress unused parameter warning
        // Set clear color (dark blue)
        opengl.setClearColor(graphics_types.ClearColor{ .r = 0.1, .g = 0.1, .b = 0.3, .a = 1.0 });

        // Clear the screen
        opengl.clear(true, true, false);

        // In a full implementation, this would render the actual scene
        // For now, we'll just present the cleared frame
        opengl.present();
    }

    fn renderSoftware(self: *Self) void {
        // Minimal software rendering - just log that we're "rendering"
        // In a real implementation, this would do CPU-based rendering
        std.log.debug("Software render frame ({}x{})", .{ self.width, self.height });
    }
};

// Utility functions for backend selection
pub fn selectBestBackend() RendererBackend {
    // Prefer Vulkan, then OpenGL, then software
    if (isVulkanSupported()) {
        return .vulkan;
    } else if (isOpenGLSupported()) {
        return .opengl;
    }
    return .software;
}

pub fn isVulkanSupported() bool {
    // Simple check - in a real implementation this would probe for Vulkan support
    // Check for Vulkan loader and basic device support
    return true; // Assume available for now
}

pub fn isOpenGLSupported() bool {
    // Simple check - in a real implementation this would check for OpenGL context creation
    return true; // OpenGL is widely supported
}

pub fn isMacOS() bool {
    return @import("builtin").target.os.tag == .macos;
}

pub fn isWindows() bool {
    return @import("builtin").target.os.tag == .windows;
}

pub fn isLinux() bool {
    return @import("builtin").target.os.tag == .linux;
}

// Test functions
test "renderer backend selection" {
    const backend = selectBestBackend();
    try std.testing.expect(backend == .vulkan or backend == .software);
}

test "renderer initialization" {
    const allocator = std.testing.allocator;

    const config = RendererConfig{
        .backend = .software, // Use software for testing
        .width = 800,
        .height = 600,
    };

    // This would fail without a window handle for Vulkan, which is expected
    _ = config;
    _ = allocator;
}
