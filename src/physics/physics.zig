const std = @import("std");
const Allocator = std.mem.Allocator;
pub const math = @import("math/math.zig");
const platform = @import("../platform/platform.zig");
const Vector = math.Vector;
const Quaternion = math.Quaternion;
const SIMD = platform.SIMD;
const MemoryPool = std.heap.MemoryPool;

/// SIMD vector type for 3D physics with optimized alignment
/// Uses 4 components for better SIMD alignment, where the 4th component is typically 0
pub const Vec3f = @Vector(4, f32);

/// Constants for physics calculations
pub const PhysicsConstants = struct {
    /// Threshold below which distances are considered zero
    pub const EPSILON: f32 = 0.000001;
    /// Default floor height
    pub const FLOOR_HEIGHT: f32 = -5.0;
    /// Small constant to avoid division by zero
    pub const SAFE_DIVISOR: f32 = 0.0001;
    /// Maximum velocity to prevent unstable simulations
    pub const MAX_VELOCITY: f32 = 100.0;
    /// Default gravity value (Earth)
    pub const EARTH_GRAVITY: f32 = 9.81;
};

/// Configuration settings for the physics simulation
pub const PhysicsConfig = struct {
    use_gpu_acceleration: bool = SIMD.isGpuAccelerationAvailable(),
    gravity: Vec3f = Vec3f{ 0, -PhysicsConstants.EARTH_GRAVITY, 0, 0 },
    max_objects: u32 = 10000,
    max_constraints: u32 = 50000,
    cloth_damping: f32 = 0.98,
    constraint_iterations: u32 = 8,
    collision_iterations: u32 = 3,
    timestep: f32 = 1.0 / 60.0, // Fixed timestep
    collision_margin: f32 = 0.01, // Small margin to improve numerical stability
    /// Cell size for spatial hashing (0 for auto)
    spatial_cell_size: f32 = 0,
    /// Size of the world for spatial hashing
    world_size: f32 = 100.0,
    /// Enable or disable sleep optimization for static objects
    enable_sleeping: bool = true,
    /// Threshold for object sleeping (kinetic energy)
    sleep_threshold: f32 = 0.01,
    /// Number of frames object must be below threshold to sleep
    sleep_frames: u32 = 60,
};

/// Types of physical objects in the simulation
pub const ObjectType = enum(u8) {
    Particle, // Simple point mass
    ClothNode, // Node in cloth simulation
    RigidBody, // Solid body with rotational inertia
    SoftBody, // Deformable body
    Trigger, // Non-physical collision volume
    StaticBody, // Immovable body
};

/// Constraint between two physical objects
pub const SpringConstraint = struct {
    object_index_a: usize,
    object_index_b: usize,
    rest_length: f32,
    stiffness: f32,
    damping: f32 = 0.1,
    break_threshold: f32 = math.inf(f32),
    active: bool = true, // Flag to easily disable constraints

    // Additional fields for advanced constraints
    min_length: f32 = 0,
    max_length: f32 = math.inf(f32),
    bidirectional: bool = true, // If false, only pulls, doesn't push
};

/// Physical object representation with position, velocity, and other properties
pub const PhysicalObject = struct {
    position: Vec3f align(16),
    old_position: Vec3f align(16),
    velocity: Vec3f align(16),
    acceleration: Vec3f align(16),
    angular_velocity: Vec3f align(16) = Vec3f{ 0, 0, 0, 0 },
    orientation: Quaternion align(16) = Quaternion.identity(),
    mass: f32,
    inverse_mass: f32, // Cached for performance
    active: bool,
    pinned: bool = false,
    obj_type: ObjectType,
    friction: f32 = 0.3,
    restitution: f32 = 0.5,
    collision_radius: f32 = 1.0,
    material_id: u16 = 0, // For future material properties

    // Sleep optimization fields
    sleeping: bool = false,
    sleep_timer: u32 = 0,

    // Collision group/mask for filtering
    collision_group: u16 = 1,
    collision_mask: u16 = 0xFFFF,

    /// Apply force to the object
    pub fn applyForce(self: *PhysicalObject, force: Vec3f) void {
        if (self.pinned or self.sleeping) return;
        self.acceleration += force * @splat(4, self.inverse_mass);
        // Wake up sleeping objects when forces are applied
        if (self.sleeping) self.wake();
    }

    /// Apply impulse (immediate change in velocity)
    pub fn applyImpulse(self: *PhysicalObject, impulse: Vec3f) void {
        if (self.pinned or self.sleeping) return;
        self.velocity += impulse * @splat(4, self.inverse_mass);
        // Wake up sleeping objects when impulses are applied
        if (self.sleeping) self.wake();
    }

    /// Apply torque to the object (for rigid bodies)
    pub fn applyTorque(self: *PhysicalObject, torque: Vec3f) void {
        if (self.pinned or self.sleeping or self.obj_type != .RigidBody) return;
        // Use optimized inertia tensor calculation from math module
        const inertia = math.calcInertiaTensor(self.mass, self.collision_radius, self.obj_type);
        self.angular_velocity += Vector.divideVectors(torque, inertia);

        if (self.sleeping) self.wake();
    }

    /// Wake a sleeping object
    pub fn wake(self: *PhysicalObject) void {
        self.sleeping = false;
        self.sleep_timer = 0;
    }

    /// Put object to sleep (disable updates until disturbed)
    pub fn sleep(self: *PhysicalObject) void {
        self.sleeping = true;
        self.velocity = @splat(4, @as(f32, 0));
        self.angular_velocity = @splat(4, @as(f32, 0));
    }

    /// Initialize a physical object with calculated properties
    pub fn init(position: Vec3f, mass: f32, obj_type: ObjectType) PhysicalObject {
        // Use static assertion to ensure Vec3f has proper alignment
        comptime {
            if (@alignOf(Vec3f) < 16) @compileError("Vec3f must be 16-byte aligned");
        }

        const inverse_mass = switch (obj_type) {
            .StaticBody => 0.0, // Static bodies have infinite mass
            else => if (mass > PhysicsConstants.SAFE_DIVISOR) 1.0 / mass else 0.0,
        };

        return PhysicalObject{
            .position = position,
            .old_position = position,
            .velocity = @splat(4, @as(f32, 0)),
            .acceleration = @splat(4, @as(f32, 0)),
            .mass = mass,
            .inverse_mass = inverse_mass,
            .active = true,
            .obj_type = obj_type,
        };
    }

    /// Calculate kinetic energy of the object
    pub fn kineticEnergy(self: PhysicalObject) f32 {
        if (self.sleeping or self.pinned) return 0;

        // Use optimized vector dot product from math module
        const vel_sq = Vector.dot3(self.velocity, self.velocity);
        const angular_vel_sq = Vector.dot3(self.angular_velocity, self.angular_velocity);

        // Different inertia calculation based on object type
        var rotational_energy: f32 = 0;
        if (self.obj_type == .RigidBody) {
            rotational_energy = math.calcRotationalEnergy(self.mass, self.collision_radius, angular_vel_sq);
        }

        return 0.5 * self.mass * vel_sq + rotational_energy;
    }

    /// Transform a point from local to world space
    pub fn localToWorldPoint(self: PhysicalObject, local_point: Vec3f) Vec3f {
        if (self.obj_type != .RigidBody) return self.position + local_point;

        // Use quaternion rotation for more accurate rotation
        const rotated = Quaternion.rotateVector(self.orientation, local_point);
        return self.position + rotated;
    }
};

/// Main physics simulation world containing all objects and constraints
pub const World = struct {
    allocator: Allocator,
    config: PhysicsConfig,
    objects: []PhysicalObject,
    constraints: []SpringConstraint,
    object_count: usize,
    constraint_count: usize,
    initialized: bool = false,
    spatial_hash: ?SpatialHashGrid = null,
    accumulated_time: f32 = 0.0,

    // Performance statistics
    perf_stats: struct {
        update_time_ns: u64 = 0,
        collision_time_ns: u64 = 0,
        constraint_time_ns: u64 = 0,
        active_objects: usize = 0,
    } = .{},

    // Events and callbacks
    collision_callbacks: std.ArrayList(fn (a: usize, b: usize) void),

    const Self = @This();

    /// Initialize a new physics world
    pub fn init(allocator: Allocator, config: PhysicsConfig) !Self {
        // Use platform detection to setup GPU acceleration if available
        const optimized_config = if (platform.hasHardwareAcceleration() and config.use_gpu_acceleration) blk: {
            var cfg = config;
            cfg.use_gpu_acceleration = true;
            break :blk cfg;
        } else config;

        const objects = try allocator.alloc(PhysicalObject, config.max_objects);
        const constraints = try allocator.alloc(SpringConstraint, config.max_constraints);

        var world = Self{
            .allocator = allocator,
            .config = optimized_config,
            .objects = objects,
            .constraints = constraints,
            .object_count = 0,
            .constraint_count = 0,
            .initialized = true,
            .collision_callbacks = std.ArrayList(fn (a: usize, b: usize) void).init(allocator),
        };

        // Initialize spatial hash with configured parameters
        world.spatial_hash = try SpatialHashGrid.init(allocator, optimized_config.world_size, optimized_config.spatial_cell_size);

        return world;
    }

    /// Clean up all resources
    pub fn deinit(self: *Self) void {
        if (self.spatial_hash) |*grid| {
            grid.deinit();
        }
        self.allocator.free(self.objects);
        self.allocator.free(self.constraints);
        self.collision_callbacks.deinit();
        self.initialized = false;
    }

    /// Create a new physical object in the world
    pub fn createObject(self: *Self, position: Vec3f, mass: f32, obj_type: ObjectType) !*PhysicalObject {
        if (self.object_count >= self.config.max_objects) {
            return error.MaxObjectsReached;
        }

        const index = self.object_count;
        self.object_count += 1;

        self.objects[index] = PhysicalObject.init(position, mass, obj_type);

        // If object is static, set it to sleeping by default
        if (obj_type == .StaticBody) {
            self.objects[index].sleeping = true;
        }

        return &self.objects[index];
    }

    /// Register a collision callback function
    pub fn registerCollisionCallback(self: *Self, callback: fn (a: usize, b: usize) void) !void {
        try self.collision_callbacks.append(callback);
    }

    /// Create a constraint between two objects
    pub fn createConstraint(self: *Self, idx_a: usize, idx_b: usize, stiffness: f32) !void {
        if (self.constraint_count >= self.config.max_constraints) {
            return error.MaxConstraintsReached;
        }
        if (idx_a >= self.object_count or idx_b >= self.object_count) {
            return error.InvalidObjectIndex;
        }
        if (idx_a == idx_b) {
            return error.CannotConstrainToSelf;
        }

        const a_pos = self.objects[idx_a].position;
        const b_pos = self.objects[idx_b].position;

        // Use Vector module for distance calculation
        const rest_length = math.Vector.distance3(a_pos, b_pos);

        self.constraints[self.constraint_count] = SpringConstraint{
            .object_index_a = idx_a,
            .object_index_b = idx_b,
            .rest_length = @max(rest_length, PhysicsConstants.EPSILON),
            .stiffness = stiffness,
        };

        self.constraint_count += 1;
    }

    /// Create a cloth simulation grid
    pub fn createClothGrid(self: *Self, top_left: Vec3f, width: f32, height: f32, rows: usize, cols: usize, mass: f32, stiffness: f32) !void {
        if (rows < 2 or cols < 2) return error.InvalidDimensions;
        if (self.object_count + rows * cols > self.config.max_objects) return error.NotEnoughSpace;

        const total_constraints = (rows - 1) * cols + rows * (cols - 1) +
            (rows - 1) * (cols - 1) * 2 +
            (rows - 2) * cols + rows * (cols - 2);

        if (self.constraint_count + total_constraints > self.config.max_constraints) {
            return error.NotEnoughConstraintSpace;
        }

        const dx = width / @as(f32, @floatFromInt(cols - 1));
        const dy = height / @as(f32, @floatFromInt(rows - 1));

        const base_idx = self.object_count;

        // Use parallel processing if supported by the platform
        if (platform.supportsParallelProcessing() and rows * cols > 100) {
            // Placeholder for parallel implementation using platform module
            try platform.parallelFor(0, rows, 1, struct {
                fn createRow(row: usize, ctx: anytype) !void {
                    const self_ptr = ctx.self;
                    const cols_val = ctx.cols;
                    const dx_val = ctx.dx;
                    const dy_val = ctx.dy;
                    const top_left_val = ctx.top_left;
                    const mass_val = ctx.mass;

                    for (0..cols_val) |col| {
                        const pos = Vec3f{
                            top_left_val[0] + @as(f32, @floatFromInt(col)) * dx_val,
                            top_left_val[1] - @as(f32, @floatFromInt(row)) * dy_val,
                            top_left_val[2],
                            0,
                        };
                        const node = try self_ptr.createObject(pos, mass_val, .ClothNode);

                        // Pin the top row by default
                        if (row == 0) {
                            node.pinned = true;
                        }
                    }
                }
            }.createRow, .{
                .self = self,
                .cols = cols,
                .dx = dx,
                .dy = dy,
                .top_left = top_left,
                .mass = mass,
            });
        } else {
            // Original sequential implementation
            // Create nodes first
            for (0..rows) |row| {
                for (0..cols) |col| {
                    const pos = Vec3f{
                        top_left[0] + @as(f32, @floatFromInt(col)) * dx,
                        top_left[1] - @as(f32, @floatFromInt(row)) * dy,
                        top_left[2],
                        0,
                    };
                    const node = try self.createObject(pos, mass, .ClothNode);

                    // Pin the top row by default
                    if (row == 0) {
                        node.pinned = true;
                    }
                }
            }
        }

        // Now create constraints
        for (0..rows) |row| {
            for (0..cols) |col| {
                const idx = base_idx + row * cols + col;

                // Structural constraints (horizontal and vertical)
                if (col > 0) {
                    try self.createConstraint(idx, idx - 1, stiffness);
                }
                if (row > 0) {
                    try self.createConstraint(idx, idx - cols, stiffness);
                }

                // Shear constraints (diagonal)
                if (row > 0 and col > 0) {
                    try self.createConstraint(idx, idx - cols - 1, stiffness * 0.8);
                }
                if (row > 0 and col < cols - 1) {
                    try self.createConstraint(idx, idx - cols + 1, stiffness * 0.8);
                }

                // Bend constraints (connections spanning 2 particles)
                if (col > 1) {
                    try self.createConstraint(idx, idx - 2, stiffness * 0.5);
                }
                if (row > 1) {
                    try self.createConstraint(idx, idx - 2 * cols, stiffness * 0.5);
                }
            }
        }
    }

    /// Enforce all constraints between objects
    fn solveConstraints(self: *Self) void {
        const timer = platform.Timer.start();

        // Use SIMD operations if supported and enabled
        if (self.config.use_gpu_acceleration and SIMD.isAvailable()) {
            return SIMD.solveConstraintsBatch(self);
        }

        var i: usize = 0;
        while (i < self.constraint_count) : (i += 1) {
            var constraint = &self.constraints[i];

            if (!constraint.active) continue;

            var obj_a = &self.objects[constraint.object_index_a];
            var obj_b = &self.objects[constraint.object_index_b];

            if (!obj_a.active or !obj_b.active) continue;
            if (obj_a.sleeping and obj_b.sleeping) continue; // Skip if both objects are sleeping

            // Wake sleeping objects that are involved in constraints with active objects
            if (obj_a.sleeping and !obj_b.sleeping) obj_a.wake();
            if (!obj_a.sleeping and obj_b.sleeping) obj_b.wake();

            const diff = obj_a.position - obj_b.position;
            const dist_sq = Vector.dot3(diff, diff);
            if (dist_sq < PhysicsConstants.EPSILON) continue; // Avoid division by near-zero

            const dist = @sqrt(dist_sq);

            // Check length constraints (min/max)
            if (dist < constraint.min_length) {
                // Constraint is too short but we don't enforce minimum length
                if (!constraint.bidirectional) continue;
            } else if (dist > constraint.max_length) {
                // Constraint is too long
                if (dist > constraint.break_threshold) {
                    // Swap with last and decrement count (more efficient removal)
                    constraint.active = false;
                    if (i < self.constraint_count - 1) {
                        self.constraints[i] = self.constraints[self.constraint_count - 1];
                        i -= 1; // Process this index again since we replaced it
                    }
                    self.constraint_count -= 1;
                    continue;
                }
            }

            // Calculate velocity-based damping using improved vector operations
            const rel_velocity = obj_a.velocity - obj_b.velocity;
            const damping_force = Vector.dot3(diff, rel_velocity) * constraint.damping / dist;

            // Calculate position correction
            const diff_factor = (dist - constraint.rest_length) / dist;
            const correction = diff * @splat(4, (diff_factor * constraint.stiffness - damping_force));

            // Apply correction with mass weighting
            const mass_sum = obj_a.mass + obj_b.mass;
            const mass_ratio_a = if (mass_sum > PhysicsConstants.SAFE_DIVISOR)
                obj_b.mass / mass_sum
            else
                0.5;
            const mass_ratio_b = if (mass_sum > PhysicsConstants.SAFE_DIVISOR)
                obj_a.mass / mass_sum
            else
                0.5;

            if (!obj_a.pinned) {
                obj_a.position -= correction * @splat(4, mass_ratio_a);
            }

            if (!obj_b.pinned) {
                obj_b.position += correction * @splat(4, mass_ratio_b);
            }
        }

        self.perf_stats.constraint_time_ns = timer.elapsed();
    }

    /// Update the physics world with variable time step
    pub fn update(self: *Self, delta_time: f64) !void {
        const timer = platform.Timer.start();

        // Cap delta time to avoid instability with very large steps
        const capped_dt = @min(delta_time, 0.1);
        self.accumulated_time += @floatCast(capped_dt);

        // Run fixed timestep updates
        while (self.accumulated_time >= self.config.timestep) {
            try self.fixedUpdate();
            self.accumulated_time -= self.config.timestep;
        }

        self.perf_stats.update_time_ns = timer.elapsed();
    }

    /// Fixed timestep update for deterministic physics
    fn fixedUpdate(self: *Self) !void {
        const dt = self.config.timestep;
        const dt_vec = @splat(4, dt);
        const dampening = @splat(4, self.config.cloth_damping);

        // Count active objects for stats
        self.perf_stats.active_objects = 0;

        // Update spatial hash grid
        if (self.spatial_hash) |*grid| {
            try grid.clear();

            // Insert active objects into spatial hash
            for (self.objects[0..self.object_count], 0..) |*obj, i| {
                if (!obj.active or obj.sleeping) continue;
                self.perf_stats.active_objects += 1;
                try grid.insert(obj.position, i);
            }
        }

        // Apply forces and update velocities for all objects
        for (self.objects[0..self.object_count]) |*obj| {
            if (!obj.active or obj.pinned or obj.sleeping) continue;

            // Static bodies don't move
            if (obj.obj_type == .StaticBody) continue;

            // Apply gravity force
            const gravity_force = self.config.gravity * @splat(4, obj.mass);
            obj.applyForce(gravity_force);

            // Verlet integration with improved numerical stability
            obj.velocity = Vector.clampMagnitude((obj.position - obj.old_position) / dt_vec, PhysicsConstants.MAX_VELOCITY);
            const temp_pos = obj.position;

            // Update position with dampening
            obj.position += (obj.position - obj.old_position) * dampening + obj.acceleration * dt_vec * dt_vec;
            obj.old_position = temp_pos;

            // Handle rigid body orientation updates using quaternions for better stability
            if (obj.obj_type == .RigidBody) {
                // Convert angular velocity to quaternion change
                const half_omega = obj.angular_velocity * @splat(4, 0.5 * dt);
                const q_delta = Quaternion.fromAxisAngle(half_omega[0..3], Vector.length3(half_omega));
                obj.orientation = Quaternion.multiply(obj.orientation, q_delta).normalized();
            }

            // Check if object should be put to sleep
            if (self.config.enable_sleeping) {
                const energy = obj.kineticEnergy();
                if (energy < self.config.sleep_threshold) {
                    obj.sleep_timer += 1;
                    if (obj.sleep_timer >= self.config.sleep_frames) {
                        obj.sleep();
                    }
                } else {
                    obj.sleep_timer = 0;
                }
            }

            // Reset acceleration for next frame
            obj.acceleration = @splat(4, @as(f32, 0));
        }

        // Solve constraints multiple times for stability
        var iter: u32 = 0;
        while (iter < self.config.constraint_iterations) : (iter += 1) {
            self.solveConstraints();
        }

        // Handle collisions
        var collision_iter: u32 = 0;
        while (collision_iter < self.config.collision_iterations) : (collision_iter += 1) {
            try self.handleCollisions();
        }
    }

    /// Detect and resolve collisions between objects
    fn handleCollisions(self: *Self) !void {
        const timer = platform.Timer.start();
        const floor_height = PhysicsConstants.FLOOR_HEIGHT;

        if (self.spatial_hash) |grid| {
            for (self.objects[0..self.object_count], 0..) |*obj_a, i| {
                if (!obj_a.active or obj_a.sleeping) continue;

                // Skip trigger volumes for physics response (they just generate callbacks)
                const is_trigger = obj_a.obj_type == .Trigger;

                // Floor collision
                if (obj_a.position[1] < floor_height + obj_a.collision_radius) {
                    if (!is_trigger) {
                        obj_a.position[1] = floor_height + obj_a.collision_radius;

                        // Only apply restitution if moving toward the floor
                        if (obj_a.velocity[1] < 0) {
                            obj_a.velocity[1] = -obj_a.velocity[1] * obj_a.restitution;
                        }

                        // Apply friction to lateral velocity
                        const lateral_vel = Vec3f{ obj_a.velocity[0], 0, obj_a.velocity[2], 0 };
                        const lateral_speed_sq = Vector.dot3(lateral_vel, lateral_vel);

                        if (lateral_speed_sq > PhysicsConstants.EPSILON) {
                            const friction_force = lateral_vel * @splat(4, -obj_a.friction);
                            obj_a.velocity += friction_force;
                        }
                    }

                    // Fire collision callbacks for floor
                    for (self.collision_callbacks.items) |callback| {
                        callback(i, std.math.maxInt(usize)); // Use max value for floor
                    }
                }

                // Object-object collision using spatial hash for efficiency
                const query_radius = obj_a.collision_radius * 2.0 + self.config.collision_margin;
                const nearby = try grid.queryNearby(obj_a.position, query_radius);
                defer nearby.deinit();

                for (nearby.items) |j| {
                    if (i == j) continue; // Skip self-collision

                    var obj_b = &self.objects[j];
                    if (!obj_b.active or obj_b.sleeping) continue;

                    // Skip collision if objects are in different collision groups
                    if ((obj_a.collision_group & obj_b.collision_mask) == 0 and
                        (obj_b.collision_group & obj_a.collision_mask) == 0)
                    {
                        continue;
                    }

                    const diff = obj_a.position - obj_b.position;
                    // Ignore w component in distance calculation for 3D objects
                    const dist_sq = diff[0] * diff[0] + diff[1] * diff[1] + diff[2] * diff[2];
                    const min_dist = obj_a.collision_radius + obj_b.collision_radius;

                    if (dist_sq < min_dist * min_dist) {
                        // Trigger collision callbacks regardless of physics response
                        for (self.collision_callbacks.items) |callback| {
                            callback(i, j);
                        }

                        // Skip physical response if either object is a trigger
                        if (is_trigger or obj_b.obj_type == .Trigger) continue;

                        // Only compute square root when needed for collision response
                        const dist = @sqrt(dist_sq);
                        const penetration = min_dist - dist;

                        // Avoid division by zero with small distances
                        if (dist < PhysicsConstants.SAFE_DIVISOR) continue;

                        const inv_dist = 1.0 / dist;
                        const normal = diff * @splat(4, inv_dist);

                        // Check if objects are moving toward each other
                        const rel_velocity = obj_a.velocity - obj_b.velocity;
                        const normal_velocity = Vector.dot3(rel_velocity, normal);

                        if (normal_velocity > 0) continue; // Objects moving apart, no collision response needed

                        // Calculate impulse using conservation of momentum
                        const restitution = @min(obj_a.restitution, obj_b.restitution);
                        const j_numerator = -(1.0 + restitution) * normal_velocity;
                        const j_denominator = obj_a.inverse_mass + obj_b.inverse_mass;
                        const impulse = if (j_denominator > PhysicsConstants.SAFE_DIVISOR)
                            j_numerator / j_denominator
                        else
                            0;

                        const impulse_vec = normal * @splat(4, impulse);

                        // Apply impulse to velocities
                        if (!obj_a.pinned) {
                            obj_a.velocity += impulse_vec * @splat(4, obj_a.inverse_mass);
                            // Resolve penetration
                            obj_a.position += normal * @splat(4, penetration * 0.5);
                            // Wake up object if it was sleeping
                            if (obj_a.sleeping) obj_a.wake();
                        }

                        if (!obj_b.pinned) {
                            obj_b.velocity -= impulse_vec * @splat(4, obj_b.inverse_mass);
                            obj_b.position -= normal * @splat(4, penetration * 0.5);
                            // Wake up object if it was sleeping
                            if (obj_b.sleeping) obj_b.wake();
                        }

                        // Apply friction at contact point using improved model
                        if (impulse > PhysicsConstants.EPSILON) {
                            // Calculate tangent vector (perpendicular to normal)
                            const tangent_vel = rel_velocity - normal * @splat(4, normal_velocity);
                            const tangent_vel_sq = Vector.dot3(tangent_vel, tangent_vel);

                            if (tangent_vel_sq > PhysicsConstants.EPSILON) {
                                const tangent = Vector.normalize3(tangent_vel);
                                const friction = @min(obj_a.friction, obj_b.friction);
                                const friction_impulse = math.clamp(friction * impulse, 0.0, @sqrt(tangent_vel_sq));
                                const friction_vec = tangent * @splat(4, -friction_impulse);

                                if (!obj_a.pinned) {
                                    obj_a.velocity += friction_vec * @splat(4, obj_a.inverse_mass);
                                }
                                if (!obj_b.pinned) {
                                    obj_b.velocity -= friction_vec * @splat(4, obj_b.inverse_mass);
                                }
                            }
                        }
                    }
                }
            }
        }

        self.perf_stats.collision_time_ns = timer.elapsed();
    }

    /// Create a rigid body from a predefined shape
    pub fn createRigidBodyBox(self: *Self, position: Vec3f, size: Vec3f, mass: f32) !*PhysicalObject {
        const obj = try self.createObject(position, mass, .RigidBody);
        // Use more accurate inertia tensor calculation for boxes
        obj.collision_radius = @sqrt(size[0] * size[0] + size[1] * size[1] + size[2] * size[2]) * 0.5;
        return obj;
    }

    /// Create a sphere-shaped rigid body
    pub fn createRigidBodySphere(self: *Self, position: Vec3f, radius: f32, mass: f32) !*PhysicalObject {
        const obj = try self.createObject(position, mass, .RigidBody);
        obj.collision_radius = radius;
        return obj;
    }

    /// Create a static collision plane
    pub fn createStaticPlane(self: *Self, normal: Vec3f, distance: f32) !*PhysicalObject {
        const normalized_normal = Vector.normalize3(normal);
        const position = normalized_normal * @splat(4, distance);
        const obj = try self.createObject(position, math.inf(f32), .StaticBody);
        obj.pinned = true;
        return obj;
    }

    /// Create a soft body mesh
    pub fn createSoftBody(self: *Self, center: Vec3f, radius: f32, mass: f32, divisions: u32) !void {
        if (platform.hasAdvancedPhysics()) {
            // If platform supports advanced physics, delegate to its implementation
            return platform.Physics.createTetrahedralMesh(self, center, radius, mass, divisions);
        }

        // Fallback implementation - create a simple particle-based soft body
        if (divisions < 2) return error.InvalidDivisions;

        const total_particles = divisions * divisions * divisions;
        if (self.object_count + total_particles > self.config.max_objects) {
            return error.NotEnoughSpace;
        }

        const particle_mass = mass / @as(f32, @floatFromInt(total_particles));
        const step = radius * 2.0 / @as(f32, @floatFromInt(divisions - 1));
        const offset = Vec3f{ -radius, -radius, -radius, 0 };

        // Create particles in a grid
        var particles = std.ArrayList(usize).init(self.allocator);
        defer particles.deinit();

        for (0..divisions) |x| {
            for (0..divisions) |y| {
                for (0..divisions) |z| {
                    const pos = Vec3f{
                        offset[0] + @as(f32, @floatFromInt(x)) * step,
                        offset[1] + @as(f32, @floatFromInt(y)) * step,
                        offset[2] + @as(f32, @floatFromInt(z)) * step,
                        0,
                    } + center;

                    // Skip particles outside the sphere
                    const to_center = pos - center;
                    if (Vector.dot3(to_center, to_center) > radius * radius) continue;

                    const obj_idx = self.object_count;
                    _ = try self.createObject(pos, particle_mass, .SoftBody);
                    try particles.append(obj_idx);
                }
            }
        }

        // Create constraints between nearby particles
        for (particles.items) |i| {
            for (particles.items) |j| {
                if (i == j) continue;

                const diff = self.objects[i].position - self.objects[j].position;
                const dist_sq = Vector.dot3(diff, diff);

                // Only connect nearby particles
                if (dist_sq < step * step * 1.5) {
                    try self.createConstraint(i, j, 0.5);
                }
            }
        }
    }

    /// Get total kinetic energy of the system (useful for monitoring stability)
    pub fn getTotalEnergy(self: Self) f32 {
        var energy: f32 = 0;
        for (self.objects[0..self.object_count]) |obj| {
            if (obj.active and !obj.pinned and !obj.sleeping) {
                energy += obj.kineticEnergy();
            }
        }
        return energy;
    }

    /// Get performance statistics as a JSON string
    pub fn getPerformanceStats(self: Self, allocator: Allocator) ![]const u8 {
        return std.json.stringifyAlloc(allocator, self.perf_stats, .{ .whitespace = .indent_2 });
    }
};

/// Spatial hashing structure for efficient broad-phase collision detection
const SpatialHashGrid = struct {
    cell_size: f32,
    inv_cell_size: f32,
    cells: std.AutoHashMap(u64, std.ArrayList(usize)),
    allocator: Allocator,

    // Pool for query results to reduce allocations
    result_pool: MemoryPool(std.ArrayList(usize)),

    /// Initialize a new spatial hash grid
    pub fn init(allocator: Allocator, world_size: f32, cell_size: f32) !SpatialHashGrid {
        const adjusted_cell_size = if (cell_size <= 0)
            @max(world_size / 20.0, 1.0) // Better default cell size based on world size
        else
            cell_size;

        var grid = SpatialHashGrid{
            .cell_size = adjusted_cell_size,
            .inv_cell_size = 1.0 / adjusted_cell_size,
            .cells = std.AutoHashMap(u64, std.ArrayList(usize)).init(allocator),
            .allocator = allocator,
            .result_pool = try MemoryPool(std.ArrayList(usize)).init(allocator),
        };

        // Pre-allocate a reasonable number of hash buckets
        try grid.cells.ensureTotalCapacity(256);
        return grid;
    }

    /// Clean up resources
    pub fn deinit(self: *SpatialHashGrid) void {
        var it = self.cells.valueIterator();
        while (it.next()) |cell| {
            cell.deinit();
        }
        self.cells.deinit();
        self.result_pool.deinit();
    }

    /// Clear all cells but keep memory allocated
    pub fn clear(self: *SpatialHashGrid) !void {
        var it = self.cells.valueIterator();
        while (it.next()) |cell| {
            cell.clearRetainingCapacity();
        }
    }

    /// Convert a 3D position to a 1D hash value
    fn hashPosition(self: SpatialHashGrid, pos: Vec3f) u64 {
        const ix = @as(i32, @intFromFloat(@floor(pos[0] * self.inv_cell_size)));
        const iy = @as(i32, @intFromFloat(@floor(pos[1] * self.inv_cell_size)));
        const iz = @as(i32, @intFromFloat(@floor(pos[2] * self.inv_cell_size)));

        // Use improved hash function from math module if available
        if (@hasDecl(math, "spatialHash3D")) {
            return math.spatialHash3D(ix, iy, iz);
        }

        // Fallback implementation with better bit masking
        const shifted_x = @as(u64, @bitCast(@as(i64, ix))) & 0x1FFFFF; // 21 bits
        const shifted_y = @as(u64, @bitCast(@as(i64, iy))) & 0x1FFFFF; // 21 bits
        const shifted_z = @as(u64, @bitCast(@as(i64, iz))) & 0x1FFFFF; // 21 bits

        return (shifted_x << 42) | (shifted_y << 21) | shifted_z;
    }

    /// Insert an object into the grid at the specified position
    pub fn insert(self: *SpatialHashGrid, pos: Vec3f, index: usize) !void {
        const hash = self.hashPosition(pos);

        if (self.cells.getPtr(hash)) |cell| {
            try cell.append(index);
        } else {
            var new_cell = std.ArrayList(usize).init(self.allocator);
            // Most cells won't have many objects, so start small to save memory
            try new_cell.ensureTotalCapacity(4);
            try new_cell.append(index);
            try self.cells.put(hash, new_cell);
        }
    }

    /// Find all objects within a specified radius of a position
    pub fn queryNearby(self: *SpatialHashGrid, pos: Vec3f, radius: f32) !std.ArrayList(usize) {
        // Get a result list from the pool to reduce allocations
        var result = try self.result_pool.create();
        errdefer {
            result.deinit();
            _ = self.result_pool.destroy(result);
        }
        result.clearRetainingCapacity();

        // Calculate cell bounds for optimization
        const min_x = @as(i32, @intFromFloat(@floor((pos[0] - radius) * self.inv_cell_size)));
        const min_y = @as(i32, @intFromFloat(@floor((pos[1] - radius) * self.inv_cell_size)));
        const min_z = @as(i32, @intFromFloat(@floor((pos[2] - radius) * self.inv_cell_size)));
        const max_x = @as(i32, @intFromFloat(@floor((pos[0] + radius) * self.inv_cell_size)));
        const max_y = @as(i32, @intFromFloat(@floor((pos[1] + radius) * self.inv_cell_size)));
        const max_z = @as(i32, @intFromFloat(@floor((pos[2] + radius) * self.inv_cell_size)));

        // Optimize by pre-allocating the expected capacity
        const estimated_capacity = (max_x - min_x + 1) * (max_y - min_y + 1) * (max_z - min_z + 1) * 4;
        try result.ensureTotalCapacity(@min(estimated_capacity, 1024)); // Cap at reasonable size

        // Use optimized cell iteration with platform-specific vectorization if available
        if (platform.hasVectorizedSpatialQuery()) {
            try platform.vectorizedSpatialQuery(self, min_x, min_y, min_z, max_x, max_y, max_z, &result);
        } else {
            // Fallback to standard implementation
            var x = min_x;
            while (x <= max_x) : (x += 1) {
                var y = min_y;
                while (y <= max_y) : (y += 1) {
                    var z = min_z;
                    while (z <= max_z) : (z += 1) {
                        // Calculate cell hash directly
                        const hash = self.hashPosition(Vec3f{
                            @floatFromInt(x),
                            @floatFromInt(y),
                            @floatFromInt(z),
                            0,
                        });

                        if (self.cells.get(hash)) |cell| {
                            try result.appendSlice(cell.items);
                        }
                    }
                }
            }
        }

        return result;
    }

    /// Find the nearest object to the specified position
    /// Takes a callback to calculate actual distances with world objects
    pub fn findNearest(self: *SpatialHashGrid, pos: Vec3f, max_distance: f32, distFunc: fn (idx: usize, pos: Vec3f, ctx: anytype) f32, context: anytype) !?usize {
        const nearby = try self.queryNearby(pos, max_distance);
        defer {
            nearby.clearRetainingCapacity();
            _ = self.result_pool.destroy(&nearby);
        }

        var closest_idx: ?usize = null;
        var closest_dist_sq: f32 = max_distance * max_distance;

        for (nearby.items) |idx| {
            const dist = distFunc(idx, pos, context);
            if (dist < closest_dist_sq) {
                closest_dist_sq = dist;
                closest_idx = idx;
            }
        }

        return closest_idx;
    }
};
