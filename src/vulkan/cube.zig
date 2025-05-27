const std = @import("std");
const math = std.math;
const Allocator = std.mem.Allocator;
const vk = @import("vulkan_c.zig");
const material = @import("material.zig");

// Re-export Vulkan types for convenience
const VkResult = vk.VkResult;
const VkInstance = vk.VkInstance;
const VkDevice = vk.VkDevice;
const VkPhysicalDevice = vk.VkPhysicalDevice;
const VkQueue = vk.VkQueue;
const VkCommandPool = vk.VkCommandPool;
const VkCommandBuffer = vk.VkCommandBuffer;
const VkRenderPass = vk.VkRenderPass;
const VkFramebuffer = vk.VkFramebuffer;
const VkPipeline = vk.VkPipeline;
const VkPipelineLayout = vk.VkPipelineLayout;
const VkBuffer = vk.VkBuffer;
const VkDeviceMemory = vk.VkDeviceMemory;
const VkImage = vk.VkImage;
const VkImageView = vk.VkImageView;
const VkSwapchainKHR = vk.VkSwapchainKHR;
const VkSurfaceKHR = vk.VkSurfaceKHR;
const VkSemaphore = vk.VkSemaphore;
const VkFence = vk.VkFence;
const VkDescriptorSetLayout = vk.VkDescriptorSetLayout;
const VkDescriptorPool = vk.VkDescriptorPool;
const VkDescriptorSet = vk.VkDescriptorSet;

// Math utilities
const Vec3 = struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn new(x: f32, y: f32, z: f32) Vec3 {
        return Vec3{ .x = x, .y = y, .z = z };
    }
};

const Vec4 = struct {
    x: f32,
    y: f32,
    z: f32,
    w: f32,

    pub fn new(x: f32, y: f32, z: f32, w: f32) Vec4 {
        return Vec4{ .x = x, .y = y, .z = z, .w = w };
    }
};

const Mat4 = struct {
    data: [16]f32,

    pub fn identity() Mat4 {
        return Mat4{
            .data = [_]f32{
                1.0, 0.0, 0.0, 0.0,
                0.0, 1.0, 0.0, 0.0,
                0.0, 0.0, 1.0, 0.0,
                0.0, 0.0, 0.0, 1.0,
            },
        };
    }

    pub fn perspective(fov: f32, aspect: f32, near: f32, far: f32) Mat4 {
        const f = 1.0 / math.tan(fov * 0.5);
        var result = Mat4{ .data = [_]f32{0.0} ** 16 };

        result.data[0] = f / aspect;
        result.data[5] = f;
        result.data[10] = (far + near) / (near - far);
        result.data[11] = -1.0;
        result.data[14] = (2.0 * far * near) / (near - far);

        return result;
    }

    pub fn rotateY(angle: f32) Mat4 {
        const c = math.cos(angle);
        const s = math.sin(angle);

        return Mat4{
            .data = [_]f32{
                c,   0.0, s,   0.0,
                0.0, 1.0, 0.0, 0.0,
                -s,  0.0, c,   0.0,
                0.0, 0.0, 0.0, 1.0,
            },
        };
    }

    pub fn multiply(a: Mat4, b: Mat4) Mat4 {
        var result = Mat4{ .data = [_]f32{0.0} ** 16 };

        for (0..4) |row| {
            for (0..4) |col| {
                var sum: f32 = 0.0;
                for (0..4) |k| {
                    sum += a.data[row * 4 + k] * b.data[k * 4 + col];
                }
                result.data[row * 4 + col] = sum;
            }
        }

        return result;
    }
};

// Vertex structure
const Vertex = struct {
    position: Vec3,
    color: Vec3,

    pub fn new(pos: Vec3, col: Vec3) Vertex {
        return Vertex{ .position = pos, .color = col };
    }
};

// Uniform buffer object
const UniformBufferObject = struct {
    model: Mat4,
    view: Mat4,
    proj: Mat4,
};

// Cube vertices (8 vertices of a cube with colors)
const cube_vertices = [_]Vertex{
    // Front face (red)
    Vertex.new(Vec3.new(-0.5, -0.5, 0.5), Vec3.new(1.0, 0.0, 0.0)),
    Vertex.new(Vec3.new(0.5, -0.5, 0.5), Vec3.new(1.0, 0.0, 0.0)),
    Vertex.new(Vec3.new(0.5, 0.5, 0.5), Vec3.new(1.0, 0.0, 0.0)),
    Vertex.new(Vec3.new(-0.5, 0.5, 0.5), Vec3.new(1.0, 0.0, 0.0)),

    // Back face (green)
    Vertex.new(Vec3.new(-0.5, -0.5, -0.5), Vec3.new(0.0, 1.0, 0.0)),
    Vertex.new(Vec3.new(0.5, -0.5, -0.5), Vec3.new(0.0, 1.0, 0.0)),
    Vertex.new(Vec3.new(0.5, 0.5, -0.5), Vec3.new(0.0, 1.0, 0.0)),
    Vertex.new(Vec3.new(-0.5, 0.5, -0.5), Vec3.new(0.0, 1.0, 0.0)),
};

// Cube indices (12 triangles = 36 indices)
const cube_indices = [_]u16{
    // Front face
    0, 1, 2, 2, 3, 0,
    // Back face
    4, 6, 5, 6, 4, 7,
    // Left face
    4, 0, 3, 3, 7, 4,
    // Right face
    1, 5, 6, 6, 2, 1,
    // Top face
    3, 2, 6, 6, 7, 3,
    // Bottom face
    4, 5, 1, 1, 0, 4,
};

// Vulkan renderer
pub const VulkanCubeRenderer = struct {
    allocator: Allocator,
    instance: ?VkInstance,
    device: ?VkDevice,
    physical_device: ?VkPhysicalDevice,
    graphics_queue: ?VkQueue,
    surface: ?VkSurfaceKHR,
    command_pool: ?VkCommandPool,
    command_buffer: ?VkCommandBuffer,
    vertex_buffer: ?VkBuffer,
    vertex_buffer_memory: ?VkDeviceMemory,
    index_buffer: ?VkBuffer,
    index_buffer_memory: ?VkDeviceMemory,
    uniform_buffer: ?VkBuffer,
    uniform_buffer_memory: ?VkDeviceMemory,
    pipeline: ?VkPipeline,
    pipeline_layout: ?VkPipelineLayout,
    render_pass: ?VkRenderPass,
    swapchain: ?VkSwapchainKHR,
    swapchain_images: []VkImage,
    swapchain_image_views: []VkImageView,
    framebuffers: []VkFramebuffer,
    width: u32,
    height: u32,
    current_frame: u32,
    rotation_angle: f32,
    hwnd: ?*anyopaque,
    hinstance: ?*anyopaque,
    material_manager: material.MaterialManager,

    image_available_semaphores: [vk.MAX_FRAMES_IN_FLIGHT]VkSemaphore,
    render_finished_semaphores: [vk.MAX_FRAMES_IN_FLIGHT]VkSemaphore,
    frame_fences: [vk.MAX_FRAMES_IN_FLIGHT]VkFence,
    current_material_id: u32,

    const Self = @This();

    pub fn init(allocator: Allocator, width: u32, height: u32, hwnd: *anyopaque, hinstance: *anyopaque) !Self {
        return Self{
            .allocator = allocator,
            .instance = null,
            .device = null,
            .physical_device = null,
            .graphics_queue = null,
            .surface = null,
            .command_pool = null,
            .command_buffer = null,
            .vertex_buffer = null,
            .vertex_buffer_memory = null,
            .index_buffer = null,
            .index_buffer_memory = null,
            .uniform_buffer = null,
            .uniform_buffer_memory = null,
            .pipeline = null,
            .pipeline_layout = null,
            .render_pass = null,
            .swapchain = null,
            .swapchain_images = undefined,
            .swapchain_image_views = undefined,
            .framebuffers = undefined,
            .image_available_semaphores = undefined,
            .render_finished_semaphores = undefined,
            .frame_fences = undefined,
            .width = width,
            .height = height,
            .current_frame = 0,
            .rotation_angle = 0.0,
            .hwnd = hwnd,
            .hinstance = hinstance,
            .material_manager = material.MaterialManager.init(allocator),
            .current_material_id = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        // Cleanup material system
        if (self.device) |device| {
            self.material_manager.deinit(device);
        }

        // Cleanup Vulkan resources
        self.cleanupSwapchain();

        if (self.uniform_buffer_memory) |memory| {
            _ = memory;
            // vkFreeMemory(self.device, memory, null);
        }
        if (self.uniform_buffer) |buffer| {
            _ = buffer;
            // vkDestroyBuffer(self.device, buffer, null);
        }

        if (self.index_buffer_memory) |memory| {
            _ = memory;
            // vkFreeMemory(self.device, memory, null);
        }
        if (self.index_buffer) |buffer| {
            _ = buffer;
            // vkDestroyBuffer(self.device, buffer, null);
        }

        if (self.vertex_buffer_memory) |memory| {
            _ = memory;
            // vkFreeMemory(self.device, memory, null);
        }
        if (self.vertex_buffer) |buffer| {
            _ = buffer;
            // vkDestroyBuffer(self.device, buffer, null);
        }

        if (self.command_pool) |pool| {
            _ = pool;
            // vkDestroyCommandPool(self.device, pool, null);
        }

        if (self.device) |device| {
            _ = device;
            // vkDestroyDevice(device, null);
        }

        if (self.instance) |instance| {
            _ = instance;
            // vkDestroyInstance(instance, null);
        }
    }

    pub fn initVulkan(self: *Self) !void {
        try self.createInstance();
        try self.createSurface();
        try self.pickPhysicalDevice();
        try self.createLogicalDevice();
        try self.createCommandPool();
        try self.createVertexBuffer();
        try self.createIndexBuffer();
        try self.createUniformBuffer();
        try self.createRenderPass();
        try self.createGraphicsPipeline();
        try self.createSwapchain();
        try self.createFramebuffers();
        try self.createCommandBuffer();
        try self.initMaterials();
    }

    fn createInstance(self: *Self) !void {
        std.debug.print("Creating Vulkan instance...\n", .{});

        const app_info = vk.VkApplicationInfo{
            .sType = vk.VK_STRUCTURE_TYPE_APPLICATION_INFO,
            .pNext = null,
            .pApplicationName = "Zig Vulkan Cube",
            .applicationVersion = vk.c.VK_MAKE_VERSION(1, 0, 0),
            .pEngineName = "Zig Engine",
            .engineVersion = vk.c.VK_MAKE_VERSION(1, 0, 0),
            .apiVersion = vk.c.VK_API_VERSION_1_0,
        };

        const extensions = [_][*:0]const u8{
            vk.VK_KHR_SURFACE_EXTENSION_NAME,
            vk.VK_KHR_WIN32_SURFACE_EXTENSION_NAME,
        };

        const create_info = vk.VkInstanceCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .pApplicationInfo = &app_info,
            .enabledLayerCount = 0,
            .ppEnabledLayerNames = null,
            .enabledExtensionCount = extensions.len,
            .ppEnabledExtensionNames = &extensions[0],
        };

        const result = vk.vkCreateInstance(&create_info, null, &self.instance);
        if (result != vk.VK_SUCCESS) {
            std.debug.print("Failed to create Vulkan instance: {}\n", .{result});
            return error.InstanceCreationFailed;
        }
    }

    fn createSurface(self: *Self) !void {
        std.debug.print("Creating window surface...\n", .{});

        if (self.instance == null or self.hwnd == null or self.hinstance == null) {
            return error.MissingParameters;
        }

        const create_info = vk.VkWin32SurfaceCreateInfoKHR{
            .sType = vk.VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR,
            .pNext = null,
            .flags = 0,
            .hinstance = @ptrCast(self.hinstance.?),
            .hwnd = @ptrCast(self.hwnd.?),
        };

        const result = vk.vkCreateWin32SurfaceKHR(self.instance.?, &create_info, null, &self.surface);
        if (result != vk.VK_SUCCESS) {
            std.debug.print("Failed to create Win32 surface: {}\n", .{result});
            return error.SurfaceCreationFailed;
        }
    }

    fn pickPhysicalDevice(self: *Self) !void {
        std.debug.print("Picking physical device...\n", .{});

        if (self.instance == null) {
            return error.InstanceNotCreated;
        }

        var device_count: u32 = 0;
        _ = vk.vkEnumeratePhysicalDevices(self.instance.?, &device_count, null);

        if (device_count == 0) {
            return error.NoSuitableDevice;
        }

        const devices = try self.allocator.alloc(vk.VkPhysicalDevice, device_count);
        defer self.allocator.free(devices);

        _ = vk.vkEnumeratePhysicalDevices(self.instance.?, &device_count, devices.ptr);

        // For simplicity, just pick the first device
        self.physical_device = devices[0];

        var properties: vk.VkPhysicalDeviceProperties = undefined;
        vk.vkGetPhysicalDeviceProperties(self.physical_device.?, &properties);
        std.debug.print("Selected GPU: {s}\n", .{properties.deviceName});
    }

    fn createLogicalDevice(self: *Self) !void {
        std.debug.print("Creating logical device...\n", .{});

        if (self.physical_device == null) {
            return error.PhysicalDeviceNotSelected;
        }

        const queue_priority: f32 = 1.0;
        const queue_create_info = vk.VkDeviceQueueCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .queueFamilyIndex = 0, // Assume graphics queue family is 0
            .queueCount = 1,
            .pQueuePriorities = &queue_priority,
        };

        const device_extensions = [_][*:0]const u8{
            vk.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
        };

        var device_features: vk.c.VkPhysicalDeviceFeatures = std.mem.zeroes(vk.c.VkPhysicalDeviceFeatures);

        const create_info = vk.VkDeviceCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .queueCreateInfoCount = 1,
            .pQueueCreateInfos = &queue_create_info,
            .pEnabledFeatures = &device_features,
            .enabledExtensionCount = device_extensions.len,
            .ppEnabledExtensionNames = &device_extensions[0],
            .enabledLayerCount = 0,
            .ppEnabledLayerNames = null,
        };

        const result = vk.vkCreateDevice(self.physical_device.?, &create_info, null, &self.device);
        if (result != vk.VK_SUCCESS) {
            std.debug.print("Failed to create logical device: {}\n", .{result});
            return error.DeviceCreationFailed;
        }

        vk.vkGetDeviceQueue(self.device.?, 0, 0, &self.graphics_queue);
    }

    fn createCommandPool(self: *Self) !void {
        std.debug.print("Creating command pool...\n", .{});

        const pool_info = vk.c.VkCommandPoolCreateInfo{
            .sType = vk.c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .pNext = null,
            .flags = vk.c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
            .queueFamilyIndex = 0,
        };

        const result = vk.c.vkCreateCommandPool(self.device.?, &pool_info, null, &self.command_pool);
        if (result != vk.VK_SUCCESS) {
            std.debug.print("Failed to create command pool: {}\n", .{result});
            return error.CommandPoolCreationFailed;
        }
    }

    fn createVertexBuffer(self: *Self) !void {
        std.debug.print("Creating vertex buffer...\n", .{});

        const buffer_size = @sizeOf(Vertex) * cube_vertices.len;

        // Create staging buffer
        const staging_buffer_info = vk.c.VkBufferCreateInfo{
            .sType = vk.c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .size = buffer_size,
            .usage = vk.c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            .sharingMode = vk.c.VK_SHARING_MODE_EXCLUSIVE,
            .queueFamilyIndexCount = 0,
            .pQueueFamilyIndices = null,
        };

        var staging_buffer: vk.VkBuffer = undefined;
        const staging_create_result = vk.c.vkCreateBuffer(self.device.?, &staging_buffer_info, null, &staging_buffer);
        if (staging_create_result != vk.VK_SUCCESS) {
            std.debug.print("vkCreateBuffer failed: {}\n", .{staging_create_result});
            return error.BufferCreationFailed;
        }

        // Get memory requirements
        var mem_requirements: vk.c.VkMemoryRequirements = undefined;
        vk.c.vkGetBufferMemoryRequirements(self.device.?, staging_buffer, &mem_requirements);

        // Allocate staging memory
        const staging_alloc_info = vk.c.VkMemoryAllocateInfo{
            .sType = vk.c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            .pNext = null,
            .allocationSize = mem_requirements.size,
            .memoryTypeIndex = try self.findMemoryType(mem_requirements.memoryTypeBits, vk.c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT),
        };

        var staging_memory: vk.VkDeviceMemory = undefined;
        const staging_alloc_result = vk.c.vkAllocateMemory(self.device.?, &staging_alloc_info, null, &staging_memory);
        if (staging_alloc_result != vk.VK_SUCCESS) {
            std.debug.print("vkAllocateMemory failed: {}\n", .{staging_alloc_result});
            return error.MemoryAllocationFailed;
        }

        // Map memory and copy data
        var data: ?*anyopaque = undefined;
        const map_result = vk.c.vkMapMemory(self.device.?, staging_memory, 0, buffer_size, 0, &data);
        if (map_result != vk.VK_SUCCESS) {
            std.debug.print("vkMapMemory failed: {}\n", .{map_result});
            return error.MemoryMappingFailed;
        }
        @memcpy(@as([*]u8, @ptrCast(data))[0..buffer_size], std.mem.asBytes(&cube_vertices));
        vk.c.vkUnmapMemory(self.device.?, staging_memory);

        // Create vertex buffer
        const vertex_buffer_info = vk.c.VkBufferCreateInfo{
            .sType = vk.c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .size = buffer_size,
            .usage = vk.c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | vk.c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
            .sharingMode = vk.c.VK_SHARING_MODE_EXCLUSIVE,
            .queueFamilyIndexCount = 0,
            .pQueueFamilyIndices = null,
        };

        var vertex_buffer: vk.VkBuffer = undefined;
        const vertex_create_result = vk.c.vkCreateBuffer(self.device.?, &vertex_buffer_info, null, &vertex_buffer);
        self.vertex_buffer = vertex_buffer;
        if (vertex_create_result != vk.VK_SUCCESS) {
            std.debug.print("vkCreateBuffer failed: {}\n", .{vertex_create_result});
            return error.BufferCreationFailed;
        }

        // Get memory requirements for vertex buffer
        vk.c.vkGetBufferMemoryRequirements(self.device.?, self.vertex_buffer.?, &mem_requirements);

        // Allocate device memory
        const alloc_info = vk.c.VkMemoryAllocateInfo{
            .sType = vk.c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            .pNext = null,
            .allocationSize = mem_requirements.size,
            .memoryTypeIndex = try self.findMemoryType(mem_requirements.memoryTypeBits, vk.c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT),
        };

        var temp_vertex_memory: vk.VkDeviceMemory = undefined;
        const vertex_alloc_result = vk.c.vkAllocateMemory(self.device.?, &alloc_info, null, &temp_vertex_memory);
        self.vertex_buffer_memory = temp_vertex_memory;
        if (vertex_alloc_result != vk.VK_SUCCESS) {
            std.debug.print("vkAllocateMemory failed: {}\n", .{vertex_alloc_result});
            return error.MemoryAllocationFailed;
        }
        const vertex_bind_result = vk.c.vkBindBufferMemory(self.device.?, self.vertex_buffer.?, self.vertex_buffer_memory.?, 0);
        if (vertex_bind_result != vk.VK_SUCCESS) {
            std.debug.print("vkBindBufferMemory failed: {}\n", .{vertex_bind_result});
            return error.BufferBindingFailed;
        }

        // Copy from staging to vertex buffer
        try self.copyBuffer(staging_buffer, self.vertex_buffer.?, buffer_size);

        // Cleanup staging buffer
        vk.c.vkDestroyBuffer(self.device.?, staging_buffer, null);
        vk.c.vkFreeMemory(self.device.?, staging_memory, null);
    }

    fn createIndexBuffer(self: *Self) !void {
        std.debug.print("Creating index buffer...\n", .{});

        const buffer_size = @sizeOf(u16) * cube_indices.len;

        // Create staging buffer
        const staging_buffer_info = vk.VkBufferCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .size = buffer_size,
            .usage = vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
            .queueFamilyIndexCount = 0,
            .pQueueFamilyIndices = null,
        };

        var staging_buffer: vk.VkBuffer = undefined;
        const staging_create_result2 = vk.vkCreateBuffer(self.device.?, &staging_buffer_info, null, &staging_buffer);
        if (staging_create_result2 != vk.VkResult.VK_SUCCESS) {
            std.debug.print("vkCreateBuffer failed: {}\n", .{staging_create_result2});
            return error.BufferCreationFailed;
        }

        // Get memory requirements
        var mem_requirements: vk.VkMemoryRequirements = undefined;
        vk.vkGetBufferMemoryRequirements(self.device.?, staging_buffer, &mem_requirements);

        // Allocate staging memory
        const staging_alloc_info = vk.VkMemoryAllocateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            .pNext = null,
            .allocationSize = mem_requirements.size,
            .memoryTypeIndex = try self.findMemoryType(mem_requirements.memoryTypeBits, vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT),
        };

        var staging_memory: vk.VkDeviceMemory = undefined;
        const staging_alloc_result2 = vk.vkAllocateMemory(self.device.?, &staging_alloc_info, null, &staging_memory);
        if (staging_alloc_result2 != vk.VkResult.VK_SUCCESS) {
            std.debug.print("vkAllocateMemory failed: {}\n", .{staging_alloc_result2});
            return error.MemoryAllocationFailed;
        }

        // Map memory and copy data
        var data: ?*anyopaque = undefined;
        const map_result2 = vk.vkMapMemory(self.device.?, staging_memory, 0, buffer_size, 0, &data);
        if (map_result2 != vk.VkResult.VK_SUCCESS) {
            std.debug.print("vkMapMemory failed: {}\n", .{map_result2});
            return error.MemoryMappingFailed;
        }
        @memcpy(@as([*]u8, @ptrCast(data))[0..buffer_size], std.mem.asBytes(&cube_indices));
        vk.vkUnmapMemory(self.device.?, staging_memory);

        // Create index buffer
        const index_buffer_info = vk.VkBufferCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .size = buffer_size,
            .usage = vk.VK_BUFFER_USAGE_TRANSFER_DST_BIT | vk.VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
            .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
            .queueFamilyIndexCount = 0,
            .pQueueFamilyIndices = null,
        };

        var temp_index_buffer: vk.VkBuffer = undefined;
        const index_create_result = vk.vkCreateBuffer(self.device.?, &index_buffer_info, null, &temp_index_buffer);
        self.index_buffer = temp_index_buffer;
        if (index_create_result != vk.VkResult.VK_SUCCESS) {
            std.debug.print("vkCreateBuffer failed: {}\n", .{index_create_result});
            return error.BufferCreationFailed;
        }

        // Get memory requirements for index buffer
        vk.vkGetBufferMemoryRequirements(self.device.?, self.index_buffer.?, &mem_requirements);

        // Allocate device memory
        const alloc_info = vk.VkMemoryAllocateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            .pNext = null,
            .allocationSize = mem_requirements.size,
            .memoryTypeIndex = try self.findMemoryType(mem_requirements.memoryTypeBits, vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT),
        };

        var temp_index_memory: vk.VkDeviceMemory = undefined;
        const index_alloc_result = vk.vkAllocateMemory(self.device.?, &alloc_info, null, &temp_index_memory);
        self.index_buffer_memory = temp_index_memory;
        if (index_alloc_result != vk.VkResult.VK_SUCCESS) {
            std.debug.print("vkAllocateMemory failed: {}\n", .{index_alloc_result});
            return error.MemoryAllocationFailed;
        }
        const index_bind_result = vk.vkBindBufferMemory(self.device.?, self.index_buffer.?, self.index_buffer_memory.?, 0);
        if (index_bind_result != vk.VkResult.VK_SUCCESS) {
            std.debug.print("vkBindBufferMemory failed: {}\n", .{index_bind_result});
            return error.BufferBindingFailed;
        }

        // Copy from staging to index buffer
        try self.copyBuffer(staging_buffer, self.index_buffer.?, buffer_size);

        // Cleanup staging buffer
        vk.vkDestroyBuffer(self.device.?, staging_buffer, null);
        vk.vkFreeMemory(self.device.?, staging_memory, null);
    }

    fn findMemoryType(self: *Self, type_filter: u32, properties: u32) !u32 {
        var memory_properties: vk.c.VkPhysicalDeviceMemoryProperties = undefined;
        vk.c.vkGetPhysicalDeviceMemoryProperties(self.physical_device.?, &memory_properties);

        var i: u32 = 0;
        while (i < memory_properties.memoryTypeCount) : (i += 1) {
            if (type_filter & (@as(u32, 1) << @intCast(i)) != 0 and
                (memory_properties.memoryTypes[i].propertyFlags & properties) == properties)
            {
                return i;
            }
        }

        return error.NoSuitableMemoryType;
    }

    fn copyBuffer(self: *Self, src_buffer: vk.VkBuffer, dst_buffer: vk.VkBuffer, size: vk.VkDeviceSize) !void {
        // Create command buffer for transfer
        const alloc_info = vk.VkCommandBufferAllocateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .pNext = null,
            .commandPool = self.command_pool.?,
            .level = vk.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = 1,
        };

        var command_buffer: vk.VkCommandBuffer = undefined;
        var command_buffers = [_]vk.VkCommandBuffer{command_buffer};
        const result = vk.vkAllocateCommandBuffers(self.device.?, &alloc_info, &command_buffers);
        if (result != vk.VkResult.VK_SUCCESS) return error.CommandBufferAllocationFailed;
        command_buffer = command_buffers[0];

        // Begin command buffer
        const begin_info = vk.VkCommandBufferBeginInfo{
            .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .pNext = null,
            .flags = vk.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
            .pInheritanceInfo = null,
        };

        const begin_result = vk.vkBeginCommandBuffer(command_buffer, &begin_info);
        if (begin_result != vk.VkResult.VK_SUCCESS) return error.CommandBufferBeginFailed;

        // Copy buffer
        const copy_region = vk.VkBufferCopy{
            .srcOffset = 0,
            .dstOffset = 0,
            .size = size,
        };

        const copy_regions = [_]vk.VkBufferCopy{copy_region};
        vk.vkCmdCopyBuffer(command_buffer, src_buffer, dst_buffer, 1, &copy_regions);

        // End and submit command buffer
        const end_result = vk.vkEndCommandBuffer(command_buffer);
        if (end_result != vk.VkResult.VK_SUCCESS) return error.CommandBufferEndFailed;

        const submit_command_buffers = [_]vk.VkCommandBuffer{command_buffer};
        const submit_info = vk.VkSubmitInfo{
            .sType = vk.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .pNext = null,
            .waitSemaphoreCount = 0,
            .pWaitSemaphores = null,
            .pWaitDstStageMask = null,
            .commandBufferCount = 1,
            .pCommandBuffers = &submit_command_buffers,
            .signalSemaphoreCount = 0,
            .pSignalSemaphores = null,
        };

        const submit_info_array = [_]vk.VkSubmitInfo{submit_info};
        const submit_result = vk.vkQueueSubmit(self.graphics_queue.?, 1, &submit_info_array, null);
        if (submit_result != vk.VkResult.VK_SUCCESS) return error.QueueSubmitFailed;

        const wait_result = vk.vkQueueWaitIdle(self.graphics_queue.?);
        if (wait_result != vk.VkResult.VK_SUCCESS) return error.QueueWaitIdleFailed;

        const free_command_buffers = [_]vk.VkCommandBuffer{command_buffer};
        vk.vkFreeCommandBuffers(self.device.?, self.command_pool.?, 1, &free_command_buffers);
    }

    fn createUniformBuffer(self: *Self) !void {
        std.debug.print("Creating uniform buffer...\n", .{});

        const buffer_size = @sizeOf(UniformBufferObject);

        // Create uniform buffer
        const buffer_info = vk.VkBufferCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .size = buffer_size,
            .usage = vk.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
            .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
            .queueFamilyIndexCount = 0,
            .pQueueFamilyIndices = null,
        };

        var temp_uniform_buffer: vk.VkBuffer = undefined;
        const uniform_create_result = vk.vkCreateBuffer(self.device.?, &buffer_info, null, &temp_uniform_buffer);
        self.uniform_buffer = temp_uniform_buffer;
        if (uniform_create_result != vk.VkResult.VK_SUCCESS) {
            std.debug.print("vkCreateBuffer failed: {}\n", .{uniform_create_result});
            return error.BufferCreationFailed;
        }

        // Get memory requirements
        var mem_requirements: vk.VkMemoryRequirements = undefined;
        vk.vkGetBufferMemoryRequirements(self.device.?, self.uniform_buffer.?, &mem_requirements);

        // Allocate memory
        const alloc_info = vk.VkMemoryAllocateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            .pNext = null,
            .allocationSize = mem_requirements.size,
            .memoryTypeIndex = try self.findMemoryType(mem_requirements.memoryTypeBits, vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT),
        };

        var temp_uniform_memory: vk.VkDeviceMemory = undefined;
        const uniform_alloc_result = vk.vkAllocateMemory(self.device.?, &alloc_info, null, &temp_uniform_memory);
        self.uniform_buffer_memory = temp_uniform_memory;
        if (uniform_alloc_result != vk.VkResult.VK_SUCCESS) {
            std.debug.print("vkAllocateMemory failed: {}\n", .{uniform_alloc_result});
            return error.MemoryAllocationFailed;
        }
        const uniform_bind_result = vk.vkBindBufferMemory(self.device.?, self.uniform_buffer.?, self.uniform_buffer_memory.?, 0);
        if (uniform_bind_result != vk.VkResult.VK_SUCCESS) {
            std.debug.print("vkBindBufferMemory failed: {}\n", .{uniform_bind_result});
            return error.BufferBindingFailed;
        }
    }

    fn createRenderPass(self: *Self) !void {
        std.debug.print("Creating render pass...\n", .{});
        // Mock implementation - in real code would use vkCreateRenderPass
        self.render_pass = @ptrFromInt(0xCDEF); // Mock pointer
    }

    fn createGraphicsPipeline(self: *Self) !void {
        std.debug.print("Creating graphics pipeline...\n", .{});
        // Mock implementation - in real code would use vkCreateGraphicsPipelines
        self.pipeline_layout = @ptrFromInt(0xDEF0); // Mock pointer
        self.pipeline = @ptrFromInt(0xEF01); // Mock pointer
    }

    fn createSwapchain(self: *Self) !void {
        std.debug.print("Creating swapchain...\n", .{});
        // Mock implementation - in real code would use vkCreateSwapchainKHR
        self.swapchain = @ptrFromInt(0xF012); // Mock pointer

        // Mock swapchain images
        self.swapchain_images = try self.allocator.alloc(VkImage, 3);
        self.swapchain_image_views = try self.allocator.alloc(VkImageView, 3);

        for (0..3) |i| {
            self.swapchain_images[i] = @ptrFromInt(0x1000 + i);
            self.swapchain_image_views[i] = @ptrFromInt(0x2000 + i);
        }
    }

    fn createFramebuffers(self: *Self) !void {
        std.debug.print("Creating framebuffers...\n", .{});
        self.framebuffers = try self.allocator.alloc(VkFramebuffer, self.swapchain_image_views.len);

        for (0..self.framebuffers.len) |i| {
            self.framebuffers[i] = @ptrFromInt(0x3000 + i);
        }
    }

    fn createCommandBuffer(self: *Self) !void {
        std.debug.print("Creating command buffer...\n", .{});
        // Mock implementation - in real code would use vkAllocateCommandBuffers
        self.command_buffer = @ptrFromInt(0x4000); // Mock pointer
    }

    fn cleanupSwapchain(self: *Self) void {
        if (self.framebuffers.len > 0) {
            self.allocator.free(self.framebuffers);
        }

        if (self.swapchain_image_views.len > 0) {
            self.allocator.free(self.swapchain_image_views);
        }

        if (self.swapchain_images.len > 0) {
            self.allocator.free(self.swapchain_images);
        }
    }

    pub fn render(self: *Self) !void {
        std.debug.print("Begin frame {}\n", .{self.current_frame});

        // Wait for previous frame
        const fence = self.frame_fences[self.current_frame];
        const wait_result = vk.vkWaitForFences(self.device.?, 1, (&[_]vk.VkFence{fence})[0..], vk.VK_TRUE, std.math.maxInt(u64));
        if (wait_result != vk.VkResult.VK_SUCCESS) {
            std.debug.print("vkWaitForFences failed: {}\n", .{wait_result});
            return error.WaitForFencesFailed;
        }
        const reset_result = vk.vkResetFences(self.device.?, 1, (&[_]vk.VkFence{fence})[0..]);
        if (reset_result != vk.VkResult.VK_SUCCESS) {
            std.debug.print("vkResetFences failed: {}\n", .{reset_result});
            return error.ResetFencesFailed;
        }

        // Update rotation with frame limiting
        const rotation_speed = 0.01; // Slower, smoother rotation
        self.rotation_angle += rotation_speed;
        if (self.rotation_angle > 2.0 * math.pi) {
            self.rotation_angle -= 2.0 * math.pi;
        }

        // Begin debug marker
        // vk.vkCmdDebugMarkerBeginEXT(self.command_buffer, "Frame Render", .{ 1.0, 1.0, 0.0, 1.0 });

        // Acquire next swapchain image
        var image_index: u32 = undefined;
        const acquire_result = vk.vkAcquireNextImageKHR(self.device.?, self.swapchain.?, std.math.maxInt(u64), self.image_available_semaphores[self.current_frame], null, &image_index);
        if (acquire_result != vk.VkResult.VK_SUCCESS) {
            std.debug.print("vkAcquireNextImageKHR failed: {}\n", .{acquire_result});
            return error.SwapchainImageAcquisitionFailed;
        }

        // Update uniform buffer safely
        // vk.vkCmdDebugMarkerBeginEXT(self.command_buffer, "Update Uniforms", .{ 0.0, 1.0, 0.0, 1.0 });
        self.updateUniformBuffer() catch |err| {
            std.debug.print("Uniform buffer update error: {}\n", .{err});
            return;
        };
        // vk.vkCmdDebugMarkerEndEXT(self.command_buffer);

        // Record command buffer safely
        // vk.vkCmdDebugMarkerBeginEXT(self.command_buffer, "Record Commands", .{ 0.0, 0.0, 1.0, 1.0 });
        self.recordCommandBuffer() catch |err| {
            std.debug.print("Command buffer record error: {}\n", .{err});
            return;
        };
        // vk.vkCmdDebugMarkerEndEXT(self.command_buffer);

        // Submit and present safely
        const wait_semaphores = [_]vk.VkSemaphore{self.image_available_semaphores[self.current_frame]};
        const wait_stages = [_]vk.VkPipelineStageFlags{vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT};
        const signal_semaphores = [_]vk.VkSemaphore{self.render_finished_semaphores[self.current_frame]};

        const submit_info = vk.VkSubmitInfo{
            .sType = vk.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .pNext = null,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &wait_semaphores,
            .pWaitDstStageMask = &wait_stages,
            .commandBufferCount = 1,
            .pCommandBuffers = &self.command_buffer,
            .signalSemaphoreCount = 1,
            .pSignalSemaphores = &signal_semaphores,
        };

        try vk.vkQueueSubmit(self.graphics_queue, 1, &submit_info, fence);

        // Present
        const present_info = vk.VkPresentInfoKHR{
            .sType = vk.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .pNext = null,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &signal_semaphores,
            .swapchainCount = 1,
            .pSwapchains = &self.swapchain,
            .pImageIndices = &image_index,
            .pResults = null,
        };

        _ = try vk.vkQueuePresentKHR(self.graphics_queue, &present_info);

        vk.vkCmdDebugMarkerEndEXT(self.command_buffer);
        std.debug.print("End frame {}\n", .{self.current_frame});

        self.current_frame = (self.current_frame + 1) % vk.MAX_FRAMES_IN_FLIGHT;
    }

    fn updateUniformBuffer(self: *Self) !void {
        const model = Mat4.rotateY(self.rotation_angle);
        const view = Mat4.identity(); // Camera at origin looking down -Z
        const proj = Mat4.perspective(math.degreesToRadians(45.0), @as(f32, @floatFromInt(self.width)) / @as(f32, @floatFromInt(self.height)), 0.1, 10.0);

        const ubo = UniformBufferObject{
            .model = model,
            .view = view,
            .proj = proj,
        };

        // In a real implementation, we would map memory and copy the UBO
        _ = ubo;

        // Update material uniforms
        if (self.material_manager.getMaterial(self.current_material_id)) |mat| {
            mat.updateUniforms(model.data, view.data, proj.data, self.rotation_angle);
            if (self.device) |device| {
                mat.updateUniformBuffer(device) catch {};
            }
        }

        // Mock: Just print rotation info occasionally (safer)
        const rotation_int = @as(u32, @intFromFloat(@abs(self.rotation_angle * 100.0)));
        if (rotation_int % 314 == 0) { // Print every pi radians approximately
            std.debug.print("Cube rotation: {d:.2} radians\n", .{self.rotation_angle});
        }
    }

    fn recordCommandBuffer(self: *Self) !void {
        // Mock command buffer recording with material binding
        // In a real implementation, we would:
        // 1. Begin command buffer
        // 2. Begin render pass
        // 3. Bind material pipeline and descriptor sets
        // 4. Bind vertex/index buffers
        // 5. Draw indexed
        // 6. End render pass
        // 7. End command buffer

        if (self.command_buffer) |cmd_buffer| {
            if (self.material_manager.getMaterial(self.current_material_id)) |mat| {
                mat.bind(cmd_buffer);
            }
        }
    }

    fn submitCommandBuffer(self: *Self) !void {
        // Mock command buffer submission and presentation
        // In a real implementation, we would:
        // 1. Submit command buffer to graphics queue
        // 2. Present swapchain image

        _ = self;
    }

    pub fn resize(self: *Self, new_width: u32, new_height: u32) !void {
        // Validate dimensions to prevent crashes
        if (new_width == 0 or new_height == 0 or new_width > 8192 or new_height > 8192) {
            std.debug.print("Invalid resize dimensions: {}x{}\n", .{ new_width, new_height });
            return;
        }

        self.width = new_width;
        self.height = new_height;

        // Recreate swapchain and related resources safely
        self.cleanupSwapchain();
        self.createSwapchain() catch |err| {
            std.debug.print("Swapchain creation failed during resize: {}\n", .{err});
            return err;
        };
        self.createFramebuffers() catch |err| {
            std.debug.print("Framebuffer creation failed during resize: {}\n", .{err});
            return err;
        };

        std.debug.print("Vulkan renderer resized to {}x{}\n", .{ new_width, new_height });
    }

    pub fn getVertexData(self: *Self) []const Vertex {
        _ = self;
        return &cube_vertices;
    }

    pub fn getIndexData(self: *Self) []const u16 {
        _ = self;
        return &cube_indices;
    }

    fn initMaterials(self: *Self) !void {
        const device = self.device orelse return error.VulkanNotInitialized;
        const render_pass = self.render_pass orelse return error.VulkanNotInitialized;

        std.debug.print("🎨 Initializing materials...\n", .{});

        // Load default materials
        try self.material_manager.loadDefaultMaterials(device, render_pass);

        // Create and set up cube material
        const cube_material_id = try self.material_manager.createMaterial("SpinningCube", .unlit);
        self.current_material_id = cube_material_id;

        if (self.material_manager.getMaterial(cube_material_id)) |cube_material| {
            // Set colorful properties for the spinning cube
            cube_material.setProperty("albedo", [4]f32{ 0.8, 0.3, 0.1, 1.0 }); // Orange

            // Load shaders (mock implementation for now)
            try cube_material.createPipeline(self.device.?, self.render_pass.?);

            std.debug.print("✅ Spinning cube material created\n", .{});
        }
    }

    pub fn switchMaterial(self: *Self, material_name: []const u8) void {
        // Find material by name and switch to it
        var iterator = self.material_manager.materials.iterator();
        while (iterator.next()) |entry| {
            const mat = entry.value_ptr;
            if (std.mem.eql(u8, mat.name, material_name)) {
                self.current_material_id = entry.key_ptr.*;
                std.debug.print("Switched to material: {s}\n", .{material_name});
                return;
            }
        }
        std.debug.print("Material not found: {s}\n", .{material_name});
    }

    pub fn getCurrentMaterial(self: *Self) ?*material.Material {
        return self.material_manager.getMaterial(self.current_material_id);
    }
};

// Public API
pub fn createCubeRenderer(allocator: Allocator, width: u32, height: u32, hwnd: *anyopaque, hinstance: *anyopaque) !VulkanCubeRenderer {
    var renderer = try VulkanCubeRenderer.init(allocator, width, height, hwnd, hinstance);
    try renderer.initVulkan();

    std.debug.print("✅ Vulkan spinning cube renderer initialized\n", .{});
    std.debug.print("   Vertices: {}\n", .{cube_vertices.len});
    std.debug.print("   Indices: {}\n", .{cube_indices.len});
    std.debug.print("   Triangles: {}\n", .{cube_indices.len / 3});
    std.debug.print("   Surface created for window\n", .{});

    return renderer;
}

// Vertex shader source (GLSL)
pub const vertex_shader_source =
    \\#version 450
    \\
    \\layout(binding = 0) uniform UniformBufferObject {
    \\    mat4 model;
    \\    mat4 view;
    \\    mat4 proj;
    \\} ubo;
    \\
    \\layout(location = 0) in vec3 inPosition;
    \\layout(location = 1) in vec3 inColor;
    \\
    \\layout(location = 0) out vec3 fragColor;
    \\
    \\void main() {
    \\    gl_Position = ubo.proj * ubo.view * ubo.model * vec4(inPosition, 1.0);
    \\    fragColor = inColor;
    \\}
;

// Fragment shader source (GLSL)
pub const fragment_shader_source =
    \\#version 450
    \\
    \\layout(location = 0) in vec3 fragColor;
    \\layout(location = 0) out vec4 outColor;
    \\
    \\void main() {
    \\    outColor = vec4(fragColor, 1.0);
    \\}
;
