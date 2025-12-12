const std = @import("std");
const testing = std.testing;
const errors = @import("errors.zig");
const memory = @import("memory.zig");
const profiling = @import("profiling.zig");

test "error handling" {
    var error_logger = errors.ErrorLogger.init(testing.allocator);
    defer error_logger.deinit();

    // Test error logging
    try error_logger.logError(
        errors.makeError(errors.GraphicsError.DeviceCreationFailed, "Test error", "test", @src().file, @src().line, null, .critical),
        .critical,
    );

    try testing.expect(error_logger.hasErrors());
    try testing.expect(error_logger.getLastError() != null);
}

test "memory allocation" {
    var allocator = try memory.Allocator.init(testing.allocator, .general, 1024);
    defer allocator.deinit();

    // Test allocation
    var block = try allocator.allocate(.{
        .size = 256,
        .alignment = 8,
        .strategy = .linear,
        .usage = .{
            .cpu_write = true,
            .gpu_read = true,
        },
    });

    try testing.expect(block.*.size == 256);
    try testing.expect(block.*.mapped == false);

    // Test mapping
    try block.map();
    try testing.expect(block.*.mapped == true);

    // Test unmapping
    block.unmap();
    try testing.expect(block.*.mapped == false);

    // Test freeing
    allocator.free(block);
    try testing.expect(allocator.used_size == 0);
}

test "memory pool" {
    var pool = try memory.MemoryPool.init(testing.allocator, 64, // block size
        16 // capacity
    );
    defer pool.deinit();

    // Test allocation
    const block1 = try pool.allocate();
    try testing.expect(block1.len == 64);

    const block2 = try pool.allocate();
    try testing.expect(block2.len == 64);

    // Test freeing
    try pool.free(block1);
    try pool.free(block2);

    // Test pool capacity
    var blocks = std.array_list.Managed([]u8).init(testing.allocator);
    defer blocks.deinit();

    // Should be able to allocate capacity blocks
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        const block = try pool.allocate();
        try blocks.append(block);
    }

    // Next allocation should fail
    try testing.expectError(errors.GraphicsError.OutOfMemory, pool.allocate());

    // Free all blocks
    for (blocks.items) |block| {
        try pool.free(block);
    }
}

test "performance profiling" {
    var profiler = try profiling.GpuProfiler.init(testing.allocator);
    defer profiler.deinit();

    // Test frame profiling
    try profiler.beginFrame();

    // Test markers
    try profiler.pushMarker("Test Section");

    // Update some metrics
    var metrics = profiler.getCurrentMetrics();
    metrics.draw_calls += 1;
    metrics.triangle_count += 100;

    profiler.popMarker();

    try profiler.endFrame();

    // Test metrics
    try testing.expect(profiler.frame_metrics.items.len == 1);
    try testing.expect(profiler.frame_metrics.items[0].draw_calls == 1);
    try testing.expect(profiler.frame_metrics.items[0].triangle_count == 100);

    // Test average frame time
    const avg_time = profiler.getAverageFrameTime();
    try testing.expect(avg_time >= 0);
}

test "error context formatting" {
    const error_ctx = errors.makeError(
        errors.GraphicsError.DeviceCreationFailed,
        "Test error message",
        "test_backend",
        "test.zig",
        123,
        "Additional test info",
        .@"error",
    );

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try std.fmt.format(fbs.writer(), "{}", .{error_ctx});

    const output = fbs.getWritten();
    try testing.expect(std.mem.indexOf(u8, output, "[error]") != null);
    try testing.expect(std.mem.indexOf(u8, output, "DeviceCreationFailed") != null);
    try testing.expect(std.mem.indexOf(u8, output, "test_backend") != null);
    try testing.expect(std.mem.indexOf(u8, output, "test.zig:123") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Test error message") != null);
    try testing.expect(std.mem.indexOf(u8, output, "Additional test info") != null);
}

test "error logger routes severity correctly" {
    var error_logger = errors.ErrorLogger.init(testing.allocator);
    defer error_logger.deinit();

    // Log an error with .@"error" severity
    try error_logger.logError(
        errors.makeError(
            errors.GraphicsError.ShaderCompilationFailed,
            "Shader compilation test error",
            "test_backend",
            @src().file,
            @src().line,
            null,
            .@"error",
        ),
        .@"error",
    );

    try testing.expect(error_logger.hasErrors());
    const last_error = error_logger.getLastError().?;
    try testing.expect(last_error.severity == .@"error");

    // The logError function logs to std.log, which is hard to capture in a test.
    // However, we can check the formatted output of the ErrorContext.
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try std.fmt.format(fbs.writer(), "{}", .{last_error});
    const output = fbs.getWritten();

    try testing.expect(std.mem.indexOf(u8, output, "[error]") != null);
    try testing.expect(std.mem.indexOf(u8, output, "ShaderCompilationFailed") != null);
}
