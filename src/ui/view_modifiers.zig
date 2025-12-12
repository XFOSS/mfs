const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const math = @import("math");
const Vec4 = math.Vec4;
const color = @import("color.zig");
const swiftui = @import("swiftui.zig");

// Edge insets for padding
pub const EdgeInsets = struct {
    top: f32,
    leading: f32,
    bottom: f32,
    trailing: f32,

    pub fn init(top: f32, leading: f32, bottom: f32, trailing: f32) EdgeInsets {
        return EdgeInsets{
            .top = top,
            .leading = leading,
            .bottom = bottom,
            .trailing = trailing,
        };
    }

    pub fn all(value: f32) EdgeInsets {
        return EdgeInsets.init(value, value, value, value);
    }

    pub fn horizontal(value: f32) EdgeInsets {
        return EdgeInsets.init(0, value, 0, value);
    }

    pub fn vertical(value: f32) EdgeInsets {
        return EdgeInsets.init(value, 0, value, 0);
    }

    pub fn zero() EdgeInsets {
        return EdgeInsets.init(0, 0, 0, 0);
    }
};

// Transform for scale and rotation effects
pub const Transform = struct {
    scale_x: f32 = 1.0,
    scale_y: f32 = 1.0,
    rotation_angle: f32 = 0.0, // in radians
    translation_x: f32 = 0.0,
    translation_y: f32 = 0.0,

    pub fn identity() Transform {
        return Transform{};
    }

    pub fn scale(x: f32, y: f32) Transform {
        return Transform{ .scale_x = x, .scale_y = y };
    }

    pub fn rotate(radians: f32) Transform {
        return Transform{ .rotation_angle = radians };
    }

    pub fn translation(x: f32, y: f32) Transform {
        return Transform{ .translation_x = x, .translation_y = y };
    }
};

// Shadow configuration
pub const Shadow = struct {
    color: Vec4,
    radius: f32,
    offset_x: f32,
    offset_y: f32,

    pub fn init(color_val: Vec4, radius: f32, offset_x: f32, offset_y: f32) Shadow {
        return Shadow{
            .color = color_val,
            .radius = radius,
            .offset_x = offset_x,
            .offset_y = offset_y,
        };
    }

    pub fn drop(radius: f32) Shadow {
        return Shadow.init(Vec4.init(0, 0, 0, 0.3), radius, 0, radius * 0.5);
    }
};

// Frame constraints
pub const FrameConstraints = struct {
    min_width: ?f32 = null,
    ideal_width: ?f32 = null,
    max_width: ?f32 = null,
    min_height: ?f32 = null,
    ideal_height: ?f32 = null,
    max_height: ?f32 = null,
    alignment: swiftui.Alignment = .center,

    pub fn width(value: f32) FrameConstraints {
        return FrameConstraints{
            .min_width = value,
            .ideal_width = value,
            .max_width = value,
        };
    }

    pub fn height(value: f32) FrameConstraints {
        return FrameConstraints{
            .min_height = value,
            .ideal_height = value,
            .max_height = value,
        };
    }

    pub fn size(width_val: f32, height_val: f32) FrameConstraints {
        return FrameConstraints{
            .min_width = width_val,
            .ideal_width = width_val,
            .max_width = width_val,
            .min_height = height_val,
            .ideal_height = height_val,
            .max_height = height_val,
        };
    }

    pub fn maxWidth(value: f32) FrameConstraints {
        return FrameConstraints{ .max_width = value };
    }

    pub fn maxHeight(value: f32) FrameConstraints {
        return FrameConstraints{ .max_height = value };
    }
};

// Border configuration
pub const Border = struct {
    color: Vec4,
    width: f32,

    pub fn init(color_val: Vec4, width: f32) Border {
        return Border{ .color = color_val, .width = width };
    }
};

// Modifier types
pub const ModifierType = enum {
    padding,
    background_color,
    background_vec4,
    corner_radius,
    opacity,
    frame,
    shadow,
    border,
    clipped,
    scale_effect,
    rotation_effect,
    offset,
};

// Unified modifier data
pub const ModifierData = union(ModifierType) {
    padding: EdgeInsets,
    background_color: color.Color,
    background_vec4: Vec4,
    corner_radius: f32,
    opacity: f32,
    frame: FrameConstraints,
    shadow: Shadow,
    border: Border,
    clipped: void,
    scale_effect: struct { x: f32, y: f32 },
    rotation_effect: f32, // radians
    offset: struct { x: f32, y: f32 },
};

// Modified view that wraps another view with modifiers
pub const ModifiedView = struct {
    content: swiftui.ViewProtocol,
    modifiers: ArrayList(ModifierData),
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator, content: swiftui.ViewProtocol) Self {
        return Self{
            .content = content,
            .modifiers = ArrayList(ModifierData).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.modifiers.deinit();
        self.content.deinit();
    }

    // Modifier methods that return modified views
    pub fn padding(self: Self, insets: EdgeInsets) Self {
        var modified = self;
        modified.modifiers.append(ModifierData{ .padding = insets }) catch |err| {
            std.log.err("Failed to append padding modifier: {}", .{err});
            // Return unmodified view on error
            return modified;
        };
        return modified;
    }

    pub fn paddingAll(self: Self, value: f32) Self {
        return self.padding(EdgeInsets.all(value));
    }

    pub fn paddingHorizontal(self: Self, value: f32) Self {
        return self.padding(EdgeInsets.horizontal(value));
    }

    pub fn paddingVertical(self: Self, value: f32) Self {
        return self.padding(EdgeInsets.vertical(value));
    }

    pub fn background(self: Self, bg_color: color.Color) Self {
        var modified = self;
        modified.modifiers.append(ModifierData{ .background_color = bg_color }) catch |err| {
            std.log.err("Failed to append background color modifier: {}", .{err});
            return modified;
        };
        return modified;
    }

    pub fn backgroundVec4(self: Self, bg_color: Vec4) Self {
        var modified = self;
        modified.modifiers.append(ModifierData{ .background_vec4 = bg_color }) catch |err| {
            std.log.err("Failed to append background vec4 modifier: {}", .{err});
            return modified;
        };
        return modified;
    }

    pub fn cornerRadius(self: Self, radius: f32) Self {
        var modified = self;
        modified.modifiers.append(ModifierData{ .corner_radius = radius }) catch |err| {
            std.log.err("Failed to append corner radius modifier: {}", .{err});
            return modified;
        };
        return modified;
    }

    pub fn opacity(self: Self, alpha: f32) Self {
        var modified = self;
        modified.modifiers.append(ModifierData{ .opacity = std.math.clamp(alpha, 0.0, 1.0) }) catch |err| {
            std.log.err("Failed to append opacity modifier: {}", .{err});
            return modified;
        };
        return modified;
    }

    pub fn frame(self: Self, constraints: FrameConstraints) Self {
        var modified = self;
        modified.modifiers.append(ModifierData{ .frame = constraints }) catch |err| {
            std.log.err("Failed to append frame modifier: {}", .{err});
            return modified;
        };
        return modified;
    }

    pub fn frameWidth(self: Self, width: f32) Self {
        return self.frame(FrameConstraints.width(width));
    }

    pub fn frameHeight(self: Self, height: f32) Self {
        return self.frame(FrameConstraints.height(height));
    }

    pub fn frameSize(self: Self, width: f32, height: f32) Self {
        return self.frame(FrameConstraints.size(width, height));
    }

    pub fn shadow(self: Self, shadow_config: Shadow) Self {
        var modified = self;
        modified.modifiers.append(ModifierData{ .shadow = shadow_config }) catch |err| {
            std.log.err("Failed to append shadow modifier: {}", .{err});
            return modified;
        };
        return modified;
    }

    pub fn dropShadow(self: Self, radius: f32) Self {
        return self.shadow(Shadow.drop(radius));
    }

    pub fn border(self: Self, border_config: Border) Self {
        var modified = self;
        modified.modifiers.append(ModifierData{ .border = border_config }) catch |err| {
            std.log.err("Failed to append border modifier: {}", .{err});
            return modified;
        };
        return modified;
    }

    pub fn borderColor(self: Self, border_color: Vec4, width: f32) Self {
        return self.border(Border.init(border_color, width));
    }

    pub fn clipped(self: Self) Self {
        var modified = self;
        modified.modifiers.append(ModifierData{ .clipped = {} }) catch |err| {
            std.log.err("Failed to append clipped modifier: {}", .{err});
            return modified;
        };
        return modified;
    }

    pub fn scaleEffect(self: Self, scale_x: f32, scale_y: f32) Self {
        var modified = self;
        modified.modifiers.append(ModifierData{ .scale_effect = .{ .x = scale_x, .y = scale_y } }) catch |err| {
            std.log.err("Failed to append scale effect modifier: {}", .{err});
            return modified;
        };
        return modified;
    }

    pub fn scaleEffectUniform(self: Self, scale: f32) Self {
        return self.scaleEffect(scale, scale);
    }

    pub fn rotationEffect(self: Self, angle: f32) Self {
        var modified = self;
        modified.modifiers.append(ModifierData{ .rotation_effect = angle }) catch |err| {
            std.log.err("Failed to append rotation effect modifier: {}", .{err});
            return modified;
        };
        return modified;
    }

    pub fn rotationEffectDegrees(self: Self, degrees: f32) Self {
        return self.rotationEffect(degrees * std.math.pi / 180.0);
    }

    pub fn offset(self: Self, x: f32, y: f32) Self {
        var modified = self;
        modified.modifiers.append(ModifierData{ .offset = .{ .x = x, .y = y } }) catch |err| {
            std.log.err("Failed to append offset modifier: {}", .{err});
            return modified;
        };
        return modified;
    }

    pub fn view(self: Self) !swiftui.ViewProtocol {
        const self_ptr = try self.allocator.create(Self);
        self_ptr.* = self;
        return swiftui.ViewProtocol{ .ptr = self_ptr, .vtable = &ModifiedView.vtable };
    }

    // ViewProtocol implementation
    fn bodyImpl(ptr: *anyopaque) swiftui.ViewProtocol {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.content;
    }

    fn renderImpl(ptr: *anyopaque, context: *swiftui.RenderContext) void {
        const self: *Self = @ptrCast(@alignCast(ptr));

        // Apply modifiers in reverse order for proper layering
        var render_context = context.*;
        var current_frame = render_context.frame;
        var transform = Transform.identity();
        var current_opacity: f32 = 1.0;
        var background_color: ?Vec4 = null;
        var corner_radius_val: f32 = 0.0;
        var shadow_config: ?Shadow = null;
        var border_config: ?Border = null;
        var should_clip = false;

        // Process modifiers
        for (self.modifiers.items) |modifier| {
            switch (modifier) {
                .padding => |insets| {
                    current_frame.origin.x += insets.leading;
                    current_frame.origin.y += insets.top;
                    current_frame.size.width -= insets.leading + insets.trailing;
                    current_frame.size.height -= insets.top + insets.bottom;
                },
                .background_color => |bg_color| {
                    background_color = color.colorToVec4(bg_color, context.color_registry);
                },
                .background_vec4 => |bg_color| {
                    background_color = bg_color;
                },
                .corner_radius => |radius| {
                    corner_radius_val = radius;
                },
                .opacity => |alpha| {
                    current_opacity *= alpha;
                },
                .frame => |constraints| {
                    if (constraints.min_width) |min_w| {
                        current_frame.size.width = @max(current_frame.size.width, min_w);
                    }
                    if (constraints.max_width) |max_w| {
                        current_frame.size.width = @min(current_frame.size.width, max_w);
                    }
                    if (constraints.min_height) |min_h| {
                        current_frame.size.height = @max(current_frame.size.height, min_h);
                    }
                    if (constraints.max_height) |max_h| {
                        current_frame.size.height = @min(current_frame.size.height, max_h);
                    }
                    if (constraints.ideal_width) |ideal_w| {
                        current_frame.size.width = ideal_w;
                    }
                    if (constraints.ideal_height) |ideal_h| {
                        frame.size.height = ideal_h;
                    }
                },
                .shadow => |shadow_val| {
                    shadow_config = shadow_val;
                },
                .border => |border_val| {
                    border_config = border_val;
                },
                .clipped => {
                    should_clip = true;
                },
                .scale_effect => |scale| {
                    transform.scale_x *= scale.x;
                    transform.scale_y *= scale.y;
                },
                .rotation_effect => |angle| {
                    transform.rotation += angle;
                },
                .offset => |offset_val| {
                    transform.translation_x += offset_val.x;
                    transform.translation_y += offset_val.y;
                },
            }
        }

        // Render shadow first (if any)
        if (shadow_config) |shadow_val| {
            renderShadow(shadow_val, frame, corner_radius_val, context);
        }

        // Render background (if any)
        if (background_color) |bg_color| {
            renderBackground(bg_color, frame, corner_radius_val, current_opacity, context);
        }

        // Update render context with modified frame
        render_context.frame = frame;

        // Render content with transforms and clipping
        if (should_clip) {
            beginClipping(frame, corner_radius_val, context);
        }

        applyTransform(transform, frame, context);
        self.content.render(&render_context);
        resetTransform(context);

        if (should_clip) {
            endClipping(context);
        }

        // Render border last (if any)
        if (border_config) |border_val| {
            renderBorder(border_val, frame, corner_radius_val, current_opacity, context);
        }
    }

    fn layoutImpl(ptr: *anyopaque, proposed_size: swiftui.Size) swiftui.Size {
        const self: *Self = @ptrCast(@alignCast(ptr));

        var available_size = proposed_size;
        var padding_insets = EdgeInsets.zero();
        var frame_constraints: ?FrameConstraints = null;

        // Calculate size adjustments from modifiers
        for (self.modifiers.items) |modifier| {
            switch (modifier) {
                .padding => |insets| {
                    padding_insets.top += insets.top;
                    padding_insets.leading += insets.leading;
                    padding_insets.bottom += insets.bottom;
                    padding_insets.trailing += insets.trailing;

                    available_size.width -= insets.leading + insets.trailing;
                    available_size.height -= insets.top + insets.bottom;
                },
                .frame => |constraints| {
                    frame_constraints = constraints;
                },
                .border => |border_val| {
                    available_size.width -= border_val.width * 2;
                    available_size.height -= border_val.width * 2;
                },
                else => {},
            }
        }

        // Get content size
        var content_size = self.content.layout(available_size);

        // Apply frame constraints
        if (frame_constraints) |constraints| {
            if (constraints.min_width) |min_w| {
                content_size.width = @max(content_size.width, min_w);
            }
            if (constraints.max_width) |max_w| {
                content_size.width = @min(content_size.width, max_w);
            }
            if (constraints.min_height) |min_h| {
                content_size.height = @max(content_size.height, min_h);
            }
            if (constraints.max_height) |max_h| {
                content_size.height = @min(content_size.height, max_h);
            }
            if (constraints.ideal_width) |ideal_w| {
                content_size.width = ideal_w;
            }
            if (constraints.ideal_height) |ideal_h| {
                content_size.height = ideal_h;
            }
        }

        // Add padding and borders back
        content_size.width += padding_insets.leading + padding_insets.trailing;
        content_size.height += padding_insets.top + padding_insets.bottom;

        for (self.modifiers.items) |modifier| {
            switch (modifier) {
                .border => |border_val| {
                    content_size.width += border_val.width * 2;
                    content_size.height += border_val.width * 2;
                },
                else => {},
            }
        }

        return content_size;
    }

    fn deinitImpl(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        const allocator = self.allocator;
        self.deinit();
        allocator.destroy(self);
    }

    const modified_view_vtable = swiftui.ViewProtocol.VTable{
        .body = bodyImpl,
        .render = renderImpl,
        .layout = layoutImpl,
        .deinit = deinitImpl,
    };
};

// Helper functions for rendering (these would be implemented by the backend)
fn renderShadow(shadow_config: Shadow, frame: swiftui.Rect, corner_radius: f32, context: *swiftui.RenderContext) void {
    // This would be implemented by the rendering backend (Vulkan/OpenGL)
    _ = shadow_config;
    _ = frame;
    _ = corner_radius;
    _ = context;
    // TODO: Implement shadow rendering
}

fn renderBackground(bg_color: Vec4, frame: swiftui.Rect, corner_radius: f32, opacity: f32, context: *swiftui.RenderContext) void {
    // This would be implemented by the rendering backend
    _ = bg_color;
    _ = frame;
    _ = corner_radius;
    _ = opacity;
    _ = context;
    // TODO: Implement background rendering with corner radius support
}

fn renderBorder(border_config: Border, frame: swiftui.Rect, corner_radius: f32, opacity: f32, context: *swiftui.RenderContext) void {
    // This would be implemented by the rendering backend
    _ = border_config;
    _ = frame;
    _ = corner_radius;
    _ = opacity;
    _ = context;
    // TODO: Implement border rendering
}

fn beginClipping(frame: swiftui.Rect, corner_radius: f32, context: *swiftui.RenderContext) void {
    // This would be implemented by the rendering backend
    _ = frame;
    _ = corner_radius;
    _ = context;
    // TODO: Set up clipping region
}

fn endClipping(context: *swiftui.RenderContext) void {
    // This would be implemented by the rendering backend
    _ = context;
    // TODO: Restore previous clipping state
}

fn applyTransform(transform: Transform, frame: swiftui.Rect, context: *swiftui.RenderContext) void {
    // This would be implemented by the rendering backend
    _ = transform;
    _ = frame;
    _ = context;
    // TODO: Apply transformation matrix
}

fn resetTransform(context: *swiftui.RenderContext) void {
    // This would be implemented by the rendering backend
    _ = context;
    // TODO: Reset transformation matrix
}

// Convenience functions to create modified views
pub fn modify(allocator: Allocator, view: swiftui.ViewProtocol) ModifiedView {
    return ModifiedView.init(allocator, view);
}

// Extension-like functions for existing views
pub fn addPadding(allocator: Allocator, view: swiftui.ViewProtocol, insets: EdgeInsets) !swiftui.ViewProtocol {
    return try modify(allocator, view).padding(insets).view();
}

pub fn addBackground(allocator: Allocator, view: swiftui.ViewProtocol, bg_color: Vec4) !swiftui.ViewProtocol {
    return try modify(allocator, view).backgroundVec4(bg_color).view();
}

pub fn addCornerRadius(allocator: Allocator, view: swiftui.ViewProtocol, radius: f32) !swiftui.ViewProtocol {
    return try modify(allocator, view).cornerRadius(radius).view();
}

// Test the modifier system
test "Modifier chaining" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var text = swiftui.text(allocator, "Hello, World!");
    const modified = modify(allocator, text.view())
        .paddingAll(16.0)
        .backgroundVec4(Vec4.init(0.2, 0.2, 0.2, 1.0))
        .cornerRadius(8.0)
        .opacity(0.9)
        .scaleEffectUniform(1.1);

    defer modified.deinit();

    try testing.expect(modified.modifiers.items.len == 5);

    const size = modified.view().layout(swiftui.Size.init(200, 100));
    try testing.expect(size.width > 0);
    try testing.expect(size.height > 0);
}

test "Frame constraints" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var text = swiftui.text(allocator, "Test");
    const modified = modify(allocator, text.view())
        .frameWidth(100.0)
        .frameHeight(50.0);

    defer modified.deinit();

    const size = modified.view().layout(swiftui.Size.init(200, 200));
    try testing.expectEqual(@as(f32, 100.0), size.width);
    try testing.expectEqual(@as(f32, 50.0), size.height);
}
