//! MFS Engine - Mathematics Module
//! Comprehensive mathematics library for 3D graphics, physics, and general computation.
//!
//! This module provides:
//! - Vector types (Vec2, Vec3, Vec4) with SIMD optimizations
//! - Matrix types (Mat2, Mat3, Mat4) for transformations
//! - Quaternions for rotations
//! - Common mathematical functions and constants
//! - Utility functions for graphics and physics
//!
//! **Performance**: Optimized with SIMD operations where available
//! **Thread Safety**: All mathematical operations are thread-safe (immutable data)
//! **Platform**: All platforms with proper fallbacks
//!
//! **Example**:
//! ```zig
//! const math = @import("libs/math/mod.zig");
//!
//! const v1 = math.Vec3{ .x = 1.0, .y = 2.0, .z = 3.0 };
//! const v2 = math.Vec3{ .x = 4.0, .y = 5.0, .z = 6.0 };
//! const dot_product = v1.dot(v2);
//!
//! const transform = math.Mat4f.identity().translate(math.Vec3{ .x = 1.0, .y = 0.0, .z = 0.0 });
//! ```
//!
//! @thread-safe: yes (immutable operations)
//! @allocator-aware: no
//! @platform: all

const std = @import("std");
const builtin = @import("builtin");

// =============================================================================
// Public API - Core Types
// =============================================================================

// Core mathematical modules
pub const vec2 = @import("vec2.zig");
pub const vec3 = @import("vec3.zig");
pub const vec4 = @import("vec4.zig");
pub const mat2 = @import("mat2.zig");
pub const mat3 = @import("mat3.zig");
pub const mat4 = @import("mat4.zig");
pub const vector = @import("vector.zig");
pub const vector_ops = @import("vector_ops.zig");
pub const simd = @import("simd.zig");

// =============================================================================
// Type Aliases - Commonly Used Types
// =============================================================================

/// 2D vector with 32-bit floats
pub const Vec2 = vec2.Vec2(f32);
/// 2D vector with 32-bit floats (alias)
pub const Vec2f = vec2.Vec2(f32);
/// 2D vector with 64-bit floats
pub const Vec2d = vec2.Vec2(f64);
/// 2D vector with 32-bit signed integers
pub const Vec2i = vec2.Vec2i;

/// 3D vector with 32-bit floats
pub const Vec3 = vec3.Vec3f;
/// 3D vector with 32-bit floats (explicit)
pub const Vec3f = vec3.Vec3f;
/// 3D vector with 64-bit floats
pub const Vec3d = vec3.Vec3d;
/// 3D vector with 32-bit signed integers
pub const Vec3i = vec3.Vec3i;

/// 4D vector with 32-bit floats
pub const Vec4 = vec4.Vec4f;
/// 4D vector with 32-bit floats (explicit)
pub const Vec4f = vec4.Vec4f;
/// 4D vector with 64-bit floats
pub const Vec4d = vec4.Vec4d;
/// 4D vector with 32-bit signed integers
pub const Vec4i = vec4.Vec4i;

/// 2x2 matrix with 32-bit floats
pub const Mat2 = mat2.Mat2f;
/// 2x2 matrix with 32-bit floats (explicit)
pub const Mat2f = mat2.Mat2f;
/// 2x2 matrix with 64-bit floats
pub const Mat2d = mat2.Mat2d;

/// 3x3 matrix with 32-bit floats
pub const Mat3 = mat3.Mat3f;
/// 3x3 matrix with 32-bit floats (explicit)
pub const Mat3f = mat3.Mat3f;
/// 3x3 matrix with 64-bit floats
pub const Mat3d = mat3.Mat3d;

/// 4x4 matrix with 32-bit floats
pub const Mat4 = mat4.Mat4f;
/// 4x4 matrix with 32-bit floats (explicit)
pub const Mat4f = mat4.Mat4f;
/// 4x4 matrix with 64-bit floats
pub const Mat4d = mat4.Mat4d;

/// Generic vector type
pub const Vector = vector.Vector;
/// Quaternion for rotations
pub const Quaternion = vector.Quaternion;
/// Quaternion with 32-bit floats (alias)
pub const Quatf = vector.Quaternion;

// =============================================================================
// Mathematical Constants
// =============================================================================

/// Pi (π) - ratio of circle's circumference to diameter
pub const PI = std.math.pi;
/// Tau (τ) - full circle in radians (2π)
pub const TAU = 2.0 * PI;
/// Euler's number (e) - base of natural logarithm
pub const E = std.math.e;
/// Square root of 2
pub const SQRT2 = std.math.sqrt2;
/// Square root of 3
pub const SQRT3 = std.math.sqrt(3.0);
/// Half of pi (π/2)
pub const HALF_PI = PI / 2.0;
/// Quarter of pi (π/4)
pub const QUARTER_PI = PI / 4.0;

/// Conversion factor from degrees to radians
pub const DEG_TO_RAD = PI / 180.0;
/// Conversion factor from radians to degrees
pub const RAD_TO_DEG = 180.0 / PI;

/// Machine epsilon for 32-bit floats
pub const EPSILON_F32 = std.math.floatEps(f32);
/// Machine epsilon for 64-bit floats
pub const EPSILON_F64 = std.math.floatEps(f64);
/// Default epsilon for float comparisons
pub const EPSILON = EPSILON_F32;

/// Very small value for avoiding division by zero
pub const EPSILON_ZERO = 1e-8;
/// Golden ratio (φ)
pub const GOLDEN_RATIO = (1.0 + std.math.sqrt(5.0)) / 2.0;

// =============================================================================
// Utility Functions
// =============================================================================

/// Convert degrees to radians
///
/// **Parameters**:
/// - `degrees`: Angle in degrees
///
/// **Returns**: Angle in radians
///
/// **Example**:
/// ```zig
/// const rad = math.radians(90.0); // π/2
/// ```
pub fn radians(degrees: f32) f32 {
    return degrees * DEG_TO_RAD;
}

/// Convert radians to degrees
///
/// **Parameters**:
/// - `radians_value`: Angle in radians
///
/// **Returns**: Angle in degrees
///
/// **Example**:
/// ```zig
/// const deg = math.toDegrees(std.math.pi); // 180.0
/// ```
pub fn toDegrees(radians_value: f32) f32 {
    return radians_value * RAD_TO_DEG;
}

/// Clamp a value between minimum and maximum bounds
///
/// **Parameters**:
/// - `value`: Value to clamp
/// - `min_val`: Minimum bound (inclusive)
/// - `max_val`: Maximum bound (inclusive)
///
/// **Returns**: Clamped value
///
/// **Example**:
/// ```zig
/// const clamped = math.clamp(1.5, 0.0, 1.0); // 1.0
/// ```
pub fn clamp(value: anytype, min_val: @TypeOf(value), max_val: @TypeOf(value)) @TypeOf(value) {
    return @max(min_val, @min(max_val, value));
}

/// Linear interpolation between two values
///
/// **Parameters**:
/// - `a`: Start value
/// - `b`: End value
/// - `t`: Interpolation factor (typically 0.0 to 1.0)
///
/// **Returns**: Interpolated value
///
/// **Example**:
/// ```zig
/// const result = math.lerp(0.0, 10.0, 0.5); // 5.0
/// ```
pub fn lerp(a: anytype, b: @TypeOf(a), t: f32) @TypeOf(a) {
    return a + (b - a) * t;
}

/// Smooth Hermite interpolation
///
/// **Parameters**:
/// - `edge0`: Lower edge
/// - `edge1`: Upper edge
/// - `x`: Input value
///
/// **Returns**: Smoothly interpolated value
///
/// **Example**:
/// ```zig
/// const smooth = math.smoothstep(0.0, 1.0, 0.5); // ~0.5 but smoother curve
/// ```
pub fn smoothstep(edge0: f32, edge1: f32, x: f32) f32 {
    const t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

/// Step function - returns 0 or 1
///
/// **Parameters**:
/// - `edge`: Threshold value
/// - `x`: Input value
///
/// **Returns**: 0.0 if x < edge, 1.0 otherwise
///
/// **Example**:
/// ```zig
/// const result = math.step(0.5, 0.7); // 1.0
/// ```
pub fn step(edge: f32, x: f32) f32 {
    return if (x < edge) 0.0 else 1.0;
}

/// Sign function - returns -1, 0, or 1
///
/// **Parameters**:
/// - `x`: Input value
///
/// **Returns**: Sign of the input (-1, 0, or 1)
///
/// **Example**:
/// ```zig
/// const s = math.sign(-5.0); // -1.0
/// ```
pub fn sign(x: anytype) @TypeOf(x) {
    const T = @TypeOf(x);
    return switch (@typeInfo(T)) {
        .Int => if (x > 0) @as(T, 1) else if (x < 0) @as(T, -1) else @as(T, 0),
        .Float => if (x > 0.0) @as(T, 1.0) else if (x < 0.0) @as(T, -1.0) else @as(T, 0.0),
        else => @compileError("sign() only works with integer and float types"),
    };
}

/// Alias for lerp (common in shader languages)
///
/// **Parameters**:
/// - `x`: Start value
/// - `y`: End value
/// - `a`: Mix factor
///
/// **Returns**: Mixed value
pub fn mix(x: anytype, y: @TypeOf(x), a: f32) @TypeOf(x) {
    return lerp(x, y, a);
}

/// Fast inverse square root approximation
///
/// **Parameters**:
/// - `x`: Input value
///
/// **Returns**: Approximate 1/sqrt(x)
///
/// **Note**: Use std.math.sqrt for precise calculations
pub fn fastInverseSqrt(x: f32) f32 {
    if (x <= 0.0) return 0.0;

    // Quake III algorithm (with better magic number)
    const threehalfs: f32 = 1.5;
    var y = x;
    var i = @as(u32, @bitCast(y));
    i = 0x5f3759df - (i >> 1);
    y = @as(f32, @bitCast(i));
    y = y * (threehalfs - (x * 0.5 * y * y));
    return y;
}

/// Check if a floating point value is approximately equal to another
///
/// **Parameters**:
/// - `a`: First value
/// - `b`: Second value
/// - `epsilon`: Tolerance (optional, defaults to EPSILON)
///
/// **Returns**: True if values are approximately equal
///
/// **Example**:
/// ```zig
/// const equal = math.approxEqual(0.1 + 0.2, 0.3, null); // true
/// ```
pub fn approxEqual(a: f32, b: f32, epsilon: ?f32) bool {
    const eps = epsilon orelse EPSILON;
    return @abs(a - b) <= eps;
}
