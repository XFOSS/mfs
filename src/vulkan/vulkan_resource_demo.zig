// =============================
// vulkan_resource_demo.zig: Advanced Vulkan Resource Demos
// =============================
// Provides Vulkan-specific resource creation, management, and demo logic for advanced scenarios.
//
// Usage:
//   try vulkan_resource_demo.run_texture_array_demo(app, backend);
//   try vulkan_resource_demo.run_uniform_buffer_demo(app, backend);
//   try vulkan_resource_demo.run_pipeline_material_demo(app, backend);
//

const std = @import("std");
const resource_utils = @import("resource_utils.zig");
const vk = @import("vk.zig");

/// Run the Vulkan texture array demo
pub fn run_texture_array_demo(app: anytype, backend: anytype) !void {
    _ = app;
    _ = backend;
    std.log.info("=== Vulkan Texture Array Demo ===", .{});

    // --- Step 1: Create multiple images for the array ---
    const image_count = 4;
    var images: [image_count]resource_utils.ResourceUtils.Image = undefined;
    for (images, 0..) |*img, i| {
        img.* = try resource_utils.ResourceUtils.createImage(
            backend.device.?,
            128,
            128,
            vk.VkFormat.VK_FORMAT_R8G8B8A8_UNORM,
            vk.VK_IMAGE_USAGE_SAMPLED_BIT | vk.VK_IMAGE_USAGE_TRANSFER_DST_BIT,
            vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
        );
        std.log.info("Created image {} for texture array", .{i});
    }

    // --- Step 2: Create image views for each image ---
    var image_views: [image_count]vk.VkImageView = undefined;
    for (images, 0..) |*img, i| {
        image_views[i] = try resource_utils.ResourceUtils.createImageView(
            backend.device.?,
            img.image,
            img.format,
            vk.VK_IMAGE_ASPECT_COLOR_BIT,
        );
        std.log.info("Created image view {} for texture array", .{i});
    }

    // --- Step 3: Create descriptor set layout for array binding ---
    var layout_binding = vk.VkDescriptorSetLayoutBinding{
        .binding = 0,
        .descriptorType = 1, // VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE
        .descriptorCount = image_count,
        .stageFlags = 0x10, // VK_SHADER_STAGE_FRAGMENT_BIT
        .pImmutableSamplers = null,
    };
    var layout_info = vk.VkDescriptorSetLayoutCreateInfo{
        .sType = vk.VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .bindingCount = 1,
        .pBindings = &layout_binding,
    };
    var descriptor_set_layout: vk.VkDescriptorSetLayout = undefined;
    try vk.vkCreateDescriptorSetLayout(backend.device.?, &layout_info, null, &descriptor_set_layout);
    std.log.info("Created descriptor set layout for texture array", .{});

    // --- Step 4: Allocate descriptor pool and set ---
    var pool_size = vk.VkDescriptorPoolSize{
        .type = 1, // VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE
        .descriptorCount = image_count,
    };
    var pool_info = vk.VkDescriptorPoolCreateInfo{
        .sType = vk.VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .maxSets = 1,
        .poolSizeCount = 1,
        .pPoolSizes = &pool_size,
    };
    var descriptor_pool: vk.VkDescriptorPool = undefined;
    try vk.vkCreateDescriptorPool(backend.device.?, &pool_info, null, &descriptor_pool);
    std.log.info("Created descriptor pool for texture array", .{});

    var alloc_info = vk.VkDescriptorSetAllocateInfo{
        .sType = vk.VkStructureType.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .pNext = null,
        .descriptorPool = descriptor_pool,
        .descriptorSetCount = 1,
        .pSetLayouts = &descriptor_set_layout,
    };
    var descriptor_set: vk.VkDescriptorSet = undefined;
    try vk.vkAllocateDescriptorSets(backend.device.?, &alloc_info, &descriptor_set);
    std.log.info("Allocated descriptor set for texture array", .{});

    // --- Step 5: Write image views to descriptor set ---
    var image_infos: [image_count]vk.VkDescriptorImageInfo = undefined;
    for (image_infos, 0..) |*info, i| {
        info.* = vk.VkDescriptorImageInfo{
            .sampler = null,
            .imageView = image_views[i],
            .imageLayout = 5, // VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL
        };
    }
    var write = vk.VkWriteDescriptorSet{
        .sType = vk.VkStructureType.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .pNext = null,
        .dstSet = descriptor_set,
        .dstBinding = 0,
        .dstArrayElement = 0,
        .descriptorCount = image_count,
        .descriptorType = 1, // VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE
        .pImageInfo = &image_infos[0],
        .pBufferInfo = null,
        .pTexelBufferView = null,
    };
    vk.vkUpdateDescriptorSets(backend.device.?, 1, &write, 0, null);
    std.log.info("Wrote image views to descriptor set for texture array", .{});

    // --- Step 6: Provide minimal shader string for sampling from the array ---
    const shader_code =
        "#version 450\n"
        "layout(set = 0, binding = 0) uniform texture2D textures[4];\n"
        "layout(location = 0) in vec2 fragUV;\n"
        "layout(location = 0) out vec4 outColor;\n"
        "layout(push_constant) uniform PC { int imgIdx; } pc;\n"
        "void main() { outColor = texture(sampler2D(textures[pc.imgIdx], sampler), fragUV); }\n";
    std.log.info("Shader for texture array:\n{s}", .{shader_code});

    // --- Step 7: (Stub) Pipeline and draw call would go here ---
    std.log.info("(Stub) Pipeline creation and draw call would go here", .{});

    // --- Step 8: Cleanup ---
    vk.vkDestroyDescriptorPool(backend.device.?, descriptor_pool, null);
    vk.vkDestroyDescriptorSetLayout(backend.device.?, descriptor_set_layout, null);
    for (images, 0..) |*img, i| {
        _ = image_views[i];
        img.deinit(backend.device.?);
        std.log.info("Cleaned up image {} for texture array", .{i});
    }
    std.log.info("✓ Vulkan Texture Array Demo complete", .{});
}

/// Run the Vulkan uniform buffer update demo
pub fn run_uniform_buffer_demo(app: anytype, backend: anytype) !void {
    _ = app;
    _ = backend;
    std.log.info("=== Vulkan Uniform Buffer Update Demo ===", .{});
    // TODO: Implement actual Vulkan uniform buffer creation, update, and binding
    std.log.info("(Stub) Created and updated Vulkan uniform buffer.", .{});
}

/// Run the Vulkan pipeline/material system demo
pub fn run_pipeline_material_demo(app: anytype, backend: anytype) !void {
    _ = app;
    _ = backend;
    std.log.info("=== Vulkan Pipeline/Material System Demo ===", .{});
    // TODO: Implement actual Vulkan pipeline, descriptor set, and material binding
    std.log.info("(Stub) Created Vulkan pipeline and bound material.", .{});
}
