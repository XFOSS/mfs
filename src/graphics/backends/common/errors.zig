const std = @import("std");

/// Common error types shared across all graphics backends
pub const GraphicsError = error{
    // Device/initialization errors
    DeviceCreationFailed,
    DeviceLost,
    UnsupportedFeature,
    BackendNotSupported,

    // Resource errors
    OutOfMemory,
    ResourceCreationFailed,
    InvalidResource,
    ResourceBusy,
    ResourceNotBound,

    // Command/operation errors
    InvalidOperation,
    InvalidCommandBuffer,
    CommandBufferFull,
    CommandSubmissionFailed,

    // Synchronization errors
    TimeoutExpired,
    SyncError,
    WaitFailed,

    // Pipeline/state errors
    InvalidPipelineState,
    IncompatiblePipelineLayout,
    ShaderCompilationFailed,

    // Format/compatibility errors
    UnsupportedFormat,
    IncompatibleFormat,
    InvalidFormatConversion,

    // Memory errors
    AllocationFailed,
    InvalidAlignment,
    InvalidMemoryAccess,

    // Debug/validation errors
    ValidationError,
    DebugMarkerError,
};

/// Error context for better error reporting and debugging
pub const ErrorContext = struct {
    error_type: GraphicsError,
    message: []const u8,
    file: []const u8,
    line: u32,
    backend_type: []const u8,
    additional_info: ?[]const u8 = null,

    pub fn format(self: ErrorContext, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("[{s}] {s} at {s}:{d}: {s}", .{
            self.backend_type,
            @errorName(self.error_type),
            self.file,
            self.line,
            self.message,
        });
        if (self.additional_info) |info| {
            try writer.print("\nAdditional info: {s}", .{info});
        }
    }
};

/// Helper function to create error context
pub fn makeError(
    error_type: GraphicsError,
    message: []const u8,
    backend_type: []const u8,
    file: []const u8,
    line: u32,
    additional_info: ?[]const u8,
) ErrorContext {
    return ErrorContext{
        .error_type = error_type,
        .message = message,
        .file = file,
        .line = line,
        .backend_type = backend_type,
        .additional_info = additional_info,
    };
}

/// Logging levels for error reporting
pub const ErrorSeverity = enum {
    info,
    warning,
    critical,
    fatal,
};

/// Error logger for capturing and reporting errors
pub const ErrorLogger = struct {
    allocator: std.mem.Allocator,
    errors: std.ArrayList(ErrorContext),

    pub fn init(allocator: std.mem.Allocator) ErrorLogger {
        return ErrorLogger{
            .allocator = allocator,
            .errors = std.ArrayList(ErrorContext).init(allocator),
        };
    }

    pub fn deinit(self: *ErrorLogger) void {
        self.errors.deinit();
    }

    pub fn logError(
        self: *ErrorLogger,
        error_context: ErrorContext,
        severity: ErrorSeverity,
    ) !void {
        try self.errors.append(error_context);

        // Log to stderr for immediate visibility
        const stderr = std.io.getStdErr().writer();
        try stderr.print("[{s}] ", .{@tagName(severity)});
        try std.fmt.format(stderr, "{}\n", .{error_context});
    }

    pub fn clearErrors(self: *ErrorLogger) void {
        self.errors.clearRetainingCapacity();
    }

    pub fn hasErrors(self: ErrorLogger) bool {
        return self.errors.items.len > 0;
    }

    pub fn getLastError(self: ErrorLogger) ?ErrorContext {
        if (self.errors.items.len == 0) return null;
        return self.errors.items[self.errors.items.len - 1];
    }
};
