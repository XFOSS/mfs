//! MFS Engine - Utils Module
//! Utility functions and helper types used throughout the engine
//! Provides common functionality, error handling, and convenience functions
//! @thread-safe Utility functions are generally thread-safe unless noted
//! @performance Optimized for common use cases

const std = @import("std");
const builtin = @import("builtin");

// Core utility components
pub const utils = @import("utils.zig");
pub const error_utils = @import("error_utils.zig");

// Re-export main utility types
pub const ErrorHandler = error_utils.ErrorHandler;
pub const ErrorInfo = error_utils.ErrorInfo;

// Common utility functions
pub fn clamp(comptime T: type, value: T, min_val: T, max_val: T) T {
    return @max(min_val, @min(max_val, value));
}

pub fn lerp(comptime T: type, a: T, b: T, t: f32) T {
    return switch (@typeInfo(T)) {
        .Float => a + (b - a) * t,
        .Int => @intFromFloat(@as(f32, @floatFromInt(a)) + (@as(f32, @floatFromInt(b)) - @as(f32, @floatFromInt(a))) * t),
        else => @compileError("lerp only supports float and integer types"),
    };
}

pub fn map(comptime T: type, value: T, in_min: T, in_max: T, out_min: T, out_max: T) T {
    return out_min + (value - in_min) * (out_max - out_min) / (in_max - in_min);
}

pub fn isPowerOfTwo(value: anytype) bool {
    return value > 0 and (value & (value - 1)) == 0;
}

pub fn nextPowerOfTwo(value: anytype) @TypeOf(value) {
    const T = @TypeOf(value);
    if (value <= 1) return 1;

    var result: T = 1;
    while (result < value) {
        result <<= 1;
    }
    return result;
}

pub fn alignUp(value: anytype, alignment: @TypeOf(value)) @TypeOf(value) {
    const mask = alignment - 1;
    return (value + mask) & ~mask;
}

pub fn alignDown(value: anytype, alignment: @TypeOf(value)) @TypeOf(value) {
    const mask = alignment - 1;
    return value & ~mask;
}

// String utilities
pub fn stringEquals(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

pub fn stringStartsWith(haystack: []const u8, needle: []const u8) bool {
    return std.mem.startsWith(u8, haystack, needle);
}

pub fn stringEndsWith(haystack: []const u8, needle: []const u8) bool {
    return std.mem.endsWith(u8, haystack, needle);
}

pub fn stringContains(haystack: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
}

// Hash utilities
pub fn hashString(s: []const u8) u64 {
    return std.hash_map.hashString(s);
}

pub fn hashBytes(bytes: []const u8) u64 {
    return std.hash.Wyhash.hash(0, bytes);
}

// Time utilities
pub const Timer = struct {
    start_time: i64,

    const Self = @This();

    pub fn start() Self {
        return Self{
            .start_time = std.time.nanoTimestamp(),
        };
    }

    pub fn elapsed(self: Self) i64 {
        return std.time.nanoTimestamp() - self.start_time;
    }

    pub fn elapsedMs(self: Self) f64 {
        return @as(f64, @floatFromInt(self.elapsed())) / std.time.ns_per_ms;
    }

    pub fn elapsedUs(self: Self) f64 {
        return @as(f64, @floatFromInt(self.elapsed())) / std.time.ns_per_us;
    }

    pub fn reset(self: *Self) void {
        self.start_time = std.time.nanoTimestamp();
    }
};

// Random utilities
pub const Random = struct {
    rng: std.rand.DefaultPrng,

    const Self = @This();

    pub fn init(seed: u64) Self {
        return Self{
            .rng = std.rand.DefaultPrng.init(seed),
        };
    }

    pub fn initWithTime() Self {
        const seed = @as(u64, @intCast(std.time.timestamp()));
        return Self.init(seed);
    }

    pub fn float(self: *Self, comptime T: type) T {
        return self.rng.random().float(T);
    }

    pub fn int(self: *Self, comptime T: type) T {
        return self.rng.random().int(T);
    }

    pub fn intRange(self: *Self, comptime T: type, min_val: T, max_val: T) T {
        return self.rng.random().intRangeAtMost(T, min_val, max_val);
    }

    pub fn floatRange(self: *Self, comptime T: type, min_val: T, max_val: T) T {
        return min_val + self.float(T) * (max_val - min_val);
    }

    pub fn boolean(self: *Self) bool {
        return self.rng.random().boolean();
    }
};

test "utils module" {
    const testing = std.testing;

    // Test clamp
    try testing.expect(clamp(i32, 5, 0, 10) == 5);
    try testing.expect(clamp(i32, -5, 0, 10) == 0);
    try testing.expect(clamp(i32, 15, 0, 10) == 10);

    // Test power of two
    try testing.expect(isPowerOfTwo(@as(u32, 8)));
    try testing.expect(!isPowerOfTwo(@as(u32, 6)));
    try testing.expect(nextPowerOfTwo(@as(u32, 6)) == 8);

    // Test string utilities
    try testing.expect(stringEquals("hello", "hello"));
    try testing.expect(!stringEquals("hello", "world"));
    try testing.expect(stringStartsWith("hello world", "hello"));
    try testing.expect(stringEndsWith("hello world", "world"));
    try testing.expect(stringContains("hello world", "lo wo"));

    std.testing.refAllDecls(@This());
}
