const std = @import("std");
// const math = @import("math");
const Vec3 = struct { x: f32, y: f32, z: f32 };
const Vec4 = struct { x: f32, y: f32, z: f32, w: f32 };
const Mat4 = struct { data: [16]f32 };

pub const BoundingBox = struct {
    min: Vec3,
    max: Vec3,

    pub fn init(min: Vec3, max: Vec3) BoundingBox {
        return BoundingBox{
            .min = min,
            .max = max,
        };
    }

    pub fn center(self: BoundingBox) Vec3 {
        return self.min.add(self.max).scale(0.5);
    }

    pub fn size(self: BoundingBox) Vec3 {
        return self.max.sub(self.min);
    }

    pub fn intersects(self: BoundingBox, other: BoundingBox) bool {
        return (self.min.x <= other.max.x and self.max.x >= other.min.x) and
            (self.min.y <= other.max.y and self.max.y >= other.min.y) and
            (self.min.z <= other.max.z and self.max.z >= other.min.z);
    }

    pub fn contains(self: BoundingBox, point: Vec3) bool {
        return (point.x >= self.min.x and point.x <= self.max.x) and
            (point.y >= self.min.y and point.y <= self.max.y) and
            (point.z >= self.min.z and point.z <= self.max.z);
    }
};

pub const Material = struct {
    diffuse_color: Vec4,
    specular_color: Vec4,
    shininess: f32,
    texture_diffuse: ?[]const u8,
    texture_normal: ?[]const u8,
    texture_specular: ?[]const u8,

    pub fn init() Material {
        return Material{
            .diffuse_color = Vec4.init(1, 1, 1, 1),
            .specular_color = Vec4.init(1, 1, 1, 1),
            .shininess = 32.0,
            .texture_diffuse = null,
            .texture_normal = null,
            .texture_specular = null,
        };
    }
};

pub const Mesh = struct {
    vertices: []const f32,
    indices: []const u32,
    vertex_count: u32,
    index_count: u32,
    bounds: BoundingBox,

    pub fn init(vertices: []const f32, indices: []const u32) !Mesh {
        var min_x: f32 = std.math.f32_max;
        var min_y: f32 = std.math.f32_max;
        var min_z: f32 = std.math.f32_max;
        var max_x: f32 = -std.math.f32_max;
        var max_y: f32 = -std.math.f32_max;
        var max_z: f32 = -std.math.f32_max;

        // Calculate bounds from vertices (assuming 3 floats per vertex)
        var i: usize = 0;
        while (i < vertices.len) : (i += 3) {
            min_x = @min(min_x, vertices[i]);
            min_y = @min(min_y, vertices[i + 1]);
            min_z = @min(min_z, vertices[i + 2]);
            max_x = @max(max_x, vertices[i]);
            max_y = @max(max_y, vertices[i + 1]);
            max_z = @max(max_z, vertices[i + 2]);
        }

        return Mesh{
            .vertices = vertices,
            .indices = indices,
            .vertex_count = @intCast(vertices.len / 3),
            .index_count = @intCast(indices.len),
            .bounds = BoundingBox.init(Vec3.init(min_x, min_y, min_z), Vec3.init(max_x, max_y, max_z)),
        };
    }
};

pub const RenderComponent = struct {
    mesh: ?Mesh,
    material: Material,
    visible: bool,
    cast_shadows: bool,
    receive_shadows: bool,
    bounds: BoundingBox,
    world_bounds: BoundingBox,
    dirty: bool,

    pub fn init() RenderComponent {
        return RenderComponent{
            .mesh = null,
            .material = Material.init(),
            .visible = true,
            .cast_shadows = true,
            .receive_shadows = true,
            .bounds = BoundingBox.init(Vec3.init(0, 0, 0), Vec3.init(0, 0, 0)),
            .world_bounds = BoundingBox.init(Vec3.init(0, 0, 0), Vec3.init(0, 0, 0)),
            .dirty = true,
        };
    }

    pub fn setMesh(self: *RenderComponent, mesh: Mesh) void {
        self.mesh = mesh;
        self.bounds = mesh.bounds;
        self.dirty = true;
    }

    pub fn updateWorldBounds(self: *RenderComponent, world_matrix: Mat4) void {
        if (!self.dirty) return;

        const center = self.bounds.center();
        const size = self.bounds.size();

        // Transform the 8 corners of the bounding box
        const corners = [_]Vec3{
            center.add(Vec3.init(-size.x, -size.y, -size.z).scale(0.5)),
            center.add(Vec3.init(size.x, -size.y, -size.z).scale(0.5)),
            center.add(Vec3.init(-size.x, size.y, -size.z).scale(0.5)),
            center.add(Vec3.init(size.x, size.y, -size.z).scale(0.5)),
            center.add(Vec3.init(-size.x, -size.y, size.z).scale(0.5)),
            center.add(Vec3.init(size.x, -size.y, size.z).scale(0.5)),
            center.add(Vec3.init(-size.x, size.y, size.z).scale(0.5)),
            center.add(Vec3.init(size.x, size.y, size.z).scale(0.5)),
        };

        var min_x: f32 = std.math.f32_max;
        var min_y: f32 = std.math.f32_max;
        var min_z: f32 = std.math.f32_max;
        var max_x: f32 = -std.math.f32_max;
        var max_y: f32 = -std.math.f32_max;
        var max_z: f32 = -std.math.f32_max;

        for (corners) |corner| {
            const transformed = world_matrix.transformPoint(corner);
            min_x = @min(min_x, transformed.x);
            min_y = @min(min_y, transformed.y);
            min_z = @min(min_z, transformed.z);
            max_x = @max(max_x, transformed.x);
            max_y = @max(max_y, transformed.y);
            max_z = @max(max_z, transformed.z);
        }

        self.world_bounds = BoundingBox.init(Vec3.init(min_x, min_y, min_z), Vec3.init(max_x, max_y, max_z));
        self.dirty = false;
    }
};
