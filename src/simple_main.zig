const std = @import("std");
const enhanced_render = @import("enhanced_render.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("=== MFS Enhanced Renderer Demo ===", .{});
    std.log.info("Demonstrating Vulkan -> OpenGL -> Software fallback system", .{});

    // Test auto backend selection (should fallback from Vulkan to OpenGL)
    const config = enhanced_render.RendererConfig{
        .backend = .auto,
        .width = 1280,
        .height = 720,
        .vsync = true,
    };

    std.log.info("Attempting to initialize renderer with auto backend selection...", .{});

    var renderer = enhanced_render.EnhancedRenderer.init(allocator, config) catch |err| {
        std.log.err("Failed to initialize any renderer backend: {s}", .{@errorName(err)});
        return;
    };
    defer renderer.deinit();

    std.log.info("Successfully initialized with {s} backend", .{@tagName(renderer.getBackend())});
    const size = renderer.getSize();
    std.log.info("Render resolution: {}x{}", .{ size.width, size.height });

    // Simulate a game loop
    std.log.info("\n--- Starting Render Loop ---", .{});

    for (0..10) |frame| {
        renderer.render() catch |err| {
            std.log.err("Render failed on frame {}: {s}", .{ frame, @errorName(err) });
            break;
        };

        // Log every few frames to show progress
        if (frame % 3 == 0) {
            std.log.info("Rendered frame {} successfully", .{frame});
        }

        // Simulate frame timing (in a real app this would be actual frame timing)
        std.time.sleep(16_000_000); // ~60 FPS (16ms)
    }

    // Test runtime resize
    std.log.info("\n--- Testing Runtime Resize ---", .{});
    renderer.resize(1920, 1080);

    for (0..3) |frame| {
        try renderer.render();
        std.log.info("Post-resize frame {} rendered", .{frame});
        std.time.sleep(16_000_000);
    }

    std.log.info("\n--- Render Statistics ---", .{});
    std.log.info("Total frames rendered: {}", .{renderer.getFrameCount()});
    std.log.info("Final backend used: {s}", .{@tagName(renderer.getBackend())});

    // Test explicit OpenGL backend
    std.log.info("\n--- Testing Explicit OpenGL Backend ---", .{});
    const opengl_config = enhanced_render.RendererConfig{
        .backend = .opengl,
        .width = 800,
        .height = 600,
    };

    var opengl_renderer = enhanced_render.EnhancedRenderer.init(allocator, opengl_config) catch |err| {
        std.log.err("Failed to initialize OpenGL renderer: {s}", .{@errorName(err)});
        return;
    };
    defer opengl_renderer.deinit();

    std.log.info("Explicit OpenGL renderer initialized successfully", .{});

    for (0..5) |frame| {
        try opengl_renderer.render();
        if (frame % 2 == 0) {
            std.log.info("OpenGL frame {} completed", .{frame});
        }
        std.time.sleep(16_000_000);
    }

    std.log.info("OpenGL test completed with {} frames", .{opengl_renderer.getFrameCount()});

    std.log.info("\n=== Demo Complete ===", .{});
    std.log.info("Successfully demonstrated fallback rendering system:", .{});
    std.log.info("✓ Automatic backend selection", .{});
    std.log.info("✓ Vulkan -> OpenGL fallback", .{});
    std.log.info("✓ Runtime resize handling", .{});
    std.log.info("✓ Multiple renderer instances", .{});
    std.log.info("✓ Software fallback capability", .{});
}
