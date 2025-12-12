const std = @import("std");
const math = @import("../math/mod.zig");
const Vec4 = math.Vec4;
const Vector = math.Vector;
const shapes = @import("shapes.zig");
const Shape = shapes.Shape;
const SphereShape = shapes.SphereShape;
const collision_resolver = @import("collision_resolver.zig");
const CollisionData = collision_resolver.CollisionData;
const physics_engine = @import("physics_engine.zig");
const PhysicalObject = physics_engine.PhysicalObject;

/// CCD sweep result
pub const SweepResult = struct {
    hit: bool,
    time: f32, // Time of impact, normalized [0-1]
    point: Vec4, // Hit point
    normal: Vec4, // Hit normal
    object_idx: usize, // Hit object index
};

/// Continuous collision detection system
pub const ContinuousCollision = struct {
    pub fn init(allocator: std.mem.Allocator) ContinuousCollision {
        _ = allocator; // Not needed for this implementation
        return ContinuousCollision{};
    }

    pub fn deinit(self: *ContinuousCollision) void {
        _ = self; // No cleanup needed for this implementation
    }

    /// Perform a linear cast from start to end position
    pub fn linearCast(
        start_pos: Vec4,
        end_pos: Vec4,
        radius: f32,
        objects: []PhysicalObject,
        ignore_idx: ?usize,
    ) SweepResult {
        var result = SweepResult{
            .hit = false,
            .time = 1.0,
            .point = end_pos,
            .normal = Vec4{ 0, 1, 0, 0 },
            .object_idx = 0,
        };

        // Direction and length of movement
        const delta = end_pos - start_pos;
        const dist_sq = Vector.dot3(delta, delta);

        // If not moving, no collision possible
        if (dist_sq < 0.0001) return result;

        // Test against all objects
        for (objects, 0..) |*obj, idx| {
            // Skip self or inactive objects
            if (ignore_idx != null and idx == ignore_idx.?) continue;
            if (!obj.active) continue;

            // Currently only sphere vs sphere sweep is implemented
            const sphere_radius = obj.radius + radius;

            // Compute closest approach between ray and sphere center
            const sphere_to_ray_start = start_pos - obj.position;
            const a = Vector.dot3(delta, delta);
            const b = 2.0 * Vector.dot3(sphere_to_ray_start, delta);
            const c = Vector.dot3(sphere_to_ray_start, sphere_to_ray_start) -
                sphere_radius * sphere_radius;

            // Solve quadratic equation
            var discriminant = b * b - 4.0 * a * c;
            if (discriminant < 0) continue; // No collision

            discriminant = @sqrt(discriminant);

            // Find intersection times
            const t1 = (-b - discriminant) / (2.0 * a);
            const t2 = (-b + discriminant) / (2.0 * a);

            // Check if intersection is within the movement range
            if (t2 < 0 or t1 > 1.0) continue;

            const t = if (t1 >= 0.0) t1 else t2;
            if (t >= 0.0 and t < result.time) {
                result.hit = true;
                result.time = t;
                result.object_idx = idx;

                // Calculate hit point and normal
                result.point = start_pos + delta * Vector.splat(t);
                result.normal = Vector.normalize3(result.point - obj.position);
            }
        }

        return result;
    }

    /// Update object position using CCD to prevent tunneling
    pub fn updateWithCCD(
        obj: *PhysicalObject,
        dt: f32,
        objects: []PhysicalObject,
        object_idx: usize,
    ) void {
        // Only apply CCD to moving objects
        if (!obj.active or obj.pinned) return;

        // Calculate new position using velocity
        const next_position = obj.position + obj.velocity * Vector.splat(dt);

        // Check for collisions along the path
        const sweep = linearCast(
            obj.position,
            next_position,
            obj.radius,
            objects,
            object_idx,
        );

        if (sweep.hit) {
            // Move to point of impact
            obj.position = sweep.point - sweep.normal * Vector.splat(obj.radius * 1.01);

            // Reflect velocity off the surface (use default restitution since PhysicalObject doesn't have restitution property)
            const default_restitution = 0.5;
            const vel_dot_normal = Vector.dot3(obj.velocity, sweep.normal);
            if (vel_dot_normal < 0.0) {
                const reflection_scale = -(1.0 + default_restitution) * vel_dot_normal;
                obj.velocity += sweep.normal * Vector.splat(reflection_scale);
            }

            // Create a collision event with hit object
            const other_obj = &objects[sweep.object_idx];
            const collision = CollisionData{
                .object_a = obj,
                .object_b = other_obj,
                .normal = sweep.normal,
                .penetration = 0.01, // Small penetration to ensure contact resolution
                .point = sweep.point,
                .restitution = default_restitution,
            };

            // Resolve the collision
            collision_resolver.CollisionResolver.resolveCollision(collision);
        } else {
            // No collision, apply full movement
            obj.position = next_position;
        }
    }
};
