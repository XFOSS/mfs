const std = @import("std");

// Vulkan configuration and availability detection
pub const VulkanConfig = struct {
    available: bool = false,
    sdk_path: ?[]const u8 = null,
    version: ?[]const u8 = null,
    validation_enabled: bool = false,
};

// Check if Vulkan SDK is properly installed and available
pub fn detectVulkanAvailability(allocator: std.mem.Allocator) VulkanConfig {
    var config = VulkanConfig{};

    // Check for VULKAN_SDK environment variable
    if (std.process.getEnvVarOwned(allocator, "VULKAN_SDK")) |sdk_path| {
        defer allocator.free(sdk_path);

        // Check if required directories exist
        const include_path = std.fs.path.join(allocator, &[_][]const u8{ sdk_path, "Include" }) catch return config;
        defer allocator.free(include_path);

        const lib_path = std.fs.path.join(allocator, &[_][]const u8{ sdk_path, "Lib" }) catch return config;
        defer allocator.free(lib_path);

        // Try to open directories to verify they exist
        const include_dir = std.fs.openDirAbsolute(include_path, .{}) catch null;
        const lib_dir = std.fs.openDirAbsolute(lib_path, .{}) catch null;

        if (include_dir != null and lib_dir != null) {
            config.available = true;
            config.sdk_path = allocator.dupe(u8, sdk_path) catch null;

            if (include_dir) |dir| dir.close();
            if (lib_dir) |dir| dir.close();
        } else {
            if (include_dir) |dir| dir.close();
            if (lib_dir) |dir| dir.close();
        }
    } else |_| {
        // VULKAN_SDK not set
    }

    return config;
}

// Check if Vulkan runtime is available (for runtime detection)
pub fn isVulkanRuntimeAvailable() bool {
    // Try to load vulkan-1.dll on Windows
    const vulkan_lib = std.DynLib.open("vulkan-1.dll") catch return false;
    defer vulkan_lib.close();

    // Try to get vkEnumerateInstanceVersion function
    const vkEnumerateInstanceVersion = vulkan_lib.lookup(*const fn (*u32) callconv(.C) i32, "vkEnumerateInstanceVersion") orelse return false;

    var version: u32 = 0;
    const result = vkEnumerateInstanceVersion(&version);

    // VK_SUCCESS = 0
    return result == 0;
}

// Get Vulkan version if available
pub fn getVulkanVersion(allocator: std.mem.Allocator) ?[]const u8 {
    if (!isVulkanRuntimeAvailable()) return null;

    const vulkan_lib = std.DynLib.open("vulkan-1.dll") catch return null;
    defer vulkan_lib.close();

    const vkEnumerateInstanceVersion = vulkan_lib.lookup(*const fn (*u32) callconv(.C) i32, "vkEnumerateInstanceVersion") orelse return null;

    var version: u32 = 0;
    const result = vkEnumerateInstanceVersion(&version);

    if (result != 0) return null;

    const major = (version >> 22) & 0x3FF;
    const minor = (version >> 12) & 0x3FF;
    const patch = version & 0xFFF;

    return std.fmt.allocPrint(allocator, "{}.{}.{}", .{ major, minor, patch }) catch null;
}

// Compile-time Vulkan availability (based on build configuration)
pub const VULKAN_AVAILABLE = @import("builtin").target.os.tag == .windows;
