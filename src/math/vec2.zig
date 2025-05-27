const std = @import("std");
const math = std.math;
const testing = std.testing;
const builtin = @import("builtin");

/// SIMD optimizations module
const SimdOps = struct {
    const simd_enabled = switch (builtin.cpu.arch) {
        .x86_64 => true,
        .aarch64 => true,
        else => false,
    };

    inline fn canUseSimd(comptime T: type) bool {
        return simd_enabled and (T == f32 or T == f64);
    }

    inline fn simdAdd(comptime T: type, a: @Vector(2, T), b: @Vector(2, T)) @Vector(2, T) {
        return a + b;
    }

    inline fn simdSub(comptime T: type, a: @Vector(2, T), b: @Vector(2, T)) @Vector(2, T) {
        return a - b;
    }

    inline fn simdMul(comptime T: type, a: @Vector(2, T), b: @Vector(2, T)) @Vector(2, T) {
        return a * b;
    }

    inline fn simdDiv(comptime T: type, a: @Vector(2, T), b: @Vector(2, T)) @Vector(2, T) {
        return a / b;
    }

    inline fn simdScale(comptime T: type, v: @Vector(2, T), scalar: T) @Vector(2, T) {
        return v * @Vector(2, T){ scalar, scalar };
    }

    inline fn simdDot(comptime T: type, a: @Vector(2, T), b: @Vector(2, T)) T {
        const product = a * b;
        return product[0] + product[1];
    }

    inline fn simdSqrt(comptime T: type, v: @Vector(2, T)) @Vector(2, T) {
        return @sqrt(v);
    }

    inline fn simdAbs(comptime T: type, v: @Vector(2, T)) @Vector(2, T) {
        return @abs(v);
    }

    inline fn simdMin(comptime T: type, a: @Vector(2, T), b: @Vector(2, T)) @Vector(2, T) {
        return @min(a, b);
    }

    inline fn simdMax(comptime T: type, a: @Vector(2, T), b: @Vector(2, T)) @Vector(2, T) {
        return @max(a, b);
    }

    inline fn simdFloor(comptime T: type, v: @Vector(2, T)) @Vector(2, T) {
        return @floor(v);
    }

    inline fn simdCeil(comptime T: type, v: @Vector(2, T)) @Vector(2, T) {
        return @ceil(v);
    }

    inline fn simdRound(comptime T: type, v: @Vector(2, T)) @Vector(2, T) {
        return @round(v);
    }

    // Added SIMD optimizations for 3D vectors
    inline fn simdAdd3(comptime T: type, a: @Vector(3, T), b: @Vector(3, T)) @Vector(3, T) {
        return a + b;
    }

    inline fn simdSub3(comptime T: type, a: @Vector(3, T), b: @Vector(3, T)) @Vector(3, T) {
        return a - b;
    }

    inline fn simdMul3(comptime T: type, a: @Vector(3, T), b: @Vector(3, T)) @Vector(3, T) {
        return a * b;
    }

    inline fn simdDiv3(comptime T: type, a: @Vector(3, T), b: @Vector(3, T)) @Vector(3, T) {
        return a / b;
    }
};
/// Generic 2D vector implementation with SIMD optimizations
pub fn Vec2(comptime T: type) type {
    return struct {
        x: T,
        y: T,

        const Self = @This();

        /// Helper to convert to SIMD vector
        inline fn toSimd(self: Self) @Vector(2, T) {
            return @Vector(2, T){ self.x, self.y };
        }

        /// Helper to convert from SIMD vector
        inline fn fromSimd(v: @Vector(2, T)) Self {
            return Self{ .x = v[0], .y = v[1] };
        }

        /// Initialize vector with x and y components
        pub fn init(x: T, y: T) Self {
            return Self{ .x = x, .y = y };
        }

        /// Initialize vector with same value for both components
        pub fn splat(value: T) Self {
            return Self{ .x = value, .y = value };
        }

        /// Initialize from array
        pub fn fromArray(arr: [2]T) Self {
            return Self{ .x = arr[0], .y = arr[1] };
        }

        /// Convert to array
        pub fn toArray(self: Self) [2]T {
            return [2]T{ self.x, self.y };
        }

        /// Initialize from slice (bounds checked)
        pub fn fromSlice(slice: []const T) Self {
            std.debug.assert(slice.len >= 2);
            return Self{ .x = slice[0], .y = slice[1] };
        }

        /// Vector addition with SIMD optimization when available
        pub fn add(self: Self, other: Self) Self {
            if (comptime SimdOps.canUseSimd(T)) {
                const result = SimdOps.simdAdd(T, self.toSimd(), other.toSimd());
                return fromSimd(result);
            }
            const result = Self{
                .x = self.x + other.x,
                .y = self.y + other.y,
            };
            return result;
        }

        /// Vector subtraction with SIMD optimization when available
        pub fn sub(self: Self, other: Self) Self {
            if (comptime SimdOps.canUseSimd(T)) {
                return fromSimd(SimdOps.simdSub(T, self.toSimd(), other.toSimd()));
            }
            return Self{
                .x = self.x - other.x,
                .y = self.y - other.y,
            };
        }

        /// Component-wise multiplication with SIMD optimization when available
        pub fn mul(self: Self, other: Self) Self {
            if (comptime SimdOps.canUseSimd(T)) {
                return fromSimd(SimdOps.simdMul(T, self.toSimd(), other.toSimd()));
            }
            return Self{
                .x = self.x * other.x,
                .y = self.y * other.y,
            };
        }

        /// Component-wise division with SIMD optimization when available
        pub fn div(self: Self, other: Self) Self {
            if (comptime SimdOps.canUseSimd(T)) {
                return fromSimd(SimdOps.simdDiv(T, self.toSimd(), other.toSimd()));
            }
            return Self{
                .x = self.x / other.x,
                .y = self.y / other.y,
            };
        }

        /// Scalar multiplication with SIMD optimization when available
        pub fn scale(self: Self, scalar: T) Self {
            if (comptime SimdOps.canUseSimd(T)) {
                return fromSimd(SimdOps.simdScale(T, self.toSimd(), scalar));
            }
            return Self{
                .x = self.x * scalar,
                .y = self.y * scalar,
            };
        }

        /// Scalar division
        pub fn divScalar(self: Self, scalar: T) Self {
            return Self{
                .x = self.x / scalar,
                .y = self.y / scalar,
            };
        }

        /// Negation
        pub fn negate(self: Self) Self {
            return Self{
                .x = -self.x,
                .y = -self.y,
            };
        }

        /// Absolute value with SIMD optimization when available
        pub fn abs(self: Self) Self {
            if (comptime SimdOps.canUseSimd(T)) {
                return fromSimd(SimdOps.simdAbs(T, self.toSimd()));
            }
            return Self{
                .x = @abs(self.x),
                .y = @abs(self.y),
            };
        }

        /// Floor operation with SIMD optimization when available
        pub fn floor(self: Self) Self {
            if (comptime SimdOps.canUseSimd(T) and std.meta.trait.isFloat(T)) {
                return fromSimd(SimdOps.simdFloor(T, self.toSimd()));
            }
            return Self{
                .x = @floor(self.x),
                .y = @floor(self.y),
            };
        }

        /// Ceiling operation with SIMD optimization when available
        pub fn ceil(self: Self) Self {
            if (comptime SimdOps.canUseSimd(T) and std.meta.trait.isFloat(T)) {
                return fromSimd(SimdOps.simdCeil(T, self.toSimd()));
            }
            return Self{
                .x = @ceil(self.x),
                .y = @ceil(self.y),
            };
        }

        /// Round operation with SIMD optimization when available
        pub fn round(self: Self) Self {
            if (comptime SimdOps.canUseSimd(T) and std.meta.trait.isFloat(T)) {
                return fromSimd(SimdOps.simdRound(T, self.toSimd()));
            }
            return Self{
                .x = @round(self.x),
                .y = @round(self.y),
            };
        }

        /// Truncate operation
        pub fn trunc(self: Self) Self {
            return Self{
                .x = @trunc(self.x),
                .y = @trunc(self.y),
            };
        }

        /// Fractional part
        pub fn fract(self: Self) Self {
            return self.sub(self.floor());
        }

        /// Sign function (-1, 0, or 1)
        pub fn sign(self: Self) Self {
            return Self{
                .x = if (self.x > 0) @as(T, 1) else if (self.x < 0) @as(T, -1) else @as(T, 0),
                .y = if (self.y > 0) @as(T, 1) else if (self.y < 0) @as(T, -1) else @as(T, 0),
            };
        }

        /// Step function (0 if x < edge, 1 if x >= edge)
        pub fn step(edge: Self, x: Self) Self {
            return Self{
                .x = if (x.x < edge.x) @as(T, 0) else @as(T, 1),
                .y = if (x.y < edge.y) @as(T, 0) else @as(T, 1),
            };
        }

        /// Smooth step function
        pub fn smoothstep(edge0: Self, edge1: Self, x: Self) Self {
            const t = x.sub(edge0).div(edge1.sub(edge0)).clamp(Self.zero, Self.one);
            return t.mul(t).mul(Self.splat(3.0).sub(t.scale(2.0)));
        }

        /// Dot product with SIMD optimization when available
        pub fn dot(self: Self, other: Self) T {
            if (comptime SimdOps.canUseSimd(T)) {
                return SimdOps.simdDot(T, self.toSimd(), other.toSimd());
            }
            return self.x * other.x + self.y * other.y;
        }

        /// Cross product (returns scalar in 2D)
        pub fn cross(self: Self, other: Self) T {
            return self.x * other.y - self.y * other.x;
        }

        /// Calculate angle in radians between this vector and positive x-axis
        pub fn angleFromXAxis(self: Self) T {
            return math.atan2(T, self.y, self.x);
        }

        /// Calculate signed angle in radians between this vector and another vector
        pub fn signedAngleTo(self: Self, other: Self) T {
            return math.atan2(T, self.cross(other), self.dot(other));
        }

        /// Calculate absolute angle in radians between this vector and another vector
        pub fn angleTo(self: Self, other: Self) T {
            return @abs(self.signedAngleTo(other));
        }

        /// Project this vector onto another vector
        pub fn projectOnto(self: Self, other: Self) Self {
            const dot_product = self.dot(other);
            const other_length_sq = other.lengthSq();
            if (other_length_sq == 0) return Self.zero;
            return other.scale(dot_product / other_length_sq);
        }

        /// Get rejection of this vector from another vector (perpendicular component)
        pub fn reject(self: Self, other: Self) Self {
            return self.sub(self.projectOnto(other));
        }

        /// Get component of this vector in the direction of another vector
        pub fn component(self: Self, direction: Self) T {
            const normalized_dir = direction.normalize();
            return self.dot(normalized_dir);
        }

        /// Squared length (magnitude squared)
        pub fn lengthSq(self: Self) T {
            return self.dot(self);
        }

        /// Length (magnitude)
        pub fn length(self: Self) T {
            return @sqrt(self.lengthSq());
        }

        /// Fast inverse square root (approximate)
        pub fn invLength(self: Self) T {
            const len_sq = self.lengthSq();
            if (len_sq == 0) return 0;
            return 1.0 / @sqrt(len_sq);
        }

        /// Squared distance to another vector
        pub fn distanceSq(self: Self, other: Self) T {
            return self.sub(other).lengthSq();
        }

        /// Distance to another vector
        pub fn distance(self: Self, other: Self) T {
            return @sqrt(self.distanceSq(other));
        }

        /// Manhattan distance
        pub fn manhattanDistance(self: Self, other: Self) T {
            const diff = self.sub(other).abs();
            return diff.x + diff.y;
        }

        /// Chebyshev distance (maximum component difference)
        pub fn chebyshevDistance(self: Self, other: Self) T {
            const diff = self.sub(other).abs();
            return @max(diff.x, diff.y);
        }

        /// Minkowski distance with given p-norm
        pub fn minkowskiDistance(self: Self, other: Self, p: T) T {
            const diff = self.sub(other).abs();
            return math.pow(T, math.pow(T, diff.x, p) + math.pow(T, diff.y, p), 1.0 / p);
        }

        /// Normalize vector (return unit vector)
        pub fn normalize(self: Self) Self {
            const len = self.length();
            if (len == 0) return self;
            return self.divScalar(len);
        }

        /// Normalize vector or return fallback if zero length
        pub fn normalizeSafe(self: Self, fallback: Self) Self {
            const len = self.length();
            if (len == 0) return fallback;
            return self.divScalar(len);
        }

        /// Fast normalize using inverse square root
        pub fn normalizeFast(self: Self) Self {
            const inv_len = self.invLength();
            if (inv_len == 0) return self;
            return self.scale(inv_len);
        }

        /// Linear interpolation
        pub fn lerp(self: Self, other: Self, t: T) Self {
            return self.add(other.sub(self).scale(t));
        }

        /// Spherical linear interpolation (for normalized vectors)
        pub fn slerp(self: Self, other: Self, t: T) Self {
            const dot_product = self.dot(other);
            const theta = math.acos(math.clamp(dot_product, -1.0, 1.0));
            const sin_theta = math.sin(theta);

            if (@abs(sin_theta) < math.floatEps(T)) {
                return self.lerp(other, t);
            }

            const a = math.sin((1.0 - t) * theta) / sin_theta;
            const b = math.sin(t * theta) / sin_theta;

            return self.scale(a).add(other.scale(b));
        }

        /// Cubic interpolation
        pub fn cubic(self: Self, other: Self, t: T) Self {
            const t2 = t * t;
            const t3 = t2 * t;
            const a = 2.0 * t3 - 3.0 * t2 + 1.0;
            const b = -2.0 * t3 + 3.0 * t2;
            return self.scale(a).add(other.scale(b));
        }

        /// Hermite interpolation
        pub fn hermite(p0: Self, m0: Self, p1: Self, m1: Self, t: T) Self {
            const t2 = t * t;
            const t3 = t2 * t;
            const h00 = 2.0 * t3 - 3.0 * t2 + 1.0;
            const h10 = t3 - 2.0 * t2 + t;
            const h01 = -2.0 * t3 + 3.0 * t2;
            const h11 = t3 - t2;
            return p0.scale(h00).add(m0.scale(h10)).add(p1.scale(h01)).add(m1.scale(h11));
        }

        /// Bezier interpolation (quadratic)
        pub fn bezier(p0: Self, p1: Self, p2: Self, t: T) Self {
            const u = 1.0 - t;
            const uu = u * u;
            const tt = t * t;
            return p0.scale(uu).add(p1.scale(2.0 * u * t)).add(p2.scale(tt));
        }
        /// Component-wise minimum with SIMD optimization when available
        pub fn min(self: Self, other: Self) Self {
            if (comptime SimdOps.canUseSimd(T)) {
                const result = SimdOps.simdMin(T, self.toSimd(), other.toSimd());
                return Self{ .x = result[0], .y = result[1] };
            }
            return Self{
                .x = @min(self.x, other.x),
                .y = @min(self.y, other.y),
            };
        }

        /// Component-wise maximum with SIMD optimization when available
        pub fn max(self: Self, other: Self) Self {
            if (comptime SimdOps.canUseSimd(T)) {
                const result = SimdOps.simdMax(T, self.toSimd(), other.toSimd());
                return Self{ .x = result[0], .y = result[1] };
            }
            return Self{
                .x = @max(self.x, other.x),
                .y = @max(self.y, other.y),
            };
        }

        /// Clamp components between min and max
        pub fn clamp(self: Self, min_val: Self, max_val: Self) Self {
            return Self{
                .x = math.clamp(self.x, min_val.x, max_val.x),
                .y = math.clamp(self.y, min_val.y, max_val.y),
            };
        }

        /// Clamp length between min and max
        pub fn clampLength(self: Self, min_len: T, max_len: T) Self {
            const len = self.length();
            if (len == 0) return self;
            const clamped_len = math.clamp(len, min_len, max_len);
            return self.scale(clamped_len / len);
        }

        /// Wrap components to range [0, max)
        pub fn wrap(self: Self, max_val: Self) Self {
            return Self{
                .x = @mod(self.x, max_val.x),
                .y = @mod(self.y, max_val.y),
            };
        }

        /// Reflect vector around normal
        pub fn reflect(self: Self, normal: Self) Self {
            return self.sub(normal.scale(2.0 * self.dot(normal)));
        }

        /// Refract vector through surface with given ratio
        pub fn refract(self: Self, normal: Self, ratio: T) Self {
            const dot_product = self.dot(normal);
            const k = 1.0 - ratio * ratio * (1.0 - dot_product * dot_product);

            if (k < 0.0) {
                return Self.zero;
            }

            return self.scale(ratio).sub(normal.scale(ratio * dot_product + @sqrt(k)));
        }

        /// Project vector onto another vector
        pub fn project(self: Self, onto: Self) Self {
            const dot_product = self.dot(onto);
            const onto_length_sq = onto.lengthSq();
            if (onto_length_sq == 0) return Self.zero;
            return onto.scale(dot_product / onto_length_sq);
        }

        /// Rotate vector by angle (in radians)
        pub fn rotate(self: Self, rotation_angle: T) Self {
            const cos_a = math.cos(rotation_angle);
            const sin_a = math.sin(rotation_angle);
            return Self{
                .x = self.x * cos_a - self.y * sin_a,
                .y = self.x * sin_a + self.y * cos_a,
            };
        }

        pub fn angle(self: Self) T {
            return math.atan2(T, self.y, self.x);
        }

        /// Get angle between two vectors
        pub fn angleBetween(self: Self, other: Self) T {
            const cross_product = self.cross(other);
            const dot_product = self.dot(other);
            return math.atan2(T, cross_product, dot_product);
        }

        /// Move towards target by max distance
        pub fn approach(self: Self, target: Self, factor: T) Self {
            return self.add(target.sub(self).scale(factor));
        }

        /// Spring towards target
        pub fn spring(self: Self, target: Self, velocity: *Self, damping: T, stiffness: T, delta_time: T) Self {
            const displacement = self.sub(target);
            const spring_force = displacement.scale(-stiffness);
            const damping_force = velocity.*.scale(-damping);
            const acceleration = spring_force.add(damping_force);
            velocity.* = velocity.*.add(acceleration.scale(delta_time));
            return self.add(velocity.*.scale(delta_time));
        }

        /// Check if vector is approximately zero
        pub fn isZero(self: Self, epsilon: T) bool {
            return @abs(self.x) < epsilon and @abs(self.y) < epsilon;
        }

        /// Check if two vectors are approximately equal
        pub fn approxEqual(self: Self, other: Self, epsilon: T) bool {
            return @abs(self.x - other.x) < epsilon and @abs(self.y - other.y) < epsilon;
        }

        /// Check if vector is normalized (unit length)
        pub fn isNormalized(self: Self, epsilon: T) bool {
            const len_sq = self.lengthSq();
            return @abs(len_sq - 1.0) < epsilon;
        }

        /// Check if vector is finite (no inf or nan)
        pub fn isFinite(self: Self) bool {
            return math.isFinite(self.x) and math.isFinite(self.y);
        }

        /// Check if vector contains NaN
        pub fn isNan(self: Self) bool {
            return math.isNan(self.x) or math.isNan(self.y);
        }

        /// Check if vector contains infinity
        pub fn isInf(self: Self) bool {
            return math.isInf(self.x) or math.isInf(self.y);
        }

        /// Get minimum component
        pub fn minComponent(self: Self) T {
            return @min(self.x, self.y);
        }

        /// Get maximum component
        pub fn maxComponent(self: Self) T {
            return @max(self.x, self.y);
        }

        /// Get sum of components
        pub fn sum(self: Self) T {
            return self.x + self.y;
        }

        /// Get product of components
        pub fn product(self: Self) T {
            return self.x * self.y;
        }

        /// Get index of minimum component (0 for x, 1 for y)
        pub fn minComponentIndex(self: Self) u32 {
            return if (self.x <= self.y) 0 else 1;
        }

        /// Get index of maximum component (0 for x, 1 for y)
        pub fn maxComponentIndex(self: Self) u32 {
            return if (self.x >= self.y) 0 else 1;
        }

        // Extended swizzling operations
        pub fn xx(self: Self) Self {
            return Self{ .x = self.x, .y = self.x };
        }
        pub fn xy(self: Self) Self {
            return Self{ .x = self.x, .y = self.y };
        }
        pub fn yx(self: Self) Self {
            return Self{ .x = self.y, .y = self.x };
        }
        pub fn yy(self: Self) Self {
            return Self{ .x = self.y, .y = self.y };
        }

        /// Get perpendicular vector (rotated 90 degrees counter-clockwise)
        pub fn perp(self: Self) Self {
            return Self{ .x = -self.y, .y = self.x };
        }

        /// Get perpendicular vector (rotated 90 degrees clockwise)
        pub fn perpCW(self: Self) Self {
            return Self{ .x = self.y, .y = -self.x };
        }

        /// Get component by index (0 for x, 1 for y)
        pub fn getComponent(self: Self, index: u32) T {
            return switch (index) {
                0 => self.x,
                1 => self.y,
                else => unreachable,
            };
        }

        /// Set component by index (0 for x, 1 for y)
        pub fn setComponent(self: Self, index: u32, value: T) Self {
            var result = self;
            switch (index) {
                0 => result.x = value,
                1 => result.y = value,
                else => unreachable,
            }
            return result;
        }

        /// Hash function for use in hash maps
        pub fn hash(self: Self, hasher: anytype) void {
            hasher.update(std.mem.asBytes(&self.x));
            hasher.update(std.mem.asBytes(&self.y));
        }

        /// Equality comparison
        pub fn eql(self: Self, other: Self) bool {
            return self.x == other.x and self.y == other.y;
        }

        /// Ordering comparison for sorting
        pub fn order(self: Self, other: Self) std.math.Order {
            const len_self = self.lengthSq();
            const len_other = other.lengthSq();
            return std.math.order(len_self, len_other);
        }

        /// Format for printing
        pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            try writer.print("Vec2({d}, {d})", .{ self.x, self.y });
        }
    };
}

/// Generic 3D vector implementation with SIMD optimizations
pub fn Vec3(comptime T: type) type {
    return struct {
        const Self = @This();

        x: T,
        y: T,
        z: T,

        // Common constants
        pub const zero = Self{ .x = 0, .y = 0, .z = 0 };
        pub const one = Self{ .x = 1, .y = 1, .z = 1 };
        pub const unit_x = Self{ .x = 1, .y = 0, .z = 0 };
        pub const unit_y = Self{ .x = 0, .y = 1, .z = 0 };
        pub const unit_z = Self{ .x = 0, .y = 0, .z = 1 };
        pub const up = Self{ .x = 0, .y = 1, .z = 0 };
        pub const down = Self{ .x = 0, .y = -1, .z = 0 };
        pub const left = Self{ .x = -1, .y = 0, .z = 0 };
        pub const right = Self{ .x = 1, .y = 0, .z = 0 };

        /// Initialize a new vector
        pub fn init(x: T, y: T, z: T) Self {
            return Self{ .x = x, .y = y, .z = z };
        }

        /// Add two vectors
        pub fn add(self: Self, other: Self) Self {
            return Self{
                .x = self.x + other.x,
                .y = self.y + other.y,
                .z = self.z + other.z,
            };
        }

        /// Subtract two vectors
        pub fn sub(self: Self, other: Self) Self {
            return Self{
                .x = self.x - other.x,
                .y = self.y - other.y,
                .z = self.z - other.z,
            };
        }

        /// Scale vector by scalar
        pub fn scale(self: Self, scalar: T) Self {
            return Self{
                .x = self.x * scalar,
                .y = self.y * scalar,
                .z = self.z * scalar,
            };
        }

        /// Calculate dot product
        pub fn dot(self: Self, other: Self) T {
            return self.x * other.x + self.y * other.y + self.z * other.z;
        }

        /// Calculate cross product
        pub fn cross(self: Self, other: Self) Self {
            return Self{
                .x = self.y * other.z - self.z * other.y,
                .y = self.z * other.x - self.x * other.z,
                .z = self.x * other.y - self.y * other.x,
            };
        }

        /// Calculate magnitude squared
        pub fn magnitudeSquared(self: Self) T {
            return self.x * self.x + self.y * self.y + self.z * self.z;
        }

        /// Calculate magnitude
        pub fn magnitude(self: Self) T {
            return @sqrt(self.magnitudeSquared());
        }

        /// Normalize vector
        pub fn normalize(self: Self) Self {
            const mag = self.magnitude();
            if (mag == 0) return Self.zero;
            return self.scale(1.0 / mag);
        }

        /// Calculate distance to another vector
        pub fn distance(self: Self, other: Self) T {
            return self.sub(other).magnitude();
        }

        /// Linear interpolation between two vectors
        pub fn lerp(self: Self, other: Self, t: T) Self {
            return self.scale(1.0 - t).add(other.scale(t));
        }

        /// Check if vectors are equal
        pub fn eql(self: Self, other: Self) bool {
            return self.x == other.x and self.y == other.y and self.z == other.z;
        }

        /// Format for printing
        pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            try writer.print("Vec3({d}, {d}, {d})", .{ self.x, self.y, self.z });
        }
    };
}
