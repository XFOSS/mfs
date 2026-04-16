//! Pathfinding Implementation
//! A* pathfinding algorithm with grid-based navigation and 3D waypoint support

const std = @import("std");

const math = @import("../math/mod.zig");
const Vec3 = math.Vec3;

/// Pathfinding request status
pub const PathRequestStatus = enum {
    pending,
    processing,
    completed,
    failed,
    cancelled,
};

/// Pathfinding request
pub const PathRequest = struct {
    id: u32,
    start: Vec3,
    end: Vec3,
    status: PathRequestStatus,
    path: std.array_list.Managed(Vec3),
    callback: ?*const fn (*PathRequest) void = null,

    pub fn init(allocator: std.mem.Allocator, id: u32, start: Vec3, end: Vec3) PathRequest {
        return PathRequest{
            .id = id,
            .start = start,
            .end = end,
            .status = .pending,
            .path = std.array_list.Managed(Vec3).init(allocator),
            .callback = null,
        };
    }

    pub fn deinit(self: *PathRequest) void {
        self.path.deinit();
    }
};

/// Grid node for A* algorithm
const GridNode = struct {
    x: i32,
    y: i32,
    z: i32,
    g_cost: f32, // Cost from start
    h_cost: f32, // Heuristic cost to end
    f_cost: f32, // Total cost (g + h)
    parent: ?*GridNode,
    walkable: bool,
    visited: bool,

    pub fn init(x: i32, y: i32, z: i32, walkable: bool) GridNode {
        return GridNode{
            .x = x,
            .y = y,
            .z = z,
            .g_cost = 0.0,
            .h_cost = 0.0,
            .f_cost = 0.0,
            .parent = null,
            .walkable = walkable,
            .visited = false,
        };
    }

    pub fn reset(self: *GridNode) void {
        self.g_cost = 0.0;
        self.h_cost = 0.0;
        self.f_cost = 0.0;
        self.parent = null;
        self.visited = false;
    }

    pub fn equals(self: *const GridNode, other: *const GridNode) bool {
        return self.x == other.x and self.y == other.y and self.z == other.z;
    }
};

/// Pathfinding grid for spatial navigation
pub const PathfindingGrid = struct {
    allocator: std.mem.Allocator,
    cell_size: f32,
    width: i32,
    height: i32,
    depth: i32,
    nodes: []GridNode,
    origin: Vec3,

    pub fn init(allocator: std.mem.Allocator, cell_size: f32, width: i32, height: i32, depth: i32, origin: Vec3) !PathfindingGrid {
        const total_nodes = @as(usize, @intCast(width * height * depth));
        const nodes = try allocator.alloc(GridNode, total_nodes);

        var index: usize = 0;
        var z: i32 = 0;
        while (z < depth) : (z += 1) {
            var y: i32 = 0;
            while (y < height) : (y += 1) {
                var x: i32 = 0;
                while (x < width) : (x += 1) {
                    nodes[index] = GridNode.init(x, y, z, true); // All nodes walkable by default
                    index += 1;
                }
            }
        }

        return PathfindingGrid{
            .allocator = allocator,
            .cell_size = cell_size,
            .width = width,
            .height = height,
            .depth = depth,
            .nodes = nodes,
            .origin = origin,
        };
    }

    pub fn deinit(self: *PathfindingGrid) void {
        self.allocator.free(self.nodes);
    }

    pub fn worldToGrid(self: *const PathfindingGrid, world_pos: Vec3) struct { x: i32, y: i32, z: i32 } {
        const local = world_pos.sub(self.origin);
        return .{
            .x = @intFromFloat(@floor(local.x / self.cell_size)),
            .y = @intFromFloat(@floor(local.y / self.cell_size)),
            .z = @intFromFloat(@floor(local.z / self.cell_size)),
        };
    }

    pub fn gridToWorld(self: *const PathfindingGrid, grid_x: i32, grid_y: i32, grid_z: i32) Vec3 {
        return Vec3{
            .x = self.origin.x + (@as(f32, @floatFromInt(grid_x)) * self.cell_size),
            .y = self.origin.y + (@as(f32, @floatFromInt(grid_y)) * self.cell_size),
            .z = self.origin.z + (@as(f32, @floatFromInt(grid_z)) * self.cell_size),
        };
    }

    pub fn getNode(self: *PathfindingGrid, x: i32, y: i32, z: i32) ?*GridNode {
        if (x < 0 or x >= self.width or y < 0 or y >= self.height or z < 0 or z >= self.depth) {
            return null;
        }
        const index = @as(usize, @intCast(z * self.width * self.height + y * self.width + x));
        return &self.nodes[index];
    }

    pub fn setWalkable(self: *PathfindingGrid, x: i32, y: i32, z: i32, walkable: bool) void {
        if (self.getNode(x, y, z)) |node| {
            node.walkable = walkable;
        }
    }

    pub fn getNeighbors(self: *PathfindingGrid, node: *GridNode) !std.array_list.Managed(*GridNode) {
        var neighbors = std.array_list.Managed(*GridNode).init(self.allocator);

        // 26-directional neighbors (including diagonals)
        const offsets = [_]struct { x: i32, y: i32, z: i32 }{
            // Face neighbors (6)
            .{ .x = -1, .y = 0, .z = 0 },
            .{ .x = 1, .y = 0, .z = 0 },
            .{ .x = 0, .y = -1, .z = 0 },
            .{ .x = 0, .y = 1, .z = 0 },
            .{ .x = 0, .y = 0, .z = -1 },
            .{ .x = 0, .y = 0, .z = 1 },
            // Edge neighbors (12)
            .{ .x = -1, .y = -1, .z = 0 },
            .{ .x = 1, .y = -1, .z = 0 },
            .{ .x = -1, .y = 1, .z = 0 },
            .{ .x = 1, .y = 1, .z = 0 },
            .{ .x = -1, .y = 0, .z = -1 },
            .{ .x = 1, .y = 0, .z = -1 },
            .{ .x = -1, .y = 0, .z = 1 },
            .{ .x = 1, .y = 0, .z = 1 },
            .{ .x = 0, .y = -1, .z = -1 },
            .{ .x = 0, .y = 1, .z = -1 },
            .{ .x = 0, .y = -1, .z = 1 },
            .{ .x = 0, .y = 1, .z = 1 },
            // Corner neighbors (8)
            .{ .x = -1, .y = -1, .z = -1 },
            .{ .x = 1, .y = -1, .z = -1 },
            .{ .x = -1, .y = 1, .z = -1 },
            .{ .x = 1, .y = 1, .z = -1 },
            .{ .x = -1, .y = -1, .z = 1 },
            .{ .x = 1, .y = -1, .z = 1 },
            .{ .x = -1, .y = 1, .z = 1 },
            .{ .x = 1, .y = 1, .z = 1 },
        };

        for (offsets) |offset| {
            if (self.getNode(node.x + offset.x, node.y + offset.y, node.z + offset.z)) |neighbor| {
                if (neighbor.walkable) {
                    try neighbors.append(neighbor);
                }
            }
        }

        return neighbors;
    }
};

/// Pathfinding System - manages pathfinding requests
pub const PathfindingSystem = struct {
    allocator: std.mem.Allocator,
    requests: std.array_list.Managed(PathRequest),
    grid: ?*PathfindingGrid = null,
    next_request_id: u32 = 1,
    max_requests: u32 = 100,

    pub fn init(allocator: std.mem.Allocator) !PathfindingSystem {
        return PathfindingSystem{
            .allocator = allocator,
            .requests = std.array_list.Managed(PathRequest).init(allocator),
        };
    }

    pub fn deinit(self: *PathfindingSystem) void {
        for (self.requests.items) |*request| {
            request.deinit();
        }
        self.requests.deinit();
        if (self.grid) |g| {
            g.deinit();
            self.allocator.destroy(g);
        }
    }

    pub fn update(self: *PathfindingSystem, delta_time: f32) !void {
        _ = delta_time;

        // Process pending requests
        var i: usize = 0;
        while (i < self.requests.items.len) {
            const request = &self.requests.items[i];
            if (request.status == .pending) {
                request.status = .processing;
                try self.processPathRequest(request);
            }

            // Remove completed/failed/cancelled requests
            if (request.status == .completed or request.status == .failed or request.status == .cancelled) {
                if (request.callback) |cb| {
                    cb(request);
                }
                request.deinit();
                _ = self.requests.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }

    pub fn getActiveRequests(self: *const PathfindingSystem) u32 {
        var count: u32 = 0;
        for (self.requests.items) |request| {
            if (request.status == .pending or request.status == .processing) {
                count += 1;
            }
        }
        return count;
    }

    pub fn setGrid(self: *PathfindingSystem, grid: *PathfindingGrid) void {
        if (self.grid) |old_grid| {
            old_grid.deinit();
            self.allocator.destroy(old_grid);
        }
        self.grid = grid;
    }

    pub fn requestPath(self: *PathfindingSystem, start: Vec3, end: Vec3) !u32 {
        if (self.requests.items.len >= self.max_requests) {
            return error.TooManyRequests;
        }

        const id = self.next_request_id;
        self.next_request_id += 1;

        const request = PathRequest.init(self.allocator, id, start, end);
        try self.requests.append(request);

        return id;
    }

    pub fn getPath(self: *PathfindingSystem, request_id: u32) ?[]const Vec3 {
        for (self.requests.items) |*request| {
            if (request.id == request_id and request.status == .completed) {
                return request.path.items;
            }
        }
        return null;
    }

    pub fn cancelRequest(self: *PathfindingSystem, request_id: u32) void {
        for (self.requests.items) |*request| {
            if (request.id == request_id) {
                request.status = .cancelled;
                break;
            }
        }
    }

    fn processPathRequest(self: *PathfindingSystem, request: *PathRequest) !void {
        if (self.grid == null) {
            // No grid available, use simple direct path
            try request.path.append(request.start);
            try request.path.append(request.end);
            request.status = .completed;
            return;
        }

        const grid = self.grid.?;
        const start_grid = grid.worldToGrid(request.start);
        const end_grid = grid.worldToGrid(request.end);

        const start_node = grid.getNode(start_grid.x, start_grid.y, start_grid.z);
        const end_node = grid.getNode(end_grid.x, end_grid.y, end_grid.z);

        if (start_node == null or end_node == null) {
            request.status = .failed;
            return;
        }

        if (!start_node.?.walkable or !end_node.?.walkable) {
            request.status = .failed;
            return;
        }

        // Reset all nodes
        for (grid.nodes) |*node| {
            node.reset();
        }

        // A* pathfinding
        const path = try self.findPathAStar(grid, start_node.?, end_node.?);
        if (path) |p| {
            // Convert grid nodes to world positions
            for (p) |node| {
                const world_pos = grid.gridToWorld(node.x, node.y, node.z);
                try request.path.append(world_pos);
            }
            request.status = .completed;
        } else {
            request.status = .failed;
        }
    }

    fn findPathAStar(self: *PathfindingSystem, grid: *PathfindingGrid, start: *GridNode, end: *GridNode) !?[]*GridNode {
        _ = self;

        var open_set = std.PriorityQueue(*GridNode, void, compareNodes).init(self.allocator, {});
        defer open_set.deinit();

        var closed_set = std.ArrayList(*GridNode).init(self.allocator);
        defer closed_set.deinit();

        start.g_cost = 0.0;
        start.h_cost = heuristic(start, end);
        start.f_cost = start.g_cost + start.h_cost;

        try open_set.add(start);

        while (open_set.removeOrNull()) |current| {
            if (current.equals(end)) {
                // Reconstruct path
                var path = std.ArrayList(*GridNode).init(self.allocator);
                var node: ?*GridNode = current;
                while (node) |n| {
                    try path.append(n);
                    node = n.parent;
                }

                // Reverse path
                var reversed = try self.allocator.alloc(*GridNode, path.items.len);
                for (path.items, 0..) |n, i| {
                    reversed[path.items.len - 1 - i] = n;
                }

                return reversed;
            }

            try closed_set.append(current);
            current.visited = true;

            const neighbors = try grid.getNeighbors(current);
            defer neighbors.deinit();

            for (neighbors.items) |neighbor| {
                if (neighbor.visited) continue;

                const tentative_g = current.g_cost + distance(current, neighbor);

                var in_open = false;
                for (open_set.items) |open_node| {
                    if (neighbor.equals(open_node)) {
                        in_open = true;
                        break;
                    }
                }

                if (!in_open) {
                    neighbor.g_cost = tentative_g;
                    neighbor.h_cost = heuristic(neighbor, end);
                    neighbor.f_cost = neighbor.g_cost + neighbor.h_cost;
                    neighbor.parent = current;
                    try open_set.add(neighbor);
                } else if (tentative_g < neighbor.g_cost) {
                    neighbor.g_cost = tentative_g;
                    neighbor.f_cost = neighbor.g_cost + neighbor.h_cost;
                    neighbor.parent = current;
                }
            }
        }

        return null; // No path found
    }

    fn compareNodes(context: void, a: *GridNode, b: *GridNode) bool {
        _ = context;
        return a.f_cost > b.f_cost; // Lower f_cost has higher priority
    }
};

/// Pathfinder - simple interface for finding paths
pub const Pathfinder = struct {
    allocator: std.mem.Allocator,
    grid: ?*PathfindingGrid = null,

    pub fn init(allocator: std.mem.Allocator) !Pathfinder {
        return Pathfinder{
            .allocator = allocator,
            .grid = null,
        };
    }

    pub fn deinit(self: *Pathfinder) void {
        if (self.grid) |g| {
            g.deinit();
            self.allocator.destroy(g);
        }
    }

    pub fn setGrid(self: *Pathfinder, grid: *PathfindingGrid) void {
        self.grid = grid;
    }

    pub fn findPath(self: *Pathfinder, start: Vec3, end: Vec3) !?[]Vec3 {
        if (self.grid == null) {
            // No grid, return simple direct path
            var path = try self.allocator.alloc(Vec3, 2);
            path[0] = start;
            path[1] = end;
            return path;
        }

        const grid = self.grid.?;
        const start_grid = grid.worldToGrid(start);
        const end_grid = grid.worldToGrid(end);

        const start_node = grid.getNode(start_grid.x, start_grid.y, start_grid.z);
        const end_node = grid.getNode(end_grid.x, end_grid.y, end_grid.z);

        if (start_node == null or end_node == null) {
            return null;
        }

        if (!start_node.?.walkable or !end_node.?.walkable) {
            return null;
        }

        // Reset all nodes
        for (grid.nodes) |*node| {
            node.reset();
        }

        // Simple A* implementation
        const path_nodes = try findPathSimple(grid, start_node.?, end_node.?, self.allocator);
        if (path_nodes) |nodes| {
            defer self.allocator.free(nodes);

            // Convert to world positions
            var world_path = try std.ArrayList(Vec3).initCapacity(self.allocator, nodes.len);
            for (nodes) |node| {
                const world_pos = grid.gridToWorld(node.x, node.y, node.z);
                try world_path.append(world_pos);
            }

            const result = try self.allocator.alloc(Vec3, world_path.items.len);
            @memcpy(result, world_path.items);
            return result;
        }

        return null;
    }
};

/// Simple A* pathfinding helper
fn findPathSimple(grid: *PathfindingGrid, start: *GridNode, end: *GridNode, allocator: std.mem.Allocator) !?[]*GridNode {
    var open_set = std.PriorityQueue(*GridNode, void, compareNodes).init(allocator, {});
    defer open_set.deinit();

    var closed_set = std.ArrayList(*GridNode).init(allocator);
    defer closed_set.deinit();

    start.g_cost = 0.0;
    start.h_cost = heuristic(start, end);
    start.f_cost = start.g_cost + start.h_cost;

    try open_set.add(start);

    while (open_set.removeOrNull()) |current| {
        if (current.equals(end)) {
            // Reconstruct path
            var path = std.ArrayList(*GridNode).init(allocator);
            var node: ?*GridNode = current;
            while (node) |n| {
                try path.append(n);
                node = n.parent;
            }

            // Reverse path
            var reversed = try allocator.alloc(*GridNode, path.items.len);
            for (path.items, 0..) |n, i| {
                reversed[path.items.len - 1 - i] = n;
            }

            return reversed;
        }

        try closed_set.append(current);
        current.visited = true;

        const neighbors = try grid.getNeighbors(current);
        defer neighbors.deinit();

        for (neighbors.items) |neighbor| {
            if (neighbor.visited) continue;

            const tentative_g = current.g_cost + distance(current, neighbor);

            var in_open = false;
            for (open_set.items) |open_node| {
                if (neighbor.equals(open_node)) {
                    in_open = true;
                    break;
                }
            }

            if (!in_open) {
                neighbor.g_cost = tentative_g;
                neighbor.h_cost = heuristic(neighbor, end);
                neighbor.f_cost = neighbor.g_cost + neighbor.h_cost;
                neighbor.parent = current;
                try open_set.add(neighbor);
            } else if (tentative_g < neighbor.g_cost) {
                neighbor.g_cost = tentative_g;
                neighbor.f_cost = neighbor.g_cost + neighbor.h_cost;
                neighbor.parent = current;
            }
        }
    }

    return null;
}

/// Heuristic function (Euclidean distance)
fn heuristic(a: *GridNode, b: *GridNode) f32 {
    const dx = @as(f32, @floatFromInt(a.x - b.x));
    const dy = @as(f32, @floatFromInt(a.y - b.y));
    const dz = @as(f32, @floatFromInt(a.z - b.z));
    return @sqrt(dx * dx + dy * dy + dz * dz);
}

/// Distance between two nodes
fn distance(a: *GridNode, b: *GridNode) f32 {
    const dx = @as(f32, @floatFromInt(a.x - b.x));
    const dy = @as(f32, @floatFromInt(a.y - b.y));
    const dz = @as(f32, @floatFromInt(a.z - b.z));
    return @sqrt(dx * dx + dy * dy + dz * dz);
}

/// Compare nodes for priority queue
fn compareNodes(context: void, a: *GridNode, b: *GridNode) bool {
    _ = context;
    return a.f_cost > b.f_cost; // Lower f_cost has higher priority
}
