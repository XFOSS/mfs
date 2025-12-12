const std = @import("std");
const testing = std.testing;
const backend = @import("vulkan_backend.zig");
const vk = backend.vk;
const vulkan_backend = @import("vulkan_backend.zig");
const VulkanBackend = vulkan_backend.VulkanBackend;

/// Mock window handle for testing
const MockWindow = struct {
    width: u32 = 800,
    height: u32 = 600,
};

test "VulkanBackend initialization" {
    const allocator = testing.allocator;

    // Create mock window
    var window = MockWindow{};

    // Create backend config
    const config = vulkan_backend.BackendConfig{
        .app_name = "VulkanBackendTest",
        .engine_name = "TestEngine",
        .validation = .{
            .enabled = true,
            .debug_callback = mockDebugCallback,
        },
        .device_requirements = .{
            .graphics_queue = true,
            .compute_queue = true,
            .transfer_queue = true,
            .present_queue = true,
            .ray_tracing = false,
            .mesh_shading = false,
            .descriptor_indexing = true,
        },
    };

    // Initialize backend
    var backend = try VulkanBackend.init(allocator, config, &window);
    defer backend.deinit();

    // Verify initialization
    try testing.expect(backend.instance != .null_handle);
    try testing.expect(backend.physical_device != .null_handle);
    try testing.expect(backend.device != .null_handle);
    try testing.expect(backend.graphics_queue != .null_handle);
    try testing.expect(backend.transfer_queue != .null_handle);
    try testing.expect(backend.present_queue != .null_handle);
    try testing.expect(backend.compute_queue != null);
    try testing.expect(backend.surface != .null_handle);
}

test "VulkanBackend buffer creation" {
    const allocator = testing.allocator;
    var window = MockWindow{};
    const config = vulkan_backend.BackendConfig{
        .app_name = "VulkanBackendTest",
        .engine_name = "TestEngine",
    };

    var backend = try VulkanBackend.init(allocator, config, &window);
    defer backend.deinit();

    // Create vertex buffer
    const vertex_buffer = try backend.createBuffer(
        1024,
        .{ .vertex_buffer_bit = true },
        .{ .device_local_bit = true },
    );
    defer {
        backend.device.destroyBuffer(vertex_buffer.buffer, null);
        backend.memory_manager.free(&vertex_buffer.memory);
    }

    // Verify buffer creation
    try testing.expect(vertex_buffer.buffer != .null_handle);
    try testing.expect(vertex_buffer.memory.size >= 1024);
    try testing.expect(vertex_buffer.memory.memory != .null_handle);
}

test "VulkanBackend image creation" {
    const allocator = testing.allocator;
    var window = MockWindow{};
    const config = vulkan_backend.BackendConfig{
        .app_name = "VulkanBackendTest",
        .engine_name = "TestEngine",
    };

    var backend = try VulkanBackend.init(allocator, config, &window);
    defer backend.deinit();

    // Create texture image
    const texture = try backend.createImage(
        256,
        256,
        .r8g8b8a8_unorm,
        .{ .sampled_bit = true, .transfer_dst_bit = true },
        .{ .device_local_bit = true },
    );
    defer {
        backend.device.destroyImage(texture.image, null);
        backend.memory_manager.free(&texture.memory);
    }

    // Verify image creation
    try testing.expect(texture.image != .null_handle);
    try testing.expect(texture.memory.memory != .null_handle);
}

test "VulkanBackend memory stats" {
    const allocator = testing.allocator;
    var window = MockWindow{};
    const config = vulkan_backend.BackendConfig{
        .app_name = "VulkanBackendTest",
        .engine_name = "TestEngine",
    };

    var backend = try VulkanBackend.init(allocator, config, &window);
    defer backend.deinit();

    // Create some resources
    const buffer1 = try backend.createBuffer(
        1024,
        .{ .vertex_buffer_bit = true },
        .{ .device_local_bit = true },
    );
    defer {
        backend.device.destroyBuffer(buffer1.buffer, null);
        backend.memory_manager.free(&buffer1.memory);
    }

    const buffer2 = try backend.createBuffer(
        2048,
        .{ .uniform_buffer_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
    );
    defer {
        backend.device.destroyBuffer(buffer2.buffer, null);
        backend.memory_manager.free(&buffer2.memory);
    }

    // Check memory stats
    const stats = backend.getMemoryStats();
    try testing.expect(stats.total_allocated >= 3072);
    try testing.expect(stats.allocation_count == 2);
    try testing.expect(stats.current_usage >= 3072);
    try testing.expect(stats.peak_usage >= 3072);
}

fn mockDebugCallback(
    message_severity: vk.DebugUtilsMessageSeverityFlagsEXT,
    message_type: vk.DebugUtilsMessageTypeFlagsEXT,
    p_callback_data: *const vk.DebugUtilsMessengerCallbackDataEXT,
    p_user_data: ?*anyopaque,
) callconv(.C) vk.Bool32 {
    _ = message_severity;
    _ = message_type;
    _ = p_callback_data;
    _ = p_user_data;
    return vk.FALSE;
}
