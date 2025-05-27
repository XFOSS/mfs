const std = @import("std");

pub const vulkan = @import("vulkan/backend.zig");
pub const render = @import("render/software_cube.zig");
pub const material = @import("vulkan/material.zig");
pub const cube = @import("vulkan/cube.zig");
pub const vk = @import("vulkan/vk.zig");
pub const physics = @import("physics/physics.zig");
pub const ui = @import("ui/window.zig");

pub const Vec2 = struct {
    x: f32,
    y: f32,

    pub fn new(x: f32, y: f32) Vec2 {
        return Vec2{ .x = x, .y = y };
    }
};

pub const Vec3 = struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn new(x: f32, y: f32, z: f32) Vec3 {
        return Vec3{ .x = x, .y = y, .z = z };
    }
};

test "basic functionality" {
    const v = Vec2.new(1, 2);
    try std.testing.expectEqual(@as(f32, 1), v.x);
}
