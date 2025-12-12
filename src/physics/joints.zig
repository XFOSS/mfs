const std = @import("std");

const math = @import("../math/mod.zig");
const Vec4 = math.Vec4;
const Vector = math.Vector;
const Quaternion = math.Quaternion;
const physics_engine = @import("physics_engine.zig");
const PhysicalObject = physics_engine.PhysicalObject;

/// Joint types
pub const JointType = enum {
    Fixed,
    Hinge,
    Slider,
    Ball,
    Universal,
    SixDOF,
};

/// Base joint structure
pub const Joint = union(JointType) {
    Fixed: FixedJoint,
    Hinge: HingeJoint,
    Slider: SliderJoint,
    Ball: BallJoint,
    Universal: UniversalJoint,
    SixDOF: SixDofJoint,

    /// Apply the joint constraint
    pub fn solve(self: *Joint, objects: []PhysicalObject, dt: f32) void {
        switch (self.*) {
            inline else => |*joint| joint.solve(objects, dt),
        }
    }
};

/// Constraint properties shared by all joints
pub const JointProps = struct {
    body_a: usize,
    body_b: usize,
    local_anchor_a: Vec4,
    local_anchor_b: Vec4,
    breaking_force: f32 = std.math.inf(f32),
    active: bool = true,
};

/// Fixed joint that maintains a fixed relative position and orientation
pub const FixedJoint = struct {
    props: JointProps,
    ref_orientation: Quaternion,
    ref_position: Vec4,

    pub fn init(body_a: usize, body_b: usize, anchor_a: Vec4, anchor_b: Vec4) FixedJoint {
        return FixedJoint{
            .props = JointProps{
                .body_a = body_a,
                .body_b = body_b,
                .local_anchor_a = anchor_a,
                .local_anchor_b = anchor_b,
            },
            .ref_orientation = Quaternion.identity(),
            .ref_position = Vec4{ 0, 0, 0, 0 },
        };
    }

    pub fn initRelative(objects: []PhysicalObject, body_a: usize, body_b: usize) FixedJoint {
        const obj_a = &objects[body_a];
        const obj_b = &objects[body_b];

        // Store relative transform from A to B as reference
        const rel_orientation = Quaternion.multiply(obj_b.orientation, obj_a.orientation.conjugate());
        const rel_position = obj_b.position - obj_a.position;

        return FixedJoint{
            .props = JointProps{
                .body_a = body_a,
                .body_b = body_b,
                .local_anchor_a = Vec4{ 0, 0, 0, 0 },
                .local_anchor_b = Vec4{ 0, 0, 0, 0 },
            },
            .ref_orientation = rel_orientation,
            .ref_position = rel_position,
        };
    }

    pub fn solve(self: *FixedJoint, objects: []PhysicalObject, _dt: f32) void {
        _ = _dt; // autofix
        if (!self.props.active) return;

        var obj_a = &objects[self.props.body_a];
        var obj_b = &objects[self.props.body_b];

        if (obj_a.pinned and obj_b.pinned) return;

        // Position constraint
        const target_pos = obj_a.position + self.ref_position;
        const pos_delta = target_pos - obj_b.position;

        // Orientation constraint
        const target_orientation = Quaternion.multiply(obj_a.orientation, self.ref_orientation);
        const orientation_delta = Quaternion.multiply(target_orientation, obj_b.orientation.conjugate());

        // Apply position correction
        if (!obj_a.pinned and !obj_b.pinned) {
            // Share correction between both bodies
            obj_a.position -= pos_delta * Vector.splat(0.5);
            obj_b.position += pos_delta * Vector.splat(0.5);
        } else if (!obj_a.pinned) {
            obj_a.position -= pos_delta;
        } else if (!obj_b.pinned) {
            obj_b.position += pos_delta;
        }

        // Apply orientation correction
        if (orientation_delta.w < 0.99999) {
            const axis = Vec4{
                orientation_delta.x,
                orientation_delta.y,
                orientation_delta.z,
                0,
            };
            const angle = 2.0 * std.math.acos(orientation_delta.w);
            const angular_correction = axis * Vector.splat(angle * 0.1);

            if (!obj_a.pinned and !obj_b.pinned) {
                obj_a.angular_velocity -= angular_correction * Vector.splat(0.5);
                obj_b.angular_velocity += angular_correction * Vector.splat(0.5);
            } else if (!obj_a.pinned) {
                obj_a.angular_velocity -= angular_correction;
            } else if (!obj_b.pinned) {
                obj_b.angular_velocity += angular_correction;
            }
        }

        // Wake both objects
        obj_a.wake();
        obj_b.wake();
    }
};

/// Hinge joint that allows rotation around a single axis
pub const HingeJoint = struct {
    props: JointProps,
    local_axis_a: Vec4,
    local_axis_b: Vec4,
    min_angle: f32 = -std.math.pi,
    max_angle: f32 = std.math.pi,

    pub fn init(
        body_a: usize,
        body_b: usize,
        anchor_a: Vec4,
        anchor_b: Vec4,
        axis_a: Vec4,
        axis_b: Vec4,
    ) HingeJoint {
        return HingeJoint{
            .props = JointProps{
                .body_a = body_a,
                .body_b = body_b,
                .local_anchor_a = anchor_a,
                .local_anchor_b = anchor_b,
            },
            .local_axis_a = Vector.normalize3(axis_a),
            .local_axis_b = Vector.normalize3(axis_b),
        };
    }

    pub fn solve(self: *HingeJoint, objects: []PhysicalObject, _dt: f32) void {
        _ = _dt; // autofix
        if (!self.props.active) return;

        var obj_a = &objects[self.props.body_a];
        var obj_b = &objects[self.props.body_b];

        if (obj_a.pinned and obj_b.pinned) return;

        // Transform local points to world space
        const anchor_a_world = obj_a.position +
            obj_a.orientation.rotateVector(self.props.local_anchor_a);
        const anchor_b_world = obj_b.position +
            obj_b.orientation.rotateVector(self.props.local_anchor_b);

        // Transform local axes to world space
        const axis_a_world = obj_a.orientation.rotateVector(self.local_axis_a);
        const axis_b_world = obj_b.orientation.rotateVector(self.local_axis_b);

        // Position constraint - make anchor points coincide
        const pos_delta = anchor_b_world - anchor_a_world;

        // Apply position correction
        if (!obj_a.pinned and !obj_b.pinned) {
            // Share correction between both bodies
            obj_a.position += pos_delta * Vector.splat(0.5);
            obj_b.position -= pos_delta * Vector.splat(0.5);
        } else if (!obj_a.pinned) {
            obj_a.position += pos_delta;
        } else if (!obj_b.pinned) {
            obj_b.position -= pos_delta;
        }

        // Rotation constraint - align axes
        const cross = Vector.cross(axis_a_world, axis_b_world);
        const correction_torque = cross * Vector.splat(0.1);

        if (!obj_a.pinned and !obj_b.pinned) {
            obj_a.angular_velocity += correction_torque * Vector.splat(0.5);
            obj_b.angular_velocity -= correction_torque * Vector.splat(0.5);
        } else if (!obj_a.pinned) {
            obj_a.angular_velocity += correction_torque;
        } else if (!obj_b.pinned) {
            obj_b.angular_velocity -= correction_torque;
        }

        // Wake both objects
        obj_a.wake();
        obj_b.wake();
    }
};

/// Slider joint that allows movement along a single axis
pub const SliderJoint = struct {
    props: JointProps,
    local_axis: Vec4,
    min_dist: f32 = -std.math.inf(f32),
    max_dist: f32 = std.math.inf(f32),

    pub fn init(
        body_a: usize,
        body_b: usize,
        anchor_a: Vec4,
        anchor_b: Vec4,
        axis: Vec4,
    ) SliderJoint {
        return SliderJoint{
            .props = JointProps{
                .body_a = body_a,
                .body_b = body_b,
                .local_anchor_a = anchor_a,
                .local_anchor_b = anchor_b,
            },
            .local_axis = Vector.normalize3(axis),
        };
    }

    pub fn solve(self: *SliderJoint, objects: []PhysicalObject, _dt: f32) void {
        _ = _dt; // autofix
        if (!self.props.active) return;

        var obj_a = &objects[self.props.body_a];
        var obj_b = &objects[self.props.body_b];

        if (obj_a.pinned and obj_b.pinned) return;

        // Transform local points to world space
        const anchor_a_world = obj_a.position +
            obj_a.orientation.rotateVector(self.props.local_anchor_a);
        const anchor_b_world = obj_b.position +
            obj_b.orientation.rotateVector(self.props.local_anchor_b);

        // Transform local axis to world space
        const axis_world = obj_a.orientation.rotateVector(self.local_axis);

        // Position delta between anchors
        const delta = anchor_b_world - anchor_a_world;

        // Project delta onto axis to get slide distance
        const dist_along_axis = Vector.dot3(delta, axis_world);

        // Calculate rejection (perpendicular component)
        const rejection = delta - axis_world * Vector.splat(dist_along_axis);

        // Apply position correction for perpendicular component
        if (Vector.length3(rejection) > 0.0001) {
            if (!obj_a.pinned and !obj_b.pinned) {
                obj_a.position += rejection * Vector.splat(0.5);
                obj_b.position -= rejection * Vector.splat(0.5);
            } else if (!obj_a.pinned) {
                obj_a.position += rejection;
            } else if (!obj_b.pinned) {
                obj_b.position -= rejection;
            }
        }

        // Enforce min/max distance along axis
        if (dist_along_axis < self.min_dist or dist_along_axis > self.max_dist) {
            const clamped_dist = @max(self.min_dist, @min(dist_along_axis, self.max_dist));
            const correction = axis_world * Vector.splat(dist_along_axis - clamped_dist);

            if (!obj_a.pinned and !obj_b.pinned) {
                obj_a.position += correction * Vector.splat(0.5);
                obj_b.position -= correction * Vector.splat(0.5);
            } else if (!obj_a.pinned) {
                obj_a.position += correction;
            } else if (!obj_b.pinned) {
                obj_b.position -= correction;
            }
        }

        // Wake both objects
        obj_a.wake();
        obj_b.wake();
    }
};

/// Ball and socket joint that allows rotation in all directions
pub const BallJoint = struct {
    props: JointProps,

    pub fn init(body_a: usize, body_b: usize, anchor_a: Vec4, anchor_b: Vec4) BallJoint {
        return BallJoint{
            .props = JointProps{
                .body_a = body_a,
                .body_b = body_b,
                .local_anchor_a = anchor_a,
                .local_anchor_b = anchor_b,
            },
        };
    }

    pub fn solve(self: *BallJoint, objects: []PhysicalObject, _dt: f32) void {
        _ = _dt; // autofix
        if (!self.props.active) return;

        var obj_a = &objects[self.props.body_a];
        var obj_b = &objects[self.props.body_b];

        if (obj_a.pinned and obj_b.pinned) return;

        // Transform local points to world space
        const anchor_a_world = obj_a.position +
            obj_a.orientation.rotateVector(self.props.local_anchor_a);
        const anchor_b_world = obj_b.position +
            obj_b.orientation.rotateVector(self.props.local_anchor_b);

        // Position constraint - make anchor points coincide
        const pos_delta = anchor_b_world - anchor_a_world;

        // Apply position correction
        if (!obj_a.pinned and !obj_b.pinned) {
            obj_a.position += pos_delta * Vector.splat(0.5);
            obj_b.position -= pos_delta * Vector.splat(0.5);
        } else if (!obj_a.pinned) {
            obj_a.position += pos_delta;
        } else if (!obj_b.pinned) {
            obj_b.position -= pos_delta;
        }

        // Wake both objects
        obj_a.wake();
        obj_b.wake();
    }
};

/// Universal joint that allows rotation around two perpendicular axes
pub const UniversalJoint = struct {
    props: JointProps,
    local_axis1: Vec4,
    local_axis2: Vec4,

    pub fn init(
        body_a: usize,
        body_b: usize,
        anchor_a: Vec4,
        anchor_b: Vec4,
        axis1: Vec4,
        axis2: Vec4,
    ) UniversalJoint {
        return UniversalJoint{
            .props = JointProps{
                .body_a = body_a,
                .body_b = body_b,
                .local_anchor_a = anchor_a,
                .local_anchor_b = anchor_b,
            },
            .local_axis1 = Vector.normalize3(axis1),
            .local_axis2 = Vector.normalize3(axis2),
        };
    }

    pub fn solve(self: *UniversalJoint, objects: []PhysicalObject, _dt: f32) void {
        _ = _dt; // autofix
        if (!self.props.active) return;

        var obj_a = &objects[self.props.body_a];
        var obj_b = &objects[self.props.body_b];

        if (obj_a.pinned and obj_b.pinned) return;

        // Transform local points to world space
        const anchor_a_world = obj_a.position +
            obj_a.orientation.rotateVector(self.props.local_anchor_a);
        const anchor_b_world = obj_b.position +
            obj_b.orientation.rotateVector(self.props.local_anchor_b);

        // Position constraint
        const pos_delta = anchor_b_world - anchor_a_world;

        // Apply position correction
        if (!obj_a.pinned and !obj_b.pinned) {
            obj_a.position += pos_delta * Vector.splat(0.5);
            obj_b.position -= pos_delta * Vector.splat(0.5);
        } else if (!obj_a.pinned) {
            obj_a.position += pos_delta;
        } else if (!obj_b.pinned) {
            obj_b.position -= pos_delta;
        }

        // Wake both objects
        obj_a.wake();
        obj_b.wake();
    }
};

/// Six Degrees of Freedom (6DOF) joint with configurable constraints
pub const SixDofJoint = struct {
    props: JointProps,
    linear_limits: [3]struct { min: f32, max: f32 } = .{
        .{ .min = 0, .max = 0 },
        .{ .min = 0, .max = 0 },
        .{ .min = 0, .max = 0 },
    },
    angular_limits: [3]struct { min: f32, max: f32 } = .{
        .{ .min = -std.math.pi, .max = std.math.pi },
        .{ .min = -std.math.pi, .max = std.math.pi },
        .{ .min = -std.math.pi, .max = std.math.pi },
    },

    pub fn init(body_a: usize, body_b: usize, anchor_a: Vec4, anchor_b: Vec4) SixDofJoint {
        return SixDofJoint{
            .props = JointProps{
                .body_a = body_a,
                .body_b = body_b,
                .local_anchor_a = anchor_a,
                .local_anchor_b = anchor_b,
            },
        };
    }

    pub fn solve(self: *SixDofJoint, objects: []PhysicalObject, _dt: f32) void {
        _ = _dt; // autofix
        if (!self.props.active) return;

        var obj_a = &objects[self.props.body_a];
        var obj_b = &objects[self.props.body_b];

        if (obj_a.pinned and obj_b.pinned) return;

        // Transform local points to world space
        const anchor_a_world = obj_a.position +
            obj_a.orientation.rotateVector(self.props.local_anchor_a);
        const anchor_b_world = obj_b.position +
            obj_b.orientation.rotateVector(self.props.local_anchor_b);

        // Basic implementation for now - just maintain anchor points
        const pos_delta = anchor_b_world - anchor_a_world;

        // Apply position correction
        if (!obj_a.pinned and !obj_b.pinned) {
            obj_a.position += pos_delta * Vector.splat(0.5);
            obj_b.position -= pos_delta * Vector.splat(0.5);
        } else if (!obj_a.pinned) {
            obj_a.position += pos_delta;
        } else if (!obj_b.pinned) {
            obj_b.position -= pos_delta;
        }

        // Wake both objects
        obj_a.wake();
        obj_b.wake();
    }
};

/// Joint manager for handling collections of joints
pub const JointManager = struct {
    allocator: std.mem.Allocator,
    joints: std.ArrayList(*Joint),

    pub fn init(allocator: std.mem.Allocator) JointManager {
        return JointManager{
            .allocator = allocator,
            .joints = std.ArrayList(*Joint).init(allocator),
        };
    }

    pub fn deinit(self: *JointManager) void {
        for (self.joints.items) |joint| {
            self.allocator.destroy(joint);
        }
        self.joints.deinit();
    }

    pub fn addJoint(self: *JointManager, joint: *Joint) !void {
        try self.joints.append(joint);
    }

    pub fn removeJoint(self: *JointManager, joint: *Joint) void {
        for (self.joints.items, 0..) |j, i| {
            if (j == joint) {
                _ = self.joints.swapRemove(i);
                self.allocator.destroy(joint);
                return;
            }
        }
    }

    pub fn solveAll(self: *JointManager, objects: []PhysicalObject, dt: f32) void {
        for (self.joints.items) |joint| {
            joint.solve(objects, dt);
        }
    }
};
