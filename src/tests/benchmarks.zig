const std = @import("std");
const builtin = @import("builtin");
const nyx = @import("../nyx_std.zig");
const build_options = @import("build_options");

const math = @import("../math/math.zig");
const graphics = @import("../graphics/graphics.zig");
const platform = @import("../platform/platform.zig");
const physics = @import("../physics/physics.zig");

const tracy = if (@hasDecl(build_options, "enable_tracy") and build_options.enable_tracy)
    @import("tracy")
else
    struct {
        pub inline fn traceName(comptime _: []const u8) void {}
        pub inline fn tracyPlot(comptime _: []const u8, _: f64) void {}
    };

pub const BenchmarkConfig = struct {
    name: []const u8,
    iterations: u32 = 1000,
    warmup_iterations: u32 = 100,
    output: enum {
        console,
        csv,
        json,
    } = .console,
    output_file: ?[]const u8 = null,
    allocator: std.mem.Allocator,
};

pub const BenchmarkReport = struct {
    name: []const u8,
    median_ns: f64,
    mean_ns: f64,
    min_ns: f64,
    max_ns: f64,
    std_dev: f64,
    iterations: u32,
    warmup_iterations: u32,
    date: i64,

    pub fn format(
        self: BenchmarkReport,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print(
            "{s}: median={d:.3}µs mean={d:.3}µs min={d:.3}µs max={d:.3}µs stddev={d:.3}µs iterations={d}\n",
            .{
                self.name,
                self.median_ns / 1000.0,
                self.mean_ns / 1000.0,
                self.min_ns / 1000.0,
                self.max_ns / 1000.0,
                self.std_dev / 1000.0,
                self.iterations,
            },
        );
    }
};

/// Benchmarking system for measuring code performance
pub const Benchmarker = struct {
    const Self = @This();

    config: BenchmarkConfig,
    results: std.ArrayList(BenchmarkReport),
    timer: std.time.Timer,

    pub fn init(config: BenchmarkConfig) !Self {
        return Self{
            .config = config,
            .results = std.ArrayList(BenchmarkReport).init(config.allocator),
            .timer = try std.time.Timer.start(),
        };
    }

    pub fn deinit(self: *Self) void {
        self.results.deinit();
    }

    /// Run a benchmark of the specified function
    pub fn benchmark(self: *Self, comptime name: []const u8, func: anytype) !BenchmarkReport {
        const BenchmarkFn = @TypeOf(func);
        const benchmark_info = @typeInfo(BenchmarkFn);

        // Validate the function signature
        switch (benchmark_info) {
            .Fn => |fn_info| {
                if (fn_info.params.len > 1) {
                    @compileError("Benchmark function must take 0 or 1 parameters");
                }
            },
            else => @compileError("Expected a function"),
        }

        const iterations = self.config.iterations;
        const warmup_iterations = self.config.warmup_iterations;

        // Warmup phase
        std.debug.print("Warming up {s} for {d} iterations...\n", .{ name, warmup_iterations });
        var i: u32 = 0;
        while (i < warmup_iterations) : (i += 1) {
            // Call the function based on its parameter count
            if (benchmark_info.Fn.params.len == 1) {
                @call(.auto, func, .{i});
            } else {
                @call(.auto, func, .{});
            }
        }

        // Actual benchmark
        std.debug.print("Running {s} for {d} iterations...\n", .{ name, iterations });

        var times = try self.config.allocator.alloc(u64, iterations);
        defer self.config.allocator.free(times);

        i = 0;
        while (i < iterations) : (i += 1) {
            self.timer.reset();

            // Call the function based on its parameter count
            if (benchmark_info.Fn.params.len == 1) {
                @call(.auto, func, .{i});
            } else {
                @call(.auto, func, .{});
            }

            times[i] = self.timer.read();
        }

        // Process results
        var total_time: u64 = 0;
        var min_time: u64 = std.math.maxInt(u64);
        var max_time: u64 = 0;

        for (times) |time| {
            total_time += time;
            min_time = @min(min_time, time);
            max_time = @max(max_time, time);
        }

        std.sort.insertion(u64, times, {}, comptime std.sort.asc(u64));

        const median_time = times[iterations / 2];
        const mean_time = @as(f64, @floatFromInt(total_time)) / @as(f64, @floatFromInt(iterations));

        // Calculate standard deviation
        var sum_squared_diff: f64 = 0.0;
        for (times) |time| {
            const diff = @as(f64, @floatFromInt(time)) - mean_time;
            sum_squared_diff += diff * diff;
        }
        const variance = sum_squared_diff / @as(f64, @floatFromInt(iterations));
        const std_dev = @sqrt(variance);

        const report = BenchmarkReport{
            .name = name,
            .median_ns = @floatFromInt(median_time),
            .mean_ns = mean_time,
            .min_ns = @floatFromInt(min_time),
            .max_ns = @floatFromInt(max_time),
            .std_dev = std_dev,
            .iterations = iterations,
            .warmup_iterations = warmup_iterations,
            .date = std.time.timestamp(),
        };

        try self.results.append(report);
        std.debug.print("{}\n", .{report});

        return report;
    }

    /// Save benchmark results to a file
    pub fn saveResults(self: *Self) !void {
        if (self.config.output_file == null) return;

        const file = try std.fs.cwd().createFile(
            self.config.output_file.?,
            .{ .read = true, .truncate = true },
        );
        defer file.close();

        const writer = file.writer();

        switch (self.config.output) {
            .console => {
                // Already printed to console
            },
            .csv => {
                // Write CSV header
                try writer.writeAll("name,median_ns,mean_ns,min_ns,max_ns,std_dev,iterations,warmup_iterations,date\n");

                // Write data rows
                for (self.results.items) |result| {
                    try writer.print("{s},{d},{d},{d},{d},{d},{d},{d},{d}\n", .{
                        result.name,
                        result.median_ns,
                        result.mean_ns,
                        result.min_ns,
                        result.max_ns,
                        result.std_dev,
                        result.iterations,
                        result.warmup_iterations,
                        result.date,
                    });
                }
            },
            .json => {
                // Simple JSON serialization
                try writer.writeAll("[\n");

                for (self.results.items, 0..) |result, i| {
                    if (i > 0) try writer.writeAll(",\n");
                    try writer.print(
                        \\  {{
                        \\    "name": "{s}",
                        \\    "median_ns": {d},
                        \\    "mean_ns": {d},
                        \\    "min_ns": {d},
                        \\    "max_ns": {d},
                        \\    "std_dev": {d},
                        \\    "iterations": {d},
                        \\    "warmup_iterations": {d},
                        \\    "date": {d}
                        \\  }}
                    ,
                        .{
                            result.name,
                            result.median_ns,
                            result.mean_ns,
                            result.min_ns,
                            result.max_ns,
                            result.std_dev,
                            result.iterations,
                            result.warmup_iterations,
                            result.date,
                        },
                    );
                }

                try writer.writeAll("\n]");
            },
        }
    }
};

// ------ Benchmark Implementations ------

fn benchmarkVectorMath() void {
    var v1 = math.Vec3.new(1.0, 2.0, 3.0);
    var v2 = math.Vec3.new(4.0, 5.0, 6.0);

    var result = v1.add(v2);
    result = result.scale(2.0);
    result = result.normalize();
    _ = result.dot(v1);
    _ = result.cross(v2);
}

fn benchmarkMatrixMath() void {
    var m1 = math.Mat4.identity();
    m1 = m1.translate(math.Vec3.new(1.0, 2.0, 3.0));
    m1 = m1.rotate(math.Vec3.new(0.0, 1.0, 0.0), 0.5);
    m1 = m1.scale(math.Vec3.new(2.0, 2.0, 2.0));

    var m2 = math.Mat4.lookAt(
        math.Vec3.new(0.0, 5.0, 10.0),
        math.Vec3.new(0.0, 0.0, 0.0),
        math.Vec3.new(0.0, 1.0, 0.0),
    );

    _ = m1.mul(m2);
    _ = m1.invert();
}

fn benchmarkMemoryAllocations(iter: u32) void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    // Simulate allocation patterns from engine components
    const size = (iter % 10 + 1) * 1024;
    const mem = allocator.alloc(u8, size) catch unreachable;

    // Do some work with the memory to prevent optimization
    @memset(mem, @intCast(iter % 256));
}

// ------ Main Benchmark Runner ------

pub fn main() !void {
    // Initialize
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create benchmark suite
    var benchmarker = try Benchmarker.init(.{
        .name = "MFS Engine Core Benchmarks",
        .iterations = 10000,
        .warmup_iterations = 1000,
        .output = .csv,
        .output_file = "benchmark_results.csv",
        .allocator = allocator,
    });
    defer benchmarker.deinit();

    // Run benchmarks
    try benchmarker.benchmark("Vector Math Operations", benchmarkVectorMath);
    try benchmarker.benchmark("Matrix Math Operations", benchmarkMatrixMath);
    try benchmarker.benchmark("Memory Allocation Patterns", benchmarkMemoryAllocations);

    // Add physics benchmark if available
    if (@hasDecl(physics, "benchmarkPhysicsSimulation")) {
        try benchmarker.benchmark("Physics Simulation", physics.benchmarkPhysicsSimulation);
    }

    // Save results to file
    try benchmarker.saveResults();
}

test "benchmarker basic functionality" {
    const testing = std.testing;

    var benchmarker = try Benchmarker.init(.{
        .name = "Test Benchmark",
        .iterations = 100,
        .warmup_iterations = 10,
        .allocator = testing.allocator,
    });
    defer benchmarker.deinit();

    // Simple function to benchmark
    const result = try benchmarker.benchmark("Vector Addition", benchmarkVectorMath);

    try testing.expect(result.median_ns > 0);
    try testing.expect(result.iterations == 100);
}
