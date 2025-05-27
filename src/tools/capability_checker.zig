const std = @import("std");
const capabilities = @import("../platform/capabilities.zig");
const backend_manager = @import("../graphics/backend_manager.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("=== MFS Graphics Capability Checker ===", .{});

    // Initialize capabilities detection
    try capabilities.initCapabilities(allocator);
    defer capabilities.deinitCapabilities();

    const caps = capabilities.getCapabilities();

    // Print detailed capabilities
    caps.printCapabilities();

    std.log.info("\n=== Backend Manager Test ===", .{});

    // Test backend manager
    const manager_options = backend_manager.BackendManager.InitOptions{
        .auto_fallback = true,
        .debug_mode = true,
        .validate_backends = true,
    };

    var manager = backend_manager.BackendManager.init(allocator, manager_options) catch |err| {
        std.log.err("Failed to initialize backend manager: {}", .{err});
        return;
    };
    defer manager.deinit();

    manager.printStatus();

    // Test available backends
    const available_backends = manager.getAvailableBackends() catch &[_]capabilities.GraphicsBackend{};
    defer allocator.free(available_backends);

    std.log.info("\n=== Available Backends ===", .{});
    for (available_backends) |backend_type| {
        std.log.info("  ✓ {s}", .{backend_type.getName()});

        // Test features
        if (backend_type.supportsCompute()) {
            std.log.info("    - Compute shaders supported", .{});
        }
        if (backend_type.supportsRayTracing()) {
            std.log.info("    - Ray tracing supported", .{});
        }
        if (backend_type.isHardwareAccelerated()) {
            std.log.info("    - Hardware accelerated", .{});
        }
    }

    if (manager.getPrimaryBackend()) |backend| {
        const info = backend.getBackendInfo();
        std.log.info("\n=== Primary Backend Details ===", .{});
        std.log.info("Name: {s}", .{info.name});
        std.log.info("Version: {s}", .{info.version});
        std.log.info("Vendor: {s}", .{info.vendor});
        std.log.info("Device: {s}", .{info.device_name});
        std.log.info("Max texture size: {d}x{d}", .{ info.max_texture_size, info.max_texture_size });
        std.log.info("Max render targets: {d}", .{info.max_render_targets});
        std.log.info("Max vertex attributes: {d}", .{info.max_vertex_attributes});
        std.log.info("Compute support: {}", .{info.supports_compute});
        std.log.info("Ray tracing support: {}", .{info.supports_raytracing});
        std.log.info("Mesh shaders support: {}", .{info.supports_mesh_shaders});
    }

    std.log.info("\n=== Capability Check Complete ===", .{});
}
