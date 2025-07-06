//! Network Client Implementation (Stub)

const std = @import("std");
const protocol = @import("protocol.zig");

pub const GameClient = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !GameClient {
        return GameClient{ .allocator = allocator };
    }

    pub fn deinit(self: *GameClient) void {
        _ = self;
    }

    pub fn connect(self: *GameClient, config: ClientConfig) !void {
        _ = self;
        _ = config;
    }

    pub fn update(self: *GameClient, delta_time: f32) !void {
        _ = self;
        _ = delta_time;
    }

    pub fn receiveMessage(self: *GameClient) !?protocol.Message {
        _ = self;
        return null;
    }
};

pub const ClientConfig = struct {
    server_address: []const u8 = "127.0.0.1",
    server_port: u16 = 7777,
    timeout_ms: u32 = 5000,
};
