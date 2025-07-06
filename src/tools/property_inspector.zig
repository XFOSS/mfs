const std = @import("std");

pub const PropertyType = enum {
    boolean,
    integer,
    float,
    string,
    vector2,
    vector3,
    vector4,
    color,
    texture,
    material,
    enum_value,
    array,
    object,
};

pub const PropertyValue = union(PropertyType) {
    boolean: bool,
    integer: i64,
    float: f64,
    string: []const u8,
    vector2: [2]f32,
    vector3: [3]f32,
    vector4: [4]f32,
    color: [4]f32,
    texture: []const u8,
    material: []const u8,
    enum_value: []const u8,
    array: []PropertyValue,
    object: std.StringHashMap(PropertyValue),
};

pub const PropertyDefinition = struct {
    name: []const u8,
    display_name: []const u8,
    description: ?[]const u8 = null,
    property_type: PropertyType,
    default_value: PropertyValue,
    min_value: ?f64 = null,
    max_value: ?f64 = null,
    enum_options: ?[]const []const u8 = null,
    read_only: bool = false,
};

pub const InspectorConfig = struct {
    show_descriptions: bool = true,
    group_properties: bool = true,
    enable_undo_redo: bool = true,
};

pub const PropertyInspector = struct {
    allocator: std.mem.Allocator,
    config: InspectorConfig,
    properties: std.StringHashMap(PropertyValue),
    definitions: std.StringHashMap(PropertyDefinition),
    selected_object: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator, config: InspectorConfig) PropertyInspector {
        return PropertyInspector{
            .allocator = allocator,
            .config = config,
            .properties = std.StringHashMap(PropertyValue).init(allocator),
            .definitions = std.StringHashMap(PropertyDefinition).init(allocator),
            .selected_object = null,
        };
    }

    pub fn setSelectedObject(self: *PropertyInspector, object_id: ?[]const u8) !void {
        if (object_id) |id| {
            self.selected_object = try self.allocator.dupe(u8, id);
        } else {
            if (self.selected_object) |old_id| {
                self.allocator.free(old_id);
            }
            self.selected_object = null;
        }
        // TODO: Load properties for selected object
    }

    pub fn addPropertyDefinition(self: *PropertyInspector, definition: PropertyDefinition) !void {
        const name_copy = try self.allocator.dupe(u8, definition.name);
        try self.definitions.put(name_copy, definition);
    }

    pub fn setProperty(self: *PropertyInspector, name: []const u8, value: PropertyValue) !void {
        const name_copy = try self.allocator.dupe(u8, name);
        try self.properties.put(name_copy, value);
        // TODO: Trigger property change callback
    }

    pub fn getProperty(self: *const PropertyInspector, name: []const u8) ?PropertyValue {
        return self.properties.get(name);
    }

    pub fn hasProperty(self: *const PropertyInspector, name: []const u8) bool {
        return self.properties.contains(name);
    }

    pub fn getPropertyDefinition(self: *const PropertyInspector, name: []const u8) ?PropertyDefinition {
        return self.definitions.get(name);
    }

    pub fn getAllProperties(self: *const PropertyInspector) std.StringHashMap(PropertyValue).Iterator {
        return self.properties.iterator();
    }

    pub fn validateProperty(self: *const PropertyInspector, name: []const u8, value: PropertyValue) bool {
        if (self.getPropertyDefinition(name)) |def| {
            return def.property_type == @as(PropertyType, value);
        }
        return false;
    }

    pub fn resetToDefaults(self: *PropertyInspector) !void {
        var def_iter = self.definitions.iterator();
        while (def_iter.next()) |entry| {
            try self.setProperty(entry.key_ptr.*, entry.value_ptr.default_value);
        }
    }

    pub fn getSelectedObject(self: *const PropertyInspector) ?[]const u8 {
        return self.selected_object;
    }

    pub fn deinit(self: *PropertyInspector) void {
        if (self.selected_object) |id| {
            self.allocator.free(id);
        }

        var prop_iter = self.properties.iterator();
        while (prop_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.properties.deinit();

        var def_iter = self.definitions.iterator();
        while (def_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.definitions.deinit();
    }
};
