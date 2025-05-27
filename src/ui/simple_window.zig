const std = @import("std");
const Allocator = std.mem.Allocator;

// Windows API types and constants
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

const WS_OVERLAPPEDWINDOW = 0x00CF0000;
const WS_VISIBLE = 0x10000000;
const WM_DESTROY = 0x0002;
const WM_CLOSE = 0x0010;
const WM_PAINT = 0x000F;
const WM_KEYDOWN = 0x0100;
const WM_KEYUP = 0x0101;
const WM_SIZE = 0x0005;
const CS_HREDRAW = 0x0002;
const CS_VREDRAW = 0x0001;
const IDC_ARROW = 32512;
const COLOR_WINDOW = 5;
const VK_ESCAPE = 0x1B;
const SW_SHOW = 5;

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
extern "user32" fn PeekMessageW(*MSG, ?HWND, UINT, UINT, UINT) callconv(.C) BOOL;
extern "user32" fn TranslateMessage(*const MSG) callconv(.C) BOOL;
extern "user32" fn DispatchMessageW(*const MSG) callconv(.C) LRESULT;
extern "user32" fn DefWindowProcW(HWND, UINT, WPARAM, LPARAM) callconv(.C) LRESULT;
extern "user32" fn PostQuitMessage(i32) callconv(.C) void;
extern "user32" fn DestroyWindow(HWND) callconv(.C) BOOL;
extern "user32" fn LoadCursorW(?HINSTANCE, usize) callconv(.C) HCURSOR;
extern "user32" fn GetSystemMetrics(i32) callconv(.C) i32;
extern "user32" fn SetWindowLongPtrW(HWND, i32, isize) callconv(.C) isize;
extern "user32" fn GetWindowLongPtrW(HWND, i32) callconv(.C) isize;
extern "kernel32" fn GetModuleHandleW(?[*:0]const u16) callconv(.C) HINSTANCE;

const GWLP_USERDATA = -21;

pub const WindowConfig = struct {
    title: []const u8,
    width: u32 = 1280,
    height: u32 = 720,
    resizable: bool = true,
    x: ?i32 = null,
    y: ?i32 = null,
    fullscreen: bool = false,
    borderless: bool = false,
    always_on_top: bool = false,
    vsync: bool = false,
};

pub const NativeHandle = struct {
    hwnd: HWND,
    hinstance: HINSTANCE,
};

pub const Window = struct {
    allocator: Allocator,
    hwnd: ?HWND,
    hinstance: HINSTANCE,
    should_close: bool,
    width: u32,
    height: u32,

    const Self = @This();

    pub fn init(allocator: Allocator, config: WindowConfig) !Self {
        const hinstance = GetModuleHandleW(null);

        var window = Self{
            .allocator = allocator,
            .hwnd = null,
            .hinstance = hinstance,
            .should_close = false,
            .width = config.width,
            .height = config.height,
        };

        try window.createWindow(config);
        return window;
    }

    pub fn deinit(self: *Self) void {
        if (self.hwnd) |hwnd| {
            _ = DestroyWindow(hwnd);
            self.hwnd = null;
        }
    }

    fn createWindow(self: *Self, config: WindowConfig) !void {
        const class_name = std.unicode.utf8ToUtf16LeStringLiteral("NyxWindow");

        // Convert title to wide string
        const title_wide = try std.unicode.utf8ToUtf16LeAllocZ(self.allocator, config.title);
        defer self.allocator.free(title_wide);

        // Register window class
        var wc = WNDCLASSEXW{
            .cbSize = @sizeOf(WNDCLASSEXW),
            .style = CS_HREDRAW | CS_VREDRAW,
            .lpfnWndProc = windowProc,
            .cbClsExtra = 0,
            .cbWndExtra = 0,
            .hInstance = self.hinstance,
            .hIcon = null,
            .hCursor = LoadCursorW(null, IDC_ARROW),
            .hbrBackground = @ptrFromInt(COLOR_WINDOW + 1),
            .lpszMenuName = null,
            .lpszClassName = class_name,
            .hIconSm = null,
        };

        _ = RegisterClassExW(&wc);

        // Calculate window position
        const screen_width = GetSystemMetrics(0);
        const screen_height = GetSystemMetrics(1);
        const window_x = config.x orelse @divTrunc(screen_width - @as(i32, @intCast(config.width)), 2);
        const window_y = config.y orelse @divTrunc(screen_height - @as(i32, @intCast(config.height)), 2);

        // Create window
        self.hwnd = CreateWindowExW(
            0,
            class_name,
            title_wide.ptr,
            WS_OVERLAPPEDWINDOW | WS_VISIBLE,
            window_x,
            window_y,
            @intCast(config.width),
            @intCast(config.height),
            null,
            null,
            self.hinstance,
            @ptrCast(self),
        );

        if (self.hwnd == null) {
            return error.WindowCreationFailed;
        }

        // Store window pointer in window data
        _ = SetWindowLongPtrW(self.hwnd.?, GWLP_USERDATA, @intCast(@intFromPtr(self)));

        _ = ShowWindow(self.hwnd.?, SW_SHOW);
        _ = UpdateWindow(self.hwnd.?);
    }

    pub fn pollEvents(self: *Self) !void {
        var msg: MSG = undefined;

        while (PeekMessageW(&msg, null, 0, 0, 1) != 0) { // PM_REMOVE = 1
            if (msg.message == 0x0012) { // WM_QUIT
                self.should_close = true;
                break;
            }

            _ = TranslateMessage(&msg);
            _ = DispatchMessageW(&msg);
        }
    }

    pub fn shouldClose(self: *const Self) bool {
        return self.should_close;
    }

    pub fn getNativeHandle(self: *const Self) ?NativeHandle {
        if (self.hwnd) |hwnd| {
            return NativeHandle{
                .hwnd = hwnd,
                .hinstance = self.hinstance,
            };
        }
        return null;
    }

    pub fn show(self: *Self) !void {
        if (self.hwnd) |hwnd| {
            _ = ShowWindow(hwnd, SW_SHOW);
            _ = UpdateWindow(hwnd);
        }
    }

    pub fn getSize(self: *const Self) struct { width: u32, height: u32 } {
        return .{ .width = self.width, .height = self.height };
    }
};

fn windowProc(hwnd: HWND, uMsg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.C) LRESULT {
    switch (uMsg) {
        0x0001 => { // WM_CREATE
            const create_struct: *extern struct {
                lpCreateParams: ?*anyopaque,
                // ... other fields
                hInstance: HINSTANCE,
                hMenu: ?HMENU,
                hwndParent: ?HWND,
                cy: i32,
                cx: i32,
                y: i32,
                x: i32,
                style: DWORD,
                lpszName: [*:0]const u16,
                lpszClass: [*:0]const u16,
                dwExStyle: DWORD,
            } = @ptrFromInt(@as(usize, @bitCast(lParam)));

            if (create_struct.lpCreateParams) |params_ptr| {
                _ = SetWindowLongPtrW(hwnd, GWLP_USERDATA, @intCast(@intFromPtr(params_ptr)));
            }
            return 0;
        },
        WM_DESTROY => {
            const user_data = GetWindowLongPtrW(hwnd, GWLP_USERDATA);
            if (user_data != 0) {
                const window: *Window = @ptrFromInt(@as(usize, @intCast(user_data)));
                window.should_close = true;
            }
            PostQuitMessage(0);
            return 0;
        },
        WM_CLOSE => {
            const user_data = GetWindowLongPtrW(hwnd, GWLP_USERDATA);
            if (user_data != 0) {
                const window: *Window = @ptrFromInt(@as(usize, @intCast(user_data)));
                window.should_close = true;
            }
            _ = DestroyWindow(hwnd);
            return 0;
        },
        WM_KEYDOWN => {
            if (wParam == VK_ESCAPE) {
                const user_data = GetWindowLongPtrW(hwnd, GWLP_USERDATA);
                if (user_data != 0) {
                    const window: *Window = @ptrFromInt(@as(usize, @intCast(user_data)));
                    window.should_close = true;
                }
            }
            return 0;
        },
        WM_SIZE => {
            const user_data = GetWindowLongPtrW(hwnd, GWLP_USERDATA);
            if (user_data != 0) {
                const window: *Window = @ptrFromInt(@as(usize, @intCast(user_data)));
                window.width = @intCast(lParam & 0xFFFF);
                window.height = @intCast((lParam >> 16) & 0xFFFF);
            }
            return 0;
        },
        else => return DefWindowProcW(hwnd, uMsg, wParam, lParam),
    }
}
