const std = @import("std");

/// Graphics backend error types
pub const GraphicsError = error{
    InitializationFailed,
    DeviceCreationFailed,
    SwapChainCreationFailed,
    ResourceCreationFailed,
    CommandSubmissionFailed,
    OutOfMemory,
    InvalidOperation,
    UnsupportedFormat,
    BackendNotAvailable,
    BackendNotSupported,
    InvalidMemoryAccess,
    ShaderCompilationFailed,
    InvalidParameter,
    RenderPassInProgress,
    RenderPassNotInProgress,
    FeatureNotSupported,
};

/// Error severity levels
pub const ErrorSeverity = enum {
    info,
    warning,
    @"error",
    critical,
};

pub const ErrorContext = struct {
    /// Severity level of the error
    severity: ErrorSeverity,
    error_type: anyerror,
    message: []const u8,
    backend: []const u8,
    file: []const u8,
    line: u32,
    additional_info: ?[]const u8 = null,
    timestamp: i64,

    pub fn format(
        self: ErrorContext,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        // Include severity level in output
        try writer.print("[{s}] [{s}] {s} at {s}:{d}: {s}", .{
            @tagName(self.severity),
            self.backend,
            @errorName(self.error_type),
            self.file,
            self.line,
            self.message,
        });

        if (self.additional_info) |info| {
            try writer.print(" ({s})", .{info});
        }
    }
};

/// Create an error context
pub fn makeError(
    err: anyerror,
    message: []const u8,
    backend: []const u8,
    file: []const u8,
    line: u32,
    additional_info: ?[]const u8,
    severity: ErrorSeverity,
) ErrorContext {
    return ErrorContext{
        .severity = severity,
        .error_type = err,
        .message = message,
        .backend = backend,
        .file = file,
        .line = line,
        .additional_info = additional_info,
        .timestamp = std.time.nanoTimestamp(),
    };
}

/// Error logger for tracking and reporting graphics errors
pub const ErrorLogger = struct {
    allocator: std.mem.Allocator,
    errors: std.ArrayList(ErrorContext),
    max_errors: usize = 100,

    pub fn init(allocator: std.mem.Allocator) ErrorLogger {
        return ErrorLogger{
            .allocator = allocator,
            .errors = std.ArrayList(ErrorContext).init(allocator),
        };
    }

    pub fn deinit(self: *ErrorLogger) void {
        self.errors.deinit();
    }

    pub fn logError(self: *ErrorLogger, ctx: ErrorContext, severity: ErrorSeverity) !void {
        // Log to console based on severity
        switch (severity) {
            .info => std.log.info("{}", .{ctx}),
            .warning => std.log.warn("{}", .{ctx}),
            .@"error" => std.log.err("{}", .{ctx}),
            .critical => std.log.err("{}", .{ctx}),
        }

        // Store error in history
        try self.errors.append(ctx);

        // Limit error history size
        if (self.errors.items.len > self.max_errors) {
            _ = self.errors.orderedRemove(0);
        }

        // For critical errors, we might want to abort or take special action
        if (severity == .critical) {
            // Just log for now, but could abort in production builds
        }
    }

    pub fn hasErrors(self: ErrorLogger) bool {
        return self.errors.items.len > 0;
    }

    pub fn getLastError(self: ErrorLogger) ?ErrorContext {
        if (self.errors.items.len == 0) return null;
        return self.errors.items[self.errors.items.len - 1];
    }

    pub fn clearErrors(self: *ErrorLogger) void {
        self.errors.clearRetainingCapacity();
    }
};
