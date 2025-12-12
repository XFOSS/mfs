const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const math = @import("math");
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;

const EntityId = @import("../core/entity.zig").EntityId;
const RenderComponent = @import("../components/render.zig").RenderComponent;
const BoundingBox = @import("../components/render.zig").BoundingBox;

pub const Octree = struct {
    allocator: Allocator,
    bounds: BoundingBox,
    entities: ArrayList(EntityId),
    children: [8]?*Octree,
    max_entities: u32,
    max_depth: u32,
    current_depth: u32,

    pub fn init(allocator: Allocator, bounds: BoundingBox, max_entities: u32, max_depth: u32) !*Octree {
        const octree = try allocator.create(Octree);
        octree.* = Octree{
            .allocator = allocator,
            .bounds = bounds,
            .entities = blk: {
                var list = ArrayList(EntityId).init(allocator);
                try list.ensureTotalCapacity(16);
                break :blk list;
            },
            .children = [_]?*Octree{null} ** 8,
            .max_entities = max_entities,
            .max_depth = max_depth,
            .current_depth = 0,
        };
        return octree;
    }

    pub fn deinit(self: *Octree) void {
        self.entities.deinit();
        for (self.children) |child| {
            if (child) |c| {
                c.deinit();
                self.allocator.destroy(c);
            }
        }
        self.allocator.destroy(self);
    }

    pub fn insert(self: *Octree, entity_id: EntityId, bounds: BoundingBox) !void {
        if (!self.bounds.intersects(bounds)) return;

        if (self.entities.items.len < self.max_entities or self.current_depth >= self.max_depth) {
            try self.entities.append(entity_id);
            return;
        }

        if (self.children[0] == null) {
            try self.subdivide();
        }

        for (self.children) |child| {
            if (child) |c| {
                try c.insert(entity_id, bounds);
            }
        }
    }

    fn subdivide(self: *Octree) !void {
        const center = self.bounds.center();
        const half_size = self.bounds.size().scale(0.5);

        for (0..8) |i| {
            const offset = Vec3.init(
                if (i & 1 != 0) half_size.x * 0.5 else -half_size.x * 0.5,
                if (i & 2 != 0) half_size.y * 0.5 else -half_size.y * 0.5,
                if (i & 4 != 0) half_size.z * 0.5 else -half_size.z * 0.5,
            );

            const child_center = center.add(offset);
            const child_bounds = BoundingBox.init(child_center.sub(half_size.scale(0.5)), child_center.add(half_size.scale(0.5)));

            self.children[i] = try Octree.init(self.allocator, child_bounds, self.max_entities, self.max_depth);
            self.children[i].?.current_depth = self.current_depth + 1;
        }
    }

    pub fn query(self: *Octree, query_bounds: BoundingBox, results: *ArrayList(EntityId)) !void {
        if (!self.bounds.intersects(query_bounds)) return;

        for (self.entities.items) |entity_id| {
            try results.append(entity_id);
        }

        for (self.children) |child| {
            if (child) |c| {
                try c.query(query_bounds, results);
            }
        }
    }

    pub fn clear(self: *Octree) void {
        self.entities.clearRetainingCapacity();
        for (self.children) |child| {
            if (child) |c| {
                c.clear();
            }
        }
    }
};
