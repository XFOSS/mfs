const std = @import("std");
const interface = @import("../interface.zig");
const errors = @import("errors.zig");

/// Supported shader languages
pub const ShaderLanguage = enum {
    GLSL,
    HLSL,
    SPIRV,
    WGSL,
};

/// Compile shader source code to binary representation
/// Note: Actual compilation requires external tools; here we provide stubs.
pub fn compileShader(
    lang: ShaderLanguage,
    source: []const u8,
) interface.GraphicsBackendError![]u8 {
    return switch (lang) {
        .SPIRV, .WGSL => source,
        .GLSL, .HLSL => return interface.GraphicsBackendError.UnsupportedFormat,
    };
}

/// Load shader from file and compile
pub fn loadAndCompileShaderFile(
    allocator: std.mem.Allocator,
    lang: ShaderLanguage,
    path: []const u8,
) interface.GraphicsBackendError![]u8 {
    const file = try std.fs.cwd().openFile(path, .{ .read = true });
    defer file.close();
    const size = try file.getEndPos();
    const buffer = try allocator.alloc(u8, size);
    defer allocator.free(buffer);
    _ = try file.readAll(buffer);
    return compileShader(lang, buffer);
}
