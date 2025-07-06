const std = @import("std");
const builtin = @import("builtin");
const math = std.math;

/// SIMD capabilities detection and platform-specific optimizations
pub const SimdCapabilities = struct {
    has_sse: bool = false,
    has_sse2: bool = false,
    has_sse3: bool = false,
    has_ssse3: bool = false,
    has_sse41: bool = false,
    has_sse42: bool = false,
    has_avx: bool = false,
    has_avx2: bool = false,
    has_avx512: bool = false,
    has_fma: bool = false,
    has_neon: bool = false,

    pub fn detect() SimdCapabilities {
        var caps = SimdCapabilities{};

        switch (builtin.cpu.arch) {
            .x86_64, .x86 => {
                // X86/X64 SIMD detection
                caps.has_sse = std.Target.x86.featureSetHas(builtin.cpu.features, .sse);
                caps.has_sse2 = std.Target.x86.featureSetHas(builtin.cpu.features, .sse2);
                caps.has_sse3 = std.Target.x86.featureSetHas(builtin.cpu.features, .sse3);
                caps.has_ssse3 = std.Target.x86.featureSetHas(builtin.cpu.features, .ssse3);
                caps.has_sse41 = std.Target.x86.featureSetHas(builtin.cpu.features, .sse4_1);
                caps.has_sse42 = std.Target.x86.featureSetHas(builtin.cpu.features, .sse4_2);
                caps.has_avx = std.Target.x86.featureSetHas(builtin.cpu.features, .avx);
                caps.has_avx2 = std.Target.x86.featureSetHas(builtin.cpu.features, .avx2);
                caps.has_avx512 = std.Target.x86.featureSetHas(builtin.cpu.features, .avx512f);
                caps.has_fma = std.Target.x86.featureSetHas(builtin.cpu.features, .fma);
            },
            .aarch64 => {
                // ARM64 NEON detection
                caps.has_neon = std.Target.aarch64.featureSetHas(builtin.cpu.features, .neon);
            },
            .arm => {
                // ARM32 NEON detection
                caps.has_neon = std.Target.arm.featureSetHas(builtin.cpu.features, .neon);
            },
            else => {
                // Other architectures - use compiler auto-vectorization
            },
        }

        return caps;
    }
};

/// Global SIMD capabilities (detected at startup)
pub var simd_caps: SimdCapabilities = SimdCapabilities{};
var simd_caps_initialized = false;

pub fn initSimd() void {
    if (!simd_caps_initialized) {
        simd_caps = SimdCapabilities.detect();
        simd_caps_initialized = true;
    }
}

/// Check if we have vector support for the current architecture
fn hasVectorSupport() bool {
    return switch (builtin.cpu.arch) {
        .x86_64, .x86, .aarch64, .arm => true,
        else => false,
    };
}

/// Platform-specific vector types
pub const SimdVec2f = if (hasVectorSupport()) @Vector(2, f32) else struct { x: f32, y: f32 };

pub const SimdVec3f = if (hasVectorSupport()) @Vector(4, f32) else struct { x: f32, y: f32, z: f32, _pad: f32 = 0 };

pub const SimdVec4f = if (hasVectorSupport()) @Vector(4, f32) else struct { x: f32, y: f32, z: f32, w: f32 };

/// SIMD optimized operations for Vec2
pub const SimdVec2Ops = struct {
    pub fn add(a: SimdVec2f, b: SimdVec2f) SimdVec2f {
        if (hasVectorSupport()) {
            return a + b;
        } else {
            return SimdVec2f{ .x = a.x + b.x, .y = a.y + b.y };
        }
    }

    pub fn sub(a: SimdVec2f, b: SimdVec2f) SimdVec2f {
        if (hasVectorSupport()) {
            return a - b;
        } else {
            return SimdVec2f{ .x = a.x - b.x, .y = a.y - b.y };
        }
    }

    pub fn mul(a: SimdVec2f, b: SimdVec2f) SimdVec2f {
        if (hasVectorSupport()) {
            return a * b;
        } else {
            return SimdVec2f{ .x = a.x * b.x, .y = a.y * b.y };
        }
    }

    pub fn scale(a: SimdVec2f, scalar: f32) SimdVec2f {
        if (hasVectorSupport()) {
            return a * @as(SimdVec2f, @splat(scalar));
        } else {
            return SimdVec2f{ .x = a.x * scalar, .y = a.y * scalar };
        }
    }

    pub fn dot(a: SimdVec2f, b: SimdVec2f) f32 {
        if (hasVectorSupport()) {
            const prod = a * b;
            return @reduce(.Add, prod);
        } else {
            return a.x * b.x + a.y * b.y;
        }
    }

    pub fn lengthSq(a: SimdVec2f) f32 {
        return dot(a, a);
    }

    pub fn length(a: SimdVec2f) f32 {
        return @sqrt(lengthSq(a));
    }

    pub fn normalize(a: SimdVec2f) SimdVec2f {
        const len = length(a);
        if (len == 0) return a;
        return scale(a, 1.0 / len);
    }
};

/// SIMD optimized operations for Vec3
pub const SimdVec3Ops = struct {
    pub fn add(a: SimdVec3f, b: SimdVec3f) SimdVec3f {
        if (hasVectorSupport()) {
            return a + b;
        } else {
            return SimdVec3f{
                .x = a.x + b.x,
                .y = a.y + b.y,
                .z = a.z + b.z,
                ._pad = 0,
            };
        }
    }

    pub fn sub(a: SimdVec3f, b: SimdVec3f) SimdVec3f {
        if (hasVectorSupport()) {
            return a - b;
        } else {
            return SimdVec3f{
                .x = a.x - b.x,
                .y = a.y - b.y,
                .z = a.z - b.z,
                ._pad = 0,
            };
        }
    }

    pub fn mul(a: SimdVec3f, b: SimdVec3f) SimdVec3f {
        if (hasVectorSupport()) {
            return a * b;
        } else {
            return SimdVec3f{
                .x = a.x * b.x,
                .y = a.y * b.y,
                .z = a.z * b.z,
                ._pad = 0,
            };
        }
    }

    pub fn scale(a: SimdVec3f, scalar: f32) SimdVec3f {
        if (hasVectorSupport()) {
            const s = @as(SimdVec3f, @splat(scalar));
            const result = a * s;
            return @Vector(4, f32){ result[0], result[1], result[2], 0 };
        } else {
            return SimdVec3f{
                .x = a.x * scalar,
                .y = a.y * scalar,
                .z = a.z * scalar,
                ._pad = 0,
            };
        }
    }

    pub fn dot(a: SimdVec3f, b: SimdVec3f) f32 {
        if (hasVectorSupport()) {
            const prod = a * b;
            return prod[0] + prod[1] + prod[2];
        } else {
            return a.x * b.x + a.y * b.y + a.z * b.z;
        }
    }

    pub fn cross(a: SimdVec3f, b: SimdVec3f) SimdVec3f {
        if (hasVectorSupport()) {
            // Optimized cross product using shuffle operations
            const a_yzx = @Vector(4, f32){ a[1], a[2], a[0], 0 };
            const a_zxy = @Vector(4, f32){ a[2], a[0], a[1], 0 };
            const b_yzx = @Vector(4, f32){ b[1], b[2], b[0], 0 };
            const b_zxy = @Vector(4, f32){ b[2], b[0], b[1], 0 };

            return a_yzx * b_zxy - a_zxy * b_yzx;
        } else {
            return SimdVec3f{
                .x = a.y * b.z - a.z * b.y,
                .y = a.z * b.x - a.x * b.z,
                .z = a.x * b.y - a.y * b.x,
                ._pad = 0,
            };
        }
    }

    pub fn lengthSq(a: SimdVec3f) f32 {
        return dot(a, a);
    }

    pub fn length(a: SimdVec3f) f32 {
        return @sqrt(lengthSq(a));
    }

    pub fn normalize(a: SimdVec3f) SimdVec3f {
        const len = length(a);
        if (len == 0) return a;
        return scale(a, 1.0 / len);
    }
};

/// SIMD optimized operations for Vec4
pub const SimdVec4Ops = struct {
    pub fn add(a: SimdVec4f, b: SimdVec4f) SimdVec4f {
        if (hasVectorSupport()) {
            return a + b;
        } else {
            return SimdVec4f{
                .x = a.x + b.x,
                .y = a.y + b.y,
                .z = a.z + b.z,
                .w = a.w + b.w,
            };
        }
    }

    pub fn sub(a: SimdVec4f, b: SimdVec4f) SimdVec4f {
        if (hasVectorSupport()) {
            return a - b;
        } else {
            return SimdVec4f{
                .x = a.x - b.x,
                .y = a.y - b.y,
                .z = a.z - b.z,
                .w = a.w - b.w,
            };
        }
    }

    pub fn mul(a: SimdVec4f, b: SimdVec4f) SimdVec4f {
        if (hasVectorSupport()) {
            return a * b;
        } else {
            return SimdVec4f{
                .x = a.x * b.x,
                .y = a.y * b.y,
                .z = a.z * b.z,
                .w = a.w * b.w,
            };
        }
    }

    pub fn scale(a: SimdVec4f, scalar: f32) SimdVec4f {
        if (hasVectorSupport()) {
            return a * @as(SimdVec4f, @splat(scalar));
        } else {
            return SimdVec4f{
                .x = a.x * scalar,
                .y = a.y * scalar,
                .z = a.z * scalar,
                .w = a.w * scalar,
            };
        }
    }

    pub fn dot(a: SimdVec4f, b: SimdVec4f) f32 {
        if (hasVectorSupport()) {
            const prod = a * b;
            return @reduce(.Add, prod);
        } else {
            return a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
        }
    }

    pub fn lengthSq(a: SimdVec4f) f32 {
        return dot(a, a);
    }

    pub fn length(a: SimdVec4f) f32 {
        return @sqrt(lengthSq(a));
    }

    pub fn normalize(a: SimdVec4f) SimdVec4f {
        const len = length(a);
        if (len == 0) return a;
        return scale(a, 1.0 / len);
    }
};

/// Matrix-vector multiplication optimizations
pub const SimdMatrixOps = struct {
    /// Multiply 4x4 matrix with Vec4 (column-major)
    pub fn mulMatVec4(mat: [16]f32, vec: SimdVec4f) SimdVec4f {
        if (hasVectorSupport()) {
            const col0 = @Vector(4, f32){ mat[0], mat[1], mat[2], mat[3] };
            const col1 = @Vector(4, f32){ mat[4], mat[5], mat[6], mat[7] };
            const col2 = @Vector(4, f32){ mat[8], mat[9], mat[10], mat[11] };
            const col3 = @Vector(4, f32){ mat[12], mat[13], mat[14], mat[15] };

            const x = @as(SimdVec4f, @splat(vec[0]));
            const y = @as(SimdVec4f, @splat(vec[1]));
            const z = @as(SimdVec4f, @splat(vec[2]));
            const w = @as(SimdVec4f, @splat(vec[3]));

            return col0 * x + col1 * y + col2 * z + col3 * w;
        } else {
            return @Vector(4, f32){
                mat[0] * vec[0] + mat[4] * vec[1] + mat[8] * vec[2] + mat[12] * vec[3],
                mat[1] * vec[0] + mat[5] * vec[1] + mat[9] * vec[2] + mat[13] * vec[3],
                mat[2] * vec[0] + mat[6] * vec[1] + mat[10] * vec[2] + mat[14] * vec[3],
                mat[3] * vec[0] + mat[7] * vec[1] + mat[11] * vec[2] + mat[15] * vec[3],
            };
        }
    }

    /// Multiply two 4x4 matrices (column-major)
    pub fn mulMat4(a: [16]f32, b: [16]f32) [16]f32 {
        var result: [16]f32 = undefined;

        if (hasVectorSupport()) {
            // Process 4 columns of matrix B
            inline for (0..4) |col| {
                const b_col = @Vector(4, f32){ b[col * 4 + 0], b[col * 4 + 1], b[col * 4 + 2], b[col * 4 + 3] };

                const a_col0 = @Vector(4, f32){ a[0], a[1], a[2], a[3] };
                const a_col1 = @Vector(4, f32){ a[4], a[5], a[6], a[7] };
                const a_col2 = @Vector(4, f32){ a[8], a[9], a[10], a[11] };
                const a_col3 = @Vector(4, f32){ a[12], a[13], a[14], a[15] };

                const x = @as(@Vector(4, f32), @splat(b_col[0]));
                const y = @as(@Vector(4, f32), @splat(b_col[1]));
                const z = @as(@Vector(4, f32), @splat(b_col[2]));
                const w = @as(@Vector(4, f32), @splat(b_col[3]));

                const res_col = a_col0 * x + a_col1 * y + a_col2 * z + a_col3 * w;

                result[col * 4 + 0] = res_col[0];
                result[col * 4 + 1] = res_col[1];
                result[col * 4 + 2] = res_col[2];
                result[col * 4 + 3] = res_col[3];
            }
        } else {
            // Fallback scalar implementation
            for (0..4) |col| {
                for (0..4) |row| {
                    var sum: f32 = 0;
                    for (0..4) |k| {
                        sum += a[k * 4 + row] * b[col * 4 + k];
                    }
                    result[col * 4 + row] = sum;
                }
            }
        }

        return result;
    }
};

/// Bulk operations for arrays of vectors
pub const SimdBulkOps = struct {
    /// Add arrays of Vec3 (for particle systems, etc.)
    pub fn addVec3Array(a: []const [3]f32, b: []const [3]f32, result: [][3]f32) void {
        std.debug.assert(a.len == b.len and b.len == result.len);

        if (hasVectorSupport()) {
            // Process 4 vectors at a time when possible
            const simd_count = (a.len / 4) * 4;

            for (0..simd_count / 4) |i| {
                const base = i * 4;
                if (base + 3 >= a.len) break;

                // Load 4 Vec3s as separate SIMD vectors for each component
                const ax = @Vector(4, f32){ a[base + 0][0], a[base + 1][0], a[base + 2][0], a[base + 3][0] };
                const ay = @Vector(4, f32){ a[base + 0][1], a[base + 1][1], a[base + 2][1], a[base + 3][1] };
                const az = @Vector(4, f32){ a[base + 0][2], a[base + 1][2], a[base + 2][2], a[base + 3][2] };

                const bx = @Vector(4, f32){ b[base + 0][0], b[base + 1][0], b[base + 2][0], b[base + 3][0] };
                const by = @Vector(4, f32){ b[base + 0][1], b[base + 1][1], b[base + 2][1], b[base + 3][1] };
                const bz = @Vector(4, f32){ b[base + 0][2], b[base + 1][2], b[base + 2][2], b[base + 3][2] };

                const rx = ax + bx;
                const ry = ay + by;
                const rz = az + bz;

                // Store results
                result[base + 0] = [3]f32{ rx[0], ry[0], rz[0] };
                result[base + 1] = [3]f32{ rx[1], ry[1], rz[1] };
                result[base + 2] = [3]f32{ rx[2], ry[2], rz[2] };
                result[base + 3] = [3]f32{ rx[3], ry[3], rz[3] };
            }

            // Handle remaining elements
            for (simd_count..a.len) |i| {
                result[i] = [3]f32{
                    a[i][0] + b[i][0],
                    a[i][1] + b[i][1],
                    a[i][2] + b[i][2],
                };
            }
        } else {
            // Scalar fallback
            for (0..a.len) |i| {
                result[i] = [3]f32{
                    a[i][0] + b[i][0],
                    a[i][1] + b[i][1],
                    a[i][2] + b[i][2],
                };
            }
        }
    }
};

/// Auto-vectorization hints
pub inline fn prefetch(ptr: anytype, comptime locality: u2) void {
    switch (builtin.cpu.arch) {
        .x86_64, .x86 => {
            switch (locality) {
                0 => @prefetch(ptr, .{ .cache = .data, .rw = .read, .locality = 0 }),
                1 => @prefetch(ptr, .{ .cache = .data, .rw = .read, .locality = 1 }),
                2 => @prefetch(ptr, .{ .cache = .data, .rw = .read, .locality = 2 }),
                3 => @prefetch(ptr, .{ .cache = .data, .rw = .read, .locality = 3 }),
            }
        },
        else => {
            // Other architectures may not support prefetch
        },
    }
}

/// Memory alignment helpers for SIMD
pub fn getSimdAlignment() comptime_int {
    // Initialize to safe default first
    comptime var alignment = 16;

    // We can't use runtime detection here, so use compile-time features
    switch (builtin.cpu.arch) {
        .x86_64, .x86 => {
            if (std.Target.x86.featureSetHas(builtin.cpu.features, .avx)) {
                alignment = 32;
            } else {
                alignment = 16;
            }
        },
        .aarch64, .arm => {
            alignment = 16;
        },
        else => {
            alignment = @alignOf(f32);
        },
    }

    return alignment;
}

pub const SIMD_ALIGNMENT = getSimdAlignment();

pub fn isAligned(ptr: anytype) bool {
    return @intFromPtr(ptr) % SIMD_ALIGNMENT == 0;
}

/// Tests
const testing = std.testing;

test "SIMD capabilities detection" {
    initSimd();
    // Just ensure it doesn't crash
}

test "SIMD Vec4 operations" {
    const a = if (hasVectorSupport())
        @Vector(4, f32){ 1, 2, 3, 4 }
    else
        SimdVec4f{ .x = 1, .y = 2, .z = 3, .w = 4 };

    const b = if (hasVectorSupport())
        @Vector(4, f32){ 5, 6, 7, 8 }
    else
        SimdVec4f{ .x = 5, .y = 6, .z = 7, .w = 8 };

    const sum = SimdVec4Ops.add(a, b);
    const dot = SimdVec4Ops.dot(a, b);

    if (hasVectorSupport()) {
        try testing.expectEqual(@as(f32, 6), sum[0]);
        try testing.expectEqual(@as(f32, 8), sum[1]);
        try testing.expectEqual(@as(f32, 10), sum[2]);
        try testing.expectEqual(@as(f32, 12), sum[3]);
    } else {
        try testing.expectEqual(@as(f32, 6), sum.x);
        try testing.expectEqual(@as(f32, 8), sum.y);
        try testing.expectEqual(@as(f32, 10), sum.z);
        try testing.expectEqual(@as(f32, 12), sum.w);
    }

    try testing.expectEqual(@as(f32, 70), dot); // 1*5 + 2*6 + 3*7 + 4*8
}
