const std = @import("std");
const Thread = std.Thread;
const Mutex = std.Thread.Mutex;
const Condition = std.Thread.Condition;
const Allocator = std.mem.Allocator;

// Vulkan API Constants
const VK_SUCCESS = 0;
const VK_ERROR_INITIALIZATION_FAILED = -3;
const VK_API_VERSION_1_0 = (1 << 22) | (0 << 12) | 0;
const VK_STRUCTURE_TYPE_APPLICATION_INFO = 0;
const VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO = 1;
const VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO = 2;
const VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO = 3;
const VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO = 39;
const VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO = 40;
const VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT = 0x00000002;
const VK_COMMAND_BUFFER_LEVEL_PRIMARY = 0;

// Vulkan Types
const VkResult = i32;
