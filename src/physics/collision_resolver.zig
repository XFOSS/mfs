const std = @import("std");
const math = @import("math");
const Vec4 = math.Vec4;
const Vector = math.Vector;
const PhysicsConstants = @import("physics_engine.zig").PhysicsConstants;
const PhysicalObject = @import("physics_engine.zig").PhysicalObject;

/// Collision data between two objects
pub const CollisionData = struct {
    object_a: *PhysicalObject,
    object_b: *PhysicalObject,
    normal: Vec4,
    penetration: f32,
    point: Vec4,
    restitution: f32,
};

/// Collision detection and resolution system
pub const CollisionResolver = struct {
    /// Check for collision between two objects
    pub fn detectCollision(obj_a: *PhysicalObject, obj_b: *PhysicalObject) ?CollisionData {
        // Skip if both objects are pinned or sleeping
        if ((obj_a.pinned and obj_b.pinned) or
            (obj_a.sleeping and obj_b.sleeping)) return null;

        // Calculate collision data
        const pos_a = obj_a.position;
        const pos_b = obj_b.position;
        const radius_sum = obj_a.collision_radius + obj_b.collision_radius;

        // Check distance between objects
        const delta = pos_b - pos_a;
        const dist_sq = Vector.dot3(delta, delta);

        // No collision if distance is greater than sum of radii
        if (dist_sq > radius_sum * radius_sum) return null;

        // Calculate collision normal and penetration
        const dist = @sqrt(dist_sq);
        const normal = if (dist > PhysicsConstants.SAFE_DIVISOR)
            delta * Vector.splat(1.0 / dist)
        else
            Vector.new(1.0, 0.0, 0.0, 0.0);

        return CollisionData{
            .object_a = obj_a,
            .object_b = obj_b,
            .normal = normal,
            .penetration = radius_sum - dist,
            .point = pos_a + normal * Vector.splat(obj_a.collision_radius),
            .restitution = @min(obj_a.restitution, obj_b.restitution),
        };
    }

    /// Resolve collision between two objects
    pub fn resolveCollision(collision: CollisionData) void {
        const obj_a = collision.object_a;
        const obj_b = collision.object_b;

        // Calculate relative velocity
        const rel_vel = obj_b.velocity - obj_a.velocity;
        const vel_along_normal = Vector.dot3(rel_vel, collision.normal);

        // Objects are moving apart, skip resolution
        if (vel_along_normal > 0) return;

        // Calculate impulse scalar
        const impulse_scalar = -(1.0 + collision.restitution) * vel_along_normal /
            (obj_a.inverse_mass + obj_b.inverse_mass);

        // Apply impulse
        const impulse = collision.normal * Vector.splat(impulse_scalar);
        if (!obj_a.pinned) {
            obj_a.velocity -= impulse * Vector.splat(obj_a.inverse_mass);
        }
        if (!obj_b.pinned) {
            obj_b.velocity += impulse * Vector.splat(obj_b.inverse_mass);
        }

        // Apply friction
        const tangent = rel_vel - collision.normal * Vector.splat(vel_along_normal);
        const tangent_length = Vector.length3(tangent);

        if (tangent_length > PhysicsConstants.SAFE_DIVISOR) {
            const friction = @min(obj_a.friction, obj_b.friction);
            const normalized_tangent = tangent * Vector.splat(1.0 / tangent_length);
            const friction_impulse = normalized_tangent * Vector.splat(-friction * impulse_scalar);

            if (!obj_a.pinned) {
                obj_a.velocity -= friction_impulse * Vector.splat(obj_a.inverse_mass);
            }
            if (!obj_b.pinned) {
                obj_b.velocity += friction_impulse * Vector.splat(obj_b.inverse_mass);
            }
        }

        // Positional correction to prevent sinking
        const percent = 0.2; // penetration percentage to correct
        const slop = 0.01; // penetration allowance
        const correction = @max(collision.penetration - slop, 0.0) * percent;
        const correction_scale = correction / (obj_a.inverse_mass + obj_b.inverse_mass);
        const correction_vector = collision.normal * Vector.splat(correction_scale);

        if (!obj_a.pinned) {
            obj_a.position -= correction_vector * Vector.splat(obj_a.inverse_mass);
        }
        if (!obj_b.pinned) {
            obj_b.position += correction_vector * Vector.splat(obj_b.inverse_mass);
        }

        // Wake up the objects
        obj_a.wake();
        obj_b.wake();
    }
};
