const std = @import("std");
const swiftui = @import("swiftui.zig");
const color = @import("color.zig");
const view_modifiers = @import("view_modifiers.zig");
const Vec4 = @import("../math/vec4.zig").Vec4;

// Text extensions with view modifiers
pub const TextModifiers = struct {
    text: swiftui.Text,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(text: swiftui.Text, allocator: std.mem.Allocator) Self {
        return Self{
            .text = text,
            .allocator = allocator,
        };
    }

    // Spacing modifiers
    pub fn padding(self: Self, value: f32) view_modifiers.ModifiedView {
        return view_modifiers.modify(self.allocator, self.text.view()).padding(value);
    }

    pub fn paddingAll(self: Self, value: f32) view_modifiers.ModifiedView {
        return view_modifiers.modify(self.allocator, self.text.view()).paddingAll(value);
    }

    pub fn paddingHorizontal(self: Self, value: f32) view_modifiers.ModifiedView {
        return view_modifiers.modify(self.allocator, self.text.view()).paddingHorizontal(value);
    }

    pub fn paddingVertical(self: Self, value: f32) view_modifiers.ModifiedView {
        return view_modifiers.modify(self.allocator, self.text.view()).paddingVertical(value);
    }

    // Appearance modifiers
    pub fn background(self: Self, bg_color: color.Color) view_modifiers.ModifiedView {
        return view_modifiers.modify(self.allocator, self.text.view()).background(bg_color);
    }

    pub fn foregroundColor(self: Self, fg_color: color.Color) view_modifiers.ModifiedView {
        return view_modifiers.modify(self.allocator, self.text.view()).foregroundColor(fg_color);
    }

    pub fn cornerRadius(self: Self, radius: f32) view_modifiers.ModifiedView {
        return view_modifiers.modify(self.allocator, self.text.view()).cornerRadius(radius);
    }

    pub fn shadow(self: Self, radius: f32, x: f32, y: f32) view_modifiers.ModifiedView {
        return view_modifiers.modify(self.allocator, self.text.view()).shadow(radius, x, y);
    }

    pub fn opacity(self: Self, value: f32) view_modifiers.ModifiedView {
        return view_modifiers.modify(self.allocator, self.text.view()).opacity(value);
    }

    pub fn frame(self: Self, width: ?f32, height: ?f32) view_modifiers.ModifiedView {
        return view_modifiers.modify(self.allocator, self.text.view()).frame(width, height);
    }

    pub fn view(self: Self) swiftui.ViewProtocol {
        return self.text.view();
    }
};

// VStack extensions with view modifiers
pub const VStackModifiers = struct {
    vstack: swiftui.VStack,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(vstack: swiftui.VStack, allocator: std.mem.Allocator) Self {
        return Self{
            .vstack = vstack,
            .allocator = allocator,
        };
    }

    // Spacing modifiers
    pub fn padding(self: Self, value: f32) view_modifiers.ModifiedView {
        return view_modifiers.modify(self.allocator, self.vstack.view()).padding(value);
    }

    pub fn paddingAll(self: Self, value: f32) view_modifiers.ModifiedView {
        return view_modifiers.modify(self.allocator, self.vstack.view()).paddingAll(value);
    }

    pub fn paddingHorizontal(self: Self, value: f32) view_modifiers.ModifiedView {
        return view_modifiers.modify(self.allocator, self.vstack.view()).paddingHorizontal(value);
    }

    pub fn paddingVertical(self: Self, value: f32) view_modifiers.ModifiedView {
        return view_modifiers.modify(self.allocator, self.vstack.view()).paddingVertical(value);
    }

    // Appearance modifiers
    pub fn background(self: Self, bg_color: color.Color) view_modifiers.ModifiedView {
        return view_modifiers.modify(self.allocator, self.vstack.view()).background(bg_color);
    }

    pub fn foregroundColor(self: Self, fg_color: color.Color) view_modifiers.ModifiedView {
        return view_modifiers.modify(self.allocator, self.vstack.view()).foregroundColor(fg_color);
    }

    pub fn cornerRadius(self: Self, radius: f32) view_modifiers.ModifiedView {
        return view_modifiers.modify(self.allocator, self.vstack.view()).cornerRadius(radius);
    }

    pub fn frame(self: Self, width: ?f32, height: ?f32) view_modifiers.ModifiedView {
        return view_modifiers.modify(self.allocator, self.vstack.view()).frame(width, height);
    }

    pub fn view(self: Self) swiftui.ViewProtocol {
        return self.vstack.view();
    }
};

// HStack extensions with view modifiers
pub const HStackModifiers = struct {
    hstack: swiftui.HStack,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(hstack: swiftui.HStack, allocator: std.mem.Allocator) Self {
        return Self{
            .hstack = hstack,
            .allocator = allocator,
        };
    }

    // Spacing modifiers
    pub fn padding(self: Self, value: f32) view_modifiers.ModifiedView {
        return view_modifiers.modify(self.allocator, self.hstack.view()).padding(value);
    }

    pub fn paddingAll(self: Self, value: f32) view_modifiers.ModifiedView {
        return view_modifiers.modify(self.allocator, self.hstack.view()).paddingAll(value);
    }

    pub fn paddingHorizontal(self: Self, value: f32) view_modifiers.ModifiedView {
        return view_modifiers.modify(self.allocator, self.hstack.view()).paddingHorizontal(value);
    }

    pub fn paddingVertical(self: Self, value: f32) view_modifiers.ModifiedView {
        return view_modifiers.modify(self.allocator, self.hstack.view()).paddingVertical(value);
    }

    // Appearance modifiers
    pub fn background(self: Self, bg_color: color.Color) view_modifiers.ModifiedView {
        return view_modifiers.modify(self.allocator, self.hstack.view()).background(bg_color);
    }

    pub fn foregroundColor(self: Self, fg_color: color.Color) view_modifiers.ModifiedView {
        return view_modifiers.modify(self.allocator, self.hstack.view()).foregroundColor(fg_color);
    }

    pub fn cornerRadius(self: Self, radius: f32) view_modifiers.ModifiedView {
        return view_modifiers.modify(self.allocator, self.hstack.view()).cornerRadius(radius);
    }

    pub fn frame(self: Self, width: ?f32, height: ?f32) view_modifiers.ModifiedView {
        return view_modifiers.modify(self.allocator, self.hstack.view()).frame(width, height);
    }

    pub fn view(self: Self) swiftui.ViewProtocol {
        return self.hstack.view();
    }
};

// ZStack extensions with view modifiers
pub const ZStackModifiers = struct {
    zstack: swiftui.ZStack,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(zstack: swiftui.ZStack, allocator: std.mem.Allocator) Self {
        return Self{
            .zstack = zstack,
            .allocator = allocator,
        };
    }

    // Spacing modifiers
    pub fn padding(self: Self, value: f32) view_modifiers.ModifiedView {
        return view_modifiers.modify(self.allocator, self.zstack.view()).padding(value);
    }

    pub fn paddingAll(self: Self, value: f32) view_modifiers.ModifiedView {
        return view_modifiers.modify(self.allocator, self.zstack.view()).paddingAll(value);
    }

    pub fn paddingHorizontal(self: Self, value: f32) view_modifiers.ModifiedView {
        return view_modifiers.modify(self.allocator, self.zstack.view()).paddingHorizontal(value);
    }

    pub fn paddingVertical(self: Self, value: f32) view_modifiers.ModifiedView {
        return view_modifiers.modify(self.allocator, self.zstack.view()).paddingVertical(value);
    }

    // Appearance modifiers
    pub fn background(self: Self, bg_color: color.Color) view_modifiers.ModifiedView {
        return view_modifiers.modify(self.allocator, self.zstack.view()).background(bg_color);
    }

    pub fn foregroundColor(self: Self, fg_color: color.Color) view_modifiers.ModifiedView {
        return view_modifiers.modify(self.allocator, self.zstack.view()).foregroundColor(fg_color);
    }

    pub fn cornerRadius(self: Self, radius: f32) view_modifiers.ModifiedView {
        return view_modifiers.modify(self.allocator, self.zstack.view()).cornerRadius(radius);
    }

    pub fn frame(self: Self, width: ?f32, height: ?f32) view_modifiers.ModifiedView {
        return view_modifiers.modify(self.allocator, self.zstack.view()).frame(width, height);
    }

    pub fn view(self: Self) swiftui.ViewProtocol {
        return self.zstack.view();
    }
};

// Helper functions to create modifier instances
pub fn textModifiers(text: swiftui.Text, allocator: std.mem.Allocator) TextModifiers {
    return TextModifiers.init(text, allocator);
}

pub fn vstackModifiers(vstack: swiftui.VStack, allocator: std.mem.Allocator) VStackModifiers {
    return VStackModifiers.init(vstack, allocator);
}

pub fn hstackModifiers(hstack: swiftui.HStack, allocator: std.mem.Allocator) HStackModifiers {
    return HStackModifiers.init(hstack, allocator);
}

pub fn zstackModifiers(zstack: swiftui.ZStack, allocator: std.mem.Allocator) ZStackModifiers {
    return ZStackModifiers.init(zstack, allocator);
}
