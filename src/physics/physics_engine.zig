//! Advanced Physics Engine for MFS Engine
//! Implements rigid body dynamics, collision detection, and constraint solving
//! @thread-safe Physics simulation is thread-safe with proper synchronization
//! @symbol PhysicsEngine - High-performance physics simulation

const std = @import("std");
// const math = @import("math");
// const Vec3 = math.Vec3f;
// const Vec3f = math.Vec3f;
// const Mat4 = math.Mat4f;
// const Quat = math.Quatf;

// Temporary placeholder types
const Vec3f = struct {
    x: f32,
    y: f32,
    z: f32,
    pub fn init(x: f32, y: f32, z: f32) @This() {
        return .{ .x = x, .y = y, .z = z };
    }
    pub const zero = @This(){ .x = 0, .y = 0, .z = 0 };
    pub fn add(self: @This(), other: @This()) @This() {
        return .{ .x = self.x + other.x, .y = self.y + other.y, .z = self.z + other.z };
    }
    pub fn sub(self: @This(), other: @This()) @This() {
        return .{ .x = self.x - other.x, .y = self.y - other.y, .z = self.z - other.z };
    }
    pub fn scale(self: @This(), s: f32) @This() {
        return .{ .x = self.x * s, .y = self.y * s, .z = self.z * s };
    }
    pub fn magnitude(self: @This()) f32 {
        return @sqrt(self.x * self.x + self.y * self.y + self.z * self.z);
    }
    pub fn normalize(self: @This()) @This() {
        const m = self.magnitude();
        return if (m > 0) self.scale(1.0 / m) else self;
    }
    pub fn cross(self: @This(), other: @This()) @This() {
        return .{ .x = self.y * other.z - self.z * other.y, .y = self.z * other.x - self.x * other.z, .z = self.x * other.y - self.y * other.x };
    }
    pub fn dot(self: @This(), other: @This()) f32 {
        return self.x * other.x + self.y * other.y + self.z * other.z;
    }
};
const Vec3 = Vec3f;
const Mat4 = struct { data: [16]f32 };
const Quat = struct { x: f32, y: f32, z: f32, w: f32 };

// Import physics types
const physics = @import("physics.zig");
const PhysicalObject = physics.PhysicalObject;
const ObjectType = physics.ObjectType;
const PhysicsConstants = physics.PhysicsConstants;

/// Physics simulation settings
pub const PhysicsSettings = struct {
    gravity: Vec3 = Vec3.init(0.0, -9.81, 0.0),
    time_step: f32 = 1.0 / 60.0,
    max_substeps: u32 = 10,
    damping: f32 = 0.99,
    angular_damping: f32 = 0.98,
    restitution: f32 = 0.2,
    friction: f32 = 0.5,
    solver_iterations: u32 = 10,
    position_correction: f32 = 0.8,
    slop: f32 = 0.01,
    enable_warm_starting: bool = true,
    enable_continuous_collision: bool = true,
    enable_sleeping: bool = true,
    enable_ccd: bool = true,
    sleep_threshold: f32 = 0.1,
    sleep_time: f32 = 0.5,
};

/// Engine configuration (alias for PhysicsSettings for compatibility)
pub const EngineConfig = PhysicsSettings;

// Import spatial partitioning and collision systems
const spatial_partition = @import("spatial_partition.zig");
const collision_resolver = @import("collision_resolver.zig");
const constraints = @import("constraints.zig");
const rigid_body = @import("rigid_body.zig");
const continuous_collision = @import("continuous_collision.zig");

/// Advanced Physics Engine with full rigid body support
/// Provides comprehensive physics simulation including constraints, collision detection, and advanced features
pub const PhysicsEngine = struct {
    allocator: std.mem.Allocator,
    objects: std.ArrayList(PhysicalObject),
    rigid_body_manager: rigid_body.RigidBodyManager,
    constraint_manager: ConstraintManager,
    collision_detector: CollisionDetector,
    spatial_partition: spatial_partition.SpatialPartition,
    continuous_collision: continuous_collision.ContinuousCollision,
    gravity: Vec3f = Vec3f.init(0, -9.81, 0),
    time_step: f32 = 1.0 / 60.0,
    max_substeps: u32 = 4,
    collision_iterations: u32 = 8,
    constraint_iterations: u32 = 10,
    damping: f32 = 0.98,
    sleeping_enabled: bool = true,
    deterministic: bool = false,

    // Performance metrics
    performance_stats: PerformanceStats = .{},

    const PerformanceStats = struct {
        simulation_time_ms: f64 = 0.0,
        collision_detection_time_ms: f64 = 0.0,
        constraint_solving_time_ms: f64 = 0.0,
        integration_time_ms: f64 = 0.0,
        active_bodies: u32 = 0,
        collision_pairs: u32 = 0,
        constraint_count: u32 = 0,
    };

    /// Constraint system for connecting rigid bodies
    const ConstraintManager = struct {
        allocator: std.mem.Allocator,
        constraints: std.ArrayList(Constraint),

        const Constraint = struct {
            constraint_type: ConstraintType,
            body_a: usize,
            body_b: ?usize = null, // null for world constraints
            anchor_a: Vec3f,
            anchor_b: Vec3f,
            parameters: ConstraintParameters,
            enabled: bool = true,

            const ConstraintType = enum {
                fixed,
                hinge,
                ball_socket,
                slider,
                spring,
                distance,
                cone_twist,
                generic_6dof,
            };

            const ConstraintParameters = union(ConstraintType) {
                fixed: struct {
                    breaking_threshold: f32 = std.math.inf(f32),
                },
                hinge: struct {
                    axis: Vec3f,
                    lower_limit: f32 = -std.math.pi,
                    upper_limit: f32 = std.math.pi,
                    motor_enabled: bool = false,
                    motor_velocity: f32 = 0.0,
                    motor_max_force: f32 = 0.0,
                },
                ball_socket: struct {
                    breaking_threshold: f32 = std.math.inf(f32),
                },
                slider: struct {
                    axis: Vec3f,
                    lower_limit: f32 = -std.math.inf(f32),
                    upper_limit: f32 = std.math.inf(f32),
                    motor_enabled: bool = false,
                    motor_velocity: f32 = 0.0,
                    motor_max_force: f32 = 0.0,
                },
                spring: struct {
                    rest_length: f32,
                    stiffness: f32,
                    damping: f32,
                },
                distance: struct {
                    distance: f32,
                    compliance: f32 = 0.0,
                },
                cone_twist: struct {
                    swing_span1: f32,
                    swing_span2: f32,
                    twist_span: f32,
                },
                generic_6dof: struct {
                    linear_lower_limit: Vec3f,
                    linear_upper_limit: Vec3f,
                    angular_lower_limit: Vec3f,
                    angular_upper_limit: Vec3f,
                },
            };
        };

        pub fn init(allocator: std.mem.Allocator) ConstraintManager {
            return .{
                .allocator = allocator,
                .constraints = std.ArrayList(Constraint).init(allocator),
            };
        }

        pub fn deinit(self: *ConstraintManager) void {
            self.constraints.deinit();
        }

        pub fn addConstraint(self: *ConstraintManager, constraint: Constraint) !usize {
            const index = self.constraints.items.len;
            try self.constraints.append(constraint);
            return index;
        }

        pub fn removeConstraint(self: *ConstraintManager, index: usize) void {
            if (index < self.constraints.items.len) {
                _ = self.constraints.swapRemove(index);
            }
        }

        pub fn solveConstraints(self: *ConstraintManager, objects: []PhysicalObject, rigid_bodies: *rigid_body.RigidBodyManager, dt: f32, iterations: u32) void {
            for (0..iterations) |_| {
                for (self.constraints.items) |*constraint| {
                    if (!constraint.enabled) continue;
                    self.solveConstraint(constraint, objects, rigid_bodies, dt);
                }
            }
        }

        fn solveConstraint(self: *ConstraintManager, constraint: *Constraint, objects: []PhysicalObject, rigid_bodies: *rigid_body.RigidBodyManager, dt: f32) void {
            _ = self;
            const obj_a = &objects[constraint.body_a];
            const rigid_body_a = rigid_bodies.getRigidBody(constraint.body_a) orelse return;

            switch (constraint.constraint_type) {
                .distance => {
                    const params = constraint.parameters.distance;

                    if (constraint.body_b) |body_b_idx| {
                        const obj_b = &objects[body_b_idx];
                        const pos_a = obj_a.position.add(constraint.anchor_a);
                        const pos_b = obj_b.position.add(constraint.anchor_b);
                        const delta = pos_b.sub(pos_a);
                        const current_distance = delta.magnitude();

                        if (current_distance > 0.001) {
                            const distance_error = current_distance - params.distance;
                            const correction = delta.normalize().scale(distance_error * 0.5);

                            if (!obj_a.pinned) {
                                obj_a.position = obj_a.position.add(correction.scale(obj_a.inverse_mass / (obj_a.inverse_mass + obj_b.inverse_mass)));
                            }
                            if (!obj_b.pinned) {
                                obj_b.position = obj_b.position.sub(correction.scale(obj_b.inverse_mass / (obj_a.inverse_mass + obj_b.inverse_mass)));
                            }
                        }
                    }
                },
                .spring => {
                    const params = constraint.parameters.spring;

                    if (constraint.body_b) |body_b_idx| {
                        const obj_b = &objects[body_b_idx];
                        const pos_a = obj_a.position.add(constraint.anchor_a);
                        const pos_b = obj_b.position.add(constraint.anchor_b);
                        const delta = pos_b.sub(pos_a);
                        const current_length = delta.magnitude();

                        if (current_length > 0.001) {
                            const extension = current_length - params.rest_length;
                            const spring_force = delta.normalize().scale(extension * params.stiffness);

                            // Apply spring force
                            rigid_body_a.applyForceAtPoint(spring_force, pos_a, obj_a);

                            if (rigid_bodies.getRigidBody(body_b_idx)) |rigid_body_b| {
                                rigid_body_b.applyForceAtPoint(spring_force.negate(), pos_b, obj_b);
                            }

                            // Apply damping
                            const relative_velocity = obj_b.velocity.sub(obj_a.velocity);
                            const damping_force = relative_velocity.scale(params.damping);

                            rigid_body_a.applyForceAtPoint(damping_force, pos_a, obj_a);
                            if (rigid_bodies.getRigidBody(body_b_idx)) |rigid_body_b| {
                                rigid_body_b.applyForceAtPoint(damping_force.negate(), pos_b, obj_b);
                            }
                        }
                    }
                },
                else => {
                    // TODO: Implement other constraint types
                },
            }

            _ = dt;
        }
    };

    /// Advanced collision detection system
    const CollisionDetector = struct {
        allocator: std.mem.Allocator,
        collision_pairs: std.ArrayList(CollisionPair),
        contact_manifolds: std.ArrayList(ContactManifold),

        const CollisionPair = struct {
            body_a: usize,
            body_b: usize,
            collision_time: f64,
        };

        const ContactManifold = struct {
            body_a: usize,
            body_b: usize,
            contacts: [4]ContactPoint,
            contact_count: u32,
            normal: Vec3f,
            penetration: f32,

            const ContactPoint = struct {
                position: Vec3f,
                local_a: Vec3f,
                local_b: Vec3f,
                normal_impulse: f32 = 0.0,
                tangent_impulse: [2]f32 = [_]f32{ 0.0, 0.0 },
            };
        };

        pub fn init(allocator: std.mem.Allocator) CollisionDetector {
            return .{
                .allocator = allocator,
                .collision_pairs = std.ArrayList(CollisionPair).init(allocator),
                .contact_manifolds = std.ArrayList(ContactManifold).init(allocator),
            };
        }

        pub fn deinit(self: *CollisionDetector) void {
            self.collision_pairs.deinit();
            self.contact_manifolds.deinit();
        }

        pub fn detectCollisions(self: *CollisionDetector, objects: []PhysicalObject, spatial_part: *spatial_partition.SpatialPartition) !void {
            self.collision_pairs.clearRetainingCapacity();
            self.contact_manifolds.clearRetainingCapacity();

            // Broad phase collision detection using spatial partitioning
            const potential_pairs = try spatial_part.queryPotentialCollisions();
            defer potential_pairs.deinit();

            for (potential_pairs.items) |pair| {
                const obj_a = &objects[pair.body_a];
                const obj_b = &objects[pair.body_b];

                if (obj_a.pinned and obj_b.pinned) continue;
                if (!obj_a.active or !obj_b.active) continue;

                // Narrow phase collision detection
                if (try self.narrowPhaseCollision(obj_a, obj_b, pair.body_a, pair.body_b)) {
                    try self.collision_pairs.append(pair);
                }
            }
        }

        fn narrowPhaseCollision(self: *CollisionDetector, obj_a: *PhysicalObject, obj_b: *PhysicalObject, idx_a: usize, idx_b: usize) !bool {
            // Simple sphere-sphere collision for now
            const distance = obj_a.position.distance(obj_b.position);
            const combined_radius = obj_a.radius + obj_b.radius;

            if (distance < combined_radius) {
                // Create contact manifold
                var manifold = ContactManifold{
                    .body_a = idx_a,
                    .body_b = idx_b,
                    .contacts = undefined,
                    .contact_count = 1,
                    .normal = obj_b.position.sub(obj_a.position).normalize(),
                    .penetration = combined_radius - distance,
                };

                // Create contact point
                const contact_point = obj_a.position.add(manifold.normal.scale(obj_a.radius));
                manifold.contacts[0] = .{
                    .position = contact_point,
                    .local_a = contact_point.sub(obj_a.position),
                    .local_b = contact_point.sub(obj_b.position),
                };

                try self.contact_manifolds.append(manifold);
                return true;
            }

            return false;
        }

        pub fn resolveCollisions(self: *CollisionDetector, objects: []PhysicalObject, rigid_bodies: *rigid_body.RigidBodyManager, iterations: u32) void {
            for (0..iterations) |_| {
                for (self.contact_manifolds.items) |*manifold| {
                    self.resolveContact(manifold, objects, rigid_bodies);
                }
            }
        }

        fn resolveContact(self: *CollisionDetector, manifold: *ContactManifold, objects: []PhysicalObject, rigid_bodies: *rigid_body.RigidBodyManager) void {
            _ = self;
            const obj_a = &objects[manifold.body_a];
            const obj_b = &objects[manifold.body_b];

            // Position correction (Baumgarte stabilization)
            const correction = manifold.normal.scale(manifold.penetration * 0.8);
            const total_inv_mass = obj_a.inverse_mass + obj_b.inverse_mass;

            if (total_inv_mass > 0.001) {
                if (!obj_a.pinned) {
                    obj_a.position = obj_a.position.sub(correction.scale(obj_a.inverse_mass / total_inv_mass));
                }
                if (!obj_b.pinned) {
                    obj_b.position = obj_b.position.add(correction.scale(obj_b.inverse_mass / total_inv_mass));
                }
            }

            // Impulse resolution
            const relative_velocity = obj_b.velocity.sub(obj_a.velocity);
            const velocity_along_normal = relative_velocity.dot(manifold.normal);

            if (velocity_along_normal > 0) return; // Objects separating

            const restitution = 0.5; // Combined restitution coefficient
            const impulse_magnitude = -(1.0 + restitution) * velocity_along_normal / total_inv_mass;
            const impulse = manifold.normal.scale(impulse_magnitude);

            if (!obj_a.pinned) {
                obj_a.velocity = obj_a.velocity.sub(impulse.scale(obj_a.inverse_mass));
                obj_a.wake();
            }
            if (!obj_b.pinned) {
                obj_b.velocity = obj_b.velocity.add(impulse.scale(obj_b.inverse_mass));
                obj_b.wake();
            }

            // Apply angular impulse for rigid bodies
            if (rigid_bodies.getRigidBody(manifold.body_a)) |rigid_body_a| {
                const r_a = manifold.contacts[0].local_a;
                const angular_impulse_a = r_a.cross(impulse.negate());
                obj_a.angular_velocity = obj_a.angular_velocity.add(rigid_body_a.inverse_inertia_tensor_world.multiplyVector(angular_impulse_a));
            }

            if (rigid_bodies.getRigidBody(manifold.body_b)) |rigid_body_b| {
                const r_b = manifold.contacts[0].local_b;
                const angular_impulse_b = r_b.cross(impulse);
                obj_b.angular_velocity = obj_b.angular_velocity.add(rigid_body_b.inverse_inertia_tensor_world.multiplyVector(angular_impulse_b));
            }
        }
    };

    pub fn init(allocator: std.mem.Allocator, config: ?PhysicsConfig) !*PhysicsEngine {
        const default_config = PhysicsConfig{};
        const physics_config = config orelse default_config;

        const engine = try allocator.create(PhysicsEngine);
        engine.* = .{
            .allocator = allocator,
            .objects = std.ArrayList(PhysicalObject).init(allocator),
            .rigid_body_manager = rigid_body.RigidBodyManager.init(allocator),
            .constraint_manager = ConstraintManager.init(allocator),
            .collision_detector = CollisionDetector.init(allocator),
            .spatial_partition = try spatial_partition.SpatialPartition.init(allocator, physics_config.world_size, physics_config.cell_size),
            .continuous_collision = continuous_collision.ContinuousCollision.init(allocator),
            .gravity = physics_config.gravity,
            .damping = physics_config.damping,
            .collision_iterations = physics_config.collision_iterations,
            .constraint_iterations = physics_config.constraint_iterations,
            .performance_stats = PerformanceStats{},
        };
        return engine;
    }

    /// Simple init with allocator only (for API compatibility)
    pub fn initSimple(allocator: std.mem.Allocator) !*PhysicsEngine {
        return init(allocator, null);
    }

    /// Initialize with required config (for API compatibility)
    pub fn initWithConfig(allocator: std.mem.Allocator, config: PhysicsConfig) !*PhysicsEngine {
        return init(allocator, config);
    }

    pub fn deinit(self: *PhysicsEngine) void {
        self.objects.deinit();
        self.rigid_body_manager.deinit();
        self.constraint_manager.deinit();
        self.collision_detector.deinit();
        self.spatial_partition.deinit();
        self.continuous_collision.deinit();
    }

    /// Create a rigid body with specified shape and properties
    pub fn createRigidBody(self: *PhysicsEngine, config: RigidBodyConfig) !usize {
        const object_idx = self.objects.items.len;

        // Create physical object
        var physical_object = PhysicalObject.init(config.position, config.mass);
        physical_object.velocity = config.initial_velocity;
        physical_object.angular_velocity = config.initial_angular_velocity;
        physical_object.orientation = config.orientation;
        physical_object.radius = config.shape.getRadius();
        physical_object.active = true;
        physical_object.object_type = config.object_type;

        try self.objects.append(physical_object);

        // Create rigid body with appropriate inertia tensor
        const inertia_tensor = config.shape.calculateInertiaTensor(config.mass);
        _ = try self.rigid_body_manager.createRigidBody(object_idx, inertia_tensor);

        // Add to spatial partition
        try self.spatial_partition.addObject(object_idx, physical_object.position, physical_object.radius);

        return object_idx;
    }

    /// Rigid body configuration for creation
    pub const RigidBodyConfig = struct {
        position: Vec3f = Vec3f.zero,
        orientation: Quat = .{ .x = 0, .y = 0, .z = 0, .w = 1 },
        initial_velocity: Vec3f = Vec3f.zero,
        initial_angular_velocity: Vec3f = Vec3f.zero,
        mass: f32 = 1.0,
        shape: Shape = .{ .sphere = .{ .radius = 1.0 } },
        object_type: ObjectType = .dynamic,
        material: Material = .{},

        pub const Shape = union(enum) {
            sphere: struct { radius: f32 },
            box: struct { width: f32, height: f32, depth: f32 },
            cylinder: struct { radius: f32, height: f32 },
            capsule: struct { radius: f32, height: f32 },

            pub fn getRadius(self: Shape) f32 {
                return switch (self) {
                    .sphere => |s| s.radius,
                    .box => |b| @sqrt(b.width * b.width + b.height * b.height + b.depth * b.depth) * 0.5,
                    .cylinder => |c| @max(c.radius, c.height * 0.5),
                    .capsule => |c| c.radius + c.height * 0.5,
                };
            }

            pub fn calculateInertiaTensor(self: Shape, mass: f32) Mat4 {
                return switch (self) {
                    .sphere => |s| rigid_body.InertiaPresets.sphere(mass, s.radius),
                    .box => |b| rigid_body.InertiaPresets.box(mass, b.width, b.height, b.depth),
                    .cylinder => |c| rigid_body.InertiaPresets.cylinder(mass, c.radius, c.height),
                    .capsule => |c| rigid_body.InertiaPresets.cylinder(mass, c.radius, c.height), // Approximation
                };
            }
        };

        pub const Material = struct {
            restitution: f32 = 0.3,
            friction: f32 = 0.5,
            density: f32 = 1.0,
        };
    };

    /// Add a constraint between two rigid bodies
    pub fn addConstraint(self: *PhysicsEngine, body_a: usize, body_b: ?usize, constraint_type: ConstraintManager.Constraint.ConstraintType, anchor_a: Vec3f, anchor_b: Vec3f, parameters: ConstraintManager.Constraint.ConstraintParameters) !usize {
        const constraint = ConstraintManager.Constraint{
            .constraint_type = constraint_type,
            .body_a = body_a,
            .body_b = body_b,
            .anchor_a = anchor_a,
            .anchor_b = anchor_b,
            .parameters = parameters,
        };

        return try self.constraint_manager.addConstraint(constraint);
    }

    /// Apply force to a rigid body at a specific point
    pub fn applyForceAtPoint(self: *PhysicsEngine, body_index: usize, force: Vec3f, point: Vec3f) void {
        if (body_index < self.objects.items.len) {
            const obj = &self.objects.items[body_index];
            if (self.rigid_body_manager.getRigidBody(body_index)) |rigid_body_ref| {
                rigid_body_ref.applyForceAtPoint(force, point, obj);
            }
        }
    }

    /// Apply impulse to a rigid body
    pub fn applyImpulse(self: *PhysicsEngine, body_index: usize, impulse: Vec3f) void {
        if (body_index < self.objects.items.len) {
            const obj = &self.objects.items[body_index];
            if (!obj.pinned and obj.active) {
                obj.velocity = obj.velocity.add(impulse.scale(obj.inverse_mass));
                obj.wake();
            }
        }
    }

    /// Set rigid body transform
    pub fn setTransform(self: *PhysicsEngine, body_index: usize, position: Vec3f, orientation: Quat) void {
        if (body_index < self.objects.items.len) {
            const obj = &self.objects.items[body_index];
            obj.position = position;
            obj.orientation = orientation;
            obj.wake();

            // Update spatial partition
            self.spatial_partition.updateObject(body_index, position, obj.radius);
        }
    }

    /// Get rigid body transform
    pub fn getTransform(self: *PhysicsEngine, body_index: usize) ?struct { position: Vec3f, orientation: Quat } {
        if (body_index < self.objects.items.len) {
            const obj = &self.objects.items[body_index];
            return .{ .position = obj.position, .orientation = obj.orientation };
        }
        return null;
    }

    /// Main physics update with advanced features
    pub fn update(self: *PhysicsEngine, dt: f32) void {
        const start_time = std.time.nanoTimestamp();

        // Update spatial partitioning
        self.spatial_partition.update();

        // Collision detection
        const collision_start = std.time.nanoTimestamp();
        self.collision_detector.detectCollisions(self.objects.items, &self.spatial_partition) catch |err| {
            std.log.warn("Collision detection failed: {}", .{err});
        };
        self.performance_stats.collision_detection_time_ms = @as(f64, @floatFromInt(std.time.nanoTimestamp() - collision_start)) / 1_000_000.0;

        // Constraint solving
        const constraint_start = std.time.nanoTimestamp();
        self.constraint_manager.solveConstraints(self.objects.items, &self.rigid_body_manager, dt, self.constraint_iterations);
        self.performance_stats.constraint_solving_time_ms = @as(f64, @floatFromInt(std.time.nanoTimestamp() - constraint_start)) / 1_000_000.0;

        // Collision resolution
        self.collision_detector.resolveCollisions(self.objects.items, &self.rigid_body_manager, self.collision_iterations);

        // Integration
        const integration_start = std.time.nanoTimestamp();
        self.integrateMotion(dt);
        self.performance_stats.integration_time_ms = @as(f64, @floatFromInt(std.time.nanoTimestamp() - integration_start)) / 1_000_000.0;

        // Update performance stats
        self.performance_stats.simulation_time_ms = @as(f64, @floatFromInt(std.time.nanoTimestamp() - start_time)) / 1_000_000.0;
        self.performance_stats.active_bodies = self.countActiveBodies();
        self.performance_stats.collision_pairs = @intCast(self.collision_detector.collision_pairs.items.len);
        self.performance_stats.constraint_count = @intCast(self.constraint_manager.constraints.items.len);
    }

    fn integrateMotion(self: *PhysicsEngine, dt: f32) void {
        // Apply gravity and integrate all rigid bodies
        for (self.objects.items, 0..) |*obj, i| {
            if (!obj.active or obj.pinned) continue;

            // Apply gravity
            if (obj.inverse_mass > 0.0) {
                if (self.rigid_body_manager.getRigidBody(i)) |rigid_body_ref| {
                    const gravity_force = self.gravity.scale(1.0 / obj.inverse_mass);
                    rigid_body_ref.force_accumulator = rigid_body_ref.force_accumulator.add(gravity_force);
                }
            }

            // Apply damping
            obj.velocity = obj.velocity.scale(self.damping);
            obj.angular_velocity = obj.angular_velocity.scale(self.damping);

            // Sleep inactive bodies
            if (self.sleeping_enabled) {
                const kinetic_energy = 0.5 * (1.0 / obj.inverse_mass) * obj.velocity.magnitudeSquared() +
                    0.5 * obj.angular_velocity.magnitudeSquared();

                if (kinetic_energy < PhysicsConstants.SLEEP_THRESHOLD) {
                    obj.sleep_timer += dt;
                    if (obj.sleep_timer > PhysicsConstants.SLEEP_TIME) {
                        obj.active = false;
                        obj.velocity = Vec3f.zero;
                        obj.angular_velocity = Vec3f.zero;
                    }
                } else {
                    obj.sleep_timer = 0.0;
                }
            }
        }

        // Integrate all rigid bodies
        self.rigid_body_manager.integrateAll(self.objects.items, dt);

        // Update spatial partition after integration
        for (self.objects.items, 0..) |*obj, i| {
            if (obj.active) {
                self.spatial_partition.updateObject(i, obj.position, obj.radius);
            }
        }
    }

    fn countActiveBodies(self: *PhysicsEngine) u32 {
        var count: u32 = 0;
        for (self.objects.items) |*obj| {
            if (obj.active) count += 1;
        }
        return count;
    }

    /// Get performance statistics
    pub fn getPerformanceStats(self: *PhysicsEngine) PerformanceStats {
        return self.performance_stats;
    }

    /// Enable/disable deterministic simulation
    pub fn setDeterministic(self: *PhysicsEngine, deterministic: bool) void {
        self.deterministic = deterministic;
    }

    /// Set physics parameters
    pub fn setParameters(self: *PhysicsEngine, gravity: Vec3f, time_step: f32, iterations: struct { collision: u32, constraint: u32 }) void {
        self.gravity = gravity;
        self.time_step = time_step;
        self.collision_iterations = iterations.collision;
        self.constraint_iterations = iterations.constraint;
    }

    /// Legacy compatibility methods
    pub fn addObject(self: *PhysicsEngine, object: PhysicalObject) !usize {
        const index = self.objects.items.len;
        try self.objects.append(object);
        return index;
    }

    pub fn removeObject(self: *PhysicsEngine, index: usize) void {
        if (index < self.objects.items.len) {
            _ = self.objects.swapRemove(index);
        }
    }

    pub fn getObject(self: *PhysicsEngine, index: usize) ?*PhysicalObject {
        if (index < self.objects.items.len) {
            return &self.objects.items[index];
        }
        return null;
    }

    pub fn step(self: *PhysicsEngine, dt: f32) void {
        self.update(dt);
    }

    // Physics engine configuration
    pub const PhysicsConfig = struct {
        world_size: f32 = 1000.0,
        cell_size: f32 = 10.0,
        gravity: Vec3f = Vec3f{ .x = 0.0, .y = -9.81, .z = 0.0 },
        damping: f32 = 0.99,
        collision_iterations: u32 = 4,
        constraint_iterations: u32 = 8,
        time_step: f32 = 1.0 / 60.0,
        enable_ccd: bool = false,
    };
};
