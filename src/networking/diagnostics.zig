const std = @import("std");

pub const ConnectionQuality = enum {
    excellent,
    good,
    fair,
    poor,
    critical,
};

pub const NetworkStats = struct {
    bytes_sent: u64 = 0,
    bytes_received: u64 = 0,
    packets_sent: u64 = 0,
    packets_received: u64 = 0,
    packets_lost: u64 = 0,
    latency_ms: f32 = 0.0,
    jitter_ms: f32 = 0.0,
    bandwidth_up: f32 = 0.0,
    bandwidth_down: f32 = 0.0,
};

pub const DiagnosticsConfig = struct {
    update_interval_ms: u32 = 1000,
    history_size: u32 = 60,
    enable_detailed_logging: bool = false,
};

pub const NetworkDiagnostics = struct {
    allocator: std.mem.Allocator,
    config: DiagnosticsConfig,
    stats: NetworkStats,
    start_time: i64,
    last_update: i64,

    pub fn init(allocator: std.mem.Allocator, config: DiagnosticsConfig) NetworkDiagnostics {
        const now = std.time.milliTimestamp();
        return NetworkDiagnostics{
            .allocator = allocator,
            .config = config,
            .stats = NetworkStats{},
            .start_time = now,
            .last_update = now,
        };
    }

    pub fn update(self: *NetworkDiagnostics) void {
        self.last_update = std.time.milliTimestamp();
        // TODO: Update network statistics
    }

    pub fn recordPacketSent(self: *NetworkDiagnostics, size: u32) void {
        self.stats.packets_sent += 1;
        self.stats.bytes_sent += size;
    }

    pub fn recordPacketReceived(self: *NetworkDiagnostics, size: u32) void {
        self.stats.packets_received += 1;
        self.stats.bytes_received += size;
    }

    pub fn recordPacketLost(self: *NetworkDiagnostics) void {
        self.stats.packets_lost += 1;
    }

    pub fn updateLatency(self: *NetworkDiagnostics, latency_ms: f32) void {
        self.stats.latency_ms = latency_ms;
    }

    pub fn updateJitter(self: *NetworkDiagnostics, jitter_ms: f32) void {
        self.stats.jitter_ms = jitter_ms;
    }

    pub fn getConnectionQuality(self: *const NetworkDiagnostics) ConnectionQuality {
        if (self.stats.latency_ms < 50 and self.stats.packets_lost == 0) {
            return .excellent;
        } else if (self.stats.latency_ms < 100 and self.stats.packets_lost < 5) {
            return .good;
        } else if (self.stats.latency_ms < 200 and self.stats.packets_lost < 15) {
            return .fair;
        } else if (self.stats.latency_ms < 500) {
            return .poor;
        } else {
            return .critical;
        }
    }

    pub fn getStats(self: *const NetworkDiagnostics) NetworkStats {
        return self.stats;
    }

    pub fn getUptime(self: *const NetworkDiagnostics) i64 {
        return std.time.milliTimestamp() - self.start_time;
    }

    pub fn reset(self: *NetworkDiagnostics) void {
        self.stats = NetworkStats{};
        self.start_time = std.time.milliTimestamp();
    }

    pub fn deinit(_: *NetworkDiagnostics) void {
        // Nothing to clean up in stub
    }
};
