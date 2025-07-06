//! Decision Making Implementation
//! Advanced AI decision-making system with utility-based AI, state machines, and memory

const std = @import("std");
const math = @import("../math/mod.zig");
const Vec3 = math.Vec3;

pub const DecisionEngine = struct {
    allocator: std.mem.Allocator,
    decision_makers: std.ArrayList(*DecisionMaker),
    global_memory: std.HashMap([]const u8, f32, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    update_frequency: f32,
    time_accumulator: f32,

    pub fn init(allocator: std.mem.Allocator) !DecisionEngine {
        return DecisionEngine{
            .allocator = allocator,
            .decision_makers = std.ArrayList(*DecisionMaker).init(allocator),
            .global_memory = std.HashMap([]const u8, f32, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .update_frequency = 0.1, // Update every 100ms
            .time_accumulator = 0.0,
        };
    }

    pub fn deinit(self: *DecisionEngine) void {
        self.decision_makers.deinit();
        self.global_memory.deinit();
    }

    pub fn update(self: *DecisionEngine, delta_time: f32) !void {
        self.time_accumulator += delta_time;

        if (self.time_accumulator >= self.update_frequency) {
            self.time_accumulator = 0.0;

            // Update all decision makers
            for (self.decision_makers.items) |maker| {
                try maker.update(delta_time);
            }

            // Update global memory decay
            try self.updateGlobalMemory(delta_time);
        }
    }

    pub fn addDecisionMaker(self: *DecisionEngine, maker: *DecisionMaker) !void {
        try self.decision_makers.append(maker);
    }

    pub fn removeDecisionMaker(self: *DecisionEngine, maker: *DecisionMaker) void {
        for (self.decision_makers.items, 0..) |item, i| {
            if (item == maker) {
                _ = self.decision_makers.swapRemove(i);
                break;
            }
        }
    }

    fn updateGlobalMemory(self: *DecisionEngine, delta_time: f32) !void {
        var iterator = self.global_memory.iterator();
        var keys_to_remove = std.ArrayList([]const u8).init(self.allocator);
        defer keys_to_remove.deinit();

        while (iterator.next()) |entry| {
            const decay_rate = 0.1; // Memory decay rate
            entry.value_ptr.* -= decay_rate * delta_time;

            if (entry.value_ptr.* <= 0.0) {
                try keys_to_remove.append(entry.key_ptr.*);
            }
        }

        for (keys_to_remove.items) |key| {
            _ = self.global_memory.remove(key);
        }
    }

    pub fn getActiveDecisionMakers(self: *DecisionEngine) u32 {
        return @intCast(self.decision_makers.items.len);
    }
};

pub const DecisionMaker = struct {
    allocator: std.mem.Allocator,
    id: u32,
    current_state: AIState,
    state_machine: StateMachine,
    utility_evaluator: UtilityEvaluator,
    local_memory: std.HashMap([]const u8, f32, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    last_decision: ?Decision,
    decision_cooldown: f32,
    cooldown_timer: f32,

    pub fn init(allocator: std.mem.Allocator, id: u32) !DecisionMaker {
        return DecisionMaker{
            .allocator = allocator,
            .id = id,
            .current_state = .idle,
            .state_machine = try StateMachine.init(allocator),
            .utility_evaluator = try UtilityEvaluator.init(allocator),
            .local_memory = std.HashMap([]const u8, f32, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .last_decision = null,
            .decision_cooldown = 0.5, // 500ms cooldown between decisions
            .cooldown_timer = 0.0,
        };
    }

    pub fn deinit(self: *DecisionMaker) void {
        self.state_machine.deinit();
        self.utility_evaluator.deinit();
        self.local_memory.deinit();
    }

    pub fn update(self: *DecisionMaker, delta_time: f32) !void {
        self.cooldown_timer -= delta_time;
        try self.state_machine.update(delta_time);
        try self.updateLocalMemory(delta_time);
    }

    pub fn makeDecision(self: *DecisionMaker, context: DecisionContext) !?Decision {
        if (self.cooldown_timer > 0.0) {
            return self.last_decision;
        }

        // Evaluate all possible actions using utility-based AI
        const best_action = try self.utility_evaluator.evaluateBestAction(context, self.local_memory);

        if (best_action) |action| {
            const decision = Decision{
                .action = action,
                .confidence = try self.utility_evaluator.getLastConfidence(),
                .timestamp = std.time.milliTimestamp(),
            };

            self.last_decision = decision;
            self.cooldown_timer = self.decision_cooldown;

            // Update state machine based on decision
            try self.state_machine.transitionTo(self.getStateFromAction(action));

            return decision;
        }

        return null;
    }

    fn updateLocalMemory(self: *DecisionMaker, delta_time: f32) !void {
        var iterator = self.local_memory.iterator();
        var keys_to_remove = std.ArrayList([]const u8).init(self.allocator);
        defer keys_to_remove.deinit();

        while (iterator.next()) |entry| {
            const decay_rate = 0.05; // Slower decay for local memory
            entry.value_ptr.* -= decay_rate * delta_time;

            if (entry.value_ptr.* <= 0.0) {
                try keys_to_remove.append(entry.key_ptr.*);
            }
        }

        for (keys_to_remove.items) |key| {
            _ = self.local_memory.remove(key);
        }
    }

    fn getStateFromAction(self: *DecisionMaker, action: ActionType) AIState {
        _ = self;
        return switch (action) {
            .move_to => .moving,
            .attack => .attacking,
            .defend => .defending,
            .explore => .exploring,
            .idle => .idle,
            .patrol => .patrolling,
            .flee => .fleeing,
            .investigate => .investigating,
        };
    }

    pub fn addMemory(self: *DecisionMaker, key: []const u8, value: f32) !void {
        try self.local_memory.put(key, value);
    }

    pub fn getMemory(self: *DecisionMaker, key: []const u8) ?f32 {
        return self.local_memory.get(key);
    }
};

pub const DecisionContext = struct {
    position: Vec3,
    velocity: Vec3,
    health: f32,
    energy: f32,
    nearby_entities: []EntityInfo,
    environment_data: EnvironmentData,
    global_memory: *std.HashMap([]const u8, f32, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    threat_level: f32,
    resources_available: u32,
};

pub const Decision = struct {
    action: ActionType,
    confidence: f32,
    timestamp: i64,
};

pub const ActionType = union(enum) {
    move_to: Vec3,
    attack: EntityTarget,
    defend: DefenseParams,
    explore: ExploreParams,
    idle: void,
    patrol: PatrolParams,
    flee: Vec3,
    investigate: Vec3,
};

pub const EntityTarget = struct {
    id: u32,
    position: Vec3,
    priority: f32,
};

pub const DefenseParams = struct {
    position: Vec3,
    radius: f32,
};

pub const ExploreParams = struct {
    center: Vec3,
    radius: f32,
    duration: f32,
};

pub const PatrolParams = struct {
    waypoints: []Vec3,
    current_index: u32,
    loop: bool,
};

pub const EntityInfo = struct {
    id: u32,
    position: Vec3,
    entity_type: EntityType,
    threat_level: f32,
    distance: f32,
};

pub const EntityType = enum {
    ally,
    enemy,
    neutral,
    resource,
    obstacle,
};

pub const EnvironmentData = struct {
    temperature: f32,
    visibility: f32,
    noise_level: f32,
    terrain_type: TerrainType,
};

pub const TerrainType = enum {
    open,
    forest,
    urban,
    water,
    mountain,
};

pub const AIState = enum {
    idle,
    moving,
    attacking,
    defending,
    exploring,
    patrolling,
    fleeing,
    investigating,
};

pub const StateMachine = struct {
    allocator: std.mem.Allocator,
    current_state: AIState,
    previous_state: AIState,
    state_timers: std.HashMap(AIState, f32, StateContext, std.hash_map.default_max_load_percentage),
    transitions: std.HashMap(StateTransition, bool, TransitionContext, std.hash_map.default_max_load_percentage),

    const StateContext = struct {
        pub fn hash(self: @This(), state: AIState) u64 {
            _ = self;
            return @intFromEnum(state);
        }
        pub fn eql(self: @This(), a: AIState, b: AIState) bool {
            _ = self;
            return a == b;
        }
    };

    const TransitionContext = struct {
        pub fn hash(self: @This(), transition: StateTransition) u64 {
            _ = self;
            return (@intFromEnum(transition.from) << 8) | @intFromEnum(transition.to);
        }
        pub fn eql(self: @This(), a: StateTransition, b: StateTransition) bool {
            _ = self;
            return a.from == b.from and a.to == b.to;
        }
    };

    pub fn init(allocator: std.mem.Allocator) !StateMachine {
        return StateMachine{
            .allocator = allocator,
            .current_state = .idle,
            .previous_state = .idle,
            .state_timers = std.HashMap(AIState, f32, StateContext, std.hash_map.default_max_load_percentage).initContext(allocator, StateContext{}),
            .transitions = std.HashMap(StateTransition, bool, TransitionContext, std.hash_map.default_max_load_percentage).initContext(allocator, TransitionContext{}),
        };
    }

    pub fn deinit(self: *StateMachine) void {
        self.state_timers.deinit();
        self.transitions.deinit();
    }

    pub fn update(self: *StateMachine, delta_time: f32) !void {
        // Update current state timer
        const current_time = self.state_timers.get(self.current_state) orelse 0.0;
        try self.state_timers.put(self.current_state, current_time + delta_time);
    }

    pub fn transitionTo(self: *StateMachine, new_state: AIState) !void {
        if (self.current_state == new_state) return;

        const transition = StateTransition{ .from = self.current_state, .to = new_state };
        if (self.transitions.get(transition) orelse true) { // Allow transition by default
            self.previous_state = self.current_state;
            self.current_state = new_state;
            try self.state_timers.put(new_state, 0.0);
        }
    }

    pub fn getTimeInCurrentState(self: *StateMachine) f32 {
        return self.state_timers.get(self.current_state) orelse 0.0;
    }
};

pub const StateTransition = struct {
    from: AIState,
    to: AIState,
};

pub const UtilityEvaluator = struct {
    allocator: std.mem.Allocator,
    utility_functions: std.HashMap(ActionType, UtilityFunction, ActionContext, std.hash_map.default_max_load_percentage),
    last_confidence: f32,

    const ActionContext = struct {
        pub fn hash(self: @This(), action: ActionType) u64 {
            _ = self;
            return switch (action) {
                .move_to => 0,
                .attack => 1,
                .defend => 2,
                .explore => 3,
                .idle => 4,
                .patrol => 5,
                .flee => 6,
                .investigate => 7,
            };
        }
        pub fn eql(self: @This(), a: ActionType, b: ActionType) bool {
            _ = self;
            return std.meta.activeTag(a) == std.meta.activeTag(b);
        }
    };

    pub fn init(allocator: std.mem.Allocator) !UtilityEvaluator {
        var evaluator = UtilityEvaluator{
            .allocator = allocator,
            .utility_functions = std.HashMap(ActionType, UtilityFunction, ActionContext, std.hash_map.default_max_load_percentage).initContext(allocator, ActionContext{}),
            .last_confidence = 0.0,
        };

        // Initialize default utility functions
        try evaluator.initializeDefaultUtilities();
        return evaluator;
    }

    pub fn deinit(self: *UtilityEvaluator) void {
        self.utility_functions.deinit();
    }

    fn initializeDefaultUtilities(self: *UtilityEvaluator) !void {
        // Default utility functions for each action type
        try self.utility_functions.put(ActionType{ .idle = {} }, UtilityFunction{ .base_utility = 0.1, .factors = &[_]UtilityFactor{} });
        try self.utility_functions.put(ActionType{ .explore = ExploreParams{ .center = Vec3.zero(), .radius = 10.0, .duration = 5.0 } }, UtilityFunction{ .base_utility = 0.3, .factors = &[_]UtilityFactor{} });
    }

    pub fn evaluateBestAction(self: *UtilityEvaluator, context: DecisionContext, memory: std.HashMap([]const u8, f32, std.hash_map.StringContext, std.hash_map.default_max_load_percentage)) !?ActionType {
        var best_action: ?ActionType = null;
        var best_utility: f32 = -1.0;

        // Evaluate each possible action
        const possible_actions = try self.generatePossibleActions(context);
        defer self.allocator.free(possible_actions);

        for (possible_actions) |action| {
            const utility = try self.evaluateActionUtility(action, context, memory);
            if (utility > best_utility) {
                best_utility = utility;
                best_action = action;
            }
        }

        self.last_confidence = if (best_utility > 0.0) best_utility else 0.0;
        return best_action;
    }

    fn generatePossibleActions(self: *UtilityEvaluator, context: DecisionContext) ![]ActionType {
        var actions = std.ArrayList(ActionType).init(self.allocator);

        // Always possible actions
        try actions.append(ActionType{ .idle = {} });

        // Context-dependent actions
        if (context.energy > 0.2) {
            try actions.append(ActionType{ .explore = ExploreParams{ .center = context.position, .radius = 20.0, .duration = 10.0 } });
        }

        if (context.threat_level > 0.5) {
            try actions.append(ActionType{ .flee = context.position.add(Vec3.new(10.0, 0.0, 0.0)) });
        }

        // Check for nearby entities to interact with
        for (context.nearby_entities) |entity| {
            switch (entity.entity_type) {
                .enemy => {
                    if (context.health > 0.3) {
                        try actions.append(ActionType{ .attack = EntityTarget{ .id = entity.id, .position = entity.position, .priority = entity.threat_level } });
                    }
                },
                .resource => {
                    try actions.append(ActionType{ .move_to = entity.position });
                },
                else => {},
            }
        }

        return actions.toOwnedSlice();
    }

    fn evaluateActionUtility(self: *UtilityEvaluator, action: ActionType, context: DecisionContext, memory: std.HashMap([]const u8, f32, std.hash_map.StringContext, std.hash_map.default_max_load_percentage)) !f32 {
        _ = self;
        _ = memory;

        // Basic utility evaluation based on action type and context
        return switch (action) {
            .idle => 0.1,
            .explore => if (context.energy > 0.3) 0.6 else 0.2,
            .attack => if (context.health > 0.5) 0.8 else 0.3,
            .defend => if (context.threat_level > 0.4) 0.7 else 0.2,
            .flee => if (context.threat_level > 0.7 or context.health < 0.3) 0.9 else 0.1,
            .move_to => 0.4,
            .patrol => 0.3,
            .investigate => if (context.environment_data.noise_level > 0.5) 0.5 else 0.2,
        };
    }

    pub fn getLastConfidence(self: *UtilityEvaluator) !f32 {
        return self.last_confidence;
    }
};

pub const UtilityFunction = struct {
    base_utility: f32,
    factors: []const UtilityFactor,
};

pub const UtilityFactor = struct {
    weight: f32,
    curve_type: CurveType,
    input_range: [2]f32,
    output_range: [2]f32,
};

pub const CurveType = enum {
    linear,
    quadratic,
    exponential,
    logarithmic,
};
