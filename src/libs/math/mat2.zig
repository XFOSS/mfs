const std = @import("std");
const math = std.math;
const testing = std.testing;
const Vec2f = @import("vec2.zig").Vec2f;

/// Generic 2x2 matrix implementation with column-major storage
pub fn Mat2(comptime T: type) type {
    return struct {
        const Self = @This();

        // Column-major storage: m[column][row]
        m: [2][2]T,

        // Common matrices
        pub const identity = Self{
            .m = [2][2]T{
                [2]T{ 1, 0 },
                [2]T{ 0, 1 },
            },
        };

        pub const zero = Self{
            .m = [2][2]T{
                [2]T{ 0, 0 },
                [2]T{ 0, 0 },
            },
        };

        /// Initialize matrix from column vectors
        pub fn init(col0: [2]T, col1: [2]T) Self {
            return Self{
                .m = [2][2]T{ col0, col1 },
            };
        }

        /// Initialize from array (column-major)
        pub fn fromArray(arr: [4]T) Self {
            return Self{
                .m = [2][2]T{
                    [2]T{ arr[0], arr[1] },
                    [2]T{ arr[2], arr[3] },
                },
            };
        }

        /// Convert to array (column-major)
        pub fn toArray(self: Self) [4]T {
            return [4]T{
                self.m[0][0], self.m[0][1],
                self.m[1][0], self.m[1][1],
            };
        }

        /// Initialize from row vectors
        pub fn fromRows(row0: [2]T, row1: [2]T) Self {
            return Self{
                .m = [2][2]T{
                    [2]T{ row0[0], row1[0] },
                    [2]T{ row0[1], row1[1] },
                },
            };
        }

        /// Initialize from individual components
        pub fn fromComponents(m00: T, m01: T, m10: T, m11: T) Self {
            return Self{
                .m = [2][2]T{
                    [2]T{ m00, m01 },
                    [2]T{ m10, m11 },
                },
            };
        }

        /// Get column vector
        pub fn getColumn(self: Self, col: u32) [2]T {
            return self.m[col];
        }

        /// Get row vector
        pub fn getRow(self: Self, row: u32) [2]T {
            return [2]T{ self.m[0][row], self.m[1][row] };
        }

        /// Set column vector
        pub fn setColumn(self: *Self, col: u32, values: [2]T) void {
            self.m[col] = values;
        }

        /// Set row vector
        pub fn setRow(self: *Self, row: u32, values: [2]T) void {
            self.m[0][row] = values[0];
            self.m[1][row] = values[1];
        }

        /// Matrix addition
        pub fn add(self: Self, other: Self) Self {
            return Self{
                .m = [2][2]T{
                    [2]T{ self.m[0][0] + other.m[0][0], self.m[0][1] + other.m[0][1] },
                    [2]T{ self.m[1][0] + other.m[1][0], self.m[1][1] + other.m[1][1] },
                },
            };
        }

        /// Matrix subtraction
        pub fn sub(self: Self, other: Self) Self {
            return Self{
                .m = [2][2]T{
                    [2]T{ self.m[0][0] - other.m[0][0], self.m[0][1] - other.m[0][1] },
                    [2]T{ self.m[1][0] - other.m[1][0], self.m[1][1] - other.m[1][1] },
                },
            };
        }

        /// Matrix multiplication
        pub fn mul(self: Self, other: Self) Self {
            return Self{
                .m = [2][2]T{
                    [2]T{
                        self.m[0][0] * other.m[0][0] + self.m[1][0] * other.m[0][1],
                        self.m[0][1] * other.m[0][0] + self.m[1][1] * other.m[0][1],
                    },
                    [2]T{
                        self.m[0][0] * other.m[1][0] + self.m[1][0] * other.m[1][1],
                        self.m[0][1] * other.m[1][0] + self.m[1][1] * other.m[1][1],
                    },
                },
            };
        }

        /// Scalar multiplication
        pub fn scale(self: Self, scalar: T) Self {
            return Self{
                .m = [2][2]T{
                    [2]T{ self.m[0][0] * scalar, self.m[0][1] * scalar },
                    [2]T{ self.m[1][0] * scalar, self.m[1][1] * scalar },
                },
            };
        }

        /// Matrix-vector multiplication
        pub fn mulVec2(self: Self, vec: @import("vec2.zig").Vec2(T)) @import("vec2.zig").Vec2(T) {
            return @import("vec2.zig").Vec2(T).init(
                self.m[0][0] * vec.x + self.m[1][0] * vec.y,
                self.m[0][1] * vec.x + self.m[1][1] * vec.y,
            );
        }

        /// Transpose matrix
        pub fn transpose(self: Self) Self {
            return Self{
                .m = [2][2]T{
                    [2]T{ self.m[0][0], self.m[1][0] },
                    [2]T{ self.m[0][1], self.m[1][1] },
                },
            };
        }

        /// Calculate determinant
        pub fn determinant(self: Self) T {
            return self.m[0][0] * self.m[1][1] - self.m[1][0] * self.m[0][1];
        }

        /// Calculate inverse matrix
        pub fn inverse(self: Self) ?Self {
            const det = self.determinant();
            if (@abs(det) < math.floatEps(T)) return null;

            const inv_det = 1.0 / det;

            return Self{
                .m = [2][2]T{
                    [2]T{ self.m[1][1] * inv_det, -self.m[0][1] * inv_det },
                    [2]T{ -self.m[1][0] * inv_det, self.m[0][0] * inv_det },
                },
            };
        }

        /// Create 2D rotation matrix
        pub fn rotation(angle: T) Self {
            const c = @cos(angle);
            const s = @sin(angle);
            return Self{
                .m = [2][2]T{
                    [2]T{ c, s },
                    [2]T{ -s, c },
                },
            };
        }

        /// Create 2D scaling matrix
        pub fn scaling(x: T, y: T) Self {
            return Self{
                .m = [2][2]T{
                    [2]T{ x, 0 },
                    [2]T{ 0, y },
                },
            };
        }

        /// Create uniform 2D scaling matrix
        pub fn scalingUniform(scale_factor: T) Self {
            return scaling(scale_factor, scale_factor);
        }

        /// Create 2D scaling matrix from vector
        pub fn scalingVec(scale_vec: @import("vec2.zig").Vec2(T)) Self {
            return scaling(scale_vec.x, scale_vec.y);
        }

        /// Create 2D shear matrix
        pub fn shear(shear_x: T, shear_y: T) Self {
            return Self{
                .m = [2][2]T{
                    [2]T{ 1, shear_y },
                    [2]T{ shear_x, 1 },
                },
            };
        }

        /// Create 2D reflection matrix across X axis
        pub fn reflectionX() Self {
            return Self{
                .m = [2][2]T{
                    [2]T{ 1, 0 },
                    [2]T{ 0, -1 },
                },
            };
        }

        /// Create 2D reflection matrix across Y axis
        pub fn reflectionY() Self {
            return Self{
                .m = [2][2]T{
                    [2]T{ -1, 0 },
                    [2]T{ 0, 1 },
                },
            };
        }

        /// Create 2D reflection matrix across line through origin
        pub fn reflectionLine(angle: T) Self {
            const cos2a = @cos(2.0 * angle);
            const sin2a = @sin(2.0 * angle);
            return Self{
                .m = [2][2]T{
                    [2]T{ cos2a, sin2a },
                    [2]T{ sin2a, -cos2a },
                },
            };
        }

        /// Get rotation angle from rotation matrix
        pub fn getRotationAngle(self: Self) T {
            return math.atan2(T, self.m[0][1], self.m[0][0]);
        }

        /// Get scale factors from transformation matrix
        pub fn getScale(self: Self) @import("vec2.zig").Vec2(T) {
            const scale_x = @sqrt(self.m[0][0] * self.m[0][0] + self.m[0][1] * self.m[0][1]);
            const scale_y = @sqrt(self.m[1][0] * self.m[1][0] + self.m[1][1] * self.m[1][1]);
            return @import("vec2.zig").Vec2(T).init(scale_x, scale_y);
        }

        /// Decompose matrix into rotation and scale
        pub fn decompose(self: Self) struct { rotation: T, scale: @import("vec2.zig").Vec2(T) } {
            const scale_vec = self.getScale();
            var rotation_mat = self;

            // Remove scale to get pure rotation
            if (scale.x != 0) {
                rotation_mat.m[0][0] /= scale.x;
                rotation_mat.m[0][1] /= scale.x;
            }
            if (scale.y != 0) {
                rotation_mat.m[1][0] /= scale.y;
                rotation_mat.m[1][1] /= scale.y;
            }

            const rotation_angle = rotation_mat.getRotationAngle();
            return .{ .rotation = rotation_angle, .scale = scale_vec };
        }

        /// Create matrix from rotation and scale
        pub fn fromRotationScale(angle: T, scale_vec: @import("vec2.zig").Vec2(T)) Self {
            const c = @cos(angle);
            const s = @sin(angle);
            return Self{
                .m = [2][2]T{
                    [2]T{ c * scale_vec.x, s * scale_vec.x },
                    [2]T{ -s * scale_vec.y, c * scale_vec.y },
                },
            };
        }

        /// Calculate trace (sum of diagonal elements)
        pub fn trace(self: Self) T {
            return self.m[0][0] + self.m[1][1];
        }

        /// Calculate Frobenius norm
        pub fn frobeniusNorm(self: Self) T {
            return @sqrt(self.m[0][0] * self.m[0][0] + self.m[0][1] * self.m[0][1] +
                self.m[1][0] * self.m[1][0] + self.m[1][1] * self.m[1][1]);
        }

        /// Check if matrix is orthogonal
        pub fn isOrthogonal(self: Self, epsilon: T) bool {
            const product = self.mul(self.transpose());
            return product.approxEqual(Self.identity, epsilon);
        }

        /// Check if matrix is symmetric
        pub fn isSymmetric(self: Self, epsilon: T) bool {
            return self.approxEqual(self.transpose(), epsilon);
        }

        /// Linear interpolation between two matrices
        pub fn lerp(self: Self, other: Self, t: T) Self {
            const one_minus_t = 1.0 - t;
            return Self{
                .m = [2][2]T{
                    [2]T{
                        self.m[0][0] * one_minus_t + other.m[0][0] * t,
                        self.m[0][1] * one_minus_t + other.m[0][1] * t,
                    },
                    [2]T{
                        self.m[1][0] * one_minus_t + other.m[1][0] * t,
                        self.m[1][1] * one_minus_t + other.m[1][1] * t,
                    },
                },
            };
        }

        /// Check if two matrices are approximately equal
        pub fn approxEqual(self: Self, other: Self, epsilon: T) bool {
            return @abs(self.m[0][0] - other.m[0][0]) < epsilon and
                @abs(self.m[0][1] - other.m[0][1]) < epsilon and
                @abs(self.m[1][0] - other.m[1][0]) < epsilon and
                @abs(self.m[1][1] - other.m[1][1]) < epsilon;
        }

        /// Equality comparison
        pub fn eql(self: Self, other: Self) bool {
            return self.m[0][0] == other.m[0][0] and
                self.m[0][1] == other.m[0][1] and
                self.m[1][0] == other.m[1][0] and
                self.m[1][1] == other.m[1][1];
        }

        /// Format for printing
        pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            try writer.print("Mat2(\n", .{});
            for (0..2) |row| {
                try writer.print("  [{d:6.3}, {d:6.3}]\n", .{ self.m[0][row], self.m[1][row] });
            }
            try writer.print(")", .{});
        }
    };
}

// Common type aliases
pub const Mat2f = Mat2(f32);
pub const Mat2d = Mat2(f64);

// Tests
test "Mat2 identity" {
    const mat = Mat2f.identity;
    const vec = Vec2f.init(1.0, 2.0);
    const result = mat.mulVec2(vec);

    try testing.expect(result.eql(vec));
}

test "Mat2 rotation" {
    const mat = Mat2f.rotation(std.math.pi / 2.0);
    const vec = Vec2f.init(1.0, 0.0);
    const rotated = mat.mulVec2(vec);

    try testing.expect(rotated.approxEqual(Vec2f.init(0.0, 1.0), 1e-6));
}

test "Mat2 scaling" {
    const mat = Mat2f.scaling(2.0, 3.0);
    const vec = Vec2f.init(1.0, 1.0);
    const scaled = mat.mulVec2(vec);

    try testing.expect(scaled.eql(Vec2f.init(2.0, 3.0)));
}

test "Mat2 determinant and inverse" {
    const mat = Mat2f.fromComponents(2.0, 1.0, 3.0, 4.0);
    const det = mat.determinant();

    try testing.expectEqual(@as(f32, 5.0), det); // 2*4 - 1*3 = 5

    const inverse = mat.inverse().?;
    const identity = mat.mul(inverse);

    try testing.expect(identity.approxEqual(Mat2f.identity, 1e-6));
}

test "Mat2 decomposition" {
    const rotation = std.math.pi / 4.0;
    const scale = Vec2f.init(2.0, 3.0);
    const mat = Mat2f.fromRotationScale(rotation, scale);

    const decomposed = mat.decompose();

    try testing.expect(@abs(decomposed.rotation - rotation) < 1e-6);
    try testing.expect(decomposed.scale.approxEqual(scale, 1e-6));
}

test "Mat2 orthogonal check" {
    const rotation_mat = Mat2f.rotation(std.math.pi / 3.0);
    try testing.expect(rotation_mat.isOrthogonal(1e-6));

    const scaling_mat = Mat2f.scaling(2.0, 3.0);
    try testing.expect(!scaling_mat.isOrthogonal(1e-6));
}
