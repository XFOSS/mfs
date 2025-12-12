//! MFS Engine - Advanced Networking for Multiplayer Games
//! Client-server architecture, P2P networking, real-time synchronization
//! Provides comprehensive networking capabilities for modern multiplayer games

const std = @import("std");
const math = @import("../math/mod.zig");
const Vec3 = math.Vec3;

// Re-export networking modules
pub const protocol = @import("protocol.zig");
pub const client = @import("client.zig");
pub const server = @import("server.zig");
pub const p2p = @import("p2p.zig");
pub const sync = @import("synchronization.zig");
pub const security = @import("security.zig");

/// Network Manager - coordinates all networking subsystems
pub const NetworkManager = struct {
    allocator: std.mem.Allocator,
    mode: NetworkMode,

    // Network components
    server: ?server.GameServer = null,
    client: ?client.GameClient = null,
    p2p_node: ?p2p.P2PNode = null,
    sync_manager: sync.SynchronizationManager,
    security_manager: security.SecurityManager,

    // Connection management
    connections: std.HashMap(u32, Connection, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage),
    next_connection_id: u32 = 1,

    // Statistics
    stats: NetworkStats = .{},

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, mode: NetworkMode) !Self {
        std.log.info("Initializing MFS Network Manager in {} mode...", .{mode});

        var manager = Self{
            .allocator = allocator,
            .mode = mode,
            .sync_manager = try sync.SynchronizationManager.init(allocator),
            .security_manager = try security.SecurityManager.init(allocator),
            .connections = std.HashMap(u32, Connection, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage).init(allocator),
        };

        // Initialize based on mode
        switch (mode) {
            .server => {
                manager.server = try server.GameServer.init(allocator);
            },
            .client => {
                manager.client = try client.GameClient.init(allocator);
            },
            .p2p => {
                manager.p2p_node = try p2p.P2PNode.init(allocator);
            },
            .hybrid => {
                manager.server = try server.GameServer.init(allocator);
                manager.client = try client.GameClient.init(allocator);
                manager.p2p_node = try p2p.P2PNode.init(allocator);
            },
        }

        return manager;
    }

    pub fn deinit(self: *Self) void {
        if (self.server) |*s| s.deinit();
        if (self.client) |*c| c.deinit();
        if (self.p2p_node) |*p| p.deinit();

        self.sync_manager.deinit();
        self.security_manager.deinit();

        var iterator = self.connections.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.connections.deinit();
    }

    /// Start networking services
    pub fn start(self: *Self, config: NetworkConfig) !void {
        std.log.info("Starting network services...", .{});

        switch (self.mode) {
            .server => {
                if (self.server) |*s| {
                    try s.start(config.server_config);
                }
            },
            .client => {
                if (self.client) |*c| {
                    try c.connect(config.client_config);
                }
            },
            .p2p => {
                if (self.p2p_node) |*p| {
                    try p.start(config.p2p_config);
                }
            },
            .hybrid => {
                if (self.server) |*s| {
                    try s.start(config.server_config);
                }
                if (self.p2p_node) |*p| {
                    try p.start(config.p2p_config);
                }
            },
        }

        std.log.info("Network services started successfully", .{});
    }

    /// Update network systems
    pub fn update(self: *Self, delta_time: f32) !void {
        const start_time = std.time.microTimestamp();

        // Update server
        if (self.server) |*s| {
            try s.update(delta_time);
        }

        // Update client
        if (self.client) |*c| {
            try c.update(delta_time);
        }

        // Update P2P
        if (self.p2p_node) |*p| {
            try p.update(delta_time);
        }

        // Update synchronization
        try self.sync_manager.update(delta_time);

        // Update security
        try self.security_manager.update(delta_time);

        // Process messages
        try self.processMessages();

        // Update statistics
        const end_time = std.time.microTimestamp();
        self.stats.update_time_us = end_time - start_time;
        self.stats.frames_processed += 1;
    }

    /// Send a message to a specific connection
    pub fn sendMessage(self: *Self, connection_id: u32, message: protocol.Message) !void {
        if (self.connections.get(connection_id)) |connection| {
            try self.sendMessageToConnection(connection, message);
            self.stats.messages_sent += 1;
            self.stats.bytes_sent += message.getSize();
        } else {
            return error.ConnectionNotFound;
        }
    }

    /// Broadcast a message to all connections
    pub fn broadcastMessage(self: *Self, message: protocol.Message) !void {
        var iterator = self.connections.iterator();
        while (iterator.next()) |entry| {
            try self.sendMessageToConnection(entry.value_ptr.*, message);
        }

        self.stats.messages_sent += @intCast(self.connections.count());
        self.stats.bytes_sent += message.getSize() * @as(u64, @intCast(self.connections.count()));
    }

    /// Register a network event handler
    pub fn registerHandler(self: *Self, event_type: protocol.MessageType, handler: protocol.MessageHandler) !void {
        _ = self;
        _ = event_type;
        _ = handler;
        // TODO: Implement event handler registration
    }

    /// Get network statistics
    pub fn getStats(self: *Self) NetworkStats {
        return self.stats;
    }

    /// Get connection information
    pub fn getConnectionInfo(self: *Self, connection_id: u32) ?ConnectionInfo {
        if (self.connections.get(connection_id)) |connection| {
            return ConnectionInfo{
                .id = connection.id,
                .address = connection.address,
                .state = connection.state,
                .ping_ms = connection.ping_ms,
                .bytes_sent = connection.bytes_sent,
                .bytes_received = connection.bytes_received,
                .connected_time = connection.connected_time,
            };
        }
        return null;
    }

    fn processMessages(self: *Self) !void {
        // Process server messages
        if (self.server) |*s| {
            while (try s.receiveMessage()) |msg| {
                try self.handleMessage(msg);
                self.stats.messages_received += 1;
                self.stats.bytes_received += msg.getSize();
            }
        }

        // Process client messages
        if (self.client) |*c| {
            while (try c.receiveMessage()) |msg| {
                try self.handleMessage(msg);
                self.stats.messages_received += 1;
                self.stats.bytes_received += msg.getSize();
            }
        }

        // Process P2P messages
        if (self.p2p_node) |*p| {
            while (try p.receiveMessage()) |msg| {
                try self.handleMessage(msg);
                self.stats.messages_received += 1;
                self.stats.bytes_received += msg.getSize();
            }
        }
    }

    fn handleMessage(self: *Self, message: protocol.Message) !void {
        switch (message.type) {
            .player_join => try self.handlePlayerJoin(message),
            .player_leave => try self.handlePlayerLeave(message),
            .game_state => try self.handleGameState(message),
            .player_input => try self.handlePlayerInput(message),
            .chat_message => try self.handleChatMessage(message),
            .ping => try self.handlePing(message),
            .pong => try self.handlePong(message),
            else => std.log.warn("Unhandled message type: {}", .{message.type}),
        }
    }

    fn handlePlayerJoin(self: *Self, message: protocol.Message) !void {
        _ = self;
        _ = message;
        std.log.info("Player joined the game", .{});
    }

    fn handlePlayerLeave(self: *Self, message: protocol.Message) !void {
        _ = self;
        _ = message;
        std.log.info("Player left the game", .{});
    }

    fn handleGameState(self: *Self, message: protocol.Message) !void {
        try self.sync_manager.processGameState(message);
    }

    fn handlePlayerInput(self: *Self, message: protocol.Message) !void {
        try self.sync_manager.processPlayerInput(message);
    }

    fn handleChatMessage(self: *Self, message: protocol.Message) !void {
        _ = self;
        std.log.info("Chat: {s}", .{message.data});
    }

    fn handlePing(self: *Self, message: protocol.Message) !void {
        // Respond with pong
        const pong_message = protocol.Message{
            .type = .pong,
            .sender_id = 0, // Server ID
            .timestamp = std.time.milliTimestamp(),
            .data = message.data,
        };

        try self.sendMessage(message.sender_id, pong_message);
    }

    fn handlePong(self: *Self, message: protocol.Message) !void {
        // Calculate ping
        const current_time = std.time.milliTimestamp();
        const ping_ms = current_time - message.timestamp;

        if (self.connections.getPtr(message.sender_id)) |connection| {
            connection.ping_ms = @floatFromInt(ping_ms);
        }
    }

    fn sendMessageToConnection(self: *Self, connection: Connection, message: protocol.Message) !void {
        _ = self;
        _ = connection;
        _ = message;
        // TODO: Implement actual message sending based on connection type
    }
};

pub const NetworkMode = enum {
    server,
    client,
    p2p,
    hybrid,
};

pub const NetworkConfig = struct {
    server_config: server.ServerConfig = .{},
    client_config: client.ClientConfig = .{},
    p2p_config: p2p.P2PConfig = .{},
};

pub const Connection = struct {
    id: u32,
    address: []const u8,
    state: ConnectionState,
    ping_ms: f32 = 0.0,
    bytes_sent: u64 = 0,
    bytes_received: u64 = 0,
    connected_time: i64,

    pub fn deinit(self: *Connection) void {
        _ = self;
        // Cleanup connection resources
    }
};

pub const ConnectionState = enum {
    connecting,
    connected,
    disconnecting,
    disconnected,
    failed,
};

pub const ConnectionInfo = struct {
    id: u32,
    address: []const u8,
    state: ConnectionState,
    ping_ms: f32,
    bytes_sent: u64,
    bytes_received: u64,
    connected_time: i64,
};

pub const NetworkStats = struct {
    messages_sent: u64 = 0,
    messages_received: u64 = 0,
    bytes_sent: u64 = 0,
    bytes_received: u64 = 0,
    connections_active: u32 = 0,
    update_time_us: i64 = 0,
    frames_processed: u64 = 0,

    pub fn getAverageUpdateTime(self: *const NetworkStats) f64 {
        if (self.frames_processed == 0) return 0.0;
        return @as(f64, @floatFromInt(self.update_time_us)) / @as(f64, @floatFromInt(self.frames_processed));
    }

    pub fn printStats(self: *const NetworkStats) void {
        std.log.info("=== Network Statistics ===", .{});
        std.log.info("Messages Sent: {}", .{self.messages_sent});
        std.log.info("Messages Received: {}", .{self.messages_received});
        std.log.info("Bytes Sent: {} KB", .{self.bytes_sent / 1024});
        std.log.info("Bytes Received: {} KB", .{self.bytes_received / 1024});
        std.log.info("Active Connections: {}", .{self.connections_active});
        std.log.info("Average Update Time: {d:.2} μs", .{self.getAverageUpdateTime()});
    }
};

/// Network Event System
pub const NetworkEventSystem = struct {
    allocator: std.mem.Allocator,
    handlers: std.HashMap(protocol.MessageType, std.array_list.Managed(protocol.MessageHandler), std.hash_map.AutoContext(protocol.MessageType), std.hash_map.default_max_load_percentage),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .handlers = std.HashMap(protocol.MessageType, std.array_list.Managed(protocol.MessageHandler), std.hash_map.AutoContext(protocol.MessageType), std.hash_map.default_max_load_percentage).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var iterator = self.handlers.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.handlers.deinit();
    }

    pub fn registerHandler(self: *Self, message_type: protocol.MessageType, handler: protocol.MessageHandler) !void {
        const result = try self.handlers.getOrPut(message_type);
        if (!result.found_existing) {
            result.value_ptr.* = std.array_list.Managed(protocol.MessageHandler).init(self.allocator);
        }
        try result.value_ptr.append(handler);
    }

    pub fn triggerEvent(self: *Self, message: protocol.Message) !void {
        if (self.handlers.get(message.type)) |handlers| {
            for (handlers.items) |handler| {
                try handler(message);
            }
        }
    }
};

/// Network Security Manager
pub const NetworkSecurityManager = struct {
    allocator: std.mem.Allocator,
    encryption_enabled: bool = true,
    anti_cheat_enabled: bool = true,
    rate_limiting_enabled: bool = true,

    // Rate limiting
    rate_limits: std.HashMap(u32, RateLimit, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .rate_limits = std.HashMap(u32, RateLimit, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.rate_limits.deinit();
    }

    pub fn validateMessage(self: *Self, message: protocol.Message) !bool {
        // Check rate limiting
        if (self.rate_limiting_enabled) {
            if (!try self.checkRateLimit(message.sender_id)) {
                std.log.warn("Rate limit exceeded for connection {}", .{message.sender_id});
                return false;
            }
        }

        // Check message integrity
        if (self.encryption_enabled) {
            if (!try self.validateMessageIntegrity(message)) {
                std.log.warn("Message integrity check failed", .{});
                return false;
            }
        }

        // Anti-cheat validation
        if (self.anti_cheat_enabled) {
            if (!try self.validateAntiCheat(message)) {
                std.log.warn("Anti-cheat validation failed for connection {}", .{message.sender_id});
                return false;
            }
        }

        return true;
    }

    fn checkRateLimit(self: *Self, connection_id: u32) !bool {
        const current_time = std.time.milliTimestamp();

        const result = try self.rate_limits.getOrPut(connection_id);
        if (!result.found_existing) {
            result.value_ptr.* = RateLimit{
                .messages_per_second = 100, // Default limit
                .last_reset_time = current_time,
                .message_count = 0,
            };
        }

        const rate_limit = result.value_ptr;

        // Reset counter if a second has passed
        if (current_time - rate_limit.last_reset_time >= 1000) {
            rate_limit.message_count = 0;
            rate_limit.last_reset_time = current_time;
        }

        rate_limit.message_count += 1;
        return rate_limit.message_count <= rate_limit.messages_per_second;
    }

    fn validateMessageIntegrity(self: *Self, message: protocol.Message) !bool {
        _ = self;
        _ = message;
        // TODO: Implement message integrity validation (checksums, signatures, etc.)
        return true;
    }

    fn validateAntiCheat(self: *Self, message: protocol.Message) !bool {
        _ = self;

        switch (message.type) {
            .player_input => {
                // Validate player input for impossible values
                // TODO: Implement input validation logic
                return true;
            },
            .game_state => {
                // Validate game state changes
                // TODO: Implement state validation logic
                return true;
            },
            else => return true,
        }
    }
};

pub const RateLimit = struct {
    messages_per_second: u32,
    last_reset_time: i64,
    message_count: u32,
};

/// Network Diagnostics and Monitoring
pub const NetworkDiagnostics = struct {
    allocator: std.mem.Allocator,
    latency_history: std.array_list.Managed(f32),
    packet_loss_history: std.array_list.Managed(f32),
    bandwidth_history: std.array_list.Managed(f32),

    const Self = @This();
    const HISTORY_SIZE = 100;

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .latency_history = std.array_list.Managed(f32).init(allocator),
            .packet_loss_history = std.array_list.Managed(f32).init(allocator),
            .bandwidth_history = std.array_list.Managed(f32).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.latency_history.deinit();
        self.packet_loss_history.deinit();
        self.bandwidth_history.deinit();
    }

    pub fn recordLatency(self: *Self, latency_ms: f32) !void {
        try self.latency_history.append(latency_ms);
        if (self.latency_history.items.len > HISTORY_SIZE) {
            _ = self.latency_history.orderedRemove(0);
        }
    }

    pub fn recordPacketLoss(self: *Self, loss_percentage: f32) !void {
        try self.packet_loss_history.append(loss_percentage);
        if (self.packet_loss_history.items.len > HISTORY_SIZE) {
            _ = self.packet_loss_history.orderedRemove(0);
        }
    }

    pub fn recordBandwidth(self: *Self, bandwidth_kbps: f32) !void {
        try self.bandwidth_history.append(bandwidth_kbps);
        if (self.bandwidth_history.items.len > HISTORY_SIZE) {
            _ = self.bandwidth_history.orderedRemove(0);
        }
    }

    pub fn getAverageLatency(self: *Self) f32 {
        if (self.latency_history.items.len == 0) return 0.0;

        var total: f32 = 0.0;
        for (self.latency_history.items) |latency| {
            total += latency;
        }
        return total / @as(f32, @floatFromInt(self.latency_history.items.len));
    }

    pub fn getAveragePacketLoss(self: *Self) f32 {
        if (self.packet_loss_history.items.len == 0) return 0.0;

        var total: f32 = 0.0;
        for (self.packet_loss_history.items) |loss| {
            total += loss;
        }
        return total / @as(f32, @floatFromInt(self.packet_loss_history.items.len));
    }

    pub fn getAverageBandwidth(self: *Self) f32 {
        if (self.bandwidth_history.items.len == 0) return 0.0;

        var total: f32 = 0.0;
        for (self.bandwidth_history.items) |bandwidth| {
            total += bandwidth;
        }
        return total / @as(f32, @floatFromInt(self.bandwidth_history.items.len));
    }

    pub fn generateReport(self: *Self) NetworkDiagnosticsReport {
        return NetworkDiagnosticsReport{
            .average_latency_ms = self.getAverageLatency(),
            .average_packet_loss_percent = self.getAveragePacketLoss(),
            .average_bandwidth_kbps = self.getAverageBandwidth(),
            .connection_quality = self.calculateConnectionQuality(),
        };
    }

    fn calculateConnectionQuality(self: *Self) ConnectionQuality {
        const latency = self.getAverageLatency();
        const packet_loss = self.getAveragePacketLoss();

        if (latency < 50.0 and packet_loss < 1.0) {
            return .excellent;
        } else if (latency < 100.0 and packet_loss < 3.0) {
            return .good;
        } else if (latency < 200.0 and packet_loss < 5.0) {
            return .fair;
        } else {
            return .poor;
        }
    }
};

pub const NetworkDiagnosticsReport = struct {
    average_latency_ms: f32,
    average_packet_loss_percent: f32,
    average_bandwidth_kbps: f32,
    connection_quality: ConnectionQuality,

    pub fn print(self: *const NetworkDiagnosticsReport) void {
        std.log.info("=== Network Diagnostics Report ===", .{});
        std.log.info("Average Latency: {d:.1} ms", .{self.average_latency_ms});
        std.log.info("Average Packet Loss: {d:.2}%", .{self.average_packet_loss_percent});
        std.log.info("Average Bandwidth: {d:.1} KB/s", .{self.average_bandwidth_kbps});
        std.log.info("Connection Quality: {s}", .{@tagName(self.connection_quality)});
    }
};

pub const ConnectionQuality = enum {
    excellent,
    good,
    fair,
    poor,
};
