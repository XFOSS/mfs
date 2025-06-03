const std = @import("std");
const math = std.math;
const print = std.debug.print;

// Windows API types and constants
const HWND = *opaque {};
const HINSTANCE = *opaque {};
const HDC = *opaque {};
const HGLRC = *opaque {};
const UINT = u32;
const WPARAM = usize;
const LPARAM = isize;
const LRESULT = isize;
const DWORD = u32;
const BOOL = i32;
const BYTE = u8;
const WORD = u16;

const WS_OVERLAPPEDWINDOW = 0x00CF0000;
const WS_VISIBLE = 0x10000000;
const WM_DESTROY = 0x0002;
const WM_CLOSE = 0x0010;
const WM_KEYDOWN = 0x0100;
const VK_ESCAPE = 0x1B;
const CS_HREDRAW = 0x0002;
const CS_VREDRAW = 0x0001;
const CS_OWNDC = 0x0020;
const IDC_ARROW = 32512;
const COLOR_WINDOW = 5;
const SW_SHOW = 5;
const PM_REMOVE = 1;

const PFD_DRAW_TO_WINDOW = 0x00000004;
const PFD_SUPPORT_OPENGL = 0x00000020;
const PFD_DOUBLEBUFFER = 0x00000001;
const PFD_TYPE_RGBA = 0;
const PFD_MAIN_PLANE = 0;

// OpenGL constants
const GL_COLOR_BUFFER_BIT = 0x00004000;
const GL_DEPTH_BUFFER_BIT = 0x00000100;
const GL_DEPTH_TEST = 0x0B71;
const GL_MODELVIEW = 0x1700;
const GL_PROJECTION = 0x1701;
const GL_TRIANGLES = 0x0004;
const GL_LINES = 0x0001;
const GL_VERTEX_ARRAY = 0x8074;
const GL_COLOR_ARRAY = 0x8076;
const GL_FLOAT = 0x1406;
const GL_BLEND = 0x0BE2;
const GL_SRC_ALPHA = 0x0302;
const GL_ONE_MINUS_SRC_ALPHA = 0x0303;

const POINT = extern struct {
    x: i32,
    y: i32,
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

const WNDCLASSW = extern struct {
    style: UINT,
    lpfnWndProc: *const fn (HWND, UINT, WPARAM, LPARAM) callconv(.C) LRESULT,
    cbClsExtra: i32,
    cbWndExtra: i32,
    hInstance: HINSTANCE,
    hIcon: ?*anyopaque,
    hCursor: ?*anyopaque,
    hbrBackground: ?*anyopaque,
    lpszMenuName: ?[*:0]const u16,
    lpszClassName: [*:0]const u16,
};

const PIXELFORMATDESCRIPTOR = extern struct {
    nSize: WORD,
    nVersion: WORD,
    dwFlags: DWORD,
    iPixelType: BYTE,
    cColorBits: BYTE,
    cRedBits: BYTE,
    cRedShift: BYTE,
    cGreenBits: BYTE,
    cGreenShift: BYTE,
    cBlueBits: BYTE,
    cBlueShift: BYTE,
    cAlphaBits: BYTE,
    cAlphaShift: BYTE,
    cAccumBits: BYTE,
    cAccumRedBits: BYTE,
    cAccumGreenBits: BYTE,
    cAccumBlueBits: BYTE,
    cAccumAlphaBits: BYTE,
    cDepthBits: BYTE,
    cStencilBits: BYTE,
    cAuxBuffers: BYTE,
    iLayerType: BYTE,
    bReserved: BYTE,
    dwLayerMask: DWORD,
    dwVisibleMask: DWORD,
    dwDamageMask: DWORD,
};

// Windows API functions
extern "user32" fn RegisterClassW(*const WNDCLASSW) callconv(.C) u16;
extern "user32" fn CreateWindowExW(DWORD, [*:0]const u16, [*:0]const u16, DWORD, i32, i32, i32, i32, ?HWND, ?*anyopaque, HINSTANCE, ?*anyopaque) callconv(.C) ?HWND;
extern "user32" fn ShowWindow(HWND, i32) callconv(.C) BOOL;
extern "user32" fn UpdateWindow(HWND) callconv(.C) BOOL;
extern "user32" fn PeekMessageW(*MSG, ?HWND, UINT, UINT, UINT) callconv(.C) BOOL;
extern "user32" fn TranslateMessage(*const MSG) callconv(.C) BOOL;
extern "user32" fn DispatchMessageW(*const MSG) callconv(.C) LRESULT;
extern "user32" fn DefWindowProcW(HWND, UINT, WPARAM, LPARAM) callconv(.C) LRESULT;
extern "user32" fn PostQuitMessage(i32) callconv(.C) void;
extern "user32" fn DestroyWindow(HWND) callconv(.C) BOOL;
extern "user32" fn LoadCursorW(?HINSTANCE, usize) callconv(.C) ?*anyopaque;
extern "user32" fn GetDC(HWND) callconv(.C) HDC;
extern "user32" fn ReleaseDC(HWND, HDC) callconv(.C) i32;
extern "kernel32" fn GetModuleHandleW(?[*:0]const u16) callconv(.C) HINSTANCE;

// GDI32 functions
extern "gdi32" fn ChoosePixelFormat(HDC, *const PIXELFORMATDESCRIPTOR) callconv(.C) i32;
extern "gdi32" fn SetPixelFormat(HDC, i32, *const PIXELFORMATDESCRIPTOR) callconv(.C) BOOL;
extern "gdi32" fn SwapBuffers(HDC) callconv(.C) BOOL;

// OpenGL32 functions
extern "opengl32" fn wglCreateContext(HDC) callconv(.C) ?HGLRC;
extern "opengl32" fn wglMakeCurrent(HDC, HGLRC) callconv(.C) BOOL;
extern "opengl32" fn wglDeleteContext(HGLRC) callconv(.C) BOOL;
extern "opengl32" fn glClear(UINT) callconv(.C) void;
extern "opengl32" fn glClearColor(f32, f32, f32, f32) callconv(.C) void;
extern "opengl32" fn glEnable(UINT) callconv(.C) void;
extern "opengl32" fn glMatrixMode(UINT) callconv(.C) void;
extern "opengl32" fn glLoadIdentity() callconv(.C) void;
extern "opengl32" fn glTranslatef(f32, f32, f32) callconv(.C) void;
extern "opengl32" fn glRotatef(f32, f32, f32, f32) callconv(.C) void;
extern "opengl32" fn glBegin(UINT) callconv(.C) void;
extern "opengl32" fn glEnd() callconv(.C) void;
extern "opengl32" fn glVertex3f(f32, f32, f32) callconv(.C) void;
extern "opengl32" fn glColor3f(f32, f32, f32) callconv(.C) void;
extern "opengl32" fn glColor4f(f32, f32, f32, f32) callconv(.C) void;
extern "opengl32" fn glViewport(i32, i32, i32, i32) callconv(.C) void;
extern "opengl32" fn gluPerspective(f64, f64, f64, f64) callconv(.C) void;
extern "opengl32" fn glBlendFunc(UINT, UINT) callconv(.C) void;
extern "opengl32" fn glPushMatrix() callconv(.C) void;
extern "opengl32" fn glPopMatrix() callconv(.C) void;
extern "opengl32" fn glScalef(f32, f32, f32) callconv(.C) void;

const SpinningCube = struct {
    hwnd: HWND,
    hdc: HDC,
    hglrc: HGLRC,
    running: bool,
    rotation_x: f32,
    rotation_y: f32,
    start_time: u64,

    const Self = @This();

    pub fn init() !Self {
        const hinstance = GetModuleHandleW(null);
        const class_name = std.unicode.utf8ToUtf16LeStringLiteral("SpinningCube");
        const window_title = std.unicode.utf8ToUtf16LeStringLiteral("Spinning Textured Cube - OpenGL");

        // Register window class
        var wc = WNDCLASSW{
            .style = CS_HREDRAW | CS_VREDRAW | CS_OWNDC,
            .lpfnWndProc = windowProc,
            .cbClsExtra = 0,
            .cbWndExtra = 0,
            .hInstance = hinstance,
            .hIcon = null,
            .hCursor = LoadCursorW(null, IDC_ARROW),
            .hbrBackground = @ptrFromInt(COLOR_WINDOW + 1),
            .lpszMenuName = null,
            .lpszClassName = class_name,
        };

        if (RegisterClassW(&wc) == 0) {
            return error.WindowRegistrationFailed;
        }

        // Create window
        const hwnd = CreateWindowExW(0, class_name, window_title, WS_OVERLAPPEDWINDOW | WS_VISIBLE, 100, 100, 800, 600, null, null, hinstance, null) orelse return error.WindowCreationFailed;

        // Get device context
        const hdc = GetDC(hwnd);

        // Setup pixel format
        var pfd = PIXELFORMATDESCRIPTOR{
            .nSize = @sizeOf(PIXELFORMATDESCRIPTOR),
            .nVersion = 1,
            .dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER,
            .iPixelType = PFD_TYPE_RGBA,
            .cColorBits = 32,
            .cRedBits = 0,
            .cRedShift = 0,
            .cGreenBits = 0,
            .cGreenShift = 0,
            .cBlueBits = 0,
            .cBlueShift = 0,
            .cAlphaBits = 0,
            .cAlphaShift = 0,
            .cAccumBits = 0,
            .cAccumRedBits = 0,
            .cAccumGreenBits = 0,
            .cAccumBlueBits = 0,
            .cAccumAlphaBits = 0,
            .cDepthBits = 24,
            .cStencilBits = 8,
            .cAuxBuffers = 0,
            .iLayerType = PFD_MAIN_PLANE,
            .bReserved = 0,
            .dwLayerMask = 0,
            .dwVisibleMask = 0,
            .dwDamageMask = 0,
        };

        const pixel_format = ChoosePixelFormat(hdc, &pfd);
        if (pixel_format == 0) {
            return error.PixelFormatFailed;
        }

        if (SetPixelFormat(hdc, pixel_format, &pfd) == 0) {
            return error.SetPixelFormatFailed;
        }

        // Create OpenGL context
        const hglrc = wglCreateContext(hdc);
        if (hglrc == null) {
            return error.OpenGLContextFailed;
        }

        const context = hglrc.?;

        if (wglMakeCurrent(hdc, context) == 0) {
            return error.MakeCurrentFailed;
        }

        // Setup OpenGL
        glEnable(GL_DEPTH_TEST);
        glEnable(GL_BLEND);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        glClearColor(0.05, 0.05, 0.15, 1.0);
        glViewport(0, 0, 800, 600);

        // Setup projection matrix
        glMatrixMode(GL_PROJECTION);
        glLoadIdentity();
        gluPerspective(45.0, 800.0 / 600.0, 0.1, 100.0);

        _ = ShowWindow(hwnd, SW_SHOW);
        _ = UpdateWindow(hwnd);

        return Self{
            .hwnd = hwnd,
            .hdc = hdc,
            .hglrc = context,
            .running = true,
            .rotation_x = 0.0,
            .rotation_y = 0.0,
            .start_time = @intCast(std.time.milliTimestamp()),
        };
    }

    pub fn deinit(self: *Self) void {
        _ = wglDeleteContext(self.hglrc);
        _ = ReleaseDC(self.hwnd, self.hdc);
        _ = DestroyWindow(self.hwnd);
    }

    pub fn run(self: *Self) void {
        print("Starting enhanced spinning cube demo with grid...\n", .{});
        print("Features: 3D grid background, enhanced cube colors, smooth animation\n", .{});
        print("Press ESC to exit\n", .{});

        while (self.running) {
            self.processMessages();
            self.update();
            self.render();
            std.time.sleep(16_000_000); // ~60 FPS
        }

        print("Demo finished.\n", .{});
    }

    fn processMessages(self: *Self) void {
        var msg: MSG = undefined;
        while (PeekMessageW(&msg, null, 0, 0, PM_REMOVE) != 0) {
            if (msg.message == 0x0012) { // WM_QUIT
                self.running = false;
                break;
            }
            _ = TranslateMessage(&msg);
            _ = DispatchMessageW(&msg);
        }
    }

    fn update(self: *Self) void {
        const current_time_ms = @as(u64, @intCast(std.time.milliTimestamp()));
        const elapsed_ms = current_time_ms - self.start_time;
        const current_time = @as(f32, @floatFromInt(elapsed_ms)) / 1000.0;
        self.rotation_x = current_time * 50.0; // degrees per second
        self.rotation_y = current_time * 80.0;
    }

    fn render(self: *Self) void {
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

        glMatrixMode(GL_MODELVIEW);
        glLoadIdentity();
        glTranslatef(0.0, 0.0, -5.0);

        // Draw background grid first
        self.drawGrid();

        // Draw the spinning cube
        glPushMatrix();
        glRotatef(self.rotation_x, 1.0, 0.0, 0.0);
        glRotatef(self.rotation_y, 0.0, 1.0, 0.0);
        self.drawCube();
        glPopMatrix();

        _ = SwapBuffers(self.hdc);
    }

    fn drawGrid(self: *Self) void {
        _ = self; // Remove unused parameter warning

        glColor4f(0.3, 0.3, 0.5, 0.6); // Semi-transparent blue-gray grid

        // Draw horizontal grid lines on XZ plane
        glBegin(GL_LINES);
        var i: i32 = -10;
        while (i <= 10) : (i += 1) {
            const pos = @as(f32, @floatFromInt(i));
            // Lines parallel to X axis
            glVertex3f(-10.0, 0.0, pos);
            glVertex3f(10.0, 0.0, pos);
            // Lines parallel to Z axis
            glVertex3f(pos, 0.0, -10.0);
            glVertex3f(pos, 0.0, 10.0);
        }
        glEnd();

        // Draw vertical grid lines
        glColor4f(0.2, 0.2, 0.4, 0.4); // Dimmer vertical lines
        glBegin(GL_LINES);
        i = -10;
        while (i <= 10) : (i += 2) {
            const pos = @as(f32, @floatFromInt(i));
            // Vertical lines in YZ plane
            glVertex3f(0.0, pos, -10.0);
            glVertex3f(0.0, pos, 10.0);
            // Vertical lines in XY plane
            glVertex3f(pos, -10.0, 0.0);
            glVertex3f(pos, 10.0, 0.0);
        }
        glEnd();

        // Draw axis lines for reference
        glBegin(GL_LINES);
        // X axis (red)
        glColor4f(0.8, 0.2, 0.2, 0.8);
        glVertex3f(-15.0, 0.0, 0.0);
        glVertex3f(15.0, 0.0, 0.0);

        // Y axis (green)
        glColor4f(0.2, 0.8, 0.2, 0.8);
        glVertex3f(0.0, -15.0, 0.0);
        glVertex3f(0.0, 15.0, 0.0);

        // Z axis (blue)
        glColor4f(0.2, 0.2, 0.8, 0.8);
        glVertex3f(0.0, 0.0, -15.0);
        glVertex3f(0.0, 0.0, 15.0);
        glEnd();
    }

    fn drawCube(self: *Self) void {
        _ = self; // Remove unused parameter warning

        glBegin(GL_TRIANGLES);

        // Front face (bright red with gradient effect)
        glColor3f(1.0, 0.2, 0.2);
        glVertex3f(-1.0, -1.0, 1.0);
        glColor3f(1.0, 0.4, 0.4);
        glVertex3f(1.0, -1.0, 1.0);
        glColor3f(1.0, 0.6, 0.6);
        glVertex3f(1.0, 1.0, 1.0);
        glVertex3f(1.0, 1.0, 1.0);
        glColor3f(1.0, 0.3, 0.3);
        glVertex3f(-1.0, 1.0, 1.0);
        glColor3f(1.0, 0.2, 0.2);
        glVertex3f(-1.0, -1.0, 1.0);

        // Back face (bright green)
        glColor3f(0.2, 1.0, 0.2);
        glVertex3f(-1.0, -1.0, -1.0);
        glColor3f(0.3, 1.0, 0.3);
        glVertex3f(-1.0, 1.0, -1.0);
        glColor3f(0.6, 1.0, 0.6);
        glVertex3f(1.0, 1.0, -1.0);
        glVertex3f(1.0, 1.0, -1.0);
        glColor3f(0.4, 1.0, 0.4);
        glVertex3f(1.0, -1.0, -1.0);
        glColor3f(0.2, 1.0, 0.2);
        glVertex3f(-1.0, -1.0, -1.0);

        // Left face (bright blue)
        glColor3f(0.2, 0.2, 1.0);
        glVertex3f(-1.0, -1.0, -1.0);
        glColor3f(0.4, 0.4, 1.0);
        glVertex3f(-1.0, -1.0, 1.0);
        glColor3f(0.6, 0.6, 1.0);
        glVertex3f(-1.0, 1.0, 1.0);
        glVertex3f(-1.0, 1.0, 1.0);
        glColor3f(0.3, 0.3, 1.0);
        glVertex3f(-1.0, 1.0, -1.0);
        glColor3f(0.2, 0.2, 1.0);
        glVertex3f(-1.0, -1.0, -1.0);

        // Right face (bright yellow)
        glColor3f(1.0, 1.0, 0.2);
        glVertex3f(1.0, -1.0, -1.0);
        glColor3f(1.0, 1.0, 0.3);
        glVertex3f(1.0, 1.0, -1.0);
        glColor3f(1.0, 1.0, 0.6);
        glVertex3f(1.0, 1.0, 1.0);
        glVertex3f(1.0, 1.0, 1.0);
        glColor3f(1.0, 1.0, 0.4);
        glVertex3f(1.0, -1.0, 1.0);
        glColor3f(1.0, 1.0, 0.2);
        glVertex3f(1.0, -1.0, -1.0);

        // Top face (bright magenta)
        glColor3f(1.0, 0.2, 1.0);
        glVertex3f(-1.0, 1.0, -1.0);
        glColor3f(1.0, 0.4, 1.0);
        glVertex3f(-1.0, 1.0, 1.0);
        glColor3f(1.0, 0.6, 1.0);
        glVertex3f(1.0, 1.0, 1.0);
        glVertex3f(1.0, 1.0, 1.0);
        glColor3f(1.0, 0.3, 1.0);
        glVertex3f(1.0, 1.0, -1.0);
        glColor3f(1.0, 0.2, 1.0);
        glVertex3f(-1.0, 1.0, -1.0);

        // Bottom face (bright cyan)
        glColor3f(0.2, 1.0, 1.0);
        glVertex3f(-1.0, -1.0, -1.0);
        glColor3f(0.4, 1.0, 1.0);
        glVertex3f(1.0, -1.0, -1.0);
        glColor3f(0.6, 1.0, 1.0);
        glVertex3f(1.0, -1.0, 1.0);
        glVertex3f(1.0, -1.0, 1.0);
        glColor3f(0.3, 1.0, 1.0);
        glVertex3f(-1.0, -1.0, 1.0);
        glColor3f(0.2, 1.0, 1.0);
        glVertex3f(-1.0, -1.0, -1.0);

        glEnd();
    }
};

var g_cube: ?*SpinningCube = null;

fn windowProc(hwnd: HWND, uMsg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.C) LRESULT {
    switch (uMsg) {
        WM_DESTROY => {
            if (g_cube) |cube| {
                cube.running = false;
            }
            PostQuitMessage(0);
            return 0;
        },
        WM_CLOSE => {
            if (g_cube) |cube| {
                cube.running = false;
            }
            _ = DestroyWindow(hwnd);
            return 0;
        },
        WM_KEYDOWN => {
            if (wParam == VK_ESCAPE) {
                if (g_cube) |cube| {
                    cube.running = false;
                }
            }
            return 0;
        },
        else => return DefWindowProcW(hwnd, uMsg, wParam, lParam),
    }
}

pub fn main() !void {
    print("=== Simple Spinning Cube Demo ===\n", .{});
    print("Features:\n", .{});
    print("  • Colorful spinning cube with gradient effects\n", .{});
    print("  • 3D grid background with axis indicators\n", .{});
    print("  • OpenGL rendering with transparency\n", .{});
    print("  • Real-time animation at 60 FPS\n", .{});
    print("  • Native Windows window\n", .{});
    print("\n", .{});

    var cube = SpinningCube.init() catch |err| {
        print("Failed to initialize cube: {}\n", .{err});
        return;
    };
    defer cube.deinit();

    g_cube = &cube;
    cube.run();
    g_cube = null;

    print("Thanks for watching the spinning cube!\n", .{});
}
