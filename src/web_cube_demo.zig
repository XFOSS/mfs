//! MFS Engine WebAssembly Spinning Cube Demo
//! This module provides a WASM-compatible spinning cube demo for web documentation

const std = @import("std");
const math = @import("math/mod.zig");

// Web-specific imports and exports
pub const wasm_allocator = std.heap.WasmAllocator{};
var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = false }){};
const allocator = gpa.allocator();

// Global state for the cube demo
var cube_rotation: f32 = 0.0;
var last_frame_time: f64 = 0.0;
var is_running: bool = false;
var canvas_width: u32 = 800;
var canvas_height: u32 = 600;

// Cube vertices (position + color)
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
    1.0,  1.0,  -1.0, 0.0, 0.0, 1.0,
    1.0,  1.0,  1.0,  0.0, 0.0, 1.0,
    1.0,  1.0,  1.0,  0.0, 0.0, 1.0,
    -1.0, 1.0,  1.0,  0.0, 0.0, 1.0,
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

// Matrix math functions
fn mat4Identity() [16]f32 {
    return [16]f32{
        1.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 0.0,
        0.0, 0.0, 1.0, 0.0,
        0.0, 0.0, 0.0, 1.0,
    };
}

fn mat4RotateY(angle: f32) [16]f32 {
    const c = @cos(angle);
    const s = @sin(angle);
    return [16]f32{
        c,   0.0, s,   0.0,
        0.0, 1.0, 0.0, 0.0,
        -s,  0.0, c,   0.0,
        0.0, 0.0, 0.0, 1.0,
    };
}

fn mat4RotateX(angle: f32) [16]f32 {
    const c = @cos(angle);
    const s = @sin(angle);
    return [16]f32{
        1.0, 0.0, 0.0, 0.0,
        0.0, c,   -s,  0.0,
        0.0, s,   c,   0.0,
        0.0, 0.0, 0.0, 1.0,
    };
}

fn mat4Translate(x: f32, y: f32, z: f32) [16]f32 {
    return [16]f32{
        1.0, 0.0, 0.0, x,
        0.0, 1.0, 0.0, y,
        0.0, 0.0, 1.0, z,
        0.0, 0.0, 0.0, 1.0,
    };
}

fn mat4Perspective(fov: f32, aspect: f32, near: f32, far: f32) [16]f32 {
    const f = 1.0 / @tan(fov / 2.0);
    const range = near - far;
    return [16]f32{
        f / aspect, 0.0, 0.0,                  0.0,
        0.0,        f,   0.0,                  0.0,
        0.0,        0.0, (near + far) / range, (2.0 * near * far) / range,
        0.0,        0.0, -1.0,                 0.0,
    };
}

fn mat4Multiply(a: [16]f32, b: [16]f32) [16]f32 {
    var result: [16]f32 = undefined;
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

// WebGL shader sources
const vertex_shader_source =
    \\attribute vec3 a_position;
    \\attribute vec3 a_color;
    \\uniform mat4 u_model;
    \\uniform mat4 u_view;
    \\uniform mat4 u_projection;
    \\varying vec3 v_color;
    \\void main() {
    \\    gl_Position = u_projection * u_view * u_model * vec4(a_position, 1.0);
    \\    v_color = a_color;
    \\}
;

const fragment_shader_source =
    \\precision mediump float;
    \\varying vec3 v_color;
    \\void main() {
    \\    gl_FragColor = vec4(v_color, 1.0);
    \\}
;

// WebGL context and state
var gl: ?*anyopaque = null;
var program: u32 = 0;
var position_attrib: i32 = 0;
var color_attrib: i32 = 0;
var model_uniform: i32 = 0;
var view_uniform: i32 = 0;
var projection_uniform: i32 = 0;
var vbo: u32 = 0;

// WebGL function pointers (will be set by JavaScript)
var glCreateShader: ?*const fn (u32) callconv(.C) u32 = null;
var glShaderSource: ?*const fn (u32, i32, [*]const [*:0]const u8, ?[*]const i32) callconv(.C) void = null;
var glCompileShader: ?*const fn (u32) callconv(.C) void = null;
var glGetShaderiv: ?*const fn (u32, u32, [*]i32) callconv(.C) void = null;
var glCreateProgram: ?*const fn () callconv(.C) u32 = null;
var glAttachShader: ?*const fn (u32, u32) callconv(.C) void = null;
var glLinkProgram: ?*const fn (u32) callconv(.C) void = null;
var glGetProgramiv: ?*const fn (u32, u32, [*]i32) callconv(.C) void = null;
var glUseProgram: ?*const fn (u32) callconv(.C) void = null;
var glGetAttribLocation: ?*const fn (u32, [*:0]const u8) callconv(.C) i32 = null;
var glGetUniformLocation: ?*const fn (u32, [*:0]const u8) callconv(.C) i32 = null;
var glGenBuffers: ?*const fn (i32, [*]u32) callconv(.C) void = null;
var glBindBuffer: ?*const fn (u32, u32) callconv(.C) void = null;
var glBufferData: ?*const fn (u32, isize, ?*const anyopaque, u32) callconv(.C) void = null;
var glVertexAttribPointer: ?*const fn (u32, i32, u32, u8, i32, ?*const anyopaque) callconv(.C) void = null;
var glEnableVertexAttribArray: ?*const fn (u32) callconv(.C) void = null;
var glClear: ?*const fn (u32) callconv(.C) void = null;
var glClearColor: ?*const fn (f32, f32, f32, f32) callconv(.C) void = null;
var glViewport: ?*const fn (i32, i32, i32, i32) callconv(.C) void = null;
var glDrawArrays: ?*const fn (u32, i32, i32) callconv(.C) void = null;
var glUniformMatrix4fv: ?*const fn (i32, i32, u8, [*]const f32) callconv(.C) void = null;

// WebGL constants
const GL_VERTEX_SHADER = 0x8B31;
const GL_FRAGMENT_SHADER = 0x8B30;
const GL_COMPILE_STATUS = 0x8B81;
const GL_LINK_STATUS = 0x8B82;
const GL_ARRAY_BUFFER = 0x8892;
const GL_STATIC_DRAW = 0x88E4;
const GL_FLOAT = 0x1406;
const GL_FALSE = 0;
const GL_TRIANGLES = 0x0004;
const GL_COLOR_BUFFER_BIT = 0x00004000;
const GL_DEPTH_BUFFER_BIT = 0x00000100;

// Initialize the WebGL context and shaders
export fn initialize_webgl(webgl_context: *anyopaque) i32 {
    gl = webgl_context;

    // Set up function pointers (these would be set by JavaScript)
    // For now, we'll assume they're available

    // Create and compile vertex shader
    const vertex_shader = glCreateShader.?(GL_VERTEX_SHADER);
    glShaderSource.?(vertex_shader, 1, @ptrCast(&vertex_shader_source), null);
    glCompileShader.?(vertex_shader);

    var success: i32 = 0;
    glGetShaderiv.?(vertex_shader, GL_COMPILE_STATUS, @ptrCast(&success));
    if (success == GL_FALSE) {
        return -1; // Vertex shader compilation failed
    }

    // Create and compile fragment shader
    const fragment_shader = glCreateShader.?(GL_FRAGMENT_SHADER);
    glShaderSource.?(fragment_shader, 1, @ptrCast(&fragment_shader_source), null);
    glCompileShader.?(fragment_shader);

    glGetShaderiv.?(fragment_shader, GL_COMPILE_STATUS, @ptrCast(&success));
    if (success == GL_FALSE) {
        return -2; // Fragment shader compilation failed
    }

    // Create shader program
    program = glCreateProgram.?();
    glAttachShader.?(program, vertex_shader);
    glAttachShader.?(program, fragment_shader);
    glLinkProgram.?(program);

    glGetProgramiv.?(program, GL_LINK_STATUS, @ptrCast(&success));
    if (success == GL_FALSE) {
        return -3; // Program linking failed
    }

    // Get attribute and uniform locations
    position_attrib = glGetAttribLocation.?(program, "a_position");
    color_attrib = glGetAttribLocation.?(program, "a_color");
    model_uniform = glGetUniformLocation.?(program, "u_model");
    view_uniform = glGetUniformLocation.?(program, "u_view");
    projection_uniform = glGetUniformLocation.?(program, "u_projection");

    // Create and bind vertex buffer
    glGenBuffers.?(1, @ptrCast(&vbo));
    glBindBuffer.?(GL_ARRAY_BUFFER, vbo);
    glBufferData.?(GL_ARRAY_BUFFER, @sizeOf(@TypeOf(cube_vertices)), &cube_vertices, GL_STATIC_DRAW);

    // Set up vertex attributes
    glVertexAttribPointer.?(@intCast(position_attrib), 3, GL_FLOAT, GL_FALSE, 6 * @sizeOf(f32), null);
    glEnableVertexAttribArray.?(@intCast(position_attrib));

    glVertexAttribPointer.?(@intCast(color_attrib), 3, GL_FLOAT, GL_FALSE, 6 * @sizeOf(f32), @ptrFromInt(3 * @sizeOf(f32)));
    glEnableVertexAttribArray.?(@intCast(color_attrib));

    // Set up viewport and clear color
    glViewport.?(0, 0, @intCast(canvas_width), @intCast(canvas_height));
    glClearColor.?(0.2, 0.3, 0.3, 1.0);

    return 0; // Success
}

// Render the spinning cube
export fn render_cube(delta_time: f32) void {
    if (!is_running) return;

    cube_rotation += delta_time;

    glClear.?(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    glUseProgram.?(program);

    // Create transformation matrices
    const model = mat4Multiply(mat4RotateY(cube_rotation), mat4RotateX(cube_rotation * 0.5));
    const view = mat4Translate(0.0, 0.0, -5.0);
    const aspect = @as(f32, @floatFromInt(canvas_width)) / @as(f32, @floatFromInt(canvas_height));
    const projection = mat4Perspective(std.math.degreesToRadians(45.0), aspect, 0.1, 100.0);

    // Set uniforms
    glUniformMatrix4fv.?(model_uniform, 1, GL_FALSE, &model);
    glUniformMatrix4fv.?(view_uniform, 1, GL_FALSE, &view);
    glUniformMatrix4fv.?(projection_uniform, 1, GL_FALSE, &projection);

    // Draw cube
    glBindBuffer.?(GL_ARRAY_BUFFER, vbo);
    glDrawArrays.?(GL_TRIANGLES, 0, 36);
}

// Set canvas size
export fn set_canvas_size(width: u32, height: u32) void {
    canvas_width = width;
    canvas_height = height;
    glViewport.?(0, 0, @intCast(width), @intCast(height));
}

// Start the demo
export fn start_demo() void {
    is_running = true;
    last_frame_time = 0.0;
}

// Stop the demo
export fn stop_demo() void {
    is_running = false;
}

// Reset the demo
export fn reset_demo() void {
    cube_rotation = 0.0;
    last_frame_time = 0.0;
    is_running = false;
}

// Get current rotation for external use
export fn get_rotation() f32 {
    return cube_rotation;
}

// Get demo status
export fn is_demo_running() bool {
    return is_running;
}
