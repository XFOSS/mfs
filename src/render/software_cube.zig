const std = @import("std");
const math = std.math;
const Allocator = std.mem.Allocator;

// Windows API types for drawing
const HDC = *opaque {};
const RECT = extern struct {
    left: i32,
    top: i32,
    right: i32,
    bottom: i32,
};

// External drawing functions
extern "gdi32" fn SetPixel(hdc: HDC, x: i32, y: i32, color: u32) callconv(.C) u32;
extern "gdi32" fn MoveToEx(hdc: HDC, x: i32, y: i32, pt: ?*anyopaque) callconv(.C) i32;
extern "gdi32" fn LineTo(hdc: HDC, x: i32, y: i32) callconv(.C) i32;
extern "gdi32" fn CreatePen(style: i32, width: i32, color: u32) callconv(.C) *opaque {};
extern "gdi32" fn SelectObject(hdc: HDC, obj: *opaque {}) callconv(.C) *opaque {};
extern "gdi32" fn DeleteObject(obj: *opaque {}) callconv(.C) i32;

// 3D Math structures
pub const Vec3 = struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn new(x: f32, y: f32, z: f32) Vec3 {
        return Vec3{ .x = x, .y = y, .z = z };
    }

    pub fn add(a: Vec3, b: Vec3) Vec3 {
        return Vec3.new(a.x + b.x, a.y + b.y, a.z + b.z);
    }

    pub fn scale(v: Vec3, s: f32) Vec3 {
        return Vec3.new(v.x * s, v.y * s, v.z * s);
    }

    pub fn normalize(v: Vec3) Vec3 {
        const len = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
        if (len == 0.0) return v;
        return Vec3.new(v.x / len, v.y / len, v.z / len);
    }
};

pub const Vec2 = struct {
    x: f32,
    y: f32,

    pub fn new(x: f32, y: f32) Vec2 {
        return Vec2{ .x = x, .y = y };
    }
};

pub const Mat4 = struct {
    data: [16]f32,

    pub fn identity() Mat4 {
        return Mat4{
            .data = [_]f32{
                1.0, 0.0, 0.0, 0.0,
                0.0, 1.0, 0.0, 0.0,
                0.0, 0.0, 1.0, 0.0,
                0.0, 0.0, 0.0, 1.0,
            },
        };
    }

    pub fn rotateY(angle: f32) Mat4 {
        const c = math.cos(angle);
        const s = math.sin(angle);

        return Mat4{
            .data = [_]f32{
                c,   0.0, s,   0.0,
                0.0, 1.0, 0.0, 0.0,
                -s,  0.0, c,   0.0,
                0.0, 0.0, 0.0, 1.0,
            },
        };
    }

    pub fn rotateX(angle: f32) Mat4 {
        const c = math.cos(angle);
        const s = math.sin(angle);

        return Mat4{
            .data = [_]f32{
                1.0, 0.0, 0.0, 0.0,
                0.0, c,   -s,  0.0,
                0.0, s,   c,   0.0,
                0.0, 0.0, 0.0, 1.0,
            },
        };
    }

    pub fn translate(x: f32, y: f32, z: f32) Mat4 {
        return Mat4{
            .data = [_]f32{
                1.0, 0.0, 0.0, 0.0,
                0.0, 1.0, 0.0, 0.0,
                0.0, 0.0, 1.0, 0.0,
                x,   y,   z,   1.0,
            },
        };
    }

    pub fn multiply(a: Mat4, b: Mat4) Mat4 {
        var result = Mat4{ .data = [_]f32{0.0} ** 16 };

        for (0..4) |row| {
            for (0..4) |col| {
                var sum: f32 = 0.0;
                for (0..4) |k| {
                    sum += a.data[row * 4 + k] * b.data[k * 4 + col];
                }
                result.data[row * 4 + col] = sum;
            }
        }

        return result;
    }

    pub fn transformPoint(m: Mat4, v: Vec3) Vec3 {
        const x = m.data[0] * v.x + m.data[4] * v.y + m.data[8] * v.z + m.data[12];
        const y = m.data[1] * v.x + m.data[5] * v.y + m.data[9] * v.z + m.data[13];
        const z = m.data[2] * v.x + m.data[6] * v.y + m.data[10] * v.z + m.data[14];
        return Vec3.new(x, y, z);
    }
};

// Cube vertices
const cube_vertices = [_]Vec3{
    // Front face
    Vec3.new(-1.0, -1.0, 1.0),
    Vec3.new(1.0, -1.0, 1.0),
    Vec3.new(1.0, 1.0, 1.0),
    Vec3.new(-1.0, 1.0, 1.0),

    // Back face
    Vec3.new(-1.0, -1.0, -1.0),
    Vec3.new(1.0, -1.0, -1.0),
    Vec3.new(1.0, 1.0, -1.0),
    Vec3.new(-1.0, 1.0, -1.0),
};

// Cube edges (connecting vertices)
const cube_edges = [_][2]u8{
    // Front face
    [2]u8{ 0, 1 }, [2]u8{ 1, 2 }, [2]u8{ 2, 3 }, [2]u8{ 3, 0 },
    // Back face
    [2]u8{ 4, 5 }, [2]u8{ 5, 6 }, [2]u8{ 6, 7 }, [2]u8{ 7, 4 },
    // Connecting front to back
    [2]u8{ 0, 4 }, [2]u8{ 1, 5 }, [2]u8{ 2, 6 }, [2]u8{ 3, 7 },
};

// Color palette
const colors = [_]u32{
    0x00FF0000, // Red
    0x0000FF00, // Green
    0x000000FF, // Blue
    0x00FFFF00, // Yellow
    0x00FF00FF, // Magenta
    0x0000FFFF, // Cyan
};

pub const SoftwareCube = struct {
    rotation_x: f32,
    rotation_y: f32,
    scale: f32,
    center_x: i32,
    center_y: i32,
    current_color: usize,

    const Self = @This();

    pub fn init(center_x: i32, center_y: i32) Self {
        return Self{
            .rotation_x = 0.0,
            .rotation_y = 0.0,
            .scale = 100.0,
            .center_x = center_x,
            .center_y = center_y,
            .current_color = 0,
        };
    }

    pub fn update(self: *Self, dt: f32) void {
        self.rotation_x += dt * 0.8;
        self.rotation_y += dt * 1.2;

        // Keep rotations in range
        if (self.rotation_x > 2.0 * math.pi) self.rotation_x -= 2.0 * math.pi;
        if (self.rotation_y > 2.0 * math.pi) self.rotation_y -= 2.0 * math.pi;
    }

    pub fn setColor(self: *Self, color_index: usize) void {
        self.current_color = color_index % colors.len;
    }

    pub fn setCenter(self: *Self, x: i32, y: i32) void {
        self.center_x = x;
        self.center_y = y;
    }

    pub fn setScale(self: *Self, scale: f32) void {
        self.scale = @max(10.0, @min(500.0, scale));
    }

    fn projectPoint(self: *Self, point: Vec3) Vec2 {
        // Simple perspective projection
        const perspective_distance = 400.0;
        const projected_x = (point.x * perspective_distance) / (perspective_distance + point.z);
        const projected_y = (point.y * perspective_distance) / (perspective_distance + point.z);

        return Vec2.new(@as(f32, @floatFromInt(self.center_x)) + projected_x * self.scale, @as(f32, @floatFromInt(self.center_y)) - projected_y * self.scale);
    }

    pub fn render(self: *Self, hdc: HDC) void {
        // Create transformation matrix
        const rot_x = Mat4.rotateX(self.rotation_x);
        const rot_y = Mat4.rotateY(self.rotation_y);
        const transform = Mat4.multiply(rot_y, rot_x);

        // Transform vertices
        var transformed_vertices: [8]Vec3 = undefined;
        for (cube_vertices, 0..) |vertex, i| {
            transformed_vertices[i] = Mat4.transformPoint(transform, vertex);
        }

        // Project to 2D
        var projected_vertices: [8]Vec2 = undefined;
        for (transformed_vertices, 0..) |vertex, i| {
            projected_vertices[i] = self.projectPoint(vertex);
        }

        // Create pen for drawing
        const pen = CreatePen(0, 2, colors[self.current_color]);
        const old_pen = SelectObject(hdc, pen);

        // Draw edges
        for (cube_edges) |edge| {
            const start = projected_vertices[edge[0]];
            const end = projected_vertices[edge[1]];

            _ = MoveToEx(hdc, @as(i32, @intFromFloat(start.x)), @as(i32, @intFromFloat(start.y)), null);
            _ = LineTo(hdc, @as(i32, @intFromFloat(end.x)), @as(i32, @intFromFloat(end.y)));
        }

        // Draw vertices as points
        for (projected_vertices, 0..) |vertex, i| {
            const x = @as(i32, @intFromFloat(vertex.x));
            const y = @as(i32, @intFromFloat(vertex.y));

            // Draw a small cross for each vertex
            const vertex_color = colors[(i + self.current_color) % colors.len];
            _ = SetPixel(hdc, x, y, vertex_color);
            _ = SetPixel(hdc, x - 1, y, vertex_color);
            _ = SetPixel(hdc, x + 1, y, vertex_color);
            _ = SetPixel(hdc, x, y - 1, vertex_color);
            _ = SetPixel(hdc, x, y + 1, vertex_color);
        }

        // Cleanup
        _ = SelectObject(hdc, old_pen);
        _ = DeleteObject(pen);
    }

    pub fn renderWireframe(self: *Self, hdc: HDC, color: u32) void {
        // Create transformation matrix
        const rot_x = Mat4.rotateX(self.rotation_x);
        const rot_y = Mat4.rotateY(self.rotation_y);
        const transform = Mat4.multiply(rot_y, rot_x);

        // Transform vertices
        var transformed_vertices: [8]Vec3 = undefined;
        for (cube_vertices, 0..) |vertex, i| {
            transformed_vertices[i] = Mat4.transformPoint(transform, vertex);
        }

        // Project to 2D
        var projected_vertices: [8]Vec2 = undefined;
        for (transformed_vertices, 0..) |vertex, i| {
            projected_vertices[i] = self.projectPoint(vertex);
        }

        // Create pen for drawing
        const pen = CreatePen(0, 1, color);
        const old_pen = SelectObject(hdc, pen);

        // Draw edges
        for (cube_edges) |edge| {
            const start = projected_vertices[edge[0]];
            const end = projected_vertices[edge[1]];

            _ = MoveToEx(hdc, @as(i32, @intFromFloat(start.x)), @as(i32, @intFromFloat(start.y)), null);
            _ = LineTo(hdc, @as(i32, @intFromFloat(end.x)), @as(i32, @intFromFloat(end.y)));
        }

        // Cleanup
        _ = SelectObject(hdc, old_pen);
        _ = DeleteObject(pen);
    }
};

// Helper functions
pub fn createCube(center_x: i32, center_y: i32) SoftwareCube {
    return SoftwareCube.init(center_x, center_y);
}

pub fn getColorByName(name: []const u8) u32 {
    if (std.mem.eql(u8, name, "red")) return 0x00FF0000;
    if (std.mem.eql(u8, name, "green")) return 0x0000FF00;
    if (std.mem.eql(u8, name, "blue")) return 0x000000FF;
    if (std.mem.eql(u8, name, "yellow")) return 0x00FFFF00;
    if (std.mem.eql(u8, name, "magenta")) return 0x00FF00FF;
    if (std.mem.eql(u8, name, "cyan")) return 0x0000FFFF;
    return 0x00FFFFFF; // White as default
}
