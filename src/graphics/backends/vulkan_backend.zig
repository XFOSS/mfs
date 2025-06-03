const std = @import("std");
const builtin = @import("builtin");
const interface = @import("interface.zig");
const types = @import("../types.zig");
const vk = @import("../../vulkan/vk.zig");
const enhanced_backend = @import("../../vulkan/enhanced_backend.zig");

/// Enhanced Vulkan backend implementation that uses the full Vulkan API
/// to provide high-performance graphics capabilities.
pub const VulkanBackend = struct {
    allocator: std.mem.Allocator,
    initialized: bool = false,

    // Core Vulkan objects
    device: ?enhanced_backend.VulkanDevice = null,
    renderer: ?enhanced_backend.VulkanRenderer = null,
    swapchain: ?enhanced_backend.Swapchain = null,

    // Resource management
    command_pool: ?enhanced_backend.CommandPool = null,
    current_command_buffer: ?vk.VkCommandBuffer = null,

    // Resource caches
    pipelines: std.AutoHashMap(u64, enhanced_backend.Pipeline),
    buffers: std.AutoHashMap(u64, enhanced_backend.Buffer),
    textures: std.AutoHashMap(u64, enhanced_backend.Image),

    // Performance tracking
    frame_count: u64 = 0,
    last_frame_time_ns: u64 = 0,

    const Self = @This();

    const vtable = interface.GraphicsBackend.VTable{
        .deinit = deinitImpl,
        .create_swap_chain = createSwapChainImpl,
        .resize_swap_chain = resizeSwapChainImpl,
        .present = presentImpl,
        .get_current_back_buffer = getCurrentBackBufferImpl,
        .create_texture = createTextureImpl,
        .create_buffer = createBufferImpl,
        .create_shader = createShaderImpl,
        .create_pipeline = createPipelineImpl,
        .create_render_target = createRenderTargetImpl,
        .update_buffer = updateBufferImpl,
        .update_texture = updateTextureImpl,
        .destroy_texture = destroyTextureImpl,
        .destroy_buffer = destroyBufferImpl,
        .destroy_shader = destroyShaderImpl,
        .destroy_render_target = destroyRenderTargetImpl,
        .create_command_buffer = createCommandBufferImpl,
        .begin_command_buffer = beginCommandBufferImpl,
        .end_command_buffer = endCommandBufferImpl,
        .submit_command_buffer = submitCommandBufferImpl,
        .begin_render_pass = beginRenderPassImpl,
        .end_render_pass = endRenderPassImpl,
        .set_viewport = setViewportImpl,
        .set_scissor = setScissorImpl,
        .bind_pipeline = bindPipelineImpl,
        .bind_vertex_buffer = bindVertexBufferImpl,
        .bind_index_buffer = bindIndexBufferImpl,
        .bind_texture = bindTextureImpl,
        .bind_uniform_buffer = bindUniformBufferImpl,
        .draw = drawImpl,
        .draw_indexed = drawIndexedImpl,
        .dispatch = dispatchImpl,
        .copy_buffer = copyBufferImpl,
        .copy_texture = copyTextureImpl,
        .copy_buffer_to_texture = copyBufferToTextureImpl,
        .copy_texture_to_buffer = copyTextureToBufferImpl,
        .resource_barrier = resourceBarrierImpl,
        .get_backend_info = getBackendInfoImpl,
        .set_debug_name = setDebugNameImpl,
        .begin_debug_group = beginDebugGroupImpl,
        .end_debug_group = endDebugGroupImpl,
    };

    /// Initialize the Vulkan backend and required resources
    pub fn init(allocator: std.mem.Allocator) !*interface.GraphicsBackend {
        // Create the backend instance
        const backend = try allocator.create(Self);

        // Initialize Vulkan state
        backend.* = Self{
            .allocator = allocator,
            .initialized = false,
            .pipelines = std.AutoHashMap(u64, enhanced_backend.Pipeline).init(allocator),
            .buffers = std.AutoHashMap(u64, enhanced_backend.Buffer).init(allocator),
            .textures = std.AutoHashMap(u64, enhanced_backend.Image).init(allocator),
        };

        // Create core Vulkan objects
        backend.device = try enhanced_backend.VulkanDevice.init(allocator);
        backend.command_pool = try enhanced_backend.CommandPool.init(backend.device.?.device, backend.device.?.graphics_queue_family);

        // Create the interface object
        const graphics_backend = try allocator.create(interface.GraphicsBackend);
        graphics_backend.* = interface.GraphicsBackend{
            .allocator = allocator,
            .backend_type = .vulkan,
            .vtable = &vtable,
            .impl_data = backend,
            .initialized = true,
        };

        backend.initialized = true;
        std.log.info("Enhanced Vulkan backend initialized", .{});
        return graphics_backend;
    }

    // Implementation of backend interface
    fn deinitImpl(impl: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(impl));

        // Clean up resources
        self.pipelines.deinit();
        self.buffers.deinit();
        self.textures.deinit();

        // Clean up core Vulkan objects
        if (self.command_pool) |*cmd_pool| {
            cmd_pool.deinit();
        }

        if (self.renderer) |*renderer| {
            renderer.deinit();
        }

        if (self.swapchain) |*swapchain| {
            swapchain.deinit();
        }

        if (self.device) |*device| {
            device.deinit();
        }

        self.allocator.destroy(self);
    }

    fn createSwapChainImpl(impl: *anyopaque, desc: *const interface.SwapChainDesc) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (self.swapchain != null) {
            // Clean up existing swapchain
            self.swapchain.?.deinit();
            self.swapchain = null;
        }

        if (self.renderer != null) {
            // Clean up existing renderer
            self.renderer.?.deinit();
            self.renderer = null;
        }

        // Create new swapchain
        if (self.device) |device| {
            // Convert window handle to platform-specific surface
            const surface = try vk.createSurfaceFromHandle(
                device.instance,
                desc.window_handle,
            );

            // Create swapchain
            self.swapchain = try enhanced_backend.Swapchain.init(
                self.allocator,
                device.physical_device,
                device.device,
                surface,
                desc.width,
                desc.height,
                desc.vsync,
            );

            // Create renderer
            self.renderer = try enhanced_backend.VulkanRenderer.init(
                self.allocator,
                device,
                self.swapchain.?,
                self.command_pool.?,
            );

            return;
        }

        return interface.GraphicsBackendError.InitializationFailed;
    }

    fn resizeSwapChainImpl(impl: *anyopaque, width: u32, height: u32) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (self.renderer) |*renderer| {
            try renderer.resize(width, height);
            return;
        }

        return interface.GraphicsBackendError.MissingResource;
    }

    fn presentImpl(impl: *anyopaque) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (self.renderer) |*renderer| {
            try renderer.render();
            self.frame_count += 1;
            return;
        }

        return interface.GraphicsBackendError.MissingResource;
    }

    fn getCurrentBackBufferImpl(impl: *anyopaque) interface.GraphicsBackendError!*types.Texture {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (self.swapchain) |swapchain| {
            // Get current swapchain image index
            const image_index = try swapchain.acquireNextImage();

            // Create a temporary texture to represent the backbuffer
            const texture = try self.allocator.create(types.Texture);
            texture.* = types.Texture{
                .id = @intCast(self.frame_count),
                .width = swapchain.extent.width,
                .height = swapchain.extent.height,
                .depth = 1,
                .format = .rgba8_unorm,
                .mip_levels = 1,
                .array_layers = 1,
                .sample_count = 1,
                .usage = .{ .render_target = true, .shader_resource = false },
                .type = .texture2d,
                .backend_handle = @intFromPtr(swapchain.images[image_index]),
            };

            return texture;
        }

        return interface.GraphicsBackendError.MissingResource;
    }

    fn createTextureImpl(impl: *anyopaque, texture: *types.Texture, data: ?[]const u8) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (self.device) |device| {
            // Create Vulkan image
            var image = try enhanced_backend.Image.init(
                device.device,
                device.physical_device,
                texture.width,
                texture.height,
                mapTextureFormat(texture.format),
                mapTextureUsage(texture.usage),
                texture.mip_levels,
                texture.array_layers,
            );

            // Upload initial data if provided
            if (data) |pixels| {
                // TODO: Implement texture data upload
                std.log.debug("Texture data upload not yet implemented ({d} bytes)", .{pixels.len});
            }

            // Store in cache
            try self.textures.put(texture.id, image);

            // Set backend handle
            texture.backend_handle = @intFromPtr(&self.textures.get(texture.id).?);

            return;
        }

        return interface.GraphicsBackendError.InitializationFailed;
    }

    // Helper function to map texture format
    fn mapTextureFormat(format: types.TextureFormat) vk.VkFormat {
        return switch (format) {
            .rgba8_unorm => vk.VK_FORMAT_R8G8B8A8_UNORM,
            .rgba8_snorm => vk.VK_FORMAT_R8G8B8A8_SNORM,
            .rgba8_uint => vk.VK_FORMAT_R8G8B8A8_UINT,
            .rgba8_sint => vk.VK_FORMAT_R8G8B8A8_SINT,
            .rgba16_float => vk.VK_FORMAT_R16G16B16A16_SFLOAT,
            .rgba32_float => vk.VK_FORMAT_R32G32B32A32_SFLOAT,
            .r8_unorm => vk.VK_FORMAT_R8_UNORM,
            .r16_float => vk.VK_FORMAT_R16_SFLOAT,
            .r32_float => vk.VK_FORMAT_R32_SFLOAT,
            .depth32_float => vk.VK_FORMAT_D32_SFLOAT,
            .depth24_stencil8 => vk.VK_FORMAT_D24_UNORM_S8_UINT,
            .bc1_rgba_unorm => vk.VK_FORMAT_BC1_RGBA_UNORM_BLOCK,
            .bc3_rgba_unorm => vk.VK_FORMAT_BC3_UNORM_BLOCK,
            .bc5_rg_unorm => vk.VK_FORMAT_BC5_UNORM_BLOCK,
            .bc7_rgba_unorm => vk.VK_FORMAT_BC7_UNORM_BLOCK,
            else => vk.VK_FORMAT_R8G8B8A8_UNORM, // Default fallback
        };
    }

    // Helper function to map texture usage
    fn mapTextureUsage(usage: types.TextureUsageFlags) vk.VkImageUsageFlags {
        var result: vk.VkImageUsageFlags = 0;

        if (usage.shader_resource) {
            result |= vk.VK_IMAGE_USAGE_SAMPLED_BIT;
        }

        if (usage.render_target) {
            result |= vk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
        }

        if (usage.depth_stencil) {
            result |= vk.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT;
        }

        if (usage.unordered_access) {
            result |= vk.VK_IMAGE_USAGE_STORAGE_BIT;
        }

        if (usage.copy_src) {
            result |= vk.VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
        }

        if (usage.copy_dst) {
            result |= vk.VK_IMAGE_USAGE_TRANSFER_DST_BIT;
        }

        return result;
    }

    fn createBufferImpl(impl: *anyopaque, buffer: *types.Buffer, data: ?[]const u8) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (self.device) |device| {
            // Create Vulkan buffer
            var vk_buffer = try enhanced_backend.Buffer.init(
                device.device,
                device.physical_device,
                buffer.size,
                mapBufferUsage(buffer.usage),
            );

            // Upload initial data if provided
            if (data) |bytes| {
                const mapped_data = try vk_buffer.map();
                @memcpy(mapped_data[0..bytes.len], bytes);
                vk_buffer.unmap();
            }

            // Store in cache
            try self.buffers.put(buffer.id, vk_buffer);

            // Set backend handle
            buffer.backend_handle = @intFromPtr(&self.buffers.get(buffer.id).?);

            return;
        }

        return interface.GraphicsBackendError.InitializationFailed;
    }

    // Helper function to map buffer usage
    fn mapBufferUsage(usage: types.BufferUsageFlags) vk.VkBufferUsageFlags {
        var result: vk.VkBufferUsageFlags = 0;

        if (usage.vertex_buffer) {
            result |= vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT;
        }

        if (usage.index_buffer) {
            result |= vk.VK_BUFFER_USAGE_INDEX_BUFFER_BIT;
        }

        if (usage.uniform_buffer) {
            result |= vk.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT;
        }

        if (usage.storage_buffer) {
            result |= vk.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT;
        }

        if (usage.indirect_buffer) {
            result |= vk.VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT;
        }

        if (usage.copy_src) {
            result |= vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
        }

        if (usage.copy_dst) {
            result |= vk.VK_BUFFER_USAGE_TRANSFER_DST_BIT;
        }

        return result;
    }

    fn createShaderImpl(impl: *anyopaque, shader: *types.Shader) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (self.device) |device| {
            // TODO: Implement shader module creation
            std.log.debug("Creating shader: stage={}, entry={s}", .{ shader.stage, shader.entry_point });

            // Set backend handle to a non-null value to indicate success
            shader.backend_handle = shader.id;
            return;
        }

        return interface.GraphicsBackendError.InitializationFailed;
    }

    fn createPipelineImpl(impl: *anyopaque, desc: *const interface.PipelineDesc) interface.GraphicsBackendError!*interface.Pipeline {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (self.device) |_| {
            // Create a pipeline hash for caching
            const pipeline_hash = generatePipelineHash(desc);

            // Check if we already have this pipeline
            if (self.pipelines.get(pipeline_hash)) |existing_pipeline| {
                // Return a pipeline object for this existing pipeline
                const pipeline = try self.allocator.create(interface.Pipeline);
                pipeline.* = interface.Pipeline{
                    .id = pipeline_hash,
                    .backend_handle = @intFromPtr(&existing_pipeline),
                    .allocator = self.allocator,
                };
                return pipeline;
            }

            // Create vertex input state
            var vertex_bindings: [16]vk.VkVertexInputBindingDescription = undefined;
            var vertex_attrs: [16]vk.VkVertexInputAttributeDescription = undefined;

            var binding_count: u32 = 0;
            var attr_count: u32 = 0;

            if (desc.vertex_layout) |vertex_layout| {
                // Add the vertex binding
                vertex_bindings[binding_count] = .{
                    .binding = 0,
                    .stride = vertex_layout.stride,
                    .inputRate = vk.VK_VERTEX_INPUT_RATE_VERTEX,
                };
                binding_count += 1;

                // Add each vertex attribute
                for (vertex_layout.attributes) |attr| {
                    vertex_attrs[attr_count] = .{
                        .location = attr.location,
                        .binding = 0,
                        .format = mapVertexFormat(attr.format),
                        .offset = attr.offset,
                    };
                    attr_count += 1;
                }
            }

            // Create a new pipeline
            var new_pipeline = try enhanced_backend.Pipeline.init(
                device.device,
                self.getDefaultRenderPass(),
                &vertex_bindings,
                binding_count,
                &vertex_attrs,
                attr_count,
                mapPrimitiveTopology(desc.primitive_topology),
                mapBlendState(desc.blend_state),
                mapDepthStencilState(desc.depth_stencil_state),
            );

            // Store pipeline in cache
            try self.pipelines.put(pipeline_hash, new_pipeline);

            // Return a pipeline object
            const pipeline = try self.allocator.create(interface.Pipeline);
            pipeline.* = interface.Pipeline{
                .id = pipeline_hash,
                .backend_handle = @intFromPtr(&self.pipelines.get(pipeline_hash).?),
                .allocator = self.allocator,
            };

            return pipeline;
        }

        return interface.GraphicsBackendError.InitializationFailed;
    }

    // Get default renderpass (need to implement proper renderpass handling)
    fn getDefaultRenderPass(self: *Self) vk.VkRenderPass {
        if (self.renderer) |renderer| {
            return renderer.render_pass.render_pass;
        }
        return undefined;
    }

    // Generate a hash for pipeline caching
    fn generatePipelineHash(desc: *const interface.PipelineDesc) u64 {
        var hasher = std.hash.Wyhash.init(0);

        // Hash vertex shader
        if (desc.vertex_shader) |shader| {
            std.hash.autoHash(&hasher, shader.id);
        }

        // Hash fragment shader
        if (desc.fragment_shader) |shader| {
            std.hash.autoHash(&hasher, shader.id);
        }

        // Hash primitive topology
        std.hash.autoHash(&hasher, @intFromEnum(desc.primitive_topology));

        // Return the hash
        return hasher.final();
    }

    // Map vertex format to Vulkan format
    fn mapVertexFormat(format: interface.VertexFormat) vk.VkFormat {
        return switch (format) {
            .float1 => vk.VK_FORMAT_R32_SFLOAT,
            .float2 => vk.VK_FORMAT_R32G32_SFLOAT,
            .float3 => vk.VK_FORMAT_R32G32B32_SFLOAT,
            .float4 => vk.VK_FORMAT_R32G32B32A32_SFLOAT,
            .int1 => vk.VK_FORMAT_R32_SINT,
            .int2 => vk.VK_FORMAT_R32G32_SINT,
            .int3 => vk.VK_FORMAT_R32G32B32_SINT,
            .int4 => vk.VK_FORMAT_R32G32B32A32_SINT,
            .uint1 => vk.VK_FORMAT_R32_UINT,
            .uint2 => vk.VK_FORMAT_R32G32_UINT,
            .uint3 => vk.VK_FORMAT_R32G32B32_UINT,
            .uint4 => vk.VK_FORMAT_R32G32B32A32_UINT,
            .byte4_norm => vk.VK_FORMAT_R8G8B8A8_SNORM,
            .ubyte4_norm => vk.VK_FORMAT_R8G8B8A8_UNORM,
            .short2_norm => vk.VK_FORMAT_R16G16_SNORM,
            .ushort2_norm => vk.VK_FORMAT_R16G16_UNORM,
            .half2 => vk.VK_FORMAT_R16G16_SFLOAT,
            .half4 => vk.VK_FORMAT_R16G16B16A16_SFLOAT,
        };
    }

    // Map primitive topology to Vulkan topology
    fn mapPrimitiveTopology(topology: interface.PrimitiveTopology) vk.VkPrimitiveTopology {
        return switch (topology) {
            .points => vk.VK_PRIMITIVE_TOPOLOGY_POINT_LIST,
            .lines => vk.VK_PRIMITIVE_TOPOLOGY_LINE_LIST,
            .line_strip => vk.VK_PRIMITIVE_TOPOLOGY_LINE_STRIP,
            .triangles => vk.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
            .triangle_strip => vk.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP,
            .triangle_fan => vk.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN,
            .lines_adjacency => vk.VK_PRIMITIVE_TOPOLOGY_LINE_LIST_WITH_ADJACENCY,
            .line_strip_adjacency => vk.VK_PRIMITIVE_TOPOLOGY_LINE_STRIP_WITH_ADJACENCY,
            .triangles_adjacency => vk.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST_WITH_ADJACENCY,
            .triangle_strip_adjacency => vk.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP_WITH_ADJACENCY,
            .patches => vk.VK_PRIMITIVE_TOPOLOGY_PATCH_LIST,
        };
    }

    // Map blend state to Vulkan blend state
    fn mapBlendState(blend_state: ?interface.BlendState) vk.VkPipelineColorBlendAttachmentState {
        if (blend_state) |state| {
            if (state.enabled) {
                return .{
                    .blendEnable = vk.VK_TRUE,
                    .srcColorBlendFactor = mapBlendFactor(state.src_color),
                    .dstColorBlendFactor = mapBlendFactor(state.dst_color),
                    .colorBlendOp = mapBlendOp(state.color_op),
                    .srcAlphaBlendFactor = mapBlendFactor(state.src_alpha),
                    .dstAlphaBlendFactor = mapBlendFactor(state.dst_alpha),
                    .alphaBlendOp = mapBlendOp(state.alpha_op),
                    .colorWriteMask = mapColorMask(state.color_mask),
                };
            }
        }

        // Default: no blending, write all channels
        return .{
            .blendEnable = vk.VK_FALSE,
            .srcColorBlendFactor = vk.VK_BLEND_FACTOR_ONE,
            .dstColorBlendFactor = vk.VK_BLEND_FACTOR_ZERO,
            .colorBlendOp = vk.VK_BLEND_OP_ADD,
            .srcAlphaBlendFactor = vk.VK_BLEND_FACTOR_ONE,
            .dstAlphaBlendFactor = vk.VK_BLEND_FACTOR_ZERO,
            .alphaBlendOp = vk.VK_BLEND_OP_ADD,
            .colorWriteMask = vk.VK_COLOR_COMPONENT_R_BIT | vk.VK_COLOR_COMPONENT_G_BIT |
                vk.VK_COLOR_COMPONENT_B_BIT | vk.VK_COLOR_COMPONENT_A_BIT,
        };
    }

    // Map blend factor to Vulkan blend factor
    fn mapBlendFactor(factor: interface.BlendFactor) vk.VkBlendFactor {
        return switch (factor) {
            .zero => vk.VK_BLEND_FACTOR_ZERO,
            .one => vk.VK_BLEND_FACTOR_ONE,
            .src_color => vk.VK_BLEND_FACTOR_SRC_COLOR,
            .inv_src_color => vk.VK_BLEND_FACTOR_ONE_MINUS_SRC_COLOR,
            .src_alpha => vk.VK_BLEND_FACTOR_SRC_ALPHA,
            .inv_src_alpha => vk.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
            .dst_color => vk.VK_BLEND_FACTOR_DST_COLOR,
            .inv_dst_color => vk.VK_BLEND_FACTOR_ONE_MINUS_DST_COLOR,
            .dst_alpha => vk.VK_BLEND_FACTOR_DST_ALPHA,
            .inv_dst_alpha => vk.VK_BLEND_FACTOR_ONE_MINUS_DST_ALPHA,
            .blend_color => vk.VK_BLEND_FACTOR_CONSTANT_COLOR,
            .inv_blend_color => vk.VK_BLEND_FACTOR_ONE_MINUS_CONSTANT_COLOR,
            .blend_alpha => vk.VK_BLEND_FACTOR_CONSTANT_ALPHA,
            .inv_blend_alpha => vk.VK_BLEND_FACTOR_ONE_MINUS_CONSTANT_ALPHA,
        };
    }

    // Map blend op to Vulkan blend op
    fn mapBlendOp(op: interface.BlendOp) vk.VkBlendOp {
        return switch (op) {
            .add => vk.VK_BLEND_OP_ADD,
            .subtract => vk.VK_BLEND_OP_SUBTRACT,
            .reverse_subtract => vk.VK_BLEND_OP_REVERSE_SUBTRACT,
            .min => vk.VK_BLEND_OP_MIN,
            .max => vk.VK_BLEND_OP_MAX,
        };
    }

    // Map color mask to Vulkan color mask
    fn mapColorMask(mask: interface.ColorMask) vk.VkColorComponentFlags {
        var result: vk.VkColorComponentFlags = 0;
        if (mask.r) result |= vk.VK_COLOR_COMPONENT_R_BIT;
        if (mask.g) result |= vk.VK_COLOR_COMPONENT_G_BIT;
        if (mask.b) result |= vk.VK_COLOR_COMPONENT_B_BIT;
        if (mask.a) result |= vk.VK_COLOR_COMPONENT_A_BIT;
        return result;
    }

    // Map depth stencil state to Vulkan depth stencil state
    fn mapDepthStencilState(state: ?interface.DepthStencilState) vk.VkPipelineDepthStencilStateCreateInfo {
        if (state) |ds| {
            return .{
                .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .depthTestEnable = if (ds.depth_test_enabled) vk.VK_TRUE else vk.VK_FALSE,
                .depthWriteEnable = if (ds.depth_write_enabled) vk.VK_TRUE else vk.VK_FALSE,
                .depthCompareOp = mapCompareFunc(ds.depth_compare),
                .depthBoundsTestEnable = vk.VK_FALSE,
                .stencilTestEnable = if (ds.stencil_enabled) vk.VK_TRUE else vk.VK_FALSE,
                .front = mapStencilOp(ds.front_face),
                .back = mapStencilOp(ds.back_face),
                .minDepthBounds = 0.0,
                .maxDepthBounds = 1.0,
            };
        }

        // Default: depth test and write enabled, less compare, no stencil
        return .{
            .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .depthTestEnable = vk.VK_TRUE,
            .depthWriteEnable = vk.VK_TRUE,
            .depthCompareOp = vk.VK_COMPARE_OP_LESS,
            .depthBoundsTestEnable = vk.VK_FALSE,
            .stencilTestEnable = vk.VK_FALSE,
            .front = .{
                .failOp = vk.VK_STENCIL_OP_KEEP,
                .passOp = vk.VK_STENCIL_OP_KEEP,
                .depthFailOp = vk.VK_STENCIL_OP_KEEP,
                .compareOp = vk.VK_COMPARE_OP_ALWAYS,
                .compareMask = 0xFF,
                .writeMask = 0xFF,
                .reference = 0,
            },
            .back = .{
                .failOp = vk.VK_STENCIL_OP_KEEP,
                .passOp = vk.VK_STENCIL_OP_KEEP,
                .depthFailOp = vk.VK_STENCIL_OP_KEEP,
                .compareOp = vk.VK_COMPARE_OP_ALWAYS,
                .compareMask = 0xFF,
                .writeMask = 0xFF,
                .reference = 0,
            },
            .minDepthBounds = 0.0,
            .maxDepthBounds = 1.0,
        };
    }

    // Map stencil op to Vulkan stencil op state
    fn mapStencilOp(op: interface.StencilOp) vk.VkStencilOpState {
        return .{
            .failOp = mapStencilAction(op.fail),
            .passOp = mapStencilAction(op.pass),
            .depthFailOp = mapStencilAction(op.depth_fail),
            .compareOp = mapCompareFunc(op.compare),
            .compareMask = 0xFF,
            .writeMask = 0xFF,
            .reference = 0,
        };
    }

    // Map stencil action to Vulkan stencil op
    fn mapStencilAction(action: interface.StencilAction) vk.VkStencilOp {
        return switch (action) {
            .keep => vk.VK_STENCIL_OP_KEEP,
            .zero => vk.VK_STENCIL_OP_ZERO,
            .replace => vk.VK_STENCIL_OP_REPLACE,
            .incr_clamp => vk.VK_STENCIL_OP_INCREMENT_AND_CLAMP,
            .decr_clamp => vk.VK_STENCIL_OP_DECREMENT_AND_CLAMP,
            .invert => vk.VK_STENCIL_OP_INVERT,
            .incr_wrap => vk.VK_STENCIL_OP_INCREMENT_AND_WRAP,
            .decr_wrap => vk.VK_STENCIL_OP_DECREMENT_AND_WRAP,
        };
    }

    // Map compare function to Vulkan compare op
    fn mapCompareFunc(func: interface.CompareFunc) vk.VkCompareOp {
        return switch (func) {
            .never => vk.VK_COMPARE_OP_NEVER,
            .less => vk.VK_COMPARE_OP_LESS,
            .equal => vk.VK_COMPARE_OP_EQUAL,
            .less_equal => vk.VK_COMPARE_OP_LESS_OR_EQUAL,
            .greater => vk.VK_COMPARE_OP_GREATER,
            .not_equal => vk.VK_COMPARE_OP_NOT_EQUAL,
            .greater_equal => vk.VK_COMPARE_OP_GREATER_OR_EQUAL,
            .always => vk.VK_COMPARE_OP_ALWAYS,
        };
    }

    fn createRenderTargetImpl(impl: *anyopaque, render_target: *types.RenderTarget) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (self.device) |device| {
            std.log.debug("Creating render target: {}x{} format={}", .{ render_target.width, render_target.height, @intFromEnum(render_target.format) });

            // For now, just mark the render target as valid
            render_target.backend_handle = render_target.id;
            return;
        }

        return interface.GraphicsBackendError.InitializationFailed;
    }

    fn updateBufferImpl(impl: *anyopaque, buffer: *types.Buffer, offset: u64, data: []const u8) interface.GraphicsBackendError!void {
        _ = impl;
        _ = buffer;
        _ = offset;
        _ = data;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn updateTextureImpl(impl: *anyopaque, texture: *types.Texture, region: *const interface.TextureCopyRegion, data: []const u8) interface.GraphicsBackendError!void {
        _ = impl;
        _ = texture;
        _ = region;
        _ = data;
        return interface.GraphicsBackendError.UnsupportedOperation;
    }

    fn destroyTextureImpl(impl: *anyopaque, texture: *types.Texture) void {
        const self: *Self = @ptrCast(@alignCast(impl));

        // Check if this is a swapchain image (which we don't own)
        if (self.swapchain) |swapchain| {
            for (swapchain.images) |img| {
                if (texture.backend_handle == @intFromPtr(img)) {
                    // This is a swapchain image, just free the texture object
                    self.allocator.destroy(texture);
                    return;
                }
            }
        }

        // Get texture from cache by ID
        if (self.textures.getPtr(texture.id)) |img_ptr| {
            // Clean up Vulkan resources
            img_ptr.deinit();
            _ = self.textures.remove(texture.id);
        }
    }

    fn destroyBufferImpl(impl: *anyopaque, buffer: *types.Buffer) void {
        const self: *Self = @ptrCast(@alignCast(impl));

        // Get buffer from cache
        if (self.buffers.getPtr(buffer.id)) |buf_ptr| {
            // Clean up Vulkan resources
            buf_ptr.deinit();
            _ = self.buffers.remove(buffer.id);
        }
    }

    fn destroyShaderImpl(impl: *anyopaque, shader: *types.Shader) void {
        _ = impl;
        _ = shader;
        // No cleanup needed for now as we're not creating actual shader modules yet
    }

    fn destroyRenderTargetImpl(impl: *anyopaque, render_target: *types.RenderTarget) void {
        _ = impl;
        _ = render_target;
    }

    fn createCommandBufferImpl(impl: *anyopaque) interface.GraphicsBackendError!*interface.CommandBuffer {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (self.command_pool == null) {
            return interface.GraphicsBackendError.MissingResource;
        }

        // Allocate a command buffer from the pool
        var vk_cmd_buffer = try self.command_pool.?.allocateCommandBuffer();

        // Create command buffer wrapper
        const cmd = try self.allocator.create(interface.CommandBuffer);
        cmd.* = interface.CommandBuffer{
            .id = @intCast(self.frame_count),
            .backend_handle = @intFromPtr(vk_cmd_buffer),
            .allocator = self.allocator,
            .recording = false,
        };

        return cmd;
    }

    fn beginCommandBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer) interface.GraphicsBackendError!void {
        const self = @as(*Self, @ptrCast(@alignCast(impl)));

        if (cmd.backend_handle == 0) {
            return interface.GraphicsBackendError.InvalidResource;
        }

        // Get the Vulkan command buffer
        const vk_cmd_buffer = @as(vk.VkCommandBuffer, @ptrFromInt(cmd.backend_handle));

        // Begin the command buffer
        const begin_info = vk.VkCommandBufferBeginInfo{
            .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .pNext = null,
            .flags = vk.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
            .pInheritanceInfo = null,
        };

        const result = vk.vkBeginCommandBuffer(vk_cmd_buffer, &begin_info);
        if (result != vk.VK_SUCCESS) {
            return interface.GraphicsBackendError.CommandBufferError;
        }

        // Store current command buffer for later use
        self.current_command_buffer = vk_cmd_buffer;
        cmd.recording = true;
    }

    fn endCommandBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (cmd.backend_handle == 0) {
            return interface.GraphicsBackendError.InvalidResource;
        }

        // Get the Vulkan command buffer
        const vk_cmd_buffer = @as(vk.VkCommandBuffer, @ptrFromInt(cmd.backend_handle));

        // End the command buffer
        const result = vk.vkEndCommandBuffer(vk_cmd_buffer);
        if (result != vk.VK_SUCCESS) {
            return interface.GraphicsBackendError.CommandBufferError;
        }

        self.current_command_buffer = null;
        cmd.recording = false;
    }

    fn submitCommandBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (cmd.backend_handle == 0) {
            return interface.GraphicsBackendError.InvalidResource;
        }

        if (cmd.recording) {
            return interface.GraphicsBackendError.InvalidState;
        }

        if (self.device) |device| {
            // Get the Vulkan command buffer
            const vk_cmd_buffer = @as(vk.VkCommandBuffer, @ptrFromInt(cmd.backend_handle));

            // Create submit info
            const submit_info = vk.VkSubmitInfo{
                .sType = vk.VK_STRUCTURE_TYPE_SUBMIT_INFO,
                .pNext = null,
                .waitSemaphoreCount = 0,
                .pWaitSemaphores = null,
                .pWaitDstStageMask = null,
                .commandBufferCount = 1,
                .pCommandBuffers = &vk_cmd_buffer,
                .signalSemaphoreCount = 0,
                .pSignalSemaphores = null,
            };

            // Submit the command buffer
            const result = vk.vkQueueSubmit(device.graphics_queue, 1, &submit_info, 0);
            if (result != vk.VK_SUCCESS) {
                return interface.GraphicsBackendError.CommandBufferError;
            }

            // Wait for the queue to complete
            _ = vk.vkQueueWaitIdle(device.graphics_queue);

            return;
        }

        return interface.GraphicsBackendError.MissingResource;
    }

    fn beginRenderPassImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, desc: *const interface.RenderPassDesc) interface.GraphicsBackendError!void {
        const self: *Self = @ptrCast(@alignCast(impl));

        if (!cmd.recording) {
            return interface.GraphicsBackendError.InvalidState;
        }

        if (cmd.backend_handle == 0) {
            return interface.GraphicsBackendError.InvalidResource;
        }

        if (self.renderer) |*renderer| {
            // Get the Vulkan command buffer
            const vk_cmd_buffer = @as(vk.VkCommandBuffer, @ptrFromInt(cmd.backend_handle));

            // Get dimensions from color target
            var width: u32 = 1920; // Default fallback
            var height: u32 = 1080; // Default fallback

            if (desc.color_targets.len > 0 and desc.color_targets[0].texture != null) {
                width = desc.color_targets[0].texture.?.width;
                height = desc.color_targets[0].texture.?.height;
            }

            // Set up clear values
            var clear_values: [2]vk.VkClearValue = undefined;

            // Color clear value
            if (desc.clear_color) |color| {
                clear_values[0].color.float32[0] = color[0];
                clear_values[0].color.float32[1] = color[1];
                clear_values[0].color.float32[2] = color[2];
                clear_values[0].color.float32[3] = color[3];
            } else {
                clear_values[0].color.float32[0] = 0.0;
                clear_values[0].color.float32[1] = 0.0;
                clear_values[0].color.float32[2] = 0.0;
                clear_values[0].color.float32[3] = 1.0;
            }

            // Depth/stencil clear value
            clear_values[1].depthStencil.depth = desc.clear_depth;
            clear_values[1].depthStencil.stencil = desc.clear_stencil;

            // Set up render pass begin info
            const render_area = vk.VkRect2D{
                .offset = .{ .x = 0, .y = 0 },
                .extent = .{
                    .width = width,
                    .height = height,
                },
            };

            // Begin render pass
            const begin_info = vk.VkRenderPassBeginInfo{
                .sType = vk.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
                .pNext = null,
                .renderPass = renderer.render_pass.render_pass,
                .framebuffer = renderer.framebuffers.items[0].framebuffer, // TODO: Use proper framebuffer
                .renderArea = render_area,
                .clearValueCount = 2,
                .pClearValues = &clear_values,
            };

            vk.vkCmdBeginRenderPass(vk_cmd_buffer, &begin_info, vk.VK_SUBPASS_CONTENTS_INLINE);
            return;
        }

        return interface.GraphicsBackendError.MissingResource;
    }

    fn endRenderPassImpl(impl: *anyopaque, cmd: *interface.CommandBuffer) interface.GraphicsBackendError!void {
        _ = impl;

        if (!cmd.recording) {
            return interface.GraphicsBackendError.InvalidState;
        }

        if (cmd.backend_handle == 0) {
            return interface.GraphicsBackendError.InvalidResource;
        }

        // Get the Vulkan command buffer
        const vk_cmd_buffer = @as(vk.VkCommandBuffer, @ptrFromInt(cmd.backend_handle));

        // End render pass
        vk.vkCmdEndRenderPass(vk_cmd_buffer);
        return;
    }

    fn setViewportImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, viewport: *const types.Viewport) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = viewport;
    }

    fn setScissorImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, rect: *const types.Viewport) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = rect;
    }

    fn bindPipelineImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, pipeline: *interface.Pipeline) interface.GraphicsBackendError!void {
        _ = impl;

        if (!cmd.recording) {
            return interface.GraphicsBackendError.InvalidState;
        }

        if (cmd.backend_handle == 0) {
            return interface.GraphicsBackendError.InvalidResource;
        }

        // Get the Vulkan command buffer
        const vk_cmd_buffer = @as(vk.VkCommandBuffer, @ptrFromInt(cmd.backend_handle));

        // Get the pipeline from backend handle
        if (pipeline.backend_handle != 0) {
            const pipeline_ptr = @as(*enhanced_backend.Pipeline, @ptrFromInt(pipeline.backend_handle));
            pipeline_ptr.bind(vk_cmd_buffer);
            return;
        }

        return interface.GraphicsBackendError.InvalidResource;
    }

    fn bindVertexBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, slot: u32, buffer: *types.Buffer, offset: u64) interface.GraphicsBackendError!void {
        _ = impl;

        if (!cmd.recording) {
            return interface.GraphicsBackendError.InvalidState;
        }

        if (cmd.backend_handle == 0 or buffer.backend_handle == 0) {
            return interface.GraphicsBackendError.InvalidResource;
        }

        // Get the Vulkan command buffer
        const vk_cmd_buffer = @as(vk.VkCommandBuffer, @ptrFromInt(cmd.backend_handle));

        // Get buffer from handle - note we stored a pointer to the cache entry
        if (buffer.backend_handle != 0) {
            const buffer_ptr = @as(*enhanced_backend.Buffer, @ptrFromInt(buffer.backend_handle));
            const vk_buffer = buffer_ptr.buffer;
            const vk_offset: vk.VkDeviceSize = offset;

            // Bind vertex buffer
            vk.vkCmdBindVertexBuffers(vk_cmd_buffer, slot, 1, &vk_buffer, &vk_offset);
            return;
        }

        return interface.GraphicsBackendError.InvalidResource;
    }

    fn bindIndexBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, buffer: *types.Buffer, offset: u64, format: interface.IndexFormat) interface.GraphicsBackendError!void {
        _ = impl;

        if (!cmd.recording) {
            return interface.GraphicsBackendError.InvalidState;
        }

        if (cmd.backend_handle == 0 or buffer.backend_handle == 0) {
            return interface.GraphicsBackendError.InvalidResource;
        }

        // Get the Vulkan command buffer
        const vk_cmd_buffer = @as(vk.VkCommandBuffer, @ptrFromInt(cmd.backend_handle));

        // Map index format to Vulkan
        const vk_format = switch (format) {
            .uint16 => vk.VK_INDEX_TYPE_UINT16,
            .uint32 => vk.VK_INDEX_TYPE_UINT32,
        };

        // Get buffer from handle
        const buffer_ptr = @as(*enhanced_backend.Buffer, @ptrFromInt(buffer.backend_handle));
        const vk_buffer = buffer_ptr.buffer;

        // Bind index buffer
        vk.vkCmdBindIndexBuffer(vk_cmd_buffer, vk_buffer, offset, vk_format);
        return;
    }

    fn bindTextureImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, slot: u32, texture: *types.Texture) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = slot;
        _ = texture;
    }

    fn bindUniformBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, slot: u32, buffer: *types.Buffer, offset: u64, size: u64) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = slot;
        _ = buffer;
        _ = offset;
        _ = size;
    }

    fn drawImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, draw_cmd: *const interface.DrawCommand) interface.GraphicsBackendError!void {
        _ = impl;

        if (!cmd.recording) {
            return interface.GraphicsBackendError.InvalidState;
        }

        if (cmd.backend_handle == 0) {
            return interface.GraphicsBackendError.InvalidResource;
        }

        // Get the Vulkan command buffer
        const vk_cmd_buffer = @as(vk.VkCommandBuffer, @ptrFromInt(cmd.backend_handle));

        // Draw command
        vk.vkCmdDraw(vk_cmd_buffer, draw_cmd.vertex_count, draw_cmd.instance_count, draw_cmd.first_vertex, draw_cmd.first_instance);

        return;
    }

    fn drawIndexedImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, draw_cmd: *const interface.DrawIndexedCommand) interface.GraphicsBackendError!void {
        _ = impl;

        if (!cmd.recording) {
            return interface.GraphicsBackendError.InvalidState;
        }

        if (cmd.backend_handle == 0) {
            return interface.GraphicsBackendError.InvalidResource;
        }

        // Get the Vulkan command buffer
        const vk_cmd_buffer = @as(vk.VkCommandBuffer, @ptrFromInt(cmd.backend_handle));

        // Draw indexed command
        vk.vkCmdDrawIndexed(vk_cmd_buffer, draw_cmd.index_count, draw_cmd.instance_count, draw_cmd.first_index, draw_cmd.vertex_offset, draw_cmd.first_instance);

        return;
    }

    fn dispatchImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, dispatch_cmd: *const interface.DispatchCommand) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = dispatch_cmd;
    }

    fn copyBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, src: *types.Buffer, dst: *types.Buffer, region: *const interface.BufferCopyRegion) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = src;
        _ = dst;
        _ = region;
    }

    fn copyTextureImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, src: *types.Texture, dst: *types.Texture, region: *const interface.TextureCopyRegion) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = src;
        _ = dst;
        _ = region;
    }

    fn copyBufferToTextureImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, src: *types.Buffer, dst: *types.Texture, region: *const interface.TextureCopyRegion) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = src;
        _ = dst;
        _ = region;
    }

    fn copyTextureToBufferImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, src: *types.Texture, dst: *types.Buffer, region: *const interface.TextureCopyRegion) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = src;
        _ = dst;
        _ = region;
    }

    fn resourceBarrierImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, barriers: []const interface.ResourceBarrier) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = barriers;
    }

    fn getBackendInfoImpl(impl: *anyopaque) interface.BackendInfo {
        const self: *Self = @ptrCast(@alignCast(impl));

        var info = interface.BackendInfo{
            .name = "Vulkan",
            .version = "1.3",
            .vendor = "Khronos Group",
            .device_name = "Unknown Vulkan Device",
            .api_version = 13,
            .driver_version = 0,
            .memory_budget = 0,
            .memory_usage = 0,
            .max_texture_size = 16384,
            .max_render_targets = 8,
            .max_vertex_attributes = 16,
            .max_uniform_buffer_bindings = 16,
            .max_texture_bindings = 32,
            .supports_compute = true,
            .supports_geometry_shaders = true,
            .supports_tessellation = true,
            .supports_raytracing = false,
            .supports_mesh_shaders = false,
            .supports_variable_rate_shading = false,
            .supports_multiview = true,
        };

        if (self.device) |device| {
            // Retrieve device properties
            var props: vk.VkPhysicalDeviceProperties = undefined;
            vk.vkGetPhysicalDeviceProperties(device.physical_device, &props);

            // Update info with actual device data
            info.device_name = std.mem.sliceTo(&props.deviceName, 0);
            info.api_version = props.apiVersion;
            info.driver_version = props.driverVersion;
            info.max_texture_size = props.limits.maxImageDimension2D;

            // Fetch memory information
            var memory_props: vk.VkPhysicalDeviceMemoryProperties = undefined;
            vk.vkGetPhysicalDeviceMemoryProperties(device.physical_device, &memory_props);

            var total_memory: u64 = 0;
            for (0..memory_props.memoryHeapCount) |i| {
                if (memory_props.memoryHeaps[i].flags & vk.VK_MEMORY_HEAP_DEVICE_LOCAL_BIT != 0) {
                    total_memory += memory_props.memoryHeaps[i].size;
                }
            }

            info.memory_budget = @intCast(total_memory / (1024 * 1024)); // Convert to MB

            // Check feature support
            var features2: vk.VkPhysicalDeviceFeatures2 = .{
                .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,
                .pNext = null,
                .features = undefined,
            };

            vk.vkGetPhysicalDeviceFeatures2(device.physical_device, &features2);

            info.supports_geometry_shaders = features2.features.geometryShader == vk.VK_TRUE;
            info.supports_tessellation = features2.features.tessellationShader == vk.VK_TRUE;
        }

        return info;
    }

    fn setDebugNameImpl(impl: *anyopaque, resource: interface.ResourceHandle, name: []const u8) interface.GraphicsBackendError!void {
        _ = impl;
        _ = resource;
        _ = name;
    }

    fn beginDebugGroupImpl(impl: *anyopaque, cmd: *interface.CommandBuffer, name: []const u8) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
        _ = name;
    }

    fn endDebugGroupImpl(impl: *anyopaque, cmd: *interface.CommandBuffer) interface.GraphicsBackendError!void {
        _ = impl;
        _ = cmd;
    }
};
