const std = @import("std");
const Allocator = std.mem.Allocator;

pub const StringUtils = struct {
    pub fn startsWith(str: []const u8, prefix: []const u8) bool {
        if (prefix.len > str.len) return false;
        return std.mem.eql(u8, str[0..prefix.len], prefix);
    }

    pub fn endsWith(str: []const u8, suffix: []const u8) bool {
        if (suffix.len > str.len) return false;
        return std.mem.eql(u8, str[str.len - suffix.len ..], suffix);
    }

    pub fn contains(str: []const u8, needle: []const u8) bool {
        return std.mem.indexOf(u8, str, needle) != null;
    }
};

pub const MathUtils = struct {
    pub fn lerp(a: f32, b: f32, t: f32) f32 {
        return a + (b - a) * t;
    }

    pub fn clamp(value: f32, min_val: f32, max_val: f32) f32 {
        return @max(min_val, @min(max_val, value));
    }

    pub fn radians(degrees_val: f32) f32 {
        return degrees_val * (std.math.pi / 180.0);
    }

    pub fn degrees(radians_val: f32) f32 {
        return radians_val * (180.0 / std.math.pi);
    }
};

pub const TimeUtils = struct {
    pub fn getCurrentTimeMs() i64 {
        return std.time.milliTimestamp();
    }

    pub fn getCurrentTimeNs() i128 {
        return std.time.nanoTimestamp();
    }

    pub fn sleep(ms: u64) void {
        std.time.sleep(ms * 1_000_000);
    }
};

pub const HashUtils = struct {
    pub fn hashString(str: []const u8) u64 {
        return std.hash_map.hashString(str);
    }

    pub fn hashBytes(bytes: []const u8) u64 {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(bytes);
        return hasher.final();
    }
};

pub const Logger = struct {
    pub fn info(comptime fmt: []const u8, args: anytype) void {
        std.log.info(fmt, args);
    }

    pub fn warn(comptime fmt: []const u8, args: anytype) void {
        std.log.warn(fmt, args);
    }

    pub fn err(comptime fmt: []const u8, args: anytype) void {
        std.log.err(fmt, args);
    }

    pub fn debug(comptime fmt: []const u8, args: anytype) void {
        std.log.debug(fmt, args);
    }
};

test "string utils" {
    try std.testing.expect(StringUtils.startsWith("hello world", "hello"));
    try std.testing.expect(StringUtils.endsWith("hello world", "world"));
    try std.testing.expect(StringUtils.contains("hello world", "lo wo"));
}

test "math utils" {
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), MathUtils.lerp(0.0, 1.0, 0.5), 0.001);
    try std.testing.expectEqual(@as(f32, 5.0), MathUtils.clamp(10.0, 0.0, 5.0));
}
