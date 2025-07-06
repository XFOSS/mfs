//! Advanced 3D Vector Implementation with SIMD Optimizations
//! Ultra-high performance vector mathematics for game engines and scientific computing

const std = @import("std");
const builtin = @import("builtin");
const math = std.math;
const testing = std.testing;

// SIMD support detection
const has_sse = builtin.cpu.arch == .x86_64 and std.Target.x86.featureSetHas(builtin.cpu.features, .sse);
const has_avx = builtin.cpu.arch == .x86_64 and std.Target.x86.featureSetHas(builtin.cpu.features, .avx);
const has_neon = builtin.cpu.arch == .aarch64 and std.Target.aarch64.featureSetHas(builtin.cpu.features, .neon);

// SIMD vector types for optimization
const SimdF32x4 = @Vector(4, f32);
const SimdF64x2 = @Vector(2, f64);
const SimdI32x4 = @Vector(4, i32);

// Enhanced precision constants
const EPSILON_F32 = math.floatEps(f32);
const EPSILON_F64 = math.floatEps(f64);
const DEFAULT_EPSILON = 1e-6;
const HIGH_PRECISION_EPSILON = 1e-12;

// Fast inverse square root magic numbers
const FAST_INVSQRT_MAGIC_F32: u32 = 0x5f3759df;
const FAST_INVSQRT_MAGIC_F64: u64 = 0x5fe6ec85e7de30da;

/// Advanced 3D Vector with SIMD optimizations and comprehensive functionality
pub fn Vec3(comptime T: type) type {
    return struct {
        const Self = @This();

        x: T,
        y: T,
        z: T,

        // Common vector constants with compile-time evaluation
        pub const zero = Self{ .x = 0, .y = 0, .z = 0 };
        pub const one = Self{ .x = 1, .y = 1, .z = 1 };
        pub const half = Self{ .x = 0.5, .y = 0.5, .z = 0.5 };
        pub const infinity = Self{ .x = math.inf(T), .y = math.inf(T), .z = math.inf(T) };
        pub const neg_infinity = Self{ .x = -math.inf(T), .y = -math.inf(T), .z = -math.inf(T) };

        // Cardinal directions
        pub const unit_x = Self{ .x = 1, .y = 0, .z = 0 };
        pub const unit_y = Self{ .x = 0, .y = 1, .z = 0 };
        pub const unit_z = Self{ .x = 0, .y = 0, .z = 1 };

        // Common world directions
        pub const up = Self{ .x = 0, .y = 1, .z = 0 };
        pub const down = Self{ .x = 0, .y = -1, .z = 0 };
        pub const left = Self{ .x = -1, .y = 0, .z = 0 };
        pub const right = Self{ .x = 1, .y = 0, .z = 0 };
        pub const forward = Self{ .x = 0, .y = 0, .z = -1 };
        pub const back = Self{ .x = 0, .y = 0, .z = 1 };
        pub const north = Self{ .x = 0, .y = 0, .z = 1 };
        pub const south = Self{ .x = 0, .y = 0, .z = -1 };
        pub const east = Self{ .x = 1, .y = 0, .z = 0 };
        pub const west = Self{ .x = -1, .y = 0, .z = 0 };

        /// Create a new Vec3 with specified components
        pub inline fn init(x: T, y: T, z: T) Self {
            return Self{ .x = x, .y = y, .z = z };
        }

        /// Create a new Vec3 with specified components (alias for init)
        pub inline fn new(x: T, y: T, z: T) Self {
            return Self{ .x = x, .y = y, .z = z };
        }

        /// Create a Vec3 with all components set to the same value
        pub inline fn splat(value: T) Self {
            return Self{ .x = value, .y = value, .z = value };
        }

        /// Create a Vec3 from an array
        pub inline fn fromArray(arr: [3]T) Self {
            return Self{ .x = arr[0], .y = arr[1], .z = arr[2] };
        }

        /// Convert Vec3 to an array
        pub inline fn toArray(self: Self) [3]T {
            return [3]T{ self.x, self.y, self.z };
        }

        /// Create a Vec3 from a slice (must have at least 3 elements)
        pub inline fn fromSlice(slice: []const T) Self {
            std.debug.assert(slice.len >= 3);
            return Self{ .x = slice[0], .y = slice[1], .z = slice[2] };
        }

        /// Convert Vec3 to a slice
        pub inline fn toSlice(self: *const Self) []const T {
            return @as([*]const T, @ptrCast(self))[0..3];
        }

        /// Create Vec3 from polar coordinates (spherical)
        pub fn fromSpherical(radius: T, theta: T, phi: T) Self {
            const sin_phi = @sin(phi);
            return Self{
                .x = radius * sin_phi * @cos(theta),
                .y = radius * @cos(phi),
                .z = radius * sin_phi * @sin(theta),
            };
        }

        /// Convert to spherical coordinates (radius, theta, phi)
        pub fn toSpherical(self: Self) struct { radius: T, theta: T, phi: T } {
            const radius = self.magnitude();
            if (radius == 0) return .{ .radius = 0, .theta = 0, .phi = 0 };

            const theta = math.atan2(self.z, self.x);
            const phi = math.acos(self.y / radius);

            return .{ .radius = radius, .theta = theta, .phi = phi };
        }

        /// Create Vec3 from cylindrical coordinates
        pub fn fromCylindrical(radius: T, theta: T, height: T) Self {
            return Self{
                .x = radius * @cos(theta),
                .y = height,
                .z = radius * @sin(theta),
            };
        }

        /// Convert to cylindrical coordinates (radius, theta, height)
        pub fn toCylindrical(self: Self) struct { radius: T, theta: T, height: T } {
            const radius = @sqrt(self.x * self.x + self.z * self.z);
            const theta = math.atan2(self.z, self.x);
            return .{ .radius = radius, .theta = theta, .height = self.y };
        }

        // ========== SIMD-Optimized Arithmetic Operations ==========

        /// Vector addition with SIMD optimization
        pub inline fn add(self: Self, other: Self) Self {
            if (comptime T == f32 and has_sse) {
                const a = SimdF32x4{ self.x, self.y, self.z, 0 };
                const b = SimdF32x4{ other.x, other.y, other.z, 0 };
                const result = a + b;
                return Self{ .x = result[0], .y = result[1], .z = result[2] };
            } else {
                return Self{
                    .x = self.x + other.x,
                    .y = self.y + other.y,
                    .z = self.z + other.z,
                };
            }
        }

        /// Vector subtraction with SIMD optimization
        pub inline fn sub(self: Self, other: Self) Self {
            if (comptime T == f32 and has_sse) {
                const a = SimdF32x4{ self.x, self.y, self.z, 0 };
                const b = SimdF32x4{ other.x, other.y, other.z, 0 };
                const result = a - b;
                return Self{ .x = result[0], .y = result[1], .z = result[2] };
            } else {
                return Self{
                    .x = self.x - other.x,
                    .y = self.y - other.y,
                    .z = self.z - other.z,
                };
            }
        }

        /// Component-wise multiplication (Hadamard product)
        pub inline fn hadamard(self: Self, other: Self) Self {
            if (comptime T == f32 and has_sse) {
                const a = SimdF32x4{ self.x, self.y, self.z, 0 };
                const b = SimdF32x4{ other.x, other.y, other.z, 0 };
                const result = a * b;
                return Self{ .x = result[0], .y = result[1], .z = result[2] };
            } else {
                return Self{
                    .x = self.x * other.x,
                    .y = self.y * other.y,
                    .z = self.z * other.z,
                };
            }
        }

        /// Component-wise division
        pub inline fn divide(self: Self, other: Self) Self {
            return Self{
                .x = self.x / other.x,
                .y = self.y / other.y,
                .z = self.z / other.z,
            };
        }

        /// Scalar multiplication
        pub inline fn scale(self: Self, scalar: T) Self {
            if (comptime T == f32 and has_sse) {
                const vec = SimdF32x4{ self.x, self.y, self.z, 0 };
                const s = @as(SimdF32x4, @splat(scalar));
                const result = vec * s;
                return Self{ .x = result[0], .y = result[1], .z = result[2] };
            } else {
                return Self{
                    .x = self.x * scalar,
                    .y = self.y * scalar,
                    .z = self.z * scalar,
                };
            }
        }

        /// Scalar division
        pub inline fn divideScalar(self: Self, scalar: T) Self {
            const inv_scalar = 1.0 / scalar;
            return self.scale(inv_scalar);
        }

        /// Vector negation
        pub inline fn negate(self: Self) Self {
            return Self{ .x = -self.x, .y = -self.y, .z = -self.z };
        }

        /// Component-wise absolute value
        pub inline fn abs(self: Self) Self {
            return Self{
                .x = @abs(self.x),
                .y = @abs(self.y),
                .z = @abs(self.z),
            };
        }

        /// Component-wise floor
        pub inline fn floor(self: Self) Self {
            return Self{
                .x = @floor(self.x),
                .y = @floor(self.y),
                .z = @floor(self.z),
            };
        }

        /// Component-wise ceiling
        pub inline fn ceil(self: Self) Self {
            return Self{
                .x = @ceil(self.x),
                .y = @ceil(self.y),
                .z = @ceil(self.z),
            };
        }

        /// Component-wise round
        pub inline fn round(self: Self) Self {
            return Self{
                .x = @round(self.x),
                .y = @round(self.y),
                .z = @round(self.z),
            };
        }

        /// Component-wise fractional part
        pub inline fn fract(self: Self) Self {
            return Self{
                .x = self.x - @floor(self.x),
                .y = self.y - @floor(self.y),
                .z = self.z - @floor(self.z),
            };
        }

        /// Component-wise modulo
        pub inline fn mod(self: Self, other: Self) Self {
            return Self{
                .x = self.x - other.x * @floor(self.x / other.x),
                .y = self.y - other.y * @floor(self.y / other.y),
                .z = self.z - other.z * @floor(self.z / other.z),
            };
        }

        /// Component-wise power
        pub inline fn pow(self: Self, exponent: T) Self {
            return Self{
                .x = math.pow(T, self.x, exponent),
                .y = math.pow(T, self.y, exponent),
                .z = math.pow(T, self.z, exponent),
            };
        }

        /// Component-wise square root
        pub inline fn sqrt(self: Self) Self {
            return Self{
                .x = @sqrt(self.x),
                .y = @sqrt(self.y),
                .z = @sqrt(self.z),
            };
        }

        /// Component-wise reciprocal square root
        pub inline fn rsqrt(self: Self) Self {
            return Self{
                .x = 1.0 / @sqrt(self.x),
                .y = 1.0 / @sqrt(self.y),
                .z = 1.0 / @sqrt(self.z),
            };
        }

        // ========== Geometric Operations ==========

        /// Dot product with SIMD optimization
        pub inline fn dot(self: Self, other: Self) T {
            if (comptime T == f32 and has_sse) {
                const a = SimdF32x4{ self.x, self.y, self.z, 0 };
                const b = SimdF32x4{ other.x, other.y, other.z, 0 };
                const product = a * b;
                return product[0] + product[1] + product[2];
            } else {
                return self.x * other.x + self.y * other.y + self.z * other.z;
            }
        }

        /// Cross product with SIMD optimization
        pub inline fn cross(self: Self, other: Self) Self {
            if (comptime T == f32 and has_sse) {
                const a = SimdF32x4{ self.x, self.y, self.z, 0 };
                const b = SimdF32x4{ other.x, other.y, other.z, 0 };
                const a_yzx = SimdF32x4{ a[1], a[2], a[0], 0 };
                const a_zxy = SimdF32x4{ a[2], a[0], a[1], 0 };
                const b_yzx = SimdF32x4{ b[1], b[2], b[0], 0 };
                const b_zxy = SimdF32x4{ b[2], b[0], b[1], 0 };
                const result = a_yzx * b_zxy - a_zxy * b_yzx;
                return Self{ .x = result[0], .y = result[1], .z = result[2] };
            } else {
                return Self{
                    .x = self.y * other.z - self.z * other.y,
                    .y = self.z * other.x - self.x * other.z,
                    .z = self.x * other.y - self.y * other.x,
                };
            }
        }

        /// 2D cross product (returns scalar)
        pub inline fn cross2D(self: Self, other: Self) T {
            return self.x * other.y - self.y * other.x;
        }

        /// Triple scalar product (self · (a × b))
        pub inline fn tripleScalar(self: Self, a: Self, b: Self) T {
            return self.dot(a.cross(b));
        }

        /// Triple vector product (self × (a × b))
        pub inline fn tripleVector(self: Self, a: Self, b: Self) Self {
            return self.cross(a.cross(b));
        }

        /// Magnitude squared (length squared)
        pub inline fn magnitudeSquared(self: Self) T {
            return self.dot(self);
        }

        /// Magnitude (length) with fast inverse square root optimization
        pub inline fn magnitude(self: Self) T {
            const mag_sq = self.magnitudeSquared();
            return @sqrt(mag_sq);
        }

        /// Fast magnitude using fast inverse square root
        pub inline fn fastMagnitude(self: Self) T {
            const mag_sq = self.magnitudeSquared();
            if (mag_sq == 0) return 0;
            return mag_sq * fastInverseSqrt(T, mag_sq);
        }

        /// Distance squared between two points
        pub inline fn distanceSquared(self: Self, other: Self) T {
            return self.sub(other).magnitudeSquared();
        }

        /// Distance between two points
        pub inline fn distanceTo(self: Self, other: Self) T {
            return self.sub(other).magnitude();
        }

        /// Fast distance using fast square root
        pub inline fn fastDistanceTo(self: Self, other: Self) T {
            return self.sub(other).fastMagnitude();
        }

        /// Manhattan distance (L1 norm)
        pub inline fn manhattanDistance(self: Self, other: Self) T {
            const diff = self.sub(other).abs();
            return diff.x + diff.y + diff.z;
        }

        /// Chebyshev distance (L∞ norm)
        pub inline fn chebyshevDistance(self: Self, other: Self) T {
            const diff = self.sub(other).abs();
            return @max(@max(diff.x, diff.y), diff.z);
        }

        /// Minkowski distance with custom p value
        pub inline fn minkowskiDistance(self: Self, other: Self, p: T) T {
            const diff = self.sub(other).abs();
            return math.pow(T, diff.x.pow(p) + diff.y.pow(p) + diff.z.pow(p), 1.0 / p);
        }

        // ========== Normalization Operations ==========

        /// Normalize vector to unit length
        pub inline fn normalize(self: Self) Self {
            const mag = self.magnitude();
            if (mag == 0) return zero;
            return self.divideScalar(mag);
        }

        /// Safe normalize with fallback vector
        pub inline fn normalizeSafe(self: Self, fallback: Self) Self {
            const mag_sq = self.magnitudeSquared();
            if (mag_sq < EPSILON_F32) return fallback;
            return self.divideScalar(@sqrt(mag_sq));
        }

        /// Fast normalize using fast inverse square root
        pub inline fn fastNormalize(self: Self) Self {
            const mag_sq = self.magnitudeSquared();
            if (mag_sq == 0) return zero;
            const inv_mag = fastInverseSqrt(T, mag_sq);
            return self.scale(inv_mag);
        }

        /// Get normalized vector without modifying original
        pub inline fn normalized(self: Self) Self {
            return self.normalize();
        }

        /// Check if vector is normalized (unit length)
        pub inline fn isNormalized(self: Self, epsilon: T) bool {
            const mag_sq = self.magnitudeSquared();
            return @abs(mag_sq - 1.0) <= epsilon;
        }

        /// Make vector unit length if not already normalized
        pub inline fn makeNormalized(self: *Self) void {
            const mag = self.magnitude();
            if (mag > EPSILON_F32) {
                const inv_mag = 1.0 / mag;
                self.x *= inv_mag;
                self.y *= inv_mag;
                self.z *= inv_mag;
            }
        }

        // ========== Interpolation Functions ==========

        /// Linear interpolation between two vectors
        pub inline fn lerp(self: Self, target: Self, t: T) Self {
            return self.add(target.sub(self).scale(t));
        }

        /// Normalized linear interpolation (for rotations)
        pub inline fn nlerp(self: Self, target: Self, t: T) Self {
            return self.lerp(target, t).normalize();
        }

        /// Spherical linear interpolation
        pub fn slerp(self: Self, target: Self, t: T) Self {
            var dot_product = @max(-1.0, @min(1.0, self.dot(target)));

            // If vectors are very close, use linear interpolation
            if (dot_product > 0.9995) {
                return self.lerp(target, t).normalize();
            }

            // Ensure we take the shorter path
            var target_corrected = target;
            if (dot_product < 0) {
                target_corrected = target.negate();
                dot_product = -dot_product;
            }

            const theta = math.acos(dot_product);
            const sin_theta = @sin(theta);
            const factor_a = @sin((1.0 - t) * theta) / sin_theta;
            const factor_b = @sin(t * theta) / sin_theta;

            return self.scale(factor_a).add(target_corrected.scale(factor_b));
        }

        /// Quadratic Bézier interpolation
        pub inline fn bezierQuad(p0: Self, p1: Self, p2: Self, t: T) Self {
            const u = 1.0 - t;
            const a = p0.scale(u * u);
            const b = p1.scale(2.0 * u * t);
            const c = p2.scale(t * t);
            return a.add(b).add(c);
        }

        /// Cubic Bézier interpolation
        pub inline fn bezierCubic(p0: Self, p1: Self, p2: Self, p3: Self, t: T) Self {
            const u = 1.0 - t;
            const u_squared = u * u;
            const u_cubed = u_squared * u;
            const t_squared = t * t;
            const t_cubed = t_squared * t;

            const a = p0.scale(u_cubed);
            const b = p1.scale(3.0 * u_squared * t);
            const c = p2.scale(3.0 * u * t_squared);
            const d = p3.scale(t_cubed);

            return a.add(b).add(c).add(d);
        }

        /// Catmull-Rom spline interpolation
        pub inline fn catmullRom(p0: Self, p1: Self, p2: Self, p3: Self, t: T) Self {
            const t_squared = t * t;
            const t_cubed = t_squared * t;

            const a = p1.scale(2.0);
            const b = p2.sub(p0).scale(t);
            const c = p0.scale(2.0).sub(p1.scale(5.0)).add(p2.scale(4.0)).sub(p3).scale(t_squared);
            const d = p1.scale(3.0).sub(p0).sub(p2.scale(3.0)).add(p3).scale(t_cubed);

            return a.add(b).add(c).add(d).scale(0.5);
        }

        /// Hermite interpolation with tangents
        pub inline fn hermite(p0: Self, p1: Self, t0: Self, t1: Self, t: T) Self {
            const t_squared = t * t;
            const t_cubed = t_squared * t;

            const h00 = 2.0 * t_cubed - 3.0 * t_squared + 1.0;
            const h10 = t_cubed - 2.0 * t_squared + t;
            const h01 = -2.0 * t_cubed + 3.0 * t_squared;
            const h11 = t_cubed - t_squared;

            return p0.scale(h00).add(t0.scale(h10)).add(p1.scale(h01)).add(t1.scale(h11));
        }

        // ========== Component-wise Operations ==========

        /// Component-wise minimum
        pub inline fn min(self: Self, other: Self) Self {
            return Self{
                .x = @min(self.x, other.x),
                .y = @min(self.y, other.y),
                .z = @min(self.z, other.z),
            };
        }

        /// Component-wise maximum
        pub inline fn max(self: Self, other: Self) Self {
            return Self{
                .x = @max(self.x, other.x),
                .y = @max(self.y, other.y),
                .z = @max(self.z, other.z),
            };
        }

        /// Component-wise clamp
        pub inline fn clamp(self: Self, min_vec: Self, max_vec: Self) Self {
            return Self{
                .x = @max(min_vec.x, @min(max_vec.x, self.x)),
                .y = @max(min_vec.y, @min(max_vec.y, self.y)),
                .z = @max(min_vec.z, @min(max_vec.z, self.z)),
            };
        }

        /// Clamp magnitude to specified range
        pub inline fn clampMagnitude(self: Self, min_mag: T, max_mag: T) Self {
            const mag = self.magnitude();
            if (mag == 0) return self;
            const clamped_mag = @max(min_mag, @min(max_mag, mag));
            return self.scale(clamped_mag / mag);
        }

        /// Component-wise sign
        pub inline fn sign(self: Self) Self {
            return Self{
                .x = if (self.x > 0) @as(T, 1) else if (self.x < 0) @as(T, -1) else @as(T, 0),
                .y = if (self.y > 0) @as(T, 1) else if (self.y < 0) @as(T, -1) else @as(T, 0),
                .z = if (self.z > 0) @as(T, 1) else if (self.z < 0) @as(T, -1) else @as(T, 0),
            };
        }

        /// Get the component with the largest absolute value
        pub inline fn maxComponent(self: Self) T {
            return @max(@max(@abs(self.x), @abs(self.y)), @abs(self.z));
        }

        /// Get the component with the smallest absolute value
        pub inline fn minComponent(self: Self) T {
            return @min(@min(@abs(self.x), @abs(self.y)), @abs(self.z));
        }

        /// Get the index of the component with the largest absolute value
        pub inline fn maxComponentIndex(self: Self) u8 {
            const abs_x = @abs(self.x);
            const abs_y = @abs(self.y);
            const abs_z = @abs(self.z);

            if (abs_x >= abs_y and abs_x >= abs_z) return 0;
            if (abs_y >= abs_z) return 1;
            return 2;
        }

        /// Get the index of the component with the smallest absolute value
        pub inline fn minComponentIndex(self: Self) u8 {
            const abs_x = @abs(self.x);
            const abs_y = @abs(self.y);
            const abs_z = @abs(self.z);

            if (abs_x <= abs_y and abs_x <= abs_z) return 0;
            if (abs_y <= abs_z) return 1;
            return 2;
        }

        // ========== Reflection and Refraction ==========

        /// Reflect vector around a normal
        pub inline fn reflect(self: Self, normal: Self) Self {
            const VecOps = @import("vector_ops.zig");
            return VecOps.reflect(self, normal);
        }

        /// Refract vector through a surface with given indices of refraction
        pub inline fn refract(self: Self, normal: Self, eta: T) ?Self {
            const VecOps = @import("vector_ops.zig");
            return VecOps.refract(self, normal, eta);
        }

        /// Fresnel reflection coefficient (Schlick's approximation)
        pub fn fresnel(self: Self, normal: Self, ior: T) T {
            const cos_theta = @abs(self.dot(normal));
            const r0 = (1.0 - ior) / (1.0 + ior);
            const r0_sq = r0 * r0;
            return r0_sq + (1.0 - r0_sq) * math.pow(T, 1.0 - cos_theta, 5.0);
        }

        // ========== Projection Operations ==========

        /// Project this vector onto another vector
        pub inline fn project(self: Self, onto: Self) Self {
            const VecOps = @import("vector_ops.zig");
            return VecOps.project(self, onto);
        }

        /// Project this vector onto a plane defined by its normal
        pub inline fn projectOnPlane(self: Self, plane_normal: Self) Self {
            const VecOps = @import("vector_ops.zig");
            return VecOps.projectOnPlane(self, plane_normal);
        }

        /// Get the rejection of this vector from another vector
        pub inline fn reject(self: Self, from: Self) Self {
            const VecOps = @import("vector_ops.zig");
            return VecOps.reject(self, from);
        }

        /// Gram-Schmidt orthogonalization
        pub inline fn gramSchmidt(self: Self, reference: Self) Self {
            const VecOps = @import("vector_ops.zig");
            return VecOps.gramSchmidt(self, reference);
        }

        // ========== Rotation Operations ==========

        /// Rotate around X axis by angle in radians
        pub inline fn rotateX(self: Self, angle: T) Self {
            const cos_a = @cos(angle);
            const sin_a = @sin(angle);
            return Self{
                .x = self.x,
                .y = self.y * cos_a - self.z * sin_a,
                .z = self.y * sin_a + self.z * cos_a,
            };
        }

        /// Rotate around Y axis by angle in radians
        pub inline fn rotateY(self: Self, angle: T) Self {
            const cos_a = @cos(angle);
            const sin_a = @sin(angle);
            return Self{
                .x = self.x * cos_a + self.z * sin_a,
                .y = self.y,
                .z = -self.x * sin_a + self.z * cos_a,
            };
        }

        /// Rotate around Z axis by angle in radians
        pub inline fn rotateZ(self: Self, angle: T) Self {
            const cos_a = @cos(angle);
            const sin_a = @sin(angle);
            return Self{
                .x = self.x * cos_a - self.y * sin_a,
                .y = self.x * sin_a + self.y * cos_a,
                .z = self.z,
            };
        }

        /// Rotate around arbitrary axis using Rodrigues' rotation formula
        pub fn rotateAxis(self: Self, axis: Self, angle: T) Self {
            const cos_a = @cos(angle);
            const sin_a = @sin(angle);
            const one_minus_cos = 1.0 - cos_a;

            const k = axis.normalize();
            const dot_product = self.dot(k);
            const cross_product = k.cross(self);

            return self.scale(cos_a)
                .add(cross_product.scale(sin_a))
                .add(k.scale(dot_product * one_minus_cos));
        }

        /// Rotate towards a target vector by a maximum angle
        pub fn rotateTowards(self: Self, target: Self, max_angle: T) Self {
            const angle = self.angleBetween(target);
            if (angle <= max_angle) return target.normalize();

            const t = max_angle / angle;
            return self.slerp(target, t);
        }

        // ========== Angular Operations ==========

        /// Calculate angle between this vector and another
        pub inline fn angleBetween(self: Self, other: Self) T {
            const dot_product = self.dot(other);
            const mag_product = self.magnitude() * other.magnitude();
            if (mag_product == 0) return 0;

            const cos_angle = @max(-1.0, @min(1.0, dot_product / mag_product));
            return math.acos(cos_angle);
        }

        /// Calculate signed angle between vectors around an axis
        pub fn signedAngleBetween(self: Self, other: Self, axis: Self) T {
            const angle = self.angleBetween(other);
            const cross_product = self.cross(other);
            const sign_value = if (cross_product.dot(axis) >= 0) @as(T, 1) else @as(T, -1);
            return angle * sign_value;
        }

        /// Calculate the solid angle subtended by a spherical triangle
        pub fn sphericalTriangleArea(a: Self, b: Self, c: Self) T {
            const a_norm = a.normalize();
            const b_norm = b.normalize();
            const c_norm = c.normalize();

            const angle_a = b_norm.angleBetween(c_norm);
            const angle_b = c_norm.angleBetween(a_norm);
            const angle_c = a_norm.angleBetween(b_norm);

            const s = (angle_a + angle_b + angle_c) * 0.5;
            const area = 4.0 * math.atan2(T, @sqrt(@tan(s * 0.5) * @tan((s - angle_a) * 0.5) * @tan((s - angle_b) * 0.5) * @tan((s - angle_c) * 0.5)), 1.0);

            return area;
        }

        // ========== Geometric Queries ==========

        /// Distance from point to plane defined by point and normal
        pub inline fn distanceToPlane(self: Self, plane_point: Self, plane_normal: Self) T {
            const normal = plane_normal.normalize();
            return @abs(self.sub(plane_point).dot(normal));
        }

        /// Distance from point to line segment
        pub fn distanceToLineSegment(self: Self, line_start: Self, line_end: Self) T {
            const line_vec = line_end.sub(line_start);
            const line_len_sq = line_vec.magnitudeSquared();

            if (line_len_sq == 0) return self.distanceTo(line_start);

            const t = @max(0, @min(1, self.sub(line_start).dot(line_vec) / line_len_sq));
            const projection = line_start.add(line_vec.scale(t));
            return self.distanceTo(projection);
        }

        /// Distance from point to infinite line
        pub fn distanceToLine(self: Self, line_point: Self, line_direction: Self) T {
            const line_dir = line_direction.normalize();
            const point_to_line = self.sub(line_point);
            const projection_length = point_to_line.dot(line_dir);
            const projection = line_dir.scale(projection_length);
            return point_to_line.sub(projection).magnitude();
        }

        /// Check if point is inside a sphere
        pub inline fn isInsideSphere(self: Self, sphere_center: Self, sphere_radius: T) bool {
            return self.distanceTo(sphere_center) <= sphere_radius;
        }

        /// Check if point is inside an axis-aligned bounding box
        pub inline fn isInsideAABB(self: Self, min_bounds: Self, max_bounds: Self) bool {
            return self.x >= min_bounds.x and self.x <= max_bounds.x and
                self.y >= min_bounds.y and self.y <= max_bounds.y and
                self.z >= min_bounds.z and self.z <= max_bounds.z;
        }

        // ========== Barycentric and Triangle Operations ==========

        /// Barycentric coordinates structure
        pub const BarycentricCoords = struct {
            u: T, // Weight for vertex A
            v: T, // Weight for vertex B
            w: T, // Weight for vertex C

            pub inline fn isValid(self: @This()) bool {
                const epsilon = if (T == f32) EPSILON_F32 else EPSILON_F64;
                return self.u >= -epsilon and self.v >= -epsilon and self.w >= -epsilon and
                    @abs(self.u + self.v + self.w - 1.0) <= epsilon;
            }

            pub inline fn toCartesian(self: @This(), a: Vec3(T), b: Vec3(T), c: Vec3(T)) Vec3(T) {
                return a.scale(self.u).add(b.scale(self.v)).add(c.scale(self.w));
            }
        };

        /// Calculate barycentric coordinates for a point relative to a triangle
        pub fn barycentric(point: Self, a: Self, b: Self, c: Self) BarycentricCoords {
            const v0 = b.sub(a);
            const v1 = c.sub(a);
            const v2 = point.sub(a);

            const d00 = v0.dot(v0);
            const d01 = v0.dot(v1);
            const d11 = v1.dot(v1);
            const d20 = v2.dot(v0);
            const d21 = v2.dot(v1);

            const denom = d00 * d11 - d01 * d01;
            if (@abs(denom) < EPSILON_F32) {
                return BarycentricCoords{ .u = 1.0, .v = 0.0, .w = 0.0 };
            }

            const v = (d11 * d20 - d01 * d21) / denom;
            const w = (d00 * d21 - d01 * d20) / denom;
            const u = 1.0 - v - w;

            return BarycentricCoords{ .u = u, .v = v, .w = w };
        }

        /// Check if a point is inside a triangle
        pub inline fn isPointInTriangle(point: Self, a: Self, b: Self, c: Self) bool {
            const coords = barycentric(point, a, b, c);
            return coords.isValid() and coords.u >= 0 and coords.v >= 0 and coords.w >= 0;
        }

        /// Calculate normal vector for a triangle (right-hand rule)
        pub inline fn triangleNormal(a: Self, b: Self, c: Self) Self {
            return b.sub(a).cross(c.sub(a)).normalize();
        }

        /// Calculate area of a triangle
        pub inline fn triangleArea(a: Self, b: Self, c: Self) T {
            return b.sub(a).cross(c.sub(a)).magnitude() * 0.5;
        }

        /// Find closest point on triangle to given point
        pub fn closestPointOnTriangle(point: Self, a: Self, b: Self, c: Self) Self {
            const coords = barycentric(point, a, b, c);

            // If point is inside triangle, return the point itself projected onto triangle plane
            if (coords.u >= 0 and coords.v >= 0 and coords.w >= 0) {
                return coords.toCartesian(a, b, c);
            }

            // Check edges and vertices
            var closest = a;
            var min_dist = point.distanceTo(a);

            // Check vertices
            const dist_b = point.distanceTo(b);
            const dist_c = point.distanceTo(c);

            if (dist_b < min_dist) {
                closest = b;
                min_dist = dist_b;
            }

            if (dist_c < min_dist) {
                closest = c;
                min_dist = dist_c;
            }

            // Check edges
            const edge_points = [3]Self{
                closestPointOnLineSegment(point, a, b),
                closestPointOnLineSegment(point, b, c),
                closestPointOnLineSegment(point, c, a),
            };

            for (edge_points) |edge_point| {
                const dist = point.distanceTo(edge_point);
                if (dist < min_dist) {
                    closest = edge_point;
                    min_dist = dist;
                }
            }

            return closest;
        }

        /// Find closest point on line segment to given point
        pub fn closestPointOnLineSegment(point: Self, line_start: Self, line_end: Self) Self {
            const line_vec = line_end.sub(line_start);
            const line_len_sq = line_vec.magnitudeSquared();

            if (line_len_sq == 0) return line_start;

            const t_value = @max(0, @min(1, point.sub(line_start).dot(line_vec) / line_len_sq));
            return line_start.add(line_vec.scale(t_value));
        }

        // ========== Advanced Geometric Operations ==========

        /// Create orthonormal basis from a single vector (Frisvad method)
        pub fn createOrthonormalBasis(self: Self) struct { tangent: Self, bitangent: Self, normal: Self } {
            const normal = self.normalize();

            var tangent: Self = undefined;
            if (@abs(normal.z) < 0.9) {
                tangent = Self.init(0, 0, 1).cross(normal).normalize();
            } else {
                tangent = Self.init(1, 0, 0).cross(normal).normalize();
            }

            const bitangent = normal.cross(tangent);

            return .{ .tangent = tangent, .bitangent = bitangent, .normal = normal };
        }

        /// Compute centroid of multiple points
        pub fn centroid(points: []const Self) Self {
            if (points.len == 0) return zero;

            var sum = zero;
            for (points) |point| {
                sum = sum.add(point);
            }
            return sum.divideScalar(@as(T, @floatFromInt(points.len)));
        }

        /// Compute variance of points around their centroid
        pub fn variance(points: []const Self) T {
            if (points.len <= 1) return 0;

            const center = centroid(points);
            var sum_sq_dist: T = 0;

            for (points) |point| {
                sum_sq_dist += point.distanceSquared(center);
            }

            return sum_sq_dist / @as(T, @floatFromInt(points.len - 1));
        }

        // ========== Utility Functions ==========

        /// Check if vector is approximately zero
        pub inline fn isZero(self: Self, epsilon: T) bool {
            return @abs(self.x) <= epsilon and @abs(self.y) <= epsilon and @abs(self.z) <= epsilon;
        }

        /// Check if vector is exactly zero
        pub inline fn isExactlyZero(self: Self) bool {
            return self.x == 0 and self.y == 0 and self.z == 0;
        }

        /// Check if two vectors are approximately equal
        pub inline fn approxEqual(self: Self, other: Self, epsilon: T) bool {
            return @abs(self.x - other.x) <= epsilon and
                @abs(self.y - other.y) <= epsilon and
                @abs(self.z - other.z) <= epsilon;
        }

        /// Check if two vectors are exactly equal
        pub inline fn equals(self: Self, other: Self) bool {
            return self.x == other.x and self.y == other.y and self.z == other.z;
        }

        /// Get component by index (0=x, 1=y, 2=z)
        pub inline fn getComponent(self: Self, index: u8) T {
            return switch (index) {
                0 => self.x,
                1 => self.y,
                2 => self.z,
                else => @panic("Invalid component index"),
            };
        }

        /// Set component by index (0=x, 1=y, 2=z)
        pub inline fn setComponent(self: *Self, index: u8, value: T) void {
            switch (index) {
                0 => self.x = value,
                1 => self.y = value,
                2 => self.z = value,
                else => @panic("Invalid component index"),
            }
        }

        /// Hash function for use in hash maps
        pub fn hash(self: Self) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hasher.update(std.mem.asBytes(&self.x));
            hasher.update(std.mem.asBytes(&self.y));
            hasher.update(std.mem.asBytes(&self.z));
            return hasher.final();
        }

        /// Format for printing
        pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            try writer.print("Vec3({d:.3}, {d:.3}, {d:.3})", .{ self.x, self.y, self.z });
        }

        // ========== SIMD Helper Functions ==========

        /// Load into SIMD vector (internal use)
        inline fn toSimd(self: Self) SimdF32x4 {
            return SimdF32x4{ self.x, self.y, self.z, 0 };
        }

        /// Create from SIMD vector (internal use)
        inline fn fromSimd(simd_vec: SimdF32x4) Self {
            return Self{ .x = simd_vec[0], .y = simd_vec[1], .z = simd_vec[2] };
        }

        /// Static method to get zero vector (for API compatibility)
        pub fn zeroVector() Self {
            return zero;
        }

        /// Get the length (magnitude) of the vector
        pub inline fn length(self: Self) T {
            return self.magnitude();
        }

        /// Get a vector perpendicular to this one
        pub fn perpendicular(self: Self) Self {
            // Find a non-parallel vector to cross with
            const ref = if (@abs(self.x) < @abs(self.y))
                Self.unit_x
            else
                Self.unit_y;
            return self.cross(ref);
        }
    };
}

/// Fast inverse square root implementation
inline fn fastInverseSqrt(comptime T: type, x: T) T {
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

// Common type aliases with enhanced precision support
pub const Vec3f = Vec3(f32);
pub const Vec3d = Vec3(f64);
pub const Vec3i = Vec3(i32);
pub const Vec3u = Vec3(u32);
pub const Vec3h = Vec3(f16);

// ========== Comprehensive Test Suite ==========

test "Vec3 basic operations with SIMD" {
    const v1 = Vec3f.init(1.0, 2.0, 3.0);
    const v2 = Vec3f.init(4.0, 5.0, 6.0);

    // Test addition
    const sum = v1.add(v2);
    try testing.expectEqual(@as(f32, 5.0), sum.x);
    try testing.expectEqual(@as(f32, 7.0), sum.y);
    try testing.expectEqual(@as(f32, 9.0), sum.z);

    // Test subtraction
    const diff = v2.sub(v1);
    try testing.expectEqual(@as(f32, 3.0), diff.x);
    try testing.expectEqual(@as(f32, 3.0), diff.y);
    try testing.expectEqual(@as(f32, 3.0), diff.z);

    // Test scalar multiplication
    const scaled = v1.scale(2.0);
    try testing.expectEqual(@as(f32, 2.0), scaled.x);
    try testing.expectEqual(@as(f32, 4.0), scaled.y);
    try testing.expectEqual(@as(f32, 6.0), scaled.z);

    // Test Hadamard product
    const hadamard = v1.hadamard(v2);
    try testing.expectEqual(@as(f32, 4.0), hadamard.x);
    try testing.expectEqual(@as(f32, 10.0), hadamard.y);
    try testing.expectEqual(@as(f32, 18.0), hadamard.z);
}

test "Vec3 geometric operations" {
    // Test dot product
    const v1 = Vec3f.init(1.0, 0.0, 0.0);
    const v2 = Vec3f.init(0.0, 1.0, 0.0);
    try testing.expectEqual(@as(f32, 0.0), v1.dot(v2));

    // Test cross product
    const cross = v1.cross(v2);
    try testing.expectEqual(@as(f32, 0.0), cross.x);
    try testing.expectEqual(@as(f32, 0.0), cross.y);
    try testing.expectEqual(@as(f32, 1.0), cross.z);

    // Test magnitude
    const v3 = Vec3f.init(3.0, 4.0, 0.0);
    try testing.expectEqual(@as(f32, 25.0), v3.magnitudeSquared());
    try testing.expectEqual(@as(f32, 5.0), v3.magnitude());

    // Test normalization
    const normalized = v3.normalize();
    try testing.expect(normalized.isNormalized(1e-6));
    try testing.expectApproxEqAbs(@as(f32, 0.6), normalized.x, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.8), normalized.y, 1e-6);
}

test "Vec3 advanced interpolation" {
    const v1 = Vec3f.init(1.0, 0.0, 0.0);
    const v2 = Vec3f.init(0.0, 1.0, 0.0);

    // Test linear interpolation
    const lerped = v1.lerp(v2, 0.5);
    try testing.expectApproxEqAbs(@as(f32, 0.5), lerped.x, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.5), lerped.y, 1e-6);

    // Test spherical interpolation
    const slerped = v1.slerp(v2, 0.5);
    try testing.expect(slerped.isNormalized(1e-6));

    // Test Bézier interpolation
    const p0 = Vec3f.init(0, 0, 0);
    const p1 = Vec3f.init(1, 1, 0);
    const p2 = Vec3f.init(2, 0, 0);
    const bezier = Vec3f.bezierQuad(p0, p1, p2, 0.5);
    try testing.expectApproxEqAbs(@as(f32, 1.0), bezier.x, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.5), bezier.y, 1e-6);
}

test "Vec3 rotation operations" {
    const v = Vec3f.init(1.0, 0.0, 0.0);

    // Test rotation around Z axis
    const rotated_z = v.rotateZ(math.pi / 2.0);
    try testing.expectApproxEqAbs(@as(f32, 0.0), rotated_z.x, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 1.0), rotated_z.y, 1e-6);

    // Test rotation around arbitrary axis
    const axis = Vec3f.init(0, 0, 1);
    const rotated_axis = v.rotateAxis(axis, math.pi / 2.0);
    try testing.expectApproxEqAbs(@as(f32, 0.0), rotated_axis.x, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 1.0), rotated_axis.y, 1e-6);
}

test "Vec3 reflection and refraction" {
    const incident = Vec3f.init(1.0, -1.0, 0.0).normalize();
    const normal = Vec3f.init(0.0, 1.0, 0.0);

    // Test reflection
    const reflected = incident.reflect(normal);
    try testing.expectApproxEqAbs(@as(f32, 1.0), reflected.x * math.sqrt2, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 1.0), reflected.y * math.sqrt2, 1e-6);

    // Test refraction
    const refracted = incident.refract(normal, 1.5);
    try testing.expect(refracted != null);
    if (refracted) |r| {
        try testing.expect(r.magnitude() > 0);
    }
}

test "Vec3 triangle operations" {
    const a = Vec3f.init(0.0, 0.0, 0.0);
    const b = Vec3f.init(1.0, 0.0, 0.0);
    const c = Vec3f.init(0.0, 1.0, 0.0);

    // Test triangle normal
    const normal = Vec3f.triangleNormal(a, b, c);
    try testing.expectApproxEqAbs(@as(f32, 0.0), normal.x, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.0), normal.y, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 1.0), normal.z, 1e-6);

    // Test point in triangle
    const inside_point = Vec3f.init(0.25, 0.25, 0.0);
    const outside_point = Vec3f.init(-0.5, -0.5, 0.0);

    try testing.expect(Vec3f.isPointInTriangle(inside_point, a, b, c));
    try testing.expect(!Vec3f.isPointInTriangle(outside_point, a, b, c));

    // Test barycentric coordinates
    const bary = Vec3f.barycentric(inside_point, a, b, c);
    try testing.expect(bary.isValid());
    try testing.expectApproxEqAbs(@as(f32, 1.0), bary.u + bary.v + bary.w, 1e-6);
}

test "Vec3 distance operations" {
    const p1 = Vec3f.init(0, 0, 0);
    const p2 = Vec3f.init(3, 4, 0);

    // Test Euclidean distance
    try testing.expectEqual(@as(f32, 5.0), p1.distanceTo(p2));

    // Test Manhattan distance
    try testing.expectEqual(@as(f32, 7.0), p1.manhattanDistance(p2));

    // Test Chebyshev distance
    try testing.expectEqual(@as(f32, 4.0), p1.chebyshevDistance(p2));
}

test "Vec3 coordinate system conversions" {
    const cartesian = Vec3f.init(1.0, 1.0, 1.0);

    // Test spherical conversion
    const spherical = cartesian.toSpherical();
    const back_to_cartesian = Vec3f.fromSpherical(spherical.radius, spherical.theta, spherical.phi);
    try testing.expect(cartesian.approxEqual(back_to_cartesian, 1e-6));

    // Test cylindrical conversion
    const cylindrical = cartesian.toCylindrical();
    const back_to_cartesian2 = Vec3f.fromCylindrical(cylindrical.radius, cylindrical.theta, cylindrical.height);
    try testing.expect(cartesian.approxEqual(back_to_cartesian2, 1e-6));
}

test "Vec3 utility functions" {
    const v = Vec3f.init(1.5, -2.3, 3.7);

    // Test component access
    try testing.expectEqual(@as(f32, 1.5), v.getComponent(0));
    try testing.expectEqual(@as(f32, -2.3), v.getComponent(1));
    try testing.expectEqual(@as(f32, 3.7), v.getComponent(2));

    // Test component-wise operations
    const abs_v = v.abs();
    try testing.expectEqual(@as(f32, 1.5), abs_v.x);
    try testing.expectEqual(@as(f32, 2.3), abs_v.y);
    try testing.expectEqual(@as(f32, 3.7), abs_v.z);

    // Test min/max component
    try testing.expectEqual(@as(f32, 3.7), v.maxComponent());
    try testing.expectEqual(@as(f32, 1.5), v.minComponent());
    try testing.expectEqual(@as(u8, 2), v.maxComponentIndex());
    try testing.expectEqual(@as(u8, 0), v.minComponentIndex());
}

test "Vec3 fast operations" {
    const v = Vec3f.init(3.0, 4.0, 0.0);

    // Test fast magnitude vs regular magnitude
    const fast_mag = v.fastMagnitude();
    const regular_mag = v.magnitude();
    try testing.expectApproxEqAbs(regular_mag, fast_mag, 0.1); // Fast version is less precise

    // Test fast normalize
    const fast_norm = v.fastNormalize();
    const regular_norm = v.normalize();
    try testing.expect(fast_norm.approxEqual(regular_norm, 0.01));
}
