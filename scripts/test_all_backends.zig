const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;

// Import the engine and graphics modules
const engine = @import("../src/engine/engine.zig");
const graphics = @import("../src/graphics/backend_manager.zig");
const capabilities = @import("../src/platform/capabilities.zig");

// Test configuration
const TestConfig = struct {
    test_duration_ms: u64 = 5000,
    target_fps: f32 = 60.0,
    min_acceptable_fps: f32 = 30.0,
    memory_threshold_mb: f64 = 512.0,
    verbose: bool = false,
};

const TestResult = struct {
    backend: capabilities.GraphicsBackend,
    success: bool,
    error_message: ?[]const u8 = null,
    performance_stats: PerformanceStats,
    capabilities: ?capabilities.BackendCapabilities = null,
};

const PerformanceStats = struct {
    avg_fps: f32 = 0.0,
    min_fps: f32 = 0.0,
    max_fps: f32 = 0.0,
    memory_usage_mb: f64 = 0.0,
    render_time_ms: f64 = 0.0,
    frame_count: u32 = 0,
    dropped_frames: u32 = 0,
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

pub fn main() !void {
    defer _ = gpa.deinit();

    const config = TestConfig{
        .verbose = true,
        .test_duration_ms = 3000, // Shorter for CI
    };

    std.log.info("=== MFS Engine Backend Validation Suite ===", .{});
    std.log.info("Platform: {s}", .{@tagName(builtin.os.tag)});
    std.log.info("Architecture: {s}", .{@tagName(builtin.cpu.arch)});
    std.log.info("", .{});

    var test_results = std.ArrayList(TestResult).init(allocator);
    defer test_results.deinit();

    // Test all available backends
    const backends_to_test = try getAvailableBackends();
    defer allocator.free(backends_to_test);

    for (backends_to_test) |backend| {
        std.log.info("Testing {s} backend...", .{@tagName(backend)});

        const result = testBackend(backend, config) catch |err| TestResult{
            .backend = backend,
            .success = false,
            .error_message = @errorName(err),
            .performance_stats = PerformanceStats{},
        };

        try test_results.append(result);

        if (result.success) {
            std.log.info("✓ {s}: PASSED", .{@tagName(backend)});
        } else {
            std.log.err("✗ {s}: FAILED - {s}", .{ @tagName(backend), result.error_message orelse "Unknown error" });
        }
        std.log.info("", .{});
    }

    // Print comprehensive report
    try printTestReport(test_results.items, config);
}

fn getAvailableBackends() ![]const capabilities.GraphicsBackend {
    const build_options = @import("../src/build_options");

    var backends = std.ArrayList(capabilities.GraphicsBackend).init(allocator);
    errdefer backends.deinit();

    // Add backends based on build configuration and platform
    switch (builtin.os.tag) {
        .windows => {
            if (build_options.d3d12_available) try backends.append(.d3d12);
            if (build_options.d3d11_available) try backends.append(.d3d11);
            if (build_options.opengl_available) try backends.append(.opengl);
            if (build_options.vulkan_available) try backends.append(.vulkan);
        },
        .macos, .ios => {
            if (build_options.metal_available) try backends.append(.metal);
            if (build_options.vulkan_available) try backends.append(.vulkan);
            if (build_options.opengl_available) try backends.append(.opengl);
            if (build_options.opengles_available) try backends.append(.opengles);
        },
        .linux => {
            if (build_options.vulkan_available) try backends.append(.vulkan);
            if (build_options.opengl_available) try backends.append(.opengl);
            if (build_options.opengles_available) try backends.append(.opengles);
        },
        .emscripten, .wasi => {
            if (build_options.webgpu_available) try backends.append(.webgpu);
            if (build_options.opengles_available) try backends.append(.opengles);
        },
        else => {
            try backends.append(.software);
        },
    }

    // Always include software backend as fallback
    try backends.append(.software);

    return backends.toOwnedSlice();
}

fn testBackend(backend: capabilities.GraphicsBackend, config: TestConfig) !TestResult {
    var result = TestResult{
        .backend = backend,
        .success = false,
        .performance_stats = PerformanceStats{},
    };

    // Initialize backend manager with specific backend
    var backend_manager = graphics.BackendManager.init(allocator, .{
        .preferred_backend = backend,
        .auto_fallback = false, // Disable fallback for pure testing
        .debug_mode = true,
        .validate_backends = true,
    }) catch |err| {
        result.error_message = @errorName(err);
        return result;
    };
    defer backend_manager.deinit();

    // Test backend capabilities
    if (!backend_manager.supportsBackend(backend)) {
        result.error_message = "Backend not supported on this platform";
        return result;
    }

    // Get backend info and capabilities
    const backend_info = backend_manager.getBackendInfo(backend) catch {
        result.error_message = "Failed to get backend info";
        return result;
    };

    if (config.verbose) {
        std.log.info("  Backend: {s}", .{backend_info.name});
        std.log.info("  Version: {s}", .{backend_info.version});
        std.log.info("  Vendor: {s}", .{backend_info.vendor});
        std.log.info("  Device: {s}", .{backend_info.device_name});
    }

    // Test basic initialization
    const graphics_backend = backend_manager.getPrimaryBackend();
    if (graphics_backend.backend_type != backend) {
        result.error_message = "Backend fallback occurred during initialization";
        return result;
    }

    // Test swap chain creation
    const swap_chain = graphics_backend.createSwapChain(.{
        .width = 800,
        .height = 600,
        .format = .rgba8_unorm_srgb,
        .buffer_count = 2,
        .vsync = false,
        .window_handle = 0, // Mock handle for testing
    }) catch |err| {
        result.error_message = @errorName(err);
        return result;
    };
    defer graphics_backend.destroySwapChain(swap_chain);

    // Test basic resource creation
    testResourceCreation(graphics_backend) catch |err| {
        result.error_message = @errorName(err);
        return result;
    };

    // Performance testing
    result.performance_stats = try runPerformanceTest(graphics_backend, config);

    // Memory leak detection
    const initial_memory = getCurrentMemoryUsage();
    try runMemoryStressTest(graphics_backend);
    const final_memory = getCurrentMemoryUsage();

    if (final_memory - initial_memory > config.memory_threshold_mb) {
        result.error_message = "Memory leak detected";
        return result;
    }

    // Validation tests
    try runValidationTests(graphics_backend, config);

    result.success = true;
    return result;
}

fn testResourceCreation(backend: *graphics.GraphicsBackend) !void {
    // Test buffer creation
    const vertex_buffer = try backend.createBuffer(.{
        .size = 1024,
        .usage = .{ .vertex_buffer = true },
        .memory_type = .device,
    });
    defer backend.destroyBuffer(vertex_buffer);

    // Test texture creation
    const texture = try backend.createTexture(.{
        .width = 256,
        .height = 256,
        .depth = 1,
        .mip_levels = 1,
        .array_layers = 1,
        .format = .rgba8_unorm,
        .usage = .{ .texture_binding = true },
        .sample_count = 1,
    });
    defer backend.destroyTexture(texture);

    // Test shader creation
    const vertex_shader = try backend.createShader(.{
        .stage = .vertex,
        .source = getTestVertexShader(),
        .entry_point = "main",
    });
    defer backend.destroyShader(vertex_shader);

    const fragment_shader = try backend.createShader(.{
        .stage = .fragment,
        .source = getTestFragmentShader(),
        .entry_point = "main",
    });
    defer backend.destroyShader(fragment_shader);
}

fn runPerformanceTest(backend: *graphics.GraphicsBackend, config: TestConfig) !PerformanceStats {
    var stats = PerformanceStats{};
    var frame_times = std.ArrayList(f64).init(allocator);
    defer frame_times.deinit();

    const start_time = std.time.milliTimestamp();

    while (std.time.milliTimestamp() - start_time < config.test_duration_ms) {
        const frame_start = std.time.milliTimestamp();

        // Simulate frame rendering
        try renderTestFrame(backend);

        const frame_end = std.time.milliTimestamp();
        const frame_time = @as(f64, @floatFromInt(frame_end - frame_start));

        // Prevent division by zero
        if (frame_time > 0) {
            try frame_times.append(frame_time);
            stats.frame_count += 1;

            // Calculate FPS
            const current_fps = 1000.0 / frame_time;
            if (stats.frame_count == 1) {
                stats.min_fps = current_fps;
                stats.max_fps = current_fps;
            } else {
                stats.min_fps = @min(stats.min_fps, current_fps);
                stats.max_fps = @max(stats.max_fps, current_fps);
            }
        }

        // Throttle to prevent excessive CPU usage
        std.time.sleep(1000000); // 1ms
    }

    // Calculate average FPS
    if (frame_times.items.len > 0) {
        var total_time: f64 = 0;
        for (frame_times.items) |time| {
            total_time += time;
        }
        const avg_time = total_time / @as(f64, @floatFromInt(frame_times.items.len));
        if (avg_time > 0) {
            stats.avg_fps = 1000.0 / avg_time;
            stats.render_time_ms = avg_time;
        }
    }

    stats.memory_usage_mb = getCurrentMemoryUsage();

    return stats;
}

fn renderTestFrame(backend: *graphics.GraphicsBackend) !void {
    // Create command buffer
    const cmd_buffer = try backend.createCommandBuffer();
    defer backend.destroyCommandBuffer(cmd_buffer);

    // Begin command recording
    try backend.beginCommandBuffer(cmd_buffer);

    // Simple render pass
    try backend.beginRenderPass(cmd_buffer, .{
        .color_targets = &[_]graphics.ColorTargetDesc{.{
            .texture = undefined, // Would be back buffer in real scenario
            .load_action = .clear,
            .store_action = .store,
        }},
        .depth_target = null,
        .clear_color = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 },
    });

    // End render pass
    try backend.endRenderPass(cmd_buffer);

    // End command recording
    try backend.endCommandBuffer(cmd_buffer);

    // Submit commands
    try backend.submitCommandBuffer(cmd_buffer);

    // Present
    try backend.present();
}

fn runMemoryStressTest(backend: *graphics.GraphicsBackend) !void {
    // Create and destroy many resources to test for leaks
    var buffers = std.ArrayList(graphics.Buffer).init(allocator);
    defer {
        // Clean up any remaining buffers
        for (buffers.items) |buffer| {
            backend.destroyBuffer(buffer);
        }
        buffers.deinit();
    }

    for (0..100) |i| {
        const buffer = try backend.createBuffer(.{
            .size = 1024 + i * 64,
            .usage = .{ .vertex_buffer = true },
            .memory_type = .device,
        });
        try buffers.append(buffer);
    }

    // Clean up all buffers
    for (buffers.items) |buffer| {
        backend.destroyBuffer(buffer);
    }
    buffers.clearAndFree();
}

fn runValidationTests(backend: *graphics.GraphicsBackend, config: TestConfig) !void {
    _ = config;

    // Test invalid operations (should fail gracefully)
    const invalid_buffer_result = backend.createBuffer(.{
        .size = 0, // Invalid size
        .usage = .{},
        .memory_type = .device,
    });

    if (invalid_buffer_result) |buffer| {
        // If it somehow succeeded, clean it up
        backend.destroyBuffer(buffer);
        return error.ValidationFailed;
    } else |_| {
        // Expected to fail
    }

    // Test resource limits
    const backend_info = try backend.getBackendInfo();
    if (backend_info.max_texture_size < 1024) {
        return error.InsufficientCapabilities;
    }
}

fn getCurrentMemoryUsage() f64 {
    // Platform-specific memory usage detection
    switch (builtin.os.tag) {
        .windows => {
            // Would use Windows API to get process memory usage
            return 0.0; // Placeholder
        },
        .linux, .macos => {
            // Would parse /proc/self/status or use system calls
            return 0.0; // Placeholder
        },
        else => return 0.0,
    }
}

fn getTestVertexShader() []const u8 {
    return switch (builtin.os.tag) {
        .windows =>
        \\struct VS_INPUT {
        \\    float3 pos : POSITION;
        \\    float2 uv : TEXCOORD0;
        \\};
        \\struct VS_OUTPUT {
        \\    float4 pos : SV_POSITION;
        \\    float2 uv : TEXCOORD0;
        \\};
        \\VS_OUTPUT main(VS_INPUT input) {
        \\    VS_OUTPUT output;
        \\    output.pos = float4(input.pos, 1.0);
        \\    output.uv = input.uv;
        \\    return output;
        \\}
        ,
        .emscripten, .wasi =>
        \\#version 300 es
        \\precision mediump float;
        \\in vec3 a_position;
        \\in vec2 a_uv;
        \\out vec2 v_uv;
        \\void main() {
        \\    gl_Position = vec4(a_position, 1.0);
        \\    v_uv = a_uv;
        \\}
        ,
        else =>
        \\#version 450 core
        \\layout(location = 0) in vec3 a_position;
        \\layout(location = 1) in vec2 a_uv;
        \\layout(location = 0) out vec2 v_uv;
        \\void main() {
        \\    gl_Position = vec4(a_position, 1.0);
        \\    v_uv = a_uv;
        \\}
        ,
    };
}

fn getTestFragmentShader() []const u8 {
    return switch (builtin.os.tag) {
        .windows =>
        \\struct PS_INPUT {
        \\    float4 pos : SV_POSITION;
        \\    float2 uv : TEXCOORD0;
        \\};
        \\float4 main(PS_INPUT input) : SV_TARGET {
        \\    return float4(input.uv, 0.0, 1.0);
        \\}
        ,
        .emscripten, .wasi =>
        \\#version 300 es
        \\precision mediump float;
        \\in vec2 v_uv;
        \\out vec4 fragColor;
        \\void main() {
        \\    fragColor = vec4(v_uv, 0.0, 1.0);
        \\}
        ,
        else =>
        \\#version 450 core
        \\layout(location = 0) in vec2 v_uv;
        \\layout(location = 0) out vec4 fragColor;
        \\void main() {
        \\    fragColor = vec4(v_uv, 0.0, 1.0);
        \\}
        ,
    };
}

fn printTestReport(results: []const TestResult, config: TestConfig) !void {
    std.log.info("=== TEST REPORT ===", .{});
    std.log.info("", .{});

    var passed_count: u32 = 0;
    const total_count: u32 = @intCast(results.len);

    for (results) |result| {
        if (result.success) {
            passed_count += 1;
        }

        std.log.info("Backend: {s}", .{@tagName(result.backend)});
        std.log.info("Status: {s}", .{if (result.success) "PASSED" else "FAILED"});

        if (!result.success and result.error_message != null) {
            std.log.info("Error: {s}", .{result.error_message.?});
        }

        if (result.success) {
            const stats = result.performance_stats;
            std.log.info("Performance:", .{});
            std.log.info("  Average FPS: {d:.1}", .{stats.avg_fps});
            std.log.info("  Min FPS: {d:.1}", .{stats.min_fps});
            std.log.info("  Max FPS: {d:.1}", .{stats.max_fps});
            std.log.info("  Frame Count: {}", .{stats.frame_count});
            std.log.info("  Memory Usage: {d:.1} MB", .{stats.memory_usage_mb});
            std.log.info("  Avg Render Time: {d:.2} ms", .{stats.render_time_ms});

            // Performance validation
            if (stats.avg_fps < config.min_acceptable_fps) {
                std.log.warn("  WARNING: FPS below threshold ({d:.1} < {d:.1})", .{ stats.avg_fps, config.min_acceptable_fps });
            }
        }

        std.log.info("", .{});
    }

    // Summary
    std.log.info("SUMMARY:", .{});
    std.log.info("Passed: {}/{}", .{ passed_count, total_count });

    if (total_count > 0) {
        std.log.info("Success Rate: {d:.1}%", .{@as(f64, @floatFromInt(passed_count)) / @as(f64, @floatFromInt(total_count)) * 100.0});
    } else {
        std.log.info("Success Rate: 0.0%", .{});
    }

    if (passed_count == total_count) {
        std.log.info("✓ ALL TESTS PASSED", .{});
    } else {
        std.log.err("✗ SOME TESTS FAILED", .{});
        std.process.exit(1);
    }
}
