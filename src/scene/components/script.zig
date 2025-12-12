const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;

pub const ScriptFunction = struct {
    name: []const u8,
    function: *const fn (*ScriptComponent, []const u8, ?*anyopaque) void,
};

pub const ScriptComponent = struct {
    allocator: Allocator,
    script_name: []const u8,
    enabled: bool,
    functions: ArrayList(ScriptFunction),
    user_data: ?*anyopaque,
    deinit_fn: ?*const fn (*ScriptComponent) void,

    pub fn init(allocator: Allocator, script_name: []const u8) !ScriptComponent {
        return ScriptComponent{
            .allocator = allocator,
            .script_name = try allocator.dupe(u8, script_name),
            .enabled = true,
            .functions = ArrayList(ScriptFunction).init(allocator),
            .user_data = null,
            .deinit_fn = null,
        };
    }

    pub fn deinit(self: *ScriptComponent) void {
        self.allocator.free(self.script_name);
        self.functions.deinit();

        if (self.deinit_fn) |deinit_fn| {
            deinit_fn(self);
        }

        // Note: user_data deallocation should be handled by the deinit_fn
        // since we don't know the type of the data stored in anyopaque
    }

    pub fn registerFunction(self: *ScriptComponent, name: []const u8, function: *const fn (*ScriptComponent, []const u8, ?*anyopaque) void) !void {
        try self.functions.append(ScriptFunction{
            .name = try self.allocator.dupe(u8, name),
            .function = function,
        });
    }

    pub fn callFunction(self: *ScriptComponent, name: []const u8, data: ?*anyopaque) bool {
        for (self.functions.items) |func| {
            if (std.mem.eql(u8, func.name, name)) {
                func.function(self, name, data);
                return true;
            }
        }
        return false;
    }

    pub fn setUserData(self: *ScriptComponent, data: anytype) !void {
        const T = @TypeOf(data);
        const ptr = try self.allocator.create(T);
        ptr.* = data;
        self.user_data = @ptrCast(ptr);
    }

    pub fn getUserData(self: *ScriptComponent, comptime T: type) ?*T {
        if (self.user_data) |data| {
            return @ptrCast(@alignCast(data));
        }
        return null;
    }

    pub fn setDeinitFunction(self: *ScriptComponent, deinit_fn: *const fn (*ScriptComponent) void) void {
        self.deinit_fn = deinit_fn;
    }
};
