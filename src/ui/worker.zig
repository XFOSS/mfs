const std = @import("std");
const Thread = std.Thread;
const Mutex = std.Thread.Mutex;
const Condition = std.Thread.Condition;
const ArrayList = std.array_list.Managed;
const Allocator = std.mem.Allocator;

pub const WorkerType = enum {
    computation,
    file_io,
    network,
    render,
    general,
};

pub const WorkItem = struct {
    id: u64,
    worker_type: WorkerType,
    priority: u8,
    data: []const u8,
    context: ?*anyopaque,
    work_fn: *const fn (item: *const WorkItem) void,
    completion_fn: ?*const fn (item: *const WorkItem, result: ?[]const u8) void,
    created_time: i64,

    pub fn execute(self: *const WorkItem) void {
        self.work_fn(self);
    }

    pub fn complete(self: *const WorkItem, result: ?[]const u8) void {
        if (self.completion_fn) |completion| {
            completion(self, result);
        }
    }
};

pub const WorkQueue = struct {
    items: ArrayList(WorkItem),
    mutex: Mutex,
    condition: Condition,
    allocator: Allocator,
    closed: bool,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{
            .items = ArrayList(WorkItem).init(allocator),
            .mutex = Mutex{},
            .condition = Condition{},
            .allocator = allocator,
            .closed = false,
        };
    }

    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.closed = true;
        self.items.deinit();
        self.condition.broadcast();
    }

    pub fn push(self: *Self, item: WorkItem) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.closed) return error.QueueClosed;

        // Insert based on priority (higher priority first)
        var insert_index: usize = 0;
        for (self.items.items, 0..) |existing_item, i| {
            if (item.priority > existing_item.priority) {
                insert_index = i;
                break;
            }
            insert_index = i + 1;
        }

        try self.items.insert(insert_index, item);
        self.condition.signal();
    }

    pub fn pop(self: *Self) ?WorkItem {
        self.mutex.lock();
        defer self.mutex.unlock();

        while (self.items.items.len == 0 and !self.closed) {
            self.condition.wait(&self.mutex);
        }

        if (self.closed) return null;

        return self.items.orderedRemove(0);
    }

    pub fn tryPop(self: *Self) ?WorkItem {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.items.items.len == 0 or self.closed) return null;
        return self.items.orderedRemove(0);
    }

    pub fn len(self: *Self) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.items.items.len;
    }
};

pub const WorkerStats = struct {
    id: u32,
    tasks_completed: u64,
    total_work_time_ms: u64,
    last_activity: i64,
    is_active: bool,
    current_task_id: ?u64,
};

pub const WorkerThread = struct {
    id: u32,
    thread: Thread,
    queue: *WorkQueue,
    stats: WorkerStats,
    stats_mutex: Mutex,
    running: *bool,
    worker_type: WorkerType,

    const Self = @This();

    pub fn init(id: u32, queue: *WorkQueue, running: *bool, worker_type: WorkerType) Self {
        return Self{
            .id = id,
            .thread = undefined,
            .queue = queue,
            .stats = WorkerStats{
                .id = id,
                .tasks_completed = 0,
                .total_work_time_ms = 0,
                .last_activity = std.time.timestamp(),
                .is_active = false,
                .current_task_id = null,
            },
            .stats_mutex = Mutex{},
            .running = running,
            .worker_type = worker_type,
        };
    }

    pub fn start(self: *Self) !void {
        self.thread = try Thread.spawn(.{}, workerMain, .{self});
    }

    pub fn join(self: *Self) void {
        self.thread.join();
    }

    pub fn getStats(self: *Self) WorkerStats {
        self.stats_mutex.lock();
        defer self.stats_mutex.unlock();
        return self.stats;
    }

    fn updateStats(self: *Self, task_id: ?u64, completed: bool, work_time_ms: u64) void {
        self.stats_mutex.lock();
        defer self.stats_mutex.unlock();

        self.stats.current_task_id = task_id;
        self.stats.is_active = task_id != null;
        self.stats.last_activity = std.time.timestamp();

        if (completed) {
            self.stats.tasks_completed += 1;
            self.stats.total_work_time_ms += work_time_ms;
        }
    }
};

fn workerMain(worker: *WorkerThread) void {
    std.debug.print("Worker thread {} ({s}) started\n", .{ worker.id, @tagName(worker.worker_type) });

    while (worker.running.*) {
        if (worker.queue.pop()) |work_item| {
            // Check if this worker can handle this type of work
            if (worker.worker_type != .general and worker.worker_type != work_item.worker_type) {
                // Put it back for another worker
                worker.queue.push(work_item) catch {};
                std.time.sleep(1000000); // 1ms
                continue;
            }

            const start_time = std.time.milliTimestamp();
            worker.updateStats(work_item.id, false, 0);

            // Execute the work
            work_item.execute();

            const end_time = std.time.milliTimestamp();
            const work_time = @as(u64, @intCast(end_time - start_time));

            worker.updateStats(null, true, work_time);

            // Call completion callback
            work_item.complete(null);
        } else {
            // Queue is closed or no work available
            break;
        }
    }

    std.debug.print("Worker thread {} shutting down\n", .{worker.id});
}

pub const ThreadPool = struct {
    workers: ArrayList(WorkerThread),
    work_queue: WorkQueue,
    allocator: Allocator,
    running: bool,
    next_work_id: u64,
    id_mutex: Mutex,

    const Self = @This();

    pub fn init(allocator: Allocator, num_workers: u32) !Self {
        var pool = Self{
            .workers = ArrayList(WorkerThread).init(allocator),
            .work_queue = WorkQueue.init(allocator),
            .allocator = allocator,
            .running = true,
            .next_work_id = 1,
            .id_mutex = Mutex{},
        };

        // Create worker threads
        try pool.workers.ensureTotalCapacity(num_workers);

        // Create specialized workers
        const worker_types = [_]WorkerType{ .computation, .file_io, .network, .render };

        for (0..num_workers) |i| {
            const worker_type = if (i < worker_types.len) worker_types[i] else .general;
            var worker = WorkerThread.init(@intCast(i), &pool.work_queue, &pool.running, worker_type);
            try worker.start();
            try pool.workers.append(worker);
        }

        return pool;
    }

    pub fn deinit(self: *Self) void {
        self.running = false;
        self.work_queue.deinit();

        // Wait for all workers to finish
        for (self.workers.items) |*worker| {
            worker.join();
        }

        self.workers.deinit();
    }

    pub fn submitWork(self: *Self, work_type: WorkerType, priority: u8, data: []const u8, work_fn: *const fn (item: *const WorkItem) void, completion_fn: ?*const fn (item: *const WorkItem, result: ?[]const u8) void) !u64 {
        const work_id = self.getNextWorkId();

        const work_item = WorkItem{
            .id = work_id,
            .worker_type = work_type,
            .priority = priority,
            .data = data,
            .context = null,
            .work_fn = work_fn,
            .completion_fn = completion_fn,
            .created_time = std.time.timestamp(),
        };

        try self.work_queue.push(work_item);
        return work_id;
    }

    pub fn getQueueLength(self: *Self) usize {
        return self.work_queue.len();
    }

    pub fn getWorkerStats(self: *Self) !ArrayList(WorkerStats) {
        var stats = ArrayList(WorkerStats).init(self.allocator);

        for (self.workers.items) |*worker| {
            try stats.append(worker.getStats());
        }

        return stats;
    }

    fn getNextWorkId(self: *Self) u64 {
        self.id_mutex.lock();
        defer self.id_mutex.unlock();

        const id = self.next_work_id;
        self.next_work_id += 1;
        return id;
    }
};

// Example work functions
pub fn computationWork(item: *const WorkItem) void {
    _ = item;
    // Simulate heavy computation
    var result: u64 = 0;
    for (0..1000000) |i| {
        result +%= i;
    }
    std.debug.print("Computation work completed: {}\n", .{result});
}

pub fn fileIoWork(item: *const WorkItem) void {
    _ = item;
    // Simulate file I/O
    std.time.sleep(100 * std.time.ns_per_ms);
    std.debug.print("File I/O work completed\n", .{});
}

pub fn networkWork(item: *const WorkItem) void {
    _ = item;
    // Simulate network operation
    std.time.sleep(200 * std.time.ns_per_ms);
    std.debug.print("Network work completed\n", .{});
}

pub fn renderWork(item: *const WorkItem) void {
    _ = item;
    // Simulate render preparation
    std.time.sleep(50 * std.time.ns_per_ms);
    std.debug.print("Render work completed\n", .{});
}
