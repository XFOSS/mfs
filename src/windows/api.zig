const std = @import("std");

// Windows API constants
pub const WS_OVERLAPPEDWINDOW = 0x00CF0000;
pub const WS_VISIBLE = 0x10000000;
pub const WM_DESTROY = 0x0002;
pub const WM_CLOSE = 0x0010;
pub const WM_PAINT = 0x000F;
pub const WM_KEYDOWN = 0x0100;
pub const CS_HREDRAW = 0x0002;
pub const CS_VREDRAW = 0x0001;
pub const IDC_ARROW = 32512;
pub const COLOR_WINDOW = 5;
pub const VK_ESCAPE = 0x1B;
pub const DT_SINGLELINE = 0x00000020;
pub const DT_CENTER = 0x00000001;
pub const DT_VCENTER = 0x00000004;
pub const SW_SHOW = 5;

// Windows API types
pub const HWND = *opaque {};
pub const HINSTANCE = *opaque {};
pub const HMENU = *opaque {};
pub const HDC = *opaque {};
pub const HBRUSH = *opaque {};
pub const HCURSOR = *opaque {};
pub const HICON = *opaque {};
pub const UINT = u32;
pub const WPARAM = usize;
pub const LPARAM = isize;
pub const LRESULT = isize;
pub const DWORD = u32;
pub const BOOL = i32;
pub const COLORREF = DWORD;

pub const RECT = extern struct {
    left: i32,
    top: i32,
    right: i32,
    bottom: i32,
};

pub const POINT = extern struct {
    x: i32,
    y: i32,
};

pub const WNDCLASSEXW = extern struct {
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

pub const PAINTSTRUCT = extern struct {
    hdc: HDC,
    fErase: BOOL,
    rcPaint: RECT,
    fRestore: BOOL,
    fIncUpdate: BOOL,
    rgbReserved: [32]u8,
};

pub const MSG = extern struct {
    hwnd: ?HWND,
    message: UINT,
    wParam: WPARAM,
    lParam: LPARAM,
    time: DWORD,
    pt: POINT,
    lPrivate: DWORD,
};

// Windows API function declarations
extern "user32" fn RegisterClassExW(*const WNDCLASSEXW) callconv(.C) u16;
extern "user32" fn CreateWindowExW(DWORD, [*:0]const u16, [*:0]const u16, DWORD, i32, i32, i32, i32, ?HWND, ?HMENU, HINSTANCE, ?*anyopaque) callconv(.C) ?HWND;
extern "user32" fn ShowWindow(HWND, i32) callconv(.C) BOOL;
extern "user32" fn UpdateWindow(HWND) callconv(.C) BOOL;
extern "user32" fn GetMessageW(*MSG, ?HWND, UINT, UINT) callconv(.C) BOOL;
extern "user32" fn TranslateMessage(*const MSG) callconv(.C) BOOL;
extern "user32" fn DispatchMessageW(*const MSG) callconv(.C) LRESULT;
extern "user32" fn DefWindowProcW(HWND, UINT, WPARAM, LPARAM) callconv(.C) LRESULT;
extern "user32" fn PostQuitMessage(i32) callconv(.C) void;
extern "user32" fn DestroyWindow(HWND) callconv(.C) BOOL;
extern "user32" fn PostMessageW(HWND, UINT, WPARAM, LPARAM) callconv(.C) BOOL;
extern "user32" fn BeginPaint(HWND, *PAINTSTRUCT) callconv(.C) HDC;
extern "user32" fn EndPaint(HWND, *const PAINTSTRUCT) callconv(.C) BOOL;
extern "user32" fn GetClientRect(HWND, *RECT) callconv(.C) BOOL;
extern "user32" fn DrawTextW(HDC, [*:0]const u16, i32, *RECT, UINT) callconv(.C) i32;
extern "user32" fn LoadCursorW(?HINSTANCE, usize) callconv(.C) HCURSOR;
extern "user32" fn GetSystemMetrics(i32) callconv(.C) i32;
extern "user32" fn InvalidateRect(HWND, ?*const RECT, BOOL) callconv(.C) BOOL;
extern "user32" fn FillRect(HDC, *const RECT, HBRUSH) callconv(.C) i32;
