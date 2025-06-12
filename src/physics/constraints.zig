const std = @import("std");
const physics = @import("physics.zig");
const math = physics.math;
const Vector = math.Vector;
const Quaternion = math.Quaternion;
const Vec3f = physics.Vec3f;
const PhysicsConstants = physics.PhysicsConstants;
const PhysicalObject = physics.PhysicalObject;
const ObjectType = physics.ObjectType;

/// Unified constraint interface using tagged union for type safety and extensibility
pub const Constraint = union(enum) {
    Spring: *SpringConstraint,
    Distance: *DistanceConstraint,
    Position: *PositionConstraint,
    Angle: *AngleConstraint,

    pub fn apply(self: Constraint, objects: []PhysicalObject, dt: f32) void {
        switch (self) {
            .Spring => |spring| spring.solve(objects, dt),
            .Distance => |distance| distance.solve(objects, dt),
            .Position => |position| position.solve(objects, dt),
            .Angle => |angle| angle.solve(objects, dt),
        }
    }

    pub fn violation(self: Constraint, objects: []const PhysicalObject) f32 {
        return switch (self) {
            .Spring => |spring| spring.violation(objects),
            .Distance => |distance| distance.violation(objects),
            .Position => |position| position.violation(objects),
            .Angle => |angle| angle.violation(objects),
        };
    }

    pub fn typeId(self: Constraint) u32 {
        return switch (self) {
            .Spring => 1,
            .Distance => 2,
            .Position => 3,
            .Angle => 4,
        };
    }

    pub fn isActive(self: Constraint) bool {
        return switch (self) {
            .Spring => |spring| spring.active,
            .Distance => |distance| distance.active,
            .Position => |position| position.active,
            .Angle => |angle| angle.active,
        };
    }
};

/// A spring constraint between two objects
pub const SpringConstraint = struct {
    object_index_a: usize,
    object_index_b: usize,
    rest_length: f32,
    stiffness: f32,
    damping: f32,
    break_threshold: f32,
    active: bool = true,
    min_length: f32 = 0.0,
    max_length: f32 = std.math.inf(f32),
    bidirectional: bool = true,

    /// Apply the spring constraint
    pub fn solve(self: *SpringConstraint, objects: []PhysicalObject, dt: f32) void {
        if (!self.active) return;

        var obj_a = &objects[self.object_index_a];
        var obj_b = &objects[self.object_index_b];

        // Skip if both objects are pinned
        if (obj_a.pinned and obj_b.pinned) return;

        // Get positions
        const pos_a = obj_a.position;
        const pos_b = obj_b.position;

        // Calculate displacement vector
        const delta = Vec3f{
            pos_b[0] - pos_a[0],
            pos_b[1] - pos_a[1],
            pos_b[2] - pos_a[2],
            0.0,
        };

        // Calculate current length
        const current_length = @sqrt(delta[0] * delta[0] +
            delta[1] * delta[1] +
            delta[2] * delta[2]);

        // Skip if length is zero to avoid divide by zero
        if (current_length < PhysicsConstants.SAFE_DIVISOR) return;

        // Calculate normalized direction
        const direction = Vec3f{
            delta[0] / current_length,
            delta[1] / current_length,
            delta[2] / current_length,
            0.0,
        };

        // Calculate stretch amount
        var stretch = current_length - self.rest_length;

        // Clamp if beyond limits (only applies to stretching if bidirectional=false)
        if (!self.bidirectional and stretch < 0) return;

        // Apply min/max length constraints
        if (current_length < self.min_length) {
            stretch = current_length - self.min_length;
        } else if (current_length > self.max_length) {
            stretch = current_length - self.max_length;
        }

        // Break the spring if beyond threshold
        if (self.break_threshold > 0 and std.math.fabs(stretch) > self.break_threshold) {
            self.active = false;
            return;
        }

        // Calculate relative velocity
        const vel_a = obj_a.velocity;
        const vel_b = obj_b.velocity;
        const rel_vel = Vec3f{
            vel_b[0] - vel_a[0],
            vel_b[1] - vel_a[1],
            vel_b[2] - vel_a[2],
            0.0,
        };

        // Calculate velocity along spring direction (for damping)
        const vel_along_spring =
            rel_vel[0] * direction[0] +
            rel_vel[1] * direction[1] +
            rel_vel[2] * direction[2];

        // Calculate spring force (Hooke's law + damping)
        const spring_force = self.stiffness * stretch;
        const damping_force = self.damping * vel_along_spring;
        const total_force = spring_force + damping_force;

        // Apply forces to objects
        const force = Vec3f{
            direction[0] * total_force,
            direction[1] * total_force,
            direction[2] * total_force,
            0.0,
        };

        // Apply impulses
        if (!obj_a.pinned) {
            obj_a.velocity[0] += force[0] * obj_a.inverse_mass * dt;
            obj_a.velocity[1] += force[1] * obj_a.inverse_mass * dt;
            obj_a.velocity[2] += force[2] * obj_a.inverse_mass * dt;
        }

        if (!obj_b.pinned) {
            obj_b.velocity[0] -= force[0] * obj_b.inverse_mass * dt;
            obj_b.velocity[1] -= force[1] * obj_b.inverse_mass * dt;
            obj_b.velocity[2] -= force[2] * obj_b.inverse_mass * dt;
        }

        // Wake up the objects
        obj_a.wake();
        obj_b.wake();
    }

    pub fn violation(self: *const SpringConstraint, objects: []const PhysicalObject) f32 {
        const obj_a = objects[self.object_index_a];
        const obj_b = objects[self.object_index_b];

        // Calculate current length
        const delta = Vec3f{
            obj_b.position[0] - obj_a.position[0],
            obj_b.position[1] - obj_a.position[1],
            obj_b.position[2] - obj_a.position[2],
            0.0,
        };

        const current_length = @sqrt(delta[0] * delta[0] +
            delta[1] * delta[1] +
            delta[2] * delta[2]);

        // Calculate violation amount
        return std.math.fabs(current_length - self.rest_length);
    }
};

/// Distance constraint that maintains a fixed distance between points
pub const DistanceConstraint = struct {
    object_index_a: usize,
    object_index_b: usize,
    distance: f32,
    compliance: f32 = 0.0,
    active: bool = true,

    pub fn solve(self: *DistanceConstraint, objects: []PhysicalObject, dt: f32) void {
        if (!self.active) return;

        var obj_a = &objects[self.object_index_a];
        var obj_b = &objects[self.object_index_b];

        // Skip if both objects are pinned
        if (obj_a.pinned and obj_b.pinned) return;

        // Get positions
        const pos_a = obj_a.position;
        const pos_b = obj_b.position;

        // Calculate displacement vector
        const delta = Vec3f{
            pos_b[0] - pos_a[0],
            pos_b[1] - pos_a[1],
            pos_b[2] - pos_a[2],
            0.0,
        };

        // Calculate current length
        const current_length = @sqrt(delta[0] * delta[0] +
            delta[1] * delta[1] +
            delta[2] * delta[2]);

        // Skip if length is zero to avoid divide by zero
        if (current_length < PhysicsConstants.SAFE_DIVISOR) return;

        // Calculate normalized direction
        const direction = Vec3f{
            delta[0] / current_length,
            delta[1] / current_length,
            delta[2] / current_length,
            0.0,
        };

        // Calculate correction
        const diff = current_length - self.distance;

        // Calculate constraint factor based on masses
        const mass_factor = obj_a.inverse_mass + obj_b.inverse_mass;
        if (mass_factor < PhysicsConstants.SAFE_DIVISOR) return;

        // Calculate stiffness coefficient
        const alpha = self.compliance / (dt * dt);
        const beta = 0.2; // stabilization factor

        const lambda = -diff / (mass_factor + alpha);

        // Apply position corrections
        if (!obj_a.pinned) {
            obj_a.position[0] -= direction[0] * lambda * obj_a.inverse_mass * beta;
            obj_a.position[1] -= direction[1] * lambda * obj_a.inverse_mass * beta;
            obj_a.position[2] -= direction[2] * lambda * obj_a.inverse_mass * beta;
        }

        if (!obj_b.pinned) {
            obj_b.position[0] += direction[0] * lambda * obj_b.inverse_mass * beta;
            obj_b.position[1] += direction[1] * lambda * obj_b.inverse_mass * beta;
            obj_b.position[2] += direction[2] * lambda * obj_b.inverse_mass * beta;
        }

        // Calculate impulse for velocity correction
        const vel_a = obj_a.velocity;
        const vel_b = obj_b.velocity;
        const rel_vel = Vec3f{
            vel_b[0] - vel_a[0],
            vel_b[1] - vel_a[1],
            vel_b[2] - vel_a[2],
            0.0,
        };

        // Project relative velocity onto constraint direction
        const vel_proj =
            rel_vel[0] * direction[0] +
            rel_vel[1] * direction[1] +
            rel_vel[2] * direction[2];

        const impulse = -vel_proj / mass_factor;

        // Apply impulses
        if (!obj_a.pinned) {
            obj_a.velocity[0] -= direction[0] * impulse * obj_a.inverse_mass;
            obj_a.velocity[1] -= direction[1] * impulse * obj_a.inverse_mass;
            obj_a.velocity[2] -= direction[2] * impulse * obj_a.inverse_mass;
        }

        if (!obj_b.pinned) {
            obj_b.velocity[0] += direction[0] * impulse * obj_b.inverse_mass;
            obj_b.velocity[1] += direction[1] * impulse * obj_b.inverse_mass;
            obj_b.velocity[2] += direction[2] * impulse * obj_b.inverse_mass;
        }

        // Wake up the objects
        obj_a.wake();
        obj_b.wake();
    }

    pub fn violation(self: *const DistanceConstraint, objects: []const PhysicalObject) f32 {
        const obj_a = objects[self.object_index_a];
        const obj_b = objects[self.object_index_b];

        // Calculate current length
        const delta = Vec3f{
            obj_b.position[0] - obj_a.position[0],
            obj_b.position[1] - obj_a.position[1],
            obj_b.position[2] - obj_a.position[2],
            0.0,
        };

        const current_length = @sqrt(delta[0] * delta[0] +
            delta[1] * delta[1] +
            delta[2] * delta[2]);

        // Return absolute violation
        return std.math.fabs(current_length - self.distance);
    }
};

/// PositionConstraint that pins an object to a specific world position
pub const PositionConstraint = struct {
    object_index: usize,
    target_position: Vec3f,
    stiffness: f32 = 1.0,
    active: bool = true,

    /// Solves the position constraint by directly moving the object towards the target position
    /// dt parameter is unused since this is an instantaneous correction, but kept for interface consistency
    pub fn solve(self: *PositionConstraint, objects: []PhysicalObject, dt: f32) void {
        if (!self.active) return;

        var obj = &objects[self.object_index];

        // Skip if object is pinned
        if (obj.pinned) return;

        // Calculate displacement
        const delta = Vec3f{
            self.target_position[0] - obj.position[0],
            self.target_position[1] - obj.position[1],
            self.target_position[2] - obj.position[2],
            0.0,
        };

        // Apply position correction
        obj.position[0] += delta[0] * self.stiffness;
        obj.position[1] += delta[1] * self.stiffness;
        obj.position[2] += delta[2] * self.stiffness;

        // Zero out velocity to prevent oscillation
        obj.velocity[0] = 0;
        obj.velocity[1] = 0;
        obj.velocity[2] = 0;

        // Wake up the object
        obj.wake();
    }

    pub fn violation(self: *const PositionConstraint, objects: []const PhysicalObject) f32 {
        const obj = objects[self.object_index];

        // Calculate distance from target
        const delta = Vec3f{
            self.target_position[0] - obj.position[0],
            self.target_position[1] - obj.position[1],
            self.target_position[2] - obj.position[2],
            0.0,
        };

        return @sqrt(delta[0] * delta[0] +
            delta[1] * delta[1] +
            delta[2] * delta[2]);
    }
};

/// AngleConstraint between two objects
pub const AngleConstraint = struct {
    object_index_a: usize,
    object_index_b: usize,
    target_angle: f32,
    stiffness: f32,
    active: bool = true,

    pub fn solve(self: *AngleConstraint, objects: []PhysicalObject, dt: f32) void {
        if (!self.active) return;

        var obj_a = &objects[self.object_index_a];
        var obj_b = &objects[self.object_index_b];

        // Skip if both objects are pinned
        if (obj_a.pinned and obj_b.pinned) return;

        // Get orientations
        const q_a = obj_a.orientation;
        const q_b = obj_b.orientation;

        // Calculate relative orientation
        const q_rel = q_b.multiply(q_a.conjugate());

        // Extract angle of rotation
        const angle = q_rel.getAngle();

        // Calculate angular correction
        const angle_diff = self.target_angle - angle;

        // Apply correction as torque
        const axis = q_rel.getAxis();
        const torque_magnitude = angle_diff * self.stiffness;

        // Apply torque to both objects
        if (!obj_a.pinned) {
            obj_a.angular_velocity[0] += axis[0] * torque_magnitude * dt;
            obj_a.angular_velocity[1] += axis[1] * torque_magnitude * dt;
            obj_a.angular_velocity[2] += axis[2] * torque_magnitude * dt;
        }

        if (!obj_b.pinned) {
            obj_b.angular_velocity[0] -= axis[0] * torque_magnitude * dt;
            obj_b.angular_velocity[1] -= axis[1] * torque_magnitude * dt;
            obj_b.angular_velocity[2] -= axis[2] * torque_magnitude * dt;
        }

        // Wake up the objects
        obj_a.wake();
        obj_b.wake();
    }

    pub fn violation(self: *const AngleConstraint, objects: []const PhysicalObject) f32 {
        const obj_a = objects[self.object_index_a];
        const obj_b = objects[self.object_index_b];

        // Get orientations
        const q_a = obj_a.orientation;
        const q_b = obj_b.orientation;

        // Calculate relative orientation
        const q_rel = q_b.multiply(q_a.conjugate());

        // Extract angle
        const angle = q_rel.getAngle();

        // Return absolute violation
        return std.math.fabs(angle - self.target_angle);
    }
};

/// ConstraintManager for handling various constraint types
pub const ConstraintManager = struct {
    allocator: std.mem.Allocator,
    constraints: std.ArrayList(Constraint),

    pub fn init(allocator: std.mem.Allocator) ConstraintManager {
        return ConstraintManager{
            .allocator = allocator,
            .constraints = std.ArrayList(Constraint).init(allocator),
        };
    }

    pub fn deinit(self: *ConstraintManager) void {
        self.constraints.deinit();
    }

    pub fn addSpring(self: *ConstraintManager, spring: *SpringConstraint) !void {
        try self.constraints.append(Constraint{ .Spring = spring });
    }

    pub fn addDistance(self: *ConstraintManager, distance: *DistanceConstraint) !void {
        try self.constraints.append(Constraint{ .Distance = distance });
    }

    pub fn addPosition(self: *ConstraintManager, position: *PositionConstraint) !void {
        try self.constraints.append(Constraint{ .Position = position });
    }

    pub fn addAngle(self: *ConstraintManager, angle: *AngleConstraint) !void {
        try self.constraints.append(Constraint{ .Angle = angle });
    }

    pub fn solveAll(self: *ConstraintManager, objects: []PhysicalObject, dt: f32, iterations: u32) void {
        var iter: u32 = 0;
        while (iter < iterations) : (iter += 1) {
            for (self.constraints.items) |constraint| {
                if (constraint.isActive()) {
                    constraint.apply(objects, dt);
                }
            }
        }
    }
};
