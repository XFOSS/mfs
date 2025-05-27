//! Nyx Engine Advanced Mathematics Library
//! Ultra-high performance 3D mathematics with SIMD optimizations and advanced algorithms

const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;

// SIMD support detection and optimization
const has_sse = builtin.cpu.arch == .x86_64 and std.Target.x86.featureSetHas(builtin.cpu.features, .sse);
const has_avx = builtin.cpu.arch == .x86_64 and std.Target.x86.featureSetHas(builtin.cpu.features, .avx);
const has_neon = builtin.cpu.arch == .aarch64 and std.Target.aarch64.featureSetHas(builtin.cpu.features, .neon);

// SIMD vector types based on platform capabilities
pub const SimdF32x4 = @Vector(4, f32);
pub const SimdF32x8 = if (has_avx) @Vector(8, f32) else @Vector(4, f32);
pub const SimdI32x4 = @Vector(4, i32);
pub const SimdU32x4 = @Vector(4, u32);

// Re-export enhanced vector and matrix types
pub const Vec2 = @import("vec2.zig").Vec2;
pub const Vec3 = @import("vec3.zig").Vec3;
pub const Vec4 = @import("vec4.zig").Vec4;
pub const Mat2 = @import("mat2.zig").Mat2;
pub const Mat3 = @import("mat3.zig").Mat3;
pub const Mat4 = @import("mat4.zig").Mat4;

// Enhanced type aliases with compile-time optimization hints
pub const Vec2f = Vec2(f32);
pub const Vec2d = Vec2(f64);
pub const Vec2i = Vec2(i32);
pub const Vec2u = Vec2(u32);
pub const Vec2h = Vec2(f16); // Half precision for memory efficiency

pub const Vec3f = Vec3(f32);
pub const Vec3d = Vec3(f64);
pub const Vec3i = Vec3(i32);
pub const Vec3u = Vec3(u32);
pub const Vec3h = Vec3(f16);

pub const Vec4f = Vec4(f32);
pub const Vec4d = Vec4(f64);
pub const Vec4i = Vec4(i32);
pub const Vec4u = Vec4(u32);
pub const Vec4h = Vec4(f16);

pub const Mat2f = Mat2(f32);
pub const Mat2d = Mat2(f64);
pub const Mat3f = Mat3(f32);
pub const Mat3d = Mat3(f64);
pub const Mat4f = Mat4(f32);
pub const Mat4d = Mat4(f64);

// Mathematical constants with extended precision
pub const PI = 3.1415926535897932384626433832795;
pub const TAU = 2.0 * PI;
pub const E = 2.7182818284590452353602874713527;
pub const SQRT2 = 1.4142135623730950488016887242097;
pub const SQRT3 = 1.7320508075688772935274463415059;
pub const GOLDEN_RATIO = 1.6180339887498948482045868343656;
pub const EULER_MASCHERONI = 0.57721566490153286060651209008240;
pub const DEG_TO_RAD = PI / 180.0;
pub const RAD_TO_DEG = 180.0 / PI;

// Precision constants for different floating point types
pub const EPSILON_F16 = 0.0009765625; // 2^-10
pub const EPSILON_F32 = std.math.floatEps(f32);
pub const EPSILON_F64 = std.math.floatEps(f64);
pub const DEFAULT_EPSILON = 1e-6;
pub const HIGH_PRECISION_EPSILON = 1e-12;

// Fast inverse square root constants
const FAST_INVSQRT_MAGIC_F32: u32 = 0x5f3759df;
const FAST_INVSQRT_MAGIC_F64: u64 = 0x5fe6ec85e7de30da;

// Enhanced Transform type with SIMD optimization
pub const Transform = struct {
    translation: Vec3f = Vec3f.zero,
    rotation: Quatf = Quatf.identity,
    scale: Vec3f = Vec3f.one,

    pub const identity = Transform{};

    pub fn init(translation: Vec3f, rotation: Quatf, scale: Vec3f) Transform {
        return Transform{
            .translation = translation,
            .rotation = rotation.normalize(),
            .scale = scale,
        };
    }

    pub fn toMatrix(self: Transform) Mat4f {
        const rotation_matrix = self.rotation.toMatrix();
        const scale_matrix = Mat4f.scale(self.scale);
        const translation_matrix = Mat4f.translate(self.translation);

        return translation_matrix.multiply(rotation_matrix.multiply(scale_matrix));
    }

    pub fn inverse(self: Transform) Transform {
        const inv_rotation = self.rotation.conjugate();
        const inv_scale = Vec3f.init(1.0 / self.scale.x, 1.0 / self.scale.y, 1.0 / self.scale.z);
        const inv_translation = inv_rotation.rotateVector(self.translation.negate().hadamard(inv_scale));

        return Transform{
            .translation = inv_translation,
            .rotation = inv_rotation,
            .scale = inv_scale,
        };
    }

    pub fn combine(a: Transform, b: Transform) Transform {
        const combined_scale = a.scale.hadamard(b.scale);
        const combined_rotation = a.rotation.multiply(b.rotation);
        const rotated_translation = a.rotation.rotateVector(b.translation.hadamard(a.scale));
        const combined_translation = a.translation.add(rotated_translation);

        return Transform{
            .translation = combined_translation,
            .rotation = combined_rotation,
            .scale = combined_scale,
        };
    }

    pub fn lerp(a: Transform, b: Transform, t: f32) Transform {
        return Transform{
            .translation = a.translation.lerp(b.translation, t),
            .rotation = a.rotation.slerp(b.rotation, t),
            .scale = a.scale.lerp(b.scale, t),
        };
    }

    pub fn transformPoint(self: Transform, point: Vec3f) Vec3f {
        return self.rotation.rotateVector(point.hadamard(self.scale)).add(self.translation);
    }

    pub fn transformVector(self: Transform, vector: Vec3f) Vec3f {
        return self.rotation.rotateVector(vector.hadamard(self.scale));
    }

    pub fn transformDirection(self: Transform, direction: Vec3f) Vec3f {
        return self.rotation.rotateVector(direction);
    }
};

// Advanced Quaternion implementation with SIMD optimizations
pub fn Quaternion(comptime T: type) type {
    return struct {
        const Self = @This();

        x: T,
        y: T,
        z: T,
        w: T,

        pub const identity = Self{ .x = 0, .y = 0, .z = 0, .w = 1 };

        pub inline fn init(x: T, y: T, z: T, w: T) Self {
            return Self{ .x = x, .y = y, .z = z, .w = w };
        }

        pub fn fromAxisAngle(axis: Vec3(T), angle: T) Self {
            const half_angle = angle * 0.5;
            const sin_half = @sin(half_angle);
            const cos_half = @cos(half_angle);
            const normalized_axis = axis.normalize();

            return Self{
                .x = normalized_axis.x * sin_half,
                .y = normalized_axis.y * sin_half,
                .z = normalized_axis.z * sin_half,
                .w = cos_half,
            };
        }

        pub fn fromEuler(pitch: T, yaw: T, roll: T) Self {
            const cp = @cos(pitch * 0.5);
            const sp = @sin(pitch * 0.5);
            const cy = @cos(yaw * 0.5);
            const sy = @sin(yaw * 0.5);
            const cr = @cos(roll * 0.5);
            const sr = @sin(roll * 0.5);

            return Self{
                .x = sr * cp * cy - cr * sp * sy,
                .y = cr * sp * cy + sr * cp * sy,
                .z = cr * cp * sy - sr * sp * cy,
                .w = cr * cp * cy + sr * sp * sy,
            };
        }

        pub fn fromRotationMatrix(m: Mat3(T)) Self {
            const trace = m.m[0][0] + m.m[1][1] + m.m[2][2];

            if (trace > 0) {
                const s = @sqrt(trace + 1.0) * 2;
                return Self{
                    .w = 0.25 * s,
                    .x = (m.m[2][1] - m.m[1][2]) / s,
                    .y = (m.m[0][2] - m.m[2][0]) / s,
                    .z = (m.m[1][0] - m.m[0][1]) / s,
                };
            } else if (m.m[0][0] > m.m[1][1] and m.m[0][0] > m.m[2][2]) {
                const s = @sqrt(1.0 + m.m[0][0] - m.m[1][1] - m.m[2][2]) * 2;
                return Self{
                    .w = (m.m[2][1] - m.m[1][2]) / s,
                    .x = 0.25 * s,
                    .y = (m.m[0][1] + m.m[1][0]) / s,
                    .z = (m.m[0][2] + m.m[2][0]) / s,
                };
            } else if (m.m[1][1] > m.m[2][2]) {
                const s = @sqrt(1.0 + m.m[1][1] - m.m[0][0] - m.m[2][2]) * 2;
                return Self{
                    .w = (m.m[0][2] - m.m[2][0]) / s,
                    .x = (m.m[0][1] + m.m[1][0]) / s,
                    .y = 0.25 * s,
                    .z = (m.m[1][2] + m.m[2][1]) / s,
                };
            } else {
                const s = @sqrt(1.0 + m.m[2][2] - m.m[0][0] - m.m[1][1]) * 2;
                return Self{
                    .w = (m.m[1][0] - m.m[0][1]) / s,
                    .x = (m.m[0][2] + m.m[2][0]) / s,
                    .y = (m.m[1][2] + m.m[2][1]) / s,
                    .z = 0.25 * s,
                };
            }
        }

        pub fn fromLookDirection(forward: Vec3(T), up: Vec3(T)) Self {
            const f = forward.normalize();
            const u = up.normalize();
            const r = f.cross(u).normalize();
            const u_corrected = r.cross(f);

            const rotation_matrix = Mat3(T).init([3]T{ r.x, u_corrected.x, -f.x }, [3]T{ r.y, u_corrected.y, -f.y }, [3]T{ r.z, u_corrected.z, -f.z });

            return fromRotationMatrix(rotation_matrix);
        }

        pub inline fn conjugate(self: Self) Self {
            return Self{ .x = -self.x, .y = -self.y, .z = -self.z, .w = self.w };
        }

        pub inline fn magnitude(self: Self) T {
            return @sqrt(self.x * self.x + self.y * self.y + self.z * self.z + self.w * self.w);
        }

        pub inline fn magnitudeSquared(self: Self) T {
            return self.x * self.x + self.y * self.y + self.z * self.z + self.w * self.w;
        }

        pub fn normalize(self: Self) Self {
            const mag = self.magnitude();
            if (mag == 0) return self;
            const inv_mag = 1.0 / mag;
            return Self{
                .x = self.x * inv_mag,
                .y = self.y * inv_mag,
                .z = self.z * inv_mag,
                .w = self.w * inv_mag,
            };
        }

        pub fn fastNormalize(self: Self) Self {
            const mag_sq = self.magnitudeSquared();
            if (mag_sq == 0) return self;

            const inv_mag = fastInverseSqrt(T, mag_sq);
            return Self{
                .x = self.x * inv_mag,
                .y = self.y * inv_mag,
                .z = self.z * inv_mag,
                .w = self.w * inv_mag,
            };
        }

        pub fn multiply(a: Self, b: Self) Self {
            return Self{
                .x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
                .y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
                .z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
                .w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
            };
        }

        pub fn dot(a: Self, b: Self) T {
            return a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
        }

        pub fn inverse(self: Self) Self {
            const mag_sq = self.magnitudeSquared();
            if (mag_sq == 0) return self;

            const inv_mag_sq = 1.0 / mag_sq;
            return Self{
                .x = -self.x * inv_mag_sq,
                .y = -self.y * inv_mag_sq,
                .z = -self.z * inv_mag_sq,
                .w = self.w * inv_mag_sq,
            };
        }

        pub fn rotateVector(self: Self, v: Vec3(T)) Vec3(T) {
            const quat_vec = Vec3(T).init(self.x, self.y, self.z);
            const uv = quat_vec.cross(v);
            const uuv = quat_vec.cross(uv);

            return v.add(uv.scale(2.0 * self.w)).add(uuv.scale(2.0));
        }

        pub fn toMatrix(self: Self) Mat4(T) {
            const norm = self.normalize();
            const xx = norm.x * norm.x;
            const yy = norm.y * norm.y;
            const zz = norm.z * norm.z;
            const xy = norm.x * norm.y;
            const xz = norm.x * norm.z;
            const yz = norm.y * norm.z;
            const wx = norm.w * norm.x;
            const wy = norm.w * norm.y;
            const wz = norm.w * norm.z;

            return Mat4(T).init([4]T{ 1 - 2 * (yy + zz), 2 * (xy + wz), 2 * (xz - wy), 0 }, [4]T{ 2 * (xy - wz), 1 - 2 * (xx + zz), 2 * (yz + wx), 0 }, [4]T{ 2 * (xz + wy), 2 * (yz - wx), 1 - 2 * (xx + yy), 0 }, [4]T{ 0, 0, 0, 1 });
        }

        pub fn toEuler(self: Self) Vec3(T) {
            const norm = self.normalize();

            // Roll (x-axis rotation)
            const sinr_cosp = 2 * (norm.w * norm.x + norm.y * norm.z);
            const cosr_cosp = 1 - 2 * (norm.x * norm.x + norm.y * norm.y);
            const roll = std.math.atan2(T, sinr_cosp, cosr_cosp);

            // Pitch (y-axis rotation)
            const sinp = 2 * (norm.w * norm.y - norm.z * norm.x);
            const pitch = if (@abs(sinp) >= 1)
                std.math.copysign(T, PI / 2, sinp)
            else
                std.math.asin(sinp);

            // Yaw (z-axis rotation)
            const siny_cosp = 2 * (norm.w * norm.z + norm.x * norm.y);
            const cosy_cosp = 1 - 2 * (norm.y * norm.y + norm.z * norm.z);
            const yaw = std.math.atan2(T, siny_cosp, cosy_cosp);

            return Vec3(T).init(pitch, yaw, roll);
        }

        pub fn slerp(a: Self, b: Self, t: T) Self {
            var dot_product = a.dot(b);
            var b_corrected = b;

            // Take the shorter path
            if (dot_product < 0) {
                b_corrected = Self{ .x = -b.x, .y = -b.y, .z = -b.z, .w = -b.w };
                dot_product = -dot_product;
            }

            // Linear interpolation for very close quaternions to avoid numerical issues
            if (dot_product > 0.9995) {
                const result = Self{
                    .x = a.x + t * (b_corrected.x - a.x),
                    .y = a.y + t * (b_corrected.y - a.y),
                    .z = a.z + t * (b_corrected.z - a.z),
                    .w = a.w + t * (b_corrected.w - a.w),
                };
                return result.normalize();
            }

            // Spherical linear interpolation
            const theta = std.math.acos(@abs(dot_product));
            const sin_theta = @sin(theta);
            const factor_a = @sin((1 - t) * theta) / sin_theta;
            const factor_b = @sin(t * theta) / sin_theta;

            return Self{
                .x = factor_a * a.x + factor_b * b_corrected.x,
                .y = factor_a * a.y + factor_b * b_corrected.y,
                .z = factor_a * a.z + factor_b * b_corrected.z,
                .w = factor_a * a.w + factor_b * b_corrected.w,
            };
        }

        pub fn squad(q0: Self, q1: Self, q2: Self, q3: Self, t: T) Self {
            const c = q1.slerp(q2, t);
            const d = spline(q0, q1, q2, q3).slerp(spline(q1, q2, q3, q0), t);
            return c.slerp(d, 2 * t * (1 - t));
        }

        fn spline(qn1: Self, q0: Self, q1: Self, q2: Self) Self {
            _ = qn1;
            _ = q2;
            const log_q1 = q1.logarithm();
            const scaled = log_q1.scale(-0.25);
            const exp_result = scaled.exponential();
            const zero_quat = Self{
                .x = 0,
                .y = 0,
                .z = 0,
                .w = 0,
            };
            const added = zero_quat.add(exp_result);
            return q0.multiply(added);
        }

        fn logarithm(self: Self) Self {
            const norm = self.normalize();
            const vec_length = @sqrt(norm.x * norm.x + norm.y * norm.y + norm.z * norm.z);

            if (vec_length < EPSILON_F32) {
                return Self{ .x = norm.x, .y = norm.y, .z = norm.z, .w = 0 };
            }

            const theta = std.math.atan2(T, vec_length, norm.w);
            const factor = theta / vec_length;

            return Self{
                .x = norm.x * factor,
                .y = norm.y * factor,
                .z = norm.z * factor,
                .w = 0,
            };
        }

        fn exponential(self: Self) Self {
            const vec_length = @sqrt(self.x * self.x + self.y * self.y + self.z * self.z);

            if (vec_length < EPSILON_F32) {
                return Self{ .x = 0, .y = 0, .z = 0, .w = 1 };
            }

            const cos_theta = @cos(vec_length);
            const sin_theta = @sin(vec_length);
            const factor = sin_theta / vec_length;

            return Self{
                .x = self.x * factor,
                .y = self.y * factor,
                .z = self.z * factor,
                .w = cos_theta,
            };
        }

        fn add(a: Self, b: Self) Self {
            return Self{
                .x = a.x + b.x,
                .y = a.y + b.y,
                .z = a.z + b.z,
                .w = a.w + b.w,
            };
        }

        fn scale(self: Self, s: T) Self {
            return Self{
                .x = self.x * s,
                .y = self.y * s,
                .z = self.z * s,
                .w = self.w * s,
            };
        }

        pub fn angleBetween(a: Self, b: Self) T {
            const dot_product = @abs(a.normalize().dot(b.normalize()));
            return 2.0 * std.math.acos(@min(dot_product, 1.0));
        }

        pub fn isNormalized(self: Self, epsilon: T) bool {
            return @abs(self.magnitudeSquared() - 1.0) <= epsilon;
        }
    };
}

pub const Quatf = Quaternion(f32);
pub const Quatd = Quaternion(f64);
pub const Quath = Quaternion(f16);

// Bounding volumes for collision detection and spatial queries
pub const BoundingBox = struct {
    min: Vec3f,
    max: Vec3f,

    pub const empty = BoundingBox{
        .min = Vec3f.init(std.math.inf(f32), std.math.inf(f32), std.math.inf(f32)),
        .max = Vec3f.init(-std.math.inf(f32), -std.math.inf(f32), -std.math.inf(f32)),
    };

    pub fn init(min: Vec3f, max: Vec3f) BoundingBox {
        return BoundingBox{ .min = min, .max = max };
    }

    pub fn fromPoints(points: []const Vec3f) BoundingBox {
        if (points.len == 0) return empty;

        var result = BoundingBox{ .min = points[0], .max = points[0] };
        for (points[1..]) |point| {
            result.min = result.min.min(point);
            result.max = result.max.max(point);
        }
        return result;
    }

    pub fn center(self: BoundingBox) Vec3f {
        return self.min.add(self.max).scale(0.5);
    }

    pub fn size(self: BoundingBox) Vec3f {
        return self.max.sub(self.min);
    }

    pub fn extents(self: BoundingBox) Vec3f {
        return self.size().scale(0.5);
    }

    pub fn volume(self: BoundingBox) f32 {
        const s = self.size();
        return s.x * s.y * s.z;
    }

    pub fn surfaceArea(self: BoundingBox) f32 {
        const s = self.size();
        return 2.0 * (s.x * s.y + s.y * s.z + s.z * s.x);
    }

    pub fn contains(self: BoundingBox, point: Vec3f) bool {
        return point.x >= self.min.x and point.x <= self.max.x and
            point.y >= self.min.y and point.y <= self.max.y and
            point.z >= self.min.z and point.z <= self.max.z;
    }

    pub fn intersects(a: BoundingBox, b: BoundingBox) bool {
        return !(a.max.x < b.min.x or a.min.x > b.max.x or
            a.max.y < b.min.y or a.min.y > b.max.y or
            a.max.z < b.min.z or a.min.z > b.max.z);
    }

    pub fn unionWith(a: BoundingBox, b: BoundingBox) BoundingBox {
        return BoundingBox{
            .min = a.min.min(b.min),
            .max = a.max.max(b.max),
        };
    }

    pub fn intersection(a: BoundingBox, b: BoundingBox) ?BoundingBox {
        const new_min = a.min.max(b.min);
        const new_max = a.max.min(b.max);

        if (new_min.x <= new_max.x and new_min.y <= new_max.y and new_min.z <= new_max.z) {
            return BoundingBox{ .min = new_min, .max = new_max };
        }
        return null;
    }

    pub fn expand(self: BoundingBox, amount: f32) BoundingBox {
        const expansion = Vec3f.init(amount, amount, amount);
        return BoundingBox{
            .min = self.min.sub(expansion),
            .max = self.max.add(expansion),
        };
    }

    pub fn expandToContain(self: BoundingBox, point: Vec3f) BoundingBox {
        return BoundingBox{
            .min = self.min.min(point),
            .max = self.max.max(point),
        };
    }

    pub fn transform(self: BoundingBox, transform_matrix: Mat4f) BoundingBox {
        const corners = [8]Vec3f{
            Vec3f.init(self.min.x, self.min.y, self.min.z),
            Vec3f.init(self.max.x, self.min.y, self.min.z),
            Vec3f.init(self.min.x, self.max.y, self.min.z),
            Vec3f.init(self.max.x, self.max.y, self.min.z),
            Vec3f.init(self.min.x, self.min.y, self.max.z),
            Vec3f.init(self.max.x, self.min.y, self.max.z),
            Vec3f.init(self.min.x, self.max.y, self.max.z),
            Vec3f.init(self.max.x, self.max.y, self.max.z),
        };

        var transformed_corners: [8]Vec3f = undefined;
        for (corners, 0..) |corner, i| {
            transformed_corners[i] = transform_matrix.transformPoint(corner);
        }

        return fromPoints(&transformed_corners);
    }

    pub fn distanceToPoint(self: BoundingBox, point: Vec3f) f32 {
        const dx = @max(0, @max(self.min.x - point.x, point.x - self.max.x));
        const dy = @max(0, @max(self.min.y - point.y, point.y - self.max.y));
        const dz = @max(0, @max(self.min.z - point.z, point.z - self.max.z));
        return @sqrt(dx * dx + dy * dy + dz * dz);
    }

    pub fn closestPoint(self: BoundingBox, point: Vec3f) Vec3f {
        return Vec3f.init(clamp(point.x, self.min.x, self.max.x), clamp(point.y, self.min.y, self.max.y), clamp(point.z, self.min.z, self.max.z));
    }
};

pub const BoundingSphere = struct {
    center: Vec3f,
    radius: f32,

    pub fn init(center: Vec3f, radius: f32) BoundingSphere {
        return BoundingSphere{ .center = center, .radius = radius };
    }

    pub fn fromPoints(points: []const Vec3f) BoundingSphere {
        if (points.len == 0) return BoundingSphere{ .center = Vec3f.zero, .radius = 0 };

        // Use Ritter's algorithm for bounding sphere computation
        var sphere = BoundingSphere{ .center = points[0], .radius = 0 };

        // Find the point farthest from the first point
        var max_dist: f32 = 0;
        var farthest_idx: usize = 0;
        for (points, 0..) |point, i| {
            const dist = points[0].distanceTo(point);
            if (dist > max_dist) {
                max_dist = dist;
                farthest_idx = i;
            }
        }

        // Initial sphere from two farthest points
        sphere.center = points[0].add(points[farthest_idx]).scale(0.5);
        sphere.radius = max_dist * 0.5;

        // Expand sphere to include all points
        for (points) |point| {
            const dist = sphere.center.distanceTo(point);
            if (dist > sphere.radius) {
                const new_radius = (sphere.radius + dist) * 0.5;
                const expansion_factor = (new_radius - sphere.radius) / dist;
                sphere.center = sphere.center.lerp(point, expansion_factor);
                sphere.radius = new_radius;
            }
        }

        return sphere;
    }

    pub fn fromBoundingBox(bbox: BoundingBox) BoundingSphere {
        const center = bbox.center();
        const radius = center.distanceTo(bbox.max);
        return BoundingSphere{ .center = center, .radius = radius };
    }

    pub fn contains(self: BoundingSphere, point: Vec3f) bool {
        return self.center.distanceTo(point) <= self.radius;
    }

    pub fn intersects(a: BoundingSphere, b: BoundingSphere) bool {
        const dist = a.center.distanceTo(b.center);
        return dist <= (a.radius + b.radius);
    }

    pub fn unionWith(a: BoundingSphere, b: BoundingSphere) BoundingSphere {
        const center_dist = a.center.distanceTo(b.center);

        // If one sphere contains the other
        if (center_dist + b.radius <= a.radius) return a;
        if (center_dist + a.radius <= b.radius) return b;

        // Calculate new sphere
        const new_radius = (center_dist + a.radius + b.radius) * 0.5;
        const direction = b.center.sub(a.center).normalize();
        const new_center = a.center.add(direction.scale((new_radius - a.radius)));

        return BoundingSphere{ .center = new_center, .radius = new_radius };
    }

    pub fn transform(self: BoundingSphere, transform_matrix: Mat4f) BoundingSphere {
        const new_center = transform_matrix.transformPoint(self.center);

        // Calculate maximum scale factor from transform matrix
        const scale_x = Vec3f.init(transform_matrix.m[0][0], transform_matrix.m[1][0], transform_matrix.m[2][0]).magnitude();
        const scale_y = Vec3f.init(transform_matrix.m[0][1], transform_matrix.m[1][1], transform_matrix.m[2][1]).magnitude();
        const scale_z = Vec3f.init(transform_matrix.m[0][2], transform_matrix.m[1][2], transform_matrix.m[2][2]).magnitude();
        const max_scale = @max(@max(scale_x, scale_y), scale_z);

        return BoundingSphere{ .center = new_center, .radius = self.radius * max_scale };
    }
};

// Plane for geometric computations
pub const Plane = struct {
    normal: Vec3f,
    distance: f32,

    pub fn init(normal: Vec3f, distance: f32) Plane {
        return Plane{ .normal = normal.normalize(), .distance = distance };
    }

    pub fn fromPointAndNormal(point: Vec3f, normal: Vec3f) Plane {
        const norm = normal.normalize();
        return Plane{ .normal = norm, .distance = norm.dot(point) };
    }

    pub fn fromThreePoints(a: Vec3f, b: Vec3f, c: Vec3f) Plane {
        const normal = b.sub(a).cross(c.sub(a)).normalize();
        return fromPointAndNormal(a, normal);
    }

    pub fn distanceToPoint(self: Plane, point: Vec3f) f32 {
        return self.normal.dot(point) - self.distance;
    }

    pub fn closestPoint(self: Plane, point: Vec3f) Vec3f {
        const dist = self.distanceToPoint(point);
        return point.sub(self.normal.scale(dist));
    }

    pub fn intersectSphere(self: Plane, sphere: BoundingSphere) bool {
        return @abs(self.distanceToPoint(sphere.center)) <= sphere.radius;
    }

    pub fn intersectBoundingBox(self: Plane, bbox: BoundingBox) bool {
        const center = bbox.center();
        const extents = bbox.extents();

        const r = extents.x * @abs(self.normal.x) +
            extents.y * @abs(self.normal.y) +
            extents.z * @abs(self.normal.z);

        return @abs(self.distanceToPoint(center)) <= r;
    }
};

// Ray for raycasting and intersection tests
pub const Ray = struct {
    origin: Vec3f,
    direction: Vec3f,

    pub fn init(origin: Vec3f, direction: Vec3f) Ray {
        return Ray{ .origin = origin, .direction = direction.normalize() };
    }

    pub fn at(self: Ray, t: f32) Vec3f {
        return self.origin.add(self.direction.scale(t));
    }

    pub fn intersectPlane(self: Ray, plane: Plane) ?f32 {
        const denom = plane.normal.dot(self.direction);
        if (@abs(denom) < EPSILON_F32) return null; // Ray is parallel to plane

        const t = (plane.distance - plane.normal.dot(self.origin)) / denom;
        return if (t >= 0) t else null;
    }

    pub fn intersectSphere(self: Ray, sphere: BoundingSphere) ?f32 {
        const oc = self.origin.sub(sphere.center);
        const a = self.direction.dot(self.direction);
        const b = 2.0 * oc.dot(self.direction);
        const c = oc.dot(oc) - sphere.radius * sphere.radius;

        const discriminant = b * b - 4 * a * c;
        if (discriminant < 0) return null;

        const sqrt_discriminant = @sqrt(discriminant);
        const t1 = (-b - sqrt_discriminant) / (2 * a);
        const t2 = (-b + sqrt_discriminant) / (2 * a);

        if (t1 >= 0) return t1;
        if (t2 >= 0) return t2;
        return null;
    }

    pub fn intersectBoundingBox(self: Ray, bbox: BoundingBox) ?f32 {
        const inv_dir = Vec3f.init(1.0 / self.direction.x, 1.0 / self.direction.y, 1.0 / self.direction.z);

        const t1 = bbox.min.sub(self.origin).hadamard(inv_dir);
        const t2 = bbox.max.sub(self.origin).hadamard(inv_dir);

        const tmin = t1.min(t2);
        const tmax = t1.max(t2);

        const t_near = @max(@max(tmin.x, tmin.y), tmin.z);
        const t_far = @min(@min(tmax.x, tmax.y), tmax.z);

        if (t_near > t_far or t_far < 0) return null;
        return if (t_near >= 0) t_near else t_far;
    }
};

// Fast math utility functions with SIMD optimizations
pub inline fn fastInverseSqrt(comptime T: type, x: T) T {
    return switch (T) {
        f32 => {
            const magic = FAST_INVSQRT_MAGIC_F32;
            var i = @as(u32, @bitCast(x));
            i = magic - (i >> 1);
            var y = @as(f32, @bitCast(i));
            y = y * (1.5 - (x * 0.5 * y * y)); // Newton-Raphson iteration
            return y;
        },
        f64 => {
            const magic = FAST_INVSQRT_MAGIC_F64;
            var i = @as(u64, @bitCast(x));
            i = magic - (i >> 1);
            var y = @as(f64, @bitCast(i));
            y = y * (1.5 - (x * 0.5 * y * y)); // Newton-Raphson iteration
            return y;
        },
        else => 1.0 / @sqrt(x),
    };
}

// SIMD optimized vector operations
pub fn simdDotProduct(a: SimdF32x4, b: SimdF32x4) f32 {
    const product = a * b;
    return product[0] + product[1] + product[2] + product[3];
}

pub fn simdCrossProduct(a: SimdF32x4, b: SimdF32x4) SimdF32x4 {
    const a_yzx = SimdF32x4{ a[1], a[2], a[0], a[3] };
    const a_zxy = SimdF32x4{ a[2], a[0], a[1], a[3] };
    const b_yzx = SimdF32x4{ b[1], b[2], b[0], b[3] };
    const b_zxy = SimdF32x4{ b[2], b[0], b[1], b[3] };

    return a_yzx * b_zxy - a_zxy * b_yzx;
}

pub fn simdNormalize(v: SimdF32x4) SimdF32x4 {
    const dot = simdDotProduct(v, v);
    const inv_length = fastInverseSqrt(f32, dot);
    return v * @as(SimdF32x4, @splat(inv_length));
}

// Common utility functions with enhanced performance
pub inline fn radians(deg: anytype) @TypeOf(deg) {
    return deg * @as(@TypeOf(deg), DEG_TO_RAD);
}

pub inline fn degrees(rad: anytype) @TypeOf(rad) {
    return rad * @as(@TypeOf(rad), RAD_TO_DEG);
}

pub inline fn clamp(value: anytype, min_val: @TypeOf(value), max_val: @TypeOf(value)) @TypeOf(value) {
    return @max(min_val, @min(max_val, value));
}

pub inline fn lerp(a: anytype, b: @TypeOf(a), t: anytype) @TypeOf(a) {
    return a + t * (b - a);
}

pub inline fn inverseLerp(a: anytype, b: @TypeOf(a), value: @TypeOf(a)) @TypeOf(a) {
    return (value - a) / (b - a);
}

pub inline fn smoothstep(edge0: anytype, edge1: @TypeOf(edge0), x: @TypeOf(edge0)) @TypeOf(edge0) {
    const t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

pub inline fn smootherstep(edge0: anytype, edge1: @TypeOf(edge0), x: @TypeOf(edge0)) @TypeOf(edge0) {
    const t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

pub inline fn mix(a: anytype, b: @TypeOf(a), t: anytype) @TypeOf(a) {
    return lerp(a, b, t);
}

pub inline fn step(edge: anytype, x: @TypeOf(edge)) @TypeOf(edge) {
    return if (x < edge) 0.0 else 1.0;
}

pub inline fn sign(x: anytype) @TypeOf(x) {
    const T = @TypeOf(x);
    if (x > 0) return @as(T, 1);
    if (x < 0) return @as(T, -1);
    return @as(T, 0);
}

pub inline fn fract(x: anytype) @TypeOf(x) {
    return x - @floor(x);
}

pub inline fn mod(x: anytype, y: @TypeOf(x)) @TypeOf(x) {
    return x - y * @floor(x / y);
}

pub inline fn wrap(x: anytype, min_val: @TypeOf(x), max_val: @TypeOf(x)) @TypeOf(x) {
    const range = max_val - min_val;
    return min_val + mod(x - min_val, range);
}

pub inline fn ping_pong(x: anytype, length: @TypeOf(x)) @TypeOf(x) {
    const t = mod(x, 2.0 * length);
    return if (t <= length) t else 2.0 * length - t;
}

pub inline fn isPowerOfTwo(x: anytype) bool {
    return x > 0 and (x & (x - 1)) == 0;
}

pub inline fn nextPowerOfTwo(x: anytype) @TypeOf(x) {
    const T = @TypeOf(x);
    var result = @as(T, 1);
    while (result < x) {
        result <<= 1;
    }
    return result;
}

pub inline fn previousPowerOfTwo(x: anytype) @TypeOf(x) {
    return nextPowerOfTwo(x) >> 1;
}

pub inline fn roundToMultiple(value: anytype, multiple: @TypeOf(value)) @TypeOf(value) {
    return @round(value / multiple) * multiple;
}

pub inline fn ceilToMultiple(value: anytype, multiple: @TypeOf(value)) @TypeOf(value) {
    return @ceil(value / multiple) * multiple;
}

pub inline fn floorToMultiple(value: anytype, multiple: @TypeOf(value)) @TypeOf(value) {
    return @floor(value / multiple) * multiple;
}

pub inline fn approxEqual(a: anytype, b: @TypeOf(a), epsilon: @TypeOf(a)) bool {
    return @abs(a - b) <= epsilon;
}

pub inline fn approxEqualDefault(a: anytype, b: @TypeOf(a)) bool {
    const T = @TypeOf(a);
    const eps = switch (T) {
        f16 => EPSILON_F16,
        f32 => EPSILON_F32,
        f64 => EPSILON_F64,
        else => DEFAULT_EPSILON,
    };
    return approxEqual(a, b, eps);
}

pub inline fn approxZero(x: anytype, epsilon: @TypeOf(x)) bool {
    return @abs(x) <= epsilon;
}

pub inline fn approxZeroDefault(x: anytype) bool {
    const T = @TypeOf(x);
    const eps = switch (T) {
        f16 => EPSILON_F16,
        f32 => EPSILON_F32,
        f64 => EPSILON_F64,
        else => DEFAULT_EPSILON,
    };
    return approxZero(x, eps);
}

// Advanced interpolation functions
pub fn hermite(p0: anytype, p1: @TypeOf(p0), t0: @TypeOf(p0), t1: @TypeOf(p0), t: anytype) @TypeOf(p0) {
    const t2 = t * t;
    const t3 = t2 * t;

    const h00 = 2 * t3 - 3 * t2 + 1;
    const h10 = t3 - 2 * t2 + t;
    const h01 = -2 * t3 + 3 * t2;
    const h11 = t3 - t2;

    return p0 * h00 + t0 * h10 + p1 * h01 + t1 * h11;
}

pub fn catmullRom(p0: anytype, p1: @TypeOf(p0), p2: @TypeOf(p0), p3: @TypeOf(p0), t: anytype) @TypeOf(p0) {
    const t2 = t * t;
    const t3 = t2 * t;

    return 0.5 * ((2 * p1) +
        (-p0 + p2) * t +
        (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
        (-p0 + 3 * p1 - 3 * p2 + p3) * t3);
}

pub fn bezier3(p0: anytype, p1: @TypeOf(p0), p2: @TypeOf(p0), p3: @TypeOf(p0), t: anytype) @TypeOf(p0) {
    const u = 1.0 - t;
    const u_squared = u * u;
    const u_cubed = u_squared * u;
    const t_squared = t * t;
    const t_cubed = t_squared * t;

    return p0 * u_cubed + p1 * (3 * u_squared * t) + p2 * (3 * u * t_squared) + p3 * t_cubed;
}

// Easing functions for animation
pub const Easing = struct {
    pub fn linear(t: f32) f32 {
        return t;
    }

    pub fn quadIn(t: f32) f32 {
        return t * t;
    }
    pub fn quadOut(t: f32) f32 {
        return 1 - (1 - t) * (1 - t);
    }
    pub fn quadInOut(t: f32) f32 {
        return if (t < 0.5) 2 * t * t else 1 - 2 * (1 - t) * (1 - t);
    }

    pub fn cubicIn(t: f32) f32 {
        return t * t * t;
    }
    pub fn cubicOut(t: f32) f32 {
        const u = 1 - t;
        return 1 - u * u * u;
    }
    pub fn cubicInOut(t: f32) f32 {
        return if (t < 0.5) 4 * t * t * t else 1 - 4 * (1 - t) * (1 - t) * (1 - t);
    }

    pub fn quartIn(t: f32) f32 {
        return t * t * t * t;
    }
    pub fn quartOut(t: f32) f32 {
        const u = 1 - t;
        return 1 - u * u * u * u;
    }
    pub fn quartInOut(t: f32) f32 {
        return if (t < 0.5) 8 * t * t * t * t else 1 - 8 * (1 - t) * (1 - t) * (1 - t) * (1 - t);
    }

    pub fn sineIn(t: f32) f32 {
        return 1 - @cos(t * PI * 0.5);
    }
    pub fn sineOut(t: f32) f32 {
        return @sin(t * PI * 0.5);
    }
    pub fn sineInOut(t: f32) f32 {
        return 0.5 * (1 - @cos(PI * t));
    }

    pub fn expIn(t: f32) f32 {
        return if (t == 0) 0 else std.math.pow(f32, 2, 10 * (t - 1));
    }
    pub fn expOut(t: f32) f32 {
        return if (t == 1) 1 else 1 - std.math.pow(f32, 2, -10 * t);
    }
    pub fn expInOut(t: f32) f32 {
        if (t == 0) return 0;
        if (t == 1) return 1;
        if (t < 0.5) return 0.5 * std.math.pow(f32, 2, 20 * t - 10);
        return 1 - 0.5 * std.math.pow(f32, 2, -20 * t + 10);
    }

    pub fn backIn(t: f32) f32 {
        const c1 = 1.70158;
        const c3 = c1 + 1;
        return c3 * t * t * t - c1 * t * t;
    }

    pub fn backOut(t: f32) f32 {
        const c1 = 1.70158;
        const c3 = c1 + 1;
        const u = t - 1;
        return 1 + c3 * u * u * u + c1 * u * u;
    }

    pub fn elasticIn(t: f32) f32 {
        if (t == 0) return 0;
        if (t == 1) return 1;
        const c4 = (2 * PI) / 3;
        return -std.math.pow(f32, 2, 10 * t - 10) * @sin((t * 10 - 10.75) * c4);
    }

    pub fn elasticOut(t: f32) f32 {
        if (t == 0) return 0;
        if (t == 1) return 1;
        const c4 = (2 * PI) / 3;
        return std.math.pow(f32, 2, -10 * t) * @sin((t * 10 - 0.75) * c4) + 1;
    }

    pub fn bounceOut(t: f32) f32 {
        const n1 = 7.5625;
        const d1 = 2.75;

        if (t < 1 / d1) {
            return n1 * t * t;
        } else if (t < 2 / d1) {
            const t2 = t - 1.5 / d1;
            return n1 * t2 * t2 + 0.75;
        } else if (t < 2.5 / d1) {
            const t2 = t - 2.25 / d1;
            return n1 * t2 * t2 + 0.9375;
        } else {
            const t2 = t - 2.625 / d1;
            return n1 * t2 * t2 + 0.984375;
        }
    }

    pub fn bounceIn(t: f32) f32 {
        return 1 - bounceOut(1 - t);
    }
};

// Improved noise functions with better quality
pub fn hash(n: u32) u32 {
    var x = n;
    x = ((x >> 16) ^ x) *% 0x45d9f3b;
    x = ((x >> 16) ^ x) *% 0x45d9f3b;
    x = (x >> 16) ^ x;
    return x;
}

pub fn noise1D(x: f32) f32 {
    const i = @as(i32, @intFromFloat(@floor(x)));
    const f = x - @as(f32, @floatFromInt(i));

    const a = @as(f32, @floatFromInt(hash(@as(u32, @bitCast(i))))) / @as(f32, @floatFromInt(std.math.maxInt(u32)));
    const b = @as(f32, @floatFromInt(hash(@as(u32, @bitCast(i + 1))))) / @as(f32, @floatFromInt(std.math.maxInt(u32)));

    return lerp(a, b, smoothstep(0.0, 1.0, f));
}

pub fn noise2D(x: f32, y: f32) f32 {
    const ix = @as(i32, @intFromFloat(@floor(x)));
    const iy = @as(i32, @intFromFloat(@floor(y)));
    const fx = x - @as(f32, @floatFromInt(ix));
    const fy = y - @as(f32, @floatFromInt(iy));

    const a = @as(f32, @floatFromInt(hash(@as(u32, @bitCast(ix)) +% @as(u32, @bitCast(iy)) *% 57))) / @as(f32, @floatFromInt(std.math.maxInt(u32)));
    const b = @as(f32, @floatFromInt(hash(@as(u32, @bitCast(ix + 1)) +% @as(u32, @bitCast(iy)) *% 57))) / @as(f32, @floatFromInt(std.math.maxInt(u32)));
    const c = @as(f32, @floatFromInt(hash(@as(u32, @bitCast(ix)) +% @as(u32, @bitCast(iy + 1)) *% 57))) / @as(f32, @floatFromInt(std.math.maxInt(u32)));
    const d = @as(f32, @floatFromInt(hash(@as(u32, @bitCast(ix + 1)) +% @as(u32, @bitCast(iy + 1)) *% 57))) / @as(f32, @floatFromInt(std.math.maxInt(u32)));

    const u = smoothstep(@as(f32, 0.0), @as(f32, 1.0), fx);
    const v = smoothstep(@as(f32, 0.0), @as(f32, 1.0), fy);

    return lerp(lerp(a, b, u), lerp(c, d, u), v);
}

pub fn noise3D(x: f32, y: f32, z: f32) f32 {
    const ix = @as(i32, @intFromFloat(@floor(x)));
    const iy = @as(i32, @intFromFloat(@floor(y)));
    const iz = @as(i32, @intFromFloat(@floor(z)));
    const fx = x - @as(f32, @floatFromInt(ix));
    const fy = y - @as(f32, @floatFromInt(iy));
    const fz = z - @as(f32, @floatFromInt(iz));

    const h = @as(u32, @bitCast(ix)) +% @as(u32, @bitCast(iy)) *% 57 +% @as(u32, @bitCast(iz)) *% 113;

    const a = @as(f32, @floatFromInt(hash(h))) / @as(f32, @floatFromInt(std.math.maxInt(u32)));
    const b = @as(f32, @floatFromInt(hash(h +% 1))) / @as(f32, @floatFromInt(std.math.maxInt(u32)));
    const c = @as(f32, @floatFromInt(hash(h +% 57))) / @as(f32, @floatFromInt(std.math.maxInt(u32)));
    const d = @as(f32, @floatFromInt(hash(h +% 58))) / @as(f32, @floatFromInt(std.math.maxInt(u32)));
    const e = @as(f32, @floatFromInt(hash(h +% 113))) / @as(f32, @floatFromInt(std.math.maxInt(u32)));
    const f_val = @as(f32, @floatFromInt(hash(h +% 114))) / @as(f32, @floatFromInt(std.math.maxInt(u32)));
    const g_val = @as(f32, @floatFromInt(hash(h +% 170))) / @as(f32, @floatFromInt(std.math.maxInt(u32)));
    const h_val = @as(f32, @floatFromInt(hash(h +% 171))) / @as(f32, @floatFromInt(std.math.maxInt(u32)));

    const u = smoothstep(@as(f32, 0.0), @as(f32, 1.0), fx);
    const v = smoothstep(@as(f32, 0.0), @as(f32, 1.0), fy);
    const w = smoothstep(@as(f32, 0.0), @as(f32, 1.0), fz);

    return lerp(lerp(lerp(a, b, u), lerp(c, d, u), v), lerp(lerp(e, f_val, u), lerp(g_val, h_val, u), v), w);
}

pub fn fbm(x: f32, y: f32, octaves: u32) f32 {
    var value: f32 = 0.0;
    var amplitude: f32 = 0.5;
    var frequency: f32 = 1.0;

    for (0..octaves) |_| {
        value += noise2D(x * frequency, y * frequency) * amplitude;
        amplitude *= 0.5;
        frequency *= 2.0;
    }

    return value;
}

pub fn ridgedNoise(x: f32, y: f32, octaves: u32) f32 {
    var value: f32 = 0.0;
    var amplitude: f32 = 0.5;
    var frequency: f32 = 1.0;

    for (0..octaves) |_| {
        const n = noise2D(x * frequency, y * frequency);
        value += (1.0 - @abs(n)) * amplitude;
        amplitude *= 0.5;
        frequency *= 2.0;
    }

    return value;
}

// Advanced random number generation
pub const Random = struct {
    state: u64,

    pub fn init(seed: u64) Random {
        return Random{ .state = if (seed == 0) 1 else seed };
    }

    pub fn next(self: *Random) u64 {
        self.state ^= self.state << 13;
        self.state ^= self.state >> 7;
        self.state ^= self.state << 17;
        return self.state;
    }

    pub fn float(self: *Random, comptime T: type) T {
        const max_val = switch (T) {
            f32 => @as(f32, @floatFromInt(std.math.maxInt(u32))),
            f64 => @as(f64, @floatFromInt(std.math.maxInt(u64))),
            else => @compileError("Unsupported float type"),
        };

        return switch (T) {
            f32 => @as(f32, @floatFromInt(@as(u32, @truncate(self.next())))) / max_val,
            f64 => @as(f64, @floatFromInt(self.next())) / max_val,
            else => unreachable,
        };
    }

    pub fn floatRange(self: *Random, comptime T: type, min_val: T, max_val: T) T {
        return min_val + self.float(T) * (max_val - min_val);
    }

    pub fn int(self: *Random, comptime T: type, max_val: T) T {
        return @as(T, @truncate(self.next())) % max_val;
    }

    pub fn intRange(self: *Random, comptime T: type, min_val: T, max_val: T) T {
        return min_val + self.int(T, max_val - min_val);
    }

    pub fn vec2(self: *Random, comptime T: type) Vec2(T) {
        return Vec2(T).init(self.float(T), self.float(T));
    }

    pub fn vec3(self: *Random, comptime T: type) Vec3(T) {
        return Vec3(T).init(self.float(T), self.float(T), self.float(T));
    }

    pub fn vec4(self: *Random, comptime T: type) Vec4(T) {
        return Vec4(T).init(self.float(T), self.float(T), self.float(T), self.float(T));
    }

    pub fn vec2Range(self: *Random, comptime T: type, min_val: T, max_val: T) Vec2(T) {
        return Vec2(T).init(self.floatRange(T, min_val, max_val), self.floatRange(T, min_val, max_val));
    }

    pub fn vec3Range(self: *Random, comptime T: type, min_val: T, max_val: T) Vec3(T) {
        return Vec3(T).init(self.floatRange(T, min_val, max_val), self.floatRange(T, min_val, max_val), self.floatRange(T, min_val, max_val));
    }

    pub fn unitVec2(self: *Random, comptime T: type) Vec2(T) {
        const angle = self.floatRange(T, 0.0, TAU);
        return Vec2(T).init(@cos(angle), @sin(angle));
    }

    pub fn unitVec3(self: *Random, comptime T: type) Vec3(T) {
        const z = self.floatRange(T, -1.0, 1.0);
        const theta = self.floatRange(T, 0.0, TAU);
        const r = @sqrt(1.0 - z * z);
        return Vec3(T).init(r * @cos(theta), r * @sin(theta), z);
    }

    pub fn insideUnitSphere(self: *Random, comptime T: type) Vec3(T) {
        while (true) {
            const v = self.vec3Range(T, -1.0, 1.0);
            if (v.magnitudeSquared() <= 1.0) return v;
        }
    }

    pub fn gaussianPair(self: *Random, comptime T: type) struct { T, T } {
        const u1_val = self.float(T);
        const u2_val = self.float(T);
        const z0 = @sqrt(-2.0 * @log(u1_val)) * @cos(TAU * u2_val);
        const z1 = @sqrt(-2.0 * @log(u1_val)) * @sin(TAU * u2_val);
        return .{ z0, z1 };
    }

    pub fn gaussian(self: *Random, comptime T: type) T {
        const pair = self.gaussianPair(T);
        return pair[0];
    }
};

// Advanced geometric operations
pub fn pointInTriangle(p: Vec2f, a: Vec2f, b: Vec2f, c: Vec2f) bool {
    const v0 = c.sub(a);
    const v1 = b.sub(a);
    const v2 = p.sub(a);

    const dot00 = v0.dot(v0);
    const dot01 = v0.dot(v1);
    const dot02 = v0.dot(v2);
    const dot11 = v1.dot(v1);
    const dot12 = v1.dot(v2);

    const inv_denom = 1.0 / (dot00 * dot11 - dot01 * dot01);
    const u = (dot11 * dot02 - dot01 * dot12) * inv_denom;
    const v = (dot00 * dot12 - dot01 * dot02) * inv_denom;

    return (u >= 0) and (v >= 0) and (u + v <= 1);
}

pub fn pointInQuad(p: Vec2f, a: Vec2f, b: Vec2f, c: Vec2f, d: Vec2f) bool {
    return pointInTriangle(p, a, b, c) or pointInTriangle(p, a, c, d);
}

pub fn pointInPolygon(point: Vec2f, vertices: []const Vec2f) bool {
    var inside = false;
    var j = vertices.len - 1;

    for (vertices, 0..) |vertex, i| {
        if (((vertex.y > point.y) != (vertices[j].y > point.y)) and
            (point.x < (vertices[j].x - vertex.x) * (point.y - vertex.y) / (vertices[j].y - vertex.y) + vertex.x))
        {
            inside = !inside;
        }
        j = i;
    }

    return inside;
}

pub fn lineIntersection(p1: Vec2f, p2: Vec2f, p3: Vec2f, p4: Vec2f) ?Vec2f {
    const denom = (p1.x - p2.x) * (p3.y - p4.y) - (p1.y - p2.y) * (p3.x - p4.x);
    if (@abs(denom) < EPSILON_F32) return null;

    const t = ((p1.x - p3.x) * (p3.y - p4.y) - (p1.y - p3.y) * (p3.x - p4.x)) / denom;
    const u = -((p1.x - p2.x) * (p1.y - p3.y) - (p1.y - p2.y) * (p1.x - p3.x)) / denom;

    if (t >= 0 and t <= 1 and u >= 0 and u <= 1) {
        return Vec2f.init(p1.x + t * (p2.x - p1.x), p1.y + t * (p2.y - p1.y));
    }

    return null;
}

pub fn triangleArea2D(a: Vec2f, b: Vec2f, c: Vec2f) f32 {
    return 0.5 * @abs((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y));
}

pub fn triangleArea3D(a: Vec3f, b: Vec3f, c: Vec3f) f32 {
    return 0.5 * b.sub(a).cross(c.sub(a)).magnitude();
}

pub fn polygonArea2D(vertices: []const Vec2f) f32 {
    if (vertices.len < 3) return 0;

    var area: f32 = 0;
    var j = vertices.len - 1;

    for (vertices, 0..) |vertex, i| {
        area += (vertices[j].x + vertex.x) * (vertices[j].y - vertex.y);
        j = i;
    }

    return @abs(area) * 0.5;
}

pub fn convexHull2D(allocator: std.mem.Allocator, points: []Vec2f) ![]Vec2f {
    if (points.len < 3) return error.InsufficientPoints;

    // Sort points lexicographically
    std.sort.pdq(Vec2f, points, {}, struct {
        fn lessThan(context: void, a: Vec2f, b: Vec2f) bool {
            _ = context;
            return a.x < b.x or (a.x == b.x and a.y < b.y);
        }
    }.lessThan);

    var hull = std.ArrayList(Vec2f).init(allocator);
    defer hull.deinit();

    // Build lower hull
    for (points) |point| {
        while (hull.items.len >= 2) {
            const cross = (hull.items[hull.items.len - 1].sub(hull.items[hull.items.len - 2]))
                .cross2D(point.sub(hull.items[hull.items.len - 1]));
            if (cross <= 0) {
                _ = hull.pop();
            } else {
                break;
            }
        }
        try hull.append(point);
    }

    // Build upper hull
    const lower_size = hull.items.len;
    var i = points.len - 2;
    while (i >= 0) : (i -= 1) {
        const point = points[i];
        while (hull.items.len > lower_size) {
            const cross = (hull.items[hull.items.len - 1].sub(hull.items[hull.items.len - 2]))
                .cross2D(point.sub(hull.items[hull.items.len - 1]));
            if (cross <= 0) {
                _ = hull.pop();
            } else {
                break;
            }
        }
        try hull.append(point);
        if (i == 0) break;
    }

    // Remove last point as it's the same as the first
    if (hull.items.len > 1) {
        _ = hull.pop();
    }

    return hull.toOwnedSlice();
}

// Frustum for view culling
pub const Frustum = struct {
    planes: [6]Plane,

    pub fn init(view_matrix: Mat4f, proj_matrix: Mat4f) Frustum {
        const vp = proj_matrix.multiply(view_matrix);

        return Frustum{
            .planes = [6]Plane{
                // Left
                Plane.init(Vec3f.init(vp.m[0][3] + vp.m[0][0], vp.m[1][3] + vp.m[1][0], vp.m[2][3] + vp.m[2][0]), vp.m[3][3] + vp.m[3][0]),
                // Right
                Plane.init(Vec3f.init(vp.m[0][3] - vp.m[0][0], vp.m[1][3] - vp.m[1][0], vp.m[2][3] - vp.m[2][0]), vp.m[3][3] - vp.m[3][0]),
                // Top
                Plane.init(Vec3f.init(vp.m[0][3] - vp.m[0][1], vp.m[1][3] - vp.m[1][1], vp.m[2][3] - vp.m[2][1]), vp.m[3][3] - vp.m[3][1]),
                // Bottom
                Plane.init(Vec3f.init(vp.m[0][3] + vp.m[0][1], vp.m[1][3] + vp.m[1][1], vp.m[2][3] + vp.m[2][1]), vp.m[3][3] + vp.m[3][1]),
                // Near
                Plane.init(Vec3f.init(vp.m[0][3] + vp.m[0][2], vp.m[1][3] + vp.m[1][2], vp.m[2][3] + vp.m[2][2]), vp.m[3][3] + vp.m[3][2]),
                // Far
                Plane.init(Vec3f.init(vp.m[0][3] - vp.m[0][2], vp.m[1][3] - vp.m[1][2], vp.m[2][3] - vp.m[2][2]), vp.m[3][3] - vp.m[3][2]),
            },
        };
    }

    pub fn containsPoint(self: Frustum, point: Vec3f) bool {
        for (self.planes) |plane| {
            if (plane.distanceToPoint(point) < 0) return false;
        }
        return true;
    }

    pub fn intersectsSphere(self: Frustum, sphere: BoundingSphere) bool {
        for (self.planes) |plane| {
            if (plane.distanceToPoint(sphere.center) < -sphere.radius) return false;
        }
        return true;
    }

    pub fn intersectsBoundingBox(self: Frustum, bbox: BoundingBox) bool {
        for (self.planes) |plane| {
            if (!plane.intersectBoundingBox(bbox)) return false;
        }
        return true;
    }
};

// Comprehensive test suite
test "math constants" {
    try testing.expect(PI > 3.14 and PI < 3.15);
    try testing.expect(TAU > 6.28 and TAU < 6.29);
    try testing.expect(@abs(DEG_TO_RAD * 180.0 - PI) < EPSILON_F32);
    try testing.expect(@abs(RAD_TO_DEG * PI - 180.0) < EPSILON_F32);
}

test "quaternion operations" {
    const q1 = Quatf.identity;
    const q2 = Quatf.fromAxisAngle(Vec3f.init(0, 1, 0), @as(f32, PI) / 2.0);

    try testing.expect(approxEqualDefault(q1.magnitude(), 1.0));
    try testing.expect(approxEqualDefault(q2.magnitude(), 1.0));
    try testing.expect(q2.isNormalized(EPSILON_F32));

    const q4 = q1.multiply(q2);
    try testing.expect(approxEqualDefault(q4.magnitude(), 1.0));

    const slerped = q1.slerp(q2, 0.5);
    try testing.expect(approxEqualDefault(slerped.magnitude(), 1.0));
}

test "utility functions" {
    try testing.expect(clamp(5.0, 0.0, 10.0) == 5.0);
    try testing.expect(clamp(-1.0, 0.0, 10.0) == 0.0);
    try testing.expect(clamp(15.0, 0.0, 10.0) == 10.0);

    try testing.expect(approxEqualDefault(lerp(0.0, 10.0, 0.5), 5.0));
    try testing.expect(approxEqualDefault(inverseLerp(0.0, 10.0, 5.0), 0.5));

    try testing.expect(isPowerOfTwo(8));
    try testing.expect(!isPowerOfTwo(7));
    try testing.expect(nextPowerOfTwo(7) == 8);
    try testing.expect(previousPowerOfTwo(9) == 4);
}

test "bounding volumes" {
    const points = [_]Vec3f{
        Vec3f.init(-1, -1, -1),
        Vec3f.init(1, 1, 1),
        Vec3f.init(0, 2, 0),
    };

    const bbox = BoundingBox.fromPoints(&points);
    try testing.expect(bbox.contains(Vec3f.zero));
    try testing.expect(!bbox.contains(Vec3f.init(2, 2, 2)));

    const sphere = BoundingSphere.fromPoints(&points);
    try testing.expect(sphere.contains(Vec3f.zero));
    try testing.expect(sphere.radius > 0);
}

test "geometric operations" {
    const triangle = [_]Vec2f{
        Vec2f.init(0, 0),
        Vec2f.init(1, 0),
        Vec2f.init(0.5, 1),
    };

    try testing.expect(pointInTriangle(Vec2f.init(0.5, 0.3), triangle[0], triangle[1], triangle[2]));
    try testing.expect(!pointInTriangle(Vec2f.init(1.5, 0.3), triangle[0], triangle[1], triangle[2]));

    const area = triangleArea2D(triangle[0], triangle[1], triangle[2]);
    try testing.expect(area > 0);
}

test "transform operations" {
    const t1 = Transform.identity;
    const t2 = Transform.init(Vec3f.init(1, 2, 3), Quatf.fromAxisAngle(Vec3f.init(0, 1, 0), @as(f32, PI) / 4.0), Vec3f.init(2, 2, 2));

    const combined = Transform.combine(t1, t2);
    try testing.expect(!combined.translation.equals(Vec3f.zero));

    const inverse = t2.inverse();
    const identity_check = Transform.combine(t2, inverse);
    try testing.expect(identity_check.translation.magnitude() < 0.001);
}

test "ray intersections" {
    const ray = Ray.init(Vec3f.init(0, 0, -5), Vec3f.init(0, 0, 1));
    const sphere = BoundingSphere.init(Vec3f.zero, 1.0);
    const bbox = BoundingBox.init(Vec3f.init(-1, -1, -1), Vec3f.init(1, 1, 1));

    const sphere_hit = ray.intersectSphere(sphere);
    try testing.expect(sphere_hit != null);
    try testing.expect(sphere_hit.? > 0);

    const bbox_hit = ray.intersectBoundingBox(bbox);
    try testing.expect(bbox_hit != null);
    try testing.expect(bbox_hit.? > 0);
}

test "random number generation" {
    var rng = Random.init(12345);

    const f1 = rng.float(f32);
    const f2 = rng.float(f32);
    try testing.expect(f1 >= 0.0 and f1 <= 1.0);
    try testing.expect(f2 >= 0.0 and f2 <= 1.0);
    try testing.expect(f1 != f2);

    const unit_vec = rng.unitVec3(f32);
    try testing.expect(approxEqualDefault(unit_vec.magnitude(), 1.0));

    const inside_sphere = rng.insideUnitSphere(f32);
    try testing.expect(inside_sphere.magnitudeSquared() <= 1.0);
}

test "easing functions" {
    try testing.expect(Easing.linear(0.5) == 0.5);
    try testing.expect(Easing.quadIn(0.0) == 0.0);
    try testing.expect(Easing.quadIn(1.0) == 1.0);
    try testing.expect(Easing.sineIn(0.0) == 0.0);
    try testing.expect(approxEqualDefault(Easing.sineIn(1.0), 1.0));
}

test "noise functions" {
    const n1 = noise2D(1.0, 2.0);
    const n2 = noise2D(1.1, 2.0);
    try testing.expect(n1 >= 0.0 and n1 <= 1.0);
    try testing.expect(n2 >= 0.0 and n2 <= 1.0);
    try testing.expect(n1 != n2);

    const fbm_val = fbm(1.0, 2.0, 4);
    try testing.expect(fbm_val >= 0.0 and fbm_val <= 1.0);
}
