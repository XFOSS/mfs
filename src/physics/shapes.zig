const std = @import("std");
const math = @import("../math/vector.zig");
const Vec4 = math.Vec4;
const Vector = math.Vector;
const Quaternion = math.Quaternion;
const spatial_partition = @import("spatial_partition.zig");
const AABB = spatial_partition.AABB;

/// Collision shape types
pub const ShapeType = enum {
    Sphere,
    Box,
    Capsule,
    Cylinder,
    ConvexHull,
};

/// Base shape interface
pub const Shape = union(ShapeType) {
    Sphere: SphereShape,
    Box: BoxShape,
    Capsule: CapsuleShape,
    Cylinder: CylinderShape,
    ConvexHull: *ConvexHullShape,

    /// Get bounding box for shape
    pub fn getBoundingBox(self: Shape, position: Vec4, orientation: Quaternion) AABB {
        return switch (self) {
            .Sphere => |sphere| sphere.getBoundingBox(position),
            .Box => |box| box.getBoundingBox(position, orientation),
            .Capsule => |capsule| capsule.getBoundingBox(position, orientation),
            .Cylinder => |cylinder| cylinder.getBoundingBox(position, orientation),
            .ConvexHull => |hull| hull.getBoundingBox(position, orientation),
        };
    }

    /// Get volume of the shape
    pub fn getVolume(self: Shape) f32 {
        return switch (self) {
            .Sphere => |sphere| sphere.getVolume(),
            .Box => |box| box.getVolume(),
            .Capsule => |capsule| capsule.getVolume(),
            .Cylinder => |cylinder| cylinder.getVolume(),
            .ConvexHull => |hull| hull.getVolume(),
        };
    }

    /// Create a deep copy of this shape
    pub fn clone(self: Shape, allocator: std.mem.Allocator) !Shape {
        return switch (self) {
            .Sphere => |sphere| Shape{ .Sphere = sphere },
            .Box => |box| Shape{ .Box = box },
            .Capsule => |capsule| Shape{ .Capsule = capsule },
            .Cylinder => |cylinder| Shape{ .Cylinder = cylinder },
            .ConvexHull => |hull| Shape{ .ConvexHull = try hull.clone(allocator) },
        };
    }
};

/// Sphere shape
pub const SphereShape = struct {
    radius: f32,

    pub fn init(radius: f32) SphereShape {
        return SphereShape{
            .radius = radius,
        };
    }

    pub fn getBoundingBox(self: SphereShape, position: Vec4) AABB {
        return AABB.fromSphere(position, self.radius);
    }

    pub fn getVolume(self: SphereShape) f32 {
        return (4.0 / 3.0) * std.math.pi * self.radius * self.radius * self.radius;
    }
};

/// Box shape
pub const BoxShape = struct {
    half_extents: Vec4,

    pub fn init(width: f32, height: f32, depth: f32) BoxShape {
        return BoxShape{
            .half_extents = Vec4{ width * 0.5, height * 0.5, depth * 0.5, 0.0 },
        };
    }

    pub fn getBoundingBox(self: BoxShape, position: Vec4, orientation: Quaternion) AABB {
        // Calculate transformed corners
        const corners = [8]Vec4{
            // Top face
            Vector.new(self.half_extents[0], self.half_extents[1], self.half_extents[2], 0),
            Vector.new(-self.half_extents[0], self.half_extents[1], self.half_extents[2], 0),
            Vector.new(-self.half_extents[0], self.half_extents[1], -self.half_extents[2], 0),
            Vector.new(self.half_extents[0], self.half_extents[1], -self.half_extents[2], 0),
            // Bottom face
            Vector.new(self.half_extents[0], -self.half_extents[1], self.half_extents[2], 0),
            Vector.new(-self.half_extents[0], -self.half_extents[1], self.half_extents[2], 0),
            Vector.new(-self.half_extents[0], -self.half_extents[1], -self.half_extents[2], 0),
            Vector.new(self.half_extents[0], -self.half_extents[1], -self.half_extents[2], 0),
        };

        // Initialize min/max to first corner
        var rotated_corner = orientation.rotateVector(corners[0]);
        var min = position + rotated_corner;
        var max = position + rotated_corner;

        // Find min/max values across all corners
        for (corners[1..]) |corner| {
            rotated_corner = orientation.rotateVector(corner);
            const world_corner = position + rotated_corner;

            min = Vec4{
                @min(min[0], world_corner[0]),
                @min(min[1], world_corner[1]),
                @min(min[2], world_corner[2]),
                0,
            };

            max = Vec4{
                @max(max[0], world_corner[0]),
                @max(max[1], world_corner[1]),
                @max(max[2], world_corner[2]),
                0,
            };
        }

        return AABB{
            .min = min,
            .max = max,
        };
    }

    pub fn getVolume(self: BoxShape) f32 {
        return 8.0 * self.half_extents[0] * self.half_extents[1] * self.half_extents[2];
    }
};

/// Capsule shape (cylinder with hemisphere caps)
pub const CapsuleShape = struct {
    radius: f32,
    half_height: f32,
    // Capsule axis is along the Y axis

    pub fn init(radius: f32, height: f32) CapsuleShape {
        return CapsuleShape{
            .radius = radius,
            .half_height = height * 0.5,
        };
    }

    pub fn getBoundingBox(self: CapsuleShape, position: Vec4, orientation: Quaternion) AABB {
        // Calculate capsule end points (centers of the hemispheres)
        const top = Vector.new(0, self.half_height, 0, 0);
        const bottom = Vector.new(0, -self.half_height, 0, 0);

        // Rotate the points
        const rotated_top = orientation.rotateVector(top);
        const rotated_bottom = orientation.rotateVector(bottom);

        // Create spheres at each end
        const top_sphere = AABB.fromSphere(position + rotated_top, self.radius);
        const bottom_sphere = AABB.fromSphere(position + rotated_bottom, self.radius);

        // Merge AABBs
        return top_sphere.merge(bottom_sphere);
    }

    pub fn getVolume(self: CapsuleShape) f32 {
        // Volume = cylinder volume + volume of two hemispheres
        const cylinder_volume = std.math.pi * self.radius * self.radius * (self.half_height * 2.0);
        const sphere_volume = (4.0 / 3.0) * std.math.pi * self.radius * self.radius * self.radius;
        return cylinder_volume + sphere_volume;
    }
};

/// Cylinder shape
pub const CylinderShape = struct {
    radius: f32,
    half_height: f32,
    // Cylinder axis is along the Y axis

    pub fn init(radius: f32, height: f32) CylinderShape {
        return CylinderShape{
            .radius = radius,
            .half_height = height * 0.5,
        };
    }

    pub fn getBoundingBox(self: CylinderShape, position: Vec4, orientation: Quaternion) AABB {
        // Create box with cylinder dimensions
        const box = BoxShape.init(self.radius * 2.0, self.half_height * 2.0, self.radius * 2.0);
        return box.getBoundingBox(position, orientation);
    }

    pub fn getVolume(self: CylinderShape) f32 {
        return std.math.pi * self.radius * self.radius * (self.half_height * 2.0);
    }
};

/// Convex hull shape
pub const ConvexHullShape = struct {
    vertices: []Vec4,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, vertices: []const Vec4) !*ConvexHullShape {
        var hull = try allocator.create(ConvexHullShape);
        hull.allocator = allocator;
        hull.vertices = try allocator.alloc(Vec4, vertices.len);

        // Copy vertices
        @memcpy(hull.vertices, vertices);

        return hull;
    }

    pub fn deinit(self: *ConvexHullShape) void {
        self.allocator.free(self.vertices);
        self.allocator.destroy(self);
    }

    pub fn clone(self: *ConvexHullShape, allocator: std.mem.Allocator) !*ConvexHullShape {
        return ConvexHullShape.init(allocator, self.vertices);
    }

    pub fn getBoundingBox(self: *ConvexHullShape, position: Vec4, orientation: Quaternion) AABB {
        if (self.vertices.len == 0) {
            return AABB{
                .min = position,
                .max = position,
            };
        }

        // Rotate and translate first vertex
        var rotated = orientation.rotateVector(self.vertices[0]);
        var min = position + rotated;
        var max = position + rotated;

        // Process all vertices
        for (self.vertices[1..]) |vertex| {
            rotated = orientation.rotateVector(vertex);
            const world_vertex = position + rotated;

            min = Vec4{
                @min(min[0], world_vertex[0]),
                @min(min[1], world_vertex[1]),
                @min(min[2], world_vertex[2]),
                0,
            };

            max = Vec4{
                @max(max[0], world_vertex[0]),
                @max(max[1], world_vertex[1]),
                @max(max[2], world_vertex[2]),
                0,
            };
        }

        return AABB{
            .min = min,
            .max = max,
        };
    }

    pub fn getVolume(self: *ConvexHullShape) f32 {
        // TODO: Implement proper convex hull volume calculation
        // For now, approximate with bounding box
        const aabb = self.getBoundingBox(Vec4{ 0, 0, 0, 0 }, Quaternion.identity());
        const dimensions = aabb.max - aabb.min;
        return dimensions[0] * dimensions[1] * dimensions[2];
    }
};
