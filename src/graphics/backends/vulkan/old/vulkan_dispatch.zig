const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vk.zig");

pub const DispatchError = error{
    LibraryLoadFailed,
    SymbolNotFound,
};

pub const Dispatch = struct {
    // Nested function pointer type declarations
    pub const GetInstanceFn = fn (vk.VkInstance, [*:0]const u8) ?*const fn () callconv(.C) void;
    pub const GetDeviceFn = fn (vk.VkDevice, [*:0]const u8) ?*const fn () callconv(.C) void;
    pub const EnumeratePhysicalDevicesFn = fn (vk.VkInstance, *u32, ?*vk.VkPhysicalDevice) callconv(.C) vk.VkResult;
    pub const CreateDeviceFn = fn (vk.VkPhysicalDevice, *const vk.VkDeviceCreateInfo, ?*const vk.VkAllocationCallbacks, *vk.VkDevice) callconv(.C) vk.VkResult;
    pub const DestroySurfaceKHRFn = fn (vk.VkInstance, vk.VkSurfaceKHR, ?*const vk.VkAllocationCallbacks) callconv(.C) void;
    pub const GetDeviceQueueFn = fn (vk.VkDevice, u32, u32, *vk.VkQueue) callconv(.C) void;

    // Fields for function pointers
    vkGetInstanceProcAddr: GetInstanceFn,
    vkGetDeviceProcAddr: GetDeviceFn,
    vkCreateInstance: fn (*const vk.VkInstanceCreateInfo, ?*const vk.VkAllocationCallbacks, *vk.VkInstance) vk.VkResult,
    vkDestroyInstance: fn (vk.VkInstance, ?*const vk.VkAllocationCallbacks) void,
    vkEnumeratePhysicalDevices: EnumeratePhysicalDevicesFn,
    vkCreateDevice: CreateDeviceFn,
    vkDestroySurfaceKHR: DestroySurfaceKHRFn,
    vkGetDeviceQueue: GetDeviceQueueFn,

    /// Initializes the dispatch table by dynamically loading the Vulkan loader.
    pub fn init(allocator: std.mem.Allocator) !*Dispatch {
        const lib_name = switch (builtin.os.tag) {
            .windows => "vulkan-1.dll",
            .linux => "libvulkan.so.1",
            .darwin => "libvulkan.1.dylib",
            else => return DispatchError.LibraryLoadFailed,
        };
        var lib = try std.DynLib.open(lib_name);
        const disp = try allocator.create(Dispatch);

        disp.vkGetInstanceProcAddr = @as(GetInstanceFn, @ptrCast(lib.lookup("vkGetInstanceProcAddr") orelse return DispatchError.SymbolNotFound));
        disp.vkGetDeviceProcAddr = @as(GetDeviceFn, @ptrCast(lib.lookup("vkGetDeviceProcAddr") orelse return DispatchError.SymbolNotFound));

        // Load a couple of essential functions
        disp.vkCreateInstance = @as(@TypeOf(disp.vkCreateInstance), @ptrCast(disp.vkGetInstanceProcAddr(null, "vkCreateInstance") orelse return DispatchError.SymbolNotFound));
        disp.vkDestroyInstance = @as(@TypeOf(disp.vkDestroyInstance), @ptrCast(disp.vkGetInstanceProcAddr(null, "vkDestroyInstance") orelse return DispatchError.SymbolNotFound));

        return disp;
    }

    /// Load instance-level functions after vkCreateInstance
    pub fn loadInstance(self: *Dispatch, instance: vk.VkInstance) !void {
        // Load EnumeratePhysicalDevices
        self.vkEnumeratePhysicalDevices = @as(EnumeratePhysicalDevicesFn, @ptrCast(self.vkGetInstanceProcAddr(instance, "vkEnumeratePhysicalDevices") orelse return DispatchError.SymbolNotFound));
        // Load CreateDevice
        self.vkCreateDevice = @as(CreateDeviceFn, @ptrCast(self.vkGetInstanceProcAddr(instance, "vkCreateDevice") orelse return DispatchError.SymbolNotFound));
        // Load DestroySurfaceKHR
        self.vkDestroySurfaceKHR = @as(DestroySurfaceKHRFn, @ptrCast(self.vkGetInstanceProcAddr(instance, "vkDestroySurfaceKHR") orelse return DispatchError.SymbolNotFound));
    }

    /// Load device-level functions after vkCreateDevice
    pub fn loadDevice(self: *Dispatch, device: vk.VkDevice) !void {
        // Load GetDeviceQueue
        self.vkGetDeviceQueue = @as(GetDeviceQueueFn, @ptrCast(self.vkGetDeviceProcAddr(device, "vkGetDeviceQueue") orelse return DispatchError.SymbolNotFound));
    }
};
