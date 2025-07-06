//! Pathfinding Implementation (Stub)

const std = @import("std");
const math = @import("../math/mod.zig");
const Vec3 = math.Vec3;

pub const PathfindingSystem = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !PathfindingSystem {
        return PathfindingSystem{ .allocator = allocator };
    }

    pub fn deinit(self: *PathfindingSystem) void {
        _ = self;
    }

    pub fn update(self: *PathfindingSystem, delta_time: f32) !void {
        _ = self;
        _ = delta_time;
    }

    pub fn getActiveRequests(self: *PathfindingSystem) u32 {
        _ = self;
        return 0;
    }
};

pub const Pathfinder = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Pathfinder {
        return Pathfinder{ .allocator = allocator };
    }

    pub fn deinit(self: *Pathfinder) void {
        _ = self;
    }

    pub fn findPath(self: *Pathfinder, start: Vec3, end: Vec3) !?[]Vec3 {
        _ = self;
        _ = start;
        _ = end;
        return null;
    }
};
