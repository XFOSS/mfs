//! MFS Engine - Event System
//! High-performance event system with type-safe events and handlers
//! @thread-safe Event system is thread-safe with proper synchronization
//! @symbol EventSystem

const std = @import("std");
const types = @import("types.zig");

/// Core event types used throughout the engine
pub const Event = union(enum) {
    // Input events
    key_press: struct { key: u32, timestamp: i64 },
    key_release: struct { key: u32, timestamp: i64 },
    mouse_move: struct { x: f32, y: f32, timestamp: i64 },
    mouse_press: struct { button: u32, x: f32, y: f32, timestamp: i64 },
    mouse_release: struct { button: u32, x: f32, y: f32, timestamp: i64 },
    mouse_wheel: struct { delta_x: f32, delta_y: f32, timestamp: i64 },

    // Touch events
    touch_start: struct { id: u32, x: f32, y: f32, timestamp: i64 },
    touch_move: struct { id: u32, x: f32, y: f32, timestamp: i64 },
    touch_end: struct { id: u32, x: f32, y: f32, timestamp: i64 },

    // Window events
    window_resize: struct { width: u32, height: u32, timestamp: i64 },
    window_close: struct { timestamp: i64 },
    window_focus: struct { focused: bool, timestamp: i64 },
    window_minimize: struct { minimized: bool, timestamp: i64 },

    // System events
    app_quit: struct { timestamp: i64 },
    app_pause: struct { timestamp: i64 },
    app_resume: struct { timestamp: i64 },

    // Custom events
    custom: struct { type_id: u32, data: ?*anyopaque, timestamp: i64 },

    pub fn getTimestamp(self: Event) i64 {
        return switch (self) {
            inline else => |event| event.timestamp,
        };
    }

    pub fn getType(self: Event) EventType {
        return switch (self) {
            .key_press => .input,
            .key_release => .input,
            .mouse_move => .input,
            .mouse_press => .input,
            .mouse_release => .input,
            .mouse_wheel => .input,
            .touch_start => .input,
            .touch_move => .input,
            .touch_end => .input,
            .window_resize => .window,
            .window_close => .window,
            .window_focus => .window,
            .window_minimize => .window,
            .app_quit => .system,
            .app_pause => .system,
            .app_resume => .system,
            .custom => .custom,
        };
    }
};

pub const EventType = enum {
    input,
    window,
    system,
    custom,
};

/// Event handler function type
pub const EventHandler = struct {
    callback: *const fn (Event, *anyopaque) void,
    context: *anyopaque,
    priority: Priority = .normal,
    filter: ?EventType = null,

    pub const Priority = enum(u8) {
        low = 0,
        normal = 1,
        high = 2,
        critical = 3,
    };

    pub fn matches(self: EventHandler, event: Event) bool {
        return self.filter == null or self.filter.? == event.getType();
    }
};

/// High-performance event system with priority handling
pub const EventSystem = struct {
    allocator: std.mem.Allocator,
    handlers: std.ArrayList(EventHandler),
    event_queue: std.ArrayList(Event),
    immediate_events: std.ArrayList(Event),
    mutex: std.Thread.Mutex,
    max_queue_size: u32,
    stats: Stats,

    const Self = @This();

    pub const Stats = struct {
        events_processed: u64 = 0,
        events_dropped: u64 = 0,
        handlers_called: u64 = 0,
        average_process_time_ns: u64 = 0,

        pub fn reset(self: *Stats) void {
            self.events_processed = 0;
            self.events_dropped = 0;
            self.handlers_called = 0;
            self.average_process_time_ns = 0;
        }
    };

    pub fn init(allocator: std.mem.Allocator, max_queue_size: u32) Self {
        return Self{
            .allocator = allocator,
            .handlers = std.ArrayList(EventHandler).init(allocator),
            .event_queue = std.ArrayList(Event).init(allocator),
            .immediate_events = std.ArrayList(Event).init(allocator),
            .mutex = std.Thread.Mutex{},
            .max_queue_size = max_queue_size,
            .stats = Stats{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.handlers.deinit();
        self.event_queue.deinit();
        self.immediate_events.deinit();
    }

    /// Add an event handler with optional priority and filter
    pub fn addHandler(self: *Self, handler: EventHandler) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Insert handler based on priority (higher priority first)
        var insert_index: usize = 0;
        for (self.handlers.items, 0..) |existing_handler, i| {
            if (@intFromEnum(handler.priority) > @intFromEnum(existing_handler.priority)) {
                insert_index = i;
                break;
            }
            insert_index = i + 1;
        }

        try self.handlers.insert(insert_index, handler);
    }

    /// Remove an event handler
    pub fn removeHandler(self: *Self, callback: *const fn (Event, *anyopaque) void, context: *anyopaque) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var i: usize = 0;
        while (i < self.handlers.items.len) {
            const handler = self.handlers.items[i];
            if (handler.callback == callback and handler.context == context) {
                _ = self.handlers.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }

    /// Push an event to the queue
    pub fn pushEvent(self: *Self, event: Event) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.event_queue.items.len >= self.max_queue_size) {
            self.stats.events_dropped += 1;
            return;
        }

        try self.event_queue.append(event);
    }

    /// Push an event for immediate processing (bypasses queue)
    pub fn pushImmediateEvent(self: *Self, event: Event) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.immediate_events.append(event);
    }

    /// Process all queued events
    pub fn processEvents(self: *Self) void {
        const start_time = std.time.nanoTimestamp();

        // Process immediate events first
        self.processImmediateEvents();

        // Process queued events
        self.mutex.lock();
        const events_to_process = self.event_queue.toOwnedSlice() catch return;
        self.mutex.unlock();
        defer self.allocator.free(events_to_process);

        for (events_to_process) |event| {
            self.processEvent(event);
            self.stats.events_processed += 1;
        }

        const end_time = std.time.nanoTimestamp();
        const process_time = @as(u64, @intCast(end_time - start_time));

        // Update average processing time (simple moving average)
        if (self.stats.events_processed > 0) {
            self.stats.average_process_time_ns =
                (self.stats.average_process_time_ns + process_time) / 2;
        } else {
            self.stats.average_process_time_ns = process_time;
        }
    }

    fn processImmediateEvents(self: *Self) void {
        self.mutex.lock();
        const immediate_events = self.immediate_events.toOwnedSlice() catch return;
        self.mutex.unlock();
        defer self.allocator.free(immediate_events);

        for (immediate_events) |event| {
            self.processEvent(event);
        }
    }

    fn processEvent(self: *Self, event: Event) void {
        for (self.handlers.items) |handler| {
            if (handler.matches(event)) {
                handler.callback(event, handler.context);
                self.stats.handlers_called += 1;
            }
        }
    }

    /// Get event system statistics
    pub fn getStats(self: *const Self) Stats {
        return self.stats;
    }

    /// Clear all events and reset statistics
    pub fn clear(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.event_queue.clearRetainingCapacity();
        self.immediate_events.clearRetainingCapacity();
        self.stats.reset();
    }
};

test "event system" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var event_system = EventSystem.init(allocator, 100);
    defer event_system.deinit();

    // Test adding handler
    var test_context: u32 = 0;
    const test_handler = EventHandler{
        .callback = testEventHandler,
        .context = &test_context,
        .priority = .high,
        .filter = .input,
    };

    try event_system.addHandler(test_handler);

    // Test event processing
    const test_event = Event{ .key_press = .{ .key = 42, .timestamp = 123456 } };
    try event_system.pushEvent(test_event);

    event_system.processEvents();

    try testing.expect(test_context == 42);
}

fn testEventHandler(event: Event, context: *anyopaque) void {
    const test_context = @as(*u32, @ptrCast(@alignCast(context)));
    switch (event) {
        .key_press => |key_event| {
            test_context.* = key_event.key;
        },
        else => {},
    }
}
