//! MFS Engine - Core Configuration System
//! Flexible configuration management with multiple sources and validation.
//!
//! Features:
//! - Multiple configuration sources (files, environment, command line)
//! - Type-safe configuration values
//! - Hierarchical configuration with dot notation
//! - Configuration validation and schemas
//! - Hot-reloading support
//! - Multiple format support (JSON, TOML planned)
//! - Default values and overrides
//! - Thread-safe access
//!
//! @thread-safe: Config struct is thread-safe when thread_safe = true
//! @allocator-aware: yes
//! @platform: all

const std = @import("std");
const builtin = @import("builtin");
const core = @import("mod.zig");

// =============================================================================
// Types and Constants
// =============================================================================

/// Configuration value types
pub const Value = union(enum) {
    string: []const u8,
    integer: i64,
    float: f64,
    boolean: bool,
    array: []Value,
    object: std.StringHashMap(Value),
    null: void,

    /// Get value as string
    pub fn asString(self: Value) ?[]const u8 {
        return switch (self) {
            .string => |s| s,
            .boolean => |b| if (b) "true" else "false",
            .integer => |i| std.fmt.allocPrint(std.heap.page_allocator, "{}", .{i}) catch null,
            .float => |f| std.fmt.allocPrint(std.heap.page_allocator, "{d}", .{f}) catch null,
            else => null,
        };
    }

    /// Get value as integer
    pub fn asInt(self: Value) ?i64 {
        return switch (self) {
            .integer => |i| i,
            .float => |f| @intFromFloat(f),
            .boolean => |b| if (b) 1 else 0,
            .string => |s| std.fmt.parseInt(i64, s, 10) catch null,
            else => null,
        };
    }

    /// Get value as float
    pub fn asFloat(self: Value) ?f64 {
        return switch (self) {
            .float => |f| f,
            .integer => |i| @floatFromInt(i),
            .string => |s| std.fmt.parseFloat(f64, s) catch null,
            else => null,
        };
    }

    /// Get value as boolean
    pub fn asBool(self: Value) ?bool {
        return switch (self) {
            .boolean => |b| b,
            .integer => |i| i != 0,
            .float => |f| f != 0.0,
            .string => |s| blk: {
                if (std.ascii.eqlIgnoreCase(s, "true") or std.ascii.eqlIgnoreCase(s, "yes") or std.ascii.eqlIgnoreCase(s, "1")) {
                    break :blk true;
                } else if (std.ascii.eqlIgnoreCase(s, "false") or std.ascii.eqlIgnoreCase(s, "no") or std.ascii.eqlIgnoreCase(s, "0")) {
                    break :blk false;
                }
                break :blk null;
            },
            else => null,
        };
    }

    /// Get value as array
    pub fn asArray(self: Value) ?[]Value {
        return switch (self) {
            .array => |a| a,
            else => null,
        };
    }

    /// Get value as object
    pub fn asObject(self: Value) ?std.StringHashMap(Value) {
        return switch (self) {
            .object => |o| o,
            else => null,
        };
    }

    /// Check if value is null
    pub fn isNull(self: Value) bool {
        return switch (self) {
            .null => true,
            else => false,
        };
    }

    /// Clone value (deep copy)
    pub fn clone(self: Value, allocator: std.mem.Allocator) !Value {
        return switch (self) {
            .string => |s| .{ .string = try allocator.dupe(u8, s) },
            .integer => |i| .{ .integer = i },
            .float => |f| .{ .float = f },
            .boolean => |b| .{ .boolean = b },
            .null => .null,
            .array => |arr| blk: {
                var new_arr = try allocator.alloc(Value, arr.len);
                for (arr, 0..) |item, i| {
                    new_arr[i] = try item.clone(allocator);
                }
                break :blk .{ .array = new_arr };
            },
            .object => |obj| blk: {
                var new_obj = std.StringHashMap(Value).init(allocator);
                var iter = obj.iterator();
                while (iter.next()) |entry| {
                    const key = try allocator.dupe(u8, entry.key_ptr.*);
                    const value = try entry.value_ptr.clone(allocator);
                    try new_obj.put(key, value);
                }
                break :blk .{ .object = new_obj };
            },
        };
    }

    /// Free value resources
    pub fn deinit(self: *Value, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .string => |s| allocator.free(s),
            .array => |arr| {
                for (arr) |*item| {
                    item.deinit();
                }
                allocator.free(arr);
            },
            .object => |*obj| {
                var iter = obj.iterator();
                while (iter.next()) |entry| {
                    allocator.free(entry.key_ptr.*);
                    entry.value_ptr.deinit();
                }
                obj.deinit();
            },
            else => {},
        }
    }
};

// Legacy alias
pub const ConfigValue = Value;

/// Configuration source
pub const Source = enum {
    default,
    file,
    environment,
    command_line,
    runtime,

    /// Get priority (higher number = higher priority)
    pub fn priority(self: Source) u8 {
        return switch (self) {
            .default => 0,
            .file => 1,
            .environment => 2,
            .command_line => 3,
            .runtime => 4,
        };
    }
};

/// Configuration entry with metadata
pub const Entry = struct {
    value: Value,
    source: Source,
    description: ?[]const u8 = null,
    validator: ?*const Validator = null,

    /// Check if this entry can be overridden by the given source
    pub fn canOverride(self: Entry, new_source: Source) bool {
        return new_source.priority() >= self.source.priority();
    }
};

/// Configuration validator function type
pub const Validator = fn (value: Value) bool;

/// Configuration schema for validation
pub const Schema = struct {
    allocator: std.mem.Allocator,
    entries: std.StringHashMap(SchemaEntry),

    const SchemaEntry = struct {
        type: ValueType,
        required: bool = false,
        default: ?Value = null,
        validator: ?*const Validator = null,
        description: ?[]const u8 = null,
    };

    const ValueType = enum {
        string,
        integer,
        float,
        boolean,
        array,
        object,
        any,
    };

    /// Create a new schema
    pub fn init(allocator: std.mem.Allocator) Schema {
        return .{
            .allocator = allocator,
            .entries = std.StringHashMap(SchemaEntry).init(allocator),
        };
    }

    /// Cleanup schema
    pub fn deinit(self: *Schema) void {
        self.entries.deinit();
    }

    /// Add schema entry
    pub fn add(
        self: *Schema,
        key: []const u8,
        value_type: ValueType,
        required: bool,
        default: ?Value,
        validator: ?*const Validator,
        description: ?[]const u8,
    ) !void {
        try self.entries.put(key, .{
            .type = value_type,
            .required = required,
            .default = default,
            .validator = validator,
            .description = description,
        });
    }

    /// Validate configuration against schema
    pub fn validate(self: *const Schema, config: *const Config) !void {
        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            const key = entry.key_ptr.*;
            const schema_entry = entry.value_ptr.*;

            if (config.get(key)) |value| {
                // Validate type
                if (!self.validateType(value, schema_entry.type)) {
                    return error.InvalidType;
                }

                // Run custom validator
                if (schema_entry.validator) |validator| {
                    if (!validator(value)) {
                        return error.ValidationFailed;
                    }
                }
            } else if (schema_entry.required) {
                return error.MissingRequiredField;
            }
        }
    }

    fn validateType(self: *const Schema, value: Value, expected_type: ValueType) bool {
        _ = self;
        return switch (expected_type) {
            .string => switch (value) {
                .string => true,
                else => false,
            },
            .integer => switch (value) {
                .integer => true,
                else => false,
            },
            .float => switch (value) {
                .float => true,
                else => false,
            },
            .boolean => switch (value) {
                .boolean => true,
                else => false,
            },
            .array => switch (value) {
                .array => true,
                else => false,
            },
            .object => switch (value) {
                .object => true,
                else => false,
            },
            .any => true,
        };
    }
};

// =============================================================================
// Configuration Loader
// =============================================================================

/// Configuration loader for different formats
pub const Loader = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    /// Create a new loader
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    /// Load configuration from file (auto-detect format)
    pub fn loadFile(self: *Self, config: *Config, file_path: []const u8) !void {
        if (std.mem.endsWith(u8, file_path, ".json")) {
            try self.loadJson(config, file_path);
        } else {
            return error.UnsupportedFormat;
        }
    }

    /// Load JSON configuration
    pub fn loadJson(self: *Self, config: *Config, file_path: []const u8) !void {
        const file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
            switch (err) {
                error.FileNotFound => {
                    std.log.info("Config file not found: {s}, using defaults", .{file_path});
                    return;
                },
                else => return err,
            }
        };
        defer file.close();

        const contents = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024); // 10MB max
        defer self.allocator.free(contents);

        var parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, contents, .{});
        defer parsed.deinit();

        try self.parseJsonValue(config, "", parsed.value);
    }

    fn parseJsonValue(self: *Self, config: *Config, prefix: []const u8, json_value: std.json.Value) !void {
        switch (json_value) {
            .object => |obj| {
                var iter = obj.iterator();
                while (iter.next()) |entry| {
                    const key = entry.key_ptr.*;
                    const full_key = if (prefix.len > 0)
                        try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ prefix, key })
                    else
                        try self.allocator.dupe(u8, key);
                    defer self.allocator.free(full_key);

                    try self.parseJsonValue(config, full_key, entry.value_ptr.*);
                }
            },
            else => {
                const value = try self.jsonToValue(json_value);
                try config.set(prefix, value, .file, null);
            },
        }
    }

    fn jsonToValue(self: *Self, json: std.json.Value) !Value {
        return switch (json) {
            .null => .null,
            .bool => |b| .{ .boolean = b },
            .integer => |i| .{ .integer = i },
            .float => |f| .{ .float = f },
            .number_string => |s| blk: {
                if (std.fmt.parseInt(i64, s, 10)) |i| {
                    break :blk .{ .integer = i };
                } else |_| {
                    if (std.fmt.parseFloat(f64, s)) |f| {
                        break :blk .{ .float = f };
                    } else |_| {
                        break :blk .{ .string = try self.allocator.dupe(u8, s) };
                    }
                }
            },
            .string => |s| .{ .string = try self.allocator.dupe(u8, s) },
            .array => |arr| blk: {
                var values = try self.allocator.alloc(Value, arr.items.len);
                for (arr.items, 0..) |item, i| {
                    values[i] = try self.jsonToValue(item);
                }
                break :blk .{ .array = values };
            },
            .object => |obj| blk: {
                var map = std.StringHashMap(Value).init(self.allocator);
                var iter = obj.iterator();
                while (iter.next()) |entry| {
                    const key = try self.allocator.dupe(u8, entry.key_ptr.*);
                    const value = try self.jsonToValue(entry.value_ptr.*);
                    try map.put(key, value);
                }
                break :blk .{ .object = map };
            },
        };
    }
};

// =============================================================================
// Main Configuration Manager
// =============================================================================

/// Main configuration manager
pub const Config = struct {
    allocator: std.mem.Allocator,
    entries: std.StringHashMap(Entry),
    mutex: ?std.Thread.Mutex,
    file_path: ?[]const u8,
    hot_reload: bool,
    schema: ?*Schema,

    const Self = @This();

    /// Create a new configuration manager
    ///
    /// **Thread Safety**: Set `thread_safe` to true for thread-safe access
    pub fn init(allocator: std.mem.Allocator, thread_safe: bool) Self {
        return .{
            .allocator = allocator,
            .entries = std.StringHashMap(Entry).init(allocator),
            .mutex = if (thread_safe) std.Thread.Mutex{} else null,
            .file_path = null,
            .hot_reload = false,
            .schema = null,
        };
    }

    /// Cleanup configuration
    pub fn deinit(self: *Self) void {
        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            if (entry.value_ptr.description) |desc| {
                self.allocator.free(desc);
            }
            entry.value_ptr.value.deinit();
        }
        self.entries.deinit();

        if (self.file_path) |path| {
            self.allocator.free(path);
        }
    }

    /// Set configuration schema
    pub fn setSchema(self: *Self, schema: *Schema) void {
        if (self.mutex) |*m| m.lock();
        defer if (self.mutex) |*m| m.unlock();

        self.schema = schema;
    }

    /// Load configuration from file
    pub fn loadFromFile(self: *Self, file_path: []const u8) !void {
        if (self.mutex) |*m| m.lock();
        defer if (self.mutex) |*m| m.unlock();

        var loader = Loader.init(self.allocator);
        try loader.loadFile(self, file_path);

        if (self.file_path) |old_path| {
            self.allocator.free(old_path);
        }
        self.file_path = try self.allocator.dupe(u8, file_path);

        // Validate against schema if set
        if (self.schema) |schema| {
            try schema.validate(self);
        }
    }

    /// Parse command line arguments
    pub fn parseArgs(self: *Self, args: []const []const u8) !void {
        if (self.mutex) |*m| m.lock();
        defer if (self.mutex) |*m| m.unlock();

        var i: usize = 1; // Skip program name
        while (i < args.len) : (i += 1) {
            const arg = args[i];

            if (std.mem.startsWith(u8, arg, "--")) {
                const option = arg[2..];

                if (std.mem.indexOf(u8, option, "=")) |eq_pos| {
                    // --key=value format
                    const key = option[0..eq_pos];
                    const value_str = option[eq_pos + 1 ..];
                    try self.setFromString(key, value_str, .command_line, null);
                } else if (i + 1 < args.len and !std.mem.startsWith(u8, args[i + 1], "--")) {
                    // --key value format
                    const value_str = args[i + 1];
                    try self.setFromString(option, value_str, .command_line, null);
                    i += 1;
                } else {
                    // Boolean flag
                    try self.setInternal(option, .{ .boolean = true }, .command_line, null);
                }
            } else if (std.mem.startsWith(u8, arg, "-") and arg.len == 2) {
                // Short option like -v
                const key = try std.fmt.allocPrint(self.allocator, "{c}", .{arg[1]});
                defer self.allocator.free(key);
                try self.setInternal(key, .{ .boolean = true }, .command_line, null);
            }
        }
    }

    /// Load from environment variables
    pub fn loadFromEnv(self: *Self, prefix: []const u8) !void {
        if (self.mutex) |*m| m.lock();
        defer if (self.mutex) |*m| m.unlock();

        var env_map = try std.process.getEnvMap(self.allocator);
        defer env_map.deinit();

        var iter = env_map.iterator();
        while (iter.next()) |entry| {
            const key = entry.key_ptr.*;
            if (std.mem.startsWith(u8, key, prefix)) {
                const config_key = key[prefix.len..];
                if (config_key.len > 0) {
                    // Convert MY_APP_KEY to my_app.key
                    var formatted_key = try self.allocator.alloc(u8, config_key.len);
                    defer self.allocator.free(formatted_key);

                    var j: usize = 0;
                    for (config_key) |c| {
                        if (c == '_') {
                            formatted_key[j] = '.';
                        } else {
                            formatted_key[j] = std.ascii.toLower(c);
                        }
                        j += 1;
                    }

                    try self.setFromString(formatted_key[0..j], entry.value_ptr.*, .environment, null);
                }
            }
        }
    }

    /// Get configuration value
    pub fn get(self: *const Self, key: []const u8) ?Value {
        if (self.mutex) |*m| m.lock();
        defer if (self.mutex) |*m| m.unlock();

        if (self.entries.get(key)) |entry| {
            return entry.value;
        }
        return null;
    }

    /// Get configuration value with default
    pub fn getOr(self: *const Self, key: []const u8, default: Value) Value {
        return self.get(key) orelse default;
    }

    /// Get typed configuration value
    pub fn getString(self: *const Self, key: []const u8) ?[]const u8 {
        if (self.get(key)) |value| {
            return value.asString();
        }
        return null;
    }

    pub fn getInt(self: *const Self, key: []const u8) ?i64 {
        if (self.get(key)) |value| {
            return value.asInt();
        }
        return null;
    }

    pub fn getFloat(self: *const Self, key: []const u8) ?f64 {
        if (self.get(key)) |value| {
            return value.asFloat();
        }
        return null;
    }

    pub fn getBool(self: *const Self, key: []const u8) ?bool {
        if (self.get(key)) |value| {
            return value.asBool();
        }
        return null;
    }

    /// Set configuration value
    pub fn set(self: *Self, key: []const u8, value: Value, source: Source, description: ?[]const u8) !void {
        if (self.mutex) |*m| m.lock();
        defer if (self.mutex) |*m| m.unlock();

        try self.setInternal(key, value, source, description);
    }

    fn setInternal(self: *Self, key: []const u8, value: Value, source: Source, description: ?[]const u8) !void {
        // Check if can override existing value
        if (self.entries.get(key)) |existing| {
            if (!existing.canOverride(source)) {
                return;
            }
        }

        // Validate against schema if set
        if (self.schema) |schema| {
            if (schema.entries.get(key)) |schema_entry| {
                if (!schema.validateType(value, schema_entry.type)) {
                    return error.InvalidType;
                }
                if (schema_entry.validator) |validator| {
                    if (!validator(value)) {
                        return error.ValidationFailed;
                    }
                }
            }
        }

        const key_copy = try self.allocator.dupe(u8, key);
        const desc_copy = if (description) |d| try self.allocator.dupe(u8, d) else null;
        const value_copy = try value.clone(self.allocator);

        try self.entries.put(key_copy, .{
            .value = value_copy,
            .source = source,
            .description = desc_copy,
        });
    }

    /// Set value from string
    pub fn setFromString(self: *Self, key: []const u8, value_str: []const u8, source: Source, description: ?[]const u8) !void {
        const value = try self.parseValue(value_str);
        try self.set(key, value, source, description);
    }

    fn parseValue(self: *Self, str: []const u8) !Value {
        // Try boolean
        if (std.ascii.eqlIgnoreCase(str, "true") or std.ascii.eqlIgnoreCase(str, "yes")) {
            return .{ .boolean = true };
        } else if (std.ascii.eqlIgnoreCase(str, "false") or std.ascii.eqlIgnoreCase(str, "no")) {
            return .{ .boolean = false };
        }

        // Try integer
        if (std.fmt.parseInt(i64, str, 0)) |i| {
            return .{ .integer = i };
        } else |_| {}

        // Try float
        if (std.fmt.parseFloat(f64, str)) |f| {
            return .{ .float = f };
        } else |_| {}

        // Default to string
        return .{ .string = try self.allocator.dupe(u8, str) };
    }

    /// Check if key exists
    pub fn has(self: *const Self, key: []const u8) bool {
        if (self.mutex) |*m| m.lock();
        defer if (self.mutex) |*m| m.unlock();

        return self.entries.contains(key);
    }

    /// Get all keys
    pub fn keys(self: *const Self, allocator: std.mem.Allocator) ![][]const u8 {
        if (self.mutex) |*m| m.lock();
        defer if (self.mutex) |*m| m.unlock();

        var result = try allocator.alloc([]const u8, self.entries.count());
        var iter = self.entries.iterator();
        var i: usize = 0;
        while (iter.next()) |entry| : (i += 1) {
            result[i] = try allocator.dupe(u8, entry.key_ptr.*);
        }
        return result;
    }

    /// Save configuration to file
    pub fn saveToFile(self: *const Self, file_path: []const u8) !void {
        if (self.mutex) |*m| m.lock();
        defer if (self.mutex) |*m| m.unlock();

        const file = try std.fs.cwd().createFile(file_path, .{});
        defer file.close();

        var jw = std.json.writeStream(file.writer(), .{ .whitespace = .indent_2 });
        try jw.beginObject();

        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            try jw.objectField(entry.key_ptr.*);
            try self.writeJsonValue(&jw, entry.value_ptr.value);
        }

        try jw.endObject();
    }

    fn writeJsonValue(self: *const Self, jw: anytype, value: Value) !void {
        switch (value) {
            .null => try jw.write(null),
            .boolean => |b| try jw.write(b),
            .integer => |i| try jw.write(i),
            .float => |f| try jw.write(f),
            .string => |s| try jw.write(s),
            .array => |arr| {
                try jw.beginArray();
                for (arr) |item| {
                    try self.writeJsonValue(jw, item);
                }
                try jw.endArray();
            },
            .object => |obj| {
                try jw.beginObject();
                var iter = obj.iterator();
                while (iter.next()) |entry| {
                    try jw.objectField(entry.key_ptr.*);
                    try self.writeJsonValue(jw, entry.value_ptr.*);
                }
                try jw.endObject();
            },
        }
    }
};

// =============================================================================
// Default Configurations
// =============================================================================

/// Create default engine configuration
pub fn createDefaultConfig(allocator: std.mem.Allocator) !Config {
    var config = Config.init(allocator, false);

    // Engine settings
    try config.set("engine.name", .{ .string = "MFS Engine" }, .default, "Engine name");
    try config.set("engine.version", .{ .string = "1.0.0" }, .default, "Engine version");
    try config.set("engine.target_fps", .{ .integer = 60 }, .default, "Target frame rate");
    try config.set("engine.fixed_timestep", .{ .float = 1.0 / 60.0 }, .default, "Fixed timestep for physics");

    // Window settings
    try config.set("window.width", .{ .integer = 1280 }, .default, "Window width");
    try config.set("window.height", .{ .integer = 720 }, .default, "Window height");
    try config.set("window.title", .{ .string = "MFS Engine" }, .default, "Window title");
    try config.set("window.fullscreen", .{ .boolean = false }, .default, "Fullscreen mode");
    try config.set("window.vsync", .{ .boolean = true }, .default, "Vertical sync");
    try config.set("window.resizable", .{ .boolean = true }, .default, "Window resizable");

    // Graphics settings
    try config.set("graphics.backend", .{ .string = "auto" }, .default, "Graphics backend (auto/vulkan/directx/opengl)");
    try config.set("graphics.validation", .{ .boolean = builtin.mode == .Debug }, .default, "Enable validation layers");
    try config.set("graphics.ray_tracing", .{ .boolean = false }, .default, "Enable ray tracing");
    try config.set("graphics.msaa", .{ .integer = 4 }, .default, "Multisample anti-aliasing samples");

    // Audio settings
    try config.set("audio.enabled", .{ .boolean = true }, .default, "Audio system enabled");
    try config.set("audio.master_volume", .{ .float = 1.0 }, .default, "Master volume (0.0 - 1.0)");
    try config.set("audio.sample_rate", .{ .integer = 44100 }, .default, "Audio sample rate");

    // Physics settings
    try config.set("physics.enabled", .{ .boolean = true }, .default, "Physics system enabled");
    try config.set("physics.gravity.x", .{ .float = 0.0 }, .default, "Gravity X component");
    try config.set("physics.gravity.y", .{ .float = -9.81 }, .default, "Gravity Y component");
    try config.set("physics.gravity.z", .{ .float = 0.0 }, .default, "Gravity Z component");

    // Logging settings
    try config.set("log.level", .{ .string = "info" }, .default, "Minimum log level");
    try config.set("log.file", .{ .boolean = false }, .default, "Enable file logging");
    try config.set("log.file_path", .{ .string = "mfs_engine.log" }, .default, "Log file path");

    return config;
}

/// Create default engine schema
pub fn createDefaultSchema(allocator: std.mem.Allocator) !Schema {
    var schema = Schema.init(allocator);

    // Engine settings
    try schema.add("engine.name", .string, false, null, null, "Engine name");
    try schema.add("engine.version", .string, false, null, null, "Engine version");
    try schema.add("engine.target_fps", .integer, false, null, validatePositiveInt, "Target frame rate");

    // Window settings
    try schema.add("window.width", .integer, false, null, validatePositiveInt, "Window width");
    try schema.add("window.height", .integer, false, null, validatePositiveInt, "Window height");
    try schema.add("window.title", .string, false, null, null, "Window title");
    try schema.add("window.fullscreen", .boolean, false, null, null, "Fullscreen mode");

    // Graphics settings
    try schema.add("graphics.backend", .string, false, null, validateGraphicsBackend, "Graphics backend");
    try schema.add("graphics.validation", .boolean, false, null, null, "Validation layers");

    return schema;
}

// =============================================================================
// Validators
// =============================================================================

fn validatePositiveInt(value: Value) bool {
    if (value.asInt()) |i| {
        return i > 0;
    }
    return false;
}

fn validateGraphicsBackend(value: Value) bool {
    if (value.asString()) |s| {
        return std.mem.eql(u8, s, "auto") or
            std.mem.eql(u8, s, "vulkan") or
            std.mem.eql(u8, s, "directx") or
            std.mem.eql(u8, s, "opengl") or
            std.mem.eql(u8, s, "metal");
    }
    return false;
}

// =============================================================================
// Tests
// =============================================================================

test "config values" {
    const testing = std.testing;

    // Test string value
    const str_val = Value{ .string = "hello" };
    try testing.expectEqualStrings("hello", str_val.asString().?);
    try testing.expect(str_val.asInt() == null);

    // Test integer value
    const int_val = Value{ .integer = 42 };
    try testing.expect(int_val.asInt().? == 42);
    try testing.expect(int_val.asFloat().? == 42.0);
    try testing.expect(int_val.asBool().? == true);

    // Test boolean value
    const bool_val = Value{ .boolean = true };
    try testing.expect(bool_val.asBool().? == true);
    try testing.expect(bool_val.asInt().? == 1);
}

test "config basic operations" {
    const testing = std.testing;

    var config = Config.init(testing.allocator, false);
    defer config.deinit();

    // Test setting and getting values
    try config.set("test.string", .{ .string = "hello" }, .default, "Test string");
    try config.set("test.int", .{ .integer = 42 }, .default, null);
    try config.set("test.bool", .{ .boolean = true }, .default, null);

    try testing.expectEqualStrings("hello", config.getString("test.string").?);
    try testing.expect(config.getInt("test.int").? == 42);
    try testing.expect(config.getBool("test.bool").? == true);

    // Test default values
    const default_str = config.getOr("nonexistent", .{ .string = "default" });
    try testing.expectEqualStrings("default", default_str.asString().?);

    // Test has
    try testing.expect(config.has("test.string"));
    try testing.expect(!config.has("nonexistent"));
}

test "config source priority" {
    const testing = std.testing;

    var config = Config.init(testing.allocator, false);
    defer config.deinit();

    // Set value with low priority
    try config.set("test", .{ .integer = 1 }, .default, null);
    try testing.expect(config.getInt("test").? == 1);

    // Override with higher priority
    try config.set("test", .{ .integer = 2 }, .file, null);
    try testing.expect(config.getInt("test").? == 2);

    // Try to override with lower priority (should fail)
    try config.set("test", .{ .integer = 3 }, .default, null);
    try testing.expect(config.getInt("test").? == 2);

    // Override with command line (highest priority)
    try config.set("test", .{ .integer = 4 }, .command_line, null);
    try testing.expect(config.getInt("test").? == 4);
}

test "config parsing" {
    const testing = std.testing;

    var config = Config.init(testing.allocator, false);
    defer config.deinit();

    // Test string parsing
    try config.setFromString("bool_true", "true", .default, null);
    try config.setFromString("bool_false", "false", .default, null);
    try config.setFromString("int", "42", .default, null);
    try config.setFromString("float", "3.14", .default, null);
    try config.setFromString("string", "hello world", .default, null);

    try testing.expect(config.getBool("bool_true").? == true);
    try testing.expect(config.getBool("bool_false").? == false);
    try testing.expect(config.getInt("int").? == 42);
    try testing.expect(config.getFloat("float").? == 3.14);
    try testing.expectEqualStrings("hello world", config.getString("string").?);
}

test "config command line parsing" {
    const testing = std.testing;

    var config = Config.init(testing.allocator, false);
    defer config.deinit();

    const args = [_][]const u8{
        "program",
        "--width=1920",
        "--height",
        "1080",
        "--fullscreen",
        "-v",
    };

    try config.parseArgs(&args);

    try testing.expect(config.getInt("width").? == 1920);
    try testing.expect(config.getInt("height").? == 1080);
    try testing.expect(config.getBool("fullscreen").? == true);
    try testing.expect(config.getBool("v").? == true);
}

test "config schema validation" {
    const testing = std.testing;

    var config = Config.init(testing.allocator, false);
    defer config.deinit();

    var schema = Schema.init(testing.allocator);
    defer schema.deinit();

    // Add schema entries
    try schema.add("required_field", .string, true, null, null, null);
    try schema.add("optional_field", .integer, false, null, null, null);
    try schema.add("positive_int", .integer, false, null, validatePositiveInt, null);

    config.setSchema(&schema);

    // Valid configuration
    try config.set("required_field", .{ .string = "value" }, .default, null);
    try config.set("positive_int", .{ .integer = 10 }, .default, null);

    // Invalid type should fail
    try testing.expectError(error.InvalidType, config.set("required_field", .{ .integer = 42 }, .default, null));

    // Invalid validation should fail
    try testing.expectError(error.ValidationFailed, config.set("positive_int", .{ .integer = -5 }, .default, null));
}
