const std = @import("std");
const math = @import("../math/vector.zig");
const Vec4 = math.Vec4;
const Vector = math.Vector;
const physics_engine = @import("physics_engine.zig");
const PhysicalObject = physics_engine.PhysicalObject;
const CollisionResolver = @import("collision_resolver.zig").CollisionResolver;

/// Cell in the spatial grid
pub const GridCell = struct {
    objects: std.ArrayList(usize),

    pub fn init(allocator: std.mem.Allocator) GridCell {
        return GridCell{
            .objects = std.ArrayList(usize).init(allocator),
        };
    }

    pub fn deinit(self: *GridCell) void {
        self.objects.deinit();
    }
};

/// Spatial hash grid for broad-phase collision detection
pub const SpatialGrid = struct {
    allocator: std.mem.Allocator,
    cell_size: f32,
    inv_cell_size: f32,
    world_size: f32,
    grid_dim: u32,
    cells: []GridCell,
    collision_pairs: std.ArrayList([2]usize),

    /// Initialize a new spatial grid
    pub fn init(allocator: std.mem.Allocator, world_size: f32, cell_size: f32) !SpatialGrid {
        const grid_dim = @ceil(world_size / cell_size);
        const total_cells = grid_dim * grid_dim * grid_dim;

        if (total_cells > 1_000_000) {
            return error.GridTooLarge;
        }

        const total_cells_usize: usize = @intFromFloat(total_cells);

        const cells = try allocator.alloc(GridCell, total_cells_usize);
        for (cells) |*cell| {
            cell.* = GridCell.init(allocator);
        }

        return SpatialGrid{
            .allocator = allocator,
            .cell_size = cell_size,
            .inv_cell_size = 1.0 / cell_size,
            .world_size = world_size,
            .grid_dim = @intFromFloat(grid_dim),
            .cells = cells,
            .collision_pairs = std.ArrayList([2]usize).init(allocator),
        };
    }

    /// Clean up resources
    pub fn deinit(self: *SpatialGrid) void {
        for (self.cells) |*cell| {
            cell.deinit();
        }
        self.allocator.free(self.cells);
        self.collision_pairs.deinit();
    }

    /// Clear all cells (should be called each frame before insertion)
    pub fn clear(self: *SpatialGrid) void {
        for (self.cells) |*cell| {
            cell.objects.clearRetainingCapacity();
        }
        self.collision_pairs.clearRetainingCapacity();
    }

    /// Get 1D grid index from 3D position
    fn positionToIndex(self: SpatialGrid, position: Vec4) ?usize {
        // Convert world position to grid coordinates
        const half_world = self.world_size * 0.5;
        const x = @floor((position[0] + half_world) * self.inv_cell_size);
        const y = @floor((position[1] + half_world) * self.inv_cell_size);
        const z = @floor((position[2] + half_world) * self.inv_cell_size);

        // Check if position is within grid bounds
        const dim_f: f32 = @floatFromInt(self.grid_dim);
        if (x < 0 or x >= dim_f or
            y < 0 or y >= dim_f or
            z < 0 or z >= dim_f)
        {
            return null;
        }

        // Convert 3D grid coordinates to 1D index
        const gd_f: f32 = dim_f;
        const idx_f: f32 = x + y * gd_f + z * gd_f * gd_f;
        const index: usize = @intFromFloat(idx_f);
        return index;
    }

    /// Insert an object into the grid
    pub fn insertObject(self: *SpatialGrid, object_index: usize, position: Vec4, radius: f32) !void {
        // Get cell index for object's position
        const cell_index = self.positionToIndex(position) orelse return;

        // Add object to cell
        try self.cells[cell_index].objects.append(object_index);

        // Handle objects that span multiple cells
        const cells_spanned = @ceil(radius * self.inv_cell_size);
        if (cells_spanned <= 1) return;

        // Compute bounds of cells that object overlaps
        const half_world = self.world_size * 0.5;
        const min_x = @max(0, @floor((position[0] - radius + half_world) * self.inv_cell_size));
        const min_y = @max(0, @floor((position[1] - radius + half_world) * self.inv_cell_size));
        const min_z = @max(0, @floor((position[2] - radius + half_world) * self.inv_cell_size));
        const max_x = @min(@as(f32, @floatFromInt(self.grid_dim)) - 1, @floor((position[0] + radius + half_world) * self.inv_cell_size));
        const max_y = @min(@as(f32, @floatFromInt(self.grid_dim)) - 1, @floor((position[1] + radius + half_world) * self.inv_cell_size));
        const max_z = @min(@as(f32, @floatFromInt(self.grid_dim)) - 1, @floor((position[2] + radius + half_world) * self.inv_cell_size));

        // Add object to all overlapping cells
        var x: f32 = min_x;
        while (x <= max_x) : (x += 1) {
            var y: f32 = min_y;
            while (y <= max_y) : (y += 1) {
                var z: f32 = min_z;
                while (z <= max_z) : (z += 1) {
                    const i: usize = @intCast(usize, x + y * @as(f32, self.grid_dim) + z * @as(f32, self.grid_dim) * @as(f32, self.grid_dim));
                    if (i != cell_index) {
                        try self.cells[i].objects.append(object_index);
                    }
                }
            }
        }
    }

    /// Find all potential collision pairs
    pub fn findCollisionPairs(self: *SpatialGrid) !void {
        self.collision_pairs.clearRetainingCapacity();

        // Check each cell for potential collisions
        for (self.cells) |cell| {
            // Skip cells with 0 or 1 objects
            if (cell.objects.items.len <= 1) continue;

            // Check all pairs of objects in this cell
            for (cell.objects.items, 0..) |obj_idx_a, i| {
                for (cell.objects.items[i + 1 ..]) |obj_idx_b| {
                    // Skip if already added as a collision pair
                    if (self.isPairAlreadyAdded(obj_idx_a, obj_idx_b)) continue;

                    // Add as potential collision pair
                    try self.collision_pairs.append([2]usize{ obj_idx_a, obj_idx_b });
                }
            }
        }
    }

    /// Check if a collision pair is already in the list
    fn isPairAlreadyAdded(self: SpatialGrid, a: usize, b: usize) bool {
        for (self.collision_pairs.items) |pair| {
            if ((pair[0] == a and pair[1] == b) or (pair[0] == b and pair[1] == a)) {
                return true;
            }
        }
        return false;
    }

    /// Process all collision pairs
    pub fn processCollisions(self: *SpatialGrid, objects: []PhysicalObject) void {
        for (self.collision_pairs.items) |pair| {
            const obj_a = &objects[pair[0]];
            const obj_b = &objects[pair[1]];

            // Skip if objects can't collide
            if ((obj_a.collision_group & obj_b.collision_mask) == 0 or
                (obj_b.collision_group & obj_a.collision_mask) == 0)
            {
                continue;
            }

            // Check for collision and resolve if found
            if (CollisionResolver.detectCollision(obj_a, obj_b)) |collision| {
                CollisionResolver.resolveCollision(collision);
            }
        }
    }
};

/// Axis-aligned bounding box for BVH implementation
pub const AABB = struct {
    min: Vec4,
    max: Vec4,

    pub fn fromSphere(center: Vec4, radius: f32) AABB {
        const r = Vector.splat(radius);
        return AABB{
            .min = center - r,
            .max = center + r,
        };
    }

    pub fn overlaps(self: AABB, other: AABB) bool {
        return self.min[0] <= other.max[0] and self.max[0] >= other.min[0] and
            self.min[1] <= other.max[1] and self.max[1] >= other.min[1] and
            self.min[2] <= other.max[2] and self.max[2] >= other.min[2];
    }

    pub fn contains(self: AABB, point: Vec4) bool {
        return point[0] >= self.min[0] and point[0] <= self.max[0] and
            point[1] >= self.min[1] and point[1] <= self.max[1] and
            point[2] >= self.min[2] and point[2] <= self.max[2];
    }

    pub fn merge(self: AABB, other: AABB) AABB {
        return AABB{
            .min = Vec4{
                @min(self.min[0], other.min[0]),
                @min(self.min[1], other.min[1]),
                @min(self.min[2], other.min[2]),
                0,
            },
            .max = Vec4{
                @max(self.max[0], other.max[0]),
                @max(self.max[1], other.max[1]),
                @max(self.max[2], other.max[2]),
                0,
            },
        };
    }

    pub fn surface_area(self: AABB) f32 {
        const extent = self.max - self.min;
        return 2.0 * (extent[0] * extent[1] + extent[1] * extent[2] + extent[2] * extent[0]);
    }
};
