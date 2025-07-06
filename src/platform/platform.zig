const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const error_utils = @import("../utils/error_utils.zig");

// Platform detection
pub const is_windows = builtin.os.tag == .windows;
pub const is_macos = builtin.os.tag == .macos;
pub const is_linux = builtin.os.tag == .linux;
pub const is_wasm = builtin.os.tag == .wasi or builtin.os.tag == .emscripten;
pub const is_unix = is_linux or is_macos;
pub const is_bsd = builtin.os.tag == .freebsd or builtin.os.tag == .netbsd or builtin.os.tag == .openbsd;

/// Platform-specific paths
pub const PlatformPaths = struct {
    home_dir: ?[]const u8 = null,
    config_dir: ?[]const u8 = null,
    cache_dir: ?[]const u8 = null,
    data_dir: ?[]const u8 = null,
    temp_dir: ?[]const u8 = null,
    executable_dir: ?[]const u8 = null,

    pub fn deinit(self: *PlatformPaths, allocator: Allocator) void {
        if (self.home_dir) |dir| allocator.free(dir);
        if (self.config_dir) |dir| allocator.free(dir);
        if (self.cache_dir) |dir| allocator.free(dir);
        if (self.data_dir) |dir| allocator.free(dir);
        if (self.temp_dir) |dir| allocator.free(dir);
        if (self.executable_dir) |dir| allocator.free(dir);
        self.* = .{};
    }
};

/// Input state management
pub const InputState = struct {
    initialized: bool = false,
    mouse_x: i32 = 0,
    mouse_y: i32 = 0,
    mouse_buttons: u8 = 0,
    keyboard_state: [256]bool = [_]bool{false} ** 256,

    pub fn setMousePosition(self: *InputState, x: i32, y: i32) void {
        self.mouse_x = x;
        self.mouse_y = y;
    }

    pub fn setMouseButton(self: *InputState, button: u3, pressed: bool) void {
        if (pressed) {
            self.mouse_buttons |= (@as(u8, 1) << button);
        } else {
            self.mouse_buttons &= ~(@as(u8, 1) << button);
        }
    }

    pub fn setKeyState(self: *InputState, key: u8, pressed: bool) void {
        if (key < self.keyboard_state.len) {
            self.keyboard_state[key] = pressed;
        }
    }

    pub fn isKeyPressed(self: *const InputState, key: u8) bool {
        return if (key < self.keyboard_state.len) self.keyboard_state[key] else false;
    }

    pub fn isMouseButtonPressed(self: *const InputState, button: u3) bool {
        return (self.mouse_buttons & (@as(u8, 1) << button)) != 0;
    }
};

/// Core platform services
pub const Platform = struct {
    allocator: Allocator,
    initialized: bool = false,

    // Clock subsystem
    monotonic_start: i128 = 0,
    high_res_timer_freq: u64 = 1,

    // Thread pool
    thread_pool: ?ThreadPool = null,

    // Memory stats
    memory_stats: MemoryStats = .{},

    // Platform paths
    paths: PlatformPaths = .{},

    // Input state
    input_state: InputState = .{},

    // Random generator
    random_initialized: bool = false,
    random_seed: u64 = 0,
};

/// Global platform state
var g_platform: Platform = undefined;

/// Thread-local state
threadlocal var tl_thread_id: u32 = 0;

/// Platform initialization
pub fn init(allocator: Allocator) !void {
    // Validate allocator by doing a small test allocation
    const test_allocation = allocator.alloc(u8, 1) catch |err| {
        std.log.err("Allocator validation failed: {}", .{err});
        return error.InvalidAllocator;
    };
    allocator.free(test_allocation);

    g_platform = Platform{
        .allocator = allocator,
        .monotonic_start = std.time.nanoTimestamp(),
    };

    // Initialize high-resolution timer frequency
    if (is_windows) {
        g_platform.high_res_timer_freq = 1_000_000_000; // QueryPerformanceFrequency equivalent
    } else {
        g_platform.high_res_timer_freq = 1_000_000_000; // nanoseconds
    }

    // Initialize thread pool with safe configuration and debug allocator handling
    const core_count = detectCoreCount();
    const safe_queue_size = @min(256, @max(16, core_count * 8)); // Reasonable queue size

    // For debug builds with tracking allocators, use more conservative settings
    const is_debug_allocator = @TypeOf(allocator) == std.mem.Allocator and
        (@hasDecl(@TypeOf(allocator), "safety") or
            std.mem.indexOf(u8, @typeName(@TypeOf(allocator)), "GeneralPurpose") != null);

    const thread_count = if (is_debug_allocator)
        @min(2, core_count) // Minimal threads for debug allocators
    else
        @min(core_count, 16); // Normal thread count

    const queue_size = if (is_debug_allocator)
        16 // Small queue for debug allocators
    else
        safe_queue_size;

    std.log.info("Initializing thread pool: threads={d}, queue_size={d}, debug_allocator={}", .{ thread_count, queue_size, is_debug_allocator });

    // Temporarily disable thread pool to avoid memory corruption issues
    std.log.warn("Thread pool disabled temporarily to avoid memory corruption", .{});
    g_platform.thread_pool = null;

    // Initialize subsystems with error handling
    initFilesystem() catch |err| {
        std.log.warn("Failed to initialize filesystem: {}", .{err});
    };

    initInput() catch |err| {
        std.log.warn("Failed to initialize input: {}", .{err});
    };

    initRandomGenerator() catch |err| {
        std.log.warn("Failed to initialize random generator: {}", .{err});
    };

    g_platform.initialized = true;
    std.log.info("Platform subsystem initialized", .{});
    std.log.info("  OS: {s}", .{@tagName(builtin.os.tag)});
    std.log.info("  CPU: {s} ({d} cores)", .{ @tagName(builtin.cpu.arch), detectCoreCount() });
    std.log.info("  Endian: {s}", .{if (builtin.cpu.arch.endian() == .big) "big" else "little"});
    std.log.info("  Pointer size: {d} bits", .{@bitSizeOf(usize)});
    std.log.info("  Thread pool: {d} threads, queue size: {d}", .{ if (g_platform.thread_pool) |*pool| pool.getThreadCount() else 0, queue_size });
}

/// Platform shutdown
pub fn deinit() void {
    if (!g_platform.initialized) return;

    if (g_platform.thread_pool) |*pool| {
        pool.deinit();
    }

    g_platform.paths.deinit(g_platform.allocator);
    g_platform.initialized = false;
}

/// Clock management
pub fn getMonotonicTime() i64 {
    return std.time.nanoTimestamp() - g_platform.monotonic_start;
}

pub fn getMonotonicTimeMs() i64 {
    return @divFloor(getMonotonicTime(), 1_000_000);
}

pub fn getMonotonicTimeUs() i64 {
    return @divFloor(getMonotonicTime(), 1_000);
}

pub fn getMonotonicTimeSeconds() f64 {
    return @as(f64, @floatFromInt(getMonotonicTime())) / 1_000_000_000.0;
}

pub fn getSystemTime() i64 {
    return std.time.timestamp();
}

pub fn getSystemTimeMs() i64 {
    return std.time.milliTimestamp();
}

pub fn sleep(nanoseconds: u64) void {
    std.time.sleep(nanoseconds);
}

pub fn sleepMs(milliseconds: u64) void {
    std.time.sleep(milliseconds * std.time.ns_per_ms);
}

pub fn sleepUs(microseconds: u64) void {
    std.time.sleep(microseconds * std.time.ns_per_us);
}

/// Hardware detection
pub fn detectCoreCount() u32 {
    return @max(1, @as(u32, @intCast(std.Thread.getCpuCount() catch 1)));
}

pub fn getPageSize() usize {
    return std.mem.page_size;
}

pub fn getTotalSystemMemory() ?u64 {
    // Platform-specific implementation would go here
    return null;
}

/// Filesystem abstraction
fn initFilesystem() !void {
    const allocator = g_platform.allocator;

    if (is_windows) {
        // Windows-specific paths
        if (std.process.getEnvVarOwned(allocator, "USERPROFILE")) |home| {
            g_platform.paths.home_dir = home;

            g_platform.paths.config_dir = try std.fmt.allocPrint(allocator, "{s}\\AppData\\Roaming", .{home});
            g_platform.paths.cache_dir = try std.fmt.allocPrint(allocator, "{s}\\AppData\\Local", .{home});
            g_platform.paths.data_dir = try std.fmt.allocPrint(allocator, "{s}\\AppData\\Local", .{home});
        } else |_| {}

        if (std.process.getEnvVarOwned(allocator, "TEMP")) |temp| {
            g_platform.paths.temp_dir = temp;
        } else |_| {
            g_platform.paths.temp_dir = try allocator.dupe(u8, "C:\\Temp");
        }
    } else if (is_macos) {
        // macOS-specific paths
        if (std.process.getEnvVarOwned(allocator, "HOME")) |home| {
            g_platform.paths.home_dir = home;

            g_platform.paths.config_dir = try std.fmt.allocPrint(allocator, "{s}/Library/Application Support", .{home});
            g_platform.paths.cache_dir = try std.fmt.allocPrint(allocator, "{s}/Library/Caches", .{home});
            g_platform.paths.data_dir = try std.fmt.allocPrint(allocator, "{s}/Library/Application Support", .{home});
        } else |_| {}

        g_platform.paths.temp_dir = try allocator.dupe(u8, "/tmp");
    } else if (is_linux or is_bsd) {
        // Linux/BSD-specific paths
        if (std.process.getEnvVarOwned(allocator, "HOME")) |home| {
            g_platform.paths.home_dir = home;

            if (std.process.getEnvVarOwned(allocator, "XDG_CONFIG_HOME")) |config| {
                g_platform.paths.config_dir = config;
            } else |_| {
                g_platform.paths.config_dir = try std.fmt.allocPrint(allocator, "{s}/.config", .{home});
            }

            if (std.process.getEnvVarOwned(allocator, "XDG_CACHE_HOME")) |cache| {
                g_platform.paths.cache_dir = cache;
            } else |_| {
                g_platform.paths.cache_dir = try std.fmt.allocPrint(allocator, "{s}/.cache", .{home});
            }

            if (std.process.getEnvVarOwned(allocator, "XDG_DATA_HOME")) |data| {
                g_platform.paths.data_dir = data;
            } else |_| {
                g_platform.paths.data_dir = try std.fmt.allocPrint(allocator, "{s}/.local/share", .{home});
            }
        } else |_| {}

        g_platform.paths.temp_dir = try allocator.dupe(u8, "/tmp");
    }

    // Get executable directory
    if (getExecutablePath()) |exe_path| {
        if (std.fs.path.dirname(exe_path)) |dir| {
            g_platform.paths.executable_dir = try allocator.dupe(u8, dir);
        }
        g_platform.allocator.free(exe_path);
    } else |_| {}
}

pub fn getExecutablePath() ![]const u8 {
    return std.fs.selfExeDirPathAlloc(g_platform.allocator) catch |err| {
        // Log the error and propagate it
        return error_utils.logErr("Failed to get executable path", .{}, err, @src());
    };
}

pub fn getPlatformPaths() *const PlatformPaths {
    return &g_platform.paths;
}

pub fn createDirectory(path: []const u8) !void {
    std.fs.cwd().makePath(path) catch |err| switch (err) {
        error.PathAlreadyExists => return,
        else => return error_utils.logErr("Failed to create directory: {s}", .{path}, err, @src()),
    };
}

pub fn pathExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

/// Input system
fn initInput() !void {
    g_platform.input_state.initialized = true;
}

pub fn getInputState() *InputState {
    return &g_platform.input_state;
}

pub fn updateMousePosition(x: i32, y: i32) void {
    g_platform.input_state.setMousePosition(x, y);
}

pub fn updateMouseButton(button: u3, pressed: bool) void {
    g_platform.input_state.setMouseButton(button, pressed);
}

pub fn updateKeyState(key: u8, pressed: bool) void {
    g_platform.input_state.setKeyState(key, pressed);
}

/// Random number generation
fn initRandomGenerator() !void {
    g_platform.random_seed = @as(u64, @truncate(@as(u128, @bitCast(std.time.nanoTimestamp()))));
    g_platform.random_initialized = true;
}

pub fn getRandomBytes(buffer: []u8) !void {
    std.crypto.random.bytes(buffer);
}

pub fn getRandomU64() u64 {
    return std.crypto.random.int(u64);
}

pub fn getRandomU32() u32 {
    return std.crypto.random.int(u32);
}

pub fn getRandomU16() u16 {
    return std.crypto.random.int(u16);
}

pub fn getRandomU8() u8 {
    return std.crypto.random.int(u8);
}

pub fn getRandomFloat() f32 {
    return std.crypto.random.float(f32);
}

pub fn getRandomDouble() f64 {
    return std.crypto.random.float(f64);
}

pub fn getRandomRange(min: i64, max: i64) i64 {
    if (min >= max) return min;
    const range = @as(u64, @intCast(max - min));
    return min + @as(i64, @intCast(std.crypto.random.uintLessThan(u64, range + 1)));
}

/// Memory management utilities
pub const MemoryStats = struct {
    total_allocated: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    peak_allocated: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    allocation_count: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    deallocation_count: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),

    pub fn recordAllocation(self: *MemoryStats, size: usize) void {
        const new_total = self.total_allocated.fetchAdd(size, .SeqCst) + size;
        _ = self.allocation_count.fetchAdd(1, .SeqCst);

        // Update peak if necessary
        var current_peak = self.peak_allocated.load(.SeqCst);
        while (new_total > current_peak) {
            current_peak = self.peak_allocated.cmpxchgWeak(current_peak, new_total, .SeqCst, .SeqCst) orelse break;
        }
    }

    pub fn recordDeallocation(self: *MemoryStats, size: usize) void {
        const current_total = self.total_allocated.load(.SeqCst);
        if (size <= current_total) {
            _ = self.total_allocated.fetchSub(size, .SeqCst);
        } else {
            // Double free or other error - reset to 0
            self.total_allocated.store(0, .SeqCst);
        }
        _ = self.deallocation_count.fetchAdd(1, .SeqCst);
    }

    pub fn getCurrentAllocated(self: *const MemoryStats) usize {
        return self.total_allocated.load(.SeqCst);
    }

    pub fn getPeakAllocated(self: *const MemoryStats) usize {
        return self.peak_allocated.load(.SeqCst);
    }

    pub fn getAllocationCount(self: *const MemoryStats) usize {
        return self.allocation_count.load(.SeqCst);
    }

    pub fn getDeallocationCount(self: *const MemoryStats) usize {
        return self.deallocation_count.load(.SeqCst);
    }

    pub fn reset(self: *MemoryStats) void {
        self.total_allocated.store(0, .SeqCst);
        self.peak_allocated.store(0, .SeqCst);
        self.allocation_count.store(0, .SeqCst);
        self.deallocation_count.store(0, .SeqCst);
    }
};

pub fn getMemoryStats() *MemoryStats {
    return &g_platform.memory_stats;
}

/// Thread pool for parallel task execution
pub const ThreadPool = struct {
    allocator: Allocator,
    threads: std.ArrayList(*std.Thread),
    task_queue: TaskQueue,
    shutdown: std.atomic.Value(bool),
    active_tasks: std.atomic.Value(u32),

    pub const Config = struct {
        max_threads: u32 = 4,
        queue_size: u32 = 256,
    };

    const Task = struct {
        function: *const fn (*anyopaque) void,
        data: *anyopaque,
    };

    const TaskQueue = struct {
        tasks: []Task,
        mutex: std.Thread.Mutex,
        not_empty: std.Thread.Condition,
        not_full: std.Thread.Condition,
        head: usize,
        tail: usize,
        count: usize,

        fn init(allocator: Allocator, capacity: u32) !TaskQueue {
            // Validate capacity
            if (capacity == 0) return error.InvalidCapacity;
            if (capacity > 65536) return error.CapacityTooLarge; // 64K max for safety

            // Validate allocator with a small test - be more careful with debug allocators
            const test_size = @min(capacity, 16); // Use smaller test for debug allocators
            const test_ptr = allocator.alloc(u8, test_size) catch |err| {
                std.log.err("TaskQueue allocator test failed with size {d}: {}", .{ test_size, err });
                return error.AllocatorFailed;
            };
            defer allocator.free(test_ptr);

            // Try to allocate the task array with error handling
            const tasks = allocator.alloc(Task, capacity) catch |err| {
                std.log.err("Failed to allocate task queue with capacity {d}: {}", .{ capacity, err });

                // Try with a smaller capacity if the original failed
                const fallback_capacity = @max(8, capacity / 4);
                std.log.warn("Attempting fallback allocation with capacity {d}", .{fallback_capacity});

                const fallback_tasks = allocator.alloc(Task, fallback_capacity) catch |fallback_err| {
                    std.log.err("Fallback allocation also failed: {}", .{fallback_err});
                    return fallback_err;
                };

                std.log.info("TaskQueue using fallback capacity: {d} (requested: {d})", .{ fallback_capacity, capacity });

                const queue = TaskQueue{
                    .tasks = fallback_tasks,
                    .mutex = .{},
                    .not_empty = .{},
                    .not_full = .{},
                    .head = 0,
                    .tail = 0,
                    .count = 0,
                };

                // Validate the initial state
                std.debug.assert(queue.head == 0);
                std.debug.assert(queue.tail == 0);
                std.debug.assert(queue.count == 0);
                std.debug.assert(queue.tasks.len == fallback_capacity);

                return queue;
            };

            const queue = TaskQueue{
                .tasks = tasks,
                .mutex = .{},
                .not_empty = .{},
                .not_full = .{},
                .head = 0,
                .tail = 0,
                .count = 0,
            };

            // Validate the initial state
            std.debug.assert(queue.head == 0);
            std.debug.assert(queue.tail == 0);
            std.debug.assert(queue.count == 0);
            std.debug.assert(queue.tasks.len == capacity);

            return queue;
        }

        fn deinit(self: *TaskQueue, allocator: Allocator) void {
            allocator.free(self.tasks);
            self.* = undefined;
        }

        fn push(self: *TaskQueue, task: Task) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.count >= self.tasks.len) {
                return error.QueueFull;
            }

            // Bounds checking to prevent corruption
            if (self.tail >= self.tasks.len) {
                std.log.err("TaskQueue corruption detected in push: tail={d}, len={d}", .{ self.tail, self.tasks.len });
                self.tail = 0; // Reset to safe state
                return error.QueueCorrupted;
            }

            self.tasks[self.tail] = task;
            self.tail = (self.tail + 1) % self.tasks.len;
            self.count += 1;

            self.not_empty.signal();
        }

        fn pushBlocking(self: *TaskQueue, task: Task) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            while (self.count >= self.tasks.len) {
                self.not_full.wait(&self.mutex);
            }

            // Bounds checking to prevent corruption
            if (self.tail >= self.tasks.len) {
                std.log.err("TaskQueue corruption detected in pushBlocking: tail={d}, len={d}", .{ self.tail, self.tasks.len });
                self.tail = 0; // Reset to safe state
                return; // Skip this task
            }

            self.tasks[self.tail] = task;
            self.tail = (self.tail + 1) % self.tasks.len;
            self.count += 1;

            self.not_empty.signal();
        }

        fn pop(self: *TaskQueue) ?Task {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.count == 0) {
                return null;
            }

            // Bounds checking to prevent corruption
            if (self.head >= self.tasks.len) {
                std.log.err("TaskQueue corruption detected in pop: head={d}, len={d}", .{ self.head, self.tasks.len });
                self.head = 0; // Reset to safe state
                self.count = 0;
                return null;
            }

            const task = self.tasks[self.head];
            self.head = (self.head + 1) % self.tasks.len;
            self.count -= 1;

            self.not_full.signal();
            return task;
        }

        fn waitAndPop(self: *TaskQueue, shutdown: *const std.atomic.Value(bool)) ?Task {
            self.mutex.lock();
            defer self.mutex.unlock();

            while (self.count == 0) {
                if (shutdown.load(.acquire)) {
                    return null;
                }
                self.not_empty.wait(&self.mutex);
                if (shutdown.load(.acquire)) {
                    return null;
                }
            }

            // Bounds checking to prevent corruption
            if (self.head >= self.tasks.len) {
                std.log.err("TaskQueue corruption detected: head={d}, len={d}", .{ self.head, self.tasks.len });
                self.head = 0; // Reset to safe state
                self.count = 0;
                return null;
            }

            if (self.count == 0) {
                return null; // Double-check after bounds fix
            }

            const task = self.tasks[self.head];
            self.head = (self.head + 1) % self.tasks.len;
            self.count -= 1;

            self.not_full.signal();
            return task;
        }

        fn size(self: *TaskQueue) usize {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.count;
        }
    };

    fn workerThread(pool: *ThreadPool) void {
        const thread_id = @atomicRmw(u32, &tl_thread_id, .Add, 1, .monotonic);
        _ = thread_id;

        while (!pool.shutdown.load(.acquire)) {
            if (pool.task_queue.waitAndPop(&pool.shutdown)) |task| {
                _ = pool.active_tasks.fetchAdd(1, .seq_cst);
                (task.function)(task.data);
                _ = pool.active_tasks.fetchSub(1, .seq_cst);
            }
        }
    }

    pub fn init(allocator: Allocator, config: Config) !ThreadPool {
        var pool = ThreadPool{
            .allocator = allocator,
            .threads = std.ArrayList(*std.Thread).init(allocator),
            .task_queue = try TaskQueue.init(allocator, config.queue_size),
            .shutdown = std.atomic.Value(bool).init(false),
            .active_tasks = std.atomic.Value(u32).init(0),
        };

        // Create worker threads
        const thread_count = @min(config.max_threads, detectCoreCount());
        try pool.threads.ensureTotalCapacity(thread_count);

        var i: u32 = 0;
        errdefer {
            pool.shutdown.store(true, .release);
            pool.task_queue.not_empty.broadcast();

            for (pool.threads.items) |thread| {
                thread.join();
            }
        }

        while (i < thread_count) : (i += 1) {
            const thread = try allocator.create(std.Thread);
            thread.* = try std.Thread.spawn(.{}, workerThread, .{&pool});
            pool.threads.appendAssumeCapacity(thread);
        }

        return pool;
    }

    pub fn deinit(self: *ThreadPool) void {
        // Signal shutdown
        self.shutdown.store(true, .release);
        self.task_queue.not_empty.broadcast();

        // Wait for threads to finish
        for (self.threads.items) |thread| {
            thread.join();
        }

        // Cleanup
        self.threads.deinit();
        self.task_queue.deinit(self.allocator);

        self.* = undefined;
    }

    pub fn enqueue(self: *ThreadPool, comptime function: anytype, data: anytype) !void {
        const DataPtr = @TypeOf(data);

        const Wrapper = struct {
            fn wrapper(ptr: *anyopaque) void {
                const data_ptr = @as(DataPtr, @ptrCast(@alignCast(ptr)));
                function(data_ptr);
            }
        };

        const task = Task{
            .function = &Wrapper.wrapper,
            .data = @ptrCast(data),
        };

        return self.task_queue.push(task);
    }

    pub fn enqueueBlocking(self: *ThreadPool, comptime function: anytype, data: anytype) void {
        const DataPtr = @TypeOf(data);

        const Wrapper = struct {
            fn wrapper(ptr: *anyopaque) void {
                const data_ptr = @as(DataPtr, @ptrCast(@alignCast(ptr)));
                function(data_ptr);
            }
        };

        const task = Task{
            .function = &Wrapper.wrapper,
            .data = @ptrCast(data),
        };

        self.task_queue.pushBlocking(task);
    }

    pub fn waitIdle(self: *ThreadPool) void {
        while (true) {
            const queue_empty = self.task_queue.size() == 0;
            const no_active_tasks = self.active_tasks.load(.SeqCst) == 0;

            if (queue_empty and no_active_tasks) break;
            std.time.sleep(100 * std.time.ns_per_us); // 100 microseconds
        }
    }

    pub fn getQueueSize(self: *ThreadPool) usize {
        return self.task_queue.size();
    }

    pub fn getActiveTaskCount(self: *ThreadPool) u32 {
        return self.active_tasks.load(.SeqCst);
    }

    pub fn getThreadCount(self: *ThreadPool) usize {
        return self.threads.items.len;
    }
};

pub fn getThreadPool() ?*ThreadPool {
    return if (g_platform.thread_pool) |*pool| pool else null;
}

test "platform core functions" {
    const allocator = std.testing.allocator;
    try init(allocator);
    defer deinit();

    // Basic time functions
    const time1 = getMonotonicTime();
    std.time.sleep(1 * std.time.ns_per_ms);
    const time2 = getMonotonicTime();
    try std.testing.expect(time2 > time1);

    // System time
    const system_time = getSystemTime();
    try std.testing.expect(system_time > 0);

    // Random functions
    var random_buf: [16]u8 = undefined;
    try getRandomBytes(&random_buf);

    const random_val = getRandomU64();
    _ = random_val;

    // Test random range
    const range_val = getRandomRange(10, 20);
    try std.testing.expect(range_val >= 10 and range_val <= 20);

    // Test paths
    const paths = getPlatformPaths();
    _ = paths;

    // Test input
    const input = getInputState();
    try std.testing.expect(input.initialized);
}

test "memory stats" {
    const allocator = std.testing.allocator;
    try init(allocator);
    defer deinit();

    const stats = getMemoryStats();
    stats.reset();

    stats.recordAllocation(1024);
    try std.testing.expectEqual(@as(usize, 1024), stats.getCurrentAllocated());
    try std.testing.expectEqual(@as(usize, 1024), stats.getPeakAllocated());
    try std.testing.expectEqual(@as(usize, 1), stats.getAllocationCount());

    stats.recordAllocation(512);
    try std.testing.expectEqual(@as(usize, 1536), stats.getCurrentAllocated());
    try std.testing.expectEqual(@as(usize, 1536), stats.getPeakAllocated());

    stats.recordDeallocation(512);
    try std.testing.expectEqual(@as(usize, 1024), stats.getCurrentAllocated());
    try std.testing.expectEqual(@as(usize, 1536), stats.getPeakAllocated());
    try std.testing.expectEqual(@as(usize, 1), stats.getDeallocationCount());
}

test "thread pool" {
    const allocator = std.testing.allocator;

    var pool = try ThreadPool.init(allocator, .{});
    defer pool.deinit();

    const TestContext = struct {
        value: std.atomic.Value(u32),

        pub fn increment(self: *@This()) void {
            _ = self.value.fetchAdd(1, .SeqCst);
        }
    };

    var ctx = TestContext{ .value = std.atomic.Value(u32).init(0) };

    const task_count = 100;
    var i: u32 = 0;
    while (i < task_count) : (i += 1) {
        try pool.enqueue(TestContext.increment, &ctx);
    }

    pool.waitIdle();
    try std.testing.expectEqual(task_count, ctx.value.load(.SeqCst));

    // Test pool info
    try std.testing.expect(pool.getThreadCount() > 0);
    try std.testing.expectEqual(@as(usize, 0), pool.getQueueSize());
    try std.testing.expectEqual(@as(u32, 0), pool.getActiveTaskCount());
}

test "input state" {
    const allocator = std.testing.allocator;
    try init(allocator);
    defer deinit();

    updateMousePosition(100, 200);
    updateMouseButton(0, true);
    updateKeyState(65, true); // 'A' key

    const input = getInputState();
    try std.testing.expectEqual(@as(i32, 100), input.mouse_x);
    try std.testing.expectEqual(@as(i32, 200), input.mouse_y);
    try std.testing.expect(input.isMouseButtonPressed(0));
    try std.testing.expect(input.isKeyPressed(65));
    try std.testing.expect(!input.isKeyPressed(66));
}
