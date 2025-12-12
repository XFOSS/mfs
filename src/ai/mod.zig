//! MFS Engine - AI and Machine Learning Integration
//! Neural networks, behavior trees, pathfinding, and ML-powered game features
//! Provides comprehensive AI capabilities for modern game development

const std = @import("std");
const math = @import("../math/mod.zig");
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;

// Re-export AI modules
pub const neural_networks = @import("neural_networks.zig");
pub const neural = @import("neural/mod.zig");
pub const behavior = @import("behavior_trees.zig");
pub const pathfinding = @import("pathfinding.zig");
pub const ml_features = @import("ml_features.zig");
pub const decision_making = @import("decision_making.zig");

/// AI System Manager - coordinates all AI subsystems
pub const AISystem = struct {
    allocator: std.mem.Allocator,
    neural_engine: neural_networks.NeuralEngine,
    behavior_manager: behavior.BehaviorManager,
    pathfinding_system: pathfinding.PathfindingSystem,
    ml_processor: ml_features.MLProcessor,
    decision_engine: decision_making.DecisionEngine,

    // Performance tracking
    frame_time_ms: f32 = 0.0,
    ai_entities: std.array_list.Managed(AIEntity),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        std.log.info("Initializing MFS AI System...", .{});

        return Self{
            .allocator = allocator,
            .neural_engine = try neural_networks.NeuralEngine.init(allocator),
            .behavior_manager = try behavior.BehaviorManager.init(allocator),
            .pathfinding_system = try pathfinding.PathfindingSystem.init(allocator),
            .ml_processor = try ml_features.MLProcessor.init(allocator),
            .decision_engine = try decision_making.DecisionEngine.init(allocator),
            .ai_entities = std.array_list.Managed(AIEntity).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.neural_engine.deinit();
        self.behavior_manager.deinit();
        self.pathfinding_system.deinit();
        self.ml_processor.deinit();
        self.decision_engine.deinit();

        for (self.ai_entities.items) |*entity| {
            entity.deinit();
        }
        self.ai_entities.deinit();
    }

    /// Update all AI systems
    pub fn update(self: *Self, delta_time: f32) !void {
        const start_time = std.time.milliTimestamp();

        // Update neural networks
        try self.neural_engine.update(delta_time);

        // Update behavior trees
        try self.behavior_manager.update(delta_time);

        // Update pathfinding
        try self.pathfinding_system.update(delta_time);

        // Process ML features
        try self.ml_processor.update(delta_time);

        // Update decision making
        try self.decision_engine.update(delta_time);

        // Update AI entities
        for (self.ai_entities.items) |*entity| {
            try entity.update(delta_time);
        }

        const end_time = std.time.milliTimestamp();
        self.frame_time_ms = @floatFromInt(end_time - start_time);
    }

    /// Create an AI entity
    pub fn createAIEntity(self: *Self, config: AIEntityConfig) !*AIEntity {
        const entity = try self.allocator.create(AIEntity);
        entity.* = try AIEntity.init(self.allocator, config);
        try self.ai_entities.append(entity.*);
        return entity;
    }

    /// Get performance metrics
    pub fn getMetrics(self: *Self) AIMetrics {
        return AIMetrics{
            .frame_time_ms = self.frame_time_ms,
            .active_entities = @intCast(self.ai_entities.items.len),
            .neural_networks = self.neural_engine.getNetworkCount(),
            .behavior_trees = self.behavior_manager.getTreeCount(),
            .pathfinding_requests = self.pathfinding_system.getActiveRequests(),
        };
    }
};

/// AI Entity - represents an AI-controlled game entity
pub const AIEntity = struct {
    allocator: std.mem.Allocator,
    id: u32,
    position: Vec3,
    config: AIEntityConfig,

    // AI components
    neural_network: ?*neural_networks.NeuralNetwork = null,
    behavior_tree: ?*behavior.BehaviorTree = null,
    pathfinder: ?*pathfinding.Pathfinder = null,
    decision_maker: ?*decision_making.DecisionMaker = null,

    // State
    current_state: AIState = .idle,
    target_position: ?Vec3 = null,
    memory: std.HashMap([]const u8, f32, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: AIEntityConfig) !Self {
        var entity = Self{
            .allocator = allocator,
            .id = config.id,
            .position = config.initial_position,
            .config = config,
            .memory = std.HashMap([]const u8, f32, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
        };

        // Initialize AI components based on config
        if (config.use_neural_network) {
            entity.neural_network = try allocator.create(neural_networks.NeuralNetwork);
            entity.neural_network.?.* = try neural_networks.NeuralNetwork.init(allocator, config.neural_config);
        }

        if (config.use_behavior_tree) {
            entity.behavior_tree = try allocator.create(behavior.BehaviorTree);
            entity.behavior_tree.?.* = try behavior.BehaviorTree.init(allocator, config.behavior_config);
        }

        if (config.use_pathfinding) {
            entity.pathfinder = try allocator.create(pathfinding.Pathfinder);
            entity.pathfinder.?.* = try pathfinding.Pathfinder.init(allocator);
        }

        if (config.use_decision_making) {
            entity.decision_maker = try allocator.create(decision_making.DecisionMaker);
            entity.decision_maker.?.* = try decision_making.DecisionMaker.init(allocator, config.id);
        }

        return entity;
    }

    pub fn deinit(self: *Self) void {
        if (self.neural_network) |nn| {
            nn.deinit();
            self.allocator.destroy(nn);
        }

        if (self.behavior_tree) |bt| {
            bt.deinit();
            self.allocator.destroy(bt);
        }

        if (self.pathfinder) |pf| {
            pf.deinit();
            self.allocator.destroy(pf);
        }

        if (self.decision_maker) |dm| {
            dm.deinit();
            self.allocator.destroy(dm);
        }

        self.memory.deinit();
    }

    pub fn update(self: *Self, delta_time: f32) !void {
        // Update neural network
        if (self.neural_network) |nn| {
            const inputs = try self.gatherInputs();
            const outputs = try nn.forward(inputs);
            try self.processNeuralOutputs(outputs);
        }

        // Update behavior tree
        if (self.behavior_tree) |bt| {
            _ = try bt.tick(delta_time);
        }

        // Update pathfinding
        if (self.pathfinder) |pf| {
            if (self.target_position) |target| {
                if (try pf.findPath(self.position, target)) |path| {
                    try self.followPath(path, delta_time);
                }
            }
        }

        // Update decision making
        if (self.decision_maker) |dm| {
            const context = decision_making.DecisionContext{
                .position = self.position,
                .velocity = Vec3.zero(), // Default velocity
                .health = 1.0, // Default health
                .energy = 1.0, // Default energy
                .nearby_entities = &[_]decision_making.EntityInfo{}, // Empty array for now
                .environment_data = decision_making.EnvironmentData{
                    .temperature = 20.0,
                    .visibility = 1.0,
                    .noise_level = 0.1,
                    .terrain_type = .open,
                },
                .global_memory = &self.memory,
                .threat_level = 0.0,
                .resources_available = 0,
            };

            if (try dm.makeDecision(context)) |decision| {
                try self.executeDecision(decision);
            }
        }
    }

    /// Set target position for pathfinding
    pub fn setTarget(self: *Self, target: Vec3) void {
        self.target_position = target;
    }

    /// Store information in memory
    pub fn remember(self: *Self, key: []const u8, value: f32) !void {
        try self.memory.put(try self.allocator.dupe(u8, key), value);
    }

    /// Retrieve information from memory
    pub fn recall(self: *Self, key: []const u8) ?f32 {
        return self.memory.get(key);
    }

    fn gatherInputs(self: *Self) ![]f32 {
        // Gather sensory inputs for neural network
        var inputs = try self.allocator.alloc(f32, 10);

        // Position
        inputs[0] = self.position.x;
        inputs[1] = self.position.y;
        inputs[2] = self.position.z;

        // State
        inputs[3] = @floatFromInt(@intFromEnum(self.current_state));

        // Target distance
        if (self.target_position) |target| {
            const distance = self.position.distance(target);
            inputs[4] = distance;
        } else {
            inputs[4] = 0.0;
        }

        // Memory values (simplified)
        inputs[5] = self.recall("threat_level") orelse 0.0;
        inputs[6] = self.recall("energy_level") orelse 1.0;
        inputs[7] = self.recall("last_action_success") orelse 0.5;
        inputs[8] = self.recall("social_status") orelse 0.0;
        inputs[9] = self.recall("exploration_desire") orelse 0.3;

        return inputs;
    }

    fn processNeuralOutputs(self: *Self, outputs: []f32) !void {
        if (outputs.len >= 4) {
            // Interpret neural network outputs
            const move_x = outputs[0];
            const move_y = outputs[1];
            const move_z = outputs[2];
            const action_strength = outputs[3];

            // Update position based on neural output
            self.position.x += move_x * 0.1;
            self.position.y += move_y * 0.1;
            self.position.z += move_z * 0.1;

            // Update state based on action strength
            if (action_strength > 0.7) {
                self.current_state = .aggressive;
            } else if (action_strength > 0.3) {
                self.current_state = .active;
            } else {
                self.current_state = .passive;
            }
        }
    }

    fn followPath(self: *Self, path: []Vec3, delta_time: f32) !void {
        if (path.len > 0) {
            const target = path[0];
            const direction = target.subtract(self.position).normalize();
            const speed = 5.0; // units per second

            self.position = self.position.add(direction.scale(speed * delta_time));
        }
    }

    fn executeDecision(self: *Self, decision: decision_making.Decision) !void {
        switch (decision.action) {
            .move_to => |pos| self.setTarget(pos),
            .attack => |_| self.current_state = .aggressive,
            .defend => |_| self.current_state = .defensive,
            .explore => |_| self.current_state = .exploring,
            .idle => self.current_state = .idle,
            .patrol => |_| self.current_state = .active,
            .flee => |pos| {
                self.setTarget(pos);
                self.current_state = .fleeing;
            },
            .investigate => |pos| {
                self.setTarget(pos);
                self.current_state = .active;
            },
        }
    }
};

pub const AIEntityConfig = struct {
    id: u32,
    initial_position: Vec3,
    use_neural_network: bool = false,
    use_behavior_tree: bool = true,
    use_pathfinding: bool = true,
    use_decision_making: bool = true,
    neural_config: neural_networks.NetworkConfig = .{},
    behavior_config: behavior.TreeConfig = .{},
};

pub const AIState = enum {
    idle,
    active,
    passive,
    aggressive,
    defensive,
    exploring,
    fleeing,
    pursuing,
};

pub const AIMetrics = struct {
    frame_time_ms: f32,
    active_entities: u32,
    neural_networks: u32,
    behavior_trees: u32,
    pathfinding_requests: u32,
};

/// AI debugging and visualization tools
pub const AIDebugger = struct {
    allocator: std.mem.Allocator,
    debug_entities: std.array_list.Managed(DebugInfo),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .debug_entities = std.array_list.Managed(DebugInfo).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.debug_entities.deinit();
    }

    pub fn addDebugEntity(self: *Self, entity: *AIEntity) !void {
        const debug_info = DebugInfo{
            .entity_id = entity.id,
            .position = entity.position,
            .state = entity.current_state,
            .target = entity.target_position,
        };

        try self.debug_entities.append(debug_info);
    }

    pub fn renderDebugInfo(self: *Self) void {
        std.log.info("=== AI Debug Information ===", .{});
        for (self.debug_entities.items) |info| {
            std.log.info("Entity {}: State={s}, Pos=({d:.2}, {d:.2}, {d:.2})", .{
                info.entity_id,
                @tagName(info.state),
                info.position.x,
                info.position.y,
                info.position.z,
            });
        }
    }
};

pub const DebugInfo = struct {
    entity_id: u32,
    position: Vec3,
    state: AIState,
    target: ?Vec3,
};

/// AI Performance Profiler
pub const AIProfiler = struct {
    neural_time: f64 = 0.0,
    behavior_time: f64 = 0.0,
    pathfinding_time: f64 = 0.0,
    decision_time: f64 = 0.0,
    total_time: f64 = 0.0,

    pub fn startProfiling(self: *AIProfiler) void {
        _ = self;
        // Reset timers
    }

    pub fn recordNeuralTime(self: *AIProfiler, time: f64) void {
        self.neural_time += time;
    }

    pub fn recordBehaviorTime(self: *AIProfiler, time: f64) void {
        self.behavior_time += time;
    }

    pub fn recordPathfindingTime(self: *AIProfiler, time: f64) void {
        self.pathfinding_time += time;
    }

    pub fn recordDecisionTime(self: *AIProfiler, time: f64) void {
        self.decision_time += time;
    }

    pub fn finishProfiling(self: *AIProfiler) void {
        self.total_time = self.neural_time + self.behavior_time + self.pathfinding_time + self.decision_time;
    }

    pub fn printReport(self: *AIProfiler) void {
        std.log.info("=== AI Performance Report ===", .{});
        std.log.info("Neural Networks: {d:.2}ms ({d:.1}%)", .{ self.neural_time, (self.neural_time / self.total_time) * 100.0 });
        std.log.info("Behavior Trees: {d:.2}ms ({d:.1}%)", .{ self.behavior_time, (self.behavior_time / self.total_time) * 100.0 });
        std.log.info("Pathfinding: {d:.2}ms ({d:.1}%)", .{ self.pathfinding_time, (self.pathfinding_time / self.total_time) * 100.0 });
        std.log.info("Decision Making: {d:.2}ms ({d:.1}%)", .{ self.decision_time, (self.decision_time / self.total_time) * 100.0 });
        std.log.info("Total AI Time: {d:.2}ms", .{self.total_time});
    }
};
