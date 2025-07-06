const std = @import("std");
const physics = @import("physics.zig");
const physics_mod = @import("mod.zig");
const math = physics_mod.Math;
const Vector = math.Vector;
const Quaternion = math.Quaternion;
const Vec3f = math.Vec3f;
const PhysicsConstants = physics.PhysicsConstants;
const PhysicalObject = physics.PhysicalObject;
const ObjectType = physics.ObjectType;
const Matrix3 = math.Mat3f;
const Matrix4 = math.Mat4f;

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
    force_accumulator: Vec3f = Vec3f.zero,
    torque_accumulator: Vec3f = Vec3f.zero,

    /// Create a RigidBody from a PhysicalObject index
    pub fn init(object_idx: usize, inertia_tensor: Matrix3) RigidBody {
        return .{
            .object_idx = object_idx,
            .inertia_tensor = inertia_tensor,
            .inverse_inertia_tensor = inertia_tensor.inverse() orelse Matrix3.identity,
            .inertia_tensor_world = inertia_tensor,
            .inverse_inertia_tensor_world = inertia_tensor.inverse() orelse Matrix3.identity,
        };
    }

    /// Apply a force at a point in world space
    pub fn applyForceAtPoint(self: *RigidBody, force: Vec3f, point: Vec3f, obj: *PhysicalObject) void {
        // Apply the force
        self.force_accumulator = self.force_accumulator.add(force);

        // Calculate the torque: τ = r × F
        const rel_pos = point.sub(obj.position);

        // Cross product: torque = relative_pos × force
        const torque = rel_pos.cross(force);

        // Apply the torque
        self.torque_accumulator = self.torque_accumulator.add(torque);

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
        self.inverse_inertia_tensor_world = self.inertia_tensor_world.inverse() orelse Matrix3.identity;
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
        const linear_accel = self.force_accumulator.scale(obj.inverse_mass);

        // Calculate angular acceleration from torques
        const angular_accel = self.calculateAngularAcceleration();

        // Update linear velocity and position
        obj.velocity = obj.velocity.add(linear_accel.scale(dt));

        // Apply velocity limits
        const speed_sq = obj.velocity.magnitudeSquared();

        if (speed_sq > PhysicsConstants.MAX_VELOCITY * PhysicsConstants.MAX_VELOCITY) {
            const speed = @sqrt(speed_sq);
            const scale_factor = PhysicsConstants.MAX_VELOCITY / speed;
            obj.velocity = obj.velocity.scale(scale_factor);
        }

        // Update position
        obj.position = obj.position.add(obj.velocity.scale(dt));

        // Update angular velocity
        obj.angular_velocity = obj.angular_velocity.add(angular_accel.scale(dt));

        // Update orientation using quaternion integration
        const omega = Quaternion.init(obj.angular_velocity.x, obj.angular_velocity.y, obj.angular_velocity.z, 0);

        // Compute rate of change: dq/dt = 0.5 * omega * q
        const omega_q = omega.multiply(obj.orientation).scale(0.5);

        // Apply to orientation: q' = q + dq/dt * dt
        obj.orientation = obj.orientation.add(omega_q.scale(dt)).normalize();

        // Clear accumulators
        self.force_accumulator = Vec3f.zero;
        self.torque_accumulator = Vec3f.zero;
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
