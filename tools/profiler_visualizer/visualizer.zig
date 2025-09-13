const std = @import("std");
const tracy = @import("tracy");
const c = @cImport({
    @cInclude("SDL.h");
    @cInclude("SDL_ttf.h");
});

const Profiler = @import("../../src/system/profiling/profiler.zig").Profiler;
const ProfileEntry = @import("../../src/system/profiling/profiler.zig").ProfileEntry;
const CounterEntry = @import("../../src/system/profiling/profiler.zig").CounterEntry;
const MemoryAllocation = @import("../../src/system/profiling/profiler.zig").MemoryAllocation;

const WINDOW_WIDTH: c.c_int = 1280;
const WINDOW_HEIGHT: c.c_int = 820; // Increased to accommodate memory view
const TIMELINE_HEIGHT: c.c_int = 400;
const COUNTER_HEIGHT: c.c_int = 150;
const MEMORY_HEIGHT: c.c_int = 200;
const MARGIN: c.c_int = 10;

const TIMELINE_TOP: c.c_int = MARGIN;
const TIMELINE_BOTTOM: c.c_int = TIMELINE_TOP + TIMELINE_HEIGHT;
const COUNTER_TOP: c.c_int = TIMELINE_BOTTOM + MARGIN;
const COUNTER_BOTTOM: c.c_int = COUNTER_TOP + COUNTER_HEIGHT;
const MEMORY_TOP: c.c_int = COUNTER_BOTTOM + MARGIN;
const MEMORY_BOTTOM: c.c_int = MEMORY_TOP + MEMORY_HEIGHT;

const TRACK_HEIGHT: c.c_int = 20;
const MAX_TRACKS: c.c_int = 20;
const TIMESTAMP_HEIGHT: c.c_int = 20;
const TIMELINE_CONTENT_TOP: c.c_int = TIMELINE_TOP + TIMESTAMP_HEIGHT;

const DEFAULT_ZOOM: u64 = 1_000_000_000; // 1 second in ns
const MIN_ZOOM: u64 = 1_000_000; // 1 ms in ns
const MAX_ZOOM: u64 = 60_000_000_000; // 60 seconds in ns

const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,

    pub fn fromHex(hex: u32) Color {
        return Color{
            .r = @intCast((hex >> 16) & 0xFF),
            .g = @intCast((hex >> 8) & 0xFF),
            .b = @intCast(hex & 0xFF),
        };
    }
};

const ViewState = struct {
    view_start: u64 = 0,
    view_range: u64 = DEFAULT_ZOOM,
    scroll_offset: f32 = 0,
    selected_entry_id: ?usize = null,
    playing: bool = false,
    playback_speed: f32 = 1.0,
    last_time: u64 = 0,
};

const ProfileData = struct {
    entries: std.array_list.Managed(ProfileEntry),
    counters: std.array_list.Managed(CounterEntry),
    allocations: std.array_list.Managed(MemoryAllocation),
    min_time: u64 = std.math.maxInt(u64),
    max_time: u64 = 0,

    pub fn init(allocator: std.mem.Allocator) ProfileData {
        return ProfileData{
            .entries = std.array_list.Managed(ProfileEntry).init(allocator),
            .counters = std.array_list.Managed(CounterEntry).init(allocator),
            .allocations = std.array_list.Managed(MemoryAllocation).init(allocator),
        };
    }

    pub fn deinit(self: *ProfileData) void {
        self.entries.deinit();
        self.counters.deinit();
        self.allocations.deinit();
    }

    pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !ProfileData {
        var result = ProfileData.init(allocator);
        errdefer result.deinit();

        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        var buf_reader = std.io.bufferedReader(file.reader());
        const reader = buf_reader.reader();

        var line_buf: [4096]u8 = undefined;
        var line_index: usize = 0;

        while (try reader.readUntilDelimiterOrEof(&line_buf, '\n')) |line| {
            line_index += 1;
            if (line.len == 0 or line[0] == '#') continue; // Skip comments and empty lines

            var iter = std.mem.splitSequence(u8, line, ",");
            const timestamp_str = iter.next() orelse continue;
            const type_str = iter.next() orelse continue;
            const name_raw = iter.next() orelse continue;
            const duration_str = iter.next() orelse continue;
            const thread_id_str = iter.next() orelse continue;
            const parent_id_str = iter.next() orelse continue;
            const color_str = iter.next() orelse continue;

            const timestamp = try std.fmt.parseInt(u64, timestamp_str, 10);

            // Update time range
            if (timestamp < result.min_time) {
                result.min_time = timestamp;
            }

            // Remove quotes from name
            var name = name_raw;
            if (name.len >= 2 and name[0] == '"' and name[name.len - 1] == '"') {
                name = name[1 .. name.len - 1];
            }

            if (std.mem.eql(u8, type_str, "zone")) {
                const duration = try std.fmt.parseInt(u64, duration_str, 10);
                const thread_id = try std.fmt.parseInt(u32, thread_id_str, 10);
                const parent_id_raw = try std.fmt.parseInt(u32, parent_id_str, 10);
                const parent_id: ?u32 = if (parent_id_raw > 0) parent_id_raw else null;
                const color = try std.fmt.parseInt(u32, color_str, 16);

                const end_time = timestamp + duration;
                if (end_time > result.max_time) {
                    result.max_time = end_time;
                }

                try result.entries.append(.{
                    .name = try allocator.dupe(u8, name),
                    .color = color,
                    .start_time = timestamp,
                    .end_time = end_time,
                    .parent_id = parent_id,
                    .thread_id = thread_id,
                });
            } else if (std.mem.eql(u8, type_str, "counter")) {
                const value_raw = try std.fmt.parseInt(u64, duration_str, 10);
                const value = @as(f64, @floatFromInt(value_raw)) / 1000.0;

                if (timestamp > result.max_time) {
                    result.max_time = timestamp;
                }

                try result.counters.append(.{
                    .name = try allocator.dupe(u8, name),
                    .value = value,
                    .timestamp = timestamp,
                });
            } else if (std.mem.eql(u8, type_str, "alloc") or std.mem.eql(u8, type_str, "free")) {
                const size = try std.fmt.parseInt(usize, duration_str, 10);
                const thread_id = try std.fmt.parseInt(u32, thread_id_str, 10);
                const source_file = try allocator.dupe(u8, color_str);

                if (timestamp > result.max_time) {
                    result.max_time = timestamp;
                }

                try result.allocations.append(.{
                    .ptr = undefined, // We don't have the actual pointer in the file
                    .size = size,
                    .timestamp = timestamp,
                    .thread_id = thread_id,
                    .source_file = source_file,
                    .source_line = null,
                    .freed = std.mem.eql(u8, type_str, "free"),
                    .free_timestamp = if (std.mem.eql(u8, type_str, "free")) timestamp else null,
                    .category = try allocator.dupe(u8, name),
                });
            }
        }

        return result;
    }
};

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: profiler_visualizer <profile_data_file>\n", .{});
        return;
    }

    const profile_path = args[1];

    // Initialize SDL
    if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
        std.debug.print("SDL_Init Error: {s}\n", .{c.SDL_GetError()});
        return;
    }
    defer c.SDL_Quit();

    // Initialize SDL_ttf
    if (c.TTF_Init() != 0) {
        std.debug.print("TTF_Init Error: {s}\n", .{c.TTF_GetError()});
        return;
    }
    defer c.TTF_Quit();

    // Create window
    const window = c.SDL_CreateWindow("MFS Profiler Visualizer", c.SDL_WINDOWPOS_CENTERED, c.SDL_WINDOWPOS_CENTERED, WINDOW_WIDTH, WINDOW_HEIGHT, c.SDL_WINDOW_SHOWN | c.SDL_WINDOW_RESIZABLE);
    if (window == null) {
        std.debug.print("SDL_CreateWindow Error: {s}\n", .{c.SDL_GetError()});
        return;
    }
    defer c.SDL_DestroyWindow(window);

    // Create renderer
    const renderer = c.SDL_CreateRenderer(window, -1, c.SDL_RENDERER_ACCELERATED | c.SDL_RENDERER_PRESENTVSYNC);
    if (renderer == null) {
        std.debug.print("SDL_CreateRenderer Error: {s}\n", .{c.SDL_GetError()});
        return;
    }
    defer c.SDL_DestroyRenderer(renderer);

    // Load font
    const font = c.TTF_OpenFont("assets/fonts/RobotoMono-Regular.ttf", 12);
    if (font == null) {
        std.debug.print("TTF_OpenFont Error: {s} - Using default font\n", .{c.TTF_GetError()});
    }
    defer if (font != null) c.TTF_CloseFont(font);

    // Load profile data
    var profile_data = try ProfileData.loadFromFile(allocator, profile_path);
    defer profile_data.deinit();

    std.debug.print("Loaded profile data with {} entries and {} counters\n", .{ profile_data.entries.items.len, profile_data.counters.items.len });
    std.debug.print("Time range: {} to {} ({} ns)\n", .{ profile_data.min_time, profile_data.max_time, profile_data.max_time - profile_data.min_time });

    // Set up initial view
    var view = ViewState{
        .view_start = profile_data.min_time,
        .view_range = @min(DEFAULT_ZOOM, profile_data.max_time - profile_data.min_time),
    };

    // Main loop
    var running = true;
    var last_ticks = c.SDL_GetTicks();

    while (running) {
        // Calculate delta time
        const current_ticks = c.SDL_GetTicks();
        const delta_time = current_ticks - last_ticks;
        _ = delta_time; // Suppress unused variable warning
        last_ticks = current_ticks;

        // Handle events
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_QUIT => {
                    running = false;
                },
                c.SDL_KEYDOWN => {
                    switch (event.key.keysym.sym) {
                        c.SDLK_ESCAPE => running = false,
                        c.SDLK_LEFT => {
                            // Move view left
                            const move_amount: u64 = @intFromFloat(f64(view.view_range) * 0.1);
                            if (view.view_start > move_amount) {
                                view.view_start -= move_amount;
                            } else {
                                view.view_start = 0;
                            }
                        },
                        c.SDLK_RIGHT => {
                            // Move view right
                            const move_amount: u64 = @intFromFloat(f64(view.view_range) * 0.1);
                            view.view_start += move_amount;
                            if (view.view_start + view.view_range > profile_data.max_time) {
                                view.view_start = profile_data.max_time - view.view_range;
                            }
                        },
                        c.SDLK_UP => {
                            // Zoom in
                            const zoom_factor = 0.8;
                            const new_range: u64 = @intFromFloat(@as(f64, @floatFromInt(view.view_range)) * zoom_factor);
                            if (new_range >= MIN_ZOOM) {
                                const center = view.view_start + view.view_range / 2;
                                view.view_range = new_range;
                                view.view_start = center - view.view_range / 2;
                            }
                        },
                        c.SDLK_DOWN => {
                            // Zoom out
                            const zoom_factor = 1.25;
                            const new_range: u64 = @intFromFloat(@as(f64, @floatFromInt(view.view_range)) * zoom_factor);
                            if (new_range <= MAX_ZOOM) {
                                const center = view.view_start + view.view_range / 2;
                                view.view_range = new_range;
                                view.view_start = center - view.view_range / 2;
                            }
                        },
                        c.SDLK_SPACE => {
                            // Toggle playback
                            view.playing = !view.playing;
                            view.last_time = c.SDL_GetTicks();
                        },
                        c.SDLK_r => {
                            // Reset view to show all data
                            view.view_start = profile_data.min_time;
                            view.view_range = profile_data.max_time - profile_data.min_time;
                            view.playing = false;
                        },
                        else => {},
                    }
                },
                c.SDL_MOUSEWHEEL => {
                    const zoom_factor = if (event.wheel.y > 0) 0.8 else 1.25;
                    const new_range: u64 = @intFromFloat(@as(f64, @floatFromInt(view.view_range)) * zoom_factor);

                    if (new_range >= MIN_ZOOM and new_range <= MAX_ZOOM) {
                        // Get mouse position for zoom-in point
                        var mouse_x: c.c_int = undefined;
                        var mouse_y: c.c_int = undefined;
                        _ = c.SDL_GetMouseState(&mouse_x, &mouse_y);

                        // Calculate zoom position ratio
                        const window_width = getWindowWidth(window);
                        const timeline_width = window_width - 2 * MARGIN;
                        const zoom_pos_ratio = @as(f32, @floatFromInt(mouse_x - MARGIN)) / @as(f32, @floatFromInt(timeline_width));

                        const focus_time = view.view_start + @as(u64, @intFromFloat(@as(f64, @floatFromInt(view.view_range)) * @as(f64, @floatCast(zoom_pos_ratio))));
                        view.view_range = new_range;
                        view.view_start = focus_time - @as(u64, @intFromFloat(@as(f64, @floatFromInt(view.view_range)) * @as(f64, @floatCast(zoom_pos_ratio))));
                    }
                },
                c.SDL_MOUSEBUTTONDOWN => {
                    if (event.button.button == c.SDL_BUTTON_LEFT) {
                        // Check if clicked on an entry
                        var window_width: c.c_int = undefined;
                        var window_height: c.c_int = undefined;
                        c.SDL_GetWindowSize(window, &window_width, &window_height);

                        const timeline_width = window_width - 2 * MARGIN;
                        const x = event.button.x;
                        const y = event.button.y;

                        // Only handle clicks in timeline area
                        if (x >= MARGIN and x <= MARGIN + timeline_width and
                            y >= TIMELINE_CONTENT_TOP and y <= TIMELINE_BOTTOM)
                        {
                            const click_time = view.view_start + @as(u64, @intFromFloat(@as(f64, @floatFromInt(view.view_range)) *
                                (@as(f64, @floatFromInt(x - MARGIN)) / @as(f64, @floatFromInt(timeline_width)))));

                            // Find entry at click position
                            const track = @divFloor(y - TIMELINE_CONTENT_TOP, TRACK_HEIGHT);
                            if (track >= 0 and track < MAX_TRACKS) {
                                // Search for entry at this time and track
                                for (profile_data.entries.items, 0..) |entry, i| {
                                    const entry_track = findEntryTrack(profile_data.entries.items, i);
                                    if (entry_track == track and entry.start_time <= click_time and entry.end_time >= click_time) {
                                        view.selected_entry_id = i;
                                        break;
                                    }
                                }
                            }
                        }
                    }
                },
                else => {},
            }
        }

        // Update playback
        if (view.playing) {
            const now = c.SDL_GetTicks();
            const elapsed = now - view.last_time;
            view.last_time = now;

            // Move view based on playback speed
            const move_amount = @as(u64, @intFromFloat(@as(f64, @floatFromInt(elapsed)) * 1_000_000.0 * @as(f64, @floatCast(view.playback_speed))));
            view.view_start += move_amount;

            // Stop at end of data
            if (view.view_start + view.view_range > profile_data.max_time) {
                view.view_start = profile_data.max_time - view.view_range;
                view.playing = false;
            }
        }

        // Clamp view to data
        if (view.view_start < profile_data.min_time) {
            view.view_start = profile_data.min_time;
        }
        if (view.view_start + view.view_range > profile_data.max_time) {
            view.view_start = profile_data.max_time - view.view_range;
        }

        // Clear screen
        _ = c.SDL_SetRenderDrawColor(renderer, 30, 30, 30, 255);
        _ = c.SDL_RenderClear(renderer);

        // Draw timeline
        drawTimeline(renderer, font, profile_data, view);

        // Draw counters
        drawCounters(renderer, font, profile_data, view);

        // Draw UI controls
        drawControls(renderer, font, view);

        // Draw memory usage view
        drawMemoryView(renderer, font, profile_data, view);

        // Display detailed info for selected entry
        if (view.selected_entry_id) |id| {
            if (id < profile_data.entries.items.len) {
                drawEntryDetails(renderer, font, profile_data.entries.items[id]);
            }
        }

        // Present renderer
        c.SDL_RenderPresent(renderer);
    }
}

fn getWindowWidth(window: ?*c.SDL_Window) c.c_int {
    var width: c.c_int = undefined;
    var height: c.c_int = undefined;
    c.SDL_GetWindowSize(window, &width, &height);
    return width;
}

fn getWindowHeight(window: ?*c.SDL_Window) c.c_int {
    var width: c.c_int = undefined;
    var height: c.c_int = undefined;
    c.SDL_GetWindowSize(window, &width, &height);
    return height;
}

fn timeToX(time: u64, view: ViewState, timeline_width: c.c_int) c.c_int {
    const time_offset = time - view.view_start;
    const position = @as(f64, @floatFromInt(time_offset)) / @as(f64, @floatFromInt(view.view_range));
    return @as(c.c_int, @intFromFloat(@as(f64, @floatFromInt(timeline_width)) * position)) + MARGIN;
}

fn findEntryTrack(entries: []const ProfileEntry, entry_idx: usize) i32 {
    const entry = entries[entry_idx];
    var level: i32 = 0;
    var current_parent = entry.parent_id;

    // Trace back to root to determine depth
    while (current_parent) |parent_id| {
        level += 1;

        // Find the parent entry
        for (entries) |_| {
            // -1 because IDs are 1-based, index is 0-based
            if (parent_id > 0 and parent_id - 1 < entries.len) {
                current_parent = entries[parent_id - 1].parent_id;
                break;
            } else {
                current_parent = null;
                break;
            }
        }
    }

    return level;
}

fn drawTimeline(renderer: ?*c.SDL_Renderer, font: ?*c.TTF_Font, profile_data: ProfileData, view: ViewState) void {
    var window_width: c.c_int = undefined;
    var window_height: c.c_int = undefined;
    c.SDL_GetWindowSize(c.SDL_GetWindowFromID(c.SDL_GetWindowID(c.SDL_RenderGetWindow(renderer))), &window_width, &window_height);

    const timeline_width = window_width - 2 * MARGIN;

    // Draw timeline background
    {
        const rect = c.SDL_Rect{
            .x = MARGIN,
            .y = TIMELINE_TOP,
            .w = timeline_width,
            .h = TIMELINE_HEIGHT,
        };
        _ = c.SDL_SetRenderDrawColor(renderer, 20, 20, 20, 255);
        _ = c.SDL_RenderFillRect(renderer, &rect);

        _ = c.SDL_SetRenderDrawColor(renderer, 60, 60, 60, 255);
        _ = c.SDL_RenderDrawRect(renderer, &rect);
    }

    // Draw time markers
    const time_span_ns = view.view_range;
    const marker_distance_ns = calculateMarkerDistance(time_span_ns);
    const first_marker_ns = (view.view_start / marker_distance_ns) * marker_distance_ns;
    var marker_ns = first_marker_ns;

    while (marker_ns < view.view_start + time_span_ns) : (marker_ns += marker_distance_ns) {
        if (marker_ns < view.view_start) continue;

        const x = timeToX(marker_ns, view, timeline_width);

        // Draw vertical line
        _ = c.SDL_SetRenderDrawColor(renderer, 80, 80, 80, 255);
        _ = c.SDL_RenderDrawLine(renderer, x, TIMELINE_CONTENT_TOP, x, TIMELINE_BOTTOM);

        // Draw time label
        var time_buf: [64]u8 = undefined;
        const relative_time_ms = @as(f64, @floatFromInt(marker_ns - profile_data.min_time)) / 1_000_000.0;
        const time_str = std.fmt.bufPrintZ(&time_buf, "{d:.3}ms", .{relative_time_ms}) catch continue;

        if (font != null) {
            const color = c.SDL_Color{ .r = 200, .g = 200, .b = 200, .a = 255 };
            const surface = c.TTF_RenderText_Blended(font, time_str, color);
            if (surface != null) {
                defer c.SDL_FreeSurface(surface);
                const texture = c.SDL_CreateTextureFromSurface(renderer, surface);
                if (texture != null) {
                    defer c.SDL_DestroyTexture(texture);
                    const rect = c.SDL_Rect{
                        .x = x - surface.*.w / 2,
                        .y = TIMELINE_TOP + 2,
                        .w = surface.*.w,
                        .h = surface.*.h,
                    };
                    _ = c.SDL_RenderCopy(renderer, texture, null, &rect);
                }
            }
        }
    }

    // Draw entries
    for (profile_data.entries.items, 0..) |entry, i| {
        // Skip entries outside view range
        if (entry.end_time < view.view_start or entry.start_time > view.view_start + view.view_range) {
            continue;
        }

        const track = findEntryTrack(profile_data.entries.items, i);
        if (track >= MAX_TRACKS) continue;

        const start_x = timeToX(entry.start_time, view, timeline_width);
        const end_x = timeToX(entry.end_time, view, timeline_width);
        const width = std.math.max(end_x - start_x, 1);

        const y = TIMELINE_CONTENT_TOP + track * TRACK_HEIGHT;

        // Draw entry box
        const rect = c.SDL_Rect{
            .x = start_x,
            .y = y,
            .w = width,
            .h = TRACK_HEIGHT - 2,
        };

        const color = Color.fromHex(entry.color);
        _ = c.SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a);
        _ = c.SDL_RenderFillRect(renderer, &rect);

        // Highlight selected entry
        if (view.selected_entry_id != null and view.selected_entry_id.? == i) {
            _ = c.SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255);
            _ = c.SDL_RenderDrawRect(renderer, &rect);
        }

        // Draw entry name if enough space
        if (width >= 20 and font != null) {
            const text_color = c.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
            const surface = c.TTF_RenderText_Blended(font, std.mem.sliceTo(entry.name.ptr, 0), text_color);

            if (surface != null) {
                defer c.SDL_FreeSurface(surface);
                const texture = c.SDL_CreateTextureFromSurface(renderer, surface);
                if (texture != null) {
                    defer c.SDL_DestroyTexture(texture);

                    // Only draw text if it fits
                    if (surface.*.w < rect.w - 4) {
                        const text_rect = c.SDL_Rect{
                            .x = rect.x + 2,
                            .y = rect.y + (rect.h - surface.*.h) / 2,
                            .w = surface.*.w,
                            .h = surface.*.h,
                        };
                        _ = c.SDL_RenderCopy(renderer, texture, null, &text_rect);
                    }
                }
            }
        }
    }

    // Draw current time cursor
    const now = view.view_start + @divTrunc(view.view_range, 2);
    const cursor_x = timeToX(now, view, timeline_width);
    _ = c.SDL_SetRenderDrawColor(renderer, 255, 50, 50, 255);
    _ = c.SDL_RenderDrawLine(renderer, cursor_x, TIMELINE_TOP, cursor_x, TIMELINE_BOTTOM);
}

fn drawCounters(renderer: ?*c.SDL_Renderer, font: ?*c.TTF_Font, profile_data: ProfileData, view: ViewState) void {
    var window_width: c.c_int = undefined;
    var window_height: c.c_int = undefined;
    c.SDL_GetWindowSize(c.SDL_GetWindowFromID(c.SDL_GetWindowID(c.SDL_RenderGetWindow(renderer))), &window_width, &window_height);

    const counter_width = window_width - 2 * MARGIN;

    // Draw counter background
    {
        const rect = c.SDL_Rect{
            .x = MARGIN,
            .y = COUNTER_TOP,
            .w = counter_width,
            .h = COUNTER_HEIGHT,
        };
        _ = c.SDL_SetRenderDrawColor(renderer, 20, 20, 20, 255);
        _ = c.SDL_RenderFillRect(renderer, &rect);

        _ = c.SDL_SetRenderDrawColor(renderer, 60, 60, 60, 255);
        _ = c.SDL_RenderDrawRect(renderer, &rect);
    }

    // Find all unique counter names
    var counter_names = std.array_list.Managed([]const u8).init(std.heap.page_allocator);
    defer counter_names.deinit();

    for (profile_data.counters.items) |counter| {
        var found = false;
        for (counter_names.items) |name| {
            if (std.mem.eql(u8, name, counter.name)) {
                found = true;
                break;
            }
        }

        if (!found) {
            counter_names.append(counter.name) catch continue;
        }
    }

    // Draw each counter series
    for (counter_names.items, 0..) |name, i| {
        if (i >= 5) break; // Limit number of counters

        // Find min/max values for this counter
        var min_value: f64 = std.math.floatMax(f64);
        var max_value: f64 = std.math.floatMin(f64);

        for (profile_data.counters.items) |counter| {
            if (!std.mem.eql(u8, counter.name, name)) continue;

            if (counter.timestamp >= view.view_start and
                counter.timestamp <= view.view_start + view.view_range)
            {
                min_value = std.math.min(min_value, counter.value);
                max_value = std.math.max(max_value, counter.value);
            }
        }

        if (min_value > max_value) continue; // No data in range

        // Make sure range is at least 1.0
        if (max_value - min_value < 1.0) {
            const avg = (max_value + min_value) / 2.0;
            min_value = avg - 0.5;
            max_value = avg + 0.5;
        }

        // Draw counter name
        if (font != null) {
            const color = c.SDL_Color{ .r = 200, .g = 200, .b = 200, .a = 255 };
            const surface = c.TTF_RenderText_Blended(font, std.mem.sliceTo(name.ptr, 0), color);

            if (surface != null) {
                defer c.SDL_FreeSurface(surface);
                const texture = c.SDL_CreateTextureFromSurface(renderer, surface);
                if (texture != null) {
                    defer c.SDL_DestroyTexture(texture);
                    const rect = c.SDL_Rect{
                        .x = MARGIN + 5,
                        .y = COUNTER_TOP + @as(c.c_int, @intCast(i)) * 25 + 5,
                        .w = surface.*.w,
                        .h = surface.*.h,
                    };
                    _ = c.SDL_RenderCopy(renderer, texture, null, &rect);
                }
            }

            // Draw min/max values
            var buf: [64]u8 = undefined;
            const min_str = std.fmt.bufPrintZ(&buf, "Min: {d:.2}", .{min_value}) catch continue;
            const min_surface = c.TTF_RenderText_Blended(font, min_str, color);
            if (min_surface != null) {
                defer c.SDL_FreeSurface(min_surface);
                const texture = c.SDL_CreateTextureFromSurface(renderer, min_surface);
                if (texture != null) {
                    defer c.SDL_DestroyTexture(texture);
                    const rect = c.SDL_Rect{
                        .x = MARGIN + 150,
                        .y = COUNTER_TOP + @as(c.c_int, @intCast(i)) * 25 + 5,
                        .w = min_surface.*.w,
                        .h = min_surface.*.h,
                    };
                    _ = c.SDL_RenderCopy(renderer, texture, null, &rect);
                }
            }

            const max_str = std.fmt.bufPrintZ(&buf, "Max: {d:.2}", .{max_value}) catch continue;
            const max_surface = c.TTF_RenderText_Blended(font, max_str, color);
            if (max_surface != null) {
                defer c.SDL_FreeSurface(max_surface);
                const texture = c.SDL_CreateTextureFromSurface(renderer, max_surface);
                if (texture != null) {
                    defer c.SDL_DestroyTexture(texture);
                    const rect = c.SDL_Rect{
                        .x = MARGIN + 300,
                        .y = COUNTER_TOP + @as(c.c_int, @intCast(i)) * 25 + 5,
                        .w = max_surface.*.w,
                        .h = max_surface.*.h,
                    };
                    _ = c.SDL_RenderCopy(renderer, texture, null, &rect);
                }
            }
        }

        // Draw counter graph
        var points = std.array_list.Managed(c.SDL_Point).init(std.heap.page_allocator);
        defer points.deinit();

        const graph_height = 80;
        const graph_top = COUNTER_TOP + @as(c.c_int, @intCast(i)) * 25 + 20;

        // Generate counter points
        for (profile_data.counters.items) |counter| {
            if (!std.mem.eql(u8, counter.name, name)) continue;

            if (counter.timestamp >= view.view_start and
                counter.timestamp <= view.view_start + view.view_range)
            {
                const x = timeToX(counter.timestamp, view, counter_width);

                const normalized = (counter.value - min_value) / (max_value - min_value);
                const y = graph_top + graph_height - @as(c.c_int, @intFromFloat(normalized * @as(f64, @floatFromInt(graph_height))));

                points.append(c.SDL_Point{
                    .x = x,
                    .y = y,
                }) catch continue;
            }
        }

        // Draw lines between points
        if (points.items.len > 1) {
            _ = c.SDL_SetRenderDrawColor(renderer, 0, 200, 100, 255);

            for (points.items[0 .. points.items.len - 1], 0..) |point, p| {
                const next = points.items[p + 1];
                _ = c.SDL_RenderDrawLine(renderer, point.x, point.y, next.x, next.y);
            }
        }
    }
}

fn drawControls(renderer: ?*c.SDL_Renderer, font: ?*c.TTF_Font, view: ViewState) void {
    if (font == null) return;

    const color = c.SDL_Color{ .r = 200, .g = 200, .b = 200, .a = 255 };

    // Draw playback state
    var buf: [128]u8 = undefined;
    const playback_str = std.fmt.bufPrintZ(&buf, "Playback: {s} | Speed: {d:.1}x | Zoom: {d:.1}ms", .{
        if (view.playing) "Playing" else "Paused",
        view.playback_speed,
        @as(f64, @floatFromInt(view.view_range)) / 1_000_000.0,
    }) catch return;

    const surface = c.TTF_RenderText_Blended(font, playback_str, color);
    if (surface != null) {
        defer c.SDL_FreeSurface(surface);
        const texture = c.SDL_CreateTextureFromSurface(renderer, surface);
        if (texture != null) {
            defer c.SDL_DestroyTexture(texture);
            const rect = c.SDL_Rect{
                .x = MARGIN,
                .y = COUNTER_BOTTOM + 10,
                .w = surface.*.w,
                .h = surface.*.h,
            };
            _ = c.SDL_RenderCopy(renderer, texture, null, &rect);
        }
    }

    // Draw help text
    const help_str = "Controls: Space=Play/Pause | Arrows=Navigate | Mouse Wheel=Zoom | R=Reset View";
    const help_surface = c.TTF_RenderText_Blended(font, help_str, color);
    if (help_surface != null) {
        defer c.SDL_FreeSurface(help_surface);
        const texture = c.SDL_CreateTextureFromSurface(renderer, help_surface);
        if (texture != null) {
            defer c.SDL_DestroyTexture(texture);

            var window_width: c.c_int = undefined;
            var window_height: c.c_int = undefined;
            c.SDL_GetWindowSize(c.SDL_GetWindowFromID(c.SDL_GetWindowID(c.SDL_RenderGetWindow(renderer))), &window_width, &window_height);

            const rect = c.SDL_Rect{
                .x = window_width - help_surface.*.w - MARGIN,
                .y = COUNTER_BOTTOM + 10,
                .w = help_surface.*.w,
                .h = help_surface.*.h,
            };
            _ = c.SDL_RenderCopy(renderer, texture, null, &rect);
        }
    }
}

fn drawEntryDetails(renderer: ?*c.SDL_Renderer, font: ?*c.TTF_Font, entry: ProfileEntry) void {
    if (font == null) return;

    var window_width: c.c_int = undefined;
    var window_height: c.c_int = undefined;
    c.SDL_GetWindowSize(c.SDL_GetWindowFromID(c.SDL_GetWindowID(c.SDL_RenderGetWindow(renderer))), &window_width, &window_height);

    // Draw details box
    const box_width: c.c_int = 400;
    const box_height: c.c_int = 120;
    const box_x: c.c_int = (window_width - box_width) / 2;
    const box_y: c.c_int = window_height - box_height - 20;

    const box_rect = c.SDL_Rect{
        .x = box_x,
        .y = box_y,
        .w = box_width,
        .h = box_height,
    };

    _ = c.SDL_SetRenderDrawColor(renderer, 40, 40, 40, 240);
    _ = c.SDL_RenderFillRect(renderer, &box_rect);

    _ = c.SDL_SetRenderDrawColor(renderer, 100, 100, 100, 255);
    _ = c.SDL_RenderDrawRect(renderer, &box_rect);

    // Draw entry name
    const color = c.SDL_Color{ .r = 220, .g = 220, .b = 220, .a = 255 };
    const name_surface = c.TTF_RenderText_Blended(font, std.mem.sliceTo(entry.name.ptr, 0), color);
    if (name_surface != null) {
        defer c.SDL_FreeSurface(name_surface);
        const texture = c.SDL_CreateTextureFromSurface(renderer, name_surface);
        if (texture != null) {
            defer c.SDL_DestroyTexture(texture);
            const rect = c.SDL_Rect{
                .x = box_x + 10,
                .y = box_y + 10,
                .w = name_surface.*.w,
                .h = name_surface.*.h,
            };
            _ = c.SDL_RenderCopy(renderer, texture, null, &rect);
        }
    }

    // Draw duration
    var buf: [128]u8 = undefined;
    const duration_ns = entry.duration();
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;
    const duration_str = std.fmt.bufPrintZ(&buf, "Duration: {d:.3}ms", .{duration_ms}) catch return;

    const duration_surface = c.TTF_RenderText_Blended(font, duration_str, color);
    if (duration_surface != null) {
        defer c.SDL_FreeSurface(duration_surface);
        const texture = c.SDL_CreateTextureFromSurface(renderer, duration_surface);
        if (texture != null) {
            defer c.SDL_DestroyTexture(texture);
            const rect = c.SDL_Rect{
                .x = box_x + 10,
                .y = box_y + 35,
                .w = duration_surface.*.w,
                .h = duration_surface.*.h,
            };
            _ = c.SDL_RenderCopy(renderer, texture, null, &rect);
        }
    }

    // Draw thread ID
    const thread_str = std.fmt.bufPrintZ(&buf, "Thread ID: {d}", .{entry.thread_id}) catch return;
    const thread_surface = c.TTF_RenderText_Blended(font, thread_str, color);
    if (thread_surface != null) {
        defer c.SDL_FreeSurface(thread_surface);
        const texture = c.SDL_CreateTextureFromSurface(renderer, thread_surface);
        if (texture != null) {
            defer c.SDL_DestroyTexture(texture);
            const rect = c.SDL_Rect{
                .x = box_x + 10,
                .y = box_y + 60,
                .w = thread_surface.*.w,
                .h = thread_surface.*.h,
            };
            _ = c.SDL_RenderCopy(renderer, texture, null, &rect);
        }
    }

    // Draw parent info
    const parent_str = std.fmt.bufPrintZ(&buf, "Parent ID: {?}", .{entry.parent_id}) catch return;
    const parent_surface = c.TTF_RenderText_Blended(font, parent_str, color);
    if (parent_surface != null) {
        defer c.SDL_FreeSurface(parent_surface);
        const texture = c.SDL_CreateTextureFromSurface(renderer, parent_surface);
        if (texture != null) {
            defer c.SDL_DestroyTexture(texture);
            const rect = c.SDL_Rect{
                .x = box_x + 10,
                .y = box_y + 85,
                .w = parent_surface.*.w,
                .h = parent_surface.*.h,
            };
            _ = c.SDL_RenderCopy(renderer, texture, null, &rect);
        }
    }
}

fn drawMemoryView(renderer: ?*c.SDL_Renderer, font: ?*c.TTF_Font, profile_data: ProfileData, view: ViewState) void {
    var window_width: c.c_int = undefined;
    var window_height: c.c_int = undefined;
    c.SDL_GetWindowSize(c.SDL_GetWindowFromID(c.SDL_GetWindowID(c.SDL_RenderGetWindow(renderer))), &window_width, &window_height);

    const memory_width = window_width - 2 * MARGIN;

    // Draw memory view background
    {
        const rect = c.SDL_Rect{
            .x = MARGIN,
            .y = MEMORY_TOP,
            .w = memory_width,
            .h = MEMORY_HEIGHT,
        };
        _ = c.SDL_SetRenderDrawColor(renderer, 20, 20, 20, 255);
        _ = c.SDL_RenderFillRect(renderer, &rect);

        _ = c.SDL_SetRenderDrawColor(renderer, 60, 60, 60, 255);
        _ = c.SDL_RenderDrawRect(renderer, &rect);
    }

    // Draw title
    if (font != null) {
        const color = c.SDL_Color{ .r = 200, .g = 200, .b = 200, .a = 255 };
        const surface = c.TTF_RenderText_Blended(font, "Memory Allocations", color);

        if (surface != null) {
            defer c.SDL_FreeSurface(surface);
            const texture = c.SDL_CreateTextureFromSurface(renderer, surface);
            if (texture != null) {
                defer c.SDL_DestroyTexture(texture);

                const rect = c.SDL_Rect{
                    .x = MARGIN + 10,
                    .y = MEMORY_TOP + 5,
                    .w = surface.*.w,
                    .h = surface.*.h,
                };
                _ = c.SDL_RenderCopy(renderer, texture, null, &rect);
            }
        }
    }

    // Find live allocations (not freed) that might be leaks
    var potential_leaks = std.array_list.Managed(*const MemoryAllocation).init(std.heap.page_allocator);
    defer potential_leaks.deinit();

    // Calculate total allocated memory at each timestamp in the view
    var total_memory: usize = 0;
    var peak_memory: usize = 0;
    var memory_points = std.array_list.Managed(struct { timestamp: u64, total: usize }).init(std.heap.page_allocator);
    defer memory_points.deinit();

    // Process allocations in timestamp order
    var sorted_allocs = std.array_list.Managed(MemoryAllocation).init(std.heap.page_allocator);
    defer sorted_allocs.deinit();

    for (profile_data.allocations.items) |alloc| {
        sorted_allocs.append(alloc) catch continue;
    }

    // Sort by timestamp
    std.sort.sort(MemoryAllocation, sorted_allocs.items, {}, struct {
        fn lessThan(_: void, a: MemoryAllocation, b: MemoryAllocation) bool {
            return a.timestamp < b.timestamp;
        }
    }.lessThan);

    // Process allocations to build memory usage graph
    for (sorted_allocs.items) |alloc| {
        if (!alloc.freed) {
            total_memory += alloc.size;
            potential_leaks.append(&alloc) catch continue;
        } else {
            total_memory -= alloc.size;
        }

        peak_memory = @max(peak_memory, total_memory);

        memory_points.append(.{
            .timestamp = alloc.timestamp,
            .total = total_memory,
        }) catch continue;
    }

    // Draw memory usage graph
    if (memory_points.items.len > 1) {
        // Draw Y-axis labels
        if (font != null) {
            var buf: [64]u8 = undefined;
            const peak_str = std.fmt.bufPrintZ(&buf, "Peak: {d:.2} MB", .{@as(f64, @floatFromInt(peak_memory)) / (1024 * 1024)}) catch return;

            const color = c.SDL_Color{ .r = 200, .g = 200, .b = 200, .a = 255 };
            const surface = c.TTF_RenderText_Blended(font, peak_str, color);

            if (surface != null) {
                defer c.SDL_FreeSurface(surface);
                const texture = c.SDL_CreateTextureFromSurface(renderer, surface);
                if (texture != null) {
                    defer c.SDL_DestroyTexture(texture);

                    const rect = c.SDL_Rect{
                        .x = MARGIN + memory_width - surface.*.w - 10,
                        .y = MEMORY_TOP + 5,
                        .w = surface.*.w,
                        .h = surface.*.h,
                    };
                    _ = c.SDL_RenderCopy(renderer, texture, null, &rect);
                }
            }
        }

        // Draw memory usage line graph
        const graph_height = MEMORY_HEIGHT - 40;
        const graph_top = MEMORY_TOP + 30;

        _ = c.SDL_SetRenderDrawColor(renderer, 0, 180, 120, 255);

        var prev_x: c.c_int = MARGIN;
        var prev_y: c.c_int = MEMORY_BOTTOM - 10;

        for (memory_points.items) |point| {
            if (point.timestamp < view.view_start or point.timestamp > view.view_start + view.view_range) continue;

            const x = timeToX(point.timestamp, view, memory_width);
            const normalized = if (peak_memory > 0) @as(f32, @floatFromInt(point.total)) / @as(f32, @floatFromInt(peak_memory)) else 0;
            const y = graph_top + graph_height - @as(c.c_int, @intFromFloat(normalized * @as(f32, @floatFromInt(graph_height))));

            _ = c.SDL_RenderDrawLine(renderer, prev_x, prev_y, x, y);

            prev_x = x;
            prev_y = y;
        }
    }

    // Display potential memory leaks as a list
    if (potential_leaks.items.len > 0) {
        const leak_count = @min(potential_leaks.items.len, 5);
        const list_top = MEMORY_BOTTOM - @as(c.c_int, @intCast(leak_count * 20)) - 5;

        if (font != null) {
            const color = c.SDL_Color{ .r = 255, .g = 120, .b = 120, .a = 255 };
            const title_surface = c.TTF_RenderText_Blended(font, "Potential Leaks:", color);

            if (title_surface != null) {
                defer c.SDL_FreeSurface(title_surface);
                const texture = c.SDL_CreateTextureFromSurface(renderer, title_surface);
                if (texture != null) {
                    defer c.SDL_DestroyTexture(texture);

                    const rect = c.SDL_Rect{
                        .x = window_width - 300,
                        .y = list_top - 20,
                        .w = title_surface.*.w,
                        .h = title_surface.*.h,
                    };
                    _ = c.SDL_RenderCopy(renderer, texture, null, &rect);
                }
            }

            for (potential_leaks.items[0..leak_count], 0..) |leak, i| {
                var buf: [128]u8 = undefined;
                const leak_str = std.fmt.bufPrintZ(&buf, "{s}: {d} bytes", .{ leak.category, leak.size }) catch continue;

                const leak_surface = c.TTF_RenderText_Blended(font, leak_str, color);
                if (leak_surface != null) {
                    defer c.SDL_FreeSurface(leak_surface);
                    const texture = c.SDL_CreateTextureFromSurface(renderer, leak_surface);
                    if (texture != null) {
                        defer c.SDL_DestroyTexture(texture);

                        const rect = c.SDL_Rect{
                            .x = window_width - 290,
                            .y = list_top + @as(c.c_int, @intCast(i * 20)),
                            .w = leak_surface.*.w,
                            .h = leak_surface.*.h,
                        };
                        _ = c.SDL_RenderCopy(renderer, texture, null, &rect);
                    }
                }
            }
        }
    }
}

fn calculateMarkerDistance(time_span_ns: u64) u64 {
    // Aim for roughly 10 markers across the view
    const target_marker_count = 10;
    const target_marker_distance = @as(f64, @floatFromInt(time_span_ns)) / target_marker_count;

    // Possible marker distances in nanoseconds
    const distances = [_]u64{
        1_000_000, // 1ms
        5_000_000, // 5ms
        10_000_000, // 10ms
        50_000_000, // 50ms
        100_000_000, // 100ms
        500_000_000, // 500ms
        1_000_000_000, // 1s
        5_000_000_000, // 5s
        10_000_000_000, // 10s
        60_000_000_000, // 1min
    };

    // Find the closest distance
    var best_distance: u64 = distances[0];
    var best_diff: f64 = std.math.abs(@as(f64, @floatFromInt(distances[0])) - target_marker_distance);

    for (distances[1..]) |distance| {
        const diff = std.math.abs(@as(f64, @floatFromInt(distance)) - target_marker_distance);
        if (diff < best_diff) {
            best_distance = distance;
            best_diff = diff;
        }
    }

    return best_distance;
}
