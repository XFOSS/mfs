//! Network server module for MFS Engine
//! Handles server-side networking for multiplayer games

const std = @import("std");

pub const ServerError = error{
    BindFailed,
    ListenFailed,
    AcceptFailed,
    SendFailed,
    ReceiveFailed,
    ClientDisconnected,
};

pub const ClientConnection = struct {
    id: u32,
    socket: std.net.Stream,
    address: std.net.Address,
    connected: bool,
    last_ping: i64,

    pub fn init(id: u32, socket: std.net.Stream, address: std.net.Address) ClientConnection {
        return ClientConnection{
            .id = id,
            .socket = socket,
            .address = address,
            .connected = true,
            .last_ping = std.time.timestamp(),
        };
    }

    pub fn send(self: *ClientConnection, data: []const u8) ServerError!void {
        _ = self.socket.writeAll(data) catch return ServerError.SendFailed;
    }

    pub fn receive(self: *ClientConnection, buffer: []u8) ServerError!usize {
        return self.socket.read(buffer) catch return ServerError.ReceiveFailed;
    }

    pub fn disconnect(self: *ClientConnection) void {
        self.socket.close();
        self.connected = false;
    }

    pub fn updatePing(self: *ClientConnection) void {
        self.last_ping = std.time.timestamp();
    }
};

pub const NetworkServer = struct {
    socket: std.net.StreamServer,
    clients: std.ArrayList(ClientConnection),
    allocator: std.mem.Allocator,
    port: u16,
    running: bool,
    max_clients: u32,

    pub fn init(allocator: std.mem.Allocator, port: u16, max_clients: u32) NetworkServer {
        return NetworkServer{
            .socket = undefined,
            .clients = std.ArrayList(ClientConnection).init(allocator),
            .allocator = allocator,
            .port = port,
            .running = false,
            .max_clients = max_clients,
        };
    }

    pub fn deinit(self: *NetworkServer) void {
        self.stop();
        for (self.clients.items) |*client| {
            client.disconnect();
        }
        self.clients.deinit();
    }

    pub fn start(self: *NetworkServer) ServerError!void {
        const address = std.net.Address.initIp4([_]u8{ 0, 0, 0, 0 }, self.port);

        self.socket = std.net.StreamServer.init(.{});
        self.socket.listen(address) catch return ServerError.ListenFailed;

        self.running = true;
        std.log.info("Server started on port {}", .{self.port});
    }

    pub fn stop(self: *NetworkServer) void {
        if (self.running) {
            self.socket.deinit();
            self.running = false;
            std.log.info("Server stopped", .{});
        }
    }

    pub fn acceptClient(self: *NetworkServer) ServerError!?u32 {
        if (!self.running) return null;
        if (self.clients.items.len >= self.max_clients) return null;

        const connection = self.socket.accept() catch return ServerError.AcceptFailed;

        const client_id = @as(u32, @intCast(self.clients.items.len));
        const client = ClientConnection.init(client_id, connection.stream, connection.address);

        self.clients.append(client) catch return ServerError.AcceptFailed;

        std.log.info("Client {} connected from {}", .{ client_id, connection.address });
        return client_id;
    }

    pub fn broadcastMessage(self: *NetworkServer, message: []const u8) void {
        for (self.clients.items) |*client| {
            if (client.connected) {
                client.send(message) catch |err| {
                    std.log.warn("Failed to send message to client {}: {}", .{ client.id, err });
                    client.disconnect();
                };
            }
        }
    }

    pub fn sendToClient(self: *NetworkServer, client_id: u32, message: []const u8) ServerError!void {
        if (client_id >= self.clients.items.len) return ServerError.ClientDisconnected;

        var client = &self.clients.items[client_id];
        if (!client.connected) return ServerError.ClientDisconnected;

        try client.send(message);
    }

    pub fn update(self: *NetworkServer) void {
        const current_time = std.time.timestamp();

        // Check for disconnected clients (timeout after 30 seconds)
        for (self.clients.items) |*client| {
            if (client.connected and current_time - client.last_ping > 30) {
                std.log.info("Client {} timed out", .{client.id});
                client.disconnect();
            }
        }
    }

    pub fn getConnectedClients(self: *NetworkServer) u32 {
        var count: u32 = 0;
        for (self.clients.items) |client| {
            if (client.connected) count += 1;
        }
        return count;
    }
};
