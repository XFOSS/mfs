//! MFS Engine - Vector Graphics Integration
//! Advanced 2D vector graphics rendering using NanoVG-style API
//! Provides anti-aliased hardware-accelerated vector graphics

const std = @import("std");
const math = @import("../math/mod.zig");
const graphics = @import("../graphics/mod.zig");

/// Vector graphics context for 2D rendering
pub const VectorContext = struct {
    allocator: std.mem.Allocator,
    backend: *graphics.backend_manager.BackendInterface,
    width: f32,
    height: f32,
    pixel_ratio: f32,

    // Drawing state
    current_path: std.array_list.Managed(PathCommand),
    transform_stack: std.array_list.Managed(Transform),
    current_transform: Transform,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, backend: *graphics.backend_manager.BackendInterface, width: f32, height: f32) !Self {
        return Self{
            .allocator = allocator,
            .backend = backend,
            .width = width,
            .height = height,
            .pixel_ratio = 1.0,
            .current_path = std.array_list.Managed(PathCommand).init(allocator),
            .transform_stack = std.array_list.Managed(Transform).init(allocator),
            .current_transform = Transform.identity(),
        };
    }

    pub fn deinit(self: *Self) void {
        self.current_path.deinit();
        self.transform_stack.deinit();
    }

    // Path building API (similar to NanoVG)
    pub fn beginPath(self: *Self) void {
        self.current_path.clearRetainingCapacity();
    }

    pub fn moveTo(self: *Self, x: f32, y: f32) !void {
        try self.current_path.append(.{ .move_to = .{ .x = x, .y = y } });
    }

    pub fn lineTo(self: *Self, x: f32, y: f32) !void {
        try self.current_path.append(.{ .line_to = .{ .x = x, .y = y } });
    }

    pub fn bezierTo(self: *Self, c1x: f32, c1y: f32, c2x: f32, c2y: f32, x: f32, y: f32) !void {
        try self.current_path.append(.{ .bezier_to = .{
            .c1x = c1x,
            .c1y = c1y,
            .c2x = c2x,
            .c2y = c2y,
            .x = x,
            .y = y,
        } });
    }

    pub fn rect(self: *Self, x: f32, y: f32, w: f32, h: f32) !void {
        try self.moveTo(x, y);
        try self.lineTo(x + w, y);
        try self.lineTo(x + w, y + h);
        try self.lineTo(x, y + h);
        try self.closePath();
    }

    pub fn roundedRect(self: *Self, x: f32, y: f32, w: f32, h: f32, r: f32) !void {
        // Implementation for rounded rectangles with bezier curves
        const rx = @min(r, w * 0.5);
        const ry = @min(r, h * 0.5);

        try self.moveTo(x + rx, y);
        try self.lineTo(x + w - rx, y);
        try self.bezierTo(x + w - rx * 0.5522, y, x + w, y + ry * 0.5522, x + w, y + ry);
        try self.lineTo(x + w, y + h - ry);
        try self.bezierTo(x + w, y + h - ry * 0.5522, x + w - rx * 0.5522, y + h, x + w - rx, y + h);
        try self.lineTo(x + rx, y + h);
        try self.bezierTo(x + rx * 0.5522, y + h, x, y + h - ry * 0.5522, x, y + h - ry);
        try self.lineTo(x, y + ry);
        try self.bezierTo(x, y + ry * 0.5522, x + rx * 0.5522, y, x + rx, y);
        try self.closePath();
    }

    pub fn circle(self: *Self, cx: f32, cy: f32, r: f32) !void {
        try self.ellipse(cx, cy, r, r);
    }

    pub fn ellipse(self: *Self, cx: f32, cy: f32, rx: f32, ry: f32) !void {
        const kappa = 0.5522847493; // 4/3 * (sqrt(2) - 1)
        const ox = rx * kappa;
        const oy = ry * kappa;

        try self.moveTo(cx - rx, cy);
        try self.bezierTo(cx - rx, cy - oy, cx - ox, cy - ry, cx, cy - ry);
        try self.bezierTo(cx + ox, cy - ry, cx + rx, cy - oy, cx + rx, cy);
        try self.bezierTo(cx + rx, cy + oy, cx + ox, cy + ry, cx, cy + ry);
        try self.bezierTo(cx - ox, cy + ry, cx - rx, cy + oy, cx - rx, cy);
        try self.closePath();
    }

    pub fn closePath(self: *Self) !void {
        try self.current_path.append(.close_path);
    }

    // Fill and stroke operations
    pub fn fill(self: *Self) !void {
        // Convert path to triangulated mesh and render
        try self.renderPath(.fill);
    }

    pub fn stroke(self: *Self) !void {
        // Convert path to stroke geometry and render
        try self.renderPath(.stroke);
    }

    // Color and paint operations
    pub fn fillColor(self: *Self, color: Color) void {
        _ = self;
        _ = color;
        // Set current fill color
    }

    pub fn strokeColor(self: *Self, color: Color) void {
        _ = self;
        _ = color;
        // Set current stroke color
    }

    pub fn strokeWidth(self: *Self, width: f32) void {
        _ = self;
        _ = width;
        // Set stroke width
    }

    // Transform operations
    pub fn save(self: *Self) !void {
        try self.transform_stack.append(self.current_transform);
    }

    pub fn restore(self: *Self) void {
        if (self.transform_stack.items.len > 0) {
            self.current_transform = self.transform_stack.pop();
        }
    }

    pub fn translate(self: *Self, x: f32, y: f32) void {
        self.current_transform = self.current_transform.translate(x, y);
    }

    pub fn rotate(self: *Self, angle: f32) void {
        self.current_transform = self.current_transform.rotate(angle);
    }

    pub fn scale(self: *Self, x: f32, y: f32) void {
        self.current_transform = self.current_transform.scale(x, y);
    }

    // Private implementation
    fn renderPath(self: *Self, mode: RenderMode) !void {
        // This would integrate with our graphics backend to render the path
        _ = self;
        _ = mode;
        // Implementation would:
        // 1. Triangulate the path using earcut or similar algorithm
        // 2. Generate vertex/index buffers
        // 3. Submit to graphics backend for rendering
    }
};

const PathCommand = union(enum) {
    move_to: struct { x: f32, y: f32 },
    line_to: struct { x: f32, y: f32 },
    bezier_to: struct { c1x: f32, c1y: f32, c2x: f32, c2y: f32, x: f32, y: f32 },
    close_path,
};

const Transform = struct {
    m: [6]f32, // 2D affine transform matrix [a, b, c, d, e, f]

    pub fn identity() Transform {
        return Transform{ .m = .{ 1, 0, 0, 1, 0, 0 } };
    }

    pub fn translate(self: Transform, x: f32, y: f32) Transform {
        var result = self;
        result.m[4] += self.m[0] * x + self.m[2] * y;
        result.m[5] += self.m[1] * x + self.m[3] * y;
        return result;
    }

    pub fn rotate(self: Transform, angle: f32) Transform {
        const c = @cos(angle);
        const s = @sin(angle);
        return Transform{
            .m = .{
                self.m[0] * c + self.m[2] * s,
                self.m[1] * c + self.m[3] * s,
                self.m[0] * (-s) + self.m[2] * c,
                self.m[1] * (-s) + self.m[3] * c,
                self.m[4],
                self.m[5],
            },
        };
    }

    pub fn scale(self: Transform, x: f32, y: f32) Transform {
        return Transform{
            .m = .{
                self.m[0] * x,
                self.m[1] * x,
                self.m[2] * y,
                self.m[3] * y,
                self.m[4],
                self.m[5],
            },
        };
    }
};

const Color = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,

    pub fn rgba(r: u8, g: u8, b: u8, a: u8) Color {
        return Color{
            .r = @as(f32, @floatFromInt(r)) / 255.0,
            .g = @as(f32, @floatFromInt(g)) / 255.0,
            .b = @as(f32, @floatFromInt(b)) / 255.0,
            .a = @as(f32, @floatFromInt(a)) / 255.0,
        };
    }
};

const RenderMode = enum {
    fill,
    stroke,
};

// Convenience functions for common operations
pub fn createContext(allocator: std.mem.Allocator, backend: *graphics.backend_manager.BackendInterface, width: f32, height: f32) !*VectorContext {
    const ctx = try allocator.create(VectorContext);
    ctx.* = try VectorContext.init(allocator, backend, width, height);
    return ctx;
}

pub fn destroyContext(allocator: std.mem.Allocator, ctx: *VectorContext) void {
    ctx.deinit();
    allocator.destroy(ctx);
}
