const std = @import("std");
const Allocator = std.mem.Allocator;
const interface = @import("interface.zig");
const ArrayList = std.ArrayList;

// Re-export Vulkan types from vulkan.zig
const vk = @import("vulkan.zig").vk;

const MAX_FRAMES_IN_FLIGHT = 2;

// Vulkan context that holds all state
pub const VulkanContext = struct {
    allocator: Allocator,
    instance: vk.Instance,
    physical_device: vk.PhysicalDevice,
    device: vk.Device,
    graphics_queue: vk.Queue,
    present_queue: vk.Queue,
    surface: vk.SurfaceKHR,
    swapchain: vk.SwapchainKHR,
    swapchain_images: []vk.Image,
    swapchain_image_views: []vk.ImageView,
    render_pass: vk.RenderPass,
    pipeline_layout: vk.PipelineLayout,
    graphics_pipeline: vk.Pipeline,
    framebuffers: []vk.Framebuffer,
    command_pool: vk.CommandPool,
    command_buffers: []vk.CommandBuffer,
    image_available_semaphores: []vk.Semaphore,
    render_finished_semaphores: []vk.Semaphore,
    in_flight_fences: []vk.Fence,
    current_frame: usize,
    width: u32,
    height: u32,
    hwnd: usize,

    // Error tracking
    last_error: ?[]const u8,
    validation_enabled: bool,

    // Memory tracking
    total_memory_allocated: usize,
    memory_allocations: std.AutoHashMap(u64, usize),

    // Image resources
    images: std.AutoHashMap(u32, ImageResource),
    descriptor_pool: vk.DescriptorPool,
    descriptor_set_layout: vk.DescriptorSetLayout,
    descriptor_sets: []vk.DescriptorSet,

    const Self = @This();

    // Structure to store image-related resources
    const ImageResource = struct {
        image: vk.Image,
        memory: vk.DeviceMemory,
        view: vk.ImageView,
        sampler: vk.Sampler,
        width: u32,
        height: u32,
        format: interface.Image.ImageFormat,
    };

    pub fn init(allocator: Allocator, window_handle: usize) !*Self {
        var self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.allocator = allocator;
        self.hwnd = @ptrFromInt(window_handle);
        self.width = 800; // Default, will be updated in beginFrame
        self.height = 600;
        self.current_frame = 0;

        // Initialize Vulkan resources
        self.instance = undefined;
        self.physical_device = undefined;
        self.device = undefined;
        self.graphics_queue = undefined;
        self.present_queue = undefined;
        self.surface = 0;
        self.swapchain = 0;
        self.swapchain_images = &[_]vk.Image{};
        self.swapchain_image_views = &[_]vk.ImageView{};
        self.render_pass = 0;
        self.pipeline_layout = 0;
        self.graphics_pipeline = 0;
        self.framebuffers = &[_]vk.Framebuffer{};
        self.command_pool = 0;
        self.command_buffers = &[_]vk.CommandBuffer{};
        self.image_available_semaphores = &[_]vk.Semaphore{};
        self.render_finished_semaphores = &[_]vk.Semaphore{};
        self.in_flight_fences = &[_]vk.Fence{};
        self.descriptor_pool = 0;
        self.descriptor_set_layout = 0;
        self.descriptor_sets = &[_]vk.DescriptorSet{};

        // Initialize image cache
        self.images = std.AutoHashMap(usize, ImageResource).init(allocator);

        // Initialize Vulkan
        try self.initVulkan();
        try self.createSyncObjects();

        return self;
    }

    pub fn deinit(self: *Self) void {
        // Wait for all operations to complete
        if (self.device != 0) {
            // vkDeviceWaitIdle(self.device);
        }

        // Clean up Vulkan resources
        self.cleanupSwapchain();

        // Clean up image cache
        var image_iterator = self.images.valueIterator();
        while (image_iterator.next()) |image_resource| {
            self.cleanupImageResource(image_resource);
        }
        self.images.deinit();

        // Clean up synchronization objects
        for (0..MAX_FRAMES_IN_FLIGHT) |i| {
            if (self.image_available_semaphores.len > i) {
                // vkDestroySemaphore(self.device, self.image_available_semaphores[i], null);
            }
            if (self.render_finished_semaphores.len > i) {
                // vkDestroySemaphore(self.device, self.render_finished_semaphores[i], null);
            }
            if (self.in_flight_fences.len > i) {
                // vkDestroyFence(self.device, self.in_flight_fences[i], null);
            }
        }

        // Free allocated arrays
        if (self.image_available_semaphores.len > 0) {
            self.allocator.free(self.image_available_semaphores);
        }
        if (self.render_finished_semaphores.len > 0) {
            self.allocator.free(self.render_finished_semaphores);
        }
        if (self.in_flight_fences.len > 0) {
            self.allocator.free(self.in_flight_fences);
        }

        // Clean up descriptor resources
        if (self.descriptor_pool != 0) {
            // vkDestroyDescriptorPool(self.device, self.descriptor_pool, null);
        }
        if (self.descriptor_set_layout != 0) {
            // vkDestroyDescriptorSetLayout(self.device, self.descriptor_set_layout, null);
        }

        // Clean up command pool
        if (self.command_pool != 0) {
            // vkDestroyCommandPool(self.device, self.command_pool, null);
        }

        // Clean up device, surface, and instance
        if (self.device != 0) {
            // vkDestroyDevice(self.device, null);
        }
        if (self.surface != 0) {
            // vkDestroySurfaceKHR(self.instance, self.surface, null);
        }
        if (self.instance != 0) {
            // vkDestroyInstance(self.instance, null);
        }

        // Free memory
        self.allocator.destroy(self);
    }

    pub fn beginFrame(self: *Self, width: u32, height: u32) void {
        // If window was resized, recreate swapchain
        if (self.width != width or self.height != height) {
            self.resize(width, height);
        }

        // Wait for previous frame to finish
        if (self.in_flight_fences.len > 0) {
            // vkWaitForFences(self.device, 1, &self.in_flight_fences[self.current_frame], VK_TRUE, std.math.maxInt(u64));
        }

        // Acquire next image
        const image_index: u32 = 0;
        if (self.swapchain != 0 and self.image_available_semaphores.len > 0) {
            // vkAcquireNextImageKHR(self.device, self.swapchain, std.math.maxInt(u64),
            //     self.image_available_semaphores[self.current_frame], 0, &image_index);
        }

        // Reset fence
        if (self.in_flight_fences.len > 0) {
            // vkResetFences(self.device, 1, &self.in_flight_fences[self.current_frame]);
        }

        // Record command buffer
        if (self.command_buffers.len > 0) {
            // vkResetCommandBuffer(self.command_buffers[self.current_frame], 0);
            // self.recordCommandBuffer(self.command_buffers[self.current_frame], image_index);
        }

        _ = image_index; // Placeholder until Vulkan implementation is complete
    }

    pub fn endFrame(self: *Self) void {
        // Submit command buffer
        if (self.command_buffers.len > 0 and self.graphics_queue != 0) {
            // const wait_stages = [_]vk.PipelineStageFlags{ .{ .color_attachment_output = true } };
            // const submit_info = vk.SubmitInfo{
            //     .sType = vk.StructureType.SUBMIT_INFO,
            //     .waitSemaphoreCount = 1,
            //     .pWaitSemaphores = &self.image_available_semaphores[self.current_frame],
            //     .pWaitDstStageMask = &wait_stages,
            //     .commandBufferCount = 1,
            //     .pCommandBuffers = &self.command_buffers[self.current_frame],
            //     .signalSemaphoreCount = 1,
            //     .pSignalSemaphores = &self.render_finished_semaphores[self.current_frame],
            // };

            // vkQueueSubmit(self.graphics_queue, 1, &submit_info, self.in_flight_fences[self.current_frame]);
        }

        // Present image
        if (self.present_queue != 0 and self.swapchain != 0) {
            // const image_index: u32 = 0; // This should come from beginFrame
            // const present_info = vk.PresentInfoKHR{
            //     .sType = vk.StructureType.PRESENT_INFO_KHR,
            //     .waitSemaphoreCount = 1,
            //     .pWaitSemaphores = &self.render_finished_semaphores[self.current_frame],
            //     .swapchainCount = 1,
            //     .pSwapchains = &self.swapchain,
            //     .pImageIndices = &image_index,
            //     .pResults = null,
            // };

            // vkQueuePresentKHR(self.present_queue, &present_info);
        }

        // Update current frame
        self.current_frame = (self.current_frame + 1) % MAX_FRAMES_IN_FLIGHT;
    }

    pub fn resize(self: *Self, width: u32, height: u32) void {
        // Validate dimensions
        if (width == 0 or height == 0) return;

        self.width = width;
        self.height = height;

        // Wait for device to be idle before recreating swapchain
        if (self.device != 0) {
            // vkDeviceWaitIdle(self.device);
        }

        // Cleanup old swapchain
        self.cleanupSwapchain();

        // Create new swapchain
        self.createSwapchainResources() catch |err| {
            std.log.err("Failed to recreate swapchain: {}", .{err});
            return;
        };
    }

    pub fn createImage(self: *Self, width: u32, height: u32, pixels: [*]const u8, format: interface.Image.ImageFormat) !interface.Image {
        const resource_id = self.generateImageId();

        // Create Vulkan image, memory, view, and sampler
        const image_resource = ImageResource{
            .image = 0, // Placeholder - would be actual vkImage
            .memory = 0, // Placeholder - would be actual vkDeviceMemory
            .view = 0, // Placeholder - would be actual vkImageView
            .sampler = 0, // Placeholder - would be actual vkSampler
            .width = width,
            .height = height,
            .format = format,
        };

        // Upload pixel data to GPU memory
        // self.uploadImageData(&image_resource, pixels);

        try self.images.put(resource_id, image_resource);

        _ = pixels; // Placeholder until implementation

        return interface.Image{
            .id = resource_id,
            .width = width,
            .height = height,
            .format = format,
        };
    }

    pub fn destroyImage(self: *Self, image: *interface.Image) void {
        if (self.images.get(image.id)) |image_resource| {
            self.cleanupImageResource(&image_resource);
            _ = self.images.remove(image.id);
        }
        image.id = 0; // Invalidate the image
    }
    pub fn getTextSize(self: *Self, text: []const u8, font: interface.FontInfo) struct { width: f32, height: f32 } {
        _ = self;
        // Basic text measurement - would need proper font handling
        const char_width = @as(f32, @floatFromInt(font.size)) * 0.6; // Approximate
        const char_height = @as(f32, @floatFromInt(font.size));

        return .{
            .width = char_width * @as(f32, @floatFromInt(text.len)),
            .height = char_height,
        };
    }

    fn createSyncObjects(self: *Self) !void {
        // Allocate arrays for synchronization objects
        self.image_available_semaphores = try self.allocator.alloc(vk.Semaphore, MAX_FRAMES_IN_FLIGHT);
        self.render_finished_semaphores = try self.allocator.alloc(vk.Semaphore, MAX_FRAMES_IN_FLIGHT);
        self.in_flight_fences = try self.allocator.alloc(vk.Fence, MAX_FRAMES_IN_FLIGHT);

        // Initialize all to zero for now
        for (0..MAX_FRAMES_IN_FLIGHT) |i| {
            self.image_available_semaphores[i] = 0;
            self.render_finished_semaphores[i] = 0;
            self.in_flight_fences[i] = 0;
        }

        // Create actual Vulkan synchronization objects
        // for (0..MAX_FRAMES_IN_FLIGHT) |i| {
        //     const semaphore_info = vk.SemaphoreCreateInfo{
        //         .sType = vk.StructureType.SEMAPHORE_CREATE_INFO,
        //     };
        //     vkCreateSemaphore(self.device, &semaphore_info, null, &self.image_available_semaphores[i]);
        //     vkCreateSemaphore(self.device, &semaphore_info, null, &self.render_finished_semaphores[i]);
        //
        //     const fence_info = vk.FenceCreateInfo{
        //         .sType = vk.StructureType.FENCE_CREATE_INFO,
        //         .flags = vk.FenceCreateFlags{ .signaled = true },
        //     };
        //     vkCreateFence(self.device, &fence_info, null, &self.in_flight_fences[i]);
        // }
    }

    fn initVulkan(self: *Self) !void {
        // Create Vulkan instance with required extensions
        try self.createInstance();
        try self.createSurface();
        try self.selectPhysicalDevice();
        try self.createLogicalDevice();
        try self.createSwapchainResources();
        try self.createDescriptorSetLayout();
        try self.createDescriptorPool();
    }

    fn createInstance(self: *Self) !void {
        // Placeholder for Vulkan instance creation
        self.instance = 1; // Non-zero placeholder
    }

    fn createSurface(self: *Self) !void {
        // Placeholder for surface creation
        self.surface = 1; // Non-zero placeholder
    }

    fn selectPhysicalDevice(self: *Self) !void {
        // Placeholder for physical device selection
        self.physical_device = 1; // Non-zero placeholder
    }

    fn createLogicalDevice(self: *Self) !void {
        // Placeholder for logical device creation
        self.device = 1; // Non-zero placeholder
        self.graphics_queue = 1; // Non-zero placeholder
        self.present_queue = 1; // Non-zero placeholder
    }

    fn createSwapchainResources(self: *Self) !void {
        // Create swapchain, image views, render pass, pipeline, framebuffers, command buffers
        self.swapchain = 1; // Non-zero placeholder
        self.render_pass = 1; // Non-zero placeholder
        self.pipeline_layout = 1; // Non-zero placeholder
        self.graphics_pipeline = 1; // Non-zero placeholder
        self.command_pool = 1; // Non-zero placeholder

        // Allocate placeholder arrays
        self.swapchain_images = try self.allocator.alloc(vk.Image, 2);
        self.swapchain_image_views = try self.allocator.alloc(vk.ImageView, 2);
        self.framebuffers = try self.allocator.alloc(vk.Framebuffer, 2);
        self.command_buffers = try self.allocator.alloc(vk.CommandBuffer, MAX_FRAMES_IN_FLIGHT);
    }

    fn createDescriptorSetLayout(self: *Self) !void {
        self.descriptor_set_layout = 1; // Non-zero placeholder
    }

    fn createDescriptorPool(self: *Self) !void {
        self.descriptor_pool = 1; // Non-zero placeholder
        self.descriptor_sets = try self.allocator.alloc(vk.DescriptorSet, MAX_FRAMES_IN_FLIGHT);
    }

    fn cleanupSwapchain(self: *Self) void {
        // Clean up resources that need to be recreated when window is resized

        // Free allocated arrays
        if (self.command_buffers.len > 0) {
            self.allocator.free(self.command_buffers);
            self.command_buffers = &[_]vk.CommandBuffer{};
        }

        if (self.framebuffers.len > 0) {
            // for (self.framebuffers) |framebuffer| {
            //     vkDestroyFramebuffer(self.device, framebuffer, null);
            // }
            self.allocator.free(self.framebuffers);
            self.framebuffers = &[_]vk.Framebuffer{};
        }

        // Destroy pipeline
        if (self.graphics_pipeline != 0) {
            // vkDestroyPipeline(self.device, self.graphics_pipeline, null);
            self.graphics_pipeline = 0;
        }
        if (self.pipeline_layout != 0) {
            // vkDestroyPipelineLayout(self.device, self.pipeline_layout, null);
            self.pipeline_layout = 0;
        }
        if (self.render_pass != 0) {
            // vkDestroyRenderPass(self.device, self.render_pass, null);
            self.render_pass = 0;
        }

        // Destroy image views
        if (self.swapchain_image_views.len > 0) {
            // for (self.swapchain_image_views) |image_view| {
            //     vkDestroyImageView(self.device, image_view, null);
            // }
            self.allocator.free(self.swapchain_image_views);
            self.swapchain_image_views = &[_]vk.ImageView{};
        }

        // Free swapchain images array
        if (self.swapchain_images.len > 0) {
            self.allocator.free(self.swapchain_images);
            self.swapchain_images = &[_]vk.Image{};
        }

        // Destroy swapchain
        if (self.swapchain != 0) {
            // vkDestroySwapchainKHR(self.device, self.swapchain, null);
            self.swapchain = 0;
        }
    }

    fn cleanupImageResource(self: *Self, image_resource: *const ImageResource) void {
        // Clean up image resources
        if (image_resource.sampler != 0) {
            // vkDestroySampler(self.device, image_resource.sampler, null);
        }
        if (image_resource.view != 0) {
            // vkDestroyImageView(self.device, image_resource.view, null);
        }
        if (image_resource.image != 0) {
            // vkDestroyImage(self.device, image_resource.image, null);
        }
        if (image_resource.memory != 0) {
            // vkFreeMemory(self.device, image_resource.memory, null);
        }

        _ = self; // Remove when actual implementation is added
    }

    fn generateImageId(self: *Self) usize {
        // Simple ID generation - in a real implementation, this should be more robust
        return self.images.count();
    }

    fn executeDrawCommands(self: *Self, commands: []const interface.DrawCommand) void {
        if (commands.len == 0) return;

        // Begin render pass
        // const render_pass_begin_info = vk.RenderPassBeginInfo{
        //     .sType = vk.StructureType.RENDER_PASS_BEGIN_INFO,
        //     .renderPass = self.render_pass,
        //     .framebuffer = self.framebuffers[image_index],
        //     .renderArea = vk.Rect2D{
        //         .offset = vk.Offset2D{ .x = 0, .y = 0 },
        //         .extent = vk.Extent2D{ .width = self.width, .height = self.height },
        //     },
        //     .clearValueCount = 1,
        //     .pClearValues = &[_]vk.ClearValue{
        //         vk.ClearValue{ .color = [4]f32{ 0.0, 0.0, 0.0, 1.0 } },
        //     },
        // };

        // vkCmdBeginRenderPass(self.command_buffers[self.current_frame], &render_pass_begin_info,
        //     vk.SubpassContents.INLINE);

        // Process draw commands
        for (commands) |cmd| {
            switch (cmd) {
                .clear => |color| {
                    self.handleClearCommand(color);
                },
                .rect => |rect_data| {
                    self.handleRectCommand(rect_data);
                },
                .text => |text_data| {
                    self.handleTextCommand(text_data);
                },
                .image => |image_data| {
                    self.handleImageCommand(image_data);
                },
                .clip_push => |clip_rect| {
                    self.handleClipPushCommand(clip_rect);
                },
                .clip_pop => {
                    self.handleClipPopCommand();
                },
                .custom => |custom_data| {
                    self.handleCustomCommand(custom_data);
                },
            }
        }

        // End render pass
        // vkCmdEndRenderPass(self.command_buffers[self.current_frame]);
    }

    fn handleClearCommand(self: *Self, color: [4]f32) void {
        // Clear the framebuffer with the specified color
        // This would typically involve setting up a clear color value
        // and using vkCmdClearColorImage or similar
        _ = self;
        _ = color;
    }

    fn handleRectCommand(self: *Self, rect_data: interface.RectData) void {
        // Draw a rectangle
        // Convert rect to Vulkan coordinates
        // Push vertex and index data
        // Bind appropriate pipeline
        // Draw indexed
        _ = self;
        _ = rect_data;
    }

    fn handleTextCommand(self: *Self, text_data: interface.TextData) void {
        // Draw text using texture atlas
        // This would involve binding a font texture atlas
        // and rendering quads for each character
        _ = self;
        _ = text_data;
    }
    fn handleImageCommand(self: *Self, image_data: interface.ImageData) void {
        // Draw an image
        // Bind descriptor set for the image
        // Draw a textured quad
        if (self.images.get(image_data.image.id)) |image_resource| {
            // Bind the image's descriptor set and draw
            _ = image_resource;
        }
    }

    fn handleClipPushCommand(self: *Self, clip_rect: interface.Rect) void {
        // Push a scissor rectangle
        // Convert to Vulkan scissor coordinates and set via vkCmdSetScissor
        _ = self;
        _ = clip_rect;
    }

    fn handleClipPopCommand(self: *Self) void {
        // Pop the current scissor rectangle
        // Restore the previous scissor state
        _ = self;
    }

    fn handleCustomCommand(self: *Self, custom_data: interface.CustomData) void {
        // Handle custom drawing commands
        // This allows for extension points in the rendering system
        _ = self;
        _ = custom_data;
    }
};

// Type alias for the backend interface
const VulkanBackend = VulkanContext;

// Vulkan backend interface implementation
fn vulkanInit(allocator: std.mem.Allocator, window_handle: usize) !*anyopaque {
    const backend = try allocator.create(VulkanBackend);
    backend.* = VulkanBackend.init(allocator, window_handle) catch |err| {
        allocator.destroy(backend);
        return err;
    };
    return backend;
}

fn vulkanDeinit(ctx: *anyopaque) void {
    const backend: *VulkanBackend = @ptrCast(@alignCast(@alignOf(VulkanBackend), ctx));
    const allocator = backend.allocator;
    backend.deinit();
    allocator.destroy(backend);
}

fn vulkanBeginFrame(ctx: *anyopaque, width: u32, height: u32) void {
    const backend: *VulkanBackend = @ptrCast(@alignCast(ctx));
    backend.beginFrame(width, height);
}

fn vulkanEndFrame(ctx: *anyopaque) void {
    const backend: *VulkanBackend = @ptrCast(@alignCast(ctx));
    backend.endFrame();
}

fn vulkanExecuteDrawCommands(ctx: *anyopaque, commands: []const interface.DrawCommand) void {
    const backend: *VulkanBackend = @ptrCast(@alignCast(ctx));
    backend.executeDrawCommands(commands);
}

fn vulkanCreateImage(ctx: *anyopaque, width: u32, height: u32, pixels: [*]const u8, format: interface.Image.ImageFormat) !interface.Image {
    const backend: *VulkanBackend = @ptrCast(@alignCast(ctx));
    return backend.createImage(width, height, pixels, format);
}

fn vulkanDestroyImage(ctx: *anyopaque, image: *interface.Image) void {
    const backend: *VulkanBackend = @ptrCast(@alignCast(ctx));
    backend.destroyImage(image);
}

fn vulkanGetTextSize(ctx: *anyopaque, text: []const u8, font: interface.FontInfo) struct { width: f32, height: f32 } {
    const backend: *VulkanBackend = @ptrCast(@alignCast(ctx));
    return backend.getTextSize(text, font);
}

fn vulkanResize(ctx: *anyopaque, width: u32, height: u32) void {
    const backend: *VulkanBackend = @ptrCast(@alignCast(ctx));
    backend.resize(width, height);
}

// Helper function to get last error from context
fn vulkanGetLastError(ctx: *anyopaque) ?[]const u8 {
    const context: *VulkanContext = @ptrCast(@alignCast(@alignOf(VulkanContext), ctx));
    return context.last_error;
}

pub const vulkan_backend_interface: interface.BackendInterface = {
    .init_fn = vulkanInit,
    .deinit_fn = vulkanDeinit,
    .begin_frame_fn = vulkanBeginFrame,
    .end_frame_fn = vulkanEndFrame,
    .execute_draw_commands_fn = vulkanExecuteDrawCommands,
    .create_image_fn = vulkanCreateImage,
    .destroy_image_fn = vulkanDestroyImage,
    .get_text_size_fn = vulkanGetTextSize,
    .resize_fn = vulkanResize,
    .get_last_error_fn = vulkanGetLastError,
    .backend_type = .vulkan,
};
