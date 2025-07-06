//! MFS Engine - Core Types
//! Common types and type aliases used throughout the engine.
//!
//! This module provides fundamental types that are used across the engine:
//! - Vector types for SIMD operations
//! - Handle types for resource management
//! - Result and Optional types for error handling
//! - Geometric types (bounds, dimensions)
//! - Color representation
//! - ID and versioning types
//!
//! @thread-safe: All types are value types and thread-safe
//! @allocator-aware: no - types do not allocate
//! @platform: all

const std = @import("std");

// =============================================================================
// Vector Types
// =============================================================================

/// 2D float vector
pub const Vec2f = @Vector(2, f32);
/// 3D float vector
pub const Vec3f = @Vector(3, f32);
/// 4D float vector
pub const Vec4f = @Vector(4, f32);

/// 2D integer vector
pub const Vec2i = @Vector(2, i32);
/// 3D integer vector
pub const Vec3i = @Vector(3, i32);
/// 4D integer vector
pub const Vec4i = @Vector(4, i32);

// Legacy aliases for backward compatibility
pub const f32x2 = Vec2f;
pub const f32x3 = Vec3f;
pub const f32x4 = Vec4f;
pub const i32x2 = Vec2i;
pub const i32x3 = Vec3i;
pub const i32x4 = Vec4i;

// =============================================================================
// ID Types
// =============================================================================

/// Unique identifier type
pub const Id = u64;

/// Entity ID for ECS systems
pub const EntityId = Id;

/// Component ID for ECS systems
pub const ComponentId = Id;

/// System ID for ECS systems
pub const SystemId = Id;

/// Generate a new unique ID
pub fn generateId() Id {
    return @bitCast(std.time.nanoTimestamp());
}

// =============================================================================
// Handle Types
// =============================================================================

/// Generic handle with generation counter for validity checking
pub const Handle = struct {
    id: u64,
    generation: u32,

    pub const INVALID = Handle{ .id = std.math.maxInt(u64), .generation = 0 };

    /// Check if this handle is valid
    pub fn isValid(self: Handle) bool {
        return self.id != INVALID.id;
    }

    /// Create a new handle with the given ID and generation
    pub fn init(id: u64, generation: u32) Handle {
        return .{ .id = id, .generation = generation };
    }

    /// Compare two handles for equality
    pub fn eql(self: Handle, other: Handle) bool {
        return self.id == other.id and self.generation == other.generation;
    }
};

// Specific handle types for type safety
pub const TextureHandle = Handle;
pub const BufferHandle = Handle;
pub const ShaderHandle = Handle;
pub const MaterialHandle = Handle;
pub const MeshHandle = Handle;
pub const SoundHandle = Handle;
pub const FontHandle = Handle;
pub const SceneHandle = Handle;
pub const AnimationHandle = Handle;

// =============================================================================
// Version Type
// =============================================================================

/// Semantic versioning type
pub const Version = struct {
    major: u32,
    minor: u32,
    patch: u32,

    /// Create a new version
    pub fn init(major: u32, minor: u32, patch: u32) Version {
        return .{ .major = major, .minor = minor, .patch = patch };
    }

    /// Compare versions
    pub fn compare(self: Version, other: Version) std.math.Order {
        if (self.major != other.major) {
            return std.math.order(self.major, other.major);
        }
        if (self.minor != other.minor) {
            return std.math.order(self.minor, other.minor);
        }
        return std.math.order(self.patch, other.patch);
    }

    /// Check if this version is compatible with a required version
    pub fn isCompatible(self: Version, required: Version) bool {
        return self.major == required.major and
            (self.minor > required.minor or
                (self.minor == required.minor and self.patch >= required.patch));
    }

    /// Format version as string (caller owns memory)
    pub fn format(self: Version, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{}.{}.{}", .{ self.major, self.minor, self.patch });
    }
};

// =============================================================================
// Result Types
// =============================================================================

/// Result type for operations that can fail
pub fn Result(comptime T: type) type {
    return union(enum) {
        ok: T,
        err: anyerror,

        const Self = @This();

        /// Check if the result is Ok
        pub fn isOk(self: Self) bool {
            return switch (self) {
                .ok => true,
                .err => false,
            };
        }

        /// Check if the result is Err
        pub fn isErr(self: Self) bool {
            return !self.isOk();
        }

        /// Get the value or panic with error name
        pub fn unwrap(self: Self) T {
            return switch (self) {
                .ok => |value| value,
                .err => |err| std.debug.panic("Result.unwrap() called on Err: {s}", .{@errorName(err)}),
            };
        }

        /// Get the value or return default
        pub fn unwrapOr(self: Self, default: T) T {
            return switch (self) {
                .ok => |value| value,
                .err => default,
            };
        }

        /// Get the value or compute default
        pub fn unwrapOrElse(self: Self, comptime defaultFn: fn () T) T {
            return switch (self) {
                .ok => |value| value,
                .err => defaultFn(),
            };
        }

        /// Transform the Ok value
        pub fn map(self: Self, comptime U: type, mapFn: fn (T) U) Result(U) {
            return switch (self) {
                .ok => |value| .{ .ok = mapFn(value) },
                .err => |e| .{ .err = e },
            };
        }
    };
}

// =============================================================================
// Optional Types
// =============================================================================

/// Optional type with explicit null handling
pub fn Optional(comptime T: type) type {
    return union(enum) {
        some: T,
        none,

        const Self = @This();

        /// Create an Optional with a value
        pub fn of(value: T) Self {
            return .{ .some = value };
        }

        /// Create an empty Optional
        pub fn empty() Self {
            return .none;
        }

        /// Check if the optional has a value
        pub fn isSome(self: Self) bool {
            return switch (self) {
                .some => true,
                .none => false,
            };
        }

        /// Check if the optional is empty
        pub fn isNone(self: Self) bool {
            return !self.isSome();
        }

        /// Get the value or panic
        pub fn unwrap(self: Self) T {
            return switch (self) {
                .some => |value| value,
                .none => std.debug.panic("Optional.unwrap() called on None", .{}),
            };
        }

        /// Get the value or return default
        pub fn unwrapOr(self: Self, default: T) T {
            return switch (self) {
                .some => |value| value,
                .none => default,
            };
        }

        /// Transform the Some value
        pub fn map(self: Self, comptime U: type, mapFn: fn (T) U) Optional(U) {
            return switch (self) {
                .some => |value| .{ .some = mapFn(value) },
                .none => .none,
            };
        }
    };
}

// =============================================================================
// Geometric Types
// =============================================================================

/// 2D axis-aligned bounding box
pub const Bounds2D = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,

    /// Create bounds from position and size
    pub fn init(x: f32, y: f32, width: f32, height: f32) Bounds2D {
        return .{ .x = x, .y = y, .width = width, .height = height };
    }

    /// Create bounds from min and max points
    pub fn fromMinMax(min: Vec2f, max: Vec2f) Bounds2D {
        return .{
            .x = min[0],
            .y = min[1],
            .width = max[0] - min[0],
            .height = max[1] - min[1],
        };
    }

    /// Get the center point
    pub fn center(self: Bounds2D) Vec2f {
        return .{ self.x + self.width * 0.5, self.y + self.height * 0.5 };
    }

    /// Check if point is inside bounds
    pub fn contains(self: Bounds2D, point: Vec2f) bool {
        return point[0] >= self.x and point[0] <= self.x + self.width and
            point[1] >= self.y and point[1] <= self.y + self.height;
    }

    /// Check if two bounds intersect
    pub fn intersects(self: Bounds2D, other: Bounds2D) bool {
        return !(self.x + self.width < other.x or
            other.x + other.width < self.x or
            self.y + self.height < other.y or
            other.y + other.height < self.y);
    }

    /// Compute intersection of two bounds
    pub fn intersection(self: Bounds2D, other: Bounds2D) ?Bounds2D {
        if (!self.intersects(other)) return null;

        const x1 = @max(self.x, other.x);
        const y1 = @max(self.y, other.y);
        const x2 = @min(self.x + self.width, other.x + other.width);
        const y2 = @min(self.y + self.height, other.y + other.height);

        return Bounds2D.init(x1, y1, x2 - x1, y2 - y1);
    }

    /// Expand bounds to include point
    pub fn expandToInclude(self: *Bounds2D, point: Vec2f) void {
        const min_x = @min(self.x, point[0]);
        const min_y = @min(self.y, point[1]);
        const max_x = @max(self.x + self.width, point[0]);
        const max_y = @max(self.y + self.height, point[1]);

        self.x = min_x;
        self.y = min_y;
        self.width = max_x - min_x;
        self.height = max_y - min_y;
    }
};

/// 3D axis-aligned bounding box
pub const Bounds3D = struct {
    x: f32,
    y: f32,
    z: f32,
    width: f32,
    height: f32,
    depth: f32,

    /// Create bounds from position and size
    pub fn init(x: f32, y: f32, z: f32, width: f32, height: f32, depth: f32) Bounds3D {
        return .{ .x = x, .y = y, .z = z, .width = width, .height = height, .depth = depth };
    }

    /// Create bounds from min and max points
    pub fn fromMinMax(min: Vec3f, max: Vec3f) Bounds3D {
        return .{
            .x = min[0],
            .y = min[1],
            .z = min[2],
            .width = max[0] - min[0],
            .height = max[1] - min[1],
            .depth = max[2] - min[2],
        };
    }

    /// Get the center point
    pub fn center(self: Bounds3D) Vec3f {
        return .{
            self.x + self.width * 0.5,
            self.y + self.height * 0.5,
            self.z + self.depth * 0.5,
        };
    }

    /// Check if point is inside bounds
    pub fn contains(self: Bounds3D, point: Vec3f) bool {
        return point[0] >= self.x and point[0] <= self.x + self.width and
            point[1] >= self.y and point[1] <= self.y + self.height and
            point[2] >= self.z and point[2] <= self.z + self.depth;
    }
};

// =============================================================================
// Color Types
// =============================================================================

/// RGBA color with floating-point components
pub const Color = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32 = 1.0,

    // Predefined colors
    pub const WHITE = Color{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 };
    pub const BLACK = Color{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 };
    pub const RED = Color{ .r = 1.0, .g = 0.0, .b = 0.0, .a = 1.0 };
    pub const GREEN = Color{ .r = 0.0, .g = 1.0, .b = 0.0, .a = 1.0 };
    pub const BLUE = Color{ .r = 0.0, .g = 0.0, .b = 1.0, .a = 1.0 };
    pub const YELLOW = Color{ .r = 1.0, .g = 1.0, .b = 0.0, .a = 1.0 };
    pub const CYAN = Color{ .r = 0.0, .g = 1.0, .b = 1.0, .a = 1.0 };
    pub const MAGENTA = Color{ .r = 1.0, .g = 0.0, .b = 1.0, .a = 1.0 };
    pub const TRANSPARENT = Color{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 0.0 };

    /// Create color from RGB values (0-1 range)
    pub fn init(r: f32, g: f32, b: f32) Color {
        return .{ .r = r, .g = g, .b = b, .a = 1.0 };
    }

    /// Create color from RGBA values (0-1 range)
    pub fn initRgba(r: f32, g: f32, b: f32, a: f32) Color {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    /// Create color from hex value (RGB)
    pub fn fromHex(hex: u32) Color {
        return Color{
            .r = @as(f32, @floatFromInt((hex >> 16) & 0xFF)) / 255.0,
            .g = @as(f32, @floatFromInt((hex >> 8) & 0xFF)) / 255.0,
            .b = @as(f32, @floatFromInt(hex & 0xFF)) / 255.0,
            .a = 1.0,
        };
    }

    /// Create color from hex value (RGBA)
    pub fn fromHexRgba(hex: u32) Color {
        return Color{
            .r = @as(f32, @floatFromInt((hex >> 24) & 0xFF)) / 255.0,
            .g = @as(f32, @floatFromInt((hex >> 16) & 0xFF)) / 255.0,
            .b = @as(f32, @floatFromInt((hex >> 8) & 0xFF)) / 255.0,
            .a = @as(f32, @floatFromInt(hex & 0xFF)) / 255.0,
        };
    }

    /// Convert to hex value (RGB only)
    pub fn toHex(self: Color) u32 {
        const r = @as(u32, @intFromFloat(std.math.clamp(self.r * 255.0, 0, 255)));
        const g = @as(u32, @intFromFloat(std.math.clamp(self.g * 255.0, 0, 255)));
        const b = @as(u32, @intFromFloat(std.math.clamp(self.b * 255.0, 0, 255)));
        return (r << 16) | (g << 8) | b;
    }

    /// Convert to hex value (RGBA)
    pub fn toHexRgba(self: Color) u32 {
        const r = @as(u32, @intFromFloat(std.math.clamp(self.r * 255.0, 0, 255)));
        const g = @as(u32, @intFromFloat(std.math.clamp(self.g * 255.0, 0, 255)));
        const b = @as(u32, @intFromFloat(std.math.clamp(self.b * 255.0, 0, 255)));
        const a = @as(u32, @intFromFloat(std.math.clamp(self.a * 255.0, 0, 255)));
        return (r << 24) | (g << 16) | (b << 8) | a;
    }

    /// Convert to Vec4f
    pub fn toVec4(self: Color) Vec4f {
        return .{ self.r, self.g, self.b, self.a };
    }

    /// Create from Vec4f
    pub fn fromVec4(vec: Vec4f) Color {
        return .{ .r = vec[0], .g = vec[1], .b = vec[2], .a = vec[3] };
    }

    /// Blend two colors
    pub fn blend(self: Color, other: Color, t: f32) Color {
        const t_clamped = std.math.clamp(t, 0.0, 1.0);
        return .{
            .r = self.r + (other.r - self.r) * t_clamped,
            .g = self.g + (other.g - self.g) * t_clamped,
            .b = self.b + (other.b - self.b) * t_clamped,
            .a = self.a + (other.a - self.a) * t_clamped,
        };
    }

    /// Multiply color by scalar
    pub fn scale(self: Color, s: f32) Color {
        return .{
            .r = self.r * s,
            .g = self.g * s,
            .b = self.b * s,
            .a = self.a,
        };
    }
};

// =============================================================================
// Tests
// =============================================================================

test "core types - Handle" {
    const testing = std.testing;

    // Test handle creation and validation
    const handle = Handle.init(42, 1);
    try testing.expect(handle.isValid());
    try testing.expect(handle.id == 42);
    try testing.expect(handle.generation == 1);

    // Test invalid handle
    try testing.expect(!Handle.INVALID.isValid());

    // Test handle equality
    const handle2 = Handle.init(42, 1);
    const handle3 = Handle.init(42, 2);
    try testing.expect(handle.eql(handle2));
    try testing.expect(!handle.eql(handle3));
}

test "core types - Version" {
    const testing = std.testing;

    const v1 = Version.init(1, 2, 3);
    const v2 = Version.init(1, 2, 4);
    const v3 = Version.init(2, 0, 0);

    // Test comparison
    try testing.expect(v1.compare(v2) == .lt);
    try testing.expect(v2.compare(v1) == .gt);
    try testing.expect(v1.compare(v1) == .eq);

    // Test compatibility
    try testing.expect(v2.isCompatible(v1));
    try testing.expect(!v1.isCompatible(v2));
    try testing.expect(!v3.isCompatible(v1));

    // Test formatting
    const str = try v1.format(testing.allocator);
    defer testing.allocator.free(str);
    try testing.expectEqualStrings("1.2.3", str);
}

test "core types - Result" {
    const testing = std.testing;

    const ok_result = Result(i32){ .ok = 42 };
    const err_result = Result(i32){ .err = error.TestError };

    try testing.expect(ok_result.isOk());
    try testing.expect(!ok_result.isErr());
    try testing.expect(!err_result.isOk());
    try testing.expect(err_result.isErr());

    try testing.expect(ok_result.unwrapOr(0) == 42);
    try testing.expect(err_result.unwrapOr(0) == 0);

    // Test map
    const mapped = ok_result.map(i32, struct {
        fn double(x: i32) i32 {
            return x * 2;
        }
    }.double);
    try testing.expect(mapped.unwrapOr(0) == 84);
}

test "core types - Optional" {
    const testing = std.testing;

    const some_opt = Optional(i32).of(42);
    const none_opt = Optional(i32).empty();

    try testing.expect(some_opt.isSome());
    try testing.expect(!some_opt.isNone());
    try testing.expect(!none_opt.isSome());
    try testing.expect(none_opt.isNone());

    try testing.expect(some_opt.unwrapOr(0) == 42);
    try testing.expect(none_opt.unwrapOr(0) == 0);

    // Test map
    const mapped = some_opt.map(i32, struct {
        fn double(x: i32) i32 {
            return x * 2;
        }
    }.double);
    try testing.expect(mapped.unwrapOr(0) == 84);
}

test "core types - Bounds2D" {
    const testing = std.testing;

    const bounds1 = Bounds2D.init(0, 0, 100, 100);
    const bounds2 = Bounds2D.init(50, 50, 100, 100);

    // Test contains
    try testing.expect(bounds1.contains(.{ 50, 50 }));
    try testing.expect(!bounds1.contains(.{ 150, 50 }));

    // Test intersects
    try testing.expect(bounds1.intersects(bounds2));

    // Test intersection
    const inter = bounds1.intersection(bounds2).?;
    try testing.expect(inter.x == 50);
    try testing.expect(inter.y == 50);
    try testing.expect(inter.width == 50);
    try testing.expect(inter.height == 50);

    // Test center
    const c = bounds1.center();
    try testing.expect(c[0] == 50);
    try testing.expect(c[1] == 50);
}

test "core types - Color" {
    const testing = std.testing;

    // Test predefined colors
    const red = Color.RED;
    try testing.expect(red.r == 1.0);
    try testing.expect(red.g == 0.0);
    try testing.expect(red.b == 0.0);
    try testing.expect(red.a == 1.0);

    // Test hex conversion
    const from_hex = Color.fromHex(0xFF0000);
    try testing.expect(from_hex.r == 1.0);
    try testing.expect(from_hex.g == 0.0);
    try testing.expect(from_hex.b == 0.0);
    try testing.expect(from_hex.toHex() == 0xFF0000);

    // Test blending
    const white = Color.WHITE;
    const black = Color.BLACK;
    const gray = white.blend(black, 0.5);
    try testing.expect(gray.r == 0.5);
    try testing.expect(gray.g == 0.5);
    try testing.expect(gray.b == 0.5);

    // Test vector conversion
    const vec = red.toVec4();
    try testing.expect(vec[0] == 1.0);
    try testing.expect(vec[1] == 0.0);
    try testing.expect(vec[2] == 0.0);
    try testing.expect(vec[3] == 1.0);
}
