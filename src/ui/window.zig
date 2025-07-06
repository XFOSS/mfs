const std = @import("std");
const Thread = std.Thread;
const Mutex = std.Thread.Mutex;
const Condition = std.Thread.Condition;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

// Windows API types
const HWND = *opaque {};
const HINSTANCE = *opaque {};
const HMENU = *opaque {};
const HDC = *opaque {};
const HBRUSH = *opaque {};
const HCURSOR = *opaque {};
const HICON = *opaque {};
const UINT = u32;
const WPARAM = usize;
const LPARAM = isize;
const LRESULT = isize;
const DWORD = u32;
const BOOL = i32;

// Windows constants
const WS_OVERLAPPEDWINDOW = 0x00CF0000;
const WS_VISIBLE = 0x10000000;
const WM_DESTROY = 0x0002;
const WM_CLOSE = 0x0010;
const WM_SIZE = 0x0005;
const WM_PAINT = 0x000F;
const WM_KEYDOWN = 0x0100;
const WM_KEYUP = 0x0101;
const WM_LBUTTONDOWN = 0x0201;
const WM_LBUTTONUP = 0x0202;
const WM_RBUTTONDOWN = 0x0204;
const WM_RBUTTONUP = 0x0205;
const WM_MBUTTONDOWN = 0x0207;
const WM_MBUTTONUP = 0x0208;
const WM_USER = 0x0400;
const WM_CUSTOM_TASK = WM_USER + 1;
const CS_HREDRAW = 0x0002;
const CS_VREDRAW = 0x0001;
const IDC_ARROW = 32512;
const COLOR_WINDOW = 5;
const VK_ESCAPE = 0x1B;
const SW_SHOW = 5;
const GWLP_USERDATA = -21;
const DT_CENTER = 0x00000001;
const DT_VCENTER = 0x00000004;

const RECT = extern struct {
    left: i32,
    top: i32,
    right: i32,
    bottom: i32,
};

const POINT = extern struct {
    x: i32,
    y: i32,
};

const WNDCLASSEXW = extern struct {
    cbSize: UINT,
    style: UINT,
    lpfnWndProc: *const fn (HWND, UINT, WPARAM, LPARAM) callconv(.C) LRESULT,
    cbClsExtra: i32,
    cbWndExtra: i32,
    hInstance: HINSTANCE,
    hIcon: ?HICON,
    hCursor: ?HCURSOR,
    hbrBackground: ?HBRUSH,
    lpszMenuName: ?[*:0]const u16,
    lpszClassName: [*:0]const u16,
    hIconSm: ?HICON,
};

const PAINTSTRUCT = extern struct {
    hdc: HDC,
    fErase: BOOL,
    rcPaint: RECT,
    fRestore: BOOL,
    fIncUpdate: BOOL,
    rgbReserved: [32]u8,
};

const MSG = extern struct {
    hwnd: ?HWND,
    message: UINT,
    wParam: WPARAM,
    lParam: LPARAM,
    time: DWORD,
    pt: POINT,
    lPrivate: DWORD,
};

// Windows API functions
extern "user32" fn RegisterClassExW(*const WNDCLASSEXW) callconv(.C) u16;
extern "user32" fn CreateWindowExW(DWORD, [*:0]const u16, [*:0]const u16, DWORD, i32, i32, i32, i32, ?HWND, ?HMENU, HINSTANCE, ?*anyopaque) callconv(.C) ?HWND;
extern "user32" fn ShowWindow(HWND, i32) callconv(.C) BOOL;
extern "user32" fn UpdateWindow(HWND) callconv(.C) BOOL;
extern "user32" fn GetMessageW(*MSG, ?HWND, UINT, UINT) callconv(.C) BOOL;
extern "user32" fn PeekMessageW(*MSG, ?HWND, UINT, UINT, UINT) callconv(.C) BOOL;
extern "user32" fn TranslateMessage(*const MSG) callconv(.C) BOOL;
extern "user32" fn DispatchMessageW(*const MSG) callconv(.C) LRESULT;
extern "user32" fn DefWindowProcW(HWND, UINT, WPARAM, LPARAM) callconv(.C) LRESULT;
extern "user32" fn PostQuitMessage(i32) callconv(.C) void;
extern "user32" fn PostMessageW(HWND, UINT, WPARAM, LPARAM) callconv(.C) BOOL;
extern "user32" fn DestroyWindow(HWND) callconv(.C) BOOL;
extern "user32" fn BeginPaint(HWND, *PAINTSTRUCT) callconv(.C) HDC;
extern "user32" fn EndPaint(HWND, *const PAINTSTRUCT) callconv(.C) BOOL;
extern "user32" fn GetClientRect(HWND, *RECT) callconv(.C) BOOL;
extern "user32" fn DrawTextW(HDC, [*:0]const u16, i32, *RECT, UINT) callconv(.C) i32;
extern "user32" fn LoadCursorW(?HINSTANCE, usize) callconv(.C) HCURSOR;
extern "user32" fn GetSystemMetrics(i32) callconv(.C) i32;
extern "user32" fn InvalidateRect(HWND, ?*const RECT, BOOL) callconv(.C) BOOL;
extern "user32" fn FillRect(HDC, *const RECT, HBRUSH) callconv(.C) i32;
extern "user32" fn SetWindowLongPtrW(HWND, i32, isize) callconv(.C) isize;
extern "user32" fn GetWindowLongPtrW(HWND, i32) callconv(.C) isize;
extern "gdi32" fn SetBkMode(HDC, i32) callconv(.C) i32;
extern "gdi32" fn SetTextColor(HDC, DWORD) callconv(.C) DWORD;
extern "kernel32" fn GetModuleHandleW(?[*:0]const u16) callconv(.C) HINSTANCE;
extern "kernel32" fn Sleep(DWORD) callconv(.C) void;

// Task system for background work
const TaskType = enum {
    computation,
    file_io,
    network,
    render_prepare,
};

const Task = struct {
    id: u32,
    task_type: TaskType,
    data: []const u8,
    callback: ?*const fn (task: *const Task, result: []const u8) void,
};

const TaskQueue = struct {
    tasks: ArrayList(Task),
    mutex: Mutex,
    condition: Condition,
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{
            .tasks = ArrayList(Task).init(allocator),
            .mutex = Mutex{},
            .condition = Condition{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.tasks.deinit();
    }

    pub fn enqueue(self: *Self, task: Task) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.tasks.append(task);
        self.condition.signal();
    }

    pub fn dequeue(self: *Self) ?Task {
        self.mutex.lock();
        defer self.mutex.unlock();

        while (self.tasks.items.len == 0) {
            self.condition.wait(&self.mutex);
        }

        return self.tasks.orderedRemove(0);
    }

    pub fn tryDequeue(self: *Self) ?Task {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.tasks.items.len == 0) return null;
        return self.tasks.orderedRemove(0);
    }
};

// Worker thread context
const WorkerContext = struct {
    id: u32,
    queue: *TaskQueue,
    running: *bool,
    window: *WindowManager,
};

// Main window manager with threading support
pub const WindowManager = struct {
    hwnd: ?HWND,
    hInstance: HINSTANCE,
    allocator: Allocator,
    task_queue: TaskQueue,
    worker_threads: []Thread,
    running: bool,
    render_text: ArrayList(u8),
    text_mutex: Mutex,
    last_error: ?[]const u8,

    // Event callbacks
    on_resize: ?*const fn (width: i32, height: i32) void = null,
    on_close: ?*const fn () void = null,
    on_key: ?*const fn (key_code: u32, pressed: bool) void = null,
    on_mouse: ?*const fn (x: i32, y: i32, button: u32, pressed: bool) void = null,

    const Self = @This();

    pub fn init(allocator: Allocator, worker_count: u32) !Self {
        return Self{
            .hwnd = null,
            .hInstance = GetModuleHandleW(null),
            .allocator = allocator,
            .task_queue = TaskQueue.init(allocator),
            .worker_threads = try allocator.alloc(Thread, worker_count),
            .running = true,
            .render_text = ArrayList(u8).init(allocator),
            .text_mutex = Mutex{},
            .last_error = null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.running = false;

        // Signal all worker threads to wake up and exit
        for (0..self.worker_threads.len) |_| {
            self.task_queue.condition.signal();
        }

        // Wait for all worker threads to finish
        for (self.worker_threads) |thread| {
            thread.join();
        }

        // Clean up worker thread memory
        self.allocator.free(self.worker_threads);

        // Clean up task queue (tasks are cleaned up by worker threads)
        self.task_queue.deinit();

        // Clean up render text buffer
        self.text_mutex.lock();
        self.render_text.deinit();
        self.text_mutex.unlock();

        // Free any error message
        if (self.last_error) |error_msg| {
            self.allocator.free(error_msg);
        }

        // Destroy window if it exists
        if (self.hwnd) |hwnd| {
            _ = DestroyWindow(hwnd);
        }
    }

    pub fn createWindow(self: *Self, title: []const u8, width: i32, height: i32, window_style: ?u32) !void {
        const class_name = std.unicode.utf8ToUtf16LeStringLiteral("ThreadedZigWindow");
        const window_title_wide = try std.unicode.utf8ToUtf16LeAllocZ(self.allocator, title);
        defer self.allocator.free(window_title_wide);

        var wc = WNDCLASSEXW{
            .cbSize = @sizeOf(WNDCLASSEXW),
            .style = CS_HREDRAW | CS_VREDRAW,
            .lpfnWndProc = windowProc,
            .cbClsExtra = 0,
            .cbWndExtra = @sizeOf(*Self),
            .hInstance = self.hInstance,
            .hIcon = null,
            .hCursor = LoadCursorW(null, IDC_ARROW),
            .hbrBackground = @ptrFromInt(COLOR_WINDOW + 1),
            .lpszMenuName = null,
            .lpszClassName = class_name,
            .hIconSm = null,
        };

        if (RegisterClassExW(&wc) == 0) {
            self.setError("Failed to register window class");
            return error.WindowClassRegistrationFailed;
        }

        const screen_width = GetSystemMetrics(0);
        const screen_height = GetSystemMetrics(1);
        const window_x = @divTrunc(screen_width - width, 2);
        const window_y = @divTrunc(screen_height - height, 2);

        const style = window_style orelse (WS_OVERLAPPEDWINDOW | WS_VISIBLE);

        self.hwnd = CreateWindowExW(
            0,
            class_name,
            window_title_wide.ptr,
            style,
            window_x,
            window_y,
            width,
            height,
            null,
            null,
            self.hInstance,
            @ptrCast(self),
        );

        if (self.hwnd == null) {
            self.setError("Failed to create window");
            return error.WindowCreationFailed;
        }

        _ = ShowWindow(self.hwnd.?, SW_SHOW);
        _ = UpdateWindow(self.hwnd.?);

        // Start worker threads
        try self.startWorkerThreads();

        // Add initial text
        try self.updateText("Threaded Zig Window Manager\nPress ESC to exit\nBackground tasks running...");
    }

    fn startWorkerThreads(self: *Self) !void {
        for (self.worker_threads, 0..) |*thread, i| {
            const context = try self.allocator.create(WorkerContext);
            context.* = WorkerContext{
                .id = @intCast(i),
                .queue = &self.task_queue,
                .running = &self.running,
                .window = self,
            };

            thread.* = try Thread.spawn(.{}, workerThreadMain, .{context});
        }

        // Schedule some example tasks
        try self.scheduleExampleTasks();
    }

    fn scheduleExampleTasks(self: *Self) !void {
        // Schedule periodic computation tasks
        for (0..10) |i| {
            const task = Task{
                .id = @intCast(i),
                .task_type = .computation,
                .data = try std.fmt.allocPrint(self.allocator, "Task {}", .{i}),
                .callback = taskCompletedCallback,
            };
            try self.task_queue.enqueue(task);
        }
    }

    pub fn updateText(self: *Self, text: []const u8) !void {
        self.text_mutex.lock();
        defer self.text_mutex.unlock();

        self.render_text.clearRetainingCapacity();
        try self.render_text.appendSlice(text);

        // Trigger window repaint
        if (self.hwnd) |hwnd| {
            _ = InvalidateRect(hwnd, null, 1);
        }
    }

    fn setError(self: *Self, error_msg: []const u8) void {
        if (self.last_error) |old_error| {
            self.allocator.free(old_error);
        }
        self.last_error = self.allocator.dupe(u8, error_msg) catch null;
    }

    pub fn runMessageLoop(self: *Self) void {
        var msg: MSG = undefined;

        while (self.running) {
            // Use PeekMessage for non-blocking message processing
            while (PeekMessageW(&msg, null, 0, 0, 1) != 0) { // PM_REMOVE = 1
                if (msg.message == 0x0012) { // WM_QUIT
                    self.running = false;
                    break;
                }

                _ = TranslateMessage(&msg);
                _ = DispatchMessageW(&msg);
            }

            // Process any completed tasks
            self.processCompletedTasks();

            // Small sleep to prevent busy waiting
            Sleep(1);
        }
    }

    fn processCompletedTasks(self: *Self) void {
        // In a real implementation, you'd have a completion queue
        // For now, we'll just update the display periodically
        const S = struct {
            var counter: u32 = 0;
        };
        S.counter += 1;

        if (S.counter % 1000 == 0) {
            const text = std.fmt.allocPrint(self.allocator, "Threaded Zig Window Manager\nPress ESC to exit\nTasks processed: {}\nWorker threads: {}", .{ S.counter / 1000, self.worker_threads.len }) catch return;
            defer self.allocator.free(text);

            self.updateText(text) catch {};
        }
    }
};

fn workerThreadMain(context: *WorkerContext) void {
    const allocator = context.window.allocator;
    defer allocator.destroy(context); // Clean up context when thread exits

    std.debug.print("Worker thread {} started\n", .{context.id});

    while (context.running.*) {
        if (context.queue.tryDequeue()) |task| {
            // Free task data after processing
            defer if (task.data.len > 0) allocator.free(task.data);

            // Simulate work based on task type
            switch (task.task_type) {
                .computation => {
                    // Simulate CPU-intensive work
                    var result: u64 = 0;
                    for (0..1000000) |i| {
                        result +%= i;
                    }
                    std.debug.print("Worker {}: Computed result {} for task {}\n", .{ context.id, result, task.id });
                },
                .file_io => {
                    // Simulate file I/O
                    Sleep(100);
                    std.debug.print("Worker {}: File I/O completed for task {}\n", .{ context.id, task.id });
                },
                .network => {
                    // Simulate network operation
                    Sleep(200);
                    std.debug.print("Worker {}: Network operation completed for task {}\n", .{ context.id, task.id });
                },
                .render_prepare => {
                    // Simulate render preparation
                    Sleep(50);
                    std.debug.print("Worker {}: Render preparation completed for task {}\n", .{ context.id, task.id });
                },
            }

            if (task.callback) |callback| {
                callback(&task, "completed");
            }
        } else {
            // No tasks available, sleep briefly
            Sleep(10);
        }
    }

    std.debug.print("Worker thread {} shutting down\n", .{context.id});
}

fn taskCompletedCallback(task: *const Task, result: []const u8) void {
    std.debug.print("Task {} completed with result: {s}\n", .{ task.id, result });
}

fn windowProc(hwnd: HWND, uMsg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.C) LRESULT {
    // Try to get the window manager instance
    const window_ptr = GetWindowLongPtrW(hwnd, GWLP_USERDATA);
    const window_manager = if (window_ptr != 0)
        @as(*WindowManager, @ptrFromInt(@as(usize, @intCast(window_ptr))))
    else
        null;

    switch (uMsg) {
        0x0001 => { // WM_CREATE
            const create_struct: *extern struct {
                lpCreateParams: ?*anyopaque,
                // ... other fields we don't need
            } = @ptrFromInt(@as(usize, @bitCast(lParam)));

            if (create_struct.lpCreateParams) |params_ptr| {
                // Store window manager pointer in window data
                _ = SetWindowLongPtrW(hwnd, GWLP_USERDATA, @as(isize, @bitCast(@intFromPtr(params_ptr))));
            }
            return 0;
        },
        WM_DESTROY => {
            // Call the close callback if available
            if (window_manager) |mgr| {
                if (mgr.on_close) |callback| {
                    callback();
                }
                mgr.running = false;
            }
            PostQuitMessage(0);
            return 0;
        },
        WM_CLOSE => {
            // Call the close callback if available
            if (window_manager) |mgr| {
                if (mgr.on_close) |callback| {
                    callback();
                }
            }
            _ = DestroyWindow(hwnd);
            return 0;
        },
        WM_SIZE => {
            // Handle window resizing
            if (window_manager) |mgr| {
                const new_width: u16 = @intCast(lParam & 0xFFFF);
                const new_height: u16 = @intCast((lParam >> 16) & 0xFFFF);

                if (mgr.on_resize) |callback| {
                    callback(@as(i32, new_width), @as(i32, new_height));
                }
            }
            return 0;
        },
        WM_KEYDOWN => {
            // Handle key press events
            if (window_manager) |mgr| {
                if (mgr.on_key) |callback| {
                    callback(@intCast(wParam), true);
                }
            }

            if (wParam == VK_ESCAPE) {
                _ = PostMessageW(hwnd, WM_CLOSE, 0, 0);
            }
            return 0;
        },
        WM_KEYUP => {
            // Handle key release events
            if (window_manager) |mgr| {
                if (mgr.on_key) |callback| {
                    callback(@intCast(wParam), false);
                }
            }
            return 0;
        },
        WM_LBUTTONDOWN, WM_RBUTTONDOWN, WM_MBUTTONDOWN => {
            // Handle mouse button down
            if (window_manager) |mgr| {
                if (mgr.on_mouse) |callback| {
                    const x = @as(i16, @intCast(lParam & 0xFFFF));
                    const y = @as(i16, @intCast((lParam >> 16) & 0xFFFF));
                    const button: u32 = switch (uMsg) {
                        WM_LBUTTONDOWN => 0,
                        WM_RBUTTONDOWN => 1,
                        WM_MBUTTONDOWN => 2,
                        else => 0,
                    };

                    callback(@intCast(x), @intCast(y), button, true);
                }
            }
            return 0;
        },
        WM_LBUTTONUP, WM_RBUTTONUP, WM_MBUTTONUP => {
            // Handle mouse button up
            if (window_manager) |mgr| {
                if (mgr.on_mouse) |callback| {
                    const x = @as(i16, @intCast(lParam & 0xFFFF));
                    const y = @as(i16, @intCast((lParam >> 16) & 0xFFFF));
                    const button: u32 = switch (uMsg) {
                        WM_LBUTTONUP => 0,
                        WM_RBUTTONUP => 1,
                        WM_MBUTTONUP => 2,
                        else => 0,
                    };

                    callback(@intCast(x), @intCast(y), button, false);
                }
            }
            return 0;
        },
        WM_PAINT => {
            var ps: PAINTSTRUCT = undefined;
            const hdc = BeginPaint(hwnd, &ps);

            // Fill background
            _ = FillRect(hdc, &ps.rcPaint, @ptrFromInt(COLOR_WINDOW + 1));

            // Get client area
            var client_rect: RECT = undefined;
            _ = GetClientRect(hwnd, &client_rect);

            // Set text properties
            _ = SetBkMode(hdc, 1); // TRANSPARENT
            _ = SetTextColor(hdc, 0x00FF0000); // Blue text

            // Draw text from the window manager if available
            if (window_manager) |mgr| {
                mgr.text_mutex.lock();
                defer mgr.text_mutex.unlock();

                if (mgr.render_text.items.len > 0) {
                    const text_slice = mgr.render_text.items;
                    const text_wide = std.unicode.utf8ToUtf16LeAllocZ(mgr.allocator, text_slice) catch {
                        // Handle conversion error
                        const fallback_text = std.unicode.utf8ToUtf16LeStringLiteral("Text conversion error");
                        _ = DrawTextW(hdc, fallback_text, -1, &client_rect, DT_CENTER | DT_VCENTER);
                        _ = EndPaint(hwnd, &ps);
                        return 0;
                    };
                    defer mgr.allocator.free(text_wide);

                    _ = DrawTextW(hdc, text_wide.ptr, -1, &client_rect, DT_CENTER | DT_VCENTER);
                } else {
                    // Fallback if no text is set
                    const text = std.unicode.utf8ToUtf16LeStringLiteral("Threaded Zig Window\nPress ESC to exit");
                    _ = DrawTextW(hdc, text, -1, &client_rect, DT_CENTER | DT_VCENTER);
                }
            } else {
                // Fallback if no window manager is found
                const text = std.unicode.utf8ToUtf16LeStringLiteral("Threaded Zig Window\nPress ESC to exit");
                _ = DrawTextW(hdc, text, -1, &client_rect, DT_CENTER | DT_VCENTER);
            }

            _ = EndPaint(hwnd, &ps);
            return 0;
        },
        else => return DefWindowProcW(hwnd, uMsg, wParam, lParam),
    }
}

// Helper method for setting error messages
fn setError(self: *WindowManager, message: []const u8) void {
    if (self.last_error) |old_msg| {
        self.allocator.free(old_msg);
    }
    self.last_error = self.allocator.dupe(u8, message) catch null;
}

// Get the last error message
pub fn getLastError(self: *const WindowManager) ?[]const u8 {
    return self.last_error;
}

// Set callbacks for window events
pub fn setCallbacks(self: *WindowManager, resize_cb: ?*const fn (width: i32, height: i32) void, close_cb: ?*const fn () void, key_cb: ?*const fn (key_code: u32, pressed: bool) void, mouse_cb: ?*const fn (x: i32, y: i32, button: u32, pressed: bool) void) void {
    self.on_resize = resize_cb;
    self.on_close = close_cb;
    self.on_key = key_cb;
    self.on_mouse = mouse_cb;
}

// Public API for creating and managing threaded windows
pub fn createThreadedWindow(allocator: Allocator, title: []const u8, width: i32, height: i32, worker_count: u32) !WindowManager {
    var window_manager = try WindowManager.init(allocator, worker_count);
    try window_manager.createWindow(title, width, height, null);
    return window_manager;
}
