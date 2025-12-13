//! Behavior Trees Implementation
//! Complete behavior tree system with composite and decorator nodes

const std = @import("std");

const math = @import("../math/mod.zig");
const Vec3 = math.Vec3;

pub const BehaviorManager = struct {
    allocator: std.mem.Allocator,
    trees: std.array_list.Managed(*BehaviorTree),

    pub fn init(allocator: std.mem.Allocator) !BehaviorManager {
        return BehaviorManager{
            .allocator = allocator,
            .trees = std.array_list.Managed(*BehaviorTree).init(allocator),
        };
    }

    pub fn deinit(self: *BehaviorManager) void {
        for (self.trees.items) |tree| {
            tree.deinit();
            self.allocator.destroy(tree);
        }
        self.trees.deinit();
    }

    pub fn update(_: *BehaviorManager, delta_time: f32) !void {
        _ = delta_time;
        // Trees are updated individually by their owners
    }

    pub fn addTree(self: *BehaviorManager, tree: *BehaviorTree) !void {
        try self.trees.append(tree);
    }

    pub fn removeTree(self: *BehaviorManager, tree: *BehaviorTree) void {
        for (self.trees.items, 0..) |t, i| {
            if (t == tree) {
                _ = self.trees.swapRemove(i);
                break;
            }
        }
    }

    pub fn getTreeCount(self: *BehaviorManager) u32 {
        return @intCast(self.trees.items.len);
    }
};

pub const BehaviorTree = struct {
    allocator: std.mem.Allocator,
    root: ?*BehaviorNode,
    config: TreeConfig,
    blackboard: Blackboard,

    pub fn init(allocator: std.mem.Allocator, config: TreeConfig) !BehaviorTree {
        return BehaviorTree{
            .allocator = allocator,
            .root = null,
            .config = config,
            .blackboard = Blackboard.init(allocator),
        };
    }

    pub fn deinit(self: *BehaviorTree) void {
        if (self.root) |r| {
            r.deinit();
            self.allocator.destroy(r);
        }
        self.blackboard.deinit();
    }

    pub fn setRoot(self: *BehaviorTree, node: *BehaviorNode) void {
        if (self.root) |old_root| {
            old_root.deinit();
            self.allocator.destroy(old_root);
        }
        self.root = node;
    }

    pub fn tick(self: *BehaviorTree, delta_time: f32) !NodeStatus {
        _ = delta_time;
        if (self.root) |root| {
            return try root.execute(&self.blackboard);
        }
        return .failure;
    }

    pub fn getBlackboard(self: *BehaviorTree) *Blackboard {
        return &self.blackboard;
    }
};

pub const TreeConfig = struct {
    max_depth: u32 = 10,
    update_frequency: f32 = 0.1, // Update every 100ms
};

pub const NodeStatus = enum {
    success,
    failure,
    running,
};

/// Base behavior node interface
pub const BehaviorNode = struct {
    allocator: std.mem.Allocator,
    node_type: NodeType,
    name: []const u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, node_type: NodeType, name: []const u8) !*Self {
        const node = try allocator.create(Self);
        node.* = Self{
            .allocator = allocator,
            .node_type = node_type,
            .name = try allocator.dupe(u8, name),
        };
        return node;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.name);
        switch (self.node_type) {
            .composite => |*comp| comp.deinit(),
            .decorator => |*dec| dec.deinit(),
            .leaf => |*leaf| leaf.deinit(),
        }
    }

    pub fn execute(self: *Self, blackboard: *Blackboard) !NodeStatus {
        return switch (self.node_type) {
            .composite => |*comp| try comp.execute(blackboard),
            .decorator => |*dec| try dec.execute(blackboard),
            .leaf => |*leaf| try leaf.execute(blackboard),
        };
    }
};

pub const NodeType = union(enum) {
    composite: CompositeNode,
    decorator: DecoratorNode,
    leaf: LeafNode,
};

/// Composite nodes (Sequence, Selector, Parallel)
pub const CompositeNode = struct {
    children: std.array_list.Managed(*BehaviorNode),
    composite_type: CompositeType,
    current_child: usize,

    pub fn init(allocator: std.mem.Allocator, composite_type: CompositeType) CompositeNode {
        return CompositeNode{
            .children = std.array_list.Managed(*BehaviorNode).init(allocator),
            .composite_type = composite_type,
            .current_child = 0,
        };
    }

    pub fn deinit(self: *CompositeNode) void {
        for (self.children.items) |child| {
            child.deinit();
            child.allocator.destroy(child);
        }
        self.children.deinit();
    }

    pub fn addChild(self: *CompositeNode, child: *BehaviorNode) !void {
        try self.children.append(child);
    }

    pub fn execute(self: *CompositeNode, blackboard: *Blackboard) !NodeStatus {
        return switch (self.composite_type) {
            .sequence => try self.executeSequence(blackboard),
            .selector => try self.executeSelector(blackboard),
            .parallel => try self.executeParallel(blackboard),
        };
    }

    fn executeSequence(self: *CompositeNode, blackboard: *Blackboard) !NodeStatus {
        // Sequence: All children must succeed
        for (self.children.items) |child| {
            const status = try child.execute(blackboard);
            if (status == .failure) {
                self.current_child = 0;
                return .failure;
            }
            if (status == .running) {
                return .running;
            }
        }
        self.current_child = 0;
        return .success;
    }

    fn executeSelector(self: *CompositeNode, blackboard: *Blackboard) !NodeStatus {
        // Selector: First child to succeed wins
        for (self.children.items) |child| {
            const status = try child.execute(blackboard);
            if (status == .success) {
                self.current_child = 0;
                return .success;
            }
            if (status == .running) {
                return .running;
            }
        }
        self.current_child = 0;
        return .failure;
    }

    fn executeParallel(self: *CompositeNode, blackboard: *Blackboard) !NodeStatus {
        // Parallel: Run all children, succeed if all succeed
        var all_success = true;
        var any_running = false;

        for (self.children.items) |child| {
            const status = try child.execute(blackboard);
            if (status == .failure) {
                all_success = false;
            }
            if (status == .running) {
                any_running = true;
            }
        }

        if (any_running) return .running;
        return if (all_success) .success else .failure;
    }
};

pub const CompositeType = enum {
    sequence,
    selector,
    parallel,
};

/// Decorator nodes (Inverter, Repeater, etc.)
pub const DecoratorNode = struct {
    child: ?*BehaviorNode,
    decorator_type: DecoratorType,
    repeat_count: u32,
    current_count: u32,

    pub fn init(allocator: std.mem.Allocator, decorator_type: DecoratorType) DecoratorNode {
        _ = allocator;
        return DecoratorNode{
            .child = null,
            .decorator_type = decorator_type,
            .repeat_count = 0,
            .current_count = 0,
        };
    }

    pub fn deinit(self: *DecoratorNode) void {
        if (self.child) |c| {
            c.deinit();
            c.allocator.destroy(c);
        }
    }

    pub fn setChild(self: *DecoratorNode, child: *BehaviorNode) void {
        if (self.child) |old_child| {
            old_child.deinit();
            child.allocator.destroy(old_child);
        }
        self.child = child;
    }

    pub fn execute(self: *DecoratorNode, blackboard: *Blackboard) !NodeStatus {
        if (self.child == null) return .failure;

        return switch (self.decorator_type) {
            .inverter => try self.executeInverter(blackboard),
            .repeater => try self.executeRepeater(blackboard),
            .until_fail => try self.executeUntilFail(blackboard),
            .until_success => try self.executeUntilSuccess(blackboard),
        };
    }

    fn executeInverter(self: *DecoratorNode, blackboard: *Blackboard) !NodeStatus {
        const status = try self.child.?.execute(blackboard);
        return switch (status) {
            .success => .failure,
            .failure => .success,
            .running => .running,
        };
    }

    fn executeRepeater(self: *DecoratorNode, blackboard: *Blackboard) !NodeStatus {
        while (self.current_count < self.repeat_count) {
            const status = try self.child.?.execute(blackboard);
            if (status == .running) return .running;
            if (status == .failure) {
                self.current_count = 0;
                return .failure;
            }
            self.current_count += 1;
        }
        self.current_count = 0;
        return .success;
    }

    fn executeUntilFail(self: *DecoratorNode, blackboard: *Blackboard) !NodeStatus {
        while (true) {
            const status = try self.child.?.execute(blackboard);
            if (status == .running) return .running;
            if (status == .failure) return .success;
        }
    }

    fn executeUntilSuccess(self: *DecoratorNode, blackboard: *Blackboard) !NodeStatus {
        while (true) {
            const status = try self.child.?.execute(blackboard);
            if (status == .running) return .running;
            if (status == .success) return .success;
        }
    }
};

pub const DecoratorType = enum {
    inverter,
    repeater,
    until_fail,
    until_success,
};

/// Leaf nodes (Actions and Conditions)
pub const LeafNode = struct {
    action_fn: ?*const fn (*Blackboard) anyerror!NodeStatus,
    condition_fn: ?*const fn (*Blackboard) bool,
    leaf_type: LeafType,

    pub fn init(allocator: std.mem.Allocator, leaf_type: LeafType) LeafNode {
        _ = allocator;
        return LeafNode{
            .action_fn = null,
            .condition_fn = null,
            .leaf_type = leaf_type,
        };
    }

    pub fn deinit(self: *LeafNode) void {
        _ = self;
    }

    pub fn setAction(self: *LeafNode, action: *const fn (*Blackboard) anyerror!NodeStatus) void {
        self.action_fn = action;
    }

    pub fn setCondition(self: *LeafNode, condition: *const fn (*Blackboard) bool) void {
        self.condition_fn = condition;
    }

    pub fn execute(self: *LeafNode, blackboard: *Blackboard) !NodeStatus {
        return switch (self.leaf_type) {
            .action => if (self.action_fn) |action| try action(blackboard) else .failure,
            .condition => if (self.condition_fn) |condition| (if (condition(blackboard)) .success else .failure) else .failure,
        };
    }
};

pub const LeafType = enum {
    action,
    condition,
};

/// Blackboard for sharing data between nodes
pub const Blackboard = struct {
    allocator: std.mem.Allocator,
    data: std.HashMap([]const u8, BlackboardValue, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),

    pub fn init(allocator: std.mem.Allocator) Blackboard {
        return Blackboard{
            .allocator = allocator,
            .data = std.HashMap([]const u8, BlackboardValue, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }

    pub fn deinit(self: *Blackboard) void {
        var iterator = self.data.iterator();
        while (iterator.next()) |entry| {
            switch (entry.value_ptr.*) {
                .string => |s| self.allocator.free(s),
                else => {},
            }
        }
        self.data.deinit();
    }

    pub fn set(self: *Blackboard, key: []const u8, value: BlackboardValue) !void {
        const key_copy = try self.allocator.dupe(u8, key);
        if (self.data.get(key)) |old_value| {
            switch (old_value) {
                .string => |s| self.allocator.free(s),
                else => {},
            }
        }
        try self.data.put(key_copy, value);
    }

    pub fn get(self: *Blackboard, key: []const u8) ?BlackboardValue {
        return self.data.get(key);
    }

    pub fn getFloat(self: *Blackboard, key: []const u8) ?f32 {
        if (self.data.get(key)) |value| {
            return switch (value) {
                .float => |f| f,
                else => null,
            };
        }
        return null;
    }

    pub fn getInt(self: *Blackboard, key: []const u8) ?i32 {
        if (self.data.get(key)) |value| {
            return switch (value) {
                .int => |i| i,
                else => null,
            };
        }
        return null;
    }

    pub fn getBool(self: *Blackboard, key: []const u8) ?bool {
        if (self.data.get(key)) |value| {
            return switch (value) {
                .bool => |b| b,
                else => null,
            };
        }
        return null;
    }

    pub fn getVec3(self: *Blackboard, key: []const u8) ?Vec3 {
        if (self.data.get(key)) |value| {
            return switch (value) {
                .vec3 => |v| v,
                else => null,
            };
        }
        return null;
    }
};

pub const BlackboardValue = union(enum) {
    float: f32,
    int: i32,
    bool: bool,
    vec3: Vec3,
    string: []const u8,
};
