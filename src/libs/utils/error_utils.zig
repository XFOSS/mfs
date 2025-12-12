//! Enhanced Error Handling Utilities
//! Provides comprehensive error management, logging, and recovery mechanisms
//! @thread-safe All error handling operations are thread-safe
//! @symbol Public error handling API

const std = @import("std");
const builtin = @import("builtin");
const log = std.log.scoped(.error_utils);

/// Enhanced error context with stack traces and debugging information
pub const ErrorContext = struct {
    error_code: anyerror,
    message: []const u8,
    source_location: std.builtin.SourceLocation,
    timestamp: i128,
    thread_id: std.Thread.Id,
    stack_trace: ?[]usize = null,

    pub fn init(
        err: anyerror,
        message: []const u8,
        source_location: std.builtin.SourceLocation,
        allocator: ?std.mem.Allocator,
    ) ErrorContext {
        var context = ErrorContext{
            .error_code = err,
            .message = message,
            .source_location = source_location,
            .timestamp = std.time.nanoTimestamp(),
            .thread_id = std.Thread.getCurrentId(),
        };

        // Capture stack trace if allocator is provided
        if (allocator) |alloc| {
            if (builtin.mode == .Debug) {
                context.captureStackTrace(alloc) catch {};
            }
        }

        return context;
    }

    pub fn deinit(self: *ErrorContext, allocator: std.mem.Allocator) void {
        if (self.stack_trace) |trace| {
            allocator.free(trace);
        }
    }

    fn captureStackTrace(self: *ErrorContext, allocator: std.mem.Allocator) !void {
        const max_frames = 32;
        var addresses = try allocator.alloc(usize, max_frames);
        var stack_trace = std.builtin.StackTrace{
            .instruction_addresses = addresses,
            .index = 0,
        };
        std.debug.captureStackTrace(@returnAddress(), &stack_trace);
        self.stack_trace = addresses[0..stack_trace.index];
    }

    pub fn format(
        self: ErrorContext,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("Error: {s} at {s}:{d}:{d}\n", .{
            @errorName(self.error_code),
            self.source_location.file,
            self.source_location.line,
            self.source_location.column,
        });

        try writer.print("Message: {s}\n", .{self.message});
        try writer.print("Thread: {}\n", .{self.thread_id});
        try writer.print("Timestamp: {d}\n", .{self.timestamp});

        if (self.stack_trace) |trace| {
            try writer.print("Stack trace:\n", .{});
            for (trace, 0..) |addr, i| {
                try writer.print("  #{d}: 0x{x}\n", .{ i, addr });
            }
        }
    }
};

/// Error recovery strategy
pub const RecoveryStrategy = enum {
    abort, // Terminate the program
    retry, // Retry the operation
    fallback, // Use fallback mechanism
    ignore, // Log and continue
    user_prompt, // Ask user for decision
    graceful_degrade, // Reduce functionality
};

/// Error severity levels
pub const ErrorSeverity = enum(u8) {
    trace = 0,
    debug = 1,
    info = 2,
    warn = 3,
    err = 4,
    fatal = 5,

    pub fn toString(self: ErrorSeverity) []const u8 {
        return switch (self) {
            .trace => "TRACE",
            .debug => "DEBUG",
            .info => "INFO",
            .warn => "WARN",
            .err => "ERROR",
            .fatal => "FATAL",
        };
    }

    pub fn toLogLevel(self: ErrorSeverity) std.log.Level {
        return switch (self) {
            .trace, .debug => .debug,
            .info => .info,
            .warn => .warn,
            .err => .err,
            .fatal => .err,
        };
    }
};

/// Enhanced error handler with recovery mechanisms
pub const ErrorHandler = struct {
    allocator: std.mem.Allocator,
    error_log: std.ArrayList(ErrorContext),
    recovery_strategies: std.AutoHashMap(anyerror, RecoveryStrategy),
    error_callbacks: std.ArrayList(ErrorCallback),
    mutex: std.Thread.Mutex = .{},

    // Statistics
    total_errors: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    errors_by_severity: [6]std.atomic.Value(u64) = [_]std.atomic.Value(u64){
        std.atomic.Value(u64).init(0),
        std.atomic.Value(u64).init(0),
        std.atomic.Value(u64).init(0),
        std.atomic.Value(u64).init(0),
        std.atomic.Value(u64).init(0),
        std.atomic.Value(u64).init(0),
    },

    const ErrorCallback = struct {
        callback: *const fn (ErrorContext, *anyopaque) void,
        context: *anyopaque,
        severity_filter: ErrorSeverity,
    };

    pub fn init(allocator: std.mem.Allocator) !ErrorHandler {
        return ErrorHandler{
            .allocator = allocator,
            .error_log = std.ArrayList(ErrorContext).init(allocator),
            .recovery_strategies = std.AutoHashMap(anyerror, RecoveryStrategy).init(allocator),
            .error_callbacks = std.ArrayList(ErrorCallback).init(allocator),
        };
    }

    pub fn deinit(self: *ErrorHandler) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.error_log.items) |*ctx| {
            ctx.deinit();
        }
        self.error_log.deinit();
        self.recovery_strategies.deinit();
        self.error_callbacks.deinit();
    }

    /// Register a recovery strategy for a specific error type
    pub fn setRecoveryStrategy(self: *ErrorHandler, err: anyerror, strategy: RecoveryStrategy) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.recovery_strategies.put(err, strategy);
    }

    /// Register an error callback
    pub fn addErrorCallback(
        self: *ErrorHandler,
        callback: *const fn (ErrorContext, *anyopaque) void,
        context: *anyopaque,
        severity_filter: ErrorSeverity,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.error_callbacks.append(ErrorCallback{
            .callback = callback,
            .context = context,
            .severity_filter = severity_filter,
        });
    }

    /// Handle an error with full context and recovery
    pub fn handleError(
        self: *ErrorHandler,
        err: anyerror,
        comptime fmt: []const u8,
        args: anytype,
        severity: ErrorSeverity,
        source_location: std.builtin.SourceLocation,
    ) RecoveryStrategy {
        const message = std.fmt.allocPrint(self.allocator, fmt, args) catch "Failed to format error message";
        defer self.allocator.free(message);

        const context = ErrorContext.init(err, message, source_location, self.allocator);

        // Update statistics
        _ = self.total_errors.fetchAdd(1, .monotonic);
        _ = self.errors_by_severity[@intFromEnum(severity)].fetchAdd(1, .monotonic);

        // Log the error
        switch (severity) {
            .fatal => std.log.scoped(.error_utils).err("Error handled: {}", .{context}),
            .err => std.log.scoped(.error_utils).err("Error handled: {}", .{context}),
            .warn => std.log.scoped(.error_utils).warn("Error handled: {}", .{context}),
            .info => std.log.scoped(.error_utils).info("Error handled: {}", .{context}),
            .debug => std.log.scoped(.error_utils).debug("Error handled: {}", .{context}),
            .trace => std.log.scoped(.error_utils).debug("Error handled: {}", .{context}),
        }

        // Store in error log
        self.mutex.lock();
        self.error_log.append(context) catch {};
        self.mutex.unlock();

        // Notify callbacks
        self.notifyCallbacks(context, severity);

        // Determine recovery strategy
        const strategy = self.getRecoveryStrategy(err, severity);

        // Execute recovery strategy
        self.executeRecoveryStrategy(strategy, context);

        return strategy;
    }

    /// Get error statistics
    pub fn getStatistics(self: *ErrorHandler) ErrorStatistics {
        return ErrorStatistics{
            .total_errors = self.total_errors.load(.monotonic),
            .trace_count = self.errors_by_severity[0].load(.monotonic),
            .debug_count = self.errors_by_severity[1].load(.monotonic),
            .info_count = self.errors_by_severity[2].load(.monotonic),
            .warn_count = self.errors_by_severity[3].load(.monotonic),
            .error_count = self.errors_by_severity[4].load(.monotonic),
            .fatal_count = self.errors_by_severity[5].load(.monotonic),
        };
    }

    /// Clear error log (keeping statistics)
    pub fn clearLog(self: *ErrorHandler) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.error_log.items) |*ctx| {
            ctx.deinit();
        }
        self.error_log.clearRetainingCapacity();
    }

    // Private implementation

    fn notifyCallbacks(self: *ErrorHandler, context: ErrorContext, severity: ErrorSeverity) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.error_callbacks.items) |callback| {
            if (@intFromEnum(severity) >= @intFromEnum(callback.severity_filter)) {
                callback.callback(context, callback.context);
            }
        }
    }

    fn getRecoveryStrategy(self: *ErrorHandler, err: anyerror, severity: ErrorSeverity) RecoveryStrategy {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Check for specific error strategy
        if (self.recovery_strategies.get(err)) |strategy| {
            return strategy;
        }

        // Default strategies based on severity
        return switch (severity) {
            .fatal => .abort,
            .err => .fallback,
            .warn => .graceful_degrade,
            .info, .debug, .trace => .ignore,
        };
    }

    fn executeRecoveryStrategy(self: *ErrorHandler, strategy: RecoveryStrategy, context: ErrorContext) void {
        _ = self;

        switch (strategy) {
            .abort => {
                log.err("Fatal error encountered, aborting: {}", .{context});
                std.process.exit(1);
            },
            .retry => {
                log.info("Retrying operation after error: {}", .{context});
                // Caller should handle retry logic
            },
            .fallback => {
                log.warn("Using fallback mechanism for error: {}", .{context});
                // Caller should handle fallback logic
            },
            .ignore => {
                log.debug("Ignoring error: {}", .{context});
            },
            .user_prompt => {
                log.info("User intervention required for error: {}", .{context});
                // Could implement user prompting in GUI applications
            },
            .graceful_degrade => {
                log.warn("Gracefully degrading functionality due to error: {}", .{context});
                // Caller should handle degradation logic
            },
        }
    }
};

/// Error statistics structure
pub const ErrorStatistics = struct {
    total_errors: u64,
    trace_count: u64,
    debug_count: u64,
    info_count: u64,
    warn_count: u64,
    error_count: u64,
    fatal_count: u64,

    pub fn format(
        self: ErrorStatistics,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("Error Statistics:\n");
        try writer.print("  Total: {d}\n", .{self.total_errors});
        try writer.print("  Fatal: {d}\n", .{self.fatal_count});
        try writer.print("  Error: {d}\n", .{self.error_count});
        try writer.print("  Warn:  {d}\n", .{self.warn_count});
        try writer.print("  Info:  {d}\n", .{self.info_count});
        try writer.print("  Debug: {d}\n", .{self.debug_count});
        try writer.print("  Trace: {d}\n", .{self.trace_count});
    }
};

/// Global error handler instance
var global_error_handler: ?*ErrorHandler = null;
var global_handler_mutex: std.Thread.Mutex = .{};

/// Initialize global error handler
pub fn initGlobalErrorHandler(allocator: std.mem.Allocator) !void {
    global_handler_mutex.lock();
    defer global_handler_mutex.unlock();

    if (global_error_handler != null) return;

    const handler = try allocator.create(ErrorHandler);
    handler.* = try ErrorHandler.init(allocator);
    global_error_handler = handler;
}

/// Deinitialize global error handler
pub fn deinitGlobalErrorHandler(allocator: std.mem.Allocator) void {
    global_handler_mutex.lock();
    defer global_handler_mutex.unlock();

    if (global_error_handler) |handler| {
        handler.deinit();
        allocator.destroy(handler);
        global_error_handler = null;
    }
}

/// Get global error handler
pub fn getGlobalErrorHandler() ?*ErrorHandler {
    global_handler_mutex.lock();
    defer global_handler_mutex.unlock();
    return global_error_handler;
}

// Convenience functions for common error handling patterns

/// Enhanced error logging with context
pub fn logErr(
    comptime fmt: []const u8,
    args: anytype,
    err: anyerror,
    source_location: std.builtin.SourceLocation,
) anyerror {
    if (getGlobalErrorHandler()) |handler| {
        _ = handler.handleError(err, fmt, args, .err, source_location);
    } else {
        log.err(fmt ++ ": {s}", args ++ .{@errorName(err)});
    }
    return err;
}

/// Enhanced error logging with recovery strategy
pub fn logErrWithRecovery(
    comptime fmt: []const u8,
    args: anytype,
    err: anyerror,
    severity: ErrorSeverity,
    source_location: std.builtin.SourceLocation,
) RecoveryStrategy {
    if (getGlobalErrorHandler()) |handler| {
        return handler.handleError(err, fmt, args, severity, source_location);
    } else {
        switch (severity) {
            .fatal => log.err(fmt ++ ": {s}", args ++ .{@errorName(err)}),
            .err => log.err(fmt ++ ": {s}", args ++ .{@errorName(err)}),
            .warn => log.warn(fmt ++ ": {s}", args ++ .{@errorName(err)}),
            .info => log.info(fmt ++ ": {s}", args ++ .{@errorName(err)}),
            .debug => log.debug(fmt ++ ": {s}", args ++ .{@errorName(err)}),
            .trace => log.debug(fmt ++ ": {s}", args ++ .{@errorName(err)}),
        }
        return .ignore;
    }
}

/// Catch and log with automatic source location
pub fn catchAndLog(
    comptime fmt: []const u8,
    args: anytype,
    err: anyerror,
) anyerror {
    return logErr(fmt, args, err, @src());
}

/// Catch and handle with recovery
pub fn catchAndHandle(
    comptime fmt: []const u8,
    args: anytype,
    err: anyerror,
    severity: ErrorSeverity,
) RecoveryStrategy {
    return logErrWithRecovery(fmt, args, err, severity, @src());
}

/// Assert with enhanced error reporting
pub fn assertWithContext(
    condition: bool,
    comptime fmt: []const u8,
    args: anytype,
    source_location: std.builtin.SourceLocation,
) void {
    if (!condition) {
        if (getGlobalErrorHandler()) |handler| {
            _ = handler.handleError(error.AssertionFailed, fmt, args, .fatal, source_location);
        } else {
            log.err("Assertion failed: " ++ fmt, args);
            std.debug.panic("Assertion failed at {s}:{d}", .{ source_location.file, source_location.line });
        }
    }
}

/// Enhanced assert macro
pub fn assert(condition: bool, comptime fmt: []const u8, args: anytype) void {
    assertWithContext(condition, fmt, args, @src());
}

/// Try-catch pattern with automatic error handling
pub fn tryWithHandler(
    comptime T: type,
    operation: anytype,
    comptime fmt: []const u8,
    args: anytype,
    fallback: T,
) T {
    return operation catch |err| {
        _ = catchAndLog(fmt, args, err);
        return fallback;
    };
}

/// Retry pattern with exponential backoff
pub fn retryWithBackoff(
    comptime T: type,
    operation: anytype,
    max_attempts: u32,
    initial_delay_ms: u64,
) !T {
    var attempts: u32 = 0;
    var delay_ms = initial_delay_ms;

    while (attempts < max_attempts) {
        if (operation()) |result| {
            return result;
        } else |err| {
            attempts += 1;
            if (attempts >= max_attempts) {
                return err;
            }

            log.warn("Operation failed (attempt {d}/{d}), retrying in {d}ms: {s}", .{ attempts, max_attempts, delay_ms, @errorName(err) });

            std.time.sleep(delay_ms * std.time.ns_per_ms);
            delay_ms = @min(delay_ms * 2, 5000); // Cap at 5 seconds
        }
    }

    return error.MaxRetriesExceeded;
}

/// Resource cleanup with error handling
pub fn cleanupWithErrorHandling(
    cleanup_fn: anytype,
    comptime fmt: []const u8,
    args: anytype,
) void {
    cleanup_fn() catch |err| {
        _ = catchAndLog(fmt, args, err);
    };
}

// Testing utilities

test "error context creation and formatting" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var context = ErrorContext.init(
        error.TestError,
        "Test error message",
        @src(),
        allocator,
    );
    defer context.deinit();

    try testing.expect(context.error_code == error.TestError);
    try testing.expectEqualStrings("Test error message", context.message);
}

test "error handler basic functionality" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var handler = try ErrorHandler.init(allocator);
    defer handler.deinit();

    // Set recovery strategy
    try handler.setRecoveryStrategy(error.TestError, .fallback);

    // Handle an error
    const strategy = handler.handleError(
        error.TestError,
        "Test error: {s}",
        .{"test"},
        .err,
        @src(),
    );

    try testing.expect(strategy == .fallback);

    // Check statistics
    const stats = handler.getStatistics();
    try testing.expect(stats.total_errors == 1);
    try testing.expect(stats.error_count == 1);
}

test "retry with backoff" {
    const testing = std.testing;

    var attempt_count: u32 = 0;
    const test_operation = struct {
        fn call(counter: *u32) !u32 {
            counter.* += 1;
            if (counter.* < 3) {
                return error.NotReady;
            }
            return counter.*;
        }
    }.call;

    const result = try retryWithBackoff(u32, test_operation(&attempt_count), 5, 1);
    try testing.expect(result == 3);
    try testing.expect(attempt_count == 3);
}
