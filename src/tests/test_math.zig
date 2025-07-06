const std = @import("std");
const testing = std.testing;
const mfs = @import("mfs");
const math = mfs.math;
const expect = testing.expect;
const expectEqual = testing.expectEqual;
const expectApproxEqAbs = testing.expectApproxEqAbs;

test "vector creation" {
    const v1 = math.Vec3.new(1.0, 2.0, 3.0);
    try expectEqual(v1.x, 1.0);
    try expectEqual(v1.y, 2.0);
    try expectEqual(v1.z, 3.0);

    const v2 = math.Vec3.zero;
    try expectEqual(v2.x, 0.0);
    try expectEqual(v2.y, 0.0);
    try expectEqual(v2.z, 0.0);

    const v3 = math.Vec3.one;
    try expectEqual(v3.x, 1.0);
    try expectEqual(v3.y, 1.0);
    try expectEqual(v3.z, 1.0);

    const v4 = math.Vec3.up;
    try expectEqual(v4.x, 0.0);
    try expectEqual(v4.y, 1.0);
    try expectEqual(v4.z, 0.0);
}

test "vector addition" {
    const v1 = math.Vec3.new(1.0, 2.0, 3.0);
    const v2 = math.Vec3.new(4.0, 5.0, 6.0);
    const result = v1.add(v2);

    try expectEqual(result.x, 5.0);
    try expectEqual(result.y, 7.0);
    try expectEqual(result.z, 9.0);
}

test "vector subtraction" {
    const v1 = math.Vec3.new(5.0, 7.0, 9.0);
    const v2 = math.Vec3.new(1.0, 2.0, 3.0);
    const result = v1.sub(v2);

    try expectEqual(result.x, 4.0);
    try expectEqual(result.y, 5.0);
    try expectEqual(result.z, 6.0);
}

test "vector scaling" {
    const v = math.Vec3.new(1.0, 2.0, 3.0);
    const result = v.scale(2.0);

    try expectEqual(result.x, 2.0);
    try expectEqual(result.y, 4.0);
    try expectEqual(result.z, 6.0);
}

test "vector dot product" {
    const v1 = math.Vec3.new(1.0, 2.0, 3.0);
    const v2 = math.Vec3.new(4.0, 5.0, 6.0);
    const result = v1.dot(v2);

    try expectEqual(result, 32.0); // 1*4 + 2*5 + 3*6 = 4 + 10 + 18 = 32
}

test "vector cross product" {
    const v1 = math.Vec3.new(1.0, 0.0, 0.0); // X axis
    const v2 = math.Vec3.new(0.0, 1.0, 0.0); // Y axis
    const result = v1.cross(v2);

    // X cross Y = Z
    try expectEqual(result.x, 0.0);
    try expectEqual(result.y, 0.0);
    try expectEqual(result.z, 1.0);
}

test "vector length" {
    const v = math.Vec3.new(3.0, 4.0, 0.0);
    const length = v.magnitude();

    try expectEqual(length, 5.0); // Pythagorean triple 3-4-5
}

test "vector normalize" {
    const v = math.Vec3.new(3.0, 4.0, 0.0);
    const normalized = v.normalize();

    try expectApproxEqAbs(normalized.x, 0.6, 0.0001); // 3/5 = 0.6
    try expectApproxEqAbs(normalized.y, 0.8, 0.0001); // 4/5 = 0.8
    try expectEqual(normalized.z, 0.0);

    // Test that length is approximately 1
    try expectApproxEqAbs(normalized.magnitude(), 1.0, 0.0001);
}

test "vector distance" {
    const v1 = math.Vec3.new(1.0, 2.0, 3.0);
    const v2 = math.Vec3.new(4.0, 6.0, 3.0);
    const dist = v1.distanceTo(v2);

    // Distance should be sqrt((4-1)² + (6-2)² + (3-3)²) = sqrt(9 + 16 + 0) = sqrt(25) = 5
    try expectEqual(dist, 5.0);
}

test "vector lerp" {
    const v1 = math.Vec3.new(0.0, 0.0, 0.0);
    const v2 = math.Vec3.new(10.0, 20.0, 30.0);

    // Test 0% interpolation (should be equal to v1)
    const lerp0 = v1.lerp(v2, 0.0);
    try expectEqual(lerp0.x, 0.0);
    try expectEqual(lerp0.y, 0.0);
    try expectEqual(lerp0.z, 0.0);

    // Test 100% interpolation (should be equal to v2)
    const lerp1 = v1.lerp(v2, 1.0);
    try expectEqual(lerp1.x, 10.0);
    try expectEqual(lerp1.y, 20.0);
    try expectEqual(lerp1.z, 30.0);

    // Test 50% interpolation (should be halfway between)
    const lerp05 = v1.lerp(v2, 0.5);
    try expectEqual(lerp05.x, 5.0);
    try expectEqual(lerp05.y, 10.0);
    try expectEqual(lerp05.z, 15.0);
}

test "matrix identity" {
    const m = math.Mat4.identity;

    // Diagonal should be 1s
    try expectEqual(m.m[0][0], 1.0);
    try expectEqual(m.m[1][1], 1.0);
    try expectEqual(m.m[2][2], 1.0);
    try expectEqual(m.m[3][3], 1.0);

    // Off-diagonal should be 0s
    try expectEqual(m.m[0][1], 0.0);
    try expectEqual(m.m[0][2], 0.0);
    try expectEqual(m.m[0][3], 0.0);
    try expectEqual(m.m[1][0], 0.0);
    // ... etc for all off-diagonal elements
}

test "matrix multiplication" {
    // Test identity property: M * I = M
    const m = math.Mat4.translation(1.0, 2.0, 3.0);
    const i = math.Mat4.identity;
    const result = m.mul(i);

    // Should be equal to the original matrix
    try expectEqual(result.m[0][0], m.m[0][0]);
    try expectEqual(result.m[1][1], m.m[1][1]);
    try expectEqual(result.m[2][2], m.m[2][2]);
    try expectEqual(result.m[3][0], m.m[3][0]); // Translation X
    try expectEqual(result.m[3][1], m.m[3][1]); // Translation Y
    try expectEqual(result.m[3][2], m.m[3][2]); // Translation Z
}

test "matrix translation" {
    const tx = 5.0;
    const ty = -3.0;
    const tz = 7.0;
    const t = math.Mat4.translation(tx, ty, tz);

    // Check the translation components
    try expectEqual(t.m[3][0], tx);
    try expectEqual(t.m[3][1], ty);
    try expectEqual(t.m[3][2], tz);

    // Check that the matrix preserves points during transformation
    const p = math.Vec3.new(1.0, 2.0, 3.0);
    const transformed = t.mulPoint(p);

    try expectEqual(transformed.x, p.x + tx);
    try expectEqual(transformed.y, p.y + ty);
    try expectEqual(transformed.z, p.z + tz);
}

test "matrix scaling" {
    const sx = 2.0;
    const sy = 3.0;
    const sz = 4.0;
    const s = math.Mat4.scaling(sx, sy, sz);

    // Check the scaling components
    try expectEqual(s.m[0][0], sx);
    try expectEqual(s.m[1][1], sy);
    try expectEqual(s.m[2][2], sz);

    // Check that the matrix scales vectors correctly
    const v = math.Vec3.new(1.0, 1.0, 1.0);
    const scaled = s.mulDirection(v);

    try expectEqual(scaled.x, v.x * sx);
    try expectEqual(scaled.y, v.y * sy);
    try expectEqual(scaled.z, v.z * sz);
}

// TODO: Re-enable when matrix rotation is implemented
// test "matrix rotation" {
//     // Test rotation around Y axis by 90 degrees
//     const angle = std.math.pi / 2.0; // 90 degrees in radians
//     const r = math.Mat4.rotation(math.Vec3.new(0.0, 1.0, 0.0), angle);
//
//     // Rotating (1,0,0) around Y by 90 degrees should give (0,0,-1)
//     const v = math.Vec3.new(1.0, 0.0, 0.0);
//     const rotated = r.mulDirection(v);
//
//     try expectApproxEqAbs(rotated.x, 0.0, 0.0001);
//     try expectApproxEqAbs(rotated.y, 0.0, 0.0001);
//     try expectApproxEqAbs(rotated.z, -1.0, 0.0001);
// }

// TODO: Re-enable when matrix inversion and chaining are implemented
// test "matrix inversion" {
//     // Create a test matrix
//     const m = math.Mat4.translation(1.0, 2.0, 3.0)
//         .mul(math.Mat4.scaling(2.0, 2.0, 2.0));
//
//     // Invert it
//     const inv = try m.invert();
//
//     // Multiplying by its inverse should give the identity matrix
//     const should_be_identity = m.mul(inv);
//
//     // Check diagonal elements are close to 1
//     try expectApproxEqAbs(should_be_identity.m[0][0], 1.0, 0.0001);
//     try expectApproxEqAbs(should_be_identity.m[1][1], 1.0, 0.0001);
//     try expectApproxEqAbs(should_be_identity.m[2][2], 1.0, 0.0001);
//     try expectApproxEqAbs(should_be_identity.m[3][3], 1.0, 0.0001);
//
//     // Check off-diagonal elements are close to 0
//     try expectApproxEqAbs(should_be_identity.m[0][1], 0.0, 0.0001);
//     try expectApproxEqAbs(should_be_identity.m[0][2], 0.0, 0.0001);
//     try expectApproxEqAbs(should_be_identity.m[0][3], 0.0, 0.0001);
//     // ... etc for all off-diagonal elements
// }

// TODO: Re-enable when perspective matrix is implemented
// test "matrix projection" {
//     const fov = std.math.pi / 4.0; // 45 degrees
//     const aspect = 16.0 / 9.0; // Widescreen aspect ratio
//     const near = 0.1;
//     const far = 100.0;
//
//     const proj = math.Mat4.perspective(fov, aspect, near, far);
//
//     // Perspective matrix should have some specific properties
//     try expect(proj.m[0][0] > 0.0); // X scale should be positive
//     try expect(proj.m[1][1] > 0.0); // Y scale should be positive
//     try expectEqual(proj.m[2][2], -(far + near) / (far - near)); // Z projection formula
//     try expectEqual(proj.m[3][2], -1.0); // W component gets Z value
// }

// TODO: Re-enable when Quaternion type is properly exported
// test "quaternion basics" {
//     // Test identity quaternion
//     const q_id = math.Quat.identity();
//     try expectEqual(q_id.x, 0.0);
//     try expectEqual(q_id.y, 0.0);
//     try expectEqual(q_id.z, 0.0);
//     try expectEqual(q_id.w, 1.0);
//
//     // Test axis-angle construction
//     const axis = math.Vec3.new(0.0, 1.0, 0.0); // Y axis
//     const angle = std.math.pi / 2.0; // 90 degrees
//     const q = math.Quat.fromAxisAngle(axis, angle);
//
//     // Values for 90 degree rotation around Y (0, sin(45°), 0, cos(45°))
//     const s = @sin(angle / 2.0);
//     const c = @cos(angle / 2.0);
//     try expectApproxEqAbs(q.x, 0.0, 0.0001);
//     try expectApproxEqAbs(q.y, s, 0.0001);
//     try expectApproxEqAbs(q.z, 0.0, 0.0001);
//     try expectApproxEqAbs(q.w, c, 0.0001);
// }

// TODO: Re-enable when Quaternion type is properly exported
// test "quaternion vector rotation" {
//     // Create a quaternion for 90 degree rotation around Y axis
//     const axis = math.Vec3.new(0.0, 1.0, 0.0);
//     const angle = std.math.pi / 2.0; // 90 degrees
//     const q = math.Quat.fromAxisAngle(axis, angle);
//
//     // Rotate the vector (1,0,0) -> should become (0,0,-1)
//     const v = math.Vec3.new(1.0, 0.0, 0.0);
//     const rotated = q.rotate(v);
//
//     try expectApproxEqAbs(rotated.x, 0.0, 0.0001);
//     try expectApproxEqAbs(rotated.y, 0.0, 0.0001);
//     try expectApproxEqAbs(rotated.z, -1.0, 0.0001);
// }

// TODO: Re-enable when Quaternion type is properly exported
// test "quaternion multiplication" {
//     // Create two 90 degree rotations around Y
//     const q1 = math.Quat.fromAxisAngle(math.Vec3.new(0.0, 1.0, 0.0), std.math.pi / 2.0);
//     const q2 = math.Quat.fromAxisAngle(math.Vec3.new(0.0, 1.0, 0.0), std.math.pi / 2.0);
//
//     // Combine them (should be equivalent to 180 degree rotation)
//     const q_combined = q1.mul(q2);
//
//     // Rotate a vector with the combined quaternion
//     const v = math.Vec3.new(1.0, 0.0, 0.0);
//     const rotated = q_combined.rotate(v);
//
//     // After 180 degree rotation around Y, (1,0,0) should become (-1,0,0)
//     try expectApproxEqAbs(rotated.x, -1.0, 0.0001);
//     try expectApproxEqAbs(rotated.y, 0.0, 0.0001);
//     try expectApproxEqAbs(rotated.z, 0.0, 0.0001);
// }

// TODO: Re-enable when Quaternion type is properly exported
// test "quaternion slerp" {
//     // Create two quaternions: identity and 180 degree rotation around Y
//     const q1 = math.Quat.identity();
//     const q2 = math.Quat.fromAxisAngle(math.Vec3.new(0.0, 1.0, 0.0), std.math.pi);
//
//     // Test 0% interpolation (should be equal to q1)
//     const slerp0 = q1.slerp(q2, 0.0);
//     try expectApproxEqAbs(slerp0.x, q1.x, 0.0001);
//     try expectApproxEqAbs(slerp0.y, q1.y, 0.0001);
//     try expectApproxEqAbs(slerp0.z, q1.z, 0.0001);
//     try expectApproxEqAbs(slerp0.w, q1.w, 0.0001);
//
//     // Test 100% interpolation (should be equal to q2)
//     const slerp1 = q1.slerp(q2, 1.0);
//     try expectApproxEqAbs(slerp1.x, q2.x, 0.0001);
//     try expectApproxEqAbs(slerp1.y, q2.y, 0.0001);
//     try expectApproxEqAbs(slerp1.z, q2.z, 0.0001);
//     try expectApproxEqAbs(slerp1.w, q2.w, 0.0001);
//
//     // Test 50% interpolation (should be 90 degree rotation)
//     const slerp05 = q1.slerp(q2, 0.5);
//
//     // Verify by rotating a vector and checking the result
//     const v = math.Vec3.new(1.0, 0.0, 0.0);
//     const rotated = slerp05.rotate(v);
//
//     // After 90 degree rotation around Y, (1,0,0) should become approximately (0,0,-1)
//     try expectApproxEqAbs(rotated.x, 0.0, 0.0001);
//     try expectApproxEqAbs(rotated.y, 0.0, 0.0001);
//     try expectApproxEqAbs(rotated.z, -1.0, 0.0001);
// }

// TODO: Re-enable when Quaternion type is properly exported
// test "quaternion to/from euler angles" {
//     // Create Euler angles (in radians)
//     const euler = math.Vec3.new(std.math.pi / 4.0, // X - pitch - 45 degrees
//         std.math.pi / 2.0, // Y - yaw   - 90 degrees
//         0.0 // Z - roll  -  0 degrees
//     );
//
//     // Convert to quaternion
//     const q = math.Quat.fromEulerAngles(euler);
//
//     // Convert back to Euler angles
//     const euler2 = q.toEulerAngles();
//
//     // Angles should match (allowing for 2π differences and singularities)
//     // For this test we'll just check if the resulting rotation is the same by applying it to a vector
//
//     const v = math.Vec3.new(1.0, 0.0, 0.0);
//
//     // Create rotation matrices from both Euler angles
//     const m1 = math.Mat4.fromEulerAngles(euler);
//     const m2 = math.Mat4.fromEulerAngles(euler2);
//
//     // Apply the rotations
//     const v1 = m1.transformVector(v);
//     const v2 = m2.transformVector(v);
//
//     // Results should be the same
//     try expectApproxEqAbs(v1.x, v2.x, 0.0001);
//     try expectApproxEqAbs(v1.y, v2.y, 0.0001);
//     try expectApproxEqAbs(v1.z, v2.z, 0.0001);
// }

// TODO: Re-enable when matrix chaining is implemented
// test "Matrix4x4 inversion" {
//     const m = math.Mat4.identity().translate(math.Vec3.new(1, 2, 3));
//     const inv = try m.invert();
//     const result = m.mul(inv);
//
//     // Check if result is approximately identity matrix
//     try expectApproxEqAbs(result.m[0][0], 1.0, 0.0001);
//     try expectApproxEqAbs(result.m[1][1], 1.0, 0.0001);
//     try expectApproxEqAbs(result.m[2][2], 1.0, 0.0001);
//     try expectApproxEqAbs(result.m[3][3], 1.0, 0.0001);
// }
