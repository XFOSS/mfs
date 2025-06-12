const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Entity = @import("../core/entity.zig").Entity;
const Scene = @import("../core/scene.zig").Scene;
const TransformComponent = @import("../components/transform.zig").TransformComponent;
const PhysicsComponent = @import("../components/physics.zig").PhysicsComponent;
const Vec3 = @import("../../math/vec3.zig").Vec3f;
const Mat4 = @import("../../math/mat4.zig").Mat4f;

pub const CollisionPair = struct {
    entity_a: Entity,
    entity_b: Entity,
    point: Vec3,
    normal: Vec3,
    penetration: f32,
};

pub const PhysicsSystem = struct {
    allocator: Allocator,
    scene: *Scene,
    gravity: Vec3,
    max_steps: u32,
    fixed_time_step: f32,
    collision_pairs: ArrayList(CollisionPair),
    broad_phase_pairs: ArrayList(struct { Entity, Entity }),

    pub fn init(allocator: Allocator, scene: *Scene) !PhysicsSystem {
        return PhysicsSystem{
            .allocator = allocator,
            .scene = scene,
            .gravity = Vec3.init(0, -9.81, 0),
            .max_steps = 3,
            .fixed_time_step = 1.0 / 60.0,
            .collision_pairs = ArrayList(CollisionPair).init(allocator),
            .broad_phase_pairs = ArrayList(struct { Entity, Entity }).init(allocator),
        };
    }

    pub fn deinit(self: *PhysicsSystem) void {
        self.collision_pairs.deinit();
        self.broad_phase_pairs.deinit();
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

        // Find all physics bodies
        var dynamic_bodies = ArrayList(struct { Entity, *PhysicsComponent, *TransformComponent }).init(self.allocator);
        defer dynamic_bodies.deinit();

        var static_bodies = ArrayList(struct { Entity, *PhysicsComponent, *TransformComponent }).init(self.allocator);
        defer static_bodies.deinit();

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
                const entity = body[0];
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
        const aabb_a = physics_a.getAABB(transform_a);
        const aabb_b = physics_b.getAABB(transform_b);

        return (aabb_a.min.x <= aabb_b.max.x and aabb_a.max.x >= aabb_b.min.x) and
            (aabb_a.min.y <= aabb_b.max.y and aabb_a.max.y >= aabb_b.min.y) and
            (aabb_a.min.z <= aabb_b.max.z and aabb_a.max.z >= aabb_b.min.z);
    }

    fn checkCollision(self: *PhysicsSystem, physics_a: *PhysicsComponent, transform_a: *TransformComponent, physics_b: *PhysicsComponent, transform_b: *TransformComponent) !?CollisionPair {
        // TODO: Implement narrow phase collision detection for different shape types
        // For now, just return null to indicate no collision
        return null;
    }

    fn resolveCollision(self: *PhysicsSystem, physics_a: *PhysicsComponent, transform_a: *TransformComponent, physics_b: *PhysicsComponent, transform_b: *TransformComponent, collision: CollisionPair) void {
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
