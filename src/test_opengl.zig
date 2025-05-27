const std = @import("std");

pub const SimpleOpenGLRenderer = struct {
    width: u32,
    height: u32,
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

    pub fn render(self: *SimpleOpenGLRenderer) void {
        if (!self.initialized) return;

        // Simulate OpenGL rendering
        std.log.info("OpenGL render frame {}x{}", .{ self.width, self.height });

        // Simulate clear color (dark blue background)
        // In real OpenGL: glClearColor(0.1, 0.1, 0.3, 1.0);
        // In real OpenGL: glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

        // Simulate drawing a triangle
        // In real OpenGL this would bind VAO, use shader program, and call glDrawArrays
        std.log.debug("Drawing triangle with OpenGL fallback renderer", .{});
    }

    pub fn resize(self: *SimpleOpenGLRenderer, width: u32, height: u32) void {
        if (!self.initialized) return;

        self.width = width;
        self.height = height;

        // In real OpenGL: glViewport(0, 0, width, height);
        std.log.info("OpenGL viewport resized to {}x{}", .{ width, height });
    }

    pub fn isSupported() bool {
        // In a real implementation, this would check for OpenGL context creation
        // For now, assume OpenGL is always available as a fallback
        return true;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    _ = allocator;

    std.log.info("Testing OpenGL fallback renderer...", .{});

    var renderer = SimpleOpenGLRenderer.init(1280, 720);
    defer renderer.deinit();

    if (!SimpleOpenGLRenderer.isSupported()) {
        std.log.err("OpenGL not supported", .{});
        return;
    }

    std.log.info("OpenGL renderer initialized successfully", .{});

    // Simulate a few render frames
    for (0..5) |frame| {
        std.log.info("Frame {}", .{frame});
        renderer.render();
    }

    // Test resize
    renderer.resize(1920, 1080);
    renderer.render();

    std.log.info("OpenGL fallback test completed successfully", .{});
}
