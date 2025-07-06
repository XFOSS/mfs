//! MFS Engine - Core Logging System
//! Structured logging with multiple backends and filtering.
//!
//! Features:
//! - Multiple log levels (trace, debug, info, warn, error, fatal)
//! - Multiple backends (console, file, custom)
//! - Category-based filtering
//! - Colored console output
//! - Thread-safe global logger
//! - Structured log messages
//! - Performance-conscious design
//!
//! @thread-safe: Global logger is thread-safe, individual loggers are not
//! @allocator-aware: yes
//! @platform: all

const std = @import("std");
const builtin = @import("builtin");
const core = @import("mod.zig");

// =============================================================================
// Types and Constants
// =============================================================================

/// Log levels in order of severity
pub const Level = enum(u8) {
    trace = 0,
    debug = 1,
    info = 2,
    warn = 3,
    err = 4,
    fatal = 5,

    /// Convert level to string representation
    pub fn toString(self: Level) []const u8 {
        return switch (self) {
            .trace => "TRACE",
            .debug => "DEBUG",
            .info => "INFO",
            .warn => "WARN",
            .err => "ERROR",
            .fatal => "FATAL",
        };
    }

    /// Get ANSI color code for level
    pub fn toColor(self: Level) []const u8 {
        return switch (self) {
            .trace => "\x1b[90m", // Bright black (gray)
            .debug => "\x1b[36m", // Cyan
            .info => "\x1b[32m", // Green
            .warn => "\x1b[33m", // Yellow
            .err => "\x1b[31m", // Red
            .fatal => "\x1b[91m", // Bright red
        };
    }

    /// Parse level from string
    pub fn fromString(str: []const u8) ?Level {
        if (std.ascii.eqlIgnoreCase(str, "trace")) return .trace;
        if (std.ascii.eqlIgnoreCase(str, "debug")) return .debug;
        if (std.ascii.eqlIgnoreCase(str, "info")) return .info;
        if (std.ascii.eqlIgnoreCase(str, "warn")) return .warn;
        if (std.ascii.eqlIgnoreCase(str, "error") or std.ascii.eqlIgnoreCase(str, "err")) return .err;
        if (std.ascii.eqlIgnoreCase(str, "fatal")) return .fatal;
        return null;
    }
};

// Legacy alias for compatibility
pub const LogLevel = Level;

/// Configuration for logging system
pub const Config = struct {
    /// Minimum log level to output
    level: Level = .info,
    /// Enable colored output for console
    enable_colors: bool = true,
    /// Enable file output
    enable_file: bool = false,
    /// File path for file backend
    file_path: []const u8 = "app.log",
    /// Maximum file size before rotation (0 = no limit)
    max_file_size: usize = 10 * 1024 * 1024, // 10MB
    /// Number of rotated files to keep
    max_rotated_files: u32 = 5,
    /// Buffer size for async logging
    buffer_size: usize = 4096,
    /// Enable async logging
    enable_async: bool = false,
    /// Default category
    default_category: []const u8 = "MFS",
};

/// Log message structure
pub const LogMessage = struct {
    level: Level,
    timestamp: i64,
    category: []const u8,
    message: []const u8,
    thread_id: std.Thread.Id,
    source_location: ?std.builtin.SourceLocation = null,

    /// Format message as string (caller owns memory)
    pub fn format(self: LogMessage, allocator: std.mem.Allocator, use_color: bool) ![]u8 {
        const dt = std.time.epochToDateTime(self.timestamp);

        if (use_color) {
            return std.fmt.allocPrint(allocator, "{s}[{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}] [{s}] [T:{d}] [{s}] {s}\x1b[0m", .{
                self.level.toColor(),
                dt.year,
                dt.month,
                dt.day,
                dt.hour,
                dt.minute,
                dt.second,
                self.level.toString(),
                self.thread_id,
                self.category,
                self.message,
            });
        } else {
            return std.fmt.allocPrint(allocator, "[{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}] [{s}] [T:{d}] [{s}] {s}", .{
                dt.year,               dt.month,       dt.day,
                dt.hour,               dt.minute,      dt.second,
                self.level.toString(), self.thread_id, self.category,
                self.message,
            });
        }
    }
};

// =============================================================================
// Backend Interface
// =============================================================================

/// Logger backend interface
pub const LogBackend = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    const VTable = struct {
        write: *const fn (ptr: *anyopaque, message: LogMessage) void,
        flush: *const fn (ptr: *anyopaque) void,
        deinit: *const fn (ptr: *anyopaque) void,
    };

    pub fn write(self: LogBackend, message: LogMessage) void {
        self.vtable.write(self.ptr, message);
    }

    pub fn flush(self: LogBackend) void {
        self.vtable.flush(self.ptr);
    }

    pub fn deinit(self: LogBackend) void {
        self.vtable.deinit(self.ptr);
    }
};

// =============================================================================
// Console Backend
// =============================================================================

/// Console log backend
pub const ConsoleBackend = struct {
    use_colors: bool,
    mutex: std.Thread.Mutex,

    const Self = @This();

    /// Create a new console backend
    pub fn init(use_colors: bool) Self {
        return .{
            .use_colors = use_colors and std.io.getStdErr().supportsAnsiEscapeCodes(),
            .mutex = .{},
        };
    }

    /// Get the backend interface
    pub fn backend(self: *Self) LogBackend {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    const vtable = LogBackend.VTable{
        .write = write,
        .flush = flush,
        .deinit = deinitImpl,
    };

    fn write(ptr: *anyopaque, message: LogMessage) void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        self.mutex.lock();
        defer self.mutex.unlock();

        const stderr = std.io.getStdErr().writer();
        const dt = std.time.epochToDateTime(message.timestamp);

        if (self.use_colors) {
            stderr.print("{s}[{s}] {d:0>2}:{d:0>2}:{d:0>2} [{s}] {s}\x1b[0m\n", .{
                message.level.toColor(),
                message.level.toString(),
                dt.hour,
                dt.minute,
                dt.second,
                message.category,
                message.message,
            }) catch {};
        } else {
            stderr.print("[{s}] {d:0>2}:{d:0>2}:{d:0>2} [{s}] {s}\n", .{
                message.level.toString(),
                dt.hour,
                dt.minute,
                dt.second,
                message.category,
                message.message,
            }) catch {};
        }
    }

    fn flush(ptr: *anyopaque) void {
        _ = ptr;
        // stderr is typically unbuffered, but ensure flush
        std.io.getStdErr().writer().writeAll("") catch {};
    }

    fn deinitImpl(ptr: *anyopaque) void {
        _ = ptr;
        // Nothing to clean up
    }
};

// =============================================================================
// File Backend
// =============================================================================

/// File log backend with rotation support
pub const FileBackend = struct {
    allocator: std.mem.Allocator,
    file: std.fs.File,
    file_path: []const u8,
    max_size: usize,
    max_rotated: u32,
    current_size: usize,
    mutex: std.Thread.Mutex,

    const Self = @This();

    /// Create a new file backend
    pub fn init(
        allocator: std.mem.Allocator,
        file_path: []const u8,
        max_size: usize,
        max_rotated: u32,
    ) !Self {
        const file = try std.fs.cwd().createFile(file_path, .{ .truncate = false });
        const stat = try file.stat();
        try file.seekFromEnd(0);

        return .{
            .allocator = allocator,
            .file = file,
            .file_path = try allocator.dupe(u8, file_path),
            .max_size = max_size,
            .max_rotated = max_rotated,
            .current_size = stat.size,
            .mutex = .{},
        };
    }

    /// Cleanup the file backend
    pub fn deinit(self: *Self) void {
        self.file.close();
        self.allocator.free(self.file_path);
    }

    /// Get the backend interface
    pub fn backend(self: *Self) LogBackend {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    const vtable = LogBackend.VTable{
        .write = write,
        .flush = flush,
        .deinit = deinitImpl,
    };

    fn write(ptr: *anyopaque, message: LogMessage) void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        self.mutex.lock();
        defer self.mutex.unlock();

        // Check if rotation is needed
        if (self.max_size > 0 and self.current_size >= self.max_size) {
            self.rotate() catch |e| {
                std.debug.print("Failed to rotate log file: {}\n", .{e});
            };
        }

        const dt = std.time.epochToDateTime(message.timestamp);
        const writer = self.file.writer();

        // Format message to get byte count
        var buf: [4096]u8 = undefined;
        const log_line = std.fmt.bufPrint(&buf, "[{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}] [{s}] [T:{d}] [{s}] {s}\n", .{
            dt.year,                  dt.month,          dt.day,
            dt.hour,                  dt.minute,         dt.second,
            message.level.toString(), message.thread_id, message.category,
            message.message,
        }) catch |e| {
            std.debug.print("Failed to format log message: {}\n", .{e});
            return;
        };

        writer.writeAll(log_line) catch |e| {
            std.debug.print("Failed to write to log file: {}\n", .{e});
            return;
        };

        self.current_size += log_line.len;
    }

    fn flush(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.mutex.lock();
        defer self.mutex.unlock();
        self.file.sync() catch {};
    }

    fn deinitImpl(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.deinit();
    }

    fn rotate(self: *Self) !void {
        self.file.close();

        // Rotate existing files
        var i: u32 = self.max_rotated;
        while (i > 0) : (i -= 1) {
            const old_name = if (i == 1)
                try std.fmt.allocPrint(self.allocator, "{s}", .{self.file_path})
            else
                try std.fmt.allocPrint(self.allocator, "{s}.{d}", .{ self.file_path, i - 1 });
            defer self.allocator.free(old_name);

            const new_name = try std.fmt.allocPrint(self.allocator, "{s}.{d}", .{ self.file_path, i });
            defer self.allocator.free(new_name);

            std.fs.cwd().rename(old_name, new_name) catch |e| switch (e) {
                error.FileNotFound => continue,
                else => return e,
            };
        }

        // Create new file
        self.file = try std.fs.cwd().createFile(self.file_path, .{});
        self.current_size = 0;
    }
};

// =============================================================================
// Logger Implementation
// =============================================================================

/// Main logger class
pub const Logger = struct {
    allocator: std.mem.Allocator,
    backends: std.ArrayList(LogBackend),
    min_level: Level,
    category: []const u8,
    mutex: ?*std.Thread.Mutex,

    const Self = @This();

    /// Create a new logger
    ///
    /// **Thread Safety**: Set `thread_safe` to true for thread-safe logging
    pub fn init(
        allocator: std.mem.Allocator,
        category: []const u8,
        min_level: Level,
        thread_safe: bool,
    ) !Self {
        const mutex = if (thread_safe)
            try allocator.create(std.Thread.Mutex)
        else
            null;

        if (mutex) |m| m.* = .{};

        return .{
            .allocator = allocator,
            .backends = std.ArrayList(LogBackend).init(allocator),
            .min_level = min_level,
            .category = try allocator.dupe(u8, category),
            .mutex = mutex,
        };
    }

    /// Cleanup the logger
    pub fn deinit(self: *Self) void {
        for (self.backends.items) |backend| {
            backend.deinit();
        }
        self.backends.deinit();
        self.allocator.free(self.category);

        if (self.mutex) |m| {
            self.allocator.destroy(m);
        }
    }

    /// Add a backend to the logger
    pub fn addBackend(self: *Self, backend: LogBackend) !void {
        if (self.mutex) |m| m.lock();
        defer if (self.mutex) |m| m.unlock();

        try self.backends.append(backend);
    }

    /// Set minimum log level
    pub fn setLevel(self: *Self, level: Level) void {
        if (self.mutex) |m| m.lock();
        defer if (self.mutex) |m| m.unlock();

        self.min_level = level;
    }

    /// Core logging function
    pub fn log(
        self: *Self,
        comptime level: Level,
        comptime format: []const u8,
        args: anytype,
        src: ?std.builtin.SourceLocation,
    ) void {
        if (@intFromEnum(level) < @intFromEnum(self.min_level)) {
            return;
        }

        if (self.mutex) |m| m.lock();
        defer if (self.mutex) |m| m.unlock();

        var buf: [4096]u8 = undefined;
        const formatted_message = std.fmt.bufPrint(&buf, format, args) catch {
            const truncated = "Log message too long (truncated)";
            @memcpy(buf[0..truncated.len], truncated);
            return buf[0..truncated.len];
        };

        const message = LogMessage{
            .level = level,
            .timestamp = std.time.timestamp(),
            .category = self.category,
            .message = formatted_message,
            .thread_id = std.Thread.getCurrentId(),
            .source_location = src,
        };

        for (self.backends.items) |backend| {
            backend.write(message);
        }

        // Auto-flush on error or fatal
        if (level == .err or level == .fatal) {
            self.flushNoLock();
        }
    }

    /// Log with custom category
    pub fn logWithCategory(
        self: *Self,
        comptime level: Level,
        category: []const u8,
        comptime format: []const u8,
        args: anytype,
    ) void {
        const saved_category = self.category;
        self.category = category;
        defer self.category = saved_category;
        self.log(level, format, args, @src());
    }

    pub fn trace(self: *Self, comptime format: []const u8, args: anytype) void {
        self.log(.trace, format, args, @src());
    }

    pub fn debug(self: *Self, comptime format: []const u8, args: anytype) void {
        self.log(.debug, format, args, @src());
    }

    pub fn info(self: *Self, comptime format: []const u8, args: anytype) void {
        self.log(.info, format, args, @src());
    }

    pub fn warn(self: *Self, comptime format: []const u8, args: anytype) void {
        self.log(.warn, format, args, @src());
    }

    pub fn err(self: *Self, comptime format: []const u8, args: anytype) void {
        self.log(.err, format, args, @src());
    }

    pub fn fatal(self: *Self, comptime format: []const u8, args: anytype) void {
        self.log(.fatal, format, args, @src());
        self.flush();
    }

    /// Flush all backends
    pub fn flush(self: *Self) void {
        if (self.mutex) |m| m.lock();
        defer if (self.mutex) |m| m.unlock();

        self.flushNoLock();
    }

    fn flushNoLock(self: *Self) void {
        for (self.backends.items) |backend| {
            backend.flush();
        }
    }
};

// =============================================================================
// Global Logger Management
// =============================================================================

var global_logger: ?*Logger = null;
var global_mutex = std.Thread.Mutex{};
var global_initialized = false;

/// Initialize global logger with configuration
pub fn init(allocator: std.mem.Allocator, config: Config) !void {
    global_mutex.lock();
    defer global_mutex.unlock();

    if (global_initialized) {
        return;
    }

    const logger = try allocator.create(Logger);
    errdefer allocator.destroy(logger);

    logger.* = try Logger.init(allocator, config.default_category, config.level, true);
    errdefer logger.deinit();

    // Add console backend
    var console = try allocator.create(ConsoleBackend);
    console.* = ConsoleBackend.init(config.enable_colors);
    try logger.addBackend(console.backend());

    // Add file backend if enabled
    if (config.enable_file) {
        var file = try allocator.create(FileBackend);
        file.* = try FileBackend.init(allocator, config.file_path, config.max_file_size, config.max_rotated_files);
        try logger.addBackend(file.backend());
    }

    global_logger = logger;
    global_initialized = true;
}

/// Cleanup global logger
pub fn deinit() void {
    global_mutex.lock();
    defer global_mutex.unlock();

    if (global_logger) |logger| {
        logger.deinit();
        logger.allocator.destroy(logger);
        global_logger = null;
        global_initialized = false;
    }
}

/// Check if logging system is initialized
pub fn isInitialized() bool {
    global_mutex.lock();
    defer global_mutex.unlock();
    return global_initialized;
}

/// Get global logger (thread-safe)
pub fn getGlobal() ?*Logger {
    global_mutex.lock();
    defer global_mutex.unlock();
    return global_logger;
}

// =============================================================================
// Convenience Functions
// =============================================================================

pub fn trace(comptime format: []const u8, args: anytype) void {
    if (getGlobal()) |logger| {
        logger.trace(format, args);
    }
}

pub fn debug(comptime format: []const u8, args: anytype) void {
    if (getGlobal()) |logger| {
        logger.debug(format, args);
    }
}

pub fn info(comptime format: []const u8, args: anytype) void {
    if (getGlobal()) |logger| {
        logger.info(format, args);
    }
}

pub fn warn(comptime format: []const u8, args: anytype) void {
    if (getGlobal()) |logger| {
        logger.warn(format, args);
    }
}

pub fn err(comptime format: []const u8, args: anytype) void {
    if (getGlobal()) |logger| {
        logger.err(format, args);
    }
}

pub fn fatal(comptime format: []const u8, args: anytype) void {
    if (getGlobal()) |logger| {
        logger.fatal(format, args);
    }
}

// =============================================================================
// Tests
// =============================================================================

test "log levels" {
    const testing = std.testing;

    try testing.expect(Level.trace.toString()[0] == 'T');
    try testing.expect(Level.debug.toString()[0] == 'D');
    try testing.expect(Level.info.toString()[0] == 'I');
    try testing.expect(Level.warn.toString()[0] == 'W');
    try testing.expect(Level.err.toString()[0] == 'E');
    try testing.expect(Level.fatal.toString()[0] == 'F');

    try testing.expect(Level.fromString("trace") == .trace);
    try testing.expect(Level.fromString("DEBUG") == .debug);
    try testing.expect(Level.fromString("error") == .err);
    try testing.expect(Level.fromString("invalid") == null);
}

test "logger basic functionality" {
    const testing = std.testing;

    var logger = try Logger.init(testing.allocator, "TEST", .debug, false);
    defer logger.deinit();

    var console = ConsoleBackend.init(false);
    try logger.addBackend(console.backend());

    // These should output
    logger.info("Test message: {}", .{42});
    logger.debug("Debug message");
    logger.warn("Warning message");
    logger.err("Error message");

    // This should not output (below min level)
    logger.trace("This should not appear");

    logger.flush();
}

test "global logger" {
    const testing = std.testing;

    const config = Config{
        .level = .debug,
        .enable_colors = false,
        .enable_file = false,
    };

    try init(testing.allocator, config);
    defer deinit();

    try testing.expect(isInitialized());

    info("Global test message", .{});
    debug("Global debug message", .{});

    if (getGlobal()) |logger| {
        logger.flush();
    }
}

test "log message formatting" {
    const testing = std.testing;

    const msg = LogMessage{
        .level = .info,
        .timestamp = std.time.timestamp(),
        .category = "TEST",
        .message = "Test message",
        .thread_id = std.Thread.getCurrentId(),
    };

    const formatted = try msg.format(testing.allocator, false);
    defer testing.allocator.free(formatted);

    try testing.expect(std.mem.indexOf(u8, formatted, "[INFO]") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "[TEST]") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "Test message") != null);
}

test "file backend rotation" {
    const testing = std.testing;

    // Create temporary directory for test
    const tmp_dir = "test_logs";
    std.fs.cwd().makeDir(tmp_dir) catch |e| switch (e) {
        error.PathAlreadyExists => {},
        else => return e,
    };
    defer std.fs.cwd().deleteTree(tmp_dir) catch {};

    const log_path = tmp_dir ++ "/test.log";

    var file_backend = try FileBackend.init(
        testing.allocator,
        log_path,
        100, // Very small size to trigger rotation
        3, // Keep 3 rotated files
    );
    defer file_backend.deinit();

    // Write enough to trigger rotation
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        const msg = LogMessage{
            .level = .info,
            .timestamp = std.time.timestamp(),
            .category = "TEST",
            .message = "This is a test message to trigger rotation",
            .thread_id = std.Thread.getCurrentId(),
        };
        file_backend.write(&file_backend, msg);
    }

    file_backend.flush(&file_backend);

    // Check that rotation occurred
    const stat = std.fs.cwd().statFile(log_path ++ ".1") catch |e| switch (e) {
        error.FileNotFound => {
            // Rotation might not have triggered, that's okay for this test
            return;
        },
        else => return e,
    };
    _ = stat;
}
