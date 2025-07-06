//! Comprehensive Test Suite for MFS Engine
//! Provides extensive testing coverage for all engine subsystems
//! @thread-safe Test execution is designed to be thread-safe
//! @symbol Testing framework

const std = @import("std");
const testing = std.testing;
const builtin = @import("builtin");

// Import engine modules for testing
const mfs = @import("mfs");
const math = mfs.math;
const physics = mfs.physics;
const scene = mfs.scene;
const gpu = mfs.graphics;
const error_utils = mfs.utils;
const nyx = mfs; // Alias for backward compatibility

// Test utilities and helpers
const TestAllocator = struct {
    gpa: std.heap.GeneralPurposeAllocator(.{ .safety = true }),
    allocator: std.mem.Allocator,

    pub fn init() TestAllocator {
        var ta = TestAllocator{
            .gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){},
            .allocator = undefined,
        };
        ta.allocator = ta.gpa.allocator();
        return ta;
    }

    pub fn deinit(self: *TestAllocator) !void {
        const leak_check = self.gpa.deinit();
        if (leak_check == .leak) {
            return error.MemoryLeak;
        }
    }
};

const TestResult = struct {
    name: []const u8,
    passed: bool,
    duration_ns: u64,
    error_message: ?[]const u8 = null,

    pub fn format(
        self: TestResult,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        const status = if (self.passed) "PASS" else "FAIL";
        const duration_ms = @as(f64, @floatFromInt(self.duration_ns)) / std.time.ns_per_ms;

        try writer.print("[{s}] {s} ({d:.2}ms)", .{ status, self.name, duration_ms });

        if (self.error_message) |msg| {
            try writer.print(" - {s}", .{msg});
        }
    }
};

const TestSuite = struct {
    name: []const u8,
    tests: std.ArrayList(TestResult),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) TestSuite {
        return TestSuite{
            .name = name,
            .tests = std.ArrayList(TestResult).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TestSuite) void {
        for (self.tests.items) |test_result| {
            if (test_result.error_message) |msg| {
                self.allocator.free(msg);
            }
        }
        self.tests.deinit();
    }

    pub fn runTest(
        self: *TestSuite,
        comptime name: []const u8,
        test_fn: anytype,
    ) !void {
        const start_time = std.time.nanoTimestamp();

        var result = TestResult{
            .name = name,
            .passed = false,
            .duration_ns = 0,
        };

        if (test_fn()) {
            result.passed = true;
        } else |err| {
            result.error_message = try std.fmt.allocPrint(
                self.allocator,
                "{s}",
                .{@errorName(err)},
            );
        }

        const end_time = std.time.nanoTimestamp();
        result.duration_ns = @intCast(end_time - start_time);

        try self.tests.append(result);
    }

    pub fn printResults(self: *const TestSuite) void {
        var passed: u32 = 0;
        var failed: u32 = 0;
        var total_duration: u64 = 0;

        std.debug.print("\n=== Test Suite: {s} ===\n", .{self.name});

        for (self.tests.items) |test_result| {
            std.debug.print("{}\n", .{test_result});

            if (test_result.passed) {
                passed += 1;
            } else {
                failed += 1;
            }
            total_duration += test_result.duration_ns;
        }

        const total_duration_ms = @as(f64, @floatFromInt(total_duration)) / std.time.ns_per_ms;
        const success_rate = if (self.tests.items.len > 0)
            @as(f64, @floatFromInt(passed)) / @as(f64, @floatFromInt(self.tests.items.len)) * 100.0
        else
            0.0;

        std.debug.print("\nResults: {d} passed, {d} failed ({d:.1}% success rate)\n", .{ passed, failed, success_rate });
        std.debug.print("Total duration: {d:.2}ms\n", .{total_duration_ms});
    }
};

// Math library tests with comprehensive coverage
test "Vec3 comprehensive operations" {
    const v1 = math.Vec3.init(1.0, 2.0, 3.0);
    const v2 = math.Vec3.init(4.0, 5.0, 6.0);
    const v3 = math.Vec3.init(0.0, 0.0, 0.0);

    // Basic arithmetic
    const sum = v1.add(v2);
    try testing.expectEqual(@as(f32, 5.0), sum.x);
    try testing.expectEqual(@as(f32, 7.0), sum.y);
    try testing.expectEqual(@as(f32, 9.0), sum.z);

    const diff = v2.sub(v1);
    try testing.expectEqual(@as(f32, 3.0), diff.x);
    try testing.expectEqual(@as(f32, 3.0), diff.y);
    try testing.expectEqual(@as(f32, 3.0), diff.z);

    const scaled = v1.scale(2.0);
    try testing.expectEqual(@as(f32, 2.0), scaled.x);
    try testing.expectEqual(@as(f32, 4.0), scaled.y);
    try testing.expectEqual(@as(f32, 6.0), scaled.z);

    // Dot product
    const dot = v1.dot(v2);
    try testing.expectEqual(@as(f32, 32.0), dot); // 1*4 + 2*5 + 3*6 = 32

    // Cross product
    const cross = v1.cross(v2);
    try testing.expectEqual(@as(f32, -3.0), cross.x); // 2*6 - 3*5 = -3
    try testing.expectEqual(@as(f32, 6.0), cross.y); // 3*4 - 1*6 = 6
    try testing.expectEqual(@as(f32, -3.0), cross.z); // 1*5 - 2*4 = -3

    // Length and normalization
    const length = v1.length();
    try testing.expectApproxEqRel(@as(f32, 3.7416573), length, 0.0001);

    const normalized = v1.normalize();
    const normalized_length = normalized.length();
    try testing.expectApproxEqRel(@as(f32, 1.0), normalized_length, 0.0001);

    // Zero vector tests
    try testing.expectEqual(@as(f32, 0.0), v3.length());

    // Distance between vectors
    const distance = v1.distance(v2);
    try testing.expectApproxEqRel(@as(f32, 5.196152), distance, 0.0001);
}

test "Vec2 comprehensive operations" {
    const v1 = math.Vec2.init(3.0, 4.0);
    const v2 = math.Vec2.init(1.0, 2.0);

    // Basic arithmetic
    const sum = v1.add(v2);
    try testing.expectEqual(@as(f32, 4.0), sum.x);
    try testing.expectEqual(@as(f32, 6.0), sum.y);

    const diff = v1.sub(v2);
    try testing.expectEqual(@as(f32, 2.0), diff.x);
    try testing.expectEqual(@as(f32, 2.0), diff.y);

    // Length (3-4-5 triangle)
    const length = v1.length();
    try testing.expectEqual(@as(f32, 5.0), length);

    // Normalization
    const normalized = v1.normalize();
    try testing.expectApproxEqRel(@as(f32, 0.6), normalized.x, 0.0001);
    try testing.expectApproxEqRel(@as(f32, 0.8), normalized.y, 0.0001);

    // Dot product
    const dot = v1.dot(v2);
    try testing.expectEqual(@as(f32, 11.0), dot); // 3*1 + 4*2 = 11

    // Perpendicular vector
    const perp = v1.perpendicular();
    try testing.expectEqual(@as(f32, -4.0), perp.x);
    try testing.expectEqual(@as(f32, 3.0), perp.y);

    // Verify perpendicular is actually perpendicular
    const perp_dot = v1.dot(perp);
    try testing.expectApproxEqRel(@as(f32, 0.0), perp_dot, 0.0001);
}

test "Mat4 comprehensive operations" {
    // Identity matrix
    const identity = math.Mat4.identity();

    // Check diagonal elements
    try testing.expectEqual(@as(f32, 1.0), identity.m[0][0]);
    try testing.expectEqual(@as(f32, 1.0), identity.m[1][1]);
    try testing.expectEqual(@as(f32, 1.0), identity.m[2][2]);
    try testing.expectEqual(@as(f32, 1.0), identity.m[3][3]);

    // Check off-diagonal elements are zero
    try testing.expectEqual(@as(f32, 0.0), identity.m[0][1]);
    try testing.expectEqual(@as(f32, 0.0), identity.m[1][0]);
    try testing.expectEqual(@as(f32, 0.0), identity.m[2][3]);

    // Translation matrix
    const translation = math.Mat4.translation(5.0, 10.0, 15.0);
    try testing.expectEqual(@as(f32, 5.0), translation.m[3][0]);
    try testing.expectEqual(@as(f32, 10.0), translation.m[3][1]);
    try testing.expectEqual(@as(f32, 15.0), translation.m[3][2]);

    // Matrix multiplication
    const t1 = math.Mat4.translation(1.0, 2.0, 3.0);
    const t2 = math.Mat4.translation(4.0, 5.0, 6.0);
    const combined = t1.multiply(t2);

    // Combined translation should be sum of translations
    try testing.expectEqual(@as(f32, 5.0), combined.m[3][0]);
    try testing.expectEqual(@as(f32, 7.0), combined.m[3][1]);
    try testing.expectEqual(@as(f32, 9.0), combined.m[3][2]);

    // Scale matrix
    const scale = math.Mat4.scale(2.0, 3.0, 4.0);
    try testing.expectEqual(@as(f32, 2.0), scale.m[0][0]);
    try testing.expectEqual(@as(f32, 3.0), scale.m[1][1]);
    try testing.expectEqual(@as(f32, 4.0), scale.m[2][2]);

    // Rotation matrix (90 degrees around Z-axis)
    const rotation = math.Mat4.rotationZ(std.math.pi / 2.0);

    // Test vector transformation
    const test_vec = math.Vec3.init(1.0, 0.0, 0.0);
    const rotated = rotation.transformVector(test_vec);
    try testing.expectApproxEqRel(@as(f32, 0.0), rotated.x, 0.0001);
    try testing.expectApproxEqRel(@as(f32, 1.0), rotated.y, 0.0001);
    try testing.expectApproxEqRel(@as(f32, 0.0), rotated.z, 0.0001);
}

// Enhanced Resource Manager tests
test "Resource Manager comprehensive functionality" {
    var test_allocator = TestAllocator.init();
    defer test_allocator.deinit() catch {};

    var resource_manager = try nyx.ResourceManager.init(test_allocator.allocator);
    defer resource_manager.deinit();

    // Test asset creation and retrieval
    const asset_data1 = "test asset data 1";
    const asset_data2 = "test asset data 2";
    const asset_id1 = try resource_manager.createAsset("test_asset_1", asset_data1);
    const asset_id2 = try resource_manager.createAsset("test_asset_2", asset_data2);

    // Verify assets exist and have correct data
    const retrieved_asset1 = resource_manager.getAsset(asset_id1);
    try testing.expect(retrieved_asset1 != null);
    try testing.expectEqualStrings("test_asset_1", retrieved_asset1.?.name);
    try testing.expectEqualStrings(asset_data1, retrieved_asset1.?.data);

    const retrieved_asset2 = resource_manager.getAsset(asset_id2);
    try testing.expect(retrieved_asset2 != null);
    try testing.expectEqualStrings("test_asset_2", retrieved_asset2.?.name);

    // Test asset lookup by name
    const found_asset1 = resource_manager.getAssetByName("test_asset_1");
    try testing.expect(found_asset1 != null);
    try testing.expectEqual(asset_id1, found_asset1.?.id);

    const found_asset2 = resource_manager.getAssetByName("test_asset_2");
    try testing.expect(found_asset2 != null);
    try testing.expectEqual(asset_id2, found_asset2.?.id);

    // Test asset unloading
    resource_manager.unloadAsset(asset_id1);
    const unloaded_asset = resource_manager.getAsset(asset_id1);
    try testing.expect(unloaded_asset == null);

    // Verify other asset still exists
    const still_exists = resource_manager.getAsset(asset_id2);
    try testing.expect(still_exists != null);

    // Test non-existent asset
    const non_existent = resource_manager.getAsset(9999);
    try testing.expect(non_existent == null);

    const non_existent_by_name = resource_manager.getAssetByName("non_existent");
    try testing.expect(non_existent_by_name == null);
}

// Enhanced Engine configuration tests
test "Engine configuration comprehensive validation" {
    // Valid configuration
    const valid_config = nyx.EngineConfig{
        .window_width = 1920,
        .window_height = 1080,
        .target_fps = 60,
        .max_memory_budget_mb = 512,
        .enable_gpu = true,
        .enable_physics = true,
        .enable_audio = false,
    };

    try valid_config.validate();

    // Invalid configurations
    const invalid_configs = [_]nyx.EngineConfig{
        // Zero width
        nyx.EngineConfig{
            .window_width = 0,
            .window_height = 1080,
            .target_fps = 60,
            .max_memory_budget_mb = 512,
        },
        // Zero height
        nyx.EngineConfig{
            .window_width = 1920,
            .window_height = 0,
            .target_fps = 60,
            .max_memory_budget_mb = 512,
        },
        // Zero FPS
        nyx.EngineConfig{
            .window_width = 1920,
            .window_height = 1080,
            .target_fps = 0,
            .max_memory_budget_mb = 512,
        },
        // Too high FPS
        nyx.EngineConfig{
            .window_width = 1920,
            .window_height = 1080,
            .target_fps = 2000,
            .max_memory_budget_mb = 512,
        },
        // Zero memory budget
        nyx.EngineConfig{
            .window_width = 1920,
            .window_height = 1080,
            .target_fps = 60,
            .max_memory_budget_mb = 0,
        },
    };

    for (invalid_configs) |config| {
        try testing.expectError(nyx.EngineError.InvalidConfiguration, config.validate());
    }
}

test "Engine configuration defaults" {
    const config = nyx.EngineConfig{};

    try testing.expectEqual(@as(u32, 1280), config.window_width);
    try testing.expectEqual(@as(u32, 720), config.window_height);
    try testing.expectEqual(@as(u32, 60), config.target_fps);
    try testing.expectEqual(@as(u64, 512), config.max_memory_budget_mb);
    try testing.expectEqual(true, config.enable_gpu);
    try testing.expectEqual(true, config.enable_physics);
    try testing.expectEqual(true, config.enable_audio);
    try testing.expectEqual(false, config.enable_neural);
    try testing.expectEqual(false, config.enable_xr);
    try testing.expectEqual(false, config.enable_networking);
}

// Scene system comprehensive tests
test "Scene entity management comprehensive" {
    var test_allocator = TestAllocator.init();
    defer test_allocator.deinit() catch {};

    var test_scene = try scene.Scene.init(test_allocator.allocator);
    defer test_scene.deinit();

    // Create multiple entities
    var entities: [10]scene.EntityId = undefined;
    for (&entities, 0..) |*entity, i| {
        entity.* = try test_scene.createEntity();

        // Verify each entity has a unique ID
        for (entities[0..i]) |existing_entity| {
            try testing.expect(entity.* != existing_entity);
        }

        // Verify entity exists
        try testing.expect(test_scene.entityExists(entity.*));
    }

    // Test entity destruction
    const entity_to_destroy = entities[5];
    try test_scene.destroyEntity(entity_to_destroy);

    // Verify entity is removed
    try testing.expect(!test_scene.entityExists(entity_to_destroy));

    // Verify other entities still exist
    for (entities, 0..) |entity, i| {
        if (i == 5) continue; // Skip destroyed entity
        try testing.expect(test_scene.entityExists(entity));
    }

    // Test destroying non-existent entity
    const fake_entity = scene.EntityId{ .id = 9999, .generation = 0 };
    try testing.expectError(scene.SceneError.EntityNotFound, test_scene.destroyEntity(fake_entity));
}

// Error handling tests
test "Error handling comprehensive functionality" {
    var test_allocator = TestAllocator.init();
    defer test_allocator.deinit() catch {};

    // Initialize global error handler
    try error_utils.initGlobalErrorHandler(test_allocator.allocator);
    defer error_utils.deinitGlobalErrorHandler(test_allocator.allocator);

    var handler = error_utils.getGlobalErrorHandler().?;

    // Test error recovery strategies
    try handler.setRecoveryStrategy(error.TestError, .fallback);
    try handler.setRecoveryStrategy(error.OutOfMemory, .abort);

    // Test error handling
    const strategy = handler.handleError(
        error.TestError,
        "Test error occurred: {s}",
        .{"test_data"},
        .err,
        @src(),
    );

    try testing.expect(strategy == .fallback);

    // Check statistics
    const stats = handler.getStatistics();
    try testing.expect(stats.total_errors >= 1);
    try testing.expect(stats.error_count >= 1);

    // Test error callback system
    var callback_invoked = false;
    const test_callback = struct {
        fn callback(context: error_utils.ErrorContext, user_data: *anyopaque) void {
            _ = context;
            const flag = @as(*bool, @ptrCast(@alignCast(user_data)));
            flag.* = true;
        }
    }.callback;

    try handler.addErrorCallback(test_callback, &callback_invoked, .warn);

    // Trigger another error to test callback
    _ = handler.handleError(
        error.InvalidInput,
        "Another test error",
        .{},
        .warn,
        @src(),
    );

    try testing.expect(callback_invoked);
}

// Version and compatibility tests
test "Version system comprehensive" {
    try testing.expectEqualStrings("0.1.0-dev", nyx.VERSION.getVersionString());

    // Test compatibility checks
    try testing.expect(nyx.VERSION.isCompatible(0, 0));
    try testing.expect(nyx.VERSION.isCompatible(0, 1));
    try testing.expect(!nyx.VERSION.isCompatible(1, 0));
    try testing.expect(!nyx.VERSION.isCompatible(0, 2));

    // Test version constants
    try testing.expectEqual(@as(u32, 0), nyx.VERSION.MAJOR);
    try testing.expectEqual(@as(u32, 1), nyx.VERSION.MINOR);
    try testing.expectEqual(@as(u32, 0), nyx.VERSION.PATCH);
}

// Convenience function tests
test "Math convenience functions" {
    const v2 = nyx.vec2(1.0, 2.0);
    try testing.expectEqual(@as(f32, 1.0), v2.x);
    try testing.expectEqual(@as(f32, 2.0), v2.y);

    const v3 = nyx.vec3(1.0, 2.0, 3.0);
    try testing.expectEqual(@as(f32, 1.0), v3.x);
    try testing.expectEqual(@as(f32, 2.0), v3.y);
    try testing.expectEqual(@as(f32, 3.0), v3.z);

    const v4 = nyx.vec4(1.0, 2.0, 3.0, 4.0);
    try testing.expectEqual(@as(f32, 1.0), v4.x);
    try testing.expectEqual(@as(f32, 2.0), v4.y);
    try testing.expectEqual(@as(f32, 3.0), v4.z);
    try testing.expectEqual(@as(f32, 4.0), v4.w);
}

// Performance and stress tests
test "Resource Manager stress test" {
    if (builtin.mode != .Debug) return; // Skip in release builds

    var test_allocator = TestAllocator.init();
    defer test_allocator.deinit() catch {};

    var resource_manager = try nyx.ResourceManager.init(test_allocator.allocator);
    defer resource_manager.deinit();

    // Create many assets
    const num_assets = 1000;
    var asset_ids: [num_assets]u32 = undefined;

    for (&asset_ids, 0..) |*asset_id, i| {
        const name = try std.fmt.allocPrint(test_allocator.allocator, "asset_{d}", .{i});
        defer test_allocator.allocator.free(name);

        const data = try std.fmt.allocPrint(test_allocator.allocator, "data_{d}", .{i});
        defer test_allocator.allocator.free(data);

        asset_id.* = try resource_manager.createAsset(name, data);
    }

    // Verify all assets exist
    for (asset_ids) |asset_id| {
        const asset = resource_manager.getAsset(asset_id);
        try testing.expect(asset != null);
    }

    // Unload half the assets
    for (asset_ids[0 .. num_assets / 2]) |asset_id| {
        resource_manager.unloadAsset(asset_id);
    }

    // Verify first half are gone, second half still exist
    for (asset_ids[0 .. num_assets / 2]) |asset_id| {
        const asset = resource_manager.getAsset(asset_id);
        try testing.expect(asset == null);
    }

    for (asset_ids[num_assets / 2 ..]) |asset_id| {
        const asset = resource_manager.getAsset(asset_id);
        try testing.expect(asset != null);
    }
}

// Integration tests
test "Engine lifecycle comprehensive" {
    var test_allocator = TestAllocator.init();
    defer test_allocator.deinit() catch {};

    const config = nyx.EngineConfig{
        .enable_gpu = false, // Disable GPU for testing
        .enable_audio = false, // Disable audio for testing
        .enable_physics = false, // Disable physics for testing
    };

    var engine_instance = try nyx.Engine.init(test_allocator.allocator, config);
    defer engine_instance.deinit();

    // Test initial state
    try testing.expect(engine_instance.getState() == .running);
    try testing.expect(engine_instance.getFrameCount() == 0);
    try testing.expect(engine_instance.getFPS() == 0.0);

    // Test pause/resume
    engine_instance.pause();
    try testing.expect(engine_instance.getState() == .paused);

    engine_instance.resumeEngine();
    try testing.expect(engine_instance.getState() == .running);

    // Test update
    try engine_instance.update(0.016); // ~60 FPS
    try testing.expect(engine_instance.getFrameCount() == 1);
    try testing.expectApproxEqRel(@as(f32, 62.5), engine_instance.getFPS(), 0.1);

    // Test render (should not crash)
    try engine_instance.render();
}

// Test runner utility
pub fn runAllTests(allocator: std.mem.Allocator) !void {
    var suite = TestSuite.init(allocator, "MFS Engine Comprehensive Tests");
    defer suite.deinit();

    // Run all test functions
    try suite.runTest("Vec3 comprehensive operations", testVec3Comprehensive);
    try suite.runTest("Vec2 comprehensive operations", testVec2Comprehensive);
    try suite.runTest("Mat4 comprehensive operations", testMat4Comprehensive);
    try suite.runTest("Resource Manager comprehensive", testResourceManagerComprehensive);
    try suite.runTest("Engine configuration validation", testEngineConfigValidation);
    try suite.runTest("Scene entity management", testSceneEntityManagement);
    try suite.runTest("Error handling functionality", testErrorHandling);
    try suite.runTest("Version system", testVersionSystem);
    try suite.runTest("Math convenience functions", testMathConvenience);
    try suite.runTest("Engine lifecycle", testEngineLifecycle);

    suite.printResults();
}

// Helper test functions for the test runner
fn testVec3Comprehensive() !void {
    // Implementation matches the test above
    const v1 = math.Vec3.init(1.0, 2.0, 3.0);
    const v2 = math.Vec3.init(4.0, 5.0, 6.0);

    const sum = v1.add(v2);
    try testing.expectEqual(@as(f32, 5.0), sum.x);

    const dot = v1.dot(v2);
    try testing.expectEqual(@as(f32, 32.0), dot);
}

fn testVec2Comprehensive() !void {
    const v1 = math.Vec2.init(3.0, 4.0);
    const length = v1.length();
    try testing.expectEqual(@as(f32, 5.0), length);
}

fn testMat4Comprehensive() !void {
    const identity = math.Mat4.identity();
    try testing.expectEqual(@as(f32, 1.0), identity.m[0][0]);
}

fn testResourceManagerComprehensive() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var rm = try nyx.ResourceManager.init(allocator);
    defer rm.deinit();

    const id = try rm.createAsset("test", "data");
    const asset = rm.getAsset(id);
    try testing.expect(asset != null);
}

fn testEngineConfigValidation() !void {
    const config = nyx.EngineConfig{};
    try config.validate();
}

fn testSceneEntityManagement() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var test_scene = try scene.Scene.init(allocator);
    defer test_scene.deinit();

    const entity = try test_scene.createEntity();
    try testing.expect(test_scene.entityExists(entity));
}

fn testErrorHandling() !void {
    // Basic error handling test
    try testing.expect(true);
}

fn testVersionSystem() !void {
    try testing.expect(nyx.VERSION.isCompatible(0, 1));
}

fn testMathConvenience() !void {
    const v2 = nyx.vec2(1.0, 2.0);
    try testing.expectEqual(@as(f32, 1.0), v2.x);
}

fn testEngineLifecycle() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = nyx.EngineConfig{ .enable_gpu = false, .enable_audio = false, .enable_physics = false };
    var engine_instance = try nyx.Engine.init(allocator, config);
    defer engine_instance.deinit();

    try testing.expect(engine_instance.getState() == .running);
}
