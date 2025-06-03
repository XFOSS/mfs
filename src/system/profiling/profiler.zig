//! MFS Profiling System
//!
//! This module provides a comprehensive profiling system for tracking performance metrics
//! including CPU time, GPU time, memory allocations, and custom counters.
//!
//! Usage:
//! ```
//! const Profiler = @import("system/profiling/profiler.zig").Profiler;
//!
//! // Begin a timed section
//! const zone_id = Profiler.beginZone("Physics Update");
//! defer Profiler.endZone(zone_id);
//!
//! // Record a specific event
//! Profiler.markEvent("Object Spawned");
//!
//! // Track a counter
//! Profiler.trackCounter("Active Particles", particle_count);
//! ```

const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const Timer = std.time.Timer;

// Conditional Tracy integration
const tracy = if (@hasDecl(build_options, "enable_tracy") and build_options.enable_tracy)
    @import("tracy")
else
    struct {
        pub fn ZoneN(comptime name: []const u8) void {}
        pub fn ZoneC(color: u32) void {}
        pub fn ZoneNC(comptime name: []const u8, color: u32) void {}
        pub fn ZoneEnd() void {}
        pub fn FrameMark() void {}
        pub fn FrameMarkNamed(comptime name: []const u8) void {}
        pub fn Message(comptime text: []const u8) void {}
        pub fn MessageL(text: []const u8) void {}
        pub fn AllocationContext(ptr: ?*anyopaque, size: usize) void {}
        pub fn FreeContext(ptr: ?*anyopaque) void {}
        pub fn PlotValue(comptime name: []const u8, value: f64) void {}
    };

/// Maximum number of profiled zones that can be active at once
pub const MAX_ZONE_STACK_DEPTH = 32;

/// Maximum number of entries in the profiling history
pub const MAX_HISTORY_ENTRIES = 256;

/// Color definitions for different profile categories
pub const Colors = struct {
    pub const Rendering = 0x2E86C1; // Blue
    pub const Physics = 0x28B463; // Green
    pub const Audio = 0x8E44AD; // Purple
    pub const IO = 0xD35400; // Orange
    pub const Logic = 0xF1C40F; // Yellow
    pub const Memory = 0xE74C3C; // Red
    pub const System = 0x7F8C8D; // Gray
    pub const Network = 0x9B59B6; // Violet
    pub const AI = 0x2ECC71; // Emerald
    pub const UI = 0x3498DB; // Light Blue
};

/// Identifies a specific profiling zone
pub const ZoneId = u32;

/// Represents a profiling event entry
pub const ProfileEntry = struct {
    /// Unique name of the profiled zone
    name: []const u8,
    /// Color used for visualizing this zone
    color: u32,
    /// Start time in nanoseconds
    start_time: u64,
    /// End time in nanoseconds
    end_time: u64 = 0,
    /// Parent zone ID
    parent_id: ?ZoneId = null,
    /// Thread ID this zone was recorded on
    thread_id: std.Thread.Id,
    /// Optional custom data associated with the zone
    custom_data: ?[]const u8 = null,

    /// Calculate duration in nanoseconds
    pub fn duration(self: ProfileEntry) u64 {
        return if (self.end_time > 0) self.end_time - self.start_time else 0;
    }
};

/// Represents a performance counter with a name and value
pub const CounterEntry = struct {
    name: []const u8,
    value: f64,
    timestamp: u64,
};

/// Represents a memory allocation for tracking
pub const MemoryAllocation = struct {
    /// Pointer to the allocated memory
    ptr: *anyopaque,
    /// Size of the allocation in bytes
    size: usize,
    /// Timestamp when the allocation was made
    timestamp: u64,
    /// Thread ID that made the allocation
    thread_id: std.Thread.Id,
    /// Source location information (if available)
    source_file: ?[]const u8 = null,
    /// Line number in source file
    source_line: ?u32 = null,
    /// Whether this allocation has been freed
    freed: bool = false,
    /// Timestamp when the allocation was freed (if applicable)
    free_timestamp: ?u64 = null,
    /// Allocation category/tag for grouping
    category: []const u8 = "default",
};

/// The main profiling system
pub const Profiler = struct {
    // Maximum number of memory allocations to track
    pub const MAX_MEMORY_ALLOCATIONS = 10000;

    // Only use atomics when multithreading
    const AtomicCounter = if (builtin.single_threaded)
        struct {
            value: usize = 0,
            pub fn fetchAdd(self: *@This(), operand: usize) usize {
                const result = self.value;
                self.value += operand;
                return result;
            }
        }
    else
        std.atomic.Value(usize);

    // Global state
    var is_initialized: bool = false;
    var allocator: ?std.mem.Allocator = null;
    var global_timer: ?Timer = null;
    var zone_stack: [MAX_ZONE_STACK_DEPTH]ZoneId = undefined;
    var zone_stack_depth: AtomicCounter = if (builtin.single_threaded) .{} else .{ .value = 0 };

    // Collected data
    var entries: std.ArrayList(ProfileEntry) = undefined;
    var counters: std.ArrayList(CounterEntry) = undefined;
    mutexes: struct {
        entries: std.Thread.Mutex = .{},
        counters: std.Thread.Mutex = .{},
        memory: std.Thread.Mutex = .{},
    } = .{},

    // Memory tracking
    memory_allocations: std.AutoHashMap(*anyopaque, MemoryAllocation) = undefined,
    total_allocated: usize = 0,

    var frame_start_time: u64 = 0;
    var frame_count: usize = 0;
    var enabled: bool = true;

    /// Initialize the profiler
    pub fn init(alloc: std.mem.Allocator) !void {
        if (is_initialized) return;

        allocator = alloc;
        entries = std.ArrayList(ProfileEntry).init(alloc);
        counters = std.ArrayList(CounterEntry).init(alloc);
        memory_allocations = std.AutoHashMap(*anyopaque, MemoryAllocation).init(alloc);
        total_allocated = 0;
        global_timer = try Timer.start();
        is_initialized = true;

        // Start tracking memory usage immediately
        try trackCounter("Memory Used", 0);
        try markEvent("Profiler Initialized");
    }

    /// Clean up profiler resources
    pub fn deinit() void {
        if (!is_initialized) return;

        // Free memory allocation records
        {
            mutexes.memory.lock();
            defer mutexes.memory.unlock();

            // Free source file and category strings
            var it = memory_allocations.valueIterator();
            while (it.next()) |alloc| {
                if (alloc.source_file) |src_file| {
                    allocator.?.free(src_file);
                }
                // Only free category if it's not the default value
                if (!std.mem.eql(u8, alloc.category, "default")) {
                    allocator.?.free(alloc.category);
                }
            }

            memory_allocations.deinit();
        }

        entries.deinit();
        counters.deinit();
        allocator = null;
        global_timer = null;
        is_initialized = false;
    }

    /// Enable or disable profiling
    pub fn setEnabled(enable: bool) void {
        enabled = enable;
    }

    /// Begin a new profiling zone
    pub fn beginZone(name: []const u8) ZoneId {
        return beginZoneWithColor(name, Colors.System);
    }

    /// Begin a new profiling zone with a specific color
    pub fn beginZoneWithColor(name: []const u8, color: u32) ZoneId {
        if (!enabled or !is_initialized) return 0;

        // Start Tracy zone if available
        if (build_options.enable_tracy) {
            tracy.ZoneNC(name, color);
        }

        // Get current time
        const now = getTime();

        // Track zone in stack
        const stack_pos = zone_stack_depth.fetchAdd(1);
        if (stack_pos >= MAX_ZONE_STACK_DEPTH) {
            std.log.warn("Profiler zone stack overflow. Too many nested zones!", .{});
            return 0;
        }

        // Create the entry
        const zone_id = @intCast(ZoneId, entries.items.len + 1); // 1-based IDs, 0 is invalid
        zone_stack[stack_pos] = zone_id;

        // Get parent from zone stack if we have one
        const parent_id = if (stack_pos > 0) zone_stack[stack_pos - 1] else null;

        mutexes.entries.lock();
        defer mutexes.entries.unlock();

        // Add entry to list
        entries.append(.{
            .name = name,
            .color = color,
            .start_time = now,
            .parent_id = parent_id,
            .thread_id = std.Thread.getCurrentId(),
        }) catch {
            std.log.err("Failed to add profile entry", .{});
            return 0;
        };

        return zone_id;
    }

    /// End the current profiling zone
    pub fn endZone(zone_id: ZoneId) void {
        if (!enabled or !is_initialized or zone_id == 0) return;

        // End Tracy zone if available
        if (build_options.enable_tracy) {
            tracy.ZoneEnd();
        }

        // Get current time
        const now = getTime();

        if (zone_stack_depth.value == 0) {
            std.log.warn("Profiler zone stack underflow. Too many endZone calls!", .{});
            return;
        }

        // Decrement zone stack
        _ = zone_stack_depth.fetchAdd(@as(usize, @bitCast(@as(isize, -1))));

        // Update the entry with end time
        const entry_index = zone_id - 1;

        mutexes.entries.lock();
        defer mutexes.entries.unlock();

        if (entry_index < entries.items.len) {
            entries.items[entry_index].end_time = now;
        }
    }

    /// Record an instantaneous event
    pub fn markEvent(name: []const u8) !void {
        if (!enabled or !is_initialized) return;

        // Log with Tracy if available
        if (build_options.enable_tracy) {
            tracy.Message(name);
        }

        const now = getTime();

        mutexes.entries.lock();
        defer mutexes.entries.unlock();

        try entries.append(.{
            .name = name,
            .color = Colors.System,
            .start_time = now,
            .end_time = now, // Zero duration
            .thread_id = std.Thread.getCurrentId(),
        });
    }

    /// Track a named counter value
    pub fn trackCounter(name: []const u8, value: f64) !void {
        if (!enabled or !is_initialized) return;

        // Plot with Tracy if available
        if (build_options.enable_tracy) {
            tracy.PlotValue(name, value);
        }

        mutexes.counters.lock();
        defer mutexes.counters.unlock();

        try counters.append(.{
            .name = name,
            .value = value,
            .timestamp = getTime(),
        });
    }

    /// Begin a new frame
    pub fn beginFrame() void {
        if (!enabled or !is_initialized) return;

        // Mark frame with Tracy if available
        if (build_options.enable_tracy) {
            tracy.FrameMark();
        }

        frame_start_time = getTime();
        markEvent("Frame Start") catch {};
    }

    /// End the current frame
    pub fn endFrame() !void {
        if (!enabled or !is_initialized) return;

        const frame_end_time = getTime();
        const frame_time = frame_end_time - frame_start_time;

        frame_count += 1;
        try trackCounter("Frame Time (ms)", @as(f64, @floatFromInt(frame_time)) / 1_000_000.0);
        try markEvent("Frame End");

        // Trim history if it gets too large
        if (entries.items.len > MAX_HISTORY_ENTRIES) {
            mutexes.entries.lock();
            defer mutexes.entries.unlock();

            const to_remove = entries.items.len - MAX_HISTORY_ENTRIES;
            if (to_remove > 0) {
                std.mem.copy(ProfileEntry, entries.items[0 .. entries.items.len - to_remove], entries.items[to_remove..]);
                entries.shrinkRetainingCapacity(entries.items.len - to_remove);
            }
        }

        if (counters.items.len > MAX_HISTORY_ENTRIES) {
            mutexes.counters.lock();
            defer mutexes.counters.unlock();

            const to_remove = counters.items.len - MAX_HISTORY_ENTRIES;
            if (to_remove > 0) {
                std.mem.copy(CounterEntry, counters.items[0 .. counters.items.len - to_remove], counters.items[to_remove..]);
                counters.shrinkRetainingCapacity(counters.items.len - to_remove);
            }
        }
    }

    /// Remember memory allocation for profiling
    pub fn trackAllocation(ptr: ?*anyopaque, size: usize, category: ?[]const u8, file: ?[]const u8, line: ?u32) void {
        if (!enabled or !is_initialized or ptr == null) return;

        if (build_options.enable_tracy) {
            tracy.AllocationContext(ptr, size);
        }

        mutexes.memory.lock();
        defer mutexes.memory.unlock();

        // Track total allocated memory
        total_allocated += size;

        // Store allocation record
        const alloc = MemoryAllocation{
            .ptr = ptr.?,
            .size = size,
            .timestamp = getTime(),
            .thread_id = std.Thread.getCurrentId(),
            .source_file = if (file) |f| allocator.?.dupe(u8, f) catch null else null,
            .source_line = line,
            .category = if (category) |c| allocator.?.dupe(u8, c) catch "default" else "default",
        };

        // Limit number of tracked allocations to avoid memory exhaustion
        if (memory_allocations.count() < MAX_MEMORY_ALLOCATIONS) {
            memory_allocations.put(ptr.?, alloc) catch {};
        }

        // Update counter - we catch and ignore errors here since this function has void return
        _ = trackCounter("Memory Used", @as(f64, @floatFromInt(total_allocated))) catch {};

        // Track allocation by category if we have one
        if (category) |cat| {
            const counter_name = std.fmt.allocPrint(allocator.?, "Memory: {s}", .{cat}) catch "Memory: unknown";
            defer if (std.mem.eql(u8, counter_name, "Memory: unknown")) {} else allocator.?.free(counter_name);

            _ = trackCounter(counter_name, @as(f64, @floatFromInt(size))) catch {};
        }
    }

    /// Remember memory deallocation for profiling
    pub fn trackDeallocation(ptr: ?*anyopaque) void {
        if (!enabled or !is_initialized or ptr == null) return;

        if (build_options.enable_tracy) {
            tracy.FreeContext(ptr);
        }

        mutexes.memory.lock();
        defer mutexes.memory.unlock();

        // Find the allocation and update its status
        if (memory_allocations.getPtr(ptr.?)) |alloc| {
            total_allocated -= alloc.size;
            alloc.freed = true;
            alloc.free_timestamp = getTime();

            // Update counter - ignore errors since this function has void return
            _ = trackCounter("Memory Used", @as(f64, @floatFromInt(total_allocated))) catch {};

            // Track deallocation by category if we have one
            if (alloc.category.len > 0) {
                const counter_name = std.fmt.allocPrint(allocator.?, "Memory: {s}", .{alloc.category}) catch "Memory: unknown";
                defer if (std.mem.eql(u8, counter_name, "Memory: unknown")) {} else allocator.?.free(counter_name);

                // Use negative value to track deallocations
                _ = trackCounter(counter_name, -@as(f64, @floatFromInt(alloc.size))) catch {};
            }
        }
    }

    /// Get all current memory allocations
    pub fn getMemoryAllocations() []MemoryAllocation {
        var result = std.ArrayList(MemoryAllocation).init(std.heap.page_allocator);
        defer result.deinit();

        mutexes.memory.lock();
        defer mutexes.memory.unlock();

        var it = memory_allocations.valueIterator();
        while (it.next()) |alloc| {
            result.append(alloc.*) catch continue;
        }

        return result.toOwnedSlice() catch &[_]MemoryAllocation{};
    }

    /// Get memory statistics
    pub fn getMemoryStats() struct {
        total_bytes: usize,
        allocation_count: usize,
        live_allocation_count: usize,
    } {
        mutexes.memory.lock();
        defer mutexes.memory.unlock();

        var live_count: usize = 0;
        var it = memory_allocations.valueIterator();
        while (it.next()) |alloc| {
            if (!alloc.freed) live_count += 1;
        }

        return .{
            .total_bytes = total_allocated,
            .allocation_count = memory_allocations.count(),
            .live_allocation_count = live_count,
        };
    }

    /// Get all profile entries for analysis
    pub fn getEntries() []const ProfileEntry {
        mutexes.entries.lock();
        defer mutexes.entries.unlock();

        return entries.items;
    }

    /// Get all counter entries for analysis
    pub fn getCounters() []const CounterEntry {
        mutexes.counters.lock();
        defer mutexes.counters.unlock();

        return counters.items;
    }

    /// Save profiling data to a file
    pub fn saveToFile(path: []const u8) !void {
        if (!is_initialized) return error.ProfilerNotInitialized;

        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        const writer = file.writer();

        // Write header
        try writer.writeAll("# MFS Profiler Data\n");
        try writer.print("# Frames: {d}\n", .{frame_count});
        try writer.writeAll("# Timestamp,Type,Name,Duration,ThreadId,ParentId,Color\n");
        try writer.writeAll("# Memory allocations have Type='alloc' or 'free'\n");

        // Write zones
        mutexes.entries.lock();
        for (entries.items) |entry| {
            const duration = entry.duration();
            try writer.print("{d},zone,\"{s}\",{d},{d},{d},{x}\n", .{
                entry.start_time,
                entry.name,
                duration,
                entry.thread_id,
                entry.parent_id orelse 0,
                entry.color,
            });
        }
        mutexes.entries.unlock();

        // Write counters
        mutexes.counters.lock();
        for (counters.items) |counter| {
            try writer.print("{d},counter,\"{s}\",{d},0,0,0\n", .{
                counter.timestamp,
                counter.name,
                @as(u64, @intFromFloat(counter.value * 1000)),
            });
        }
        mutexes.counters.unlock();

        // Write memory allocations
        mutexes.memory.lock();
        var it = memory_allocations.valueIterator();
        while (it.next()) |alloc| {
            // Write allocation
            try writer.print("{d},alloc,\"{s}\",{d},{d},0,{s}\n", .{
                alloc.timestamp,
                alloc.category,
                alloc.size,
                alloc.thread_id,
                if (alloc.source_file) |f| f else "unknown",
            });

            // Write deallocation if present
            if (alloc.freed and alloc.free_timestamp != null) {
                try writer.print("{d},free,\"{s}\",{d},{d},0,{s}\n", .{
                    alloc.free_timestamp.?,
                    alloc.category,
                    alloc.size,
                    alloc.thread_id,
                    if (alloc.source_file) |f| f else "unknown",
                });
            }
        }
        mutexes.memory.unlock();
    }

    // Get current time in nanoseconds
    fn getTime() u64 {
        if (global_timer) |timer| {
            return timer.read();
        }
        return 0;
    }
};

// Simple scope-based profiling zone
pub const ScopedZone = struct {
    zone_id: ZoneId,

    pub fn init(name: []const u8) ScopedZone {
        return .{ .zone_id = Profiler.beginZone(name) };
    }

    pub fn initWithColor(name: []const u8, color: u32) ScopedZone {
        return .{ .zone_id = Profiler.beginZoneWithColor(name, color) };
    }

    pub fn deinit(self: *ScopedZone) void {
        Profiler.endZone(self.zone_id);
        self.zone_id = 0;
    }
};

// Tracked allocator that reports memory usage to the profiler
/// TrackedAllocator is a wrapper around an allocator that tracks all allocations
/// and reports them to the profiling system
pub const TrackedAllocator = struct {
    parent_allocator: std.mem.Allocator,
    category: ?[]const u8,

    pub fn init(parent_allocator: std.mem.Allocator, category: ?[]const u8) TrackedAllocator {
        return .{
            .parent_allocator = parent_allocator,
            .category = category,
        };
    }

    pub fn allocator(self: *TrackedAllocator) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }

    fn alloc(
        ctx: *anyopaque,
        len: usize,
        log2_ptr_align: u8,
        ret_addr: usize,
    ) ?[*]u8 {
        const self = @ptrCast(*TrackedAllocator, @alignCast(@alignOf(TrackedAllocator), ctx));
        const result = self.parent_allocator.vtable.alloc(self.parent_allocator.ptr, len, log2_ptr_align, ret_addr);

        if (result != null) {
            Profiler.trackAllocation(result, len, self.category, null, // TODO: Capture source location in future versions
                null);
        }

        return result;
    }

    fn resize(
        ctx: *anyopaque,
        buf: []u8,
        log2_buf_align: u8,
        new_len: usize,
        ret_addr: usize,
    ) bool {
        const self = @ptrCast(*TrackedAllocator, @alignCast(@alignOf(TrackedAllocator), ctx));

        // If growing, count as new allocation
        if (new_len > buf.len) {
            Profiler.trackDeallocation(buf.ptr);
            const result = self.parent_allocator.vtable.resize(self.parent_allocator.ptr, buf, log2_buf_align, new_len, ret_addr);

            if (result) {
                Profiler.trackAllocation(buf.ptr, new_len);
            }

            return result;
        } else {
            // If shrinking, just let it happen
            return self.parent_allocator.vtable.resize(self.parent_allocator.ptr, buf, log2_buf_align, new_len, ret_addr);
        }
    }

    fn free(
        ctx: *anyopaque,
        buf: []u8,
        log2_buf_align: u8,
        ret_addr: usize,
    ) void {
        const self = @ptrCast(*TrackedAllocator, @alignCast(@alignOf(TrackedAllocator), ctx));
        Profiler.trackDeallocation(buf.ptr);
        self.parent_allocator.vtable.free(self.parent_allocator.ptr, buf, log2_buf_align, ret_addr);
    }
};

test "basic profiling" {
    // Initialize the profiler
    try Profiler.init(std.testing.allocator);
    defer Profiler.deinit();

    // Basic zone profiling
    const zone = Profiler.beginZone("Test Zone");
    std.time.sleep(1 * std.time.ns_per_ms); // Sleep for 1ms
    Profiler.endZone(zone);

    // Counter tracking
    try Profiler.trackCounter("Test Counter", 42.0);

    // Frame markers
    Profiler.beginFrame();
    std.time.sleep(1 * std.time.ns_per_ms);
    try Profiler.endFrame();

    // Make sure we recorded the data
    const entries = Profiler.getEntries();
    const counters = Profiler.getCounters();

    try std.testing.expect(entries.len >= 3); // At least zone + frame markers
    try std.testing.expect(counters.len >= 2); // Counter + frame time

    // Check zone timing
    const zone_entry = entries[0];
    try std.testing.expectEqualStrings("Test Zone", zone_entry.name);
    try std.testing.expect(zone_entry.duration() >= 1 * std.time.ns_per_ms);

    // Check counter
    const counter_entry = counters[0];
    try std.testing.expectEqualStrings("Test Counter", counter_entry.name);
    try std.testing.expectEqual(42.0, counter_entry.value);
}
