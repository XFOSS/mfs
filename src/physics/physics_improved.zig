const std = @import("std");
const Allocator = std.mem.Allocator;
const math = @import("math/math.zig");
const platform = @import("../platform/platform.zig");
const Vector = math.Vector;
const Quaternion = math.Quaternion;
const SIMD = platform.SIMD;
const MemoryPool = std.heap.MemoryPool;

const collision = @import("collision.zig");
const constraints = @import("constraints.zig");
const rigid_body = @import("rigid_body.zig");

// Export submodule symbols
pub const collision_module = collision;
pub const constraints_module = constraints;
pub const rigid_body_module = rigid_body;
pub const math = math;

/// Vector type for 3D physics operations, using 4 components for SIMD alignment
pub const Vec3f = @Vector(4, f32);

/// Constants used throughout the physics system
pub const PhysicsConstants = struct {
    /// Small value to avoid numerical errors
    pub const EPSILON: f32 = 0.000001;

    /// Default floor height for simulations
    pub const FLOOR_HEIGHT: f32 = -5.0;

    /// Safe divisor to avoid division by zero
    pub const SAFE_DIVISOR: f32 = 0.0001;

    /// Maximum allowed velocity magnitude
    pub const MAX_VELOCITY: f32 = 100.0;

    /// Earth's gravitational acceleration (m/s²)
    pub const EARTH_GRAVITY: f32 = 9.81;
};

/// Configuration options for the physics world
pub const PhysicsConfig = struct {
    /// Whether to use GPU acceleration when available
    use_gpu_acceleration: bool = false,

    /// Gravity vector (default is Earth gravity along -Y axis)
    gravity: Vec3f = Vec3f{ 0.0, -PhysicsConstants.EARTH_GRAVITY, 0.0, 0.0 },

    /// Maximum number of physical objects
    max_objects: usize = 1000,

    /// Maximum number of constraints
    max_constraints: usize = 2000,

    /// Damping coefficient for cloth simulation
    cloth_damping: f32 = 0.01,

    /// Number of constraint solver iterations per step
    constraint_iterations: u32 = 4,

    /// Number of collision handling iterations per step
    collision_iterations: u32 = 1,

    /// Fixed timestep for physics simulation
    timestep: f32 = 1.0 / 60.0,

    /// Collision margin to improve stability
    collision_margin: f32 = 0.01,

    /// Cell size for spatial partitioning
    spatial_cell_size: f32 = 1.0,

    /// Size of the simulation world
    world_size: f32 = 100.0,

    /// Whether to enable object sleeping for performance
    enable_sleeping: bool = true,

    /// Energy threshold below which objects go to sleep
    sleep_threshold: f32 = 0.01,

    /// Number of frames below threshold to sleep
    sleep_frames: u32 = 60,
};

/// Types of physical objects
pub const ObjectType = enum(u8) {
    Particle,
    ClothNode,
    RigidBody,
    SoftBody,
    Trigger,
    StaticBody,
};

/// Spring constraint between two objects
pub const SpringConstraint = struct {
    object_index_a: usize,
    object_index_b: usize,
    rest_length: f32,
    stiffness: f32,
    damping: f32,
    break_threshold: f32,
    active: bool = true,

    // Advanced spring properties
    min_length: f32 = 0.0,
    max_length: f32 = std.math.inf(f32),
    bidirectional: bool = true,
};

/// Material properties for physical objects
pub const PhysicsMaterial = struct {
    density: f32 = 1.0,
    friction: f32 = 0.5,
    restitution: f32 = 0.5,
    name: []const u8 = "default",
};

/// Base physical object in the simulation
pub const PhysicalObject = struct {
    position: Vec3f,
    old_position: Vec3f,
    velocity: Vec3f,
    acceleration: Vec3f,
    angular_velocity: Vec3f,
    orientation: Quaternion,
    mass: f32,
    inverse_mass: f32,
    active: bool = true,
    pinned: bool = false,
    obj_type: ObjectType,
    friction: f32,
    restitution: f32,
    collision_radius: f32,
    material_id: u16 = 0,

    // Sleep management
    sleeping: bool = false,
    sleep_timer: u32 = 0,

    // Collision filtering
    collision_group: u32 = 1,
    collision_mask: u32 = 0xFFFFFFFF,

    /// Apply a force to this object
    pub fn applyForce(self: *PhysicalObject, force: Vec3f, dt: f32) void {
        if (self.pinned or !self.active) return;

        self.acceleration[0] += force[0] * self.inverse_mass;
        self.acceleration[1] += force[1] * self.inverse_mass;
        self.acceleration[2] += force[2] * self.inverse_mass;
    }

    /// Apply an instantaneous impulse to this object
    pub fn applyImpulse(self: *PhysicalObject, impulse: Vec3f) void {
        if (self.pinned or !self.active) return;

        self.velocity[0] += impulse[0] * self.inverse_mass;
        self.velocity[1] += impulse[1] * self.inverse_mass;
        self.velocity[2] += impulse[2] * self.inverse_mass;
        self.wake();
    }

    /// Apply a torque to rotate this object
    pub fn applyTorque(self: *PhysicalObject, torque: Vec3f, dt: f32) void {
        if (self.pinned or !self.active or
            self.obj_type != .RigidBody) return;

        // Simple approximation for angular acceleration based on torque
        // For more accurate rigid body physics, use the RigidBody module
        const torque_factor = 0.1;
        self.angular_velocity[0] += torque[0] * torque_factor * dt;
        self.angular_velocity[1] += torque[1] * torque_factor * dt;
        self.angular_velocity[2] += torque[2] * torque_factor * dt;
        self.wake();
    }

    /// Wake up a sleeping object
    pub fn wake(self: *PhysicalObject) void {
        self.sleeping = false;
        self.sleep_timer = 0;
    }

    /// Put an object to sleep
    pub fn sleep(self: *PhysicalObject) void {
        self.sleeping = true;
        self.velocity = @splat(0);
        self.angular_velocity = @splat(0);
    }

    /// Initialize a new physical object with default values
    pub fn init(
        position: Vec3f,
        mass: f32,
        obj_type: ObjectType,
        radius: f32,
    ) PhysicalObject {
        return PhysicalObject{
            .position = position,
            .old_position = position,
            .velocity = Vec3f{ 0, 0, 0, 0 },
            .acceleration = Vec3f{ 0, 0, 0, 0 },
            .angular_velocity = Vec3f{ 0, 0, 0, 0 },
            .orientation = Quaternion.identity(),
            .mass = mass,
            .inverse_mass = if (mass > PhysicsConstants.SAFE_DIVISOR) 1.0 / mass else 0.0,
            .active = true,
            .pinned = false,
            .obj_type = obj_type,
            .friction = 0.5,
            .restitution = 0.5,
            .collision_radius = radius,
            .sleeping = false,
            .sleep_timer = 0,
        };
    }

    /// Calculate the kinetic energy of this object
    pub fn kineticEnergy(self: *const PhysicalObject) f32 {
        if (self.sleeping or !self.active) return 0.0;

        // Linear kinetic energy: 0.5 * m * v^2
        const v_squared =
            self.velocity[0] * self.velocity[0] +
            self.velocity[1] * self.velocity[1] +
            self.velocity[2] * self.velocity[2];

        const linear_energy = 0.5 * self.mass * v_squared;

        // Angular kinetic energy (simplified approximation)
        const w_squared =
            self.angular_velocity[0] * self.angular_velocity[0] +
            self.angular_velocity[1] * self.angular_velocity[1] +
            self.angular_velocity[2] * self.angular_velocity[2];

        // Use a simple approximation for rotational inertia
        const rotational_energy = 0.4 * self.mass * self.collision_radius * self.collision_radius * w_squared;

        return linear_energy + rotational_energy;
    }

    /// Convert a point from local to world space
    pub fn localToWorldPoint(self: *const PhysicalObject, local_point: Vec3f) Vec3f {
        // Apply rotation first
        const rotated = self.orientation.rotateVector(local_point);

        // Then add position
        return Vec3f{
            self.position[0] + rotated[0],
            self.position[1] + rotated[1],
            self.position[2] + rotated[2],
            0.0,
        };
    }
};

/// Physics World that manages all physics simulation
pub const World = struct {
    allocator: Allocator,
    config: PhysicsConfig,
    objects: []PhysicalObject,
    constraints: []SpringConstraint,
    object_count: usize,
    constraint_count: usize,
    initialized: bool = false,
    spatial_hash: ?collision.CollisionSystem = null,
    accumulated_time: f32 = 0.0,

    // Enhanced modules
    constraint_manager: ?constraints.ConstraintManager = null,
    rigid_body_manager: ?rigid_body.RigidBodyManager = null,

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

        // Allocate memory for objects and constraints
        const objects = try allocator.alloc(PhysicalObject, config.max_objects);
        const constraints = try allocator.alloc(SpringConstraint, config.max_constraints);

        // Initialize spatial hash system for collision detection
        var spatial_hash = try collision.CollisionSystem.init(
            allocator,
            config.spatial_cell_size,
            config.world_size,
        );

        // Initialize constraint manager
        var constraint_manager = constraints.ConstraintManager.init(allocator);

        // Initialize rigid body manager
        var rb_manager = rigid_body.RigidBodyManager.init(allocator);

        return Self{
            .allocator = allocator,
            .config = optimized_config,
            .objects = objects,
            .constraints = constraints,
            .object_count = 0,
            .constraint_count = 0,
            .initialized = true,
            .spatial_hash = spatial_hash,
            .constraint_manager = constraint_manager,
            .rigid_body_manager = rb_manager,
            .collision_callbacks = std.ArrayList(fn (a: usize, b: usize) void).init(allocator),
        };
    }

    /// Free all resources
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.objects);
        self.allocator.free(self.constraints);

        if (self.spatial_hash) |*spatial| {
            spatial.deinit();
        }

        if (self.constraint_manager) |*cm| {
            cm.deinit();
        }

        if (self.rigid_body_manager) |*rbm| {
            rbm.deinit();
        }

        self.collision_callbacks.deinit();
    }

    /// Create a new physical object in the world
    pub fn createObject(
        self: *Self,
        position: Vec3f,
        mass: f32,
        obj_type: ObjectType,
        radius: f32,
    ) !usize {
        if (self.object_count >= self.config.max_objects) {
            return error.OutOfSpace;
        }

        const index = self.object_count;
        self.objects[index] = PhysicalObject.init(position, mass, obj_type, radius);
        self.object_count += 1;

        return index;
    }

    /// Register a collision callback function
    pub fn registerCollisionCallback(self: *Self, callback: fn (a: usize, b: usize) void) !void {
        try self.collision_callbacks.append(callback);
    }

    /// Create a new spring constraint between objects
    pub fn createConstraint(
        self: *Self,
        object_a: usize,
        object_b: usize,
        rest_length: ?f32,
        stiffness: f32,
        damping: f32,
    ) !usize {
        if (self.constraint_count >= self.config.max_constraints) {
            return error.OutOfSpace;
        }

        if (object_a >= self.object_count or object_b >= self.object_count) {
            return error.InvalidObjectIndex;
        }

        const a_pos = self.objects[object_a].position;
        const b_pos = self.objects[object_b].position;

        // Calculate distance between objects if rest_length is not provided
        const actual_rest_length = rest_length orelse blk: {
            const dx = b_pos[0] - a_pos[0];
            const dy = b_pos[1] - a_pos[1];
            const dz = b_pos[2] - a_pos[2];
            break :blk @sqrt(dx * dx + dy * dy + dz * dz);
        };

        const index = self.constraint_count;
        self.constraints[index] = SpringConstraint{
            .object_index_a = object_a,
            .object_index_b = object_b,
            .rest_length = actual_rest_length,
            .stiffness = stiffness,
            .damping = damping,
            .break_threshold = 0.0, // No breaking by default
        };

        self.constraint_count += 1;
        return index;
    }

    /// Create a cloth grid of particles connected by springs
    pub fn createClothGrid(
        self: *Self,
        top_left: Vec3f,
        width: f32,
        height: f32,
        rows: usize,
        columns: usize,
        particle_mass: f32,
        stiffness: f32,
        damping: f32,
    ) !void {
        const row_spacing = height / @intToFloat(f32, rows - 1);
        const col_spacing = width / @intToFloat(f32, columns - 1);

        // Maximum possible constraints needed:
        // - Horizontal: rows * (columns - 1)
        // - Vertical: columns * (rows - 1)
        // - Diagonal: 2 * (rows - 1) * (columns - 1)
        const max_new_constraints = rows * (columns - 1) + columns * (rows - 1) +
            2 * (rows - 1) * (columns - 1);

        if (self.object_count + (rows * columns) > self.config.max_objects or
            self.constraint_count + max_new_constraints > self.config.max_constraints)
        {
            return error.OutOfSpace;
        }

        var grid_points = try self.allocator.alloc(usize, rows * columns);
        defer self.allocator.free(grid_points);

        // Create particles
        for (0..rows) |i| {
            try self.createRow(i, columns, top_left, row_spacing, col_spacing, particle_mass, grid_points);
        }

        // Create structural springs (horizontal and vertical)
        for (0..rows) |i| {
            for (0..columns) |j| {
                const index = i * columns + j;
                const point_index = grid_points[index];

                // Connect to right neighbor (horizontal)
                if (j < columns - 1) {
                    const right_index = grid_points[i * columns + j + 1];
                    _ = try self.createConstraint(point_index, right_index, col_spacing, stiffness, damping);
                }

                // Connect to bottom neighbor (vertical)
                if (i < rows - 1) {
                    const bottom_index = grid_points[(i + 1) * columns + j];
                    _ = try self.createConstraint(point_index, bottom_index, row_spacing, stiffness, damping);
                }

                // Connect diagonal springs
                if (i < rows - 1 and j < columns - 1) {
                    // Diagonal to bottom-right
                    const bottom_right_index = grid_points[(i + 1) * columns + j + 1];
                    const diagonal_length = @sqrt(row_spacing * row_spacing + col_spacing * col_spacing);
                    _ = try self.createConstraint(point_index, bottom_right_index, diagonal_length, stiffness * 0.8, damping);

                    // Diagonal to bottom-left (if not in first column)
                    if (j > 0) {
                        const bottom_left_index = grid_points[(i + 1) * columns + j - 1];
                        _ = try self.createConstraint(point_index, bottom_left_index, diagonal_length, stiffness * 0.8, damping);
                    }
                }
            }
        }

        // Pin the top row
        for (0..columns) |j| {
            const top_index = grid_points[j];
            self.objects[top_index].pinned = true;
        }
    }

    fn createRow(
        self: *Self,
        row: usize,
        columns: usize,
        top_left: Vec3f,
        row_spacing: f32,
        col_spacing: f32,
        mass: f32,
        grid_points: []usize,
    ) !void {
        const y_offset = @intToFloat(f32, row) * row_spacing;

        for (0..columns) |j| {
            const x_offset = @intToFloat(f32, j) * col_spacing;
            const position = Vec3f{
                top_left[0] + x_offset,
                top_left[1] - y_offset,
                top_left[2],
                0.0,
            };

            const index = try self.createObject(
                position,
                mass,
                .ClothNode,
                0.1, // Small radius for cloth particles
            );

            grid_points[row * columns + j] = index;
        }
    }

    /// Solve all constraints
    fn solveConstraints(self: *Self, dt: f32) void {
        const start_time = std.time.nanoTimestamp();

        // Use the enhanced constraint system if available
        if (self.constraint_manager) |*cm| {
            cm.solveAll(self.objects, dt, self.config.constraint_iterations);
        } else {
            // Fall back to legacy spring constraints
            for (0..self.config.constraint_iterations) |_| {
                for (0..self.constraint_count) |i| {
                    const spring = &self.constraints[i];
                    if (!spring.active) continue;

                    const a_idx = spring.object_index_a;
                    const b_idx = spring.object_index_b;

                    var obj_a = &self.objects[a_idx];
                    var obj_b = &self.objects[b_idx];

                    // Skip if both objects are pinned
                    if (obj_a.pinned and obj_b.pinned) continue;

                    // Calculate vector between objects
                    const delta = Vec3f{
                        obj_b.position[0] - obj_a.position[0],
                        obj_b.position[1] - obj_a.position[1],
                        obj_b.position[2] - obj_a.position[2],
                        0.0,
                    };

                    // Calculate distance
                    const distance_sq =
                        delta[0] * delta[0] +
                        delta[1] * delta[1] +
                        delta[2] * delta[2];

                    const distance = @sqrt(distance_sq);

                    // Skip if distance is too small to avoid division by zero
                    if (distance < PhysicsConstants.SAFE_DIVISOR) continue;

                    // Calculate stretch
                    const stretch = distance - spring.rest_length;

                    // Skip if spring doesn't need to be bidirectional and is compressed
                    if (!spring.bidirectional and stretch < 0) continue;

                    // Check min/max length limits
                    if (distance < spring.min_length or distance > spring.max_length) continue;

                    // Check if spring should break
                    if (spring.break_threshold > 0 and @fabs(stretch) > spring.break_threshold) {
                        spring.active = false;
                        continue;
                    }

                    // Calculate force direction
                    const direction = Vec3f{
                        delta[0] / distance,
                        delta[1] / distance,
                        delta[2] / distance,
                        0.0,
                    };

                    // Calculate spring force (Hooke's law)
                    const spring_force = spring.stiffness * stretch;

                    // Add damping force based on relative velocity
                    const rel_velocity = Vec3f{
                        obj_b.velocity[0] - obj_a.velocity[0],
                        obj_b.velocity[1] - obj_a.velocity[1],
                        obj_b.velocity[2] - obj_a.velocity[2],
                        0.0,
                    };

                    const vel_projection =
                        rel_velocity[0] * direction[0] +
                        rel_velocity[1] * direction[1] +
                        rel_velocity[2] * direction[2];

                    const damping_force = spring.damping * vel_projection;

                    // Total force
                    const total_force = spring_force + damping_force;

                    // Apply force as impulse
                    const impulse_a = Vec3f{
                        direction[0] * total_force * dt,
                        direction[1] * total_force * dt,
                        direction[2] * total_force * dt,
                        0.0,
                    };

                    if (!obj_a.pinned) {
                        obj_a.velocity[0] += impulse_a[0] * obj_a.inverse_mass;
                        obj_a.velocity[1] += impulse_a[1] * obj_a.inverse_mass;
                        obj_a.velocity[2] += impulse_a[2] * obj_a.inverse_mass;
                    }

                    if (!obj_b.pinned) {
                        obj_b.velocity[0] -= impulse_a[0] * obj_b.inverse_mass;
                        obj_b.velocity[1] -= impulse_a[1] * obj_b.inverse_mass;
                        obj_b.velocity[2] -= impulse_a[2] * obj_b.inverse_mass;
                    }

                    // Wake up objects
                    obj_a.wake();
                    obj_b.wake();
                }
            }
        }

        self.perf_stats.constraint_time_ns = @intCast(u64, std.time.nanoTimestamp() - start_time);
    }

    /// Update the physics world with a given time step
    pub fn update(self: *Self, dt: f32) void {
        if (!self.initialized) return;

        const start_time = std.time.nanoTimestamp();

        // Accumulate time and perform fixed timestep updates
        self.accumulated_time += dt;

        const fixed_dt = self.config.timestep;
        while (self.accumulated_time >= fixed_dt) {
            self.fixedUpdate(fixed_dt);
            self.accumulated_time -= fixed_dt;
        }

        self.perf_stats.update_time_ns = @intCast(u64, std.time.nanoTimestamp() - start_time);
    }

    /// Perform a physics update with a fixed time step
    fn fixedUpdate(self: *Self, dt: f32) void {
        var active_objects: usize = 0;

        // Update rigid bodies
        if (self.rigid_body_manager) |*rbm| {
            rbm.integrateAll(self.objects, dt);
        }

        // Apply forces and integrate
        for (0..self.object_count) |i| {
            var obj = &self.objects[i];

            // Skip inactive objects
            if (!obj.active) continue;

            // Count active objects
            if (!obj.sleeping) active_objects += 1;

            // Skip sleeping objects
            if (obj.sleeping) continue;

            // Apply gravity
            if (!obj.pinned and obj.obj_type != .StaticBody) {
                obj.acceleration[0] += self.config.gravity[0];
                obj.acceleration[1] += self.config.gravity[1];
                obj.acceleration[2] += self.config.gravity[2];
            }

            // Store old position for verlet integration
            obj.old_position = obj.position;

            // Don't update rigid bodies here if using the rigid body manager
            if (self.rigid_body_manager == null or obj.obj_type != .RigidBody) {
                // Integrate velocity and position
                obj.velocity[0] += obj.acceleration[0] * dt;
                obj.velocity[1] += obj.acceleration[1] * dt;
                obj.velocity[2] += obj.acceleration[2] * dt;

                // Apply velocity limits
                const speed_sq = obj.velocity[0] * obj.velocity[0] +
                    obj.velocity[1] * obj.velocity[1] +
                    obj.velocity[2] * obj.velocity[2];

                if (speed_sq > PhysicsConstants.MAX_VELOCITY * PhysicsConstants.MAX_VELOCITY) {
                    const speed = @sqrt(speed_sq);
                    const scale = PhysicsConstants.MAX_VELOCITY / speed;
                    obj.velocity[0] *= scale;
                    obj.velocity[1] *= scale;
                    obj.velocity[2] *= scale;
                }

                // Update position
                obj.position[0] += obj.velocity[0] * dt;
                obj.position[1] += obj.velocity[1] * dt;
                obj.position[2] += obj.velocity[2] * dt;

                // Simple orientation update for non-rigid bodies
                if (obj.obj_type != .RigidBody and
                    (obj.angular_velocity[0] != 0 or
                        obj.angular_velocity[1] != 0 or
                        obj.angular_velocity[2] != 0))
                {
                    const rotation = Quaternion.fromAxisAngle(obj.angular_velocity[0], obj.angular_velocity[1], obj.angular_velocity[2], @sqrt(obj.angular_velocity[0] * obj.angular_velocity[0] +
                        obj.angular_velocity[1] * obj.angular_velocity[1] +
                        obj.angular_velocity[2] * obj.angular_velocity[2]) * dt);

                    obj.orientation = rotation.multiply(obj.orientation).normalize();
                }
            }

            // Reset acceleration for next step
            obj.acceleration = @splat(0);

            // Check sleeping conditions
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
        }

        // Update performance stats
        self.perf_stats.active_objects = active_objects;

        // Solve constraints
        self.solveConstraints(dt);

        // Handle collisions
        self.handleCollisions(dt);
    }

    /// Handle collisions between physics objects
    fn handleCollisions(self: *Self, dt: f32) void {
        const start_time = std.time.nanoTimestamp();

        // Use enhanced collision system if available
        if (self.spatial_hash) |*cs| {
            // Perform broadphase collision detection
            cs.broadphase(self.objects, self.object_count) catch return;

            // Perform narrowphase collision detection
            cs.narrowphase(self.objects) catch return;

            // Resolve collisions
            cs.resolveCollisions(self.objects, dt);

            // Trigger collision callbacks
            for (cs.collision_results.items) |collision| {
                for (self.collision_callbacks.items) |callback| {
                    callback(collision.object_a_idx, collision.object_b_idx);
                }
            }
        } else {
            // Simple O(n²) collision detection without spatial partitioning
            for (0..self.object_count) |i| {
                var obj_a = &self.objects[i];
                if (!obj_a.active or obj_a.obj_type == .Trigger) continue;

                for (i + 1..self.object_count) |j| {
                    var obj_b = &self.objects[j];
                    if (!obj_b.active) continue;

                    // Check collision masks
                    if ((obj_a.collision_group & obj_b.collision_mask) == 0 and
                        (obj_b.collision_group & obj_a.collision_mask) == 0) continue;

                    // Skip if both are static
                    if (obj_a.obj_type == .StaticBody and obj_b.obj_type == .StaticBody) continue;

                    // Calculate distance between objects
                    const delta = Vec3f{
                        obj_b.position[0] - obj_a.position[0],
                        obj_b.position[1] - obj_a.position[1],
                        obj_b.position[2] - obj_a.position[2],
                        0.0,
                    };

                    const distance_sq =
                        delta[0] * delta[0] +
                        delta[1] * delta[1] +
                        delta[2] * delta[2];

                    const min_distance = obj_a.collision_radius + obj_b.collision_radius;

                    // Check for collision
                    if (distance_sq < min_distance * min_distance) {
                        // Process as a trigger if either object is a trigger
                        if (obj_a.obj_type == .Trigger or obj_b.obj_type == .Trigger) {
                            for (self.collision_callbacks.items) |callback| {
                                callback(i, j);
                            }
                            continue;
                        }

                        // Calculate collision response
                        const distance = @sqrt(distance_sq);
                        const penetration = min_distance - distance;

                        // Calculate normalized direction
                        var normal = if (distance > PhysicsConstants.SAFE_DIVISOR)
                            Vec3f{
                                delta[0] / distance,
                                delta[1] / distance,
                                delta[2] / distance,
                                0.0,
                            }
                        else
                            Vec3f{ 0.0, 1.0, 0.0, 0.0 };

                        // Calculate relative velocity
                        const rel_vel = Vec3f{
                            obj_b.velocity[0] - obj_a.velocity[0],
                            obj_b.velocity[1] - obj_a.velocity[1],
                            obj_b.velocity[2] - obj_a.velocity[2],
                            0.0,
                        };

                        // Calculate velocity along normal
                        const vel_along_normal =
                            rel_vel[0] * normal[0] +
                            rel_vel[1] * normal[1] +
                            rel_vel[2] * normal[2];

                        // Skip if objects are separating
                        if (vel_along_normal > 0) continue;

                        // Calculate restitution (coefficient of restitution)
                        const restitution = @min(obj_a.restitution, obj_b.restitution);

                        // Calculate impulse scalar
                        var impulse_scalar = -(1.0 + restitution) * vel_along_normal;
                        impulse_scalar /= (obj_a.inverse_mass + obj_b.inverse_mass);

                        // Apply impulse
                        const impulse = Vec3f{
                            normal[0] * impulse_scalar,
                            normal[1] * impulse_scalar,
                            normal[2] * impulse_scalar,
                            0.0,
                        };

                        if (!obj_a.pinned and obj_a.obj_type != .StaticBody) {
                            obj_a.velocity[0] -= impulse[0] * obj_a.inverse_mass;
                            obj_a.velocity[1] -= impulse[1] * obj_a.inverse_mass;
                            obj_a.velocity[2] -= impulse[2] * obj_a.inverse_mass;
                        }

                        if (!obj_b.pinned and obj_b.obj_type != .StaticBody) {
                            obj_b.velocity[0] += impulse[0] * obj_b.inverse_mass;
                            obj_b.velocity[1] += impulse[1] * obj_b.inverse_mass;
                            obj_b.velocity[2] += impulse[2] * obj_b.inverse_mass;
                        }

                        // Positional correction to prevent sinking
                        const correction = @max(penetration - self.config.collision_margin, 0.0) * 0.2;
                        const correction_scale = correction / (obj_a.inverse_mass + obj_b.inverse_mass);

                        if (!obj_a.pinned and obj_a.obj_type != .StaticBody) {
                            obj_a.position[0] -= normal[0] * correction_scale * obj_a.inverse_mass;
                            obj_a.position[1] -= normal[1] * correction_scale * obj_a.inverse_mass;
                            obj_a.position[2] -= normal[2] * correction_scale * obj_a.inverse_mass;
                        }

                        if (!obj_b.pinned and obj_b.obj_type != .StaticBody) {
                            obj_b.position[0] += normal[0] * correction_scale * obj_b.inverse_mass;
                            obj_b.position[1] += normal[1] * correction_scale * obj_b.inverse_mass;
                            obj_b.position[2] += normal[2] * correction_scale * obj_b.inverse_mass;
                        }

                        // Wake both objects
                        obj_a.wake();
                        obj_b.wake();

                        // Invoke collision callbacks
                        for (self.collision_callbacks.items) |callback| {
                            callback(i, j);
                        }
                    }
                }
            }
        }

        self.perf_stats.collision_time_ns = @intCast(u64, std.time.nanoTimestamp() - start_time);
    }

    /// Create a rigid body box
    pub fn createRigidBodyBox(self: *Self, position: Vec3f, size: Vec3f, mass: f32) !usize {
        const obj_idx = try self.createObject(position, mass, .RigidBody, @sqrt(size[0] * size[0] + size[1] * size[1] + size[2] * size[2]) * 0.5);

        if (self.rigid_body_manager) |*rbm| {
            const inertia = rigid_body.InertiaPresets.box(mass, size[0], size[1], size[2]);
            _ = try rbm.createRigidBody(obj_idx, inertia);
        }

        return obj_idx;
    }

    /// Create a rigid body sphere
    pub fn createRigidBodySphere(self: *Self, position: Vec3f, radius: f32, mass: f32) !usize {
        const obj_idx = try self.createObject(position, mass, .RigidBody, radius);

        if (self.rigid_body_manager) |*rbm| {
            const inertia = rigid_body.InertiaPresets.sphere(mass, radius);
            _ = try rbm.createRigidBody(obj_idx, inertia);
        }

        return obj_idx;
    }

    /// Create a static plane
    pub fn createStaticPlane(self: *Self, position: Vec3f, normal: Vec3f, size: f32) !usize {
        const obj_idx = try self.createObject(position, 0.0, .StaticBody, size);

        // Set up the static plane
        var obj = &self.objects[obj_idx];
        obj.pinned = true;

        // Calculate orientation to align with normal
        obj.orientation = Quaternion.fromToRotation(Vec3f{ 0, 1, 0, 0 }, normal);

        return obj_idx;
    }

    /// Create a soft body with particles connected by springs
    pub fn createSoftBody(
        self: *Self,
        center: Vec3f,
        radius: f32,
        resolution: u32,
        total_mass: f32,
        stiffness: f32,
    ) ![]usize {
        // Icosphere generation parameters
        const base_vertices = 12; // Icosahedron vertices
        const base_faces = 20; // Icosahedron faces

        // Calculate vertices based on resolution
        const num_subdivisions = resolution;
        const vertices_per_face = (num_subdivisions + 1) * (num_subdivisions + 2) / 2;
        const total_vertices = base_vertices + base_faces * (vertices_per_face - 3);

        // Check if there's enough space
        if (self.object_count + total_vertices > self.config.max_objects) {
            return error.OutOfSpace;
        }

        var vertices = try self.allocator.alloc(usize, total_vertices);
        errdefer self.allocator.free(vertices);

        // Particle mass
        const particle_mass = total_mass / @intToFloat(f32, total_vertices);

        // Generate icosphere points
        // We use a simplified version with just basic vertices for this example
        const golden_ratio = 1.618;
        const positions = [_]Vec3f{
            // Top and bottom vertices
            Vec3f{ 0, 1, 0, 0 },
            Vec3f{ 0, -1, 0, 0 },

            // Middle ring vertices
            Vec3f{ 1, golden_ratio, 0, 0 },
            Vec3f{ -1, golden_ratio, 0, 0 },
            Vec3f{ 1, -golden_ratio, 0, 0 },
            Vec3f{ -1, -golden_ratio, 0, 0 },

            // Other ring vertices
            Vec3f{ golden_ratio, 0, 1, 0 },
            Vec3f{ -golden_ratio, 0, 1, 0 },
            Vec3f{ golden_ratio, 0, -1, 0 },
            Vec3f{ -golden_ratio, 0, -1, 0 },
            Vec3f{ 0, 1, golden_ratio, 0 },
            Vec3f{ 0, -1, golden_ratio, 0 },
        };

        // Create vertices
        for (positions, 0..) |pos, i| {
            // Normalize and scale by radius
            const length = @sqrt(pos[0] * pos[0] + pos[1] * pos[1] + pos[2] * pos[2]);
            const scale = radius / length;

            const scaled_pos = Vec3f{
                center[0] + pos[0] * scale,
                center[1] + pos[1] * scale,
                center[2] + pos[2] * scale,
                0.0,
            };

            vertices[i] = try self.createObject(
                scaled_pos,
                particle_mass,
                .SoftBody,
                radius / 10.0, // Small radius for each particle
            );
        }

        // Create springs between adjacent vertices
        for (0..positions.len) |i| {
            for (i + 1..positions.len) |j| {
                // Create springs between close enough vertices
                const pos_i = positions[i];
                const pos_j = positions[j];

                const distance_sq =
                    (pos_i[0] - pos_j[0]) * (pos_i[0] - pos_j[0]) +
                    (pos_i[1] - pos_j[1]) * (pos_i[1] - pos_j[1]) +
                    (pos_i[2] - pos_j[2]) * (pos_i[2] - pos_j[2]);

                // Threshold for connecting vertices
                if (distance_sq < 4.0) {
                    _ = try self.createConstraint(vertices[i], vertices[j], null, // Calculate rest length automatically
                        stiffness, 0.1 // Damping
                    );
                }
            }
        }

        return vertices;
    }

    /// Calculate the total energy in the system
    pub fn getTotalEnergy(self: *const Self) f32 {
        var total_energy: f32 = 0.0;

        for (0..self.object_count) |i| {
            total_energy += self.objects[i].kineticEnergy();
        }

        return total_energy;
    }

    /// Get current performance statistics
    pub fn getPerformanceStats(self: *const Self) @TypeOf(self.perf_stats) {
        return self.perf_stats;
    }
};
