const std = @import("std");
// const math = @import("math");
const Vec3 = struct { x: f32, y: f32, z: f32 };
const Vec4 = struct { x: f32, y: f32, z: f32, w: f32 };
const Mat4 = struct { data: [16]f32 };

pub const CollisionShape = union(enum) {
    box: BoxShape,
    sphere: SphereShape,
    capsule: CapsuleShape,
    mesh: MeshShape,

    pub const BoxShape = struct {
        half_extents: Vec3,
    };

    pub const SphereShape = struct {
        radius: f32,
    };

    pub const CapsuleShape = struct {
        radius: f32,
        height: f32,
    };

    pub const MeshShape = struct {
        vertices: []const f32,
        indices: []const u32,
    };
};

pub const PhysicsBodyType = enum {
    Static,
    Dynamic,
    Kinematic,
};

pub const PhysicsComponent = struct {
    body_type: PhysicsBodyType,
    mass: f32,
    velocity: Vec3,
    acceleration: Vec3,
    force: Vec3,
    damping: f32,
    restitution: f32,
    friction: f32,
    collision_shape: CollisionShape,
    is_trigger: bool,
    is_sleeping: bool,
    gravity_scale: f32,
    linear_damping: f32,
    angular_damping: f32,
    angular_velocity: Vec3,
    torque: Vec3,
    inertia: Vec3,
    dirty: bool,

    pub fn init() PhysicsComponent {
        return PhysicsComponent{
            .body_type = .Dynamic,
            .mass = 1.0,
            .velocity = Vec3.init(0, 0, 0),
            .acceleration = Vec3.init(0, 0, 0),
            .force = Vec3.init(0, 0, 0),
            .damping = 0.1,
            .restitution = 0.2,
            .friction = 0.5,
            .collision_shape = CollisionShape{ .box = .{ .half_extents = Vec3.init(0.5, 0.5, 0.5) } },
            .is_trigger = false,
            .is_sleeping = false,
            .gravity_scale = 1.0,
            .linear_damping = 0.1,
            .angular_damping = 0.1,
            .angular_velocity = Vec3.init(0, 0, 0),
            .torque = Vec3.init(0, 0, 0),
            .inertia = Vec3.init(1, 1, 1),
            .dirty = true,
        };
    }

    pub fn setBodyType(self: *PhysicsComponent, body_type: PhysicsBodyType) void {
        self.body_type = body_type;
        self.dirty = true;
    }

    pub fn setMass(self: *PhysicsComponent, mass: f32) void {
        self.mass = mass;
        self.dirty = true;
    }

    pub fn setCollisionShape(self: *PhysicsComponent, shape: CollisionShape) void {
        self.collision_shape = shape;
        self.dirty = true;
    }

    pub fn applyForce(self: *PhysicsComponent, force: Vec3) void {
        self.force = self.force.add(force);
        self.is_sleeping = false;
    }

    pub fn applyImpulse(self: *PhysicsComponent, impulse: Vec3) void {
        self.velocity = self.velocity.add(impulse.scale(1.0 / self.mass));
        self.is_sleeping = false;
    }

    pub fn applyTorque(self: *PhysicsComponent, torque: Vec3) void {
        self.torque = self.torque.add(torque);
        self.is_sleeping = false;
    }

    pub fn clearForces(self: *PhysicsComponent) void {
        self.force = Vec3.init(0, 0, 0);
        self.torque = Vec3.init(0, 0, 0);
    }

    pub fn update(self: *PhysicsComponent, delta_time: f32, gravity: Vec3) void {
        if (self.body_type != .Dynamic or self.is_sleeping) return;

        // Apply gravity
        if (self.gravity_scale != 0) {
            self.force = self.force.add(gravity.scale(self.mass * self.gravity_scale));
        }

        // Update velocity
        self.acceleration = self.force.scale(1.0 / self.mass);
        self.velocity = self.velocity.add(self.acceleration.scale(delta_time));

        // Apply damping
        const damping_factor = std.math.pow(f32, self.linear_damping, delta_time);
        self.velocity = self.velocity.scale(damping_factor);

        // Update angular velocity
        const angular_acceleration = self.torque.scale(1.0 / self.mass);
        self.angular_velocity = self.angular_velocity.add(angular_acceleration.scale(delta_time));

        // Apply angular damping
        const angular_damping_factor = std.math.pow(f32, self.angular_damping, delta_time);
        self.angular_velocity = self.angular_velocity.scale(angular_damping_factor);

        // Clear forces
        self.clearForces();

        // Check if body should sleep
        const velocity_squared = self.velocity.lengthSquared();
        const angular_velocity_squared = self.angular_velocity.lengthSquared();
        if (velocity_squared < 0.01 and angular_velocity_squared < 0.01) {
            self.is_sleeping = true;
        }
    }
};
