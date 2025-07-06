//! Basic physics constants and utilities
//! This module provides fundamental physics constants and utility functions

const std = @import("std");
// pub const math = @import("math"); // Export math for other physics modules
// const Vec3 = math.Vec3;
// pub const Vec3f = math.Vec3f;

// Temporary placeholder types to resolve compilation
pub const Vec3f = struct {
    x: f32,
    y: f32,
    z: f32,
    pub fn init(x: f32, y: f32, z: f32) Vec3f {
        return .{ .x = x, .y = y, .z = z };
    }
    pub const zero = Vec3f{ .x = 0, .y = 0, .z = 0 };
};

pub const Quatf = struct {
    x: f32,
    y: f32,
    z: f32,
    w: f32,
    pub fn identity() Quatf {
        return .{ .x = 0, .y = 0, .z = 0, .w = 1 };
    }
};

const Vec3 = Vec3f;

/// Physics constants
pub const GRAVITY = Vec3f.init(0.0, -9.81, 0.0);
pub const AIR_DENSITY = 1.225; // kg/m³ at sea level
pub const SPEED_OF_LIGHT = 299792458.0; // m/s

/// Physics constants used by rigid body system
pub const PhysicsConstants = struct {
    pub const MAX_VELOCITY: f32 = 1000.0; // m/s
    pub const MIN_MASS: f32 = 0.001; // kg
    pub const SLEEP_THRESHOLD: f32 = 0.1;
    pub const GRAVITY: Vec3f = Vec3f.init(0.0, -9.81, 0.0);
};

/// Object types for physics simulation
pub const ObjectType = enum {
    static,
    dynamic,
    kinematic,
};

/// Basic physical object structure
pub const PhysicalObject = struct {
    position: Vec3f = Vec3f.zero,
    velocity: Vec3f = Vec3f.zero,
    orientation: Quatf = Quatf.identity(),
    angular_velocity: Vec3f = Vec3f.zero,
    mass: f32 = 1.0,
    inverse_mass: f32 = 1.0,
    pinned: bool = false,
    active: bool = true,
    object_type: ObjectType = .dynamic,

    pub fn init(position: Vec3f, mass: f32) PhysicalObject {
        return PhysicalObject{
            .position = position,
            .mass = mass,
            .inverse_mass = if (mass > 0.0) 1.0 / mass else 0.0,
        };
    }

    pub fn wake(self: *PhysicalObject) void {
        self.active = true;
    }
};

/// Physics utility functions
pub const PhysicsUtils = struct {
    /// Calculate drag force
    pub fn calculateDrag(velocity: Vec3, drag_coefficient: f32, area: f32) Vec3 {
        const speed = velocity.magnitude();
        if (speed == 0.0) return Vec3.zero();

        const drag_magnitude = 0.5 * AIR_DENSITY * drag_coefficient * area * speed * speed;
        return velocity.normalize().scale(-drag_magnitude);
    }

    /// Calculate gravitational force between two objects
    pub fn calculateGravitationalForce(mass1: f32, mass2: f32, distance: f32) f32 {
        const G = 6.67430e-11; // Gravitational constant
        return G * mass1 * mass2 / (distance * distance);
    }
};
