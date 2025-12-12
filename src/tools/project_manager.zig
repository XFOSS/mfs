const std = @import("std");

pub const ProjectType = enum {
    game_2d,
    game_3d,
    application,
    library,
    demo,
};

pub const ProjectSettings = struct {
    name: []const u8,
    version: []const u8 = "1.0.0",
    description: []const u8 = "",
    author: []const u8 = "",
    project_type: ProjectType = .game_3d,
    target_platforms: []const []const u8 = &.{},
    build_configuration: []const u8 = "debug",
};

pub const ProjectFile = struct {
    path: []const u8,
    type: []const u8,
    size: u64,
    modified: i64,
};

pub const ProjectManager = struct {
    allocator: std.mem.Allocator,
    current_project_path: ?[]const u8,
    settings: ?ProjectSettings,
    files: std.array_list.Managed(ProjectFile),
    recent_projects: std.array_list.Managed([]const u8),

    pub fn init(allocator: std.mem.Allocator) ProjectManager {
        return ProjectManager{
            .allocator = allocator,
            .current_project_path = null,
            .settings = null,
            .files = std.array_list.Managed(ProjectFile).init(allocator),
            .recent_projects = std.array_list.Managed([]const u8).init(allocator),
        };
    }

    pub fn createProject(self: *ProjectManager, path: []const u8, settings: ProjectSettings) !void {
        self.current_project_path = try self.allocator.dupe(u8, path);
        self.settings = settings;
        // TODO: Create project directory structure
        try self.saveProject();
    }

    pub fn openProject(self: *ProjectManager, path: []const u8) !void {
        self.current_project_path = try self.allocator.dupe(u8, path);
        // TODO: Load project settings and files
        try self.addToRecentProjects(path);
    }

    pub fn saveProject(self: *ProjectManager) !void {
        if (self.current_project_path == null or self.settings == null) {
            return error.NoProjectLoaded;
        }
        // TODO: Save project settings to file
    }

    pub fn closeProject(self: *ProjectManager) void {
        if (self.current_project_path) |path| {
            self.allocator.free(path);
            self.current_project_path = null;
        }
        self.settings = null;
        self.clearFiles();
    }

    pub fn addFile(self: *ProjectManager, file_path: []const u8, file_type: []const u8) !void {
        const file = ProjectFile{
            .path = try self.allocator.dupe(u8, file_path),
            .type = try self.allocator.dupe(u8, file_type),
            .size = 0, // TODO: Get actual file size
            .modified = std.time.timestamp(),
        };
        try self.files.append(file);
    }

    pub fn removeFile(self: *ProjectManager, file_path: []const u8) void {
        for (self.files.items, 0..) |file, i| {
            if (std.mem.eql(u8, file.path, file_path)) {
                self.allocator.free(file.path);
                self.allocator.free(file.type);
                _ = self.files.swapRemove(i);
                break;
            }
        }
    }

    pub fn getFiles(self: *const ProjectManager) []const ProjectFile {
        return self.files.items;
    }

    pub fn getSettings(self: *const ProjectManager) ?ProjectSettings {
        return self.settings;
    }

    pub fn updateSettings(self: *ProjectManager, new_settings: ProjectSettings) void {
        self.settings = new_settings;
    }

    pub fn getCurrentProjectPath(self: *const ProjectManager) ?[]const u8 {
        return self.current_project_path;
    }

    pub fn addToRecentProjects(self: *ProjectManager, path: []const u8) !void {
        const path_copy = try self.allocator.dupe(u8, path);
        try self.recent_projects.append(path_copy);

        // Keep only last 10 recent projects
        if (self.recent_projects.items.len > 10) {
            self.allocator.free(self.recent_projects.orderedRemove(0));
        }
    }

    pub fn getRecentProjects(self: *const ProjectManager) []const []const u8 {
        return self.recent_projects.items;
    }

    pub fn clearFiles(self: *ProjectManager) void {
        for (self.files.items) |file| {
            self.allocator.free(file.path);
            self.allocator.free(file.type);
        }
        self.files.clearRetainingCapacity();
    }

    pub fn deinit(self: *ProjectManager) void {
        self.closeProject();
        self.clearFiles();
        self.files.deinit();

        for (self.recent_projects.items) |path| {
            self.allocator.free(path);
        }
        self.recent_projects.deinit();
    }
};
