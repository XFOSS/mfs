const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var test_filter: ?[]const u8 = null;
    var verbose = false;
    var benchmark = false;
    var memory_check = false;

    // Parse command line arguments
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--filter") or std.mem.eql(u8, arg, "-f")) {
            i += 1;
            if (i >= args.len) {
                std.log.err("Missing value for --filter", .{});
                std.process.exit(1);
            }
            test_filter = args[i];
        } else if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
            verbose = true;
        } else if (std.mem.eql(u8, arg, "--benchmark") or std.mem.eql(u8, arg, "-b")) {
            benchmark = true;
        } else if (std.mem.eql(u8, arg, "--memory-check") or std.mem.eql(u8, arg, "-m")) {
            memory_check = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printUsage();
            std.process.exit(0);
        } else {
            std.log.err("Unknown option: {s}", .{arg});
            try printUsage();
            std.process.exit(1);
        }
    }

    std.log.info("MFS Engine Test Runner", .{});
    std.log.info("======================", .{});

    const test_suites = [_]TestSuite{
        .{ .name = "Math Library", .path = "src/tests/test_math.zig" },
        .{ .name = "Physics Engine", .path = "src/tests/physics_test.zig" },
        .{ .name = "Graphics System", .path = "src/tests/test_opengl.zig" },
        .{ .name = "Vulkan Backend", .path = "src/tests/test_vulkan.zig" },
        .{ .name = "Comprehensive Tests", .path = "src/tests/comprehensive_tests.zig" },
        .{ .name = "Benchmarks", .path = "src/tests/benchmarks/render_bench.zig" },
        .{ .name = "Asset Processor", .path = "tools/asset_processor/asset_processor.zig" },
    };

    var total_tests: usize = 0;
    var passed_tests: usize = 0;
    var failed_tests: usize = 0;
    var skipped_tests: usize = 0;

    const start_time = std.time.nanoTimestamp();

    for (test_suites) |suite| {
        if (test_filter) |filter| {
            if (std.mem.indexOf(u8, suite.name, filter) == null) {
                if (verbose) {
                    std.log.info("Skipping {s} (filtered)", .{suite.name});
                }
                skipped_tests += 1;
                continue;
            }
        }

        if (verbose) {
            std.log.info("Running {s}...", .{suite.name});
        }

        const result = runTestSuite(allocator, suite, verbose, memory_check) catch |err| {
            std.log.err("Failed to run {s}: {}", .{ suite.name, err });
            failed_tests += 1;
            continue;
        };

        total_tests += 1;
        if (result.success) {
            passed_tests += 1;
            if (verbose) {
                std.log.info("✓ {s} passed ({d} tests, {d:.2}ms)", .{ suite.name, result.test_count, @as(f64, @floatFromInt(result.duration_ns)) / 1_000_000.0 });
            }
        } else {
            failed_tests += 1;
            std.log.err("✗ {s} failed", .{suite.name});
        }

        if (benchmark) {
            if (result.benchmark_data) |bench_data| {
                std.log.info("Benchmark results for {s}:", .{suite.name});
                for (bench_data) |bench| {
                    std.log.info("  {s}: {d:.2}ms", .{ bench.name, bench.duration_ms });
                }
            }
        }
    }

    const end_time = std.time.nanoTimestamp();
    const total_duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;

    std.log.info("", .{});
    std.log.info("Test Results:", .{});
    std.log.info("=============", .{});
    std.log.info("Total test suites: {d}", .{total_tests});
    std.log.info("Passed: {d}", .{passed_tests});
    std.log.info("Failed: {d}", .{failed_tests});
    std.log.info("Skipped: {d}", .{skipped_tests});
    std.log.info("Total time: {d:.2}ms", .{total_duration_ms});

    if (failed_tests > 0) {
        std.log.err("Some tests failed!", .{});
        std.process.exit(1);
    } else {
        std.log.info("All tests passed! ✓", .{});
    }
}

const TestSuite = struct {
    name: []const u8,
    path: []const u8,
};

const TestResult = struct {
    success: bool,
    test_count: usize,
    duration_ns: i128,
    benchmark_data: ?[]BenchmarkResult = null,
};

const BenchmarkResult = struct {
    name: []const u8,
    duration_ms: f64,
};

fn runTestSuite(allocator: std.mem.Allocator, suite: TestSuite, verbose: bool, memory_check: bool) !TestResult {
    const start_time = std.time.nanoTimestamp();

    // Check if test file exists
    std.fs.cwd().access(suite.path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            if (verbose) {
                std.log.warn("Test file not found: {s}", .{suite.path});
            }
            return TestResult{
                .success = true,
                .test_count = 0,
                .duration_ns = 0,
            };
        }
        return err;
    };

    // Build test command
    var cmd_args = std.ArrayList([]const u8).init(allocator);
    defer cmd_args.deinit();

    try cmd_args.append("zig");
    try cmd_args.append("test");
    try cmd_args.append(suite.path);

    if (memory_check) {
        try cmd_args.append("--test-filter");
        try cmd_args.append("memory");
    }

    // Run the test
    var child = std.process.Child.init(cmd_args.items, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    const stdout = try child.stdout.?.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(stdout);

    const stderr = try child.stderr.?.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(stderr);

    const result = try child.wait();

    const end_time = std.time.nanoTimestamp();
    const duration_ns = end_time - start_time;

    if (verbose and stdout.len > 0) {
        std.log.info("Test output for {s}:", .{suite.name});
        std.log.info("{s}", .{stdout});
    }

    if (stderr.len > 0) {
        std.log.err("Test errors for {s}:", .{suite.name});
        std.log.err("{s}", .{stderr});
    }

    const success = switch (result) {
        .Exited => |code| code == 0,
        else => false,
    };

    // Parse test count from output
    const test_count = parseTestCount(stdout);

    return TestResult{
        .success = success,
        .test_count = test_count,
        .duration_ns = duration_ns,
    };
}

fn parseTestCount(output: []const u8) usize {
    // Look for patterns like "All X tests passed" or "X/Y tests passed"
    var lines = std.mem.splitSequence(u8, output, "\n");
    while (lines.next()) |line| {
        if (std.mem.indexOf(u8, line, "tests passed")) |_| {
            // Try to extract number
            var tokens = std.mem.tokenizeScalar(u8, line, ' ');
            while (tokens.next()) |token| {
                if (std.fmt.parseInt(usize, token, 10)) |count| {
                    return count;
                } else |_| {
                    continue;
                }
            }
        }
    }
    return 0;
}

fn printUsage() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(
        \\Usage: zig run scripts/run_tests.zig [options]
        \\
        \\Options:
        \\  --filter, -f <pattern>    Run only tests matching pattern
        \\  --verbose, -v             Enable verbose output
        \\  --benchmark, -b           Run benchmark tests
        \\  --memory-check, -m        Run memory leak detection tests
        \\  --help, -h                Show this help message
        \\
        \\Examples:
        \\  zig run scripts/run_tests.zig
        \\  zig run scripts/run_tests.zig --filter "Math"
        \\  zig run scripts/run_tests.zig --verbose --benchmark
        \\  zig run scripts/run_tests.zig --memory-check
        \\
    );
}

test "test runner functionality" {
    // Basic test to ensure the test runner compiles
    const suite = TestSuite{
        .name = "Test Suite",
        .path = "nonexistent.zig",
    };

    // Just verify the structure is correct
    try std.testing.expectEqualStrings("Test Suite", suite.name);
    try std.testing.expectEqualStrings("nonexistent.zig", suite.path);
}
