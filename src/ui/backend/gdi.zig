const std = @import("std");
const Allocator = std.mem.Allocator;
const interface = @import("interface.zig");
const ArrayList = std.ArrayList;

// Windows API types
const HWND = *opaque {};
const HDC = *opaque {};
const HBRUSH = *opaque {};
const HPEN = *opaque {};
const HFONT = *opaque {};
const COLORREF = u32;
const HBITMAP = *opaque {};
const RECT = extern struct {
    left: i32,
    top: i32,
    right: i32,
    bottom: i32,
};

// Windows API constants
const DT_LEFT = 0x00000000;
const DT_CENTER = 0x00000001;
const DT_RIGHT = 0x00000002;
const DT_VCENTER = 0x00000004;
const DT_SINGLELINE = 0x00000020;
const TRANSPARENT = 1;
const PS_SOLID = 0;
const DEFAULT_CHARSET = 1;
const OUT_TT_PRECIS = 4;
const CLIP_DEFAULT_PRECIS = 0;
const PROOF_QUALITY = 2;
const VARIABLE_PITCH = 2;
const FF_DONTCARE = 0;
const FW_NORMAL = 400;
const FW_BOLD = 700;

// External drawing functions
extern "gdi32" fn CreateSolidBrush(color: COLORREF) callconv(.C) HBRUSH;
extern "gdi32" fn CreatePen(style: i32, width: i32, color: COLORREF) callconv(.C) HPEN;
extern "gdi32" fn CreateFontW(height: i32, width: i32, escapement: i32, orientation: i32, weight: i32, italic: u32, underline: u32, strikeout: u32, charset: u32, out_precision: u32, clip_precision: u32, quality: u32, pitch_and_family: u32, face_name: [*:0]const u16) callconv(.C) HFONT;
extern "gdi32" fn SelectObject(hdc: HDC, obj: *opaque {}) callconv(.C) *opaque {};
extern "gdi32" fn DeleteObject(obj: *opaque {}) callconv(.C) i32;
extern "gdi32" fn Rectangle(hdc: HDC, left: i32, top: i32, right: i32, bottom: i32) callconv(.C) i32;
extern "gdi32" fn RoundRect(hdc: HDC, left: i32, top: i32, right: i32, bottom: i32, width: i32, height: i32) callconv(.C) i32;
extern "gdi32" fn Ellipse(hdc: HDC, left: i32, top: i32, right: i32, bottom: i32) callconv(.C) i32;
extern "gdi32" fn SetTextColor(hdc: HDC, color: COLORREF) callconv(.C) COLORREF;
extern "gdi32" fn SetBkMode(hdc: HDC, mode: i32) callconv(.C) i32;
extern "gdi32" fn GetTextExtentPoint32W(hdc: HDC, string: [*:0]const u16, count: i32, size: *SIZE) callconv(.C) i32;
extern "gdi32" fn CreateCompatibleDC(hdc: HDC) callconv(.C) HDC;
extern "gdi32" fn CreateCompatibleBitmap(hdc: HDC, width: i32, height: i32) callconv(.C) HBITMAP;
extern "gdi32" fn BitBlt(hdcDest: HDC, x: i32, y: i32, width: i32, height: i32, hdcSrc: HDC, xSrc: i32, ySrc: i32, rop: u32) callconv(.C) i32;
extern "gdi32" fn SetDIBits(hdc: HDC, hbm: HBITMAP, start: u32, cLines: u32, lpBits: *const anyopaque, lpbmi: *const BITMAPINFO, colorUse: u32) callconv(.C) i32;
extern "gdi32" fn CreateDIBSection(hdc: HDC, pbmi: *const BITMAPINFO, usage: u32, ppvBits: *?*anyopaque, hSection: ?*anyopaque, offset: u32) callconv(.C) HBITMAP;
extern "user32" fn DrawTextW(hdc: HDC, text: [*:0]const u16, count: i32, rect: *RECT, format: u32) callconv(.C) i32;
extern "user32" fn FillRect(hdc: HDC, rect: *const RECT, brush: HBRUSH) callconv(.C) i32;
extern "user32" fn GetDC(hwnd: HWND) callconv(.C) HDC;
extern "user32" fn ReleaseDC(hwnd: HWND, hdc: HDC) callconv(.C) i32;
extern "user32" fn InvalidateRect(hwnd: HWND, lpRect: ?*const RECT, bErase: i32) callconv(.C) i32;

// Additional Windows structures
const SIZE = extern struct {
    cx: i32,
    cy: i32,
};

const BITMAPINFOHEADER = extern struct {
    biSize: u32,
    biWidth: i32,
    biHeight: i32,
    biPlanes: u16,
    biBitCount: u16,
    biCompression: u32,
    biSizeImage: u32,
    biXPelsPerMeter: i32,
    biYPelsPerMeter: i32,
    biClrUsed: u32,
    biClrImportant: u32,
};

const BITMAPINFO = extern struct {
    bmiHeader: BITMAPINFOHEADER,
    bmiColors: [1]u32,
};

const DIB_RGB_COLORS = 0;
const BI_RGB = 0;
const SRCCOPY = 0x00CC0020;

const ClipRect = struct {
    rect: RECT,
};

// GDI Backend context
pub const GdiContext = struct {
    allocator: Allocator,
    hwnd: HWND,
    hdc: HDC,
    width: u32 = 0,
    height: u32 = 0,
    clip_stack: ArrayList(ClipRect),
    current_clip_rect: ?RECT = null,
    memDC: ?HDC = null,
    memBitmap: ?HBITMAP = null,
    oldBitmap: ?HBITMAP = null,
    last_error: ?[]const u8 = null,

    const Self = @This();

    pub fn init(allocator: Allocator, window_handle: usize) !*Self {
        const ctx = try allocator.create(Self);
        ctx.last_error = null;
        const hwnd = @as(HWND, @ptrFromInt(window_handle));
        const hdc = GetDC(hwnd);

        if (hdc == null) return error.FailedToGetDC;

        ctx.* = Self{
            .allocator = allocator,
            .hwnd = hwnd,
            .hdc = hdc,
            .clip_stack = ArrayList(ClipRect).init(allocator),
        };
        return ctx;
    }

    pub fn deinit(self: *Self) void {
        if (self.hdc != null) {
            _ = ReleaseDC(self.hwnd, self.hdc);
        }

        if (self.memDC) |mem_dc| {
            if (self.oldBitmap) |old_bitmap| {
                _ = SelectObject(mem_dc, old_bitmap);
            }
            if (self.memBitmap) |mem_bitmap| {
                _ = DeleteObject(mem_bitmap);
            }
            _ = DeleteObject(mem_dc);
        }

        self.clip_stack.deinit();
        self.allocator.destroy(self);
    }

    pub fn beginFrame(self: *Self, width: u32, height: u32) void {
        self.width = width;
        self.height = height;

        // Create or recreate double buffer if needed
        if (self.memDC == null or self.width != width or self.height != height) {
            self.cleanupGraphicsResources();
            self.createDoubleBuffer();
        }

        // Reset clip stack
        self.clip_stack.clearRetainingCapacity();
        self.current_clip_rect = null;
    }

    fn cleanupGraphicsResources(self: *Self) void {
        if (self.memDC) |mem_dc| {
            if (self.oldBitmap) |old_bitmap| {
                _ = SelectObject(mem_dc, old_bitmap);
            }
            if (self.memBitmap) |mem_bitmap| {
                _ = DeleteObject(mem_bitmap);
            }
            _ = DeleteObject(mem_dc);
            self.memDC = null;
            self.memBitmap = null;
            self.oldBitmap = null;
        }
    }

    fn createDoubleBuffer(self: *Self) void {
        self.memDC = CreateCompatibleDC(self.hdc);
        if (self.memDC) |mem_dc| {
            self.memBitmap = CreateCompatibleBitmap(self.hdc, @intCast(self.width), @intCast(self.height));
            if (self.memBitmap) |mem_bitmap| {
                self.oldBitmap = @ptrCast(SelectObject(mem_dc, mem_bitmap));
            }
        }
    }

    pub fn endFrame(self: *Self) void {
        if (self.memDC) |mem_dc| {
            _ = BitBlt(self.hdc, 0, 0, @intCast(self.width), @intCast(self.height), mem_dc, 0, 0, SRCCOPY);
        }

        // Trigger a window repaint
        _ = InvalidateRect(self.hwnd, null, 0);
    }

    pub fn executeDrawCommands(self: *Self, commands: []const interface.DrawCommand) void {
        for (commands) |cmd| {
            self.executeDrawCommand(cmd);
        }
    }

    fn executeDrawCommand(self: *Self, cmd: interface.DrawCommand) void {
        const hdc = if (self.memDC) |mem_dc| mem_dc else self.hdc;

        switch (cmd) {
            .clear => |color| {
                const brush = CreateSolidBrush(colorToColorref(color));
                var rc = RECT{ .left = 0, .top = 0, .right = @intCast(self.width), .bottom = @intCast(self.height) };
                _ = FillRect(hdc, &rc, brush);
                _ = DeleteObject(brush);
            },
            .rect => |rect_data| {
                const brush = CreateSolidBrush(colorToColorref(rect_data.color));
                const pen = if (rect_data.border_width > 0)
                    CreatePen(PS_SOLID, @intFromFloat(rect_data.border_width), colorToColorref(rect_data.border_color))
                else
                    CreatePen(PS_SOLID, 0, colorToColorref(rect_data.color));

                const old_brush = SelectObject(hdc, brush);
                const old_pen = SelectObject(hdc, pen);

                const x: i32 = @intFromFloat(rect_data.rect.x);
                const y: i32 = @intFromFloat(rect_data.rect.y);
                const width: i32 = @intFromFloat(rect_data.rect.width);
                const height: i32 = @intFromFloat(rect_data.rect.height);

                if (rect_data.border_radius > 0) {
                    const radius: i32 = @intFromFloat(rect_data.border_radius * 2);
                    _ = RoundRect(hdc, x, y, x + width, y + height, radius, radius);
                } else {
                    _ = Rectangle(hdc, x, y, x + width, y + height);
                }

                _ = SelectObject(hdc, old_brush);
                _ = SelectObject(hdc, old_pen);
                _ = DeleteObject(brush);
                _ = DeleteObject(pen);
            },
            .text => |text_data| {
                _ = SetBkMode(hdc, TRANSPARENT);
                _ = SetTextColor(hdc, colorToColorref(text_data.color));

                // Create font
                const font_height = @as(i32, @intFromFloat(-text_data.font.style.size * 1.3));
                const font_width = 0; // auto
                const font_weight = if (text_data.font.style.weight >= 700) FW_BOLD else FW_NORMAL;
                const font_italic: u32 = if (text_data.font.style.italic) 1 else 0;
                const font_underline: u32 = if (text_data.font.style.underline) 1 else 0;

                const face_name_wide = blk: {
                    const default_face = "Segoe UI";
                    const face_name = if (text_data.font.name.len > 0) text_data.font.name else default_face;
                    break :blk std.unicode.utf8ToUtf16LeStringLiteral(face_name);
                };

                const font = CreateFontW(font_height, font_width, 0, 0, @intCast(font_weight), font_italic, font_underline, 0, DEFAULT_CHARSET, OUT_TT_PRECIS, CLIP_DEFAULT_PRECIS, PROOF_QUALITY, VARIABLE_PITCH | FF_DONTCARE, face_name_wide);

                const old_font = SelectObject(hdc, font);

                // Convert text to wide characters
                const wide_text = std.unicode.utf8ToUtf16LeWithNull(self.allocator, text_data.text) catch return;
                defer self.allocator.free(wide_text);

                // Convert rect
                var text_rect = RECT{
                    .left = @intFromFloat(text_data.rect.x),
                    .top = @intFromFloat(text_data.rect.y),
                    .right = @intFromFloat(text_data.rect.x + text_data.rect.width),
                    .bottom = @intFromFloat(text_data.rect.y + text_data.rect.height),
                };

                // Set text alignment
                var format: u32 = DT_SINGLELINE | DT_VCENTER;
                switch (text_data.align_) {
                    .left => format |= DT_LEFT,
                    .center => format |= DT_CENTER,
                    .right => format |= DT_RIGHT,
                }

                _ = DrawTextW(hdc, wide_text.ptr, -1, &text_rect, format);

                _ = SelectObject(hdc, old_font);
                _ = DeleteObject(font);
            },
            .image => |image_data| {
                // For GDI, we assume the image handle is a HBITMAP
                const bitmap: HBITMAP = @ptrFromInt(image_data.image.handle);
                if (bitmap == null) return;

                // Create a device context for the bitmap
                const bitmap_dc = CreateCompatibleDC(hdc);
                if (bitmap_dc == null) return;

                const old_bitmap = SelectObject(bitmap_dc, bitmap);

                // Calculate coordinates
                const x = @as(i32, @intFromFloat(image_data.rect.x));
                const y = @as(i32, @intFromFloat(image_data.rect.y));
                const width = @as(i32, @intFromFloat(image_data.rect.width));
                const height = @as(i32, @intFromFloat(image_data.rect.height));

                // BitBlt the image to our target DC
                _ = BitBlt(hdc, x, y, width, height, bitmap_dc, 0, 0, SRCCOPY);

                // Clean up
                _ = SelectObject(bitmap_dc, old_bitmap);
                _ = DeleteObject(bitmap_dc);
            },
            .clip_push => |clip_rect| {
                // Save current clip rect if any
                if (self.current_clip_rect) |current| {
                    self.clip_stack.append(ClipRect{ .rect = current }) catch return;
                } else {
                    // If no current clip rect, add a full-screen one
                    self.clip_stack.append(ClipRect{
                        .rect = RECT{
                            .left = 0,
                            .top = 0,
                            .right = @intCast(self.width),
                            .bottom = @intCast(self.height),
                        },
                    }) catch return;
                }

                // Create new clip rect
                const new_rect = RECT{
                    .left = @as(i32, @intFromFloat(clip_rect.x)),
                    .top = @as(i32, @intFromFloat(clip_rect.y)),
                    .right = @as(i32, @intFromFloat(clip_rect.x + clip_rect.width)),
                    .bottom = @as(i32, @intFromFloat(clip_rect.y + clip_rect.height)),
                };

                // Apply new clip rect
                self.current_clip_rect = new_rect;
                // TODO: Implement proper GDI clipping region support
            },
            .clip_pop => {
                if (self.clip_stack.items.len > 0) {
                    const last = self.clip_stack.pop();
                    self.current_clip_rect = last.rect;
                } else {
                    self.current_clip_rect = null;
                }
            },
            .custom => |custom_data| {
                if (custom_data.callback) |callback| {
                    callback(custom_data.data, self);
                }
            },
        }
    }

    pub fn createImage(self: *Self, width: u32, height: u32, pixels: [*]const u8, format: interface.Image.ImageFormat) !interface.Image {
        const hdc = if (self.memDC) |mem_dc| mem_dc else self.hdc;
        var bitmap_info = BITMAPINFO{
            .bmiHeader = BITMAPINFOHEADER{
                .biSize = @sizeOf(BITMAPINFOHEADER),
                .biWidth = @intCast(width),
                .biHeight = -@as(i32, @intCast(height)), // Negative for top-down DIB
                .biPlanes = 1,
                .biBitCount = 32,
                .biCompression = BI_RGB,
                .biSizeImage = 0,
                .biXPelsPerMeter = 0,
                .biYPelsPerMeter = 0,
                .biClrUsed = 0,
                .biClrImportant = 0,
            },
            .bmiColors = [1]u32{0},
        };

        var bits: ?*anyopaque = null;
        const bitmap = CreateDIBSection(hdc, &bitmap_info, DIB_RGB_COLORS, &bits, null, 0);
        if (bitmap == null) {
            return error.ImageCreationFailed;
        }

        // Copy pixel data to bitmap
        if (bits) |ptr| {
            const dest: [*]u8 = @ptrCast(ptr);
            const bytes_per_pixel = switch (format) {
                .rgba8, .bgra8 => 4,
                .rgb8, .bgr8 => 3,
            };
            const stride = width * 4; // DIB is always 32-bit aligned
            const total_size = stride * height;

            // If formats match, we can do a direct copy
            if (format == .bgra8) {
                @memcpy(dest[0..total_size], pixels[0..total_size]);
            } else {
                // Otherwise, we need to convert
                var y: usize = 0;
                while (y < height) : (y += 1) {
                    var x: usize = 0;
                    while (x < width) : (x += 1) {
                        const src_idx = (y * width + x) * bytes_per_pixel;
                        const dst_idx = y * stride + x * 4;

                        switch (format) {
                            .rgba8 => {
                                dest[dst_idx + 0] = pixels[src_idx + 2]; // B
                                dest[dst_idx + 1] = pixels[src_idx + 1]; // G
                                dest[dst_idx + 2] = pixels[src_idx + 0]; // R
                                dest[dst_idx + 3] = pixels[src_idx + 3]; // A
                            },
                            .rgb8 => {
                                dest[dst_idx + 0] = pixels[src_idx + 2]; // B
                                dest[dst_idx + 1] = pixels[src_idx + 1]; // G
                                dest[dst_idx + 2] = pixels[src_idx + 0]; // R
                                dest[dst_idx + 3] = 255; // A
                            },
                            .bgr8 => {
                                dest[dst_idx + 0] = pixels[src_idx + 0]; // B
                                dest[dst_idx + 1] = pixels[src_idx + 1]; // G
                                dest[dst_idx + 2] = pixels[src_idx + 2]; // R
                                dest[dst_idx + 3] = 255; // A
                            },
                            .bgra8 => {}, // Already handled
                        }
                    }
                }
            }
        }

        return interface.Image{
            .handle = @intFromPtr(bitmap),
            .width = width,
            .height = height,
            .format = format,
        };
    }

    pub fn destroyImage(self: *Self, image: *interface.Image) void {
        _ = self;
        if (image.handle == 0) return;

        const bitmap: HBITMAP = @ptrFromInt(image.handle);
        _ = DeleteObject(bitmap);
        image.handle = 0;
    }

    pub fn getTextSize(self: *Self, text: []const u8, font: interface.FontInfo) struct { width: f32, height: f32 } {
        const hdc = if (self.memDC) |mem_dc| mem_dc else self.hdc;

        // Create font
        const font_height: i32 = @intFromFloat(-font.style.size * 1.3);
        const font_width = 0; // auto
        const font_weight = if (font.style.weight >= 700) FW_BOLD else FW_NORMAL;
        const font_italic: u32 = if (font.style.italic) 1 else 0;
        const font_underline: u32 = if (font.style.underline) 1 else 0;

        const face_name_wide = blk: {
            const default_face = "Segoe UI";
            const face_name = if (font.name.len > 0) font.name else default_face;
            break :blk std.unicode.utf8ToUtf16LeStringLiteral(face_name);
        };

        const font_handle = CreateFontW(font_height, font_width, 0, 0, @intCast(font_weight), font_italic, font_underline, 0, DEFAULT_CHARSET, OUT_TT_PRECIS, CLIP_DEFAULT_PRECIS, PROOF_QUALITY, VARIABLE_PITCH | FF_DONTCARE, face_name_wide);

        if (font_handle == null) return .{ .width = 0, .height = 0 };

        const old_font = SelectObject(hdc, font_handle);

        // Convert text to wide characters
        const wide_text = std.unicode.utf8ToUtf16LeWithNull(self.allocator, text) catch return .{ .width = 0, .height = 0 };
        defer self.allocator.free(wide_text);

        // Measure text
        var size: SIZE = undefined;
        _ = GetTextExtentPoint32W(hdc, wide_text.ptr, @intCast(wide_text.len - 1), &size);

        _ = SelectObject(hdc, old_font);
        _ = DeleteObject(font_handle);

        return .{
            .width = @floatFromInt(size.cx),
            .height = @floatFromInt(size.cy),
        };
    }

    pub fn resize(self: *Self, width: u32, height: u32) void {
        if (width == self.width and height == self.height) return;
        self.width = width;
        self.height = height;

        // Force recreation of the double buffer on next beginFrame
        self.cleanupGraphicsResources();
    }
};

// Helper function to convert interface color to GDI COLORREF
fn colorToColorref(color: interface.Color) COLORREF {
    const r = @as(u32, @intFromFloat(color.r * 255.0)) & 0xFF;
    const g = @as(u32, @intFromFloat(color.g * 255.0)) & 0xFF;
    const b = @as(u32, @intFromFloat(color.b * 255.0)) & 0xFF;
    return (b << 16) | (g << 8) | r; // GDI uses BGR format
}

// Implementation of the backend interface
// Get last error message from the context
fn gdiGetLastError(ctx: *anyopaque) ?[]const u8 {
    const gdi_context = @as(*GdiContext, @ptrCast(@alignCast(ctx)));
    return gdi_context.last_error;
}

pub const gdi_backend_interface = interface.BackendInterface{
    .init_fn = gdiInit,
    .deinit_fn = gdiDeinit,
    .begin_frame_fn = gdiBeginFrame,
    .end_frame_fn = gdiEndFrame,
    .execute_draw_commands_fn = gdiExecuteDrawCommands,
    .create_image_fn = gdiCreateImage,
    .destroy_image_fn = gdiDestroyImage,
    .get_text_size_fn = gdiGetTextSize,
    .resize_fn = gdiResize,
    .get_last_error_fn = gdiGetLastError,
    .backend_type = .gdi,
};

fn gdiInit(allocator: Allocator, window_handle: usize) anyerror!*anyopaque {
    const ctx = try GdiContext.init(allocator, window_handle);
    return ctx;
}

fn gdiDeinit(ctx: *anyopaque) void {
    const gdi_ctx: *GdiContext = @ptrCast(@alignCast(ctx));
    gdi_ctx.deinit();
}

fn gdiBeginFrame(ctx: *anyopaque, width: u32, height: u32) void {
    const gdi_ctx: *GdiContext = @ptrCast(@alignCast(ctx));
    gdi_ctx.beginFrame(width, height);
}

fn gdiEndFrame(ctx: *anyopaque) void {
    const gdi_ctx: *GdiContext = @ptrCast(@alignCast(ctx));
    gdi_ctx.endFrame();
}

fn gdiExecuteDrawCommands(ctx: *anyopaque, commands: []const interface.DrawCommand) void {
    const gdi_ctx: *GdiContext = @ptrCast(@alignCast(ctx));
    gdi_ctx.executeDrawCommands(commands);
}

fn gdiCreateImage(ctx: *anyopaque, width: u32, height: u32, pixels: [*]const u8, format: interface.Image.ImageFormat) anyerror!interface.Image {
    const gdi_ctx: *GdiContext = @ptrCast(@alignCast(ctx));
    return gdi_ctx.createImage(width, height, pixels, format);
}

fn gdiDestroyImage(ctx: *anyopaque, image: *interface.Image) void {
    const gdi_ctx: *GdiContext = @ptrCast(@alignCast(ctx));
    gdi_ctx.destroyImage(image);
}

fn gdiGetTextSize(ctx: *anyopaque, text: []const u8, font: interface.FontInfo) struct { width: f32, height: f32 } {
    const gdi_ctx: *GdiContext = @ptrCast(@alignCast(ctx));
    return gdi_ctx.getTextSize(text, font);
}

fn gdiResize(ctx: *anyopaque, width: u32, height: u32) void {
    const gdi_ctx: *GdiContext = @ptrCast(@alignCast(ctx));
    gdi_ctx.resize(width, height);
}
