//! Legacy stub: forwarded to new location in libs/math
// Re-export key types from the math library
const math_lib = @import("../libs/math/mod.zig");

pub const Vec2 = math_lib.Vec2;
pub const Vec2f = math_lib.Vec2f;
pub const Vec2d = math_lib.Vec2d;
pub const Vec2i = math_lib.Vec2i;
pub const Vec3 = math_lib.Vec3;
pub const Vec3f = math_lib.Vec3f;
pub const Vec3d = math_lib.Vec3d;
pub const Vec3i = math_lib.Vec3i;
pub const Vec4 = math_lib.Vec4;
pub const Vec4f = math_lib.Vec4f;
pub const Vec4d = math_lib.Vec4d;
pub const Vec4i = math_lib.Vec4i;
pub const Mat2 = math_lib.Mat2;
pub const Mat2f = math_lib.Mat2f;
pub const Mat2d = math_lib.Mat2d;
pub const Mat3 = math_lib.Mat3;
pub const Mat3f = math_lib.Mat3f;
pub const Mat3d = math_lib.Mat3d;
pub const Mat4 = math_lib.Mat4;
pub const Mat4f = math_lib.Mat4f;
pub const Mat4d = math_lib.Mat4d;
pub const Vector = math_lib.Vector;
pub const Quaternion = math_lib.Quaternion;
pub const Quatf = math_lib.Quatf;

// Re-export constants
pub const PI = math_lib.PI;
pub const TAU = math_lib.TAU;
pub const E = math_lib.E;
pub const EPSILON = math_lib.EPSILON;
