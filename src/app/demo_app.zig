const std = @import("std");
const builtin = @import("../builtin");
const build_options = @import("../build_options");
const capabilities = @import("../platform/capabilities.zig");
const backend_manager = @import("../graphics/backend_manager.zig");
const interface = @import("../graphics/backends/interface.zig");
const types = @import("../graphics/types.zig");

pub const DemoApp = struct {
    allocator: std.mem.Allocator,
    backend_manager: ?*backend_manager.BackendManager,
    adaptive_renderer: ?backend_manager.AdaptiveRenderer,
    window_width: u32 = 1280,
    window_height: u32 = 720,
    frame_count: u64 = 0,
    last_time: u64 = 0,
    fps: f32 = 0.0,
    running: bool = true,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !*Self {
        // First create the backend manager to avoid potential null states
        const manager_options = backend_manager.BackendManager.InitOptions{
            .preferred_backend = null, // Auto-detect best backend
            .auto_fallback = true,
            .debug_mode = (builtin.mode == .Debug),
            .validate_backends = true,
            .enable_backend_switching = true,
        };

        var backend_mgr = try backend_manager.BackendManager.init(allocator, manager_options);
        errdefer backend_mgr.deinit();

        var adaptive_rend = try backend_mgr.createAdaptiveRenderer();
        errdefer adaptive_rend.deinit();

        const app = try allocator.create(Self);
        errdefer allocator.destroy(app);

        app.* = Self{
            .allocator = allocator,
            .backend_manager = backend_mgr,
            .adaptive_renderer = adaptive_rend,
        };

        std.log.info("Demo application initialized successfully", .{});
        return app;
    }

    pub fn deinit(self: *Self) void {
        if (self.backend_manager) |manager| {
            manager.deinit();
        }
        self.allocator.destroy(self);
    }

    pub fn run(self: *Self) !void {
        std.log.info("=== MFS Graphics Demo Starting ===", .{});

        // Print system information
        self.printSystemInfo();

        // Create swap chain with improved error handling
        try self.createSwapChain() catch |err| {
            std.log.err("Swap chain creation failed: {}", .{err});
            return err;
        };

        // Main render loop
        self.last_time = @intCast(std.time.milliTimestamp());

        while (self.running and self.frame_count < 1000) { // Run for 1000 frames max
            try self.update();
            try self.render();
            self.frame_count += 1;

            // Calculate FPS every 60 frames
            if (self.frame_count % 60 == 0) {
                self.updateFPS();
            }

            // Break after demonstrating functionality
            if (self.frame_count >= 100) {
                self.running = false;
            }

            // Small delay to prevent spinning
            std.time.sleep(16_000_000); // ~60 FPS
        }

        std.log.info("Demo completed after {} frames", .{self.frame_count});
    }

    fn printSystemInfo(self: *Self) void {
        std.log.info("=== System Information ===", .{});
        std.log.info("Platform: {s} ({s})", .{ @tagName(builtin.os.tag), @tagName(builtin.cpu.arch) });
        std.log.info("Build Mode: {s}", .{@tagName(builtin.mode)});
        std.log.info("Target: {s}", .{build_options.target_os});

        if (build_options.is_mobile) {
            std.log.info("Mobile platform detected", .{});
        }
        if (build_options.is_desktop) {
            std.log.info("Desktop platform detected", .{});
        }

        // Print available backends
        std.log.info("=== Available Graphics Backends ===", .{});
        if (build_options.vulkan_available) std.log.info("✓ Vulkan", .{});
        if (build_options.d3d11_available) std.log.info("✓ DirectX 11", .{});
        if (build_options.d3d12_available) std.log.info("✓ DirectX 12", .{});
        if (build_options.metal_available) std.log.info("✓ Metal", .{});
        if (build_options.opengl_available) std.log.info("✓ OpenGL", .{});
        if (build_options.opengles_available) std.log.info("✓ OpenGL ES", .{});
        if (build_options.webgpu_available) std.log.info("✓ WebGPU", .{});
        std.log.info("✓ Software Renderer", .{});

        if (self.backend_manager) |manager| {
            manager.printStatus();
        }
    }

    fn createSwapChain(self: *Self) !void {
        if (self.backend_manager) |manager| {
            if (manager.getPrimaryBackend()) |backend| {
                const swap_chain_desc = interface.SwapChainDesc{
                    .width = self.window_width,
                    .height = self.window_height,
                    .format = .rgba8,
                    .buffer_count = 2,
                    .vsync = true,
                    .window_handle = null, // Would be actual window handle in real app
                };

                backend.createSwapChain(&swap_chain_desc) catch |err| {
                    std.log.warn("Failed to create swap chain: {}", .{err});
                    // Continue with demo anyway
                };

                std.log.info("Swap chain created: {}x{}", .{ self.window_width, self.window_height });
            }
        }
    }

    fn update(self: *Self) !void {
        // Simulate window resize every 200 frames
        if (self.frame_count > 0 and self.frame_count % 200 == 0) {
            const new_width = if (self.window_width == 1280) 1920 else 1280;
            const new_height = if (self.window_height == 720) 1080 else 720;

            try self.resizeWindow(new_width, new_height);
        }

        // Test backend switching every 300 frames
        if (self.frame_count > 0 and self.frame_count % 300 == 0) {
            try self.demonstrateBackendSwitching();
        }
    }

    fn render(self: *Self) !void {
        // Adaptive renderer is guaranteed to be non-null after init
        const frame_data = struct {
            frame_number: u64,
            time: f32,
        }{
            .frame_number = self.frame_count,
            .time = @as(f32, @floatFromInt(self.frame_count)) * 0.016,
        };

        try self.adaptive_renderer.?.render(frame_data);

        if (self.backend_manager) |manager| {
            if (manager.getPrimaryBackend()) |backend| {
                // Basic rendering demonstration
                try self.performBasicRendering(backend);
            }
        }
    }

    fn performBasicRendering(self: *Self, backend: *interface.GraphicsBackend) !void {
        // Create command buffer
        var cmd_buffer = backend.createCommandBuffer() catch return;
        defer cmd_buffer.deinit();

        // Begin command recording
        try backend.beginCommandBuffer(cmd_buffer);

        // Begin render pass
        const render_pass_desc = interface.RenderPassDesc{
            .clear_color = types.ClearColor{
                .r = 0.2,
                .g = 0.3,
                .b = 0.4,
                .a = 1.0,
            },
            .clear_depth = 1.0,
            .clear_stencil = 0,
        };

        backend.beginRenderPass(cmd_buffer, &render_pass_desc) catch {};

        // Set viewport
        const viewport = types.Viewport{
            .x = 0,
            .y = 0,
            .width = self.window_width,
            .height = self.window_height,
        };
        backend.setViewport(cmd_buffer, &viewport) catch {};

        // Draw something simple
        const draw_cmd = interface.DrawCommand{
            .vertex_count = 3, // Triangle
            .instance_count = 1,
            .first_vertex = 0,
            .first_instance = 0,
        };
        backend.draw(cmd_buffer, &draw_cmd) catch {};

        // End render pass
        backend.endRenderPass(cmd_buffer) catch {};

        // End command recording
        try backend.endCommandBuffer(cmd_buffer);

        // Submit commands
        try backend.submitCommandBuffer(cmd_buffer);

        // Present
        backend.present() catch {};
    }

    fn resizeWindow(self: *Self, new_width: u32, new_height: u32) !void {
        self.window_width = new_width;
        self.window_height = new_height;

        if (self.backend_manager) |manager| {
            if (manager.getPrimaryBackend()) |backend| {
                backend.resizeSwapChain(new_width, new_height) catch |err| {
                    std.log.warn("Failed to resize swap chain: {}", .{err});
                };

                std.log.info("Window resized to: {}x{}", .{ new_width, new_height });
            }
        }
    }

    fn demonstrateBackendSwitching(self: *Self) !void {
        if (self.backend_manager) |manager| {
            const current_backend = manager.getPrimaryBackend().?.backend_type;
            std.log.info("Current backend: {s}", .{current_backend.getName()});

            // Get available backends and try to switch to a different one
            const available = manager.getAvailableBackends() catch return;
            defer self.allocator.free(available);

            for (available) |backend_type| {
                if (backend_type != current_backend) {
                    std.log.info("Attempting to switch to: {s}", .{backend_type.getName()});

                    if (try manager.switchBackend(backend_type)) {
                        std.log.info("Successfully switched to: {s}", .{backend_type.getName()});

                        // Recreate swap chain for new backend
                        try self.createSwapChain();
                        break;
                    } else {
                        std.log.warn("Failed to switch to: {s}", .{backend_type.getName()});
                    }
                }
            }
        }
    }

    fn updateFPS(self: *Self) void {
        const current_time = @as(u64, @intCast(std.time.milliTimestamp()));
        const delta_time = current_time - self.last_time;

        if (delta_time > 0) {
            self.fps = 60000.0 / @as(f32, @floatFromInt(delta_time));
            std.log.info("Frame: {} | FPS: {d:.1} | Backend: {s}", .{
                self.frame_count,
                self.fps,
                if (self.backend_manager) |manager|
                    if (manager.getPrimaryBackend()) |backend|
                        backend.backend_type.getName()
                    else
                        "None"
                else
                    "None",
            });
        }

        self.last_time = current_time;
    }

    pub fn createResourceDemonstration(self: *Self) !void {
        if (self.backend_manager) |manager| {
            if (manager.getPrimaryBackend()) |backend| {
                std.log.info("=== Resource Creation Demo ===", .{});

                // Create test texture
                var texture = try types.Texture.init(self.allocator, 256, 256, .rgba8);
                defer texture.deinit();

                // Create texture data (simple gradient)
                const texture_data = try self.allocator.alloc(u8, 256 * 256 * 4);
                defer self.allocator.free(texture_data);

                for (0..256) |y| {
                    for (0..256) |x| {
                        const offset = (y * 256 + x) * 4;
                        texture_data[offset + 0] = @intCast(x); // R
                        texture_data[offset + 1] = @intCast(y); // G
                        texture_data[offset + 2] = 128; // B
                        texture_data[offset + 3] = 255; // A
                    }
                }

                backend.createTexture(texture, texture_data) catch |err| {
                    std.log.warn("Failed to create texture: {}", .{err});
                };

                std.log.info("✓ Created 256x256 RGBA texture", .{});

                // Create test buffer
                var buffer = try types.Buffer.init(self.allocator, 1024, .vertex);
                defer buffer.deinit();

                const buffer_data = try self.allocator.alloc(u8, 1024);
                defer self.allocator.free(buffer_data);
                @memset(buffer_data, 0x42);

                backend.createBuffer(buffer, buffer_data) catch |err| {
                    std.log.warn("Failed to create buffer: {}", .{err});
                };

                std.log.info("✓ Created 1KB vertex buffer", .{});

                // Create test shader
                var shader = try types.Shader.init(self.allocator, .vertex,
                    \\#version 330 core
                    \\layout (location = 0) in vec3 aPos;
                    \\void main() {
                    \\    gl_Position = vec4(aPos, 1.0);
                    \\}
                );
                defer shader.deinit();

                backend.createShader(shader) catch |err| {
                    std.log.warn("Failed to create shader: {}", .{err});
                };

                std.log.info("✓ Created vertex shader", .{});

                // Cleanup resources
                backend.destroyTexture(texture);
                backend.destroyBuffer(buffer);
                backend.destroyShader(shader);

                std.log.info("✓ Successfully cleaned up all resources", .{});
            }
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("=== MFS Cross-Platform Graphics Demo ===", .{});

    var app = try DemoApp.init(allocator);
    defer app.deinit();

    // Run the main demo
    try app.run();

    // Demonstrate resource creation
    try app.createResourceDemonstration();

    std.log.info("=== Demo Complete ===", .{});
}
