//! Debug utilities for MFS Engine
//! Provides debugging tools and introspection capabilities

const std = @import("std");

pub const DebugLevel = enum {
    trace,
    debug,
    info,
    warn,
    err,
};

pub const Debugger = struct {
    level: DebugLevel,
    enabled: bool,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, level: DebugLevel) Debugger {
        return Debugger{
            .level = level,
            .enabled = true,
            .allocator = allocator,
        };
    }

    pub fn log(self: *Debugger, level: DebugLevel, comptime format: []const u8, args: anytype) void {
        if (!self.enabled) return;
        if (@intFromEnum(level) < @intFromEnum(self.level)) return;

        const prefix = switch (level) {
            .trace => "[TRACE]",
            .debug => "[DEBUG]",
            .info => "[INFO]",
            .warn => "[WARN]",
            .err => "[ERROR]",
        };

        std.log.info("{s} " ++ format, .{prefix} ++ args);
    }

    pub fn setLevel(self: *Debugger, level: DebugLevel) void {
        self.level = level;
    }

    pub fn enable(self: *Debugger) void {
        self.enabled = true;
    }

    pub fn disable(self: *Debugger) void {
        self.enabled = false;
    }
};
