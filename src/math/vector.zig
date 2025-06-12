const std = @import("std");

/// SIMD-optimized 4D vector type
pub const Vec4 = @Vector(4, f32);

/// Vector operations for physics engine
pub const Vector = struct {
    /// Create a vector from components
    pub fn new(x: f32, y: f32, z: f32, w: f32) Vec4 {
        return Vec4{ x, y, z, w };
    }

    /// Create a vector with all components set to value
    pub fn splat(value: f32) Vec4 {
        return @splat(value);
    }

    /// Calculate dot product of two vectors
    pub fn dot(a: Vec4, b: Vec4) f32 {
        const prod = a * b;
        return prod[0] + prod[1] + prod[2] + prod[3];
    }

    /// Calculate dot product using only first 3 components
    pub fn dot3(a: Vec4, b: Vec4) f32 {
        const prod = a * b;
        return prod[0] + prod[1] + prod[2];
    }

    /// Calculate cross product (only for 3D vectors)
    pub fn cross(a: Vec4, b: Vec4) Vec4 {
        return Vec4{
            a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0],
            0.0,
        };
    }

    /// Calculate length of vector
    pub fn length(v: Vec4) f32 {
        return @sqrt(dot(v, v));
    }

    /// Calculate length using only first 3 components
    pub fn length3(v: Vec4) f32 {
        return @sqrt(dot3(v, v));
    }

    /// Normalize vector to unit length
    pub fn normalize(v: Vec4) Vec4 {
        const l = length(v);
        return if (l > 0.0) v * Vector.splat(1.0 / l) else v;
    }

    /// Normalize using only first 3 components
    pub fn normalize3(v: Vec4) Vec4 {
        const l = length3(v);
        return if (l > 0.0) v * Vector.splat(1.0 / l) else v;
    }

    /// Clamp vector length to maximum value
    pub fn clampLength(v: Vec4, max_length: f32) Vec4 {
        const l = length(v);
        return if (l > max_length) v * Vector.splat(max_length / l) else v;
    }

    /// Linear interpolation between vectors
    pub fn lerp(a: Vec4, b: Vec4, t: f32) Vec4 {
        return a * Vector.splat(1.0 - t) + b * Vector.splat(t);
    }

    /// Calculate squared distance between points
    pub fn distanceSquared(a: Vec4, b: Vec4) f32 {
        const d = b - a;
        return dot(d, d);
    }

    /// Calculate distance between points
    pub fn distance(a: Vec4, b: Vec4) f32 {
        return @sqrt(distanceSquared(a, b));
    }

    /// Project vector a onto vector b
    pub fn project(a: Vec4, b: Vec4) Vec4 {
        const b_dot = dot(b, b);
        return if (b_dot > 0.0) b * Vector.splat(dot(a, b) / b_dot) else b;
    }

    /// Reflect vector around normal
    pub fn reflect(v: Vec4, normal: Vec4) Vec4 {
        return v - normal * Vector.splat(2.0 * dot(v, normal));
    }

    /// Check if vectors are approximately equal
    pub fn approxEq(a: Vec4, b: Vec4, epsilon: f32) bool {
        const diff = a - b;
        return dot(diff, diff) <= epsilon * epsilon;
    }
};

/// Quaternion type for rotations
pub const Quaternion = struct {
    x: f32,
    y: f32,
    z: f32,
    w: f32,

    /// Create identity quaternion
    pub fn identity() Quaternion {
        return Quaternion{ .x = 0, .y = 0, .z = 0, .w = 1 };
    }

    /// Create quaternion from axis and angle
    pub fn fromAxisAngle(axis: []const f32, angle: f32) Quaternion {
        const half_angle = angle * 0.5;
        const sin_half = @sin(half_angle);
        return Quaternion{
            .x = axis[0] * sin_half,
            .y = axis[1] * sin_half,
            .z = axis[2] * sin_half,
            .w = @cos(half_angle),
        };
    }

    /// Convert quaternion to axis-angle representation
    pub fn toAxisAngle(self: Quaternion) struct { axis: Vec4, angle: f32 } {
        const scale = @sqrt(self.x * self.x + self.y * self.y + self.z * self.z);
        if (scale < std.math.f32_min) {
            return .{
                .axis = Vec4{ 1, 0, 0, 0 },
                .angle = 0,
            };
        }

        return .{
            .axis = Vec4{
                self.x / scale,
                self.y / scale,
                self.z / scale,
                0,
            },
            .angle = 2.0 * std.math.acos(self.w),
        };
    }

    /// Multiply two quaternions
    pub fn multiply(a: Quaternion, b: Quaternion) Quaternion {
        return Quaternion{
            .x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
            .y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
            .z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
            .w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
        };
    }

    /// Get conjugate quaternion
    pub fn conjugate(self: Quaternion) Quaternion {
        return Quaternion{
            .x = -self.x,
            .y = -self.y,
            .z = -self.z,
            .w = self.w,
        };
    }

    /// Normalize quaternion
    pub fn normalize(self: Quaternion) Quaternion {
        const len = @sqrt(self.x * self.x + self.y * self.y + self.z * self.z + self.w * self.w);
        if (len > 0) {
            const inv_len = 1.0 / len;
            return Quaternion{
                .x = self.x * inv_len,
                .y = self.y * inv_len,
                .z = self.z * inv_len,
                .w = self.w * inv_len,
            };
        }
        return self;
    }

    /// Rotate vector by quaternion
    pub fn rotateVector(self: Quaternion, v: Vec4) Vec4 {
        const qv = Vec4{ self.x, self.y, self.z, 0 };
        const uv = Vector.cross(qv, v);
        const uuv = Vector.cross(qv, uv);
        return v + (uv * Vector.splat(2.0 * self.w) + uuv * Vector.splat(2.0));
    }

    /// Get rotation angle
    pub fn getAngle(self: Quaternion) f32 {
        return 2.0 * std.math.acos(self.w);
    }

    /// Get rotation axis
    pub fn getAxis(self: Quaternion) Vec4 {
        const scale = @sqrt(self.x * self.x + self.y * self.y + self.z * self.z);
        if (scale < std.math.f32_min) {
            return Vec4{ 1, 0, 0, 0 };
        }
        return Vec4{
            self.x / scale,
            self.y / scale,
            self.z / scale,
            0,
        };
    }
};

/// Helper function to create vector from components
pub fn vec4(x: f32, y: f32, z: f32, w: f32) Vec4 {
    return Vector.new(x, y, z, w);
}

/// Helper function to create 3D vector (w=0)
pub fn vec3(x: f32, y: f32, z: f32) Vec4 {
    return Vector.new(x, y, z, 0);
}
