const std = @import("std");
const vk = @import("vk.zig");
const enhanced_backend = @import("enhanced_backend.zig");

pub const ResourceUtils = struct {
    pub fn createImage(device: *const enhanced_backend.VulkanDevice, width: u32, height: u32, format: vk.VkFormat, usage: vk.VkImageUsageFlags, memory_properties: vk.VkMemoryPropertyFlags) !enhanced_backend.Image {
        const image_info = vk.VkImageCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
            .imageType = vk.VK_IMAGE_TYPE_2D,
            .extent = vk.VkExtent3D{
                .width = width,
                .height = height,
                .depth = 1,
            },
            .mipLevels = 1,
            .arrayLayers = 1,
            .format = format,
            .tiling = vk.VK_IMAGE_TILING_OPTIMAL,
            .initialLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,
            .usage = usage,
            .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
            .samples = vk.VK_SAMPLE_COUNT_1_BIT,
            .flags = 0,
            .pNext = null,
            .queueFamilyIndexCount = 0,
            .pQueueFamilyIndices = null,
        };

        var image: vk.VkImage = undefined;
        try enhanced_backend.checkVkResult(vk.vkCreateImage(device.device, &image_info, null, &image));
        errdefer vk.vkDestroyImage(device.device, image, null);

        var mem_requirements: vk.VkMemoryRequirements = undefined;
        vk.vkGetImageMemoryRequirements(device.device, image, &mem_requirements);

        const memory_type_index = try enhanced_backend.findMemoryType(device, mem_requirements.memoryTypeBits, memory_properties);
        const alloc_info = vk.VkMemoryAllocateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            .allocationSize = mem_requirements.size,
            .memoryTypeIndex = memory_type_index,
            .pNext = null,
        };

        var memory: vk.VkDeviceMemory = undefined;
        try enhanced_backend.checkVkResult(vk.vkAllocateMemory(device.device, &alloc_info, null, &memory));
        errdefer vk.vkFreeMemory(device.device, memory, null);

        try enhanced_backend.checkVkResult(vk.vkBindImageMemory(device.device, image, memory, 0));

        return enhanced_backend.Image{
            .image = image,
            .memory = memory,
            .width = width,
            .height = height,
            .format = format,
        };
    }

    pub fn createImageView(device: *const enhanced_backend.VulkanDevice, image: vk.VkImage, format: vk.VkFormat, aspect_flags: vk.VkImageAspectFlags) !vk.VkImageView {
        const view_info = vk.VkImageViewCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image = image,
            .viewType = vk.VK_IMAGE_VIEW_TYPE_2D,
            .format = format,
            .components = vk.VkComponentMapping{
                .r = vk.VK_COMPONENT_SWIZZLE_IDENTITY,
                .g = vk.VK_COMPONENT_SWIZZLE_IDENTITY,
                .b = vk.VK_COMPONENT_SWIZZLE_IDENTITY,
                .a = vk.VK_COMPONENT_SWIZZLE_IDENTITY,
            },
            .subresourceRange = vk.VkImageSubresourceRange{
                .aspectMask = aspect_flags,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
            .pNext = null,
            .flags = 0,
        };

        var image_view: vk.VkImageView = undefined;
        try enhanced_backend.checkVkResult(vk.vkCreateImageView(device.device, &view_info, null, &image_view));
        return image_view;
    }

    pub fn createRenderPass(device: *const enhanced_backend.VulkanDevice, color_format: vk.VkFormat, depth_format: vk.VkFormat) !enhanced_backend.RenderPass {
        const color_attachment = vk.VkAttachmentDescription{
            .format = color_format,
            .samples = vk.VK_SAMPLE_COUNT_1_BIT,
            .loadOp = vk.VK_ATTACHMENT_LOAD_OP_CLEAR,
            .storeOp = vk.VK_ATTACHMENT_STORE_OP_STORE,
            .stencilLoadOp = vk.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
            .stencilStoreOp = vk.VK_ATTACHMENT_STORE_OP_DONT_CARE,
            .initialLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,
            .finalLayout = vk.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
            .flags = 0,
        };

        const depth_attachment = vk.VkAttachmentDescription{
            .format = depth_format,
            .samples = vk.VK_SAMPLE_COUNT_1_BIT,
            .loadOp = vk.VK_ATTACHMENT_LOAD_OP_CLEAR,
            .storeOp = vk.VK_ATTACHMENT_STORE_OP_DONT_CARE,
            .stencilLoadOp = vk.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
            .stencilStoreOp = vk.VK_ATTACHMENT_STORE_OP_DONT_CARE,
            .initialLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,
            .finalLayout = vk.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
            .flags = 0,
        };

        const color_ref = vk.VkAttachmentReference{
            .attachment = 0,
            .layout = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        };

        const depth_ref = vk.VkAttachmentReference{
            .attachment = 1,
            .layout = vk.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
        };

        const subpass = vk.VkSubpassDescription{
            .pipelineBindPoint = vk.VK_PIPELINE_BIND_POINT_GRAPHICS,
            .colorAttachmentCount = 1,
            .pColorAttachments = &color_ref,
            .pDepthStencilAttachment = &depth_ref,
            .inputAttachmentCount = 0,
            .pInputAttachments = null,
            .preserveAttachmentCount = 0,
            .pPreserveAttachments = null,
            .pResolveAttachments = null,
            .flags = 0,
        };

        const dependency = vk.VkSubpassDependency{
            .srcSubpass = vk.VK_SUBPASS_EXTERNAL,
            .dstSubpass = 0,
            .srcStageMask = vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | vk.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
            .srcAccessMask = 0,
            .dstStageMask = vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | vk.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
            .dstAccessMask = vk.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT | vk.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
            .dependencyFlags = 0,
        };

        const attachments = [_]vk.VkAttachmentDescription{ color_attachment, depth_attachment };
        const subpasses = [_]vk.VkSubpassDescription{subpass};
        const dependencies = [_]vk.VkSubpassDependency{dependency};

        const render_pass_info = vk.VkRenderPassCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
            .attachmentCount = attachments.len,
            .pAttachments = &attachments,
            .subpassCount = subpasses.len,
            .pSubpasses = &subpasses,
            .dependencyCount = dependencies.len,
            .pDependencies = &dependencies,
            .pNext = null,
            .flags = 0,
        };

        var render_pass: vk.VkRenderPass = undefined;
        try enhanced_backend.checkVkResult(vk.vkCreateRenderPass(device.device, &render_pass_info, null, &render_pass));
        return enhanced_backend.RenderPass{
            .render_pass = render_pass,
        };
    }

    pub fn createFramebuffer(device: *const enhanced_backend.VulkanDevice, render_pass: *const enhanced_backend.RenderPass, color_view: vk.VkImageView, depth_view: vk.VkImageView, width: u32, height: u32) !enhanced_backend.Framebuffer {
        const attachments = [_]vk.VkImageView{ color_view, depth_view };
        const framebuffer_info = vk.VkFramebufferCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            .renderPass = render_pass.render_pass,
            .attachmentCount = attachments.len,
            .pAttachments = &attachments,
            .width = width,
            .height = height,
            .layers = 1,
            .pNext = null,
            .flags = 0,
        };

        var framebuffer: vk.VkFramebuffer = undefined;
        try enhanced_backend.checkVkResult(vk.vkCreateFramebuffer(device.device, &framebuffer_info, null, &framebuffer));
        return enhanced_backend.Framebuffer{
            .framebuffer = framebuffer,
        };
    }
};
