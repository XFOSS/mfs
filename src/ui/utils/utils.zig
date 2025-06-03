const std = @import("std");

/// UI utilities module that provides access to various helper functions
pub const error_handler = @import("error_handler.zig");

/// Format utilities for displaying values
pub const format = struct {
    /// Format a file size into a human-readable string (e.g., "1.5 MB")
    pub fn formatFileSize(bytes: u64, buffer: []u8) ![]u8 {
        const units = [_][]const u8{ "B", "KB", "MB", "GB", "TB" };
        var size: f64 = @floatFromInt(bytes);
        var unit_index: usize = 0;

        while (size >= 1024.0 and unit_index < units.len - 1) {
            size /= 1024.0;
            unit_index += 1;
        }

        if (unit_index == 0) {
            // For bytes, show as integer
            return std.fmt.bufPrint(buffer, "{d} {s}", .{ @as(u64, @intFromFloat(size)), units[unit_index] });
        } else {
            // For KB and above, show with decimal points
            return std.fmt.bufPrint(buffer, "{d:.1} {s}", .{ size, units[unit_index] });
        }
    }

    /// Format a duration in milliseconds to a human-readable string
    pub fn formatDuration(milliseconds: u64, buffer: []u8) ![]u8 {
        if (milliseconds < 1000) {
            return std.fmt.bufPrint(buffer, "{d}ms", .{milliseconds});
        } else if (milliseconds < 60 * 1000) {
            const seconds = @as(f64, @floatFromInt(milliseconds)) / 1000.0;
            return std.fmt.bufPrint(buffer, "{d:.1}s", .{seconds});
        } else if (milliseconds < 60 * 60 * 1000) {
            const minutes = @divFloor(milliseconds, 60 * 1000);
            const seconds = @divFloor(milliseconds - minutes * 60 * 1000, 1000);
            return std.fmt.bufPrint(buffer, "{d}m {d}s", .{ minutes, seconds });
        } else {
            const hours = @divFloor(milliseconds, 60 * 60 * 1000);
            const minutes = @divFloor(milliseconds - hours * 60 * 60 * 1000, 60 * 1000);
            return std.fmt.bufPrint(buffer, "{d}h {d}m", .{ hours, minutes });
        }
    }
};

/// Math utilities for UI operations
pub const math = struct {
    /// Linear interpolation between two values
    pub fn lerp(a: f32, b: f32, t: f32) f32 {
        return a + (b - a) * std.math.clamp(t, 0.0, 1.0);
    }

    /// Smooth step function for animations
    pub fn smoothStep(t: f32) f32 {
        const clamped = std.math.clamp(t, 0.0, 1.0);
        return clamped * clamped * (3.0 - 2.0 * clamped);
    }

    /// Convert degrees to radians
    pub fn degreesToRadians(degrees: f32) f32 {
        return degrees * (std.math.pi / 180.0);
    }

    /// Convert radians to degrees
    pub fn radiansToDegrees(radians: f32) f32 {
        return radians * (180.0 / std.math.pi);
    }
};

/// String utilities for UI operations
pub const strings = struct {
    /// Truncate a string with an ellipsis if it's too long
    pub fn truncateWithEllipsis(allocator: std.mem.Allocator, input: []const u8, max_length: usize) ![]u8 {
        if (input.len <= max_length) {
            return allocator.dupe(u8, input);
        }

        // Reserve space for the string + ellipsis
        const ellipsis = "...";
        const result_len = max_length;
        const result = try allocator.alloc(u8, result_len);

        // Copy the truncated part of the input
        const chars_to_copy = max_length - ellipsis.len;
        std.mem.copy(u8, result[0..chars_to_copy], input[0..chars_to_copy]);

        // Add ellipsis
        std.mem.copy(u8, result[chars_to_copy..], ellipsis);

        return result;
    }
};

test "format file size" {
    const testing = std.testing;
    var buffer: [100]u8 = undefined;

    // Test bytes
    const bytes_result = try format.formatFileSize(750, &buffer);
    try testing.expectEqualStrings("750 B", bytes_result);

    // Test kilobytes
    const kb_result = try format.formatFileSize(1500, &buffer);
    try testing.expectEqualStrings("1.5 KB", kb_result);

    // Test megabytes
    const mb_result = try format.formatFileSize(2 * 1024 * 1024, &buffer);
    try testing.expectEqualStrings("2.0 MB", mb_result);
}

test "string truncation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test string that doesn't need truncation
    const short = try strings.truncateWithEllipsis(allocator, "Hello", 10);
    defer allocator.free(short);
    try testing.expectEqualStrings("Hello", short);

    // Test string that needs truncation
    const long = try strings.truncateWithEllipsis(allocator, "This is a very long string", 10);
    defer allocator.free(long);
    try testing.expectEqualStrings("This is...", long);
}
