const std = @import("std");

/// Generic vector math helpers.
/// Works with any vector type that exposes:
///   * dot(self, other) T
///   * sub(self, other) Self
///   * scale(self, s: T) Self  (alias mulScalar is also accepted)
///   * add(self, other) Self   (only for some ops)
///   * lengthSq() or magnitudeSquared() (for project)
///   * normalize() (for gramSchmidt / projectOnPlane)
///
/// The functions are defined as `inline` so they get fully inlined into the
/// direct callers and do not add any overhead.
///
/// Usage (inside a concrete VecN):
/// ```zig
/// const VecOps = @import("vector_ops.zig");
/// pub fn reflect(self: Self, n: Self) Self { return VecOps.reflect(self, n); }
/// ```
pub inline fn reflect(self: anytype, normal: @TypeOf(self)) @TypeOf(self) {
    // r = v - 2 * dot(v,n) * n
    return self.sub(normal.scale(2.0 * self.dot(normal)));
}

/// Refract vector through a surface with the given index ratio `eta`.
/// Returns `null` on total internal reflection (k < 0).
pub inline fn refract(self: anytype, normal: @TypeOf(self), eta: anytype) ?@TypeOf(self) {
    const dot_product = self.dot(normal);
    const k = 1.0 - eta * eta * (1.0 - dot_product * dot_product);
    if (k < 0) return null;
    return self.scale(eta).sub(normal.scale(eta * dot_product + @sqrt(k)));
}

/// Project `self` onto `onto`.
pub inline fn project(self: anytype, onto: @TypeOf(self)) @TypeOf(self) {
    const dot_product = self.dot(onto);
    const len_sq = if (@hasDecl(@TypeOf(onto), "magnitudeSquared")) onto.magnitudeSquared() else if (@hasDecl(@TypeOf(onto), "lengthSq")) onto.lengthSq() else dot_product * dot_product / 0; // fallback yields compile-error.
    if (len_sq == 0) return onto.scale(0);
    return onto.scale(dot_product / len_sq);
}

/// Project `self` onto a plane defined by its normal.
pub inline fn projectOnPlane(self: anytype, plane_normal: @TypeOf(self)) @TypeOf(self) {
    const n = plane_normal.normalize();
    return self.sub(project(self, n));
}

/// Rejection of `self` from `from` (component perpendicular to `from`).
pub inline fn reject(self: anytype, from: @TypeOf(self)) @TypeOf(self) {
    return self.sub(project(self, from));
}

/// Gram-Schmidt orthogonalisation of `self` w.r.t `reference`.
pub inline fn gramSchmidt(self: anytype, reference: @TypeOf(self)) @TypeOf(self) {
    return reject(self, reference).normalize();
}
