const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Entity = @import("../core/entity.zig").Entity;
const Scene = @import("../core/scene.zig").Scene;
const System = @import("../core/scene.zig").System;
const TransformComponent = @import("../components/transform.zig").Transform;
const PhysicsComponent = @import("../components/physics.zig").PhysicsComponent;
const math = @import("../../libs/math/mod.zig");
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;

pub const CollisionPair = struct {
    entity_a: Entity,
    entity_b: Entity,
    normal: Vec3,
    penetration: f32,
    contact_point: Vec3,
};

pub const PhysicsSystem = struct {
    allocator: Allocator,
    scene: *Scene,
    gravity: Vec3,
    max_steps: u32,
    fixed_time_step: f32,
    collision_pairs: ArrayList(CollisionPair),
    broad_phase_pairs: ArrayList(struct { Entity, Entity }),
    dynamic_bodies: ArrayList(struct { Entity, *PhysicsComponent, *TransformComponent }),
    static_bodies: ArrayList(struct { Entity, *PhysicsComponent, *TransformComponent }),

    pub fn init(allocator: Allocator, scene: *Scene) !PhysicsSystem {
        return PhysicsSystem{
            .allocator = allocator,
            .scene = scene,
            .gravity = Vec3.init(0, -9.81, 0),
            .max_steps = 3,
            .fixed_time_step = 1.0 / 60.0,
            .collision_pairs = ArrayList(CollisionPair).init(allocator),
            .broad_phase_pairs = ArrayList(struct { Entity, Entity }).init(allocator),
            .dynamic_bodies = ArrayList(struct { Entity, *PhysicsComponent, *TransformComponent }).init(allocator),
            .static_bodies = ArrayList(struct { Entity, *PhysicsComponent, *TransformComponent }).init(allocator),
        };
    }

    pub fn deinit(self: *PhysicsSystem) void {
        self.collision_pairs.deinit();
        self.broad_phase_pairs.deinit();
        self.dynamic_bodies.deinit();
        self.static_bodies.deinit();
    }

    pub fn setGravity(self: *PhysicsSystem, gravity: Vec3) void {
        self.gravity = gravity;
    }

    pub fn setMaxSteps(self: *PhysicsSystem, max_steps: u32) void {
        self.max_steps = max_steps;
    }

    pub fn setFixedTimeStep(self: *PhysicsSystem, time_step: f32) void {
        self.fixed_time_step = time_step;
    }

    pub fn update(self: *PhysicsSystem, delta_time: f32) !void {
        // Clear collision pairs
        self.collision_pairs.clearRetainingCapacity();
        self.broad_phase_pairs.clearRetainingCapacity();

        // Reuse pre-allocated body lists instead of allocating each frame
        self.dynamic_bodies.clearRetainingCapacity();
        self.static_bodies.clearRetainingCapacity();

        var dynamic_bodies = &self.dynamic_bodies;
        var static_bodies = &self.static_bodies;

        // Find all physics bodies
        var it = self.scene.iterator(.{ .physics = true, .transform = true });
        while (it.next()) |entity| {
            const physics = self.scene.getComponent(entity, PhysicsComponent) orelse continue;
            const transform = self.scene.getComponent(entity, TransformComponent) orelse continue;

            if (physics.body_type == .Dynamic) {
                try dynamic_bodies.append(.{ entity, physics, transform });
            } else if (physics.body_type == .Static) {
                try static_bodies.append(.{ entity, physics, transform });
            }
        }

        // Perform broad phase collision detection
        try self.broadPhase(dynamic_bodies.items, static_bodies.items);

        // Perform narrow phase collision detection and response
        for (self.broad_phase_pairs.items) |pair| {
            const entity_a = pair[0];
            const entity_b = pair[1];

            const physics_a = self.scene.getComponent(entity_a, PhysicsComponent) orelse continue;
            const physics_b = self.scene.getComponent(entity_b, PhysicsComponent) orelse continue;
            const transform_a = self.scene.getComponent(entity_a, TransformComponent) orelse continue;
            const transform_b = self.scene.getComponent(entity_b, TransformComponent) orelse continue;

            if (try self.checkCollision(physics_a, transform_a, physics_b, transform_b)) |collision| {
                try self.collision_pairs.append(collision);
                self.resolveCollision(physics_a, transform_a, physics_b, transform_b, collision);
            }
        }

        // Update physics
        const steps = @min(@as(u32, @intFromFloat(delta_time / self.fixed_time_step)), self.max_steps);
        const step_delta = delta_time / @as(f32, @floatFromInt(steps));

        for (0..steps) |_| {
            // Update dynamic bodies
            for (dynamic_bodies.items) |body| {
                _ = body[0]; // entity currently unused but available for future use
                const physics = body[1];
                const transform = body[2];

                // Skip sleeping bodies
                if (physics.is_sleeping) continue;

                // Update physics
                physics.update(step_delta, self.gravity);

                // Update transform
                transform.position = transform.position.add(physics.velocity.scale(step_delta));
                transform.rotation = transform.rotation.add(physics.angular_velocity.scale(step_delta));
                transform.dirty = true;
            }
        }
    }

    fn broadPhase(self: *PhysicsSystem, dynamic_bodies: []const struct { Entity, *PhysicsComponent, *TransformComponent }, static_bodies: []const struct { Entity, *PhysicsComponent, *TransformComponent }) !void {
        // Simple AABB-based broad phase
        for (dynamic_bodies) |body_a| {
            const entity_a = body_a[0];
            const physics_a = body_a[1];
            const transform_a = body_a[2];

            // Check against other dynamic bodies
            for (dynamic_bodies) |body_b| {
                const entity_b = body_b[0];
                if (entity_a.id >= entity_b.id) continue;

                const physics_b = body_b[1];
                const transform_b = body_b[2];

                if (self.checkAABB(transform_a, physics_a, transform_b, physics_b)) {
                    try self.broad_phase_pairs.append(.{ entity_a, entity_b });
                }
            }

            // Check against static bodies
            for (static_bodies) |body_b| {
                const entity_b = body_b[0];
                const physics_b = body_b[1];
                const transform_b = body_b[2];

                if (self.checkAABB(transform_a, physics_a, transform_b, physics_b)) {
                    try self.broad_phase_pairs.append(.{ entity_a, entity_b });
                }
            }
        }
    }

    fn checkAABB(self: *PhysicsSystem, transform_a: *TransformComponent, physics_a: *PhysicsComponent, transform_b: *TransformComponent, physics_b: *PhysicsComponent) bool {
        _ = self; // TODO: Will be used when AABB system is expanded
        const aabb_a = physics_a.getAABB(transform_a);
        const aabb_b = physics_b.getAABB(transform_b);

        return (aabb_a.min.x <= aabb_b.max.x and aabb_a.max.x >= aabb_b.min.x) and
            (aabb_a.min.y <= aabb_b.max.y and aabb_a.max.y >= aabb_b.min.y) and
            (aabb_a.min.z <= aabb_b.max.z and aabb_a.max.z >= aabb_b.min.z);
    }

    fn checkCollision(self: *PhysicsSystem, physics_a: *PhysicsComponent, transform_a: *TransformComponent, physics_b: *PhysicsComponent, transform_b: *TransformComponent) !?CollisionPair {
        _ = self; // May be used for future collision system expansion

        // Get collision shapes
        const shape_a = physics_a.collision_shape;
        const shape_b = physics_b.collision_shape;

        // Handle different collision shape combinations
        if (shape_a == .Sphere and shape_b == .Sphere) {
            return checkSphereSphere(physics_a, transform_a, physics_b, transform_b);
        } else if ((shape_a == .Sphere and shape_b == .Box) or (shape_a == .Box and shape_b == .Sphere)) {
            if (shape_a == .Sphere) {
                return checkSphereBox(physics_a, transform_a, physics_b, transform_b);
            } else {
                const result = checkSphereBox(physics_b, transform_b, physics_a, transform_a);
                if (result) |collision| {
                    // Flip the normal since we swapped the order
                    return CollisionPair{
                        .entity_a = collision.entity_b,
                        .entity_b = collision.entity_a,
                        .normal = collision.normal.scale(-1.0),
                        .penetration = collision.penetration,
                        .contact_point = collision.contact_point,
                    };
                }
                return result;
            }
        } else if (shape_a == .Box and shape_b == .Box) {
            return checkBoxBox(physics_a, transform_a, physics_b, transform_b);
        }

        // Unsupported collision shape combination
        return null;
    }

    fn checkSphereSphere(physics_a: *PhysicsComponent, transform_a: *TransformComponent, physics_b: *PhysicsComponent, transform_b: *TransformComponent) ?CollisionPair {
        const center_a = transform_a.position;
        const center_b = transform_b.position;
        const radius_a = physics_a.collision_shape.Sphere.radius * transform_a.scale.x; // Assume uniform scaling
        const radius_b = physics_b.collision_shape.Sphere.radius * transform_b.scale.x;

        const distance_vec = center_b.sub(center_a);
        const distance = distance_vec.length();
        const combined_radius = radius_a + radius_b;

        if (distance < combined_radius and distance > 0.0) {
            const normal = distance_vec.scale(1.0 / distance);
            const penetration = combined_radius - distance;
            const contact_point = center_a.add(normal.scale(radius_a));

            return CollisionPair{
                .entity_a = undefined, // Will be set by caller
                .entity_b = undefined, // Will be set by caller
                .normal = normal,
                .penetration = penetration,
                .contact_point = contact_point,
            };
        }

        return null;
    }

    fn checkSphereBox(physics_sphere: *PhysicsComponent, transform_sphere: *TransformComponent, physics_box: *PhysicsComponent, transform_box: *TransformComponent) ?CollisionPair {
        const sphere_center = transform_sphere.position;
        const sphere_radius = physics_sphere.collision_shape.Sphere.radius * transform_sphere.scale.x;

        const box_center = transform_box.position;
        const box_half_extents = physics_box.collision_shape.Box.half_extents.mul(transform_box.scale);

        // Find the closest point on the box to the sphere center
        const closest_point = Vec3.init(std.math.clamp(sphere_center.x, box_center.x - box_half_extents.x, box_center.x + box_half_extents.x), std.math.clamp(sphere_center.y, box_center.y - box_half_extents.y, box_center.y + box_half_extents.y), std.math.clamp(sphere_center.z, box_center.z - box_half_extents.z, box_center.z + box_half_extents.z));

        const distance_vec = sphere_center.sub(closest_point);
        const distance = distance_vec.length();

        if (distance < sphere_radius and distance > 0.0) {
            const normal = distance_vec.scale(1.0 / distance);
            const penetration = sphere_radius - distance;

            return CollisionPair{
                .entity_a = undefined, // Will be set by caller
                .entity_b = undefined, // Will be set by caller
                .normal = normal,
                .penetration = penetration,
                .contact_point = closest_point,
            };
        }

        return null;
    }

    fn checkBoxBox(physics_a: *PhysicsComponent, transform_a: *TransformComponent, physics_b: *PhysicsComponent, transform_b: *TransformComponent) ?CollisionPair {
        // Simplified AABB vs AABB collision (assumes axis-aligned boxes)
        const center_a = transform_a.position;
        const center_b = transform_b.position;
        const half_extents_a = physics_a.collision_shape.Box.half_extents.mul(transform_a.scale);
        const half_extents_b = physics_b.collision_shape.Box.half_extents.mul(transform_b.scale);

        const distance = center_b.sub(center_a);
        const combined_extents = half_extents_a.add(half_extents_b);

        // Check for overlap on all axes
        if (@abs(distance.x) < combined_extents.x and
            @abs(distance.y) < combined_extents.y and
            @abs(distance.z) < combined_extents.z)
        {

            // Find the axis with minimum penetration
            const x_penetration = combined_extents.x - @abs(distance.x);
            const y_penetration = combined_extents.y - @abs(distance.y);
            const z_penetration = combined_extents.z - @abs(distance.z);

            var normal: Vec3 = undefined;
            var penetration: f32 = undefined;

            if (x_penetration < y_penetration and x_penetration < z_penetration) {
                normal = Vec3.init(if (distance.x > 0) 1.0 else -1.0, 0.0, 0.0);
                penetration = x_penetration;
            } else if (y_penetration < z_penetration) {
                normal = Vec3.init(0.0, if (distance.y > 0) 1.0 else -1.0, 0.0);
                penetration = y_penetration;
            } else {
                normal = Vec3.init(0.0, 0.0, if (distance.z > 0) 1.0 else -1.0);
                penetration = z_penetration;
            }

            const contact_point = center_a.add(distance.scale(0.5));

            return CollisionPair{
                .entity_a = undefined, // Will be set by caller
                .entity_b = undefined, // Will be set by caller
                .normal = normal,
                .penetration = penetration,
                .contact_point = contact_point,
            };
        }

        return null;
    }

    fn resolveCollision(self: *PhysicsSystem, physics_a: *PhysicsComponent, transform_a: *TransformComponent, physics_b: *PhysicsComponent, transform_b: *TransformComponent, collision: CollisionPair) void {
        _ = self; // TODO: Will be used when collision system is expanded
        // Skip if either body is a trigger
        if (physics_a.is_trigger or physics_b.is_trigger) return;

        // Calculate relative velocity
        const relative_velocity = physics_a.velocity.sub(physics_b.velocity);

        // Calculate relative velocity along normal
        const velocity_along_normal = relative_velocity.dot(collision.normal);

        // Do not resolve if objects are moving apart
        if (velocity_along_normal > 0) return;

        // Calculate restitution
        const restitution = @min(physics_a.restitution, physics_b.restitution);

        // Calculate impulse scalar
        var impulse_scalar = -(1.0 + restitution) * velocity_along_normal;
        impulse_scalar /= physics_a.mass + physics_b.mass;

        // Apply impulse
        const impulse = collision.normal.scale(impulse_scalar);
        physics_a.velocity = physics_a.velocity.add(impulse.scale(1.0 / physics_a.mass));
        physics_b.velocity = physics_b.velocity.sub(impulse.scale(1.0 / physics_b.mass));

        // Friction
        const relative_velocity_tangent = relative_velocity.sub(collision.normal.scale(relative_velocity.dot(collision.normal)));
        const tangent = relative_velocity_tangent.normalize();
        _ = @min(physics_a.friction, physics_b.friction); // Store friction for future use

        const jt = -relative_velocity.dot(tangent);
        const lambda = -jt / (physics_a.mass + physics_b.mass);

        const friction_impulse = tangent.scale(lambda);
        physics_a.velocity = physics_a.velocity.add(friction_impulse.scale(1.0 / physics_a.mass));
        physics_b.velocity = physics_b.velocity.sub(friction_impulse.scale(1.0 / physics_b.mass));

        // Positional correction
        const percent: f32 = 0.2;
        const correction = collision.normal.scale(percent * collision.penetration / (physics_a.mass + physics_b.mass));
        transform_a.position = transform_a.position.add(correction.scale(1.0 / physics_a.mass));
        transform_b.position = transform_b.position.sub(correction.scale(1.0 / physics_b.mass));
        transform_a.dirty = true;
        transform_b.dirty = true;
    }
};

/// Standalone update function for use with Scene.addSystem
pub fn update(system: *System, scene: *Scene, delta_time: f32) void {
    _ = system;

    // Simple physics update without full system
    var entity_iter = scene.entities.iterator();
    while (entity_iter.next()) |entry| {
        const entity = entry.value_ptr;

        // Find physics and transform components
        var physics_comp: ?*PhysicsComponent = null;
        var transform_comp: ?*TransformComponent = null;

        var comp_iter = entity.components.iterator();
        while (comp_iter.next()) |comp_entry| {
            switch (comp_entry.value_ptr.*) {
                .physics => |*physics| physics_comp = physics,
                .transform => |*transform| transform_comp = transform,
                else => {},
            }
        }

        if (physics_comp) |physics| {
            if (transform_comp) |transform| {
                if (physics.body_type == .Dynamic) {
                    // Apply gravity
                    const gravity = Vec3.init(0, -9.81, 0);
                    const scaled_gravity = Vec3{
                        .x = gravity.x * delta_time,
                        .y = gravity.y * delta_time,
                        .z = gravity.z * delta_time,
                    };
                    physics.velocity.x += scaled_gravity.x;
                    physics.velocity.y += scaled_gravity.y;
                    physics.velocity.z += scaled_gravity.z;

                    // Update position
                    const scaled_velocity = Vec3{
                        .x = physics.velocity.x * delta_time,
                        .y = physics.velocity.y * delta_time,
                        .z = physics.velocity.z * delta_time,
                    };
                    transform.position.x += scaled_velocity.x;
                    transform.position.y += scaled_velocity.y;
                    transform.position.z += scaled_velocity.z;
                    transform.dirty = true;
                }
            }
        }
    }
}
