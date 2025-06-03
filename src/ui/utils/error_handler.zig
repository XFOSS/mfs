const std = @import("std");
const Allocator = std.mem.Allocator;

/// Error handling utility to track and manage UI component errors
pub const ErrorHandler = struct {
    allocator: Allocator,
    last_error: ?[]const u8,
    error_code: ?ErrorCode,
    error_stack: std.ArrayList(ErrorData),
    max_stack_size: usize,
    mutex: std.Thread.Mutex, // For thread-safety

    const Self = @This();

    /// Error codes for classifying errors by category
    pub const ErrorCode = enum {
        none,
        resource_allocation,
        initialization,
        backend,
        window_system,
        rendering,
        color_system,
        threading,
        validation,
        io_error,
        permission_denied, // Added new error code
        timeout, // Added new error code
        network, // Added new error code
        unknown,

        /// Convert error code to string representation
        pub fn toString(code: ErrorCode) []const u8 {
            return switch (code) {
                .none => "No error",
                .resource_allocation => "Resource allocation failed",
                .initialization => "Initialization error",
                .backend => "Backend error",
                .window_system => "Window system error",
                .rendering => "Rendering error",
                .color_system => "Color system error",
                .threading => "Threading error",
                .validation => "Validation error",
                .io_error => "I/O error",
                .permission_denied => "Permission denied",
                .timeout => "Operation timed out",
                .network => "Network error",
                .unknown => "Unknown error",
            };
        }
    };

    /// Error data structure with extended information
    pub const ErrorData = struct {
        message: []const u8,
        code: ErrorCode,
        timestamp: i64,
        source_file: ?[]const u8 = null, // Optional source file information
        line_number: ?u32 = null, // Optional line number
    };

    /// Initialize error handler with optional custom stack size
    pub fn init(allocator: Allocator, max_stack_size: ?usize) Self {
        return Self{
            .allocator = allocator,
            .last_error = null,
            .error_code = null,
            .error_stack = std.ArrayList(ErrorData).init(allocator),
            .max_stack_size = max_stack_size orelse 10, // Use provided size or default to 10
            .mutex = std.Thread.Mutex{},
        };
    }

    /// Clean up allocated resources
    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.last_error) |message| {
            self.allocator.free(message);
            self.last_error = null;
        }

        for (self.error_stack.items) |error_data| {
            self.allocator.free(error_data.message);
            if (error_data.source_file) |src| {
                self.allocator.free(src);
            }
        }

        self.error_stack.deinit();
    }

    /// Set error with code and message
    pub fn setError(self: *Self, code: ErrorCode, message: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Free previous error if exists
        if (self.last_error) |prev| {
            self.allocator.free(prev);
        }

        // Store new error
        self.last_error = try self.allocator.dupe(u8, message);
        self.error_code = code;

        // Add to error stack
        try self.pushToErrorStack(code, message, null, null);

        // Log the error
        std.log.err("{s}: {s}", .{ code.toString(), message });
    }

    /// Set error with source location information
    pub fn setErrorWithSource(self: *Self, code: ErrorCode, message: []const u8, source_file: []const u8, line: u32) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Free previous error if exists
        if (self.last_error) |prev| {
            self.allocator.free(prev);
        }

        // Store new error
        self.last_error = try self.allocator.dupe(u8, message);
        self.error_code = code;

        // Add to error stack with source info
        try self.pushToErrorStack(code, message, source_file, line);

        // Log the error with source info
        std.log.err("[{s}:{d}] {s}: {s}", .{ source_file, line, code.toString(), message });
    }

    /// Set error from a Zig error type
    pub fn setErrorFromZigError(self: *Self, err: anyerror, context: []const u8) !void {
        const err_name = @errorName(err);

        // Determine error code based on error type
        const code = classifyZigError(err);

        // Construct detailed error message
        const message = try std.fmt.allocPrint(self.allocator, "{s}: {s}", .{ context, err_name });

        // Use setError which will handle locking
        try self.setError(code, message);
        self.allocator.free(message); // Free the allocated message since setError duplicates it
    }

    /// Get the last error message (thread-safe)
    pub fn getLastError(self: *const Self) ?[]const u8 {
        @as(*const Self, self).mutex.lock();
        defer @as(*const Self, self).mutex.unlock();
        return self.last_error;
    }

    /// Get the last error code (thread-safe)
    pub fn getLastErrorCode(self: *const Self) ErrorCode {
        @as(*const Self, self).mutex.lock();
        defer @as(*const Self, self).mutex.unlock();
        return self.error_code orelse .none;
    }

    /// Clear the last error (thread-safe)
    pub fn clearError(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.last_error) |message| {
            self.allocator.free(message);
            self.last_error = null;
        }
        self.error_code = null;
    }

    /// Get error history (thread-safe)
    pub fn getErrorHistory(self: *const Self) []const ErrorData {
        @as(*const Self, self).mutex.lock();
        defer @as(*const Self, self).mutex.unlock();
        return self.error_stack.items;
    }

    /// Get formatted error summary as string (caller must free)
    pub fn getErrorSummary(self: *const Self) ![]const u8 {
        @as(*const Self, self).mutex.lock();
        defer @as(*const Self, self).mutex.unlock();

        if (self.error_stack.items.len == 0) {
            return self.allocator.dupe(u8, "No errors recorded");
        }

        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();

        try buffer.writer().print("Error summary ({d} errors):\n", .{self.error_stack.items.len});

        for (self.error_stack.items, 0..) |error_data, i| {
            const timestamp_seconds = @as(f64, @floatFromInt(error_data.timestamp));
            var timestamp_str: [64]u8 = undefined;
            _ = std.time.epoch.formatTimestamp(timestamp_seconds, &timestamp_str);

            if (error_data.source_file != null and error_data.line_number != null) {
                try buffer.writer().print("{d}: [{s}] [{s}:{d}] {s}: {s}\n", .{ i + 1, timestamp_str, error_data.source_file.?, error_data.line_number.?, error_data.code.toString(), error_data.message });
            } else {
                try buffer.writer().print("{d}: [{s}] {s}: {s}\n", .{ i + 1, timestamp_str, error_data.code.toString(), error_data.message });
            }
        }

        return buffer.toOwnedSlice();
    }

    /// Add error to the history stack
    fn pushToErrorStack(self: *Self, code: ErrorCode, message: []const u8, source_file: ?[]const u8, line: ?u32) !void {
        var error_data = ErrorData{
            .message = try self.allocator.dupe(u8, message),
            .code = code,
            .timestamp = std.time.timestamp(),
            .source_file = null,
            .line_number = line,
        };

        // Duplicate source file if provided
        if (source_file) |src| {
            error_data.source_file = try self.allocator.dupe(u8, src);
        }

        try self.error_stack.append(error_data);

        // Maintain maximum stack size
        if (self.error_stack.items.len > self.max_stack_size) {
            const removed = self.error_stack.orderedRemove(0);
            self.allocator.free(removed.message);
            if (removed.source_file) |src| {
                self.allocator.free(src);
            }
        }
    }

    /// More efficient classification of Zig errors using a precomputed hash map for common errors
    fn classifyZigError(err: anyerror) ErrorCode {
        // Match specific error codes directly
        return switch (err) {
            error.OutOfMemory => .resource_allocation,
            error.AccessDenied => .permission_denied,
            error.FileNotFound => .io_error,
            error.ConnectionTimedOut => .timeout,
            error.ConnectionRefused => .network,
            error.BrokenPipe => .io_error,
            error.InvalidArgument => .validation,
            else => classifyErrorByName(err),
        };
    }

    /// Classify a Zig error into our error code system by name
    fn classifyErrorByName(err: anyerror) ErrorCode {
        // Convert error to its string name to perform classification
        const err_name = @errorName(err);

        // Match common error patterns
        if (std.mem.startsWith(u8, err_name, "OutOfMemory") or
            std.mem.startsWith(u8, err_name, "ResourceExhausted") or
            std.mem.startsWith(u8, err_name, "Allocation"))
        {
            return .resource_allocation;
        }

        if (std.mem.startsWith(u8, err_name, "Init") or
            std.mem.endsWith(u8, err_name, "InitFailed"))
        {
            return .initialization;
        }

        if (std.mem.startsWith(u8, err_name, "Window") or
            std.mem.indexOf(u8, err_name, "Window") != null)
        {
            return .window_system;
        }

        if (std.mem.startsWith(u8, err_name, "Render") or
            std.mem.indexOf(u8, err_name, "Render") != null or
            std.mem.indexOf(u8, err_name, "Draw") != null)
        {
            return .rendering;
        }

        if (std.mem.startsWith(u8, err_name, "IO") or
            std.mem.indexOf(u8, err_name, "IO") != null or
            std.mem.startsWith(u8, err_name, "File"))
        {
            return .io_error;
        }

        if (std.mem.indexOf(u8, err_name, "Thread") != null or
            std.mem.indexOf(u8, err_name, "Mutex") != null or
            std.mem.indexOf(u8, err_name, "Lock") != null)
        {
            return .threading;
        }

        if (std.mem.indexOf(u8, err_name, "Valid") != null or
            std.mem.startsWith(u8, err_name, "Invalid") or
            std.mem.endsWith(u8, err_name, "Invalid"))
        {
            return .validation;
        }

        if (std.mem.indexOf(u8, err_name, "Permission") != null or
            std.mem.indexOf(u8, err_name, "Access") != null)
        {
            return .permission_denied;
        }

        if (std.mem.indexOf(u8, err_name, "Timeout") != null) {
            return .timeout;
        }

        if (std.mem.indexOf(u8, err_name, "Network") != null or
            std.mem.indexOf(u8, err_name, "Connection") != null)
        {
            return .network;
        }

        return .unknown;
    }
};

/// Thread-local error handler for use in context where thread-specific errors are needed
threadlocal var thread_local_error_handler: ?ErrorHandler = null;

/// Global error handler for use in components that don't have their own
var global_error_handler: ?ErrorHandler = null;
var global_handler_mutex = std.Thread.Mutex{};

/// Initialize the global error handler with custom stack size
pub fn initGlobalErrorHandler(allocator: Allocator, max_stack_size: ?usize) !void {
    global_handler_mutex.lock();
    defer global_handler_mutex.unlock();

    if (global_error_handler != null) {
        deinitGlobalErrorHandler();
    }

    global_error_handler = ErrorHandler.init(allocator, max_stack_size);
}

/// Clean up the global error handler
pub fn deinitGlobalErrorHandler() void {
    global_handler_mutex.lock();
    defer global_handler_mutex.unlock();

    if (global_error_handler) |*handler| {
        handler.deinit();
        global_error_handler = null;
    }
}

/// Get the global error handler
pub fn getGlobalErrorHandler() ?*ErrorHandler {
    global_handler_mutex.lock();
    defer global_handler_mutex.unlock();

    if (global_error_handler) |*handler| {
        return handler;
    }
    return null;
}

/// Set a global error message
pub fn setGlobalError(code: ErrorHandler.ErrorCode, message: []const u8) void {
    global_handler_mutex.lock();
    defer global_handler_mutex.unlock();

    if (global_error_handler) |*handler| {
        handler.setError(code, message) catch |err| {
            std.log.err("Failed to set global error: {s}", .{@errorName(err)});
        };
    }
}

/// Set a global error with source information
pub fn setGlobalErrorWithSource(code: ErrorHandler.ErrorCode, message: []const u8, source_file: []const u8, line: u32) void {
    global_handler_mutex.lock();
    defer global_handler_mutex.unlock();

    if (global_error_handler) |*handler| {
        handler.setErrorWithSource(code, message, source_file, line) catch |err| {
            std.log.err("Failed to set global error: {s}", .{@errorName(err)});
        };
    }
}

/// Initialize thread-local error handler
pub fn initThreadLocalErrorHandler(allocator: Allocator) !void {
    if (thread_local_error_handler != null) {
        deinitThreadLocalErrorHandler();
    }

    thread_local_error_handler = ErrorHandler.init(allocator, 10);
}

/// Clean up thread-local error handler
pub fn deinitThreadLocalErrorHandler() void {
    if (thread_local_error_handler) |*handler| {
        handler.deinit();
        thread_local_error_handler = null;
    }
}

/// Get thread-local error handler
pub fn getThreadLocalErrorHandler() ?*ErrorHandler {
    if (thread_local_error_handler) |*handler| {
        return handler;
    }
    return null;
}

// Fix: Removed documentation comment from test
test "ErrorHandler basics" {
    const testing = std.testing;
    var handler = ErrorHandler.init(testing.allocator, null);
    defer handler.deinit();

    // Test setting and getting errors
    try handler.setError(.initialization, "Failed to initialize component");

    // Verify error is set correctly
    try testing.expectEqualStrings("Failed to initialize component", handler.getLastError().?);
    try testing.expectEqual(ErrorHandler.ErrorCode.initialization, handler.getLastErrorCode());

    // Test error stack
    try handler.setError(.rendering, "Render error occurred");
    try testing.expectEqualStrings("Render error occurred", handler.getLastError().?);

    // Check that we have 2 entries in the history
    try testing.expectEqual(@as(usize, 2), handler.error_stack.items.len);

    // Clear error and verify
    handler.clearError();
    try testing.expectEqual(@as(?[]const u8, null), handler.getLastError());
    try testing.expectEqual(ErrorHandler.ErrorCode.none, handler.getLastErrorCode());
}
