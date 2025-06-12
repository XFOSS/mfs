const std = @import("std");
const Vec3 = @import("../../math/vec3.zig").Vec3f;
const Mat4 = @import("../../math/mat4.zig").Mat4f;
const Quaternion = @import("../../math/math.zig").Quaternion(f32);

pub const Transform = struct {
    position: Vec3,
    rotation: Quaternion,
    scale: Vec3,
    local_matrix: Mat4,
    world_matrix: Mat4,
    dirty: bool,

    pub fn init() Transform {
        return Transform{
            .position = Vec3.init(0, 0, 0),
            .rotation = Quaternion.identity(),
            .scale = Vec3.init(1, 1, 1),
            .local_matrix = Mat4.identity(),
            .world_matrix = Mat4.identity(),
            .dirty = true,
        };
    }

    pub fn setPosition(self: *Transform, pos: Vec3) void {
        self.position = pos;
        self.dirty = true;
    }

    pub fn setRotation(self: *Transform, rot: Quaternion) void {
        self.rotation = rot;
        self.dirty = true;
    }

    pub fn setScale(self: *Transform, s: Vec3) void {
        self.scale = s;
        self.dirty = true;
    }

    pub fn updateMatrices(self: *Transform, parent_world: ?Mat4) void {
        if (self.dirty) {
            self.local_matrix = Mat4.fromTransform(self.position, self.rotation, self.scale);
            self.dirty = false;
        }

        self.world_matrix = if (parent_world) |parent|
            parent.multiply(self.local_matrix)
        else
            self.local_matrix;
    }

    pub fn translate(self: *Transform, delta: Vec3) void {
        self.position = self.position.add(delta);
        self.dirty = true;
    }

    pub fn rotate(self: *Transform, axis: Vec3, angle: f32) void {
        const rot = Quaternion.fromAxisAngle(axis, angle);
        self.rotation = self.rotation.multiply(rot);
        self.dirty = true;
    }

    pub fn lookAt(self: *Transform, target: Vec3, up: Vec3) void {
        const forward = target.sub(self.position).normalize();
        const right = forward.cross(up).normalize();
        const new_up = right.cross(forward);

        self.rotation = Quaternion.fromMatrix(Mat4.lookToLH(Vec3.init(0, 0, 0), forward, new_up));
        self.dirty = true;
    }
};
