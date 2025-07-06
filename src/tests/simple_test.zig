const std = @import("std");
const testing = std.testing;
const math = @import("math");

test "basic math types" {
    // Test Vec3f (Vec3 with f32)
    const v1 = math.Vec3f.init(1.0, 2.0, 3.0);
    try testing.expectEqual(@as(f32, 1.0), v1.x);
    try testing.expectEqual(@as(f32, 2.0), v1.y);
    try testing.expectEqual(@as(f32, 3.0), v1.z);

    // Test Vec3f constants
    const zero = math.Vec3f.zero;
    try testing.expectEqual(@as(f32, 0.0), zero.x);
    try testing.expectEqual(@as(f32, 0.0), zero.y);
    try testing.expectEqual(@as(f32, 0.0), zero.z);

    // Test Vec3f operations
    const v2 = math.Vec3f.init(4.0, 5.0, 6.0);
    const sum = v1.add(v2);
    try testing.expectEqual(@as(f32, 5.0), sum.x);
    try testing.expectEqual(@as(f32, 7.0), sum.y);
    try testing.expectEqual(@as(f32, 9.0), sum.z);
}

test "vector operations" {
    const v1 = math.Vec3f.init(1.0, 0.0, 0.0);
    const v2 = math.Vec3f.init(0.0, 1.0, 0.0);

    // Test dot product
    const dot = v1.dot(v2);
    try testing.expectEqual(@as(f32, 0.0), dot);

    // Test cross product
    const cross = v1.cross(v2);
    try testing.expectEqual(@as(f32, 0.0), cross.x);
    try testing.expectEqual(@as(f32, 0.0), cross.y);
    try testing.expectEqual(@as(f32, 1.0), cross.z);
}

test "vector magnitude" {
    const v = math.Vec3f.init(3.0, 4.0, 0.0);
    const mag = v.magnitude();
    try testing.expectEqual(@as(f32, 5.0), mag);
}
