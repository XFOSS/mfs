const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const physics = @import("physics.zig");
const math = physics.math;
const Vector = math.Vector;
const Vec3f = physics.Vec3f;
const PhysicsConstants = physics.PhysicsConstants;
const PhysicalObject = physics.PhysicalObject;
const ObjectType = physics.ObjectType;

/// Collision data structure holding information about a single collision
pub const CollisionInfo = struct {
    object_a_idx: usize,
    object_b_idx: usize,
    contact_point: Vec3f,
    contact_normal: Vec3f,
    penetration_depth: f32,
    restitution: f32,
    friction: f32,
};

/// AABB structure for broad-phase collision detection
pub const AABB = struct {
    min: Vec3f,
    max: Vec3f,

    pub fn fromObject(obj: *const PhysicalObject) AABB {
        const radius = obj.collision_radius;
        return .{
            .min = Vec3f{ obj.position[0] - radius, obj.position[1] - radius, obj.position[2] - radius, 0.0 },
            .max = Vec3f{ obj.position[0] + radius, obj.position[1] + radius, obj.position[2] + radius, 0.0 },
        };
    }

    pub fn overlaps(self: AABB, other: AABB) bool {
        return self.min[0] <= other.max[0] and self.max[0] >= other.min[0] and
            self.min[1] <= other.max[1] and self.max[1] >= other.min[1] and
            self.min[2] <= other.max[2] and self.max[2] >= other.min[2];
    }
};

/// Improved collision detection system that can use either spatial hashing or AABB trees
pub const CollisionSystem = struct {
    allocator: Allocator,
    spatial_cell_size: f32,
    world_size: f32,

    /// Container for potential collision pairs to check
    collision_pairs: ArrayList([2]usize),

    /// Result list for actual collisions
    collision_results: ArrayList(CollisionInfo),

    pub fn init(allocator: Allocator, spatial_cell_size: f32, world_size: f32) !CollisionSystem {
        return CollisionSystem{
            .allocator = allocator,
            .spatial_cell_size = spatial_cell_size,
            .world_size = world_size,
            .collision_pairs = ArrayList([2]usize).init(allocator),
            .collision_results = ArrayList(CollisionInfo).init(allocator),
        };
    }

    pub fn deinit(self: *CollisionSystem) void {
        self.collision_pairs.deinit();
        self.collision_results.deinit();
    }

    /// Perform broadphase collision detection using spatial hashing
    pub fn broadphase(self: *CollisionSystem, objects: []PhysicalObject, object_count: usize) !void {
        try self.collision_pairs.resize(0);

        // Use 3D spatial hashing for broad-phase
        var cell_map = std.AutoHashMap([3]i32, ArrayList(usize)).init(self.allocator);
        defer {
            var it = cell_map.valueIterator();
            while (it.next()) |cell_objects| {
                cell_objects.deinit();
            }
            cell_map.deinit();
        }

        // Insert objects into cells
        for (objects[0..object_count], 0..) |obj, i| {
            if (!obj.active or obj.pinned) continue;

            // Calculate cell coordinates
            const inv_cell_size = 1.0 / self.spatial_cell_size;
            const min_x = @floatToInt(i32, @floor(obj.position[0] - obj.collision_radius) * inv_cell_size);
            const min_y = @floatToInt(i32, @floor(obj.position[1] - obj.collision_radius) * inv_cell_size);
            const min_z = @floatToInt(i32, @floor(obj.position[2] - obj.collision_radius) * inv_cell_size);
            const max_x = @floatToInt(i32, @floor(obj.position[0] + obj.collision_radius) * inv_cell_size);
            const max_y = @floatToInt(i32, @floor(obj.position[1] + obj.collision_radius) * inv_cell_size);
            const max_z = @floatToInt(i32, @floor(obj.position[2] + obj.collision_radius) * inv_cell_size);

            // Insert into all overlapping cells
            var x = min_x;
            while (x <= max_x) : (x += 1) {
                var y = min_y;
                while (y <= max_y) : (y += 1) {
                    var z = min_z;
                    while (z <= max_z) : (z += 1) {
                        const cell_key = [3]i32{ x, y, z };

                        var cell_entry = try cell_map.getOrPut(cell_key);
                        if (!cell_entry.found_existing) {
                            cell_entry.value_ptr.* = ArrayList(usize).init(self.allocator);
                        }

                        try cell_entry.value_ptr.append(i);
                    }
                }
            }
        }

        // Generate collision pairs from cells
        var it = cell_map.valueIterator();
        while (it.next()) |cell_objects| {
            const objects_in_cell = cell_objects.items;

            // Generate pairs within this cell
            for (objects_in_cell, 0..) |obj_a_idx, i| {
                for (objects_in_cell[i + 1 ..]) |obj_b_idx| {
                    // Don't create pairs between objects that can't collide
                    const obj_a = objects[obj_a_idx];
                    const obj_b = objects[obj_b_idx];

                    // Skip if either object is inactive
                    if (!obj_a.active or !obj_b.active) continue;

                    // Check collision masks
                    if ((obj_a.collision_group & obj_b.collision_mask) == 0 and
                        (obj_b.collision_group & obj_a.collision_mask) == 0) continue;

                    // Add collision pair
                    try self.collision_pairs.append([2]usize{ obj_a_idx, obj_b_idx });
                }
            }
        }
    }

    /// Perform narrow-phase collision detection
    pub fn narrowphase(self: *CollisionSystem, objects: []PhysicalObject) !void {
        try self.collision_results.resize(0);

        for (self.collision_pairs.items) |pair| {
            const a_idx = pair[0];
            const b_idx = pair[1];
            const obj_a = &objects[a_idx];
            const obj_b = &objects[b_idx];

            // Calculate distance between objects
            const delta = Vec3f{
                obj_b.position[0] - obj_a.position[0],
                obj_b.position[1] - obj_a.position[1],
                obj_b.position[2] - obj_a.position[2],
                0.0,
            };

            const distance_sq = delta[0] * delta[0] + delta[1] * delta[1] + delta[2] * delta[2];
            const min_dist = obj_a.collision_radius + obj_b.collision_radius;

            // Check if collision occurred
            if (distance_sq < min_dist * min_dist) {
                const distance = @sqrt(distance_sq);
                const penetration = min_dist - distance;

                var normal = if (distance > PhysicsConstants.SAFE_DIVISOR)
                    Vec3f{ delta[0] / distance, delta[1] / distance, delta[2] / distance, 0.0 }
                else
                    Vec3f{ 0.0, 1.0, 0.0, 0.0 };

                // Calculate contact point
                const contact_point = Vec3f{
                    obj_a.position[0] + normal[0] * obj_a.collision_radius,
                    obj_a.position[1] + normal[1] * obj_a.collision_radius,
                    obj_a.position[2] + normal[2] * obj_a.collision_radius,
                    0.0,
                };

                // Use the average restitution and friction
                const restitution = (obj_a.restitution + obj_b.restitution) * 0.5;
                const friction = (obj_a.friction + obj_b.friction) * 0.5;

                try self.collision_results.append(CollisionInfo{
                    .object_a_idx = a_idx,
                    .object_b_idx = b_idx,
                    .contact_point = contact_point,
                    .contact_normal = normal,
                    .penetration_depth = penetration,
                    .restitution = restitution,
                    .friction = friction,
                });
            }
        }
    }

    /// Resolve all collisions
    pub fn resolveCollisions(self: *CollisionSystem, objects: []PhysicalObject, dt: f32) void {
        for (self.collision_results.items) |collision| {
            const a_idx = collision.object_a_idx;
            const b_idx = collision.object_b_idx;
            var obj_a = &objects[a_idx];
            var obj_b = &objects[b_idx];

            // Skip if either object is pinned
            if (obj_a.pinned and obj_b.pinned) continue;

            // Calculate relative velocity
            const rel_vel = Vec3f{
                obj_b.velocity[0] - obj_a.velocity[0],
                obj_b.velocity[1] - obj_a.velocity[1],
                obj_b.velocity[2] - obj_a.velocity[2],
                0.0,
            };

            // Get collision normal
            const normal = collision.contact_normal;

            // Calculate relative velocity along the normal
            const vel_along_normal = rel_vel[0] * normal[0] + rel_vel[1] * normal[1] + rel_vel[2] * normal[2];

            // Objects are moving away from each other, no resolution needed
            if (vel_along_normal > 0) continue;

            // Calculate impulse scalar
            const e = collision.restitution;
            var j = -(1.0 + e) * vel_along_normal;
            j /= obj_a.inverse_mass + obj_b.inverse_mass;

            // Apply impulse
            const impulse = Vec3f{
                j * normal[0],
                j * normal[1],
                j * normal[2],
                0.0,
            };

            // Update velocities based on mass
            if (!obj_a.pinned) {
                obj_a.velocity[0] -= obj_a.inverse_mass * impulse[0];
                obj_a.velocity[1] -= obj_a.inverse_mass * impulse[1];
                obj_a.velocity[2] -= obj_a.inverse_mass * impulse[2];
            }

            if (!obj_b.pinned) {
                obj_b.velocity[0] += obj_b.inverse_mass * impulse[0];
                obj_b.velocity[1] += obj_b.inverse_mass * impulse[1];
                obj_b.velocity[2] += obj_b.inverse_mass * impulse[2];
            }

            // Positional correction to prevent sinking
            const percent = 0.2; // penetration percentage to correct
            const slop = 0.01; // penetration allowance
            const correction_magnitude = @max(collision.penetration_depth - slop, 0.0) * percent / (obj_a.inverse_mass + obj_b.inverse_mass);

            const correction = Vec3f{
                normal[0] * correction_magnitude,
                normal[1] * correction_magnitude,
                normal[2] * correction_magnitude,
                0.0,
            };

            if (!obj_a.pinned) {
                obj_a.position[0] -= correction[0] * obj_a.inverse_mass;
                obj_a.position[1] -= correction[1] * obj_a.inverse_mass;
                obj_a.position[2] -= correction[2] * obj_a.inverse_mass;
            }

            if (!obj_b.pinned) {
                obj_b.position[0] += correction[0] * obj_b.inverse_mass;
                obj_b.position[1] += correction[1] * obj_b.inverse_mass;
                obj_b.position[2] += correction[2] * obj_b.inverse_mass;
            }

            // Wake up objects involved in collision
            obj_a.wake();
            obj_b.wake();
        }
    }
};
