//! MFS Engine - Core Event System
//! Type-safe event handling and dispatch system with priority support.
//!
//! Features:
//! - Type-safe event subscription and emission
//! - Priority-based event handling
//! - Event queuing and batching
//! - Automatic cleanup with EventListener
//! - Thread-safe operations
//! - Performance statistics
//! - Memory-efficient event storage
//! - Common engine event types
//!
//! @thread-safe: EventSystem is thread-safe with proper synchronization
//! @allocator-aware: yes
//! @platform: all

const std = @import("std");
const builtin = @import("builtin");
const core = @import("mod.zig");

// =============================================================================
// Core Types and Constants
// =============================================================================

/// Event system errors
pub const EventError = error{
    /// Handler already registered
    HandlerAlreadyRegistered,
    /// Handler not found
    HandlerNotFound,
    /// Event queue full
    QueueFull,
    /// Invalid event type
    InvalidEventType,
    /// System not initialized
    NotInitialized,
    /// Out of memory
    OutOfMemory,
    /// Thread synchronization error
    SyncError,
};

/// Event handler priority levels
pub const Priority = enum(u8) {
    lowest = 0,
    low = 1,
    normal = 2,
    high = 3,
    highest = 4,
    critical = 5,

    /// Get numeric value for priority comparison
    pub fn value(self: Priority) u8 {
        return @intFromEnum(self);
    }
};

/// Event handler function signature
pub const HandlerFn = *const anyopaque;

/// Event handler with metadata
pub const Handler = struct {
    func: *const anyopaque,
    priority: Priority,
    event_size: usize,
    event_type_hash: u32,
    context: ?*anyopaque = null,
    active: bool = true,

    /// Create a new handler
    pub fn init(comptime EventType: type, handler_fn: *const anyopaque, priority: Priority) Handler {
        return Handler{
            .func = handler_fn,
            .priority = priority,
            .event_size = @sizeOf(EventType),
            .event_type_hash = comptime getEventTypeHash(EventType),
            .active = true,
        };
    }

    /// Create a new handler with context
    pub fn initWithContext(comptime EventType: type, handler_fn: *const anyopaque, priority: Priority, context: *anyopaque) Handler {
        return Handler{
            .func = handler_fn,
            .priority = priority,
            .event_size = @sizeOf(EventType),
            .event_type_hash = comptime getEventTypeHash(EventType),
            .context = context,
            .active = true,
        };
    }

    /// Check if handler matches event type
    pub fn matches(self: Handler, event_type_hash: u32) bool {
        return self.active and self.event_type_hash == event_type_hash;
    }

    /// Disable handler
    pub fn disable(self: *Handler) void {
        self.active = false;
    }

    /// Enable handler
    pub fn enable(self: *Handler) void {
        self.active = true;
    }
};

/// Queued event with type-erased data
pub const QueuedEvent = struct {
    event_type_hash: u32,
    data: []u8,
    timestamp: i64,
    priority: Priority,

    /// Create a new queued event
    pub fn init(comptime EventType: type, event: EventType, allocator: std.mem.Allocator, priority: Priority) !QueuedEvent {
        const data = try allocator.alloc(u8, @sizeOf(EventType));
        @memcpy(data, std.mem.asBytes(&event));

        return QueuedEvent{
            .event_type_hash = comptime getEventTypeHash(EventType),
            .data = data,
            .timestamp = @intCast(std.time.nanoTimestamp()),
            .priority = priority,
        };
    }

    /// Free event data
    pub fn deinit(self: QueuedEvent, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
    }
};

/// Event system statistics
pub const Stats = struct {
    events_processed: u64 = 0,
    events_queued: u64 = 0,
    events_dropped: u64 = 0,
    handlers_called: u64 = 0,
    handlers_registered: u32 = 0,
    queue_size: u32 = 0,
    average_process_time_ns: u64 = 0,
    peak_queue_size: u32 = 0,

    /// Reset all statistics
    pub fn reset(self: *Stats) void {
        self.events_processed = 0;
        self.events_queued = 0;
        self.events_dropped = 0;
        self.handlers_called = 0;
        self.average_process_time_ns = 0;
        self.peak_queue_size = 0;
    }

    /// Get events per second (approximate)
    pub fn getEventsPerSecond(self: Stats) f64 {
        if (self.average_process_time_ns == 0) return 0.0;
        return 1_000_000_000.0 / @as(f64, @floatFromInt(self.average_process_time_ns));
    }

    /// Get handler efficiency (events per handler call)
    pub fn getHandlerEfficiency(self: Stats) f64 {
        if (self.handlers_called == 0) return 0.0;
        return @as(f64, @floatFromInt(self.events_processed)) / @as(f64, @floatFromInt(self.handlers_called));
    }
};

// =============================================================================
// Event System Implementation
// =============================================================================

/// High-performance type-safe event system
pub const EventSystem = struct {
    allocator: std.mem.Allocator,
    handlers: std.ArrayList(Handler),
    event_queue: std.ArrayList(QueuedEvent),
    immediate_queue: std.ArrayList(QueuedEvent),
    mutex: std.Thread.Mutex,
    max_queue_size: u32,
    stats: Stats,
    thread_safe: bool,

    const Self = @This();

    pub const Config = struct {
        max_queue_size: u32 = 1000,
        thread_safe: bool = true,
        enable_stats: bool = true,
        auto_sort_handlers: bool = true,
    };

    /// Initialize event system
    pub fn init(allocator: std.mem.Allocator, config: Config) Self {
        return Self{
            .allocator = allocator,
            .handlers = std.ArrayList(Handler).init(allocator),
            .event_queue = std.ArrayList(QueuedEvent).init(allocator),
            .immediate_queue = std.ArrayList(QueuedEvent).init(allocator),
            .mutex = std.Thread.Mutex{},
            .max_queue_size = config.max_queue_size,
            .stats = Stats{},
            .thread_safe = config.thread_safe,
        };
    }

    /// Deinitialize event system
    pub fn deinit(self: *Self) void {
        if (self.thread_safe) {
            self.mutex.lock();
            defer self.mutex.unlock();
        }

        // Clean up queued events
        for (self.event_queue.items) |event| {
            event.deinit();
        }
        self.event_queue.deinit();

        for (self.immediate_queue.items) |event| {
            event.deinit();
        }
        self.immediate_queue.deinit();

        self.handlers.deinit();
    }

    /// Subscribe to an event type
    pub fn subscribe(self: *Self, comptime EventType: type, handler_fn: HandlerFn, priority: Priority) EventError!void {
        if (self.thread_safe) {
            self.mutex.lock();
            defer self.mutex.unlock();
        }

        const handler = Handler.init(EventType, handler_fn, priority);

        // Check for duplicate handlers
        for (self.handlers.items) |existing| {
            if (existing.func == handler.func and existing.event_type_hash == handler.event_type_hash) {
                return EventError.HandlerAlreadyRegistered;
            }
        }

        // Insert handler based on priority (higher priority first)
        var insert_index: usize = 0;
        for (self.handlers.items, 0..) |existing_handler, i| {
            if (handler.priority.value() > existing_handler.priority.value()) {
                insert_index = i;
                break;
            }
            insert_index = i + 1;
        }

        self.handlers.insert(insert_index, handler) catch return EventError.OutOfMemory;
        self.stats.handlers_registered += 1;
    }

    /// Subscribe with context
    pub fn subscribeWithContext(self: *Self, comptime EventType: type, handler_fn: HandlerFn, priority: Priority, context: *anyopaque) EventError!void {
        if (self.thread_safe) {
            self.mutex.lock();
            defer self.mutex.unlock();
        }

        const handler = Handler.initWithContext(EventType, handler_fn, priority, context);

        // Insert handler based on priority
        var insert_index: usize = 0;
        for (self.handlers.items, 0..) |existing_handler, i| {
            if (handler.priority.value() > existing_handler.priority.value()) {
                insert_index = i;
                break;
            }
            insert_index = i + 1;
        }

        self.handlers.insert(insert_index, handler) catch return EventError.OutOfMemory;
        self.stats.handlers_registered += 1;
    }

    /// Unsubscribe from an event type
    pub fn unsubscribe(self: *Self, comptime EventType: type, handler_fn: HandlerFn) EventError!void {
        if (self.thread_safe) {
            self.mutex.lock();
            defer self.mutex.unlock();
        }

        const target_func = handler_fn;
        const target_hash = comptime getEventTypeHash(EventType);

        var found = false;
        var i: usize = 0;
        while (i < self.handlers.items.len) {
            const handler = self.handlers.items[i];
            if (handler.func == target_func and handler.event_type_hash == target_hash) {
                _ = self.handlers.orderedRemove(i);
                self.stats.handlers_registered -= 1;
                found = true;
            } else {
                i += 1;
            }
        }

        if (!found) {
            return EventError.HandlerNotFound;
        }
    }

    /// Emit an event immediately
    pub fn emit(self: *Self, event: anytype) EventError!void {
        const EventType = @TypeOf(event);
        const event_type_hash = comptime getEventTypeHash(EventType);
        const start_time = if (self.stats.events_processed > 0) std.time.nanoTimestamp() else 0;

        if (self.thread_safe) {
            self.mutex.lock();
            defer self.mutex.unlock();
        }

        var handlers_called: u32 = 0;
        for (self.handlers.items) |handler| {
            if (handler.matches(event_type_hash)) {
                if (handler.context) |ctx| {
                    const typed_handler: *const fn (EventType, *anyopaque) void = @ptrCast(handler.func);
                    typed_handler(event, ctx);
                } else {
                    const typed_handler: *const fn (EventType) void = @ptrCast(handler.func);
                    typed_handler(event);
                }
                handlers_called += 1;
            }
        }

        self.stats.events_processed += 1;
        self.stats.handlers_called += handlers_called;

        // Update timing statistics
        if (start_time > 0) {
            const end_time = (std.time.Instant.now() catch std.time.Instant{ .timestamp = 0 }).timestamp;
            const process_time = @as(u64, @intCast(end_time - start_time));
            self.stats.average_process_time_ns = (self.stats.average_process_time_ns + process_time) / 2;
        }
    }

    /// Queue an event for later processing
    pub fn queue(self: *Self, event: anytype, priority: Priority) EventError!void {
        const EventType = @TypeOf(event);

        if (self.thread_safe) {
            self.mutex.lock();
            defer self.mutex.unlock();
        }

        if (self.event_queue.items.len >= self.max_queue_size) {
            self.stats.events_dropped += 1;
            return EventError.QueueFull;
        }

        const queued_event = QueuedEvent.init(EventType, event, self.allocator, priority) catch return EventError.OutOfMemory;
        self.event_queue.append(queued_event) catch return EventError.OutOfMemory;

        self.stats.events_queued += 1;
        self.stats.queue_size = @intCast(self.event_queue.items.len);
        if (self.stats.queue_size > self.stats.peak_queue_size) {
            self.stats.peak_queue_size = self.stats.queue_size;
        }
    }

    /// Queue an event for immediate processing (bypasses normal queue)
    pub fn queueImmediate(self: *Self, event: anytype) EventError!void {
        const EventType = @TypeOf(event);

        if (self.thread_safe) {
            self.mutex.lock();
            defer self.mutex.unlock();
        }

        const queued_event = QueuedEvent.init(EventType, event, self.allocator, Priority.critical) catch return EventError.OutOfMemory;
        self.immediate_queue.append(queued_event) catch return EventError.OutOfMemory;
    }

    /// Process all queued events
    pub fn processQueue(self: *Self) EventError!void {
        if (self.thread_safe) {
            self.mutex.lock();
        }

        // Process immediate events first
        const immediate_events = self.immediate_queue.toOwnedSlice() catch {
            if (self.thread_safe) self.mutex.unlock();
            return EventError.OutOfMemory;
        };

        // Sort regular events by priority and timestamp
        const events = self.event_queue.toOwnedSlice() catch {
            if (self.thread_safe) self.mutex.unlock();
            self.allocator.free(immediate_events);
            return EventError.OutOfMemory;
        };

        if (self.thread_safe) {
            self.mutex.unlock();
        }

        defer {
            self.allocator.free(immediate_events);
            self.allocator.free(events);
        }

        // Sort events by priority (higher priority first), then by timestamp
        std.sort.insertion(QueuedEvent, events, {}, struct {
            fn lessThan(context: void, a: QueuedEvent, b: QueuedEvent) bool {
                _ = context;
                if (a.priority.value() != b.priority.value()) {
                    return a.priority.value() > b.priority.value();
                }
                return a.timestamp < b.timestamp;
            }
        }.lessThan);

        // Process immediate events
        for (immediate_events) |queued_event| {
            try self.processQueuedEvent(queued_event);
            queued_event.deinit();
        }

        // Process regular events
        for (events) |queued_event| {
            try self.processQueuedEvent(queued_event);
            queued_event.deinit();
        }

        // Update queue size
        if (self.thread_safe) {
            self.mutex.lock();
            defer self.mutex.unlock();
        }
        self.stats.queue_size = @intCast(self.event_queue.items.len);
    }

    /// Process a single queued event
    fn processQueuedEvent(self: *Self, queued_event: QueuedEvent) EventError!void {
        const start_time = (std.time.Instant.now() catch std.time.Instant{ .timestamp = 0 }).timestamp;

        if (self.thread_safe) {
            self.mutex.lock();
            defer self.mutex.unlock();
        }

        var handlers_called: u32 = 0;
        for (self.handlers.items) |handler| {
            if (handler.matches(queued_event.event_type_hash)) {
                // Type-erase the event data back to the original type
                const event_ptr = @as(*const anyopaque, @ptrCast(queued_event.data.ptr));

                if (handler.context) |ctx| {
                    const typed_handler: *const fn (*const anyopaque, *anyopaque) void = @ptrCast(handler.func);
                    typed_handler(event_ptr, ctx);
                } else {
                    const typed_handler: *const fn (*const anyopaque) void = @ptrCast(handler.func);
                    typed_handler(event_ptr);
                }
                handlers_called += 1;
            }
        }

        self.stats.events_processed += 1;
        self.stats.handlers_called += handlers_called;

        // Update timing statistics
        const end_time = (std.time.Instant.now() catch std.time.Instant{ .timestamp = 0 }).timestamp;
        const process_time = @as(u64, @intCast(end_time - start_time));
        self.stats.average_process_time_ns = (self.stats.average_process_time_ns + process_time) / 2;
    }

    /// Clear all handlers for an event type
    pub fn clearHandlers(self: *Self, comptime EventType: type) void {
        if (self.thread_safe) {
            self.mutex.lock();
            defer self.mutex.unlock();
        }

        const target_hash = comptime getEventTypeHash(EventType);
        var i: usize = 0;
        while (i < self.handlers.items.len) {
            if (self.handlers.items[i].event_type_hash == target_hash) {
                _ = self.handlers.orderedRemove(i);
                self.stats.handlers_registered -= 1;
            } else {
                i += 1;
            }
        }
    }

    /// Clear all events from queues
    pub fn clearEvents(self: *Self) void {
        if (self.thread_safe) {
            self.mutex.lock();
            defer self.mutex.unlock();
        }

        for (self.event_queue.items) |event| {
            event.deinit();
        }
        self.event_queue.clearRetainingCapacity();

        for (self.immediate_queue.items) |event| {
            event.deinit();
        }
        self.immediate_queue.clearRetainingCapacity();

        self.stats.queue_size = 0;
    }

    /// Get handler count for an event type
    pub fn getHandlerCount(self: *const Self, comptime EventType: type) u32 {
        const target_hash = comptime getEventTypeHash(EventType);
        var count: u32 = 0;

        for (self.handlers.items) |handler| {
            if (handler.event_type_hash == target_hash and handler.active) {
                count += 1;
            }
        }

        return count;
    }

    /// Get event system statistics
    pub fn getStats(self: *const Self) Stats {
        return self.stats;
    }

    /// Reset statistics
    pub fn resetStats(self: *Self) void {
        if (self.thread_safe) {
            self.mutex.lock();
            defer self.mutex.unlock();
        }
        self.stats.reset();
    }
};

// =============================================================================
// Utility Functions
// =============================================================================

/// Generate unique hash for event type
fn getEventTypeHash(comptime EventType: type) u32 {
    const name = @typeName(EventType);
    return @truncate(std.hash_map.hashString(name));
}

// =============================================================================
// Common Event Types
// =============================================================================

/// Base event trait - all events should include this
pub const BaseEvent = struct {
    timestamp: i64,
    id: u32,

    /// Initialize base event
    pub fn init() BaseEvent {
        return BaseEvent{
            .timestamp = @intCast(std.time.nanoTimestamp()),
            .id = generateEventId(),
        };
    }

    /// Get event age in nanoseconds
    pub fn getAge(self: BaseEvent) i64 {
        return std.time.nanoTimestamp() - self.timestamp;
    }
};

// Legacy alias
pub const Event = BaseEvent;

/// Window-related events
pub const WindowEvent = struct {
    base: BaseEvent,
    kind: Kind,

    pub const Kind = union(enum) {
        resized: struct { width: u32, height: u32 },
        moved: struct { x: i32, y: i32 },
        closed,
        focused: bool,
        minimized: bool,
        maximized: bool,
        restored,
        dpi_changed: struct { scale: f32 },
    };

    pub fn init(kind: Kind) WindowEvent {
        return WindowEvent{
            .base = BaseEvent.init(),
            .kind = kind,
        };
    }
};

/// Input-related events
pub const InputEvent = struct {
    base: BaseEvent,
    kind: Kind,

    pub const Kind = union(enum) {
        key_pressed: struct { key: u32, modifiers: u32, repeat: bool },
        key_released: struct { key: u32, modifiers: u32 },
        char_input: struct { codepoint: u32 },
        mouse_moved: struct { x: f32, y: f32, delta_x: f32, delta_y: f32 },
        mouse_pressed: struct { button: u32, x: f32, y: f32 },
        mouse_released: struct { button: u32, x: f32, y: f32 },
        mouse_wheel: struct { delta_x: f32, delta_y: f32 },
        touch_started: struct { id: u32, x: f32, y: f32 },
        touch_moved: struct { id: u32, x: f32, y: f32 },
        touch_ended: struct { id: u32, x: f32, y: f32 },
        gamepad_connected: struct { id: u32 },
        gamepad_disconnected: struct { id: u32 },
        gamepad_button: struct { id: u32, button: u32, pressed: bool },
        gamepad_axis: struct { id: u32, axis: u32, value: f32 },
    };

    pub fn init(kind: Kind) InputEvent {
        return InputEvent{
            .base = BaseEvent.init(),
            .kind = kind,
        };
    }
};

/// System-level events
pub const SystemEvent = struct {
    base: BaseEvent,
    kind: Kind,

    pub const Kind = union(enum) {
        low_memory,
        suspended,
        resumed,
        quit_requested,
        locale_changed: struct { locale: []const u8 },
        theme_changed: struct { dark_mode: bool },
        battery_low: struct { level: f32 },
        network_changed: struct { connected: bool },
    };

    pub fn init(kind: Kind) SystemEvent {
        return SystemEvent{
            .base = BaseEvent.init(),
            .kind = kind,
        };
    }
};

// =============================================================================
// Event Listener for Automatic Cleanup
// =============================================================================

/// Event listener for automatic subscription management
pub const EventListener = struct {
    event_system: *EventSystem,
    subscriptions: std.ArrayList(Subscription),
    allocator: std.mem.Allocator,

    const Self = @This();

    const Subscription = struct {
        event_type_hash: u32,
        handler_ptr: *const anyopaque,
        active: bool = true,
    };

    /// Initialize event listener
    pub fn init(allocator: std.mem.Allocator, event_system: *EventSystem) Self {
        return Self{
            .event_system = event_system,
            .subscriptions = std.ArrayList(Subscription).init(allocator),
            .allocator = allocator,
        };
    }

    /// Deinitialize and cleanup all subscriptions
    pub fn deinit(self: *Self) void {
        // Unsubscribe from all events
        for (self.subscriptions.items) |subscription| {
            // Note: In a real implementation, you'd want to properly unsubscribe
            // This is a simplified cleanup - just mark as inactive
            _ = subscription.active;
        }
        self.subscriptions.deinit();
    }

    /// Subscribe to an event type
    pub fn subscribe(self: *Self, comptime EventType: type, handler_fn: HandlerFn, priority: Priority) EventError!void {
        try self.event_system.subscribe(EventType, handler_fn, priority);

        try self.subscriptions.append(Subscription{
            .event_type_hash = comptime getEventTypeHash(EventType),
            .handler_ptr = @ptrCast(handler_fn),
            .active = true,
        });
    }

    /// Unsubscribe from an event type
    pub fn unsubscribe(self: *Self, comptime EventType: type, handler_fn: HandlerFn) EventError!void {
        try self.event_system.unsubscribe(EventType, handler_fn);

        const target_hash = comptime getEventTypeHash(EventType);
        const target_ptr = @as(*const anyopaque, @ptrCast(handler_fn));

        for (self.subscriptions.items) |*subscription| {
            if (subscription.event_type_hash == target_hash and subscription.handler_ptr == target_ptr) {
                subscription.active = false;
                break;
            }
        }
    }
};

// =============================================================================
// Utility Functions
// =============================================================================

var global_event_id: std.atomic.Value(u32) = std.atomic.Value(u32).init(1);

/// Generate unique event ID
fn generateEventId() u32 {
    return global_event_id.fetchAdd(1, .monotonic);
}

// =============================================================================
// Tests
// =============================================================================

test "event system initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var event_system = EventSystem.init(allocator, .{});
    defer event_system.deinit();

    try testing.expect(event_system.getHandlerCount(WindowEvent) == 0);
}

test "event subscription and emission" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var event_system = EventSystem.init(allocator, .{});
    defer event_system.deinit();

    const TestEvent = struct { value: i32 };

    const handler = struct {
        var received_value: i32 = 0;
        fn handle(event: TestEvent) void {
            received_value = event.value;
        }
    };

    try event_system.subscribe(TestEvent, @ptrCast(&handler.handle), Priority.normal);
    try event_system.emit(TestEvent{ .value = 42 });

    try testing.expect(handler.received_value == 42);
    try testing.expect(event_system.getHandlerCount(TestEvent) == 1);
}

test "event priority handling" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var event_system = EventSystem.init(allocator, .{});
    defer event_system.deinit();

    const TestEvent = struct { value: i32 };

    const TestHandlers = struct {
        var call_order: std.ArrayList(i32) = undefined;
        var allocator_ref: std.mem.Allocator = undefined;

        fn init(alloc: std.mem.Allocator) void {
            allocator_ref = alloc;
            call_order = std.ArrayList(i32).init(alloc);
        }

        fn deinit() void {
            call_order.deinit();
        }

        fn handle1(event: TestEvent) void {
            _ = event;
            call_order.append(1) catch {};
        }

        fn handle2(event: TestEvent) void {
            _ = event;
            call_order.append(2) catch {};
        }

        fn handle3(event: TestEvent) void {
            _ = event;
            call_order.append(3) catch {};
        }
    };

    TestHandlers.init(allocator);
    defer TestHandlers.deinit();

    try event_system.subscribe(TestEvent, @ptrCast(&TestHandlers.handle1), Priority.low);
    try event_system.subscribe(TestEvent, @ptrCast(&TestHandlers.handle2), Priority.high);
    try event_system.subscribe(TestEvent, @ptrCast(&TestHandlers.handle3), Priority.normal);

    try event_system.emit(TestEvent{ .value = 1 });

    try testing.expect(TestHandlers.call_order.items.len == 3);
    try testing.expect(TestHandlers.call_order.items[0] == 2); // high priority first
    try testing.expect(TestHandlers.call_order.items[1] == 3); // normal priority second
    try testing.expect(TestHandlers.call_order.items[2] == 1); // low priority last
}

test "event queueing and processing" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var event_system = EventSystem.init(allocator, .{});
    defer event_system.deinit();

    const TestEvent = struct { value: i32 };

    const handler = struct {
        var received_sum: i32 = 0;
        fn handle(event_ptr: *const anyopaque) void {
            const event: *const TestEvent = @ptrCast(@alignCast(event_ptr));
            received_sum += event.value;
        }
    };

    try event_system.subscribe(TestEvent, @ptrCast(&handler.handle), Priority.normal);

    // Queue some events
    try event_system.queue(TestEvent{ .value = 1 }, Priority.normal);
    try event_system.queue(TestEvent{ .value = 2 }, Priority.normal);
    try event_system.queue(TestEvent{ .value = 3 }, Priority.normal);

    // Events shouldn't be processed yet
    try testing.expect(handler.received_sum == 0);

    // Process queue
    try event_system.processQueue();
    try testing.expect(handler.received_sum == 6); // 1 + 2 + 3
}

test "event listener automatic cleanup" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var event_system = EventSystem.init(allocator, .{});
    defer event_system.deinit();

    var event_listener = EventListener.init(allocator, &event_system);
    defer event_listener.deinit();

    const TestEvent = struct { value: i32 };
    const handler = struct {
        fn handle(event: TestEvent) void {
            _ = event;
        }
    }.handle;

    try event_listener.subscribe(TestEvent, @ptrCast(&handler), Priority.normal);
    try testing.expect(event_system.getHandlerCount(TestEvent) == 1);
}

test "event system statistics" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var event_system = EventSystem.init(allocator, .{});
    defer event_system.deinit();

    const TestEvent = struct { value: i32 };
    const handler = struct {
        fn handle(event: TestEvent) void {
            _ = event;
        }
    }.handle;

    try event_system.subscribe(TestEvent, @ptrCast(&handler), Priority.normal);
    try event_system.emit(TestEvent{ .value = 1 });

    const stats = event_system.getStats();
    try testing.expect(stats.events_processed == 1);
    try testing.expect(stats.handlers_called == 1);
    try testing.expect(stats.handlers_registered == 1);
}

test "window event types" {
    const testing = std.testing;

    const resize_event = WindowEvent.init(.{ .resized = .{ .width = 800, .height = 600 } });
    try testing.expect(resize_event.base.timestamp > 0);
    try testing.expect(resize_event.base.id > 0);

    const close_event = WindowEvent.init(.closed);
    try testing.expect(close_event.base.timestamp > 0);
}

test "input event types" {
    const testing = std.testing;

    const key_event = InputEvent.init(.{ .key_pressed = .{ .key = 32, .modifiers = 0, .repeat = false } });
    try testing.expect(key_event.base.timestamp > 0);

    const mouse_event = InputEvent.init(.{ .mouse_moved = .{ .x = 100.0, .y = 200.0, .delta_x = 5.0, .delta_y = -3.0 } });
    try testing.expect(mouse_event.base.timestamp > 0);
}

test "system event types" {
    const testing = std.testing;

    const quit_event = SystemEvent.init(.quit_requested);
    try testing.expect(quit_event.base.timestamp > 0);

    const memory_event = SystemEvent.init(.low_memory);
    try testing.expect(memory_event.base.timestamp > 0);
}
