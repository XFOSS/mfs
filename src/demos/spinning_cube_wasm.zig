const std = @import("std");

// Global state
var allocator: std.mem.Allocator = undefined;
var canvas_width: u32 = 800;
var canvas_height: u32 = 400;
var is_running: bool = false;
var rotation: f32 = 0.0;
var last_time: f64 = 0.0;

// WebGL context (simulated for WASM)
var gl_context: ?*anyopaque = null;

// Vertex and fragment shaders
const vertex_shader_source = 
    \\attribute vec3 position;
    \\attribute vec3 color;
    \\uniform mat4 modelViewMatrix;
    \\uniform mat4 projectionMatrix;
    \\varying vec3 vColor;
    \\void main() {
    \\    gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
    \\    vColor = color;
    \\}
;

const fragment_shader_source = 
    \\precision mediump float;
    \\varying vec3 vColor;
    \\void main() {
    \\    gl_FragColor = vec4(vColor, 1.0);
    \\}
;

// Cube vertices (position + color)
const cube_vertices = [_]f32{
    // Front face
    -1.0, -1.0,  1.0,  1.0, 0.0, 0.0,
     1.0, -1.0,  1.0,  0.0, 1.0, 0.0,
     1.0,  1.0,  1.0,  0.0, 0.0, 1.0,
    -1.0,  1.0,  1.0,  1.0, 1.0, 0.0,
    // Back face
    -1.0, -1.0, -1.0,  1.0, 0.0, 1.0,
     1.0, -1.0, -1.0,  0.0, 1.0, 1.0,
     1.0,  1.0, -1.0,  1.0, 1.0, 1.0,
    -1.0,  1.0, -1.0,  0.0, 0.0, 0.0,
};

const cube_indices = [_]u16{
    0, 1, 2,  0, 2, 3,  // Front
    1, 5, 6,  1, 6, 2,  // Right
    5, 4, 7,  5, 7, 6,  // Back
    4, 0, 3,  4, 3, 7,  // Left
    3, 2, 6,  3, 6, 7,  // Top
    4, 5, 1,  4, 1, 0   // Bottom
};

// Matrix utilities
fn createModelViewMatrix(rot: f32) [16]f32 {
    const cos = @cos(rot);
    const sin = @sin(rot);
    
    return [16]f32{
        cos,  0.0,  sin,  0.0,
        0.0,  1.0,  0.0,  0.0,
        -sin, 0.0,  cos,  0.0,
        0.0,  0.0,  -5.0, 1.0,
    };
}

fn createProjectionMatrix() [16]f32 {
    const aspect = @as(f32, @floatFromInt(canvas_width)) / @as(f32, @floatFromInt(canvas_height));
    const fov = std.math.pi / 4.0;
    const near: f32 = 0.1;
    const far: f32 = 100.0;
    
    const f = 1.0 / @tan(fov / 2.0);
    
    return [16]f32{
        f / aspect, 0.0, 0.0, 0.0,
        0.0, f, 0.0, 0.0,
        0.0, 0.0, (far + near) / (near - far), -1.0,
        0.0, 0.0, (2.0 * far * near) / (near - far), 0.0,
    };
}

// WebGL simulation functions (for WASM)
fn webglClearColor(r: f32, g: f32, b: f32, a: f32) void {
    _ = r; _ = g; _ = b; _ = a;
    // In real WASM, this would call the actual WebGL function
}

fn webglClear(mask: u32) void {
    _ = mask;
    // In real WASM, this would call the actual WebGL function
}

fn webglUseProgram(program: u32) void {
    _ = program;
    // In real WASM, this would call the actual WebGL function
}

fn webglUniformMatrix4fv(location: i32, transpose: bool, value: [16]f32) void {
    _ = location; _ = transpose; _ = value;
    // In real WASM, this would call the actual WebGL function
}

fn webglDrawElements(mode: u32, count: i32, type: u32, offset: usize) void {
    _ = mode; _ = count; _ = type; _ = offset;
    // In real WASM, this would call the actual WebGL function
}

fn webglViewport(x: i32, y: i32, width: i32, height: i32) void {
    _ = x; _ = y; _ = width; _ = height;
    // In real WASM, this would call the actual WebGL function
}

fn webglEnable(cap: u32) void {
    _ = cap;
    // In real WASM, this would call the actual WebGL function
}

// Animation frame callback
fn requestAnimationFrame(callback: fn() void) void {
    _ = callback;
    // In real WASM, this would call the browser's requestAnimationFrame
}

// Main render function
fn render(current_time: f64) void {
    if (!is_running) return;

    const delta_time = current_time - last_time;
    rotation += @as(f32, @floatCast(delta_time)) * 0.001;
    last_time = current_time;

    // Clear
    webglClearColor(0.1, 0.1, 0.2, 1.0);
    webglClear(0x00004000 | 0x00000100); // COLOR_BUFFER_BIT | DEPTH_BUFFER_BIT

    // Use program (assuming program 1 is our shader program)
    webglUseProgram(1);

    // Set up matrices
    const model_view_matrix = createModelViewMatrix(rotation);
    const projection_matrix = createProjectionMatrix();

    // Set uniforms (assuming locations 0 and 1)
    webglUniformMatrix4fv(0, false, model_view_matrix);
    webglUniformMatrix4fv(1, false, projection_matrix);

    // Draw
    webglDrawElements(0x0004, 36, 0x1403, 0); // TRIANGLES, 36 indices, UNSIGNED_SHORT, 0 offset

    // Continue animation
    if (is_running) {
        requestAnimationFrame(render);
    }
}

// Exported functions for JavaScript
export fn initialize_spinning_cube_demo() i32 {
    allocator = std.heap.page_allocator;
    
    // Set up viewport
    webglViewport(0, 0, @as(i32, @intCast(canvas_width)), @as(i32, @intCast(canvas_height)));
    webglEnable(0x0B71); // DEPTH_TEST
    
    // Initialize time
    last_time = 0.0;
    rotation = 0.0;
    is_running = false;
    
    return 0; // Success
}

export fn start_spinning_cube_demo() void {
    is_running = true;
    last_time = 0.0;
    requestAnimationFrame(render);
}

export fn pause_spinning_cube_demo() void {
    is_running = false;
}

export fn reset_spinning_cube_demo() void {
    rotation = 0.0;
    last_time = 0.0;
    is_running = false;
}

export fn web_resize(width: u32, height: u32) void {
    canvas_width = width;
    canvas_height = height;
    webglViewport(0, 0, @as(i32, @intCast(width)), @as(i32, @intCast(height)));
}

// Memory management
export fn malloc(size: usize) ?[*]u8 {
    return allocator.alloc(u8, size) catch null;
}

export fn free(ptr: [*]u8) void {
    allocator.free(ptr);
}

// Main function (not used in WASM but required)
pub fn main() !void {
    _ = try initialize_spinning_cube_demo();
}