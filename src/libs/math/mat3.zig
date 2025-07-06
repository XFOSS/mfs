const std = @import("std");
const math = std.math;
const testing = std.testing;
const Vec2f = @import("vec2.zig").Vec2f;
const Vec3f = @import("vec3.zig").Vec3f;

/// Generic 3x3 matrix implementation with column-major storage
pub fn Mat3(comptime T: type) type {
    return struct {
        const Self = @This();

        // Column-major storage: m[column][row]
        m: [3][3]T,

        // Common matrices
        pub const identity = Self{
            .m = [3][3]T{
                [3]T{ 1, 0, 0 },
                [3]T{ 0, 1, 0 },
                [3]T{ 0, 0, 1 },
            },
        };

        pub const zero = Self{
            .m = [3][3]T{
                [3]T{ 0, 0, 0 },
                [3]T{ 0, 0, 0 },
                [3]T{ 0, 0, 0 },
            },
        };

        /// Initialize matrix from column vectors
        pub fn init(col0: [3]T, col1: [3]T, col2: [3]T) Self {
            return Self{
                .m = [3][3]T{ col0, col1, col2 },
            };
        }

        /// Initialize from array (column-major)
        pub fn fromArray(arr: [9]T) Self {
            return Self{
                .m = [3][3]T{
                    [3]T{ arr[0], arr[1], arr[2] },
                    [3]T{ arr[3], arr[4], arr[5] },
                    [3]T{ arr[6], arr[7], arr[8] },
                },
            };
        }

        /// Convert to array (column-major)
        pub fn toArray(self: Self) [9]T {
            return [9]T{
                self.m[0][0], self.m[0][1], self.m[0][2],
                self.m[1][0], self.m[1][1], self.m[1][2],
                self.m[2][0], self.m[2][1], self.m[2][2],
            };
        }

        /// Initialize from row vectors
        pub fn fromRows(row0: [3]T, row1: [3]T, row2: [3]T) Self {
            return Self{
                .m = [3][3]T{
                    [3]T{ row0[0], row1[0], row2[0] },
                    [3]T{ row0[1], row1[1], row2[1] },
                    [3]T{ row0[2], row1[2], row2[2] },
                },
            };
        }

        /// Get column vector
        pub fn getColumn(self: Self, col: u32) [3]T {
            return self.m[col];
        }

        /// Get row vector
        pub fn getRow(self: Self, row: u32) [3]T {
            return [3]T{ self.m[0][row], self.m[1][row], self.m[2][row] };
        }

        /// Set column vector
        pub fn setColumn(self: *Self, col: u32, values: [3]T) void {
            self.m[col] = values;
        }

        /// Set row vector
        pub fn setRow(self: *Self, row: u32, values: [3]T) void {
            self.m[0][row] = values[0];
            self.m[1][row] = values[1];
            self.m[2][row] = values[2];
        }

        /// Matrix addition
        pub fn add(self: Self, other: Self) Self {
            var result = Self.zero;
            for (0..3) |col| {
                for (0..3) |row| {
                    result.m[col][row] = self.m[col][row] + other.m[col][row];
                }
            }
            return result;
        }

        /// Matrix subtraction
        pub fn sub(self: Self, other: Self) Self {
            var result = Self.zero;
            for (0..3) |col| {
                for (0..3) |row| {
                    result.m[col][row] = self.m[col][row] - other.m[col][row];
                }
            }
            return result;
        }

        /// Matrix multiplication
        pub fn mul(self: Self, other: Self) Self {
            var result = Self.zero;
            for (0..3) |col| {
                for (0..3) |row| {
                    var sum: T = 0;
                    for (0..3) |k| {
                        sum += self.m[k][row] * other.m[col][k];
                    }
                    result.m[col][row] = sum;
                }
            }
            return result;
        }

        /// Scalar multiplication
        pub fn scale(self: Self, scalar: T) Self {
            var result = Self.zero;
            for (0..3) |col| {
                for (0..3) |row| {
                    result.m[col][row] = self.m[col][row] * scalar;
                }
            }
            return result;
        }

        /// Matrix-vector multiplication (3D)
        pub fn mulVec3(self: Self, vec: @import("vec3.zig").Vec3(T)) @import("vec3.zig").Vec3(T) {
            return @import("vec3.zig").Vec3(T).init(
                self.m[0][0] * vec.x + self.m[1][0] * vec.y + self.m[2][0] * vec.z,
                self.m[0][1] * vec.x + self.m[1][1] * vec.y + self.m[2][1] * vec.z,
                self.m[0][2] * vec.x + self.m[1][2] * vec.y + self.m[2][2] * vec.z,
            );
        }

        /// Matrix-vector multiplication (2D homogeneous)
        pub fn mulVec2(self: Self, vec: @import("vec2.zig").Vec2(T)) @import("vec2.zig").Vec2(T) {
            const x = self.m[0][0] * vec.x + self.m[1][0] * vec.y + self.m[2][0];
            const y = self.m[0][1] * vec.x + self.m[1][1] * vec.y + self.m[2][1];
            const w = self.m[0][2] * vec.x + self.m[1][2] * vec.y + self.m[2][2];

            if (w == 0) return @import("vec2.zig").Vec2(T).zero;
            return @import("vec2.zig").Vec2(T).init(x / w, y / w);
        }

        /// Transform 2D point (assuming homogeneous coordinates)
        pub fn transformPoint(self: Self, point: @import("vec2.zig").Vec2(T)) @import("vec2.zig").Vec2(T) {
            return self.mulVec2(point);
        }

        /// Transform 2D direction (ignore translation)
        pub fn transformDirection(self: Self, dir: @import("vec2.zig").Vec2(T)) @import("vec2.zig").Vec2(T) {
            return @import("vec2.zig").Vec2(T).init(
                self.m[0][0] * dir.x + self.m[1][0] * dir.y,
                self.m[0][1] * dir.x + self.m[1][1] * dir.y,
            );
        }

        /// Transpose matrix
        pub fn transpose(self: Self) Self {
            return Self{
                .m = [3][3]T{
                    [3]T{ self.m[0][0], self.m[1][0], self.m[2][0] },
                    [3]T{ self.m[0][1], self.m[1][1], self.m[2][1] },
                    [3]T{ self.m[0][2], self.m[1][2], self.m[2][2] },
                },
            };
        }

        /// Calculate determinant
        pub fn determinant(self: Self) T {
            return self.m[0][0] * (self.m[1][1] * self.m[2][2] - self.m[1][2] * self.m[2][1]) -
                self.m[1][0] * (self.m[0][1] * self.m[2][2] - self.m[0][2] * self.m[2][1]) +
                self.m[2][0] * (self.m[0][1] * self.m[1][2] - self.m[0][2] * self.m[1][1]);
        }

        /// Calculate inverse matrix
        pub fn inverse(self: Self) ?Self {
            const det = self.determinant();
            if (@abs(det) < math.floatEps(T)) return null;

            const inv_det = 1.0 / det;

            return Self{
                .m = [3][3]T{
                    [3]T{
                        (self.m[1][1] * self.m[2][2] - self.m[1][2] * self.m[2][1]) * inv_det,
                        (self.m[0][2] * self.m[2][1] - self.m[0][1] * self.m[2][2]) * inv_det,
                        (self.m[0][1] * self.m[1][2] - self.m[0][2] * self.m[1][1]) * inv_det,
                    },
                    [3]T{
                        (self.m[1][2] * self.m[2][0] - self.m[1][0] * self.m[2][2]) * inv_det,
                        (self.m[0][0] * self.m[2][2] - self.m[0][2] * self.m[2][0]) * inv_det,
                        (self.m[0][2] * self.m[1][0] - self.m[0][0] * self.m[1][2]) * inv_det,
                    },
                    [3]T{
                        (self.m[1][0] * self.m[2][1] - self.m[1][1] * self.m[2][0]) * inv_det,
                        (self.m[0][1] * self.m[2][0] - self.m[0][0] * self.m[2][1]) * inv_det,
                        (self.m[0][0] * self.m[1][1] - self.m[0][1] * self.m[1][0]) * inv_det,
                    },
                },
            };
        }

        /// Create 2D translation matrix
        pub fn translation2D(x: T, y: T) Self {
            return Self{
                .m = [3][3]T{
                    [3]T{ 1, 0, 0 },
                    [3]T{ 0, 1, 0 },
                    [3]T{ x, y, 1 },
                },
            };
        }

        /// Create 2D translation matrix from vector
        pub fn translation2DVec(vec: @import("vec2.zig").Vec2(T)) Self {
            return translation2D(vec.x, vec.y);
        }

        /// Create 2D scaling matrix
        pub fn scaling2D(x: T, y: T) Self {
            return Self{
                .m = [3][3]T{
                    [3]T{ x, 0, 0 },
                    [3]T{ 0, y, 0 },
                    [3]T{ 0, 0, 1 },
                },
            };
        }

        /// Create uniform 2D scaling matrix
        pub fn scaling2DUniform(scale_factor: T) Self {
            return scaling2D(scale_factor, scale_factor);
        }

        /// Create 2D rotation matrix
        pub fn rotation2D(angle: T) Self {
            const c = @cos(angle);
            const s = @sin(angle);
            return Self{
                .m = [3][3]T{
                    [3]T{ c, s, 0 },
                    [3]T{ -s, c, 0 },
                    [3]T{ 0, 0, 1 },
                },
            };
        }

        /// Create 3D scaling matrix
        pub fn scaling3D(x: T, y: T, z: T) Self {
            return Self{
                .m = [3][3]T{
                    [3]T{ x, 0, 0 },
                    [3]T{ 0, y, 0 },
                    [3]T{ 0, 0, z },
                },
            };
        }

        /// Create uniform 3D scaling matrix
        pub fn scaling3DUniform(scale_factor: T) Self {
            return scaling3D(scale_factor, scale_factor, scale_factor);
        }

        /// Create 3D rotation matrix around X axis
        pub fn rotationX(angle: T) Self {
            const c = @cos(angle);
            const s = @sin(angle);
            return Self{
                .m = [3][3]T{
                    [3]T{ 1, 0, 0 },
                    [3]T{ 0, c, s },
                    [3]T{ 0, -s, c },
                },
            };
        }

        /// Create 3D rotation matrix around Y axis
        pub fn rotationY(angle: T) Self {
            const c = @cos(angle);
            const s = @sin(angle);
            return Self{
                .m = [3][3]T{
                    [3]T{ c, 0, -s },
                    [3]T{ 0, 1, 0 },
                    [3]T{ s, 0, c },
                },
            };
        }

        /// Create 3D rotation matrix around Z axis
        pub fn rotationZ(angle: T) Self {
            const c = @cos(angle);
            const s = @sin(angle);
            return Self{
                .m = [3][3]T{
                    [3]T{ c, s, 0 },
                    [3]T{ -s, c, 0 },
                    [3]T{ 0, 0, 1 },
                },
            };
        }

        /// Create 3D rotation matrix around arbitrary axis
        pub fn rotationAxis(axis: @import("vec3.zig").Vec3(T), angle: T) Self {
            const normalized_axis = axis.normalize();
            const c = @cos(angle);
            const s = @sin(angle);
            const one_minus_c = 1.0 - c;

            const x = normalized_axis.x;
            const y = normalized_axis.y;
            const z = normalized_axis.z;

            return Self{
                .m = [3][3]T{
                    [3]T{
                        c + x * x * one_minus_c,
                        x * y * one_minus_c + z * s,
                        x * z * one_minus_c - y * s,
                    },
                    [3]T{
                        y * x * one_minus_c - z * s,
                        c + y * y * one_minus_c,
                        y * z * one_minus_c + x * s,
                    },
                    [3]T{
                        z * x * one_minus_c + y * s,
                        z * y * one_minus_c - x * s,
                        c + z * z * one_minus_c,
                    },
                },
            };
        }

        /// Create rotation matrix from Euler angles (ZYX order)
        pub fn rotationEuler(x: T, y: T, z: T) Self {
            return rotationZ(z).mul(rotationY(y)).mul(rotationX(x));
        }

        /// Create 2D transformation matrix from translation, rotation, and scale
        pub fn transform2D(translation: @import("vec2.zig").Vec2(T), rotation: T, scale_vec: @import("vec2.zig").Vec2(T)) Self {
            const c = @cos(rotation);
            const s = @sin(rotation);

            return Self{
                .m = [3][3]T{
                    [3]T{ c * scale_vec.x, s * scale_vec.x, 0 },
                    [3]T{ -s * scale_vec.y, c * scale_vec.y, 0 },
                    [3]T{ translation.x, translation.y, 1 },
                },
            };
        }

        /// Create normal matrix (inverse transpose of upper-left 3x3)
        pub fn normalMatrix(transform: @import("mat4.zig").Mat4(T)) Self {
            // Extract upper-left 3x3 from 4x4 matrix
            const mat3 = Self{
                .m = [3][3]T{
                    [3]T{ transform.m[0][0], transform.m[0][1], transform.m[0][2] },
                    [3]T{ transform.m[1][0], transform.m[1][1], transform.m[1][2] },
                    [3]T{ transform.m[2][0], transform.m[2][1], transform.m[2][2] },
                },
            };

            // Return inverse transpose for correct normal transformation
            if (mat3.inverse()) |inv| {
                return inv.transpose();
            } else {
                return Self.identity;
            }
        }

        /// Extract 2D translation from transformation matrix
        pub fn getTranslation2D(self: Self) @import("vec2.zig").Vec2(T) {
            return @import("vec2.zig").Vec2(T).init(self.m[2][0], self.m[2][1]);
        }

        /// Extract 2D scale from transformation matrix
        pub fn getScale2D(self: Self) @import("vec2.zig").Vec2(T) {
            const scale_x = @sqrt(self.m[0][0] * self.m[0][0] + self.m[0][1] * self.m[0][1]);
            const scale_y = @sqrt(self.m[1][0] * self.m[1][0] + self.m[1][1] * self.m[1][1]);

            return @import("vec2.zig").Vec2(T).init(scale_x, scale_y);
        }

        /// Extract 2D rotation angle from transformation matrix
        pub fn getRotation2D(self: Self) T {
            return math.atan2(T, self.m[0][1], self.m[0][0]);
        }

        /// Check if two matrices are approximately equal
        pub fn approxEqual(self: Self, other: Self, epsilon: T) bool {
            for (0..3) |col| {
                for (0..3) |row| {
                    if (@abs(self.m[col][row] - other.m[col][row]) > epsilon) {
                        return false;
                    }
                }
            }
            return true;
        }

        /// Equality comparison
        pub fn eql(self: Self, other: Self) bool {
            for (0..3) |col| {
                for (0..3) |row| {
                    if (self.m[col][row] != other.m[col][row]) {
                        return false;
                    }
                }
            }
            return true;
        }

        /// Create diagonal matrix
        pub fn diagonal(x: T, y: T, z: T) Self {
            return Self{
                .m = [3][3]T{
                    [3]T{ x, 0, 0 },
                    [3]T{ 0, y, 0 },
                    [3]T{ 0, 0, z },
                },
            };
        }

        /// Matrix multiplication (alias for mul)
        pub fn multiply(self: Self, other: Self) Self {
            return self.mul(other);
        }

        /// Matrix-vector multiplication for Vec3f
        pub fn multiplyVector(self: Self, vec: @import("vec3.zig").Vec3(T)) @import("vec3.zig").Vec3(T) {
            return @import("vec3.zig").Vec3(T).init(
                self.m[0][0] * vec.x + self.m[1][0] * vec.y + self.m[2][0] * vec.z,
                self.m[0][1] * vec.x + self.m[1][1] * vec.y + self.m[2][1] * vec.z,
                self.m[0][2] * vec.x + self.m[1][2] * vec.y + self.m[2][2] * vec.z,
            );
        }

        /// Format for printing
        pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            try writer.print("Mat3(\n", .{});
            for (0..3) |row| {
                try writer.print("  [{d:6.3}, {d:6.3}, {d:6.3}]\n", .{ self.m[0][row], self.m[1][row], self.m[2][row] });
            }
            try writer.print(")", .{});
        }
    };
}

// Common type aliases
pub const Mat3f = Mat3(f32);
pub const Mat3d = Mat3(f64);

// Tests
test "Mat3 identity" {
    const mat = Mat3f.identity;
    const vec = Vec3f.init(1.0, 2.0, 3.0);
    const result = mat.mulVec3(vec);

    try testing.expect(result.eql(vec));
}

test "Mat3 2D transformation" {
    const translation = Vec2f.init(1.0, 2.0);
    const rotation = std.math.pi / 4.0;
    const scale = Vec2f.init(2.0, 3.0);

    const transform = Mat3f.transform2D(translation, rotation, scale);
    const point = Vec2f.init(1.0, 0.0);
    const transformed = transform.transformPoint(point);

    // Verify transformation is applied correctly
    try testing.expect(@abs(transformed.x - (1.0 + @sqrt(2.0))) < 1e-6);
}

test "Mat3 determinant and inverse" {
    const mat = Mat3f.scaling2D(2.0, 3.0);
    const det = mat.determinant();

    try testing.expectEqual(@as(f32, 6.0), det);

    const inverse = mat.inverse().?;
    const identity = mat.mul(inverse);

    try testing.expect(identity.approxEqual(Mat3f.identity, 1e-6));
}

test "Mat3 3D rotation" {
    const mat = Mat3f.rotationZ(std.math.pi / 2.0);
    const vec = Vec3f.init(1.0, 0.0, 0.0);
    const rotated = mat.mulVec3(vec);

    try testing.expect(rotated.approxEqual(Vec3f.init(0.0, 1.0, 0.0), 1e-6));
}
