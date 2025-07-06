const std = @import("std");
const math = std.math;
const testing = std.testing;
const simd = @import("simd.zig");

/// Generic 4D vector implementation with SIMD optimizations
pub fn Vec4(comptime T: type) type {
    return struct {
        const Self = @This();

        x: T,
        y: T,
        z: T,
        w: T,

        // Common type aliases
        pub const zero = Self{ .x = 0, .y = 0, .z = 0, .w = 0 };
        pub const one = Self{ .x = 1, .y = 1, .z = 1, .w = 1 };
        pub const unit_x = Self{ .x = 1, .y = 0, .z = 0, .w = 0 };
        pub const unit_y = Self{ .x = 0, .y = 1, .z = 0, .w = 0 };
        pub const unit_z = Self{ .x = 0, .y = 0, .z = 1, .w = 0 };
        pub const unit_w = Self{ .x = 0, .y = 0, .z = 0, .w = 1 };

        // Common homogeneous coordinate values
        pub const point = Self{ .x = 0, .y = 0, .z = 0, .w = 1 };
        pub const direction = Self{ .x = 0, .y = 0, .z = 0, .w = 0 };

        // Common color values
        pub const black = Self{ .x = 0, .y = 0, .z = 0, .w = 1 };
        pub const white = Self{ .x = 1, .y = 1, .z = 1, .w = 1 };
        pub const red = Self{ .x = 1, .y = 0, .z = 0, .w = 1 };
        pub const green = Self{ .x = 0, .y = 1, .z = 0, .w = 1 };
        pub const blue = Self{ .x = 0, .y = 0, .z = 1, .w = 1 };
        pub const transparent = Self{ .x = 0, .y = 0, .z = 0, .w = 0 };

        /// Initialize vector with x, y, z and w components
        pub fn init(x: T, y: T, z: T, w: T) Self {
            return Self{ .x = x, .y = y, .z = z, .w = w };
        }

        /// Initialize vector with same value for all components
        pub fn splat(value: T) Self {
            return Self{ .x = value, .y = value, .z = value, .w = value };
        }

        /// Initialize from array
        pub fn fromArray(arr: [4]T) Self {
            return Self{ .x = arr[0], .y = arr[1], .z = arr[2], .w = arr[3] };
        }

        /// Convert to array
        pub fn toArray(self: Self) [4]T {
            return [4]T{ self.x, self.y, self.z, self.w };
        }

        /// Initialize from slice (bounds checked)
        pub fn fromSlice(slice: []const T) Self {
            std.debug.assert(slice.len >= 4);
            return Self{ .x = slice[0], .y = slice[1], .z = slice[2], .w = slice[3] };
        }

        /// Initialize from Vec3 with w component
        pub fn fromVec3(v: @import("vec3.zig").Vec3(T), w: T) Self {
            return Self{ .x = v.x, .y = v.y, .z = v.z, .w = w };
        }

        /// Extract Vec3 (xyz components)
        pub fn toVec3(self: Self) @import("vec3.zig").Vec3(T) {
            return @import("vec3.zig").Vec3(T).init(self.x, self.y, self.z);
        }

        /// Initialize RGB color with alpha
        pub fn rgba(r: T, g: T, b: T, a: T) Self {
            return Self{ .x = r, .y = g, .z = b, .w = a };
        }

        /// Initialize RGB color with alpha = 1
        pub fn rgb(r: T, g: T, b: T) Self {
            return Self{ .x = r, .y = g, .z = b, .w = 1 };
        }

        /// Vector addition with SIMD optimization when available
        pub fn add(self: Self, other: Self) Self {
            if (T == f32 and simd.SimdVec4Ops.isEnabled()) {
                var result: simd.SimdVec4f = undefined;
                simd.SimdVec4Ops.add(@as(simd.SimdVec4f, @bitCast(self)), @as(simd.SimdVec4f, @bitCast(other)), &result);
                return @as(Self, @bitCast(result));
            }
            return Self{
                .x = self.x + other.x,
                .y = self.y + other.y,
                .z = self.z + other.z,
                .w = self.w + other.w,
            };
        }

        /// Vector subtraction with SIMD optimization when available
        pub fn sub(self: Self, other: Self) Self {
            if (T == f32 and simd.SimdVec4Ops.isEnabled()) {
                var result: simd.SimdVec4f = undefined;
                simd.SimdVec4Ops.sub(@as(simd.SimdVec4f, @bitCast(self)), @as(simd.SimdVec4f, @bitCast(other)), &result);
                return @as(Self, @bitCast(result));
            }
            return Self{
                .x = self.x - other.x,
                .y = self.y - other.y,
                .z = self.z - other.z,
                .w = self.w - other.w,
            };
        }

        /// Component-wise multiplication
        pub fn mul(self: Self, other: Self) Self {
            return Self{
                .x = self.x * other.x,
                .y = self.y * other.y,
                .z = self.z * other.z,
                .w = self.w * other.w,
            };
        }

        /// Component-wise division
        pub fn div(self: Self, other: Self) Self {
            return Self{
                .x = self.x / other.x,
                .y = self.y / other.y,
                .z = self.z / other.z,
                .w = self.w / other.w,
            };
        }

        /// Scalar multiplication
        pub fn scale(self: Self, scalar: T) Self {
            return Self{
                .x = self.x * scalar,
                .y = self.y * scalar,
                .z = self.z * scalar,
                .w = self.w * scalar,
            };
        }

        /// Scalar division
        pub fn divScalar(self: Self, scalar: T) Self {
            return Self{
                .x = self.x / scalar,
                .y = self.y / scalar,
                .z = self.z / scalar,
                .w = self.w / scalar,
            };
        }

        /// Negation
        pub fn negate(self: Self) Self {
            return Self{
                .x = -self.x,
                .y = -self.y,
                .z = -self.z,
                .w = -self.w,
            };
        }

        /// Absolute value
        pub fn abs(self: Self) Self {
            return Self{
                .x = @abs(self.x),
                .y = @abs(self.y),
                .z = @abs(self.z),
                .w = @abs(self.w),
            };
        }

        /// Floor operation
        pub fn floor(self: Self) Self {
            return Self{
                .x = @floor(self.x),
                .y = @floor(self.y),
                .z = @floor(self.z),
                .w = @floor(self.w),
            };
        }

        /// Ceiling operation
        pub fn ceil(self: Self) Self {
            return Self{
                .x = @ceil(self.x),
                .y = @ceil(self.y),
                .z = @ceil(self.z),
                .w = @ceil(self.w),
            };
        }

        /// Round operation
        pub fn round(self: Self) Self {
            return Self{
                .x = @round(self.x),
                .y = @round(self.y),
                .z = @round(self.z),
                .w = @round(self.w),
            };
        }

        /// Dot product with SIMD optimization when available
        pub fn dot(self: Self, other: Self) T {
            if (T == f32 and simd.SimdVec4Ops.isEnabled()) {
                return simd.SimdVec4Ops.dot(@as(simd.SimdVec4f, @bitCast(self)), @as(simd.SimdVec4f, @bitCast(other)));
            }
            return self.x * other.x + self.y * other.y + self.z * other.z + self.w * other.w;
        }

        /// Convert RGB color to HSV (returns h: [0,360], s: [0,1], v: [0,1])
        pub fn toHSV(self: Self) Self {
            const r = self.x;
            const g = self.y;
            const b = self.z;
            const max_val = @max(r, @max(g, b));
            const min_val = @min(r, @min(g, b));
            const delta = max_val - min_val;

            var h: T = 0;
            const s: T = if (max_val > 0) delta / max_val else 0;
            const v: T = max_val;

            if (delta > 0) {
                if (max_val == r) {
                    h = 60.0 * @mod((g - b) / delta, 6.0);
                } else if (max_val == g) {
                    h = 60.0 * ((b - r) / delta + 2.0);
                } else {
                    h = 60.0 * ((r - g) / delta + 4.0);
                }
                if (h < 0) h += 360.0;
            }

            return Self{ .x = h, .y = s, .z = v, .w = self.w };
        }

        /// Convert HSV color to RGB (expects h: [0,360], s: [0,1], v: [0,1])
        pub fn fromHSV(h: T, s: T, v: T, alpha: T) Self {
            const c = v * s;
            const x = c * (1 - @abs(@mod(h / 60.0, 2.0) - 1));
            const m = v - c;

            var r: T = 0;
            var g: T = 0;
            var b: T = 0;

            if (h < 60.0) {
                r = c;
                g = x;
                b = 0;
            } else if (h < 120.0) {
                r = x;
                g = c;
                b = 0;
            } else if (h < 180.0) {
                r = 0;
                g = c;
                b = x;
            } else if (h < 240.0) {
                r = 0;
                g = x;
                b = c;
            } else if (h < 300.0) {
                r = x;
                g = 0;
                b = c;
            } else {
                r = c;
                g = 0;
                b = x;
            }

            return Self{
                .x = r + m,
                .y = g + m,
                .z = b + m,
                .w = alpha,
            };
        }

        /// Apply gamma correction to color
        pub fn applyGamma(self: Self, gamma: T) Self {
            const inv_gamma = 1.0 / gamma;
            return Self{
                .x = math.pow(T, self.x, inv_gamma),
                .y = math.pow(T, self.y, inv_gamma),
                .z = math.pow(T, self.z, inv_gamma),
                .w = self.w,
            };
        }

        /// Convert color to linear space
        pub fn toLinear(self: Self) Self {
            return self.applyGamma(2.2);
        }

        /// Convert color from linear to sRGB space
        pub fn toSRGB(self: Self) Self {
            return self.applyGamma(1.0 / 2.2);
        }

        /// Squared length (magnitude squared)
        pub fn lengthSq(self: Self) T {
            return self.dot(self);
        }

        /// Length (magnitude)
        pub fn length(self: Self) T {
            return @sqrt(self.lengthSq());
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
            return diff.x + diff.y + diff.z + diff.w;
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

        /// Perspective divide (for homogeneous coordinates)
        pub fn perspectiveDivide(self: Self) @import("vec3.zig").Vec3(T) {
            if (self.w == 0) return @import("vec3.zig").Vec3(T).zero;
            return @import("vec3.zig").Vec3(T).init(self.x / self.w, self.y / self.w, self.z / self.w);
        }

        /// Linear interpolation
        pub fn lerp(self: Self, other: Self, t: T) Self {
            return self.add(other.sub(self).scale(t));
        }

        /// Spherical linear interpolation (for normalized vectors)
        pub fn slerp(self: Self, other: Self, t: T) Self {
            const dot_product = math.clamp(self.dot(other), -1.0, 1.0);
            const theta = math.acos(dot_product);
            const sin_theta = math.sin(theta);

            if (@abs(sin_theta) < math.floatEps(T)) {
                return self.lerp(other, t);
            }

            const a = math.sin((1.0 - t) * theta) / sin_theta;
            const b = math.sin(t * theta) / sin_theta;

            return self.scale(a).add(other.scale(b));
        }

        /// Component-wise minimum
        pub fn min(self: Self, other: Self) Self {
            return Self{
                .x = @min(self.x, other.x),
                .y = @min(self.y, other.y),
                .z = @min(self.z, other.z),
                .w = @min(self.w, other.w),
            };
        }

        /// Component-wise maximum
        pub fn max(self: Self, other: Self) Self {
            return Self{
                .x = @max(self.x, other.x),
                .y = @max(self.y, other.y),
                .z = @max(self.z, other.z),
                .w = @max(self.w, other.w),
            };
        }

        /// Clamp components between min and max
        pub fn clamp(self: Self, min_val: Self, max_val: Self) Self {
            return Self{
                .x = math.clamp(self.x, min_val.x, max_val.x),
                .y = math.clamp(self.y, min_val.y, max_val.y),
                .z = math.clamp(self.z, min_val.z, max_val.z),
                .w = math.clamp(self.w, min_val.w, max_val.w),
            };
        }

        /// Reflect vector around normal
        pub inline fn reflect(self: Self, normal: Self) Self {
            const VecOps = @import("vector_ops.zig");
            return VecOps.reflect(self, normal);
        }

        /// Refract vector through surface with given ratio
        pub inline fn refract(self: Self, normal: Self, ratio: T) Self {
            const VecOps = @import("vector_ops.zig");
            return VecOps.refract(self, normal, ratio) orelse Self.zero;
        }

        /// Project vector onto another vector
        pub inline fn project(self: Self, onto: Self) Self {
            const VecOps = @import("vector_ops.zig");
            return VecOps.project(self, onto);
        }

        /// Check if vector is approximately zero
        pub fn isZero(self: Self, epsilon: T) bool {
            return @abs(self.x) < epsilon and @abs(self.y) < epsilon and
                @abs(self.z) < epsilon and @abs(self.w) < epsilon;
        }

        /// Check if two vectors are approximately equal
        pub fn approxEqual(self: Self, other: Self, epsilon: T) bool {
            return @abs(self.x - other.x) < epsilon and
                @abs(self.y - other.y) < epsilon and
                @abs(self.z - other.z) < epsilon and
                @abs(self.w - other.w) < epsilon;
        }

        /// Check if vector is normalized (unit length)
        pub fn isNormalized(self: Self, epsilon: T) bool {
            const len_sq = self.lengthSq();
            return @abs(len_sq - 1.0) < epsilon;
        }

        // Color-specific operations (when used as RGBA)

        /// Premultiply alpha
        pub fn premultiplyAlpha(self: Self) Self {
            return Self{
                .x = self.x * self.w,
                .y = self.y * self.w,
                .z = self.z * self.w,
                .w = self.w,
            };
        }

        /// Un-premultiply alpha
        pub fn unpremultiplyAlpha(self: Self) Self {
            if (self.w == 0) return self;
            return Self{
                .x = self.x / self.w,
                .y = self.y / self.w,
                .z = self.z / self.w,
                .w = self.w,
            };
        }

        /// Convert to gamma space
        pub fn toGamma(self: Self, gamma: T) Self {
            return Self{
                .x = math.pow(T, self.x, 1.0 / gamma),
                .y = math.pow(T, self.y, 1.0 / gamma),
                .z = math.pow(T, self.z, 1.0 / gamma),
                .w = self.w,
            };
        }

        /// Convert to linear space with custom gamma
        pub fn toLinearWithGamma(self: Self, gamma: T) Self {
            return Self{
                .x = math.pow(T, self.x, gamma),
                .y = math.pow(T, self.y, gamma),
                .z = math.pow(T, self.z, gamma),
                .w = self.w,
            };
        }

        // Swizzling operations - 2D
        pub fn xx(self: Self) @import("vec2.zig").Vec2(T) {
            return @import("vec2.zig").Vec2(T).init(self.x, self.x);
        }
        pub fn xy(self: Self) @import("vec2.zig").Vec2(T) {
            return @import("vec2.zig").Vec2(T).init(self.x, self.y);
        }
        pub fn xz(self: Self) @import("vec2.zig").Vec2(T) {
            return @import("vec2.zig").Vec2(T).init(self.x, self.z);
        }
        pub fn xw(self: Self) @import("vec2.zig").Vec2(T) {
            return @import("vec2.zig").Vec2(T).init(self.x, self.w);
        }
        pub fn yx(self: Self) @import("vec2.zig").Vec2(T) {
            return @import("vec2.zig").Vec2(T).init(self.y, self.x);
        }
        pub fn yy(self: Self) @import("vec2.zig").Vec2(T) {
            return @import("vec2.zig").Vec2(T).init(self.y, self.y);
        }
        pub fn yz(self: Self) @import("vec2.zig").Vec2(T) {
            return @import("vec2.zig").Vec2(T).init(self.y, self.z);
        }
        pub fn yw(self: Self) @import("vec2.zig").Vec2(T) {
            return @import("vec2.zig").Vec2(T).init(self.y, self.w);
        }
        pub fn zx(self: Self) @import("vec2.zig").Vec2(T) {
            return @import("vec2.zig").Vec2(T).init(self.z, self.x);
        }
        pub fn zy(self: Self) @import("vec2.zig").Vec2(T) {
            return @import("vec2.zig").Vec2(T).init(self.z, self.y);
        }
        pub fn zz(self: Self) @import("vec2.zig").Vec2(T) {
            return @import("vec2.zig").Vec2(T).init(self.z, self.z);
        }
        pub fn zw(self: Self) @import("vec2.zig").Vec2(T) {
            return @import("vec2.zig").Vec2(T).init(self.z, self.w);
        }
        pub fn wx(self: Self) @import("vec2.zig").Vec2(T) {
            return @import("vec2.zig").Vec2(T).init(self.w, self.x);
        }
        pub fn wy(self: Self) @import("vec2.zig").Vec2(T) {
            return @import("vec2.zig").Vec2(T).init(self.w, self.y);
        }
        pub fn wz(self: Self) @import("vec2.zig").Vec2(T) {
            return @import("vec2.zig").Vec2(T).init(self.w, self.z);
        }
        pub fn ww(self: Self) @import("vec2.zig").Vec2(T) {
            return @import("vec2.zig").Vec2(T).init(self.w, self.w);
        }

        // Swizzling operations - 3D
        pub fn xxx(self: Self) @import("vec3.zig").Vec3(T) {
            return @import("vec3.zig").Vec3(T).init(self.x, self.x, self.x);
        }
        pub fn xxy(self: Self) @import("vec3.zig").Vec3(T) {
            return @import("vec3.zig").Vec3(T).init(self.x, self.x, self.y);
        }
        pub fn xxz(self: Self) @import("vec3.zig").Vec3(T) {
            return @import("vec3.zig").Vec3(T).init(self.x, self.x, self.z);
        }
        pub fn xxw(self: Self) @import("vec3.zig").Vec3(T) {
            return @import("vec3.zig").Vec3(T).init(self.x, self.x, self.w);
        }
        pub fn xyz(self: Self) @import("vec3.zig").Vec3(T) {
            return @import("vec3.zig").Vec3(T).init(self.x, self.y, self.z);
        }
        pub fn xyw(self: Self) @import("vec3.zig").Vec3(T) {
            return @import("vec3.zig").Vec3(T).init(self.x, self.y, self.w);
        }
        pub fn xzw(self: Self) @import("vec3.zig").Vec3(T) {
            return @import("vec3.zig").Vec3(T).init(self.x, self.z, self.w);
        }
        pub fn yzw(self: Self) @import("vec3.zig").Vec3(T) {
            return @import("vec3.zig").Vec3(T).init(self.y, self.z, self.w);
        }

        /// Equality comparison
        pub fn eql(self: Self, other: Self) bool {
            return self.x == other.x and self.y == other.y and self.z == other.z and self.w == other.w;
        }

        /// Format for printing
        pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            try writer.print("Vec4({d}, {d}, {d}, {d})", .{ self.x, self.y, self.z, self.w });
        }
    };
}

// Common type aliases
pub const Vec4f = Vec4(f32);
pub const Vec4d = Vec4(f64);
pub const Vec4i = Vec4(i32);
pub const Vec4u = Vec4(u32);

// Tests
test "Vec4 basic operations" {
    const v1 = Vec4f.init(1.0, 2.0, 3.0, 4.0);
    const v2 = Vec4f.init(5.0, 6.0, 7.0, 8.0);

    const sum = v1.add(v2);
    try testing.expectEqual(@as(f32, 6.0), sum.x);
    try testing.expectEqual(@as(f32, 8.0), sum.y);
    try testing.expectEqual(@as(f32, 10.0), sum.z);
    try testing.expectEqual(@as(f32, 12.0), sum.w);

    const diff = v2.sub(v1);
    try testing.expectEqual(@as(f32, 4.0), diff.x);
    try testing.expectEqual(@as(f32, 4.0), diff.y);
    try testing.expectEqual(@as(f32, 4.0), diff.z);
    try testing.expectEqual(@as(f32, 4.0), diff.w);

    const scaled = v1.scale(2.0);
    try testing.expectEqual(@as(f32, 2.0), scaled.x);
    try testing.expectEqual(@as(f32, 4.0), scaled.y);
    try testing.expectEqual(@as(f32, 6.0), scaled.z);
    try testing.expectEqual(@as(f32, 8.0), scaled.w);
}

test "Vec4 dot product" {
    const v1 = Vec4f.init(1.0, 2.0, 3.0, 4.0);
    const v2 = Vec4f.init(5.0, 6.0, 7.0, 8.0);

    const dot = v1.dot(v2);
    try testing.expectEqual(@as(f32, 70.0), dot); // 1*5 + 2*6 + 3*7 + 4*8 = 5 + 12 + 21 + 32 = 70
}

test "Vec4 color operations" {
    const color = Vec4f.rgba(0.5, 0.7, 0.9, 0.8);

    const premult = color.premultiplyAlpha();
    try testing.expectEqual(@as(f32, 0.4), premult.x);
    try testing.expectEqual(@as(f32, 0.56), premult.y);
    try testing.expectEqual(@as(f32, 0.72), premult.z);
    try testing.expectEqual(@as(f32, 0.8), premult.w);

    // Test HSV conversion
    const hsv = color.toHSV();
    try testing.expect(@abs(hsv.x - 210.0) < 1.0); // Hue around 210 degrees for light blue
    try testing.expect(@abs(hsv.y - 0.444) < 0.01); // Saturation ~0.444
    try testing.expect(@abs(hsv.z - 0.9) < 0.01); // Value 0.9

    // Test HSV to RGB conversion
    const rgb = Vec4f.fromHSV(210.0, 0.444, 0.9, 0.8);
    try testing.expect(rgb.approxEqual(color, 0.01));

    // Test gamma correction
    const gamma_corrected = color.applyGamma(2.2);
    try testing.expect(gamma_corrected.w == color.w); // Alpha unchanged
    try testing.expect(gamma_corrected.x < color.x); // RGB values decrease due to gamma > 1

    // Test linear/sRGB conversion
    const linear = color.toLinear();
    const srgb = linear.toSRGB();
    try testing.expect(srgb.approxEqual(color, 0.01));
}

test "Vec4 perspective divide" {
    const homogeneous = Vec4f.init(2.0, 4.0, 6.0, 2.0);
    const cartesian = homogeneous.perspectiveDivide();

    try testing.expectEqual(@as(f32, 1.0), cartesian.x);
    try testing.expectEqual(@as(f32, 2.0), cartesian.y);
    try testing.expectEqual(@as(f32, 3.0), cartesian.z);
}

test "Vec4 from Vec3" {
    const v3 = @import("vec3.zig").Vec3f.init(1.0, 2.0, 3.0);
    const v4 = Vec4f.fromVec3(v3, 4.0);

    try testing.expectEqual(@as(f32, 1.0), v4.x);
    try testing.expectEqual(@as(f32, 2.0), v4.y);
    try testing.expectEqual(@as(f32, 3.0), v4.z);
    try testing.expectEqual(@as(f32, 4.0), v4.w);
}
