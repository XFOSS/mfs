const std = @import("std");
const Allocator = std.mem.Allocator;
const math = @import("../math/vector.zig");
const platform = @import("../platform/platform.zig");
const Vector = math.Vector;
const Quaternion = math.Quaternion;
const Vec4 = math.Vec4;
const SIMD = platform.SIMD;
const constraints = @import("constraints.zig");
const spatial_partition = @import("spatial_partition.zig");
const SpatialGrid = spatial_partition.SpatialGrid;
const AABB = spatial_partition.AABB;
const shapes = @import("shapes.zig");
const Shape = shapes.Shape;
const collision_resolver = @import("collision_resolver.zig");
const CollisionResolver = collision_resolver.CollisionResolver;
const continuous_collision = @import("continuous_collision.zig");
const ContinuousCollision = continuous_collision.ContinuousCollision;
const joints = @import("joints.zig");
const JointManager = joints.JointManager;
const triggers = @import("triggers.zig");
const TriggerManager = triggers.TriggerManager;

/// Optimized SIMD vector type for 3D physics operations
pub const Vec3f = @Vector(4, f32);

/// Core physics system constants
pub const PhysicsConstants = struct {
    pub const EPSILON: f32 = 0.000001;
    pub const FLOOR_HEIGHT: f32 = -5.0;
    pub const SAFE_DIVISOR: f32 = 0.0001;
    pub const MAX_VELOCITY: f32 = 100.0;
    pub const EARTH_GRAVITY: f32 = 9.81;
};

/// Enhanced configuration for physics simulation
pub const PhysicsConfig = struct {
    /// GPU acceleration when available
    use_gpu_acceleration: bool = false,

    /// Gravity vector (default Earth gravity)
    gravity: Vec4 = Vec4{ 0.0, -PhysicsConstants.EARTH_GRAVITY, 0.0, 0.0 },

    /// Capacity limits
    max_objects: u32 = 10000,
    max_constraints: u32 = 50000,

    /// Simulation parameters
    cloth_damping: f32 = 0.98,
    constraint_iterations: u32 = 8,
    collision_iterations: u32 = 3,
    timestep: f32 = 1.0 / 60.0,
    collision_margin: f32 = 0.01,

    /// Spatial partitioning
    spatial_cell_size: f32 = 1.0,
    world_size: f32 = 100.0,

    /// Sleep optimization
    enable_sleeping: bool = true,
    sleep_threshold: f32 = 0.01,
    sleep_frames: u32 = 60,

    /// Continuous collision detection
    use_continuous_collision: bool = true,
    ccd_threshold_velocity: f32 = 20.0,
};

/// Physical object types
pub const ObjectType = enum(u8) {
    Particle, // Simple point mass
    ClothNode, // Node in cloth simulation
    RigidBody, // Solid body with rotational inertia
    SoftBody, // Deformable body
    Trigger, // Non-physical collision volume
    StaticBody, // Immovable body
};

/// Material properties
pub const PhysicsMaterial = struct {
    density: f32 = 1.0,
    friction: f32 = 0.5,
    restitution: f32 = 0.5,
    name: []const u8 = "default",
};

/// Enhanced physical object with improved features
pub const PhysicalObject = struct {
    position: Vec4 align(16),
    old_position: Vec4 align(16),
    velocity: Vec4 align(16),
    acceleration: Vec4 align(16),
    angular_velocity: Vec4 align(16),
    orientation: Quaternion align(16),

    mass: f32,
    inverse_mass: f32,
    active: bool = true,
    pinned: bool = false,
    obj_type: ObjectType,

    // Material properties
    friction: f32 = 0.3,
    restitution: f32 = 0.5,
    collision_radius: f32 = 1.0,
    material_id: u16 = 0,

    // Shape properties
    shape: ?Shape = null,

    // Sleep management
    sleeping: bool = false,
    sleep_timer: u32 = 0,

    // Collision filtering
    collision_group: u32 = 1,
    collision_mask: u32 = 0xFFFFFFFF,

    /// Apply force with improved wake handling
    pub fn applyForce(self: *PhysicalObject, force: Vec4) void {
        if (self.pinned or !self.active) return;
        self.acceleration += force * Vector.splat(self.inverse_mass);
        self.wake();
    }

    /// Apply impulse with collision response
    pub fn applyImpulse(self: *PhysicalObject, impulse: Vec4) void {
        if (self.pinned or !self.active) return;
        self.velocity += impulse * Vector.splat(self.inverse_mass);
        self.wake();
    }

    /// Apply torque with improved rigid body handling
    pub fn applyTorque(self: *PhysicalObject, torque: Vec4) void {
        if (self.pinned or !self.active or self.obj_type != .RigidBody) return;

        // Simple approximation for angular acceleration
        self.angular_velocity += torque * Vector.splat(0.1 * self.inverse_mass);
        self.wake();
    }

    /// Wake object from sleep state
    pub fn wake(self: *PhysicalObject) void {
        self.sleeping = false;
        self.sleep_timer = 0;
    }

    /// Put object to sleep
    pub fn sleep(self: *PhysicalObject) void {
        self.sleeping = true;
        self.velocity = Vector.splat(0);
        self.angular_velocity = Vector.splat(0);
    }

    /// Calculate object's kinetic energy
    pub fn kineticEnergy(self: PhysicalObject) f32 {
        if (self.sleeping or self.pinned) return 0;

        const vel_sq = Vector.dot3(self.velocity, self.velocity);
        const angular_vel_sq = Vector.dot3(self.angular_velocity, self.angular_velocity);

        // Simple approximation of rotational energy
        const rotational_factor = if (self.obj_type == .RigidBody) 0.4 else 0.0;
        return 0.5 * self.mass * (vel_sq + rotational_factor * angular_vel_sq);
    }

    /// Get bounding box for this object
    pub fn getBoundingBox(self: PhysicalObject) AABB {
        if (self.shape) |shape| {
            return shape.getBoundingBox(self.position, self.orientation);
        } else {
            return AABB.fromSphere(self.position, self.collision_radius);
        }
    }
};

/// Callback type for collision events
pub const CollisionCallback = fn (world: *World, a: usize, b: usize) void;

/// Main physics world with improved features
pub const World = struct {
    allocator: Allocator,
    config: PhysicsConfig,
    objects: std.ArrayList(PhysicalObject),
    constraints: std.ArrayList(constraints.Constraint),
    spatial_grid: ?SpatialGrid,
    joint_manager: JointManager,
    trigger_manager: TriggerManager,
    accumulated_time: f32 = 0.0,

    /// Event callback for collisions
    collision_callback: ?CollisionCallback = null,

    /// Initialize physics world
    pub fn init(allocator: Allocator, config: PhysicsConfig) !World {
        var world = World{
            .allocator = allocator,
            .config = config,
            .objects = std.ArrayList(PhysicalObject).init(allocator),
            .constraints = std.ArrayList(constraints.Constraint).init(allocator),
            .spatial_grid = null,
            .joint_manager = JointManager.init(allocator),
            .trigger_manager = TriggerManager.init(allocator),
        };

        // Initialize spatial partitioning if enabled
        if (config.spatial_cell_size > 0) {
            world.spatial_grid = try SpatialGrid.init(allocator, config.world_size, config.spatial_cell_size);
        }

        return world;
    }

    /// Clean up resources
    pub fn deinit(self: *World) void {
        self.objects.deinit();
        self.constraints.deinit();
        if (self.spatial_grid) |*grid| {
            grid.deinit();
        }
        self.joint_manager.deinit();
        self.trigger_manager.deinit();
    }

    /// Add object to world
    pub fn addObject(self: *World, object: PhysicalObject) !usize {
        const index = self.objects.items.len;
        try self.objects.append(object);
        return index;
    }

    /// Create sphere object
    pub fn createSphere(
        self: *World,
        position: Vec4,
        radius: f32,
        mass: f32,
        material: PhysicsMaterial,
    ) !usize {
        const obj = PhysicalObject{
            .position = position,
            .old_position = position,
            .velocity = Vector.splat(0),
            .acceleration = Vector.splat(0),
            .angular_velocity = Vector.splat(0),
            .orientation = Quaternion.identity(),
            .mass = mass,
            .inverse_mass = if (mass > 0) 1.0 / mass else 0.0,
            .obj_type = if (mass <= 0) .StaticBody else .RigidBody,
            .friction = material.friction,
            .restitution = material.restitution,
            .collision_radius = radius,
            .shape = Shape{ .Sphere = shapes.SphereShape.init(radius) },
        };

        return self.addObject(obj);
    }

    /// Create box object
    pub fn createBox(
        self: *World,
        position: Vec4,
        size: Vec4,
        mass: f32,
        material: PhysicsMaterial,
    ) !usize {
        const obj = PhysicalObject{
            .position = position,
            .old_position = position,
            .velocity = Vector.splat(0),
            .acceleration = Vector.splat(0),
            .angular_velocity = Vector.splat(0),
            .orientation = Quaternion.identity(),
            .mass = mass,
            .inverse_mass = if (mass > 0) 1.0 / mass else 0.0,
            .obj_type = if (mass <= 0) .StaticBody else .RigidBody,
            .friction = material.friction,
            .restitution = material.restitution,
            .collision_radius = @max(size[0], @max(size[1], size[2])) * 0.5,
            .shape = Shape{ .Box = shapes.BoxShape.init(size[0], size[1], size[2]) },
        };

        return self.addObject(obj);
    }

    /// Create capsule object
    pub fn createCapsule(
        self: *World,
        position: Vec4,
        radius: f32,
        height: f32,
        mass: f32,
        material: PhysicsMaterial,
    ) !usize {
        const obj = PhysicalObject{
            .position = position,
            .old_position = position,
            .velocity = Vector.splat(0),
            .acceleration = Vector.splat(0),
            .angular_velocity = Vector.splat(0),
            .orientation = Quaternion.identity(),
            .mass = mass,
            .inverse_mass = if (mass > 0) 1.0 / mass else 0.0,
            .obj_type = if (mass <= 0) .StaticBody else .RigidBody,
            .friction = material.friction,
            .restitution = material.restitution,
            .collision_radius = radius + height * 0.5,
            .shape = Shape{ .Capsule = shapes.CapsuleShape.init(radius, height) },
        };

        return self.addObject(obj);
    }

    /// Remove object from world
    pub fn removeObject(self: *World, index: usize) void {
        if (index >= self.objects.items.len) return;

        // Remove constraints that reference this object
        var i: usize = 0;
        while (i < self.constraints.items.len) {
            const constraint = self.constraints.items[i];
            var should_remove = false;

            switch (constraint) {
                .Spring => |spring| {
                    should_remove = spring.object_index_a == index or spring.object_index_b == index;
                },
                .Distance => |distance| {
                    should_remove = distance.object_index_a == index or distance.object_index_b == index;
                },
                .Position => |position| {
                    should_remove = position.object_index == index;
                },
                .Angle => |angle| {
                    should_remove = angle.object_index_a == index or angle.object_index_b == index;
                },
            }

            if (should_remove) {
                _ = self.constraints.swapRemove(i);
            } else {
                i += 1;
            }
        }

        // Remove object
        _ = self.objects.swapRemove(index);
    }

    /// Add a spring constraint between two objects
    pub fn addSpringConstraint(
        self: *World,
        object_a: usize,
        object_b: usize,
        rest_length: f32,
        stiffness: f32,
        damping: f32,
    ) !void {
        const spring = try self.allocator.create(constraints.SpringConstraint);
        spring.* = constraints.SpringConstraint{
            .object_index_a = object_a,
            .object_index_b = object_b,
            .rest_length = rest_length,
            .stiffness = stiffness,
            .damping = damping,
            .break_threshold = 0.0,
        };

        try self.constraints.append(constraints.Constraint{ .Spring = spring });
    }

    /// Add a distance constraint between two objects
    pub fn addDistanceConstraint(
        self: *World,
        object_a: usize,
        object_b: usize,
        distance: f32,
    ) !void {
        const constraint = try self.allocator.create(constraints.DistanceConstraint);
        constraint.* = constraints.DistanceConstraint{
            .object_index_a = object_a,
            .object_index_b = object_b,
            .distance = distance,
            .compliance = 0.0,
        };

        try self.constraints.append(constraints.Constraint{ .Distance = constraint });
    }

    /// Add a fixed joint between two objects
    pub fn addFixedJoint(
        self: *World,
        object_a: usize,
        object_b: usize,
    ) !void {
        const joint = try self.allocator.create(joints.Joint);
        joint.* = joints.Joint{
            .Fixed = joints.FixedJoint.initRelative(self.objects.items, object_a, object_b),
        };

        try self.joint_manager.addJoint(joint);
    }

    /// Add a hinge joint between two objects
    pub fn addHingeJoint(
        self: *World,
        object_a: usize,
        object_b: usize,
        anchor_a: Vec4,
        anchor_b: Vec4,
        axis: Vec4,
    ) !void {
        const joint = try self.allocator.create(joints.Joint);
        joint.* = joints.Joint{
            .Hinge = joints.HingeJoint.init(object_a, object_b, anchor_a, anchor_b, axis, axis),
        };

        try self.joint_manager.addJoint(joint);
    }

    /// Create a trigger volume
    pub fn createTrigger(
        self: *World,
        shape: Shape,
        position: Vec4,
        callback: ?triggers.TriggerCallback,
    ) !usize {
        return self.trigger_manager.createTrigger(shape, position, callback);
    }

    /// Update physics simulation with fixed timestep
    pub fn update(self: *World, dt: f32) !void {
        self.accumulated_time += dt;

        // Fixed timestep for stability
        while (self.accumulated_time >= self.config.timestep) {
            try self.step(self.config.timestep);
            self.accumulated_time -= self.config.timestep;
        }
    }

    /// Step physics simulation forward
    fn step(self: *World, dt: f32) !void {
        // Update spatial partitioning
        if (self.spatial_grid) |*grid| {
            grid.clear();
            for (self.objects.items, 0..) |obj, i| {
                if (!obj.sleeping) {
                    grid.insertObject(i, obj.position, obj.collision_radius) catch {};
                }
            }
        }

        // Integrate forces
        for (self.objects.items, 0..) |*obj, obj_idx| {
            if (obj.sleeping or obj.pinned or obj.obj_type == .StaticBody) continue;

            // Apply gravity
            const gravity_force = self.config.gravity * Vector.splat(obj.mass);
            obj.applyForce(gravity_force);

            // Semi-implicit Euler integration
            obj.velocity += obj.acceleration * Vector.splat(dt);

            // Apply damping
            obj.velocity *= Vector.splat(self.config.cloth_damping);

            // Clamp velocity to max allowed
            const speed_sq = Vector.dot3(obj.velocity, obj.velocity);
            if (speed_sq > PhysicsConstants.MAX_VELOCITY * PhysicsConstants.MAX_VELOCITY) {
                const speed = @sqrt(speed_sq);
                obj.velocity *= Vector.splat(PhysicsConstants.MAX_VELOCITY / speed);
            }

            // Update position with continuous collision detection if needed
            if (self.config.use_continuous_collision and
                speed_sq > self.config.ccd_threshold_velocity * self.config.ccd_threshold_velocity)
            {
                ContinuousCollision.updateWithCCD(obj, dt, self.objects.items, obj_idx);
            } else {
                // Regular position update
                obj.position += obj.velocity * Vector.splat(dt);
            }

            // Update rigid body orientation
            if (obj.obj_type == .RigidBody) {
                const half_omega = obj.angular_velocity * Vector.splat(0.5 * dt);
                const angle = Vector.length3(half_omega);
                if (angle > PhysicsConstants.EPSILON) {
                    const axis = Vector.normalize3(half_omega);
                    const q_delta = Quaternion.fromAxisAngle(&[_]f32{ axis[0], axis[1], axis[2] }, angle);
                    obj.orientation = Quaternion.multiply(obj.orientation, q_delta);
                    obj.orientation = Quaternion.normalize(obj.orientation);
                }
            }

            // Handle sleeping
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
            obj.acceleration = Vector.splat(0);
        }

        // Solve constraints
        var iter: u32 = 0;
        while (iter < self.config.constraint_iterations) : (iter += 1) {
            for (self.constraints.items) |constraint| {
                if (constraint.isActive()) {
                    constraint.apply(self.objects.items, dt);
                }
            }

            // Solve joints
            self.joint_manager.solveAll(self.objects.items, dt);
        }

        // Handle collisions
        try self.resolveCollisions(dt);

        // Update triggers
        try self.trigger_manager.update(self.objects.items, dt);
    }

    /// Resolve collisions between objects
    fn resolveCollisions(self: *World, _dt: f32) !void {
        var iter: u32 = 0;
        while (iter < self.config.collision_iterations) : (iter += 1) {
            if (self.spatial_grid) |*grid| {
                // Use spatial partitioning for collision detection
                try grid.findCollisionPairs();
                grid.processCollisions(self.objects.items);
            } else {
                // Fallback to O(n²) collision detection
                var i: usize = 0;
                while (i < self.objects.items.len) : (i += 1) {
                    var j: usize = i + 1;
                    while (j < self.objects.items.len) : (j += 1) {
                        const obj_a = &self.objects.items[i];
                        const obj_b = &self.objects.items[j];

                        // Skip if objects can't collide
                        if ((obj_a.collision_group & obj_b.collision_mask) == 0 or
                            (obj_b.collision_group & obj_a.collision_mask) == 0)
                        {
                            continue;
                        }

                        // Check for collision and resolve if found
                        if (CollisionResolver.detectCollision(obj_a, obj_b)) |collision| {
                            CollisionResolver.resolveCollision(collision);

                            // Call collision callback if provided
                            if (self.collision_callback) |callback| {
                                callback(self, i, j);
                            }
                        }
                    }
                }
            }
        }
    }
};

/// Spatial partitioning for efficient collision detection
const SpatialHash = struct {
    // Implementation details to be added
};
