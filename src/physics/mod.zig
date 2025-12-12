//! MFS Engine - Physics Module
//! Comprehensive physics simulation system with collision detection, rigid body dynamics,
//! constraints, joints, and continuous collision detection
//! @thread-safe Physics simulation can be multi-threaded with proper synchronization
//! @performance Optimized with spatial partitioning and broad-phase collision detection

const std = @import("std");
const builtin = @import("builtin");

// Export math module for physics components
pub const Math = @import("../math/mod.zig");

// Core physics components
pub const physics_engine = @import("physics_engine.zig");
pub const rigid_body = @import("rigid_body.zig");
pub const shapes = @import("shapes.zig");
pub const collision_resolver = @import("collision_resolver.zig");
pub const continuous_collision = @import("continuous_collision.zig");
pub const constraints = @import("constraints.zig");
pub const joints = @import("joints.zig");
pub const triggers = @import("triggers.zig");
pub const spatial_partition = @import("spatial_partition.zig");

// Re-export main physics types
pub const PhysicsEngine = physics_engine.PhysicsEngine;
pub const PhysicsConfig = physics_engine.PhysicsEngine.PhysicsConfig;
pub const PhysicsSettings = physics_engine.PhysicsSettings;
pub const PhysicsWorld = physics_engine.PhysicsWorld;

pub const RigidBody = rigid_body.RigidBody;
pub const RigidBodyConfig = rigid_body.RigidBodyConfig;

pub const Shape = shapes.Shape;
pub const ShapeType = shapes.ShapeType;
pub const CollisionShape = shapes.CollisionShape;

pub const CollisionResolver = collision_resolver.CollisionResolver;
pub const CollisionInfo = collision_resolver.CollisionInfo;
pub const ContactPoint = collision_resolver.ContactPoint;

pub const Constraint = constraints.Constraint;
pub const ConstraintType = constraints.ConstraintType;

pub const Joint = joints.Joint;
pub const JointType = joints.JointType;

pub const Trigger = triggers.Trigger;
pub const TriggerEvent = triggers.TriggerEvent;

pub const SpatialPartition = spatial_partition.SpatialPartition;

// Add missing RigidBodyDesc for API compatibility
pub const RigidBodyDesc = struct {
    position: [3]f32 = [_]f32{0} ** 3,
    velocity: [3]f32 = [_]f32{0} ** 3,
    angular_velocity: [3]f32 = [_]f32{0} ** 3,
    mass: f32 = 1.0,
    restitution: f32 = 0.3,
    friction: f32 = 0.5,
    body_type: RigidBodyType = .dynamic,
    shape: ?*CollisionShape = null,

    pub const BodyType = enum {
        static,
        kinematic,
        dynamic,
    };
};

// Additional compatibility types
pub const RigidBodyType = RigidBodyDesc.BodyType;

// Physics simulation configuration
pub const Config = struct {
    gravity: [3]f32 = [_]f32{ 0.0, -9.81, 0.0 },
    time_step: f32 = 1.0 / 60.0,
    max_substeps: u32 = 10,
    solver_iterations: u32 = 8,
    enable_sleeping: bool = true,
    enable_ccd: bool = true,
    enable_warm_starting: bool = true,
    enable_multithreading: bool = false,
    max_rigid_bodies: u32 = 10000,
    enable_continuous_collision: bool = true,
    broad_phase_type: BroadPhaseType = .sweep_and_prune,

    pub const BroadPhaseType = enum {
        brute_force,
        sweep_and_prune,
        spatial_hash,
        octree,
    };

    pub fn validate(self: Config) !void {
        if (self.time_step <= 0.0 or self.time_step > 1.0) {
            return error.InvalidParameter;
        }
        if (self.max_substeps == 0 or self.max_substeps > 100) {
            return error.InvalidParameter;
        }
        if (self.solver_iterations == 0 or self.solver_iterations > 50) {
            return error.InvalidParameter;
        }
    }
};

// Alias for backward compatibility
pub const SimulationConfig = struct {
    gravity: [3]f32 = [_]f32{ 0.0, -9.81, 0.0 },
    time_step: f32 = 1.0 / 60.0,
    max_substeps: u32 = 10,
    solver_iterations: u32 = 8,
    enable_sleeping: bool = true,
    enable_ccd: bool = true,
    enable_warm_starting: bool = true,
    broad_phase_type: BroadPhaseType = .sweep_and_prune,

    pub const BroadPhaseType = enum {
        brute_force,
        sweep_and_prune,
        spatial_hash,
        octree,
    };

    pub fn validate(self: SimulationConfig) !void {
        if (self.time_step <= 0.0 or self.time_step > 1.0) {
            return error.InvalidParameter;
        }
        if (self.max_substeps == 0 or self.max_substeps > 100) {
            return error.InvalidParameter;
        }
        if (self.solver_iterations == 0 or self.solver_iterations > 50) {
            return error.InvalidParameter;
        }
    }
};

// Initialize physics system
pub fn init(allocator: std.mem.Allocator, config: Config) !*PhysicsEngine {
    // Validate configuration
    try config.validate();

    // Convert Config to PhysicsConfig
    const physics_config = physics_engine.PhysicsEngine.PhysicsConfig{
        .gravity = .{ .x = config.gravity[0], .y = config.gravity[1], .z = config.gravity[2] },
        .damping = 0.99,
        .world_size = 1000.0,
        .cell_size = 10.0,
        .collision_iterations = config.solver_iterations,
        .constraint_iterations = config.solver_iterations,
    };

    // Create physics engine with config
    const engine = try PhysicsEngine.init(allocator, physics_config);

    return engine;
}

// Cleanup physics system
pub fn deinit(engine: *PhysicsEngine) void {
    engine.deinit();
}

test "physics module" {
    std.testing.refAllDecls(@This());
}
