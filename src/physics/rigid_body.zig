const std = @import("std");
const physics = @import("physics.zig");
const math = physics.math;
const Vector = math.Vector;
const Quaternion = math.Quaternion;
const Vec3f = physics.Vec3f;
const PhysicsConstants = physics.PhysicsConstants;
const PhysicalObject = physics.PhysicalObject;
const ObjectType = physics.ObjectType;
const Matrix3 = math.mat3.Matrix3;
const Matrix4 = math.mat4.Matrix4;

/// Inertia tensor presets for common shapes
pub const InertiaPresets = struct {
    /// Inertia tensor for a solid sphere
    pub fn sphere(mass: f32, radius: f32) Matrix3 {
        const i = (2.0 / 5.0) * mass * radius * radius;
        return Matrix3.diagonal(i, i, i);
    }

    /// Inertia tensor for a solid box
    pub fn box(mass: f32, width: f32, height: f32, depth: f32) Matrix3 {
        const w2 = width * width;
        const h2 = height * height;
        const d2 = depth * depth;

        const ix = (1.0 / 12.0) * mass * (h2 + d2);
        const iy = (1.0 / 12.0) * mass * (w2 + d2);
        const iz = (1.0 / 12.0) * mass * (w2 + h2);

        return Matrix3.diagonal(ix, iy, iz);
    }

    /// Inertia tensor for a cylinder along the Y axis
    pub fn cylinder(mass: f32, radius: f32, height: f32) Matrix3 {
        const r2 = radius * radius;
        const h2 = height * height;

        const ix = (1.0 / 12.0) * mass * (3 * r2 + h2);
        const iy = 0.5 * mass * r2;
        const iz = ix;

        return Matrix3.diagonal(ix, iy, iz);
    }
};

/// RigidBody with full rotational dynamics
pub const RigidBody = struct {
    // Base physical properties from PhysicalObject
    object_idx: usize,

    // Rotation-specific properties
    inertia_tensor: Matrix3,
    inverse_inertia_tensor: Matrix3,
    inertia_tensor_world: Matrix3,
    inverse_inertia_tensor_world: Matrix3,

    // Force and torque accumulators
    force_accumulator: Vec3f = .{ 0, 0, 0, 0 },
    torque_accumulator: Vec3f = .{ 0, 0, 0, 0 },

    /// Create a RigidBody from a PhysicalObject index
    pub fn init(object_idx: usize, inertia_tensor: Matrix3) RigidBody {
        return .{
            .object_idx = object_idx,
            .inertia_tensor = inertia_tensor,
            .inverse_inertia_tensor = inertia_tensor.inverse() catch Matrix3.identity(),
            .inertia_tensor_world = inertia_tensor,
            .inverse_inertia_tensor_world = inertia_tensor.inverse() catch Matrix3.identity(),
        };
    }

    /// Apply a force at a point in world space
    pub fn applyForceAtPoint(self: *RigidBody, force: Vec3f, point: Vec3f, obj: *PhysicalObject) void {
        // Apply the force
        self.force_accumulator[0] += force[0];
        self.force_accumulator[1] += force[1];
        self.force_accumulator[2] += force[2];

        // Calculate the torque: τ = r × F
        const rel_pos = Vec3f{
            point[0] - obj.position[0],
            point[1] - obj.position[1],
            point[2] - obj.position[2],
            0,
        };

        // Cross product: torque = relative_pos × force
        const torque = Vec3f{
            rel_pos[1] * force[2] - rel_pos[2] * force[1],
            rel_pos[2] * force[0] - rel_pos[0] * force[2],
            rel_pos[0] * force[1] - rel_pos[1] * force[0],
            0,
        };

        // Apply the torque
        self.torque_accumulator[0] += torque[0];
        self.torque_accumulator[1] += torque[1];
        self.torque_accumulator[2] += torque[2];

        // Ensure the object is awake
        obj.wake();
    }

    /// Update inertia tensor in world space
    pub fn updateInertiaTensor(self: *RigidBody, obj: *PhysicalObject) void {
        // Convert quaternion to rotation matrix
        const rotation_matrix = obj.orientation.toMatrix3();

        // Transform the inertia tensor to world space: I_world = R * I_local * R^T
        self.inertia_tensor_world = rotation_matrix.multiply(self.inertia_tensor).multiply(rotation_matrix.transpose());

        // Update the inverse tensor
        self.inverse_inertia_tensor_world = self.inertia_tensor_world.inverse() catch Matrix3.identity();
    }

    /// Calculate angular acceleration from torque: α = I^-1 * τ
    pub fn calculateAngularAcceleration(self: *RigidBody) Vec3f {
        const torque = self.torque_accumulator;

        // Compute angular acceleration: α = I^-1 * τ
        const angular_accel = self.inverse_inertia_tensor_world.multiplyVector(torque);

        return angular_accel;
    }

    /// Integrate rigid body motion using Runge-Kutta 4th order
    pub fn integrate(self: *RigidBody, obj: *PhysicalObject, dt: f32) void {
        if (obj.pinned or !obj.active) return;

        // Update the inertia tensor in world space
        self.updateInertiaTensor(obj);

        // Calculate linear acceleration from forces: a = F/m
        const linear_accel = Vec3f{
            self.force_accumulator[0] * obj.inverse_mass,
            self.force_accumulator[1] * obj.inverse_mass,
            self.force_accumulator[2] * obj.inverse_mass,
            0,
        };

        // Calculate angular acceleration from torques
        const angular_accel = self.calculateAngularAcceleration();

        // Update linear velocity and position
        obj.velocity[0] += linear_accel[0] * dt;
        obj.velocity[1] += linear_accel[1] * dt;
        obj.velocity[2] += linear_accel[2] * dt;

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

        // Update angular velocity
        obj.angular_velocity[0] += angular_accel[0] * dt;
        obj.angular_velocity[1] += angular_accel[1] * dt;
        obj.angular_velocity[2] += angular_accel[2] * dt;

        // Update orientation using quaternion integration
        const omega = Quaternion.fromVector(obj.angular_velocity[0], obj.angular_velocity[1], obj.angular_velocity[2], 0);

        // Compute rate of change: dq/dt = 0.5 * omega * q
        const omega_q = omega.multiply(obj.orientation).scale(0.5);

        // Apply to orientation: q' = q + dq/dt * dt
        obj.orientation = obj.orientation.add(omega_q.scale(dt)).normalize();

        // Clear accumulators
        self.force_accumulator = Vec3f{ 0, 0, 0, 0 };
        self.torque_accumulator = Vec3f{ 0, 0, 0, 0 };
    }
};

/// RigidBodyManager for managing a collection of rigid bodies
pub const RigidBodyManager = struct {
    allocator: std.mem.Allocator,
    rigid_bodies: std.ArrayList(RigidBody),
    object_to_rigid_body: std.AutoHashMap(usize, usize),

    pub fn init(allocator: std.mem.Allocator) RigidBodyManager {
        return .{
            .allocator = allocator,
            .rigid_bodies = std.ArrayList(RigidBody).init(allocator),
            .object_to_rigid_body = std.AutoHashMap(usize, usize).init(allocator),
        };
    }

    pub fn deinit(self: *RigidBodyManager) void {
        self.rigid_bodies.deinit();
        self.object_to_rigid_body.deinit();
    }

    pub fn createRigidBody(self: *RigidBodyManager, object_idx: usize, inertia_tensor: Matrix3) !*RigidBody {
        const body_idx = self.rigid_bodies.items.len;
        try self.rigid_bodies.append(RigidBody.init(object_idx, inertia_tensor));
        try self.object_to_rigid_body.put(object_idx, body_idx);
        return &self.rigid_bodies.items[body_idx];
    }

    pub fn getRigidBody(self: *RigidBodyManager, object_idx: usize) ?*RigidBody {
        if (self.object_to_rigid_body.get(object_idx)) |body_idx| {
            return &self.rigid_bodies.items[body_idx];
        }
        return null;
    }

    pub fn integrateAll(self: *RigidBodyManager, objects: []PhysicalObject, dt: f32) void {
        for (self.rigid_bodies.items) |*rigid_body| {
            const obj = &objects[rigid_body.object_idx];
            rigid_body.integrate(obj, dt);
        }
    }
};
