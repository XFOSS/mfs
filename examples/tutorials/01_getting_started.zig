//! MFS Engine: Getting Started Tutorial
//!
//! This tutorial introduces the basics of using the MFS Engine.
//! It creates a simple window and renders a colored triangle.

const std = @import("std");
const mfs = @import("mfs");
const math = @import("zmath");

// Simple vertex representation
const Vertex = struct {
    position: [3]f32,
    color: [4]f32,
};

pub fn main() !void {
    // Initialize standard allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize the engine with default configuration
    var engine = try mfs.Engine.init(.{
        .allocator = allocator,
        .window_title = "MFS Getting Started",
        .window_width = 800,
        .window_height = 600,
        .renderer_backend = .auto, // Automatically choose the best backend
    });
    defer engine.deinit();
    
    // Create a simple triangle mesh
    const vertices = [_]Vertex{
        // Position                  Color (RGBA)
        .{ .position = .{ 0.0, 0.5, 0.0 }, .color = .{ 1.0, 0.0, 0.0, 1.0 } },  // Top (Red)
        .{ .position = .{ -0.5, -0.5, 0.0 }, .color = .{ 0.0, 1.0, 0.0, 1.0 } }, // Bottom-left (Green)
        .{ .position = .{ 0.5, -0.5, 0.0 }, .color = .{ 0.0, 0.0, 1.0, 1.0 } },  // Bottom-right (Blue)
    };
    
    // Create a vertex buffer
    const vertex_buffer = try engine.createVertexBuffer(.{
        .data = &vertices,
        .size = @sizeOf(@TypeOf(vertices)),
    });
    defer engine.destroyBuffer(vertex_buffer);
    
    // Create a simple shader
    const shader = try engine.createShader(.{
        .vertex = @embedFile("shaders/basic.vert"),
        .fragment = @embedFile("shaders/basic.frag"),
    });
    defer engine.destroyShader(shader);
    
    // Create a material using our shader
    const material = try engine.createMaterial(.{
        .shader = shader,
    });
    defer engine.destroyMaterial(material);

    // Main game loop
    while (!engine.shouldClose()) {
        try engine.beginFrame();
        
        // Clear the screen to a dark gray color
        engine.clearScreen(.{ 0.2, 0.2, 0.2, 1.0 });
        
        // Bind our material
        engine.bindMaterial(material);
        
        // Draw our triangle
        try engine.draw(.{
            .vertex_buffer = vertex_buffer,
            .vertex_count = 3,
        });
        
        try engine.endFrame();
        
        // Handle basic window events
        try engine.pollEvents();
    }
}

// This tutorial also requires two shader files:
// 
// shaders/basic.vert:
// ```
// #version 330 core
// layout (location = 0) in vec3 aPos;
// layout (location = 1) in vec4 aColor;
//
// out vec4 vertexColor;
//
// void main() {
//     gl_Position = vec4(aPos, 1.0);
//     vertexColor = aColor;
// }
// ```
//
// shaders/basic.frag:
// ```
// #version 330 core
// in vec4 vertexColor;
// out vec4 FragColor;
//
// void main() {
//     FragColor = vertexColor;
// }
// ```