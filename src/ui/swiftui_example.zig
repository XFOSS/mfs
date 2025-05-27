const std = @import("std");
const Allocator = std.mem.Allocator;
const swiftui = @import("swiftui.zig");
const color = @import("color.zig");
const color_bridge = @import("color_bridge.zig");
const Vec4 = @import("../math/vec4.zig").Vec4f;
const ui_framework = @import("ui_framework.zig");

// Example SwiftUI-like app demonstrating the declarative UI system

const ContentView = struct {
    allocator: Allocator,
    counter: *swiftui.State(i32),
    name: *swiftui.State([]const u8),
    show_details: *swiftui.State(bool),

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        var counter = try allocator.create(swiftui.State(i32));
        counter.* = swiftui.State(i32).init(allocator, 0);

        var name = try allocator.create(swiftui.State([]const u8));
        name.* = swiftui.State([]const u8).init(allocator, "SwiftUI App");

        var show_details = try allocator.create(swiftui.State(bool));
        show_details.* = swiftui.State(bool).init(allocator, false);

        return Self{
            .allocator = allocator,
            .counter = counter,
            .name = name,
            .show_details = show_details,
        };
    }

    pub fn deinit(self: *Self) void {
        self.counter.deinit();
        self.name.deinit();
        self.show_details.deinit();
        self.allocator.destroy(self.counter);
        self.allocator.destroy(self.name);
        self.allocator.destroy(self.show_details);
    }

    pub fn body(self: *Self) !swiftui.ViewProtocol {
        const children = try self.allocator.alloc(swiftui.ViewProtocol, 5);

        // Title using Apple system colors
        var title = swiftui.text(self.allocator, self.name.get());
        title = title.fontSize(28.0);
        title = title.foregroundColor(color.Constants.label); // Apple's adaptive label color
        children[0] = title.view();

        // Counter display with Vec4 integration
        const counter_text = try std.fmt.allocPrint(self.allocator, "Count: {d}", .{self.counter.get()});
        var counter_label = swiftui.text(self.allocator, counter_text);
        counter_label = counter_label.fontSize(20.0);
        counter_label = counter_label.foregroundColorVec4(Vec4.init(0.0, 0.5, 1.0, 1.0)); // Blue using Vec4
        children[1] = counter_label.view();

        // Button row
        const button_children = try self.allocator.alloc(swiftui.ViewProtocol, 2);

        // Decrement button
        var dec_text = swiftui.text(self.allocator, "-");
        dec_text = dec_text.foregroundColor(color.Constants.white);
        const dec_button = swiftui.button(self.allocator, dec_text.view(), &decrementAction);
        button_children[0] = dec_button.view();

        // Increment button
        var inc_text = swiftui.text(self.allocator, "+");
        inc_text = inc_text.foregroundColor(color.Constants.white);
        const inc_button = swiftui.button(self.allocator, inc_text.view(), &incrementAction);
        button_children[1] = inc_button.view();

        var button_row = swiftui.hstack(self.allocator, button_children);
        button_row = button_row.spacing(16.0);
        children[2] = button_row.view();

        // Toggle button for details
        var toggle_text = swiftui.text(self.allocator, if (self.show_details.get()) "Hide Details" else "Show Details");
        toggle_text = toggle_text.foregroundColor(color.Constants.systemBlue); // Apple's system blue
        const toggle_button = swiftui.button(self.allocator, toggle_text.view(), &toggleDetailsAction);
        children[3] = toggle_button.view();

        // Conditional details view
        if (self.show_details.get()) {
            const detail_children = try self.allocator.alloc(swiftui.ViewProtocol, 3);

            var detail1 = swiftui.text(self.allocator, "Built with Zig & SwiftUI-like API");
            detail1 = detail1.fontSize(14.0);
            detail1 = detail1.foregroundColor(color.Constants.secondaryLabel);
            detail_children[0] = detail1.view();

            var detail2 = swiftui.text(self.allocator, "Integrates with Vec4 math system");
            detail2 = detail2.fontSize(14.0);
            detail2 = detail2.foregroundColor(color.Constants.secondaryLabel);
            detail_children[1] = detail2.view();

            var detail3 = swiftui.text(self.allocator, "Uses Apple's semantic colors");
            detail3 = detail3.fontSize(14.0);
            detail3 = detail3.foregroundColor(color.Constants.tertiaryLabel);
            detail_children[2] = detail3.view();

            var details_stack = swiftui.vstack(self.allocator, detail_children);
            details_stack = details_stack.spacing(4.0);
            children[4] = details_stack.view();
        } else {
            var empty = swiftui.text(self.allocator, "");
            children[4] = empty.view();
        }

        var main_stack = swiftui.vstack(self.allocator, children);
        main_stack = main_stack.spacing(20.0);
        main_stack = main_stack.alignment(.center);

        return main_stack.view();
    }

    fn incrementAction() void {
        // In a real implementation, this would be bound to the state
        std.log.info("Increment button pressed", .{});
    }

    fn decrementAction() void {
        // In a real implementation, this would be bound to the state
        std.log.info("Decrement button pressed", .{});
    }

    fn toggleDetailsAction() void {
        // In a real implementation, this would toggle the state
        std.log.info("Toggle details button pressed", .{});
    }
};

// Weather App Example
const WeatherView = struct {
    allocator: Allocator,
    temperature: *swiftui.State(f32),
    location: *swiftui.State([]const u8),
    is_sunny: *swiftui.State(bool),

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        var temperature = try allocator.create(swiftui.State(f32));
        temperature.* = swiftui.State(f32).init(allocator, 22.5);

        var location = try allocator.create(swiftui.State([]const u8));
        location.* = swiftui.State([]const u8).init(allocator, "San Francisco");

        var is_sunny = try allocator.create(swiftui.State(bool));
        is_sunny.* = swiftui.State(bool).init(allocator, true);

        return Self{
            .allocator = allocator,
            .temperature = temperature,
            .location = location,
            .is_sunny = is_sunny,
        };
    }

    pub fn deinit(self: *Self) void {
        self.temperature.deinit();
        self.location.deinit();
        self.is_sunny.deinit();
        self.allocator.destroy(self.temperature);
        self.allocator.destroy(self.location);
        self.allocator.destroy(self.is_sunny);
    }

    pub fn body(self: *Self) !swiftui.ViewProtocol {
        const children = try self.allocator.alloc(swiftui.ViewProtocol, 4);

        // Weather icon (using text for simplicity)
        var icon = swiftui.text(self.allocator, if (self.is_sunny.get()) "☀️" else "☁️");
        icon = icon.fontSize(48.0);
        children[0] = icon.view();

        // Temperature with custom Vec4 color based on value
        const temp_text = try std.fmt.allocPrint(self.allocator, "{d:.1}°C", .{self.temperature.get()});
        var temp_label = swiftui.text(self.allocator, temp_text);
        temp_label = temp_label.fontSize(36.0);

        // Color temperature based on value using Vec4
        const temp_color = if (self.temperature.get() > 25.0)
            Vec4.red // Hot - red
        else if (self.temperature.get() > 15.0)
            Vec4.init(1.0, 0.5, 0.0, 1.0) // Warm - orange
        else
            Vec4.init(0.0, 0.5, 1.0, 1.0); // Cold - blue

        temp_label = temp_label.foregroundColorVec4(temp_color);
        children[1] = temp_label.view();

        // Location
        var location_label = swiftui.text(self.allocator, self.location.get());
        location_label = location_label.fontSize(18.0);
        location_label = location_label.foregroundColor(color.Constants.secondaryLabel);
        children[2] = location_label.view();

        // Status text with semantic colors
        const status = if (self.is_sunny.get()) "Perfect weather!" else "Cloudy day";
        var status_label = swiftui.text(self.allocator, status);
        status_label = status_label.fontSize(16.0);
        status_label = status_label.foregroundColor(if (self.is_sunny.get()) color.Constants.systemGreen else color.Constants.systemGray);
        children[3] = status_label.view();

        var weather_stack = swiftui.vstack(self.allocator, children);
        weather_stack = weather_stack.spacing(12.0);
        weather_stack = weather_stack.alignment(.center);

        return weather_stack.view();
    }
};

// Main Application
pub fn createExampleApp(allocator: Allocator, color_registry: *color.ColorRegistry) !swiftui.App {
    var app = swiftui.App.init(allocator, color_registry);

    // Create a complex layout with multiple views
    var content_view = try ContentView.init(allocator);
    var weather_view = try WeatherView.init(allocator);

    const main_children = try allocator.alloc(swiftui.ViewProtocol, 2);
    main_children[0] = try content_view.body();
    main_children[1] = try weather_view.body();

    var main_layout = swiftui.hstack(allocator, main_children);
    main_layout = main_layout.spacing(40.0);
    main_layout = main_layout.alignment(.top);

    app.setRootView(main_layout.view());

    return app;
}

// Color theme helper
pub fn setupAppleColors(color_registry: *color.ColorRegistry) !void {
    // Create custom theme with Apple-like colors using Vec4 integration
    const accent_color = color_bridge.vec4ToColor(Vec4.init(0.0, 0.48, 1.0, 1.0)); // Apple blue
    try color_bridge.defineCustomTheme(color_registry, accent_color);
}

// Usage example
pub fn runExample() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Setup color system
    var color_registry = color.ColorRegistry.init(allocator);
    defer color_registry.deinit();

    try setupAppleColors(&color_registry);

    // Create app
    var app = try createExampleApp(allocator, &color_registry);
    defer app.deinit();

    // Set dark mode
    app.setColorScheme(.dark);

    // Render the app
    const frame = swiftui.Rect.init(0, 0, 800, 600);
    const theme = ui_framework.Theme.dark();
    try app.render(frame, theme);

    std.log.info("SwiftUI-like app rendered successfully!", .{});
}

// Test the example
test "SwiftUI example compilation" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var color_registry = color.ColorRegistry.init(allocator);
    defer color_registry.deinit();

    var content_view = try ContentView.init(allocator);
    defer content_view.deinit();

    // Test that we can create the body
    const body = try content_view.body();
    defer body.deinit();

    // Test layout calculation
    const size = body.layout(swiftui.Size.init(400, 300));
    try testing.expect(size.width > 0);
    try testing.expect(size.height > 0);
}
