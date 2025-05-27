const std = @import("std");
const Allocator = std.mem.Allocator;

// Windows OpenGL API
const HWND = *opaque {};
const HDC = *opaque {};
const HGLRC = *opaque {};
const PIXELFORMATDESCRIPTOR = extern struct {
    nSize: u16,
    nVersion: u16,
    dwFlags: u32,
    iPixelType: u8,
    cColorBits: u8,
    cRedBits: u8,
    cRedShift: u8,
    cGreenBits: u8,
    cGreenShift: u8,
    cBlueBits: u8,
    cBlueShift: u8,
    cAlphaBits: u8,
    cAlphaShift: u8,
    cAccumBits: u8,
    cAccumRedBits: u8,
    cAccumGreenBits: u8,
    cAccumBlueBits: u8,
    cAccumAlphaBits: u8,
    cDepthBits: u8,
    cStencilBits: u8,
    cAuxBuffers: u8,
    iLayerType: u8,
    bReserved: u8,
    dwLayerMask: u32,
    dwVisibleMask: u32,
    dwDamageMask: u32,
};

// OpenGL constants
const PFD_DRAW_TO_WINDOW = 0x00000004;
const PFD_SUPPORT_OPENGL = 0x00000020;
const PFD_DOUBLEBUFFER = 0x00000001;
const PFD_TYPE_RGBA = 0;
const PFD_MAIN_PLANE = 0;

const GL_COLOR_BUFFER_BIT = 0x00004000;
const GL_DEPTH_BUFFER_BIT = 0x00000100;
const GL_DEPTH_TEST = 0x0B71;
const GL_TRIANGLES = 0x0004;
const GL_FLOAT = 0x1406;
const GL_FALSE = 0;
const GL_TRUE = 1;
const GL_VERTEX_SHADER = 0x8B31;
const GL_FRAGMENT_SHADER = 0x8B35;
const GL_COMPILE_STATUS = 0x8B81;
const GL_LINK_STATUS = 0x8B82;
const GL_ARRAY_BUFFER = 0x8892;
const GL_STATIC_DRAW = 0x88E4;

// Windows API
extern "gdi32" fn GetDC(HWND) callconv(.C) HDC;
extern "gdi32" fn ReleaseDC(HWND, HDC) callconv(.C) i32;
extern "gdi32" fn ChoosePixelFormat(HDC, *const PIXELFORMATDESCRIPTOR) callconv(.C) i32;
extern "gdi32" fn SetPixelFormat(HDC, i32, *const PIXELFORMATDESCRIPTOR) callconv(.C) i32;
extern "gdi32" fn SwapBuffers(HDC) callconv(.C) i32;

// OpenGL API
extern "opengl32" fn wglCreateContext(HDC) callconv(.C) ?HGLRC;
extern "opengl32" fn wglMakeCurrent(HDC, ?HGLRC) callconv(.C) i32;
extern "opengl32" fn wglDeleteContext(?HGLRC) callconv(.C) i32;
extern "opengl32" fn wglGetProcAddress([*:0]const u8) callconv(.C) ?*anyopaque;

// OpenGL function pointers
var glClear: ?*const fn (u32) callconv(.C) void = null;
var glClearColor: ?*const fn (f32, f32, f32, f32) callconv(.C) void = null;
var glEnable: ?*const fn (u32) callconv(.C) void = null;
var glViewport: ?*const fn (i32, i32, i32, i32) callconv(.C) void = null;
var glGenBuffers: ?*const fn (i32, [*]u32) callconv(.C) void = null;
var glBindBuffer: ?*const fn (u32, u32) callconv(.C) void = null;
var glBufferData: ?*const fn (u32, isize, ?*const anyopaque, u32) callconv(.C) void = null;
var glGenVertexArrays: ?*const fn (i32, [*]u32) callconv(.C) void = null;
var glBindVertexArray: ?*const fn (u32) callconv(.C) void = null;
var glVertexAttribPointer: ?*const fn (u32, i32, u32, u8, i32, ?*const anyopaque) callconv(.C) void = null;
var glEnableVertexAttribArray: ?*const fn (u32) callconv(.C) void = null;
var glCreateShader: ?*const fn (u32) callconv(.C) u32 = null;
var glShaderSource: ?*const fn (u32, i32, [*]const [*:0]const u8, ?[*]const i32) callconv(.C) void = null;
var glCompileShader: ?*const fn (u32) callconv(.C) void = null;
var glGetShaderiv: ?*const fn (u32, u32, [*]i32) callconv(.C) void = null;
var glCreateProgram: ?*const fn () callconv(.C) u32 = null;
var glAttachShader: ?*const fn (u32, u32) callconv(.C) void = null;
var glLinkProgram: ?*const fn (u32) callconv(.C) void = null;
var glGetProgramiv: ?*const fn (u32, u32, [*]i32) callconv(.C) void = null;
var glUseProgram: ?*const fn (u32) callconv(.C) void = null;
var glGetUniformLocation: ?*const fn (u32, [*:0]const u8) callconv(.C) i32 = null;
var glUniformMatrix4fv: ?*const fn (i32, i32, u8, [*]const f32) callconv(.C) void = null;
var glDrawArrays: ?*const fn (u32, i32, i32) callconv(.C) void = null;
var glDeleteShader: ?*const fn (u32) callconv(.C) void = null;

// Matrix math
const Mat4 = [16]f32;

fn mat4Identity() Mat4 {
    return [_]f32{
        1.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 0.0,
        0.0, 0.0, 1.0, 0.0,
        0.0, 0.0, 0.0, 1.0,
    };
}

fn mat4Perspective(fov: f32, aspect: f32, near: f32, far: f32) Mat4 {
    const f = 1.0 / std.math.tan(fov * 0.5);
    var result = mat4Identity();

    result[0] = f / aspect;
    result[5] = f;
    result[10] = (far + near) / (near - far);
    result[11] = -1.0;
    result[14] = (2.0 * far * near) / (near - far);
    result[15] = 0.0;

    return result;
}

fn mat4RotateY(angle: f32) Mat4 {
    const cos_a = std.math.cos(angle);
    const sin_a = std.math.sin(angle);
    var result = mat4Identity();

    result[0] = cos_a;
    result[2] = sin_a;
    result[8] = -sin_a;
    result[10] = cos_a;

    return result;
}

fn mat4RotateX(angle: f32) Mat4 {
    const cos_a = std.math.cos(angle);
    const sin_a = std.math.sin(angle);
    var result = mat4Identity();

    result[5] = cos_a;
    result[6] = -sin_a;
    result[9] = sin_a;
    result[10] = cos_a;

    return result;
}

fn mat4Multiply(a: Mat4, b: Mat4) Mat4 {
    var result: Mat4 = undefined;

    for (0..4) |i| {
        for (0..4) |j| {
            result[i * 4 + j] = 0.0;
            for (0..4) |k| {
                result[i * 4 + j] += a[i * 4 + k] * b[k * 4 + j];
            }
        }
    }

    return result;
}

fn mat4Translate(x: f32, y: f32, z: f32) Mat4 {
    var result = mat4Identity();
    result[12] = x;
    result[13] = y;
    result[14] = z;
    return result;
}

// Cube vertex data (position + color)
const cube_vertices = [_]f32{
    // Front face (red)
    -1.0, -1.0, 1.0,  1.0, 0.0, 0.0,
    1.0,  -1.0, 1.0,  1.0, 0.0, 0.0,
    1.0,  1.0,  1.0,  1.0, 0.0, 0.0,
    1.0,  1.0,  1.0,  1.0, 0.0, 0.0,
    -1.0, 1.0,  1.0,  1.0, 0.0, 0.0,
    -1.0, -1.0, 1.0,  1.0, 0.0, 0.0,

    // Back face (green)
    -1.0, -1.0, -1.0, 0.0, 1.0, 0.0,
    -1.0, 1.0,  -1.0, 0.0, 1.0, 0.0,
    1.0,  1.0,  -1.0, 0.0, 1.0, 0.0,
    1.0,  1.0,  -1.0, 0.0, 1.0, 0.0,
    1.0,  -1.0, -1.0, 0.0, 1.0, 0.0,
    -1.0, -1.0, -1.0, 0.0, 1.0, 0.0,

    // Top face (blue)
    -1.0, 1.0,  -1.0, 0.0, 0.0, 1.0,
    -1.0, 1.0,  1.0,  0.0, 0.0, 1.0,
    1.0,  1.0,  1.0,  0.0, 0.0, 1.0,
    1.0,  1.0,  1.0,  0.0, 0.0, 1.0,
    1.0,  1.0,  -1.0, 0.0, 0.0, 1.0,
    -1.0, 1.0,  -1.0, 0.0, 0.0, 1.0,

    // Bottom face (yellow)
    -1.0, -1.0, -1.0, 1.0, 1.0, 0.0,
    1.0,  -1.0, -1.0, 1.0, 1.0, 0.0,
    1.0,  -1.0, 1.0,  1.0, 1.0, 0.0,
    1.0,  -1.0, 1.0,  1.0, 1.0, 0.0,
    -1.0, -1.0, 1.0,  1.0, 1.0, 0.0,
    -1.0, -1.0, -1.0, 1.0, 1.0, 0.0,

    // Right face (magenta)
    1.0,  -1.0, -1.0, 1.0, 0.0, 1.0,
    1.0,  1.0,  -1.0, 1.0, 0.0, 1.0,
    1.0,  1.0,  1.0,  1.0, 0.0, 1.0,
    1.0,  1.0,  1.0,  1.0, 0.0, 1.0,
    1.0,  -1.0, 1.0,  1.0, 0.0, 1.0,
    1.0,  -1.0, -1.0, 1.0, 0.0, 1.0,

    // Left face (cyan)
    -1.0, -1.0, -1.0, 0.0, 1.0, 1.0,
    -1.0, -1.0, 1.0,  0.0, 1.0, 1.0,
    -1.0, 1.0,  1.0,  0.0, 1.0, 1.0,
    -1.0, 1.0,  1.0,  0.0, 1.0, 1.0,
    -1.0, 1.0,  -1.0, 0.0, 1.0, 1.0,
    -1.0, -1.0, -1.0, 0.0, 1.0, 1.0,
};

const vertex_shader_source =
    \\#version 330 core
    \\layout (location = 0) in vec3 aPos;
    \\layout (location = 1) in vec3 aColor;
    \\
    \\uniform mat4 model;
    \\uniform mat4 view;
    \\uniform mat4 projection;
    \\
    \\out vec3 vertexColor;
    \\
    \\void main()
    \\{
    \\    gl_Position = projection * view * model * vec4(aPos, 1.0);
    \\    vertexColor = aColor;
    \\}
;

const fragment_shader_source =
    \\#version 330 core
    \\in vec3 vertexColor;
    \\out vec4 FragColor;
    \\
    \\void main()
    \\{
    \\    FragColor = vec4(vertexColor, 1.0);
    \\}
;

pub const OpenGLCube = struct {
    allocator: Allocator,
    hwnd: HWND,
    hdc: HDC,
    hglrc: ?HGLRC,
    vao: u32,
    vbo: u32,
    shader_program: u32,
    model_loc: i32,
    view_loc: i32,
    projection_loc: i32,
    width: u32,
    height: u32,
    rotation: f32,

    const Self = @This();

    pub fn init(allocator: Allocator, hwnd: HWND, width: u32, height: u32) !Self {
        const hdc = GetDC(hwnd);

        // Set up pixel format
        const pfd = PIXELFORMATDESCRIPTOR{
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
            return error.PixelFormatNotFound;
        }

        if (SetPixelFormat(hdc, pixel_format, &pfd) == 0) {
            return error.SetPixelFormatFailed;
        }

        // Create OpenGL context
        const hglrc = wglCreateContext(hdc) orelse return error.OpenGLContextCreationFailed;

        if (wglMakeCurrent(hdc, hglrc) == 0) {
            _ = wglDeleteContext(hglrc);
            return error.MakeCurrentFailed;
        }

        var cube = Self{
            .allocator = allocator,
            .hwnd = hwnd,
            .hdc = hdc,
            .hglrc = hglrc,
            .vao = 0,
            .vbo = 0,
            .shader_program = 0,
            .model_loc = -1,
            .view_loc = -1,
            .projection_loc = -1,
            .width = width,
            .height = height,
            .rotation = 0.0,
        };

        try cube.loadOpenGLFunctions();
        try cube.setupShaders();
        try cube.setupBuffers();
        cube.setupViewport();

        return cube;
    }

    pub fn deinit(self: *Self) void {
        if (self.hglrc) |hglrc| {
            _ = wglMakeCurrent(self.hdc, null);
            _ = wglDeleteContext(hglrc);
        }
        _ = ReleaseDC(self.hwnd, self.hdc);
    }

    fn loadOpenGLFunctions(self: *Self) !void {
        _ = self;

        glClear = @ptrCast(wglGetProcAddress("glClear") orelse return error.MissingGLFunction);
        glClearColor = @ptrCast(wglGetProcAddress("glClearColor") orelse return error.MissingGLFunction);
        glEnable = @ptrCast(wglGetProcAddress("glEnable") orelse return error.MissingGLFunction);
        glViewport = @ptrCast(wglGetProcAddress("glViewport") orelse return error.MissingGLFunction);
        glGenBuffers = @ptrCast(wglGetProcAddress("glGenBuffers") orelse return error.MissingGLFunction);
        glBindBuffer = @ptrCast(wglGetProcAddress("glBindBuffer") orelse return error.MissingGLFunction);
        glBufferData = @ptrCast(wglGetProcAddress("glBufferData") orelse return error.MissingGLFunction);
        glGenVertexArrays = @ptrCast(wglGetProcAddress("glGenVertexArrays") orelse return error.MissingGLFunction);
        glBindVertexArray = @ptrCast(wglGetProcAddress("glBindVertexArray") orelse return error.MissingGLFunction);
        glVertexAttribPointer = @ptrCast(wglGetProcAddress("glVertexAttribPointer") orelse return error.MissingGLFunction);
        glEnableVertexAttribArray = @ptrCast(wglGetProcAddress("glEnableVertexAttribArray") orelse return error.MissingGLFunction);
        glCreateShader = @ptrCast(wglGetProcAddress("glCreateShader") orelse return error.MissingGLFunction);
        glShaderSource = @ptrCast(wglGetProcAddress("glShaderSource") orelse return error.MissingGLFunction);
        glCompileShader = @ptrCast(wglGetProcAddress("glCompileShader") orelse return error.MissingGLFunction);
        glGetShaderiv = @ptrCast(wglGetProcAddress("glGetShaderiv") orelse return error.MissingGLFunction);
        glCreateProgram = @ptrCast(wglGetProcAddress("glCreateProgram") orelse return error.MissingGLFunction);
        glAttachShader = @ptrCast(wglGetProcAddress("glAttachShader") orelse return error.MissingGLFunction);
        glLinkProgram = @ptrCast(wglGetProcAddress("glLinkProgram") orelse return error.MissingGLFunction);
        glGetProgramiv = @ptrCast(wglGetProcAddress("glGetProgramiv") orelse return error.MissingGLFunction);
        glUseProgram = @ptrCast(wglGetProcAddress("glUseProgram") orelse return error.MissingGLFunction);
        glGetUniformLocation = @ptrCast(wglGetProcAddress("glGetUniformLocation") orelse return error.MissingGLFunction);
        glUniformMatrix4fv = @ptrCast(wglGetProcAddress("glUniformMatrix4fv") orelse return error.MissingGLFunction);
        glDrawArrays = @ptrCast(wglGetProcAddress("glDrawArrays") orelse return error.MissingGLFunction);
        glDeleteShader = @ptrCast(wglGetProcAddress("glDeleteShader") orelse return error.MissingGLFunction);
    }

    fn setupShaders(self: *Self) !void {
        // Compile vertex shader
        const vertex_shader = glCreateShader.?(GL_VERTEX_SHADER);
        const vertex_source_ptr: [*:0]const u8 = vertex_shader_source.ptr;
        glShaderSource.?(vertex_shader, 1, @ptrCast(&vertex_source_ptr), null);
        glCompileShader.?(vertex_shader);

        var success: i32 = 0;
        glGetShaderiv.?(vertex_shader, GL_COMPILE_STATUS, &success);
        if (success == GL_FALSE) {
            return error.VertexShaderCompilationFailed;
        }

        // Compile fragment shader
        const fragment_shader = glCreateShader.?(GL_FRAGMENT_SHADER);
        const fragment_source_ptr: [*:0]const u8 = fragment_shader_source.ptr;
        glShaderSource.?(fragment_shader, 1, @ptrCast(&fragment_source_ptr), null);
        glCompileShader.?(fragment_shader);

        glGetShaderiv.?(fragment_shader, GL_COMPILE_STATUS, &success);
        if (success == GL_FALSE) {
            return error.FragmentShaderCompilationFailed;
        }

        // Create shader program
        self.shader_program = glCreateProgram.?();
        glAttachShader.?(self.shader_program, vertex_shader);
        glAttachShader.?(self.shader_program, fragment_shader);
        glLinkProgram.?(self.shader_program);

        glGetProgramiv.?(self.shader_program, GL_LINK_STATUS, &success);
        if (success == GL_FALSE) {
            return error.ShaderProgramLinkFailed;
        }

        // Get uniform locations
        self.model_loc = glGetUniformLocation.?(self.shader_program, "model");
        self.view_loc = glGetUniformLocation.?(self.shader_program, "view");
        self.projection_loc = glGetUniformLocation.?(self.shader_program, "projection");

        // Clean up shaders
        glDeleteShader.?(vertex_shader);
        glDeleteShader.?(fragment_shader);
    }

    fn setupBuffers(self: *Self) !void {
        // Generate and bind VAO
        glGenVertexArrays.?(1, @ptrCast(&self.vao));
        glBindVertexArray.?(self.vao);

        // Generate and bind VBO
        glGenBuffers.?(1, @ptrCast(&self.vbo));
        glBindBuffer.?(GL_ARRAY_BUFFER, self.vbo);
        glBufferData.?(GL_ARRAY_BUFFER, @sizeOf(@TypeOf(cube_vertices)), &cube_vertices, GL_STATIC_DRAW);

        // Position attribute
        glVertexAttribPointer.?(0, 3, GL_FLOAT, GL_FALSE, 6 * @sizeOf(f32), null);
        glEnableVertexAttribArray.?(0);

        // Color attribute
        glVertexAttribPointer.?(1, 3, GL_FLOAT, GL_FALSE, 6 * @sizeOf(f32), @ptrFromInt(3 * @sizeOf(f32)));
        glEnableVertexAttribArray.?(1);
    }

    fn setupViewport(self: *Self) void {
        glViewport.?(0, 0, @intCast(self.width), @intCast(self.height));
        glEnable.?(GL_DEPTH_TEST);
        glClearColor.?(0.2, 0.3, 0.3, 1.0);
    }

    pub fn resize(self: *Self, width: u32, height: u32) void {
        self.width = width;
        self.height = height;
        glViewport.?(0, 0, @intCast(width), @intCast(height));
    }

    pub fn render(self: *Self, delta_time: f32) void {
        self.rotation += delta_time;

        glClear.?(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

        glUseProgram.?(self.shader_program);

        // Create matrices
        const model = mat4Multiply(mat4RotateY(self.rotation), mat4RotateX(self.rotation * 0.5));
        const view = mat4Translate(0.0, 0.0, -5.0);
        const aspect = @as(f32, @floatFromInt(self.width)) / @as(f32, @floatFromInt(self.height));
        const projection = mat4Perspective(std.math.degreesToRadians(45.0), aspect, 0.1, 100.0);

        // Set uniforms
        glUniformMatrix4fv.?(self.model_loc, 1, GL_FALSE, &model);
        glUniformMatrix4fv.?(self.view_loc, 1, GL_FALSE, &view);
        glUniformMatrix4fv.?(self.projection_loc, 1, GL_FALSE, &projection);

        // Draw cube
        glBindVertexArray.?(self.vao);
        glDrawArrays.?(GL_TRIANGLES, 0, 36);

        _ = SwapBuffers(self.hdc);
    }
};

// Simple OpenGL window with cube
pub const OpenGLWindow = struct {
    allocator: Allocator,
    window: @import("../ui/simple_window.zig").Window,
    cube: OpenGLCube,

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        var window = try @import("../ui/simple_window.zig").Window.init(allocator, .{
            .title = "OpenGL Spinning Cube",
            .width = 1280,
            .height = 720,
            .resizable = true,
        });

        const native_handle = window.getNativeHandle() orelse return error.NoNativeHandle;
        const cube = try OpenGLCube.init(allocator, native_handle.hwnd, window.width, window.height);

        return Self{
            .allocator = allocator,
            .window = window,
            .cube = cube,
        };
    }

    pub fn deinit(self: *Self) void {
        self.cube.deinit();
        self.window.deinit();
    }

    pub fn run(self: *Self) !void {
        var last_time = std.time.nanoTimestamp();

        while (!self.window.shouldClose()) {
            try self.window.pollEvents();

            const current_time = std.time.nanoTimestamp();
            const delta_time = @as(f32, @floatFromInt(current_time - last_time)) / 1_000_000_000.0;
            last_time = current_time;

            const size = self.window.getSize();
            if (size.width != self.cube.width or size.height != self.cube.height) {
                self.cube.resize(size.width, size.height);
            }

            self.cube.render(delta_time);
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var opengl_window = try OpenGLWindow.init(allocator);
    defer opengl_window.deinit();

    std.debug.print("Starting OpenGL cube demo...\n");
    std.debug.print("Press ESC to exit\n");

    try opengl_window.run();
}
