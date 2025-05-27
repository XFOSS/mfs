const std = @import("std");
const math = std.math;
const testing = std.testing;
const Vec3f = @import("vec3.zig").Vec3f;
const Vec4f = @import("vec4.zig").Vec4f;
const simd = @import("simd.zig");

/// Generic 4x4 matrix implementation with column-major storage
pub fn Mat4(comptime T: type) type {
    return struct {
        const Self = @This();

        // Column-major storage: m[column][row]
        m: [4][4]T,

        // Common matrices
        pub const identity = Self{
            .m = [4][4]T{
                [4]T{ 1, 0, 0, 0 },
                [4]T{ 0, 1, 0, 0 },
                [4]T{ 0, 0, 1, 0 },
                [4]T{ 0, 0, 0, 1 },
            },
        };

        pub const zero = Self{
            .m = [4][4]T{
                [4]T{ 0, 0, 0, 0 },
                [4]T{ 0, 0, 0, 0 },
                [4]T{ 0, 0, 0, 0 },
                [4]T{ 0, 0, 0, 0 },
            },
        };

        /// Initialize matrix from column vectors
        pub fn init(col0: [4]T, col1: [4]T, col2: [4]T, col3: [4]T) Self {
            return Self{
                .m = [4][4]T{ col0, col1, col2, col3 },
            };
        }

        /// Initialize from array (column-major)
        pub fn fromArray(arr: [16]T) Self {
            return Self{
                .m = [4][4]T{
                    [4]T{ arr[0], arr[1], arr[2], arr[3] },
                    [4]T{ arr[4], arr[5], arr[6], arr[7] },
                    [4]T{ arr[8], arr[9], arr[10], arr[11] },
                    [4]T{ arr[12], arr[13], arr[14], arr[15] },
                },
            };
        }

        /// Convert to array (column-major)
        pub fn toArray(self: Self) [16]T {
            return [16]T{
                self.m[0][0], self.m[0][1], self.m[0][2], self.m[0][3],
                self.m[1][0], self.m[1][1], self.m[1][2], self.m[1][3],
                self.m[2][0], self.m[2][1], self.m[2][2], self.m[2][3],
                self.m[3][0], self.m[3][1], self.m[3][2], self.m[3][3],
            };
        }

        /// Initialize from row vectors
        pub fn fromRows(row0: [4]T, row1: [4]T, row2: [4]T, row3: [4]T) Self {
            return Self{
                .m = [4][4]T{
                    [4]T{ row0[0], row1[0], row2[0], row3[0] },
                    [4]T{ row0[1], row1[1], row2[1], row3[1] },
                    [4]T{ row0[2], row1[2], row2[2], row3[2] },
                    [4]T{ row0[3], row1[3], row2[3], row3[3] },
                },
            };
        }

        /// Get column vector
        pub fn getColumn(self: Self, col: u32) [4]T {
            return self.m[col];
        }

        /// Get row vector
        pub fn getRow(self: Self, row: u32) [4]T {
            return [4]T{ self.m[0][row], self.m[1][row], self.m[2][row], self.m[3][row] };
        }

        /// Set column vector
        pub fn setColumn(self: *Self, col: u32, values: [4]T) void {
            self.m[col] = values;
        }

        /// Set row vector
        pub fn setRow(self: *Self, row: u32, values: [4]T) void {
            self.m[0][row] = values[0];
            self.m[1][row] = values[1];
            self.m[2][row] = values[2];
            self.m[3][row] = values[3];
        }

        /// Matrix addition
        pub fn add(self: Self, other: Self) Self {
            var result = Self.zero;
            for (0..4) |col| {
                for (0..4) |row| {
                    result.m[col][row] = self.m[col][row] + other.m[col][row];
                }
            }
            return result;
        }

        /// Matrix subtraction
        pub fn sub(self: Self, other: Self) Self {
            var result = Self.zero;
            for (0..4) |col| {
                for (0..4) |row| {
                    result.m[col][row] = self.m[col][row] - other.m[col][row];
                }
            }
            return result;
        }

        /// Matrix multiplication
        pub fn mul(self: Self, other: Self) Self {
            if (T == f32) {
                // Use SIMD optimization for f32
                const a_arr = self.toArray();
                const b_arr = other.toArray();
                const result_arr = simd.SimdMatrixOps.mulMat4(a_arr, b_arr);
                return Self.fromArray(result_arr);
            } else {
                // Fallback scalar implementation
                var result = Self.zero;
                for (0..4) |col| {
                    for (0..4) |row| {
                        var sum: T = 0;
                        for (0..4) |k| {
                            sum += self.m[k][row] * other.m[col][k];
                        }
                        result.m[col][row] = sum;
                    }
                }
                return result;
            }
        }

        /// Scalar multiplication
        pub fn scale(self: Self, scalar: T) Self {
            var result = Self.zero;
            for (0..4) |col| {
                for (0..4) |row| {
                    result.m[col][row] = self.m[col][row] * scalar;
                }
            }
            return result;
        }

        /// Matrix-vector multiplication
        pub fn mulVec4(self: Self, vec: @import("vec4.zig").Vec4(T)) @import("vec4.zig").Vec4(T) {
            if (T == f32) {
                // Use SIMD optimization for f32
                const mat_arr = self.toArray();
                const vec_simd = switch (@import("builtin").cpu.arch) {
                    .x86_64, .x86, .aarch64, .arm => @Vector(4, f32){ vec.x, vec.y, vec.z, vec.w },
                    else => simd.SimdVec4f{ .x = vec.x, .y = vec.y, .z = vec.z, .w = vec.w },
                };
                const result_simd = simd.SimdMatrixOps.mulMatVec4(mat_arr, vec_simd);

                return switch (@import("builtin").cpu.arch) {
                    .x86_64, .x86, .aarch64, .arm => @import("vec4.zig").Vec4(T).init(result_simd[0], result_simd[1], result_simd[2], result_simd[3]),
                    else => @import("vec4.zig").Vec4(T).init(result_simd.x, result_simd.y, result_simd.z, result_simd.w),
                };
            } else {
                return @import("vec4.zig").Vec4(T).init(
                    self.m[0][0] * vec.x + self.m[1][0] * vec.y + self.m[2][0] * vec.z + self.m[3][0] * vec.w,
                    self.m[0][1] * vec.x + self.m[1][1] * vec.y + self.m[2][1] * vec.z + self.m[3][1] * vec.w,
                    self.m[0][2] * vec.x + self.m[1][2] * vec.y + self.m[2][2] * vec.z + self.m[3][2] * vec.w,
                    self.m[0][3] * vec.x + self.m[1][3] * vec.y + self.m[2][3] * vec.z + self.m[3][3] * vec.w,
                );
            }
        }

        /// Matrix-vector multiplication (transform point)
        pub fn mulPoint(self: Self, point: @import("vec3.zig").Vec3(T)) @import("vec3.zig").Vec3(T) {
            const vec4 = @import("vec4.zig").Vec4(T).fromVec3(point, 1.0);
            const result = self.mulVec4(vec4);
            return result.perspectiveDivide();
        }

        /// Matrix-vector multiplication (transform direction)
        pub fn mulDirection(self: Self, dir: @import("vec3.zig").Vec3(T)) @import("vec3.zig").Vec3(T) {
            const vec4 = @import("vec4.zig").Vec4(T).fromVec3(dir, 0.0);
            const result = self.mulVec4(vec4);
            return result.toVec3();
        }

        /// Transpose matrix
        pub fn transpose(self: Self) Self {
            return Self{
                .m = [4][4]T{
                    [4]T{ self.m[0][0], self.m[1][0], self.m[2][0], self.m[3][0] },
                    [4]T{ self.m[0][1], self.m[1][1], self.m[2][1], self.m[3][1] },
                    [4]T{ self.m[0][2], self.m[1][2], self.m[2][2], self.m[3][2] },
                    [4]T{ self.m[0][3], self.m[1][3], self.m[2][3], self.m[3][3] },
                },
            };
        }

        /// Calculate determinant
        pub fn determinant(self: Self) T {
            const a = self.m[0][0];
            const b = self.m[1][0];
            const c = self.m[2][0];
            const d = self.m[3][0];
            const e = self.m[0][1];
            const f = self.m[1][1];
            const g = self.m[2][1];
            const h = self.m[3][1];
            const i = self.m[0][2];
            const j = self.m[1][2];
            const k = self.m[2][2];
            const l = self.m[3][2];
            const m = self.m[0][3];
            const n = self.m[1][3];
            const o = self.m[2][3];
            const p = self.m[3][3];

            return a * (f * (k * p - l * o) - g * (j * p - l * n) + h * (j * o - k * n)) -
                b * (e * (k * p - l * o) - g * (i * p - l * m) + h * (i * o - k * m)) +
                c * (e * (j * p - l * n) - f * (i * p - l * m) + h * (i * n - j * m)) -
                d * (e * (j * o - k * n) - f * (i * o - k * m) + g * (i * n - j * m));
        }

        /// Calculate inverse matrix
        pub fn inverse(self: Self) ?Self {
            const det = self.determinant();
            if (@abs(det) < math.floatEps(T)) return null;

            const inv_det = 1.0 / det;
            var result: Self = undefined;

            // Calculate adjugate matrix
            result.m[0][0] = (self.m[1][1] * (self.m[2][2] * self.m[3][3] - self.m[2][3] * self.m[3][2]) -
                self.m[1][2] * (self.m[2][1] * self.m[3][3] - self.m[2][3] * self.m[3][1]) +
                self.m[1][3] * (self.m[2][1] * self.m[3][2] - self.m[2][2] * self.m[3][1])) * inv_det;

            result.m[1][0] = -(self.m[1][0] * (self.m[2][2] * self.m[3][3] - self.m[2][3] * self.m[3][2]) -
                self.m[1][2] * (self.m[2][0] * self.m[3][3] - self.m[2][3] * self.m[3][0]) +
                self.m[1][3] * (self.m[2][0] * self.m[3][2] - self.m[2][2] * self.m[3][0])) * inv_det;

            result.m[2][0] = (self.m[1][0] * (self.m[2][1] * self.m[3][3] - self.m[2][3] * self.m[3][1]) -
                self.m[1][1] * (self.m[2][0] * self.m[3][3] - self.m[2][3] * self.m[3][0]) +
                self.m[1][3] * (self.m[2][0] * self.m[3][1] - self.m[2][1] * self.m[3][0])) * inv_det;

            result.m[3][0] = -(self.m[1][0] * (self.m[2][1] * self.m[3][2] - self.m[2][2] * self.m[3][1]) -
                self.m[1][1] * (self.m[2][0] * self.m[3][2] - self.m[2][2] * self.m[3][0]) +
                self.m[1][2] * (self.m[2][0] * self.m[3][1] - self.m[2][1] * self.m[3][0])) * inv_det;

            result.m[0][1] = -(self.m[0][1] * (self.m[2][2] * self.m[3][3] - self.m[2][3] * self.m[3][2]) -
                self.m[0][2] * (self.m[2][1] * self.m[3][3] - self.m[2][3] * self.m[3][1]) +
                self.m[0][3] * (self.m[2][1] * self.m[3][2] - self.m[2][2] * self.m[3][1])) * inv_det;

            result.m[1][1] = (self.m[0][0] * (self.m[2][2] * self.m[3][3] - self.m[2][3] * self.m[3][2]) -
                self.m[0][2] * (self.m[2][0] * self.m[3][3] - self.m[2][3] * self.m[3][0]) +
                self.m[0][3] * (self.m[2][0] * self.m[3][2] - self.m[2][2] * self.m[3][0])) * inv_det;

            result.m[2][1] = -(self.m[0][0] * (self.m[2][1] * self.m[3][3] - self.m[2][3] * self.m[3][1]) -
                self.m[0][1] * (self.m[2][0] * self.m[3][3] - self.m[2][3] * self.m[3][0]) +
                self.m[0][3] * (self.m[2][0] * self.m[3][1] - self.m[2][1] * self.m[3][0])) * inv_det;

            result.m[3][1] = (self.m[0][0] * (self.m[2][1] * self.m[3][2] - self.m[2][2] * self.m[3][1]) -
                self.m[0][1] * (self.m[2][0] * self.m[3][2] - self.m[2][2] * self.m[3][0]) +
                self.m[0][2] * (self.m[2][0] * self.m[3][1] - self.m[2][1] * self.m[3][0])) * inv_det;

            result.m[0][2] = (self.m[0][1] * (self.m[1][2] * self.m[3][3] - self.m[1][3] * self.m[3][2]) -
                self.m[0][2] * (self.m[1][1] * self.m[3][3] - self.m[1][3] * self.m[3][1]) +
                self.m[0][3] * (self.m[1][1] * self.m[3][2] - self.m[1][2] * self.m[3][1])) * inv_det;

            result.m[1][2] = -(self.m[0][0] * (self.m[1][2] * self.m[3][3] - self.m[1][3] * self.m[3][2]) -
                self.m[0][2] * (self.m[1][0] * self.m[3][3] - self.m[1][3] * self.m[3][0]) +
                self.m[0][3] * (self.m[1][0] * self.m[3][2] - self.m[1][2] * self.m[3][0])) * inv_det;

            result.m[2][2] = (self.m[0][0] * (self.m[1][1] * self.m[3][3] - self.m[1][3] * self.m[3][1]) -
                self.m[0][1] * (self.m[1][0] * self.m[3][3] - self.m[1][3] * self.m[3][0]) +
                self.m[0][3] * (self.m[1][0] * self.m[3][1] - self.m[1][1] * self.m[3][0])) * inv_det;

            result.m[3][2] = -(self.m[0][0] * (self.m[1][1] * self.m[3][2] - self.m[1][2] * self.m[3][1]) -
                self.m[0][1] * (self.m[1][0] * self.m[3][2] - self.m[1][2] * self.m[3][0]) +
                self.m[0][2] * (self.m[1][0] * self.m[3][1] - self.m[1][1] * self.m[3][0])) * inv_det;

            result.m[0][3] = -(self.m[0][1] * (self.m[1][2] * self.m[2][3] - self.m[1][3] * self.m[2][2]) -
                self.m[0][2] * (self.m[1][1] * self.m[2][3] - self.m[1][3] * self.m[2][1]) +
                self.m[0][3] * (self.m[1][1] * self.m[2][2] - self.m[1][2] * self.m[2][1])) * inv_det;

            result.m[1][3] = (self.m[0][0] * (self.m[1][2] * self.m[2][3] - self.m[1][3] * self.m[2][2]) -
                self.m[0][2] * (self.m[1][0] * self.m[2][3] - self.m[1][3] * self.m[2][0]) +
                self.m[0][3] * (self.m[1][0] * self.m[2][2] - self.m[1][2] * self.m[2][0])) * inv_det;

            result.m[2][3] = -(self.m[0][0] * (self.m[1][1] * self.m[2][3] - self.m[1][3] * self.m[2][1]) -
                self.m[0][1] * (self.m[1][0] * self.m[2][3] - self.m[1][3] * self.m[2][0]) +
                self.m[0][3] * (self.m[1][0] * self.m[2][1] - self.m[1][1] * self.m[2][0])) * inv_det;

            result.m[3][3] = (self.m[0][0] * (self.m[1][1] * self.m[2][2] - self.m[1][2] * self.m[2][1]) -
                self.m[0][1] * (self.m[1][0] * self.m[2][2] - self.m[1][2] * self.m[2][0]) +
                self.m[0][2] * (self.m[1][0] * self.m[2][1] - self.m[1][1] * self.m[2][0])) * inv_det;

            return result;
        }

        /// Fast inverse for transformation matrices (assumes bottom row is [0,0,0,1])
        pub fn inverseTransform(self: Self) Self {
            // Extract upper-left 3x3 rotation matrix
            const r00 = self.m[0][0];
            const r01 = self.m[1][0];
            const r02 = self.m[2][0];
            const r10 = self.m[0][1];
            const r11 = self.m[1][1];
            const r12 = self.m[2][1];
            const r20 = self.m[0][2];
            const r21 = self.m[1][2];
            const r22 = self.m[2][2];

            // Extract translation
            const tx = self.m[3][0];
            const ty = self.m[3][1];
            const tz = self.m[3][2];

            // Transpose rotation matrix (inverse of orthogonal matrix)
            // Apply negative translation
            const inv_tx = -(r00 * tx + r10 * ty + r20 * tz);
            const inv_ty = -(r01 * tx + r11 * ty + r21 * tz);
            const inv_tz = -(r02 * tx + r12 * ty + r22 * tz);

            return Self{
                .m = [4][4]T{
                    [4]T{ r00, r10, r20, 0 },
                    [4]T{ r01, r11, r21, 0 },
                    [4]T{ r02, r12, r22, 0 },
                    [4]T{ inv_tx, inv_ty, inv_tz, 1 },
                },
            };
        }

        /// Create translation matrix
        pub fn translation(x: T, y: T, z: T) Self {
            return Self{
                .m = [4][4]T{
                    [4]T{ 1, 0, 0, 0 },
                    [4]T{ 0, 1, 0, 0 },
                    [4]T{ 0, 0, 1, 0 },
                    [4]T{ x, y, z, 1 },
                },
            };
        }

        /// Create translation matrix from vector
        pub fn translationVec(vec: @import("vec3.zig").Vec3(T)) Self {
            return translation(vec.x, vec.y, vec.z);
        }

        /// Create scaling matrix
        pub fn scaling(x: T, y: T, z: T) Self {
            return Self{
                .m = [4][4]T{
                    [4]T{ x, 0, 0, 0 },
                    [4]T{ 0, y, 0, 0 },
                    [4]T{ 0, 0, z, 0 },
                    [4]T{ 0, 0, 0, 1 },
                },
            };
        }

        /// Create uniform scaling matrix
        pub fn scalingUniform(scale_factor: T) Self {
            return scaling(scale_factor, scale_factor, scale_factor);
        }

        /// Create rotation matrix around X axis
        pub fn rotationX(angle: T) Self {
            const c = @cos(angle);
            const s = @sin(angle);
            return Self{
                .m = [4][4]T{
                    [4]T{ 1, 0, 0, 0 },
                    [4]T{ 0, c, s, 0 },
                    [4]T{ 0, -s, c, 0 },
                    [4]T{ 0, 0, 0, 1 },
                },
            };
        }

        /// Create rotation matrix around Y axis
        pub fn rotationY(angle: T) Self {
            const c = @cos(angle);
            const s = @sin(angle);
            return Self{
                .m = [4][4]T{
                    [4]T{ c, 0, -s, 0 },
                    [4]T{ 0, 1, 0, 0 },
                    [4]T{ s, 0, c, 0 },
                    [4]T{ 0, 0, 0, 1 },
                },
            };
        }

        /// Create rotation matrix around Z axis
        pub fn rotationZ(angle: T) Self {
            const c = @cos(angle);
            const s = @sin(angle);
            return Self{
                .m = [4][4]T{
                    [4]T{ c, s, 0, 0 },
                    [4]T{ -s, c, 0, 0 },
                    [4]T{ 0, 0, 1, 0 },
                    [4]T{ 0, 0, 0, 1 },
                },
            };
        }

        /// Create rotation matrix around arbitrary axis
        pub fn rotationAxis(axis: @import("vec3.zig").Vec3(T), angle: T) Self {
            const normalized_axis = axis.normalize();
            const c = @cos(angle);
            const s = @sin(angle);
            const one_minus_c = 1.0 - c;

            const x = normalized_axis.x;
            const y = normalized_axis.y;
            const z = normalized_axis.z;

            return Self{
                .m = [4][4]T{
                    [4]T{ c + x * x * one_minus_c, x * y * one_minus_c + z * s, x * z * one_minus_c - y * s, 0 },
                    [4]T{ y * x * one_minus_c - z * s, c + y * y * one_minus_c, y * z * one_minus_c + x * s, 0 },
                    [4]T{ z * x * one_minus_c + y * s, z * y * one_minus_c - x * s, c + z * z * one_minus_c, 0 },
                    [4]T{ 0, 0, 0, 1 },
                },
            };
        }

        /// Create rotation matrix from Euler angles (ZYX order)
        pub fn rotationEuler(x: T, y: T, z: T) Self {
            return rotationZ(z).mul(rotationY(y)).mul(rotationX(x));
        }

        /// Create perspective projection matrix
        pub fn perspective(fov_y: T, aspect: T, near: T, far: T) Self {
            const tan_half_fov = @tan(fov_y * 0.5);
            const f = 1.0 / tan_half_fov;

            return Self{
                .m = [4][4]T{
                    [4]T{ f / aspect, 0, 0, 0 },
                    [4]T{ 0, f, 0, 0 },
                    [4]T{ 0, 0, -(far + near) / (far - near), -1 },
                    [4]T{ 0, 0, -(2.0 * far * near) / (far - near), 0 },
                },
            };
        }

        /// Create infinite perspective projection matrix
        pub fn perspectiveInfinite(fov_y: T, aspect: T, near: T) Self {
            const tan_half_fov = @tan(fov_y * 0.5);
            const f = 1.0 / tan_half_fov;

            return Self{
                .m = [4][4]T{
                    [4]T{ f / aspect, 0, 0, 0 },
                    [4]T{ 0, f, 0, 0 },
                    [4]T{ 0, 0, -1, -1 },
                    [4]T{ 0, 0, -2.0 * near, 0 },
                },
            };
        }

        /// Create orthographic projection matrix
        pub fn orthographic(left: T, right: T, bottom: T, top: T, near: T, far: T) Self {
            const width = right - left;
            const height = top - bottom;
            const depth = far - near;

            return Self{
                .m = [4][4]T{
                    [4]T{ 2.0 / width, 0, 0, 0 },
                    [4]T{ 0, 2.0 / height, 0, 0 },
                    [4]T{ 0, 0, -2.0 / depth, 0 },
                    [4]T{ -(right + left) / width, -(top + bottom) / height, -(far + near) / depth, 1 },
                },
            };
        }

        /// Create look-at view matrix
        pub fn lookAt(eye: @import("vec3.zig").Vec3(T), target: @import("vec3.zig").Vec3(T), up: @import("vec3.zig").Vec3(T)) Self {
            const forward = target.sub(eye).normalize();
            const right = forward.cross(up).normalize();
            const camera_up = right.cross(forward);

            return Self{
                .m = [4][4]T{
                    [4]T{ right.x, camera_up.x, -forward.x, 0 },
                    [4]T{ right.y, camera_up.y, -forward.y, 0 },
                    [4]T{ right.z, camera_up.z, -forward.z, 0 },
                    [4]T{ -right.dot(eye), -camera_up.dot(eye), forward.dot(eye), 1 },
                },
            };
        }

        /// Create view matrix from position and orientation
        pub fn view(position: @import("vec3.zig").Vec3(T), forward: @import("vec3.zig").Vec3(T), up: @import("vec3.zig").Vec3(T)) Self {
            const f = forward.normalize();
            const u = up.normalize();
            const r = f.cross(u).normalize();
            const corrected_up = r.cross(f);

            return Self{
                .m = [4][4]T{
                    [4]T{ r.x, corrected_up.x, -f.x, 0 },
                    [4]T{ r.y, corrected_up.y, -f.y, 0 },
                    [4]T{ r.z, corrected_up.z, -f.z, 0 },
                    [4]T{ -r.dot(position), -corrected_up.dot(position), f.dot(position), 1 },
                },
            };
        }

        /// Create transformation matrix from translation, rotation, and scale
        pub fn transform(translate: @import("vec3.zig").Vec3(T), rotation: Self, scale_vec: @import("vec3.zig").Vec3(T)) Self {
            var result = rotation;

            // Apply scale
            result.m[0][0] *= scale_vec.x;
            result.m[0][1] *= scale_vec.x;
            result.m[0][2] *= scale_vec.x;
            result.m[1][0] *= scale_vec.y;
            result.m[1][1] *= scale_vec.y;
            result.m[1][2] *= scale_vec.y;
            result.m[2][0] *= scale_vec.z;
            result.m[2][1] *= scale_vec.z;
            result.m[2][2] *= scale_vec.z;

            // Apply translation
            result.m[3][0] = translate.x;
            result.m[3][1] = translate.y;
            result.m[3][2] = translate.z;

            return result;
        }

        /// Extract translation from transformation matrix
        pub fn getTranslation(self: Self) @import("vec3.zig").Vec3(T) {
            return @import("vec3.zig").Vec3(T).init(self.m[3][0], self.m[3][1], self.m[3][2]);
        }

        /// Extract scale from transformation matrix
        pub fn getScale(self: Self) @import("vec3.zig").Vec3(T) {
            const scale_x = @sqrt(self.m[0][0] * self.m[0][0] + self.m[0][1] * self.m[0][1] + self.m[0][2] * self.m[0][2]);
            const scale_y = @sqrt(self.m[1][0] * self.m[1][0] + self.m[1][1] * self.m[1][1] + self.m[1][2] * self.m[1][2]);
            const scale_z = @sqrt(self.m[2][0] * self.m[2][0] + self.m[2][1] * self.m[2][1] + self.m[2][2] * self.m[2][2]);

            return @import("vec3.zig").Vec3(T).init(scale_x, scale_y, scale_z);
        }

        /// Decompose transformation matrix into translation, rotation, and scale
        pub fn decompose(self: Self) struct { translation: @import("vec3.zig").Vec3(T), rotation: Self, scale: @import("vec3.zig").Vec3(T) } {
            const translate = self.getTranslation();
            const scale_vec = self.getScale();

            // Extract rotation by removing scale
            var rotation = self;
            rotation.m[0][0] /= scale_vec.x;
            rotation.m[0][1] /= scale_vec.x;
            rotation.m[0][2] /= scale_vec.x;
            rotation.m[1][0] /= scale_vec.y;
            rotation.m[1][1] /= scale_vec.y;
            rotation.m[1][2] /= scale_vec.y;
            rotation.m[2][0] /= scale_vec.z;
            rotation.m[2][1] /= scale_vec.z;
            rotation.m[2][2] /= scale_vec.z;
            rotation.m[3][0] = 0;
            rotation.m[3][1] = 0;
            rotation.m[3][2] = 0;
            rotation.m[3][3] = 1;

            return .{ .translation = translate, .rotation = rotation, .scale = scale_vec };
        }

        /// Check if two matrices are approximately equal
        pub fn approxEqual(self: Self, other: Self, epsilon: T) bool {
            for (0..4) |col| {
                for (0..4) |row| {
                    if (@abs(self.m[col][row] - other.m[col][row]) > epsilon) {
                        return false;
                    }
                }
            }
            return true;
        }

        /// Equality comparison
        pub fn eql(self: Self, other: Self) bool {
            for (0..4) |col| {
                for (0..4) |row| {
                    if (self.m[col][row] != other.m[col][row]) {
                        return false;
                    }
                }
            }
            return true;
        }

        /// Format for printing
        pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            try writer.print("Mat4(\n", .{});
            for (0..4) |row| {
                try writer.print("  [{d:6.3}, {d:6.3}, {d:6.3}, {d:6.3}]\n", .{ self.m[0][row], self.m[1][row], self.m[2][row], self.m[3][row] });
            }
            try writer.print(")", .{});
        }
    };
}

// Common type aliases
pub const Mat4f = Mat4(f32);
pub const Mat4d = Mat4(f64);

// Tests
test "Mat4 identity" {
    const mat = Mat4f.identity;
    const vec = Vec4f.init(1.0, 2.0, 3.0, 4.0);
    const result = mat.mulVec4(vec);

    try testing.expect(result.eql(vec));
}

test "Mat4 multiplication" {
    const a = Mat4f.translation(1.0, 2.0, 3.0);
    const b = Mat4f.scaling(2.0, 3.0, 4.0);
    const c = a.mul(b);

    const point = Vec3f.init(1.0, 1.0, 1.0);
    const transformed = c.mulPoint(point);

    try testing.expectEqual(@as(f32, 3.0), transformed.x); // (1 * 2) + 1
    try testing.expectEqual(@as(f32, 5.0), transformed.y); // (1 * 3) + 2
    try testing.expectEqual(@as(f32, 7.0), transformed.z); // (1 * 4) + 3
}

test "Mat4 inverse" {
    const original = Mat4f.translation(1.0, 2.0, 3.0);
    const inverse = original.inverse().?;
    const identity = original.mul(inverse);

    try testing.expect(identity.approxEqual(Mat4f.identity, 1e-6));
}

test "Mat4 perspective projection" {
    const proj = Mat4f.perspective(std.math.pi / 4.0, 16.0 / 9.0, 0.1, 100.0);
    const point = Vec4f.init(0.0, 0.0, -1.0, 1.0);
    const projected = proj.mulVec4(point);

    // Point should be projected correctly
    try testing.expect(projected.w > 0);
}

test "Mat4 look-at" {
    const eye = Vec3f.init(0.0, 0.0, 1.0);
    const target = Vec3f.init(0.0, 0.0, 0.0);
    const up = Vec3f.init(0.0, 1.0, 0.0);

    const view = Mat4f.lookAt(eye, target, up);
    const origin = view.mulPoint(target);

    // Target should be at origin in view space
    try testing.expect(origin.approxEqual(Vec3f.init(0.0, 0.0, -1.0), 1e-6));
}
