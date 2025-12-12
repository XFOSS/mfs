//! Pathfinding Implementation
//! A* pathfinding algorithm with grid-based and navmesh support

const std = @import("std");
const math = @import("../math/mod.zig");
const Vec3 = math.Vec3;

/// Pathfinding request for async pathfinding
pub const PathRequest = struct {
    id: u32,
    start: Vec3,
    end: Vec3,
    callback: ?*const fn ([]Vec3) void = null,
    status: PathStatus = .pending,
    path: std.array_list.Managed(Vec3),

    pub fn init(allocator: std.mem.Allocator, id: u32, start: Vec3, end: Vec3) PathRequest {
        return PathRequest{
            .id = id,
            .start = start,
            .end = end,
            .path = std.array_list.Managed(Vec3).init(allocator),
        };
    }

    pub fn deinit(self: *PathRequest) void {
        self.path.deinit();
    }
};

pub const PathStatus = enum {
    pending,
    processing,
    completed,
    failed,
};

/// Pathfinding system that manages multiple pathfinding requests
pub const PathfindingSystem = struct {
    allocator: std.mem.Allocator,
    active_requests: std.array_list.Managed(PathRequest),
    next_request_id: u32,
    grid: ?*NavigationGrid = null,

    pub fn init(allocator: std.mem.Allocator) !PathfindingSystem {
        return PathfindingSystem{
            .allocator = allocator,
            .active_requests = std.array_list.Managed(PathRequest).init(allocator),
            .next_request_id = 1,
            .grid = null,
        };
    }

    pub fn deinit(self: *PathfindingSystem) void {
        for (self.active_requests.items) |*request| {
            request.deinit();
        }
        self.active_requests.deinit();
        if (self.grid) |g| {
            g.deinit();
            self.allocator.destroy(g);
        }
    }

    pub fn update(self: *PathfindingSystem, delta_time: f32) !void {
        _ = delta_time;
        // Process pending requests
        for (self.active_requests.items) |*request| {
            if (request.status == .pending) {
                request.status = .processing;
                if (self.grid) |grid| {
                    if (try self.computePath(grid, request.start, request.end)) |path| {
                        request.path.clearRetainingCapacity();
                        try request.path.appendSlice(path);
                        request.status = .completed;
                        self.allocator.free(path);
                    } else {
                        request.status = .failed;
                    }
                } else {
                    // Simple straight-line path if no grid
                    request.path.clearRetainingCapacity();
                    try request.path.append(request.start);
                    try request.path.append(request.end);
                    request.status = .completed;
                }
            }
        }

        // Remove completed/failed requests after a delay
        var i: usize = 0;
        while (i < self.active_requests.items.len) {
            if (self.active_requests.items[i].status == .completed or self.active_requests.items[i].status == .failed) {
                var request = self.active_requests.swapRemove(i);
                request.deinit();
            } else {
                i += 1;
            }
        }
    }

    pub fn requestPath(self: *PathfindingSystem, start: Vec3, end: Vec3) !u32 {
        const request_id = self.next_request_id;
        self.next_request_id += 1;
        const request = PathRequest.init(self.allocator, request_id, start, end);
        try self.active_requests.append(request);
        return request_id;
    }

    pub fn getPath(self: *PathfindingSystem, request_id: u32) ?[]const Vec3 {
        for (self.active_requests.items) |*request| {
            if (request.id == request_id and request.status == .completed) {
                return request.path.items;
            }
        }
        return null;
    }

    pub fn setNavigationGrid(self: *PathfindingSystem, grid: *NavigationGrid) void {
        if (self.grid) |old_grid| {
            old_grid.deinit();
            self.allocator.destroy(old_grid);
        }
        self.grid = grid;
    }

    fn computePath(self: *PathfindingSystem, grid: *NavigationGrid, start: Vec3, end: Vec3) !?[]Vec3 {
        _ = self;
        return try grid.findPath(start, end);
    }

    pub fn getActiveRequests(self: *PathfindingSystem) u32 {
        var count: u32 = 0;
        for (self.active_requests.items) |*request| {
            if (request.status == .pending or request.status == .processing) {
                count += 1;
            }
        }
        return count;
    }
};

/// Individual pathfinder for synchronous pathfinding
pub const Pathfinder = struct {
    allocator: std.mem.Allocator,
    grid: ?*NavigationGrid = null,

    pub fn init(allocator: std.mem.Allocator) !Pathfinder {
        return Pathfinder{ .allocator = allocator };
    }

    pub fn deinit(self: *Pathfinder) void {
        if (self.grid) |g| {
            g.deinit();
            self.allocator.destroy(g);
        }
    }

    pub fn setNavigationGrid(self: *Pathfinder, grid: *NavigationGrid) void {
        if (self.grid) |old_grid| {
            old_grid.deinit();
            self.allocator.destroy(old_grid);
        }
        self.grid = grid;
    }

    pub fn findPath(self: *Pathfinder, start: Vec3, end: Vec3) !?[]Vec3 {
        if (self.grid) |grid| {
            return try grid.findPath(start, end);
        } else {
            // Simple straight-line path if no grid
            const path = try self.allocator.alloc(Vec3, 2);
            path[0] = start;
            path[1] = end;
            return path;
        }
    }
};

/// Navigation grid for A* pathfinding
pub const NavigationGrid = struct {
    allocator: std.mem.Allocator,
    width: u32,
    height: u32,
    cell_size: f32,
    cells: []GridCell,
    origin: Vec3,

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32, cell_size: f32, origin: Vec3) !*NavigationGrid {
        const grid = try allocator.create(NavigationGrid);
        const total_cells = width * height;
        grid.* = NavigationGrid{
            .allocator = allocator,
            .width = width,
            .height = height,
            .cell_size = cell_size,
            .cells = try allocator.alloc(GridCell, total_cells),
            .origin = origin,
        };

        // Initialize all cells as walkable
        for (grid.cells) |*cell| {
            cell.* = GridCell{ .walkable = true, .cost = 1.0 };
        }

        return grid;
    }

    pub fn deinit(self: *NavigationGrid) void {
        self.allocator.free(self.cells);
    }

    pub fn setCellWalkable(self: *NavigationGrid, x: u32, y: u32, walkable: bool) void {
        if (x < self.width and y < self.height) {
            const index = y * self.width + x;
            self.cells[index].walkable = walkable;
        }
    }

    pub fn setCellCost(self: *NavigationGrid, x: u32, y: u32, cost: f32) void {
        if (x < self.width and y < self.height) {
            const index = y * self.width + x;
            self.cells[index].cost = cost;
        }
    }

    pub fn worldToGrid(self: *NavigationGrid, world_pos: Vec3) struct { x: u32, y: u32 } {
        const local = world_pos.subtract(self.origin);
        const x = @as(u32, @intFromFloat(@floor(local.x / self.cell_size)));
        const y = @as(u32, @intFromFloat(@floor(local.z / self.cell_size))); // Use Z for Y in grid
        return .{ .x = @min(x, self.width - 1), .y = @min(y, self.height - 1) };
    }

    pub fn gridToWorld(self: *NavigationGrid, x: u32, y: u32) Vec3 {
        const world_x = @as(f32, @floatFromInt(x)) * self.cell_size + self.cell_size * 0.5;
        const world_z = @as(f32, @floatFromInt(y)) * self.cell_size + self.cell_size * 0.5;
        return Vec3.new(world_x, self.origin.y, world_z).add(self.origin);
    }

    pub fn findPath(self: *NavigationGrid, start: Vec3, end: Vec3) !?[]Vec3 {
        const start_grid = self.worldToGrid(start);
        const end_grid = self.worldToGrid(end);

        if (start_grid.x == end_grid.x and start_grid.y == end_grid.y) {
            // Same cell, return direct path
            const path = try self.allocator.alloc(Vec3, 2);
            path[0] = start;
            path[1] = end;
            return path;
        }

        // A* pathfinding
        return try self.astar(start_grid, end_grid, start, end);
    }

    fn astar(self: *NavigationGrid, start: struct { x: u32, y: u32 }, end: struct { x: u32, y: u32 }, start_world: Vec3, end_world: Vec3) !?[]Vec3 {
        var open_set = std.PriorityQueue(AStarNode, void, compareAStarNode).init(self.allocator, {});
        defer open_set.deinit();

        var came_from = std.HashMap(GridPos, GridPos, GridPosContext, std.hash_map.default_max_load_percentage).init(self.allocator);
        defer came_from.deinit();

        var g_score = std.HashMap(GridPos, f32, GridPosContext, std.hash_map.default_max_load_percentage).init(self.allocator);
        defer g_score.deinit();

        const start_pos = GridPos{ .x = start.x, .y = start.y };
        const end_pos = GridPos{ .x = end.x, .y = end.y };

        try g_score.put(start_pos, 0.0);
        try open_set.add(AStarNode{ .pos = start_pos, .f_score = self.heuristic(start, end) });

        while (open_set.removeOrNull()) |current| {
            if (current.pos.x == end_pos.x and current.pos.y == end_pos.y) {
                // Reconstruct path
                return try self.reconstructPath(came_from, current.pos, start_world, end_world);
            }

            // Check neighbors (8-directional)
            const neighbors = [_]struct { dx: i32, dy: i32 }{
                .{ .dx = -1, .dy = -1 }, .{ .dx = 0, .dy = -1 }, .{ .dx = 1, .dy = -1 },
                .{ .dx = -1, .dy = 0 }, .{ .dx = 1, .dy = 0 },
                .{ .dx = -1, .dy = 1 }, .{ .dx = 0, .dy = 1 }, .{ .dx = 1, .dy = 1 },
            };

            for (neighbors) |neighbor| {
                const nx = @as(i32, @intCast(current.pos.x)) + neighbor.dx;
                const ny = @as(i32, @intCast(current.pos.y)) + neighbor.dy;

                if (nx < 0 or ny < 0 or nx >= self.width or ny >= self.height) continue;

                const neighbor_pos = GridPos{ .x = @intCast(nx), .y = @intCast(ny) };
                const cell_index = neighbor_pos.y * self.width + neighbor_pos.x;

                if (!self.cells[cell_index].walkable) continue;

                const tentative_g = (g_score.get(current.pos) orelse std.math.inf(f32)) + self.cells[cell_index].cost;
                const neighbor_g = g_score.get(neighbor_pos) orelse std.math.inf(f32);

                if (tentative_g < neighbor_g) {
                    try came_from.put(neighbor_pos, current.pos);
                    try g_score.put(neighbor_pos, tentative_g);
                    const f_score = tentative_g + self.heuristic(.{ .x = neighbor_pos.x, .y = neighbor_pos.y }, end);
                    try open_set.add(AStarNode{ .pos = neighbor_pos, .f_score = f_score });
                }
            }
        }

        return null; // No path found
    }

    fn reconstructPath(self: *NavigationGrid, came_from: std.HashMap(GridPos, GridPos, GridPosContext, std.hash_map.default_max_load_percentage), current: GridPos, start_world: Vec3, end_world: Vec3) ![]Vec3 {
        var path = std.array_list.Managed(Vec3).init(self.allocator);
        try path.append(end_world);

        var current_pos = current;
        while (came_from.get(current_pos)) |prev| {
            const world = self.gridToWorld(current_pos.x, current_pos.y);
            try path.insert(0, world);
            current_pos = prev;
        }

        try path.insert(0, start_world);
        return path.toOwnedSlice();
    }

    fn heuristic(self: *NavigationGrid, a: struct { x: u32, y: u32 }, b: struct { x: u32, y: u32 }) f32 {
        _ = self;
        const dx = @as(f32, @floatFromInt(if (a.x > b.x) a.x - b.x else b.x - a.x));
        const dy = @as(f32, @floatFromInt(if (a.y > b.y) a.y - b.y else b.y - a.y));
        return dx + dy; // Manhattan distance
    }
};

const GridCell = struct {
    walkable: bool,
    cost: f32,
};

const GridPos = struct {
    x: u32,
    y: u32,
};

const GridPosContext = struct {
    pub fn hash(self: @This(), pos: GridPos) u64 {
        _ = self;
        return (@as(u64, pos.x) << 32) | pos.y;
    }
    pub fn eql(self: @This(), a: GridPos, b: GridPos) bool {
        _ = self;
        return a.x == b.x and a.y == b.y;
    }
};

const AStarNode = struct {
    pos: GridPos,
    f_score: f32,
};

fn compareAStarNode(context: void, a: AStarNode, b: AStarNode) std.math.Order {
    _ = context;
    return std.math.order(b.f_score, a.f_score); // Lower f_score is better
};
