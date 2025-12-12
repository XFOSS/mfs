const std = @import("std");

pub const ProjectRole = enum {
    owner,
    admin,
    contributor,
    viewer,
};

pub const InviteStatus = enum {
    pending,
    accepted,
    declined,
    expired,
};

pub const ProjectMember = struct {
    user_id: u64,
    username: []const u8,
    role: ProjectRole,
    joined_at: i64,
    last_active: i64,
    permissions: []const []const u8,
};

pub const ProjectInvite = struct {
    id: u64,
    project_id: u64,
    inviter_id: u64,
    invitee_email: []const u8,
    role: ProjectRole,
    status: InviteStatus,
    created_at: i64,
    expires_at: i64,
    message: ?[]const u8 = null,
};

pub const CollaborativeProject = struct {
    id: u64,
    name: []const u8,
    description: []const u8,
    owner_id: u64,
    created_at: i64,
    updated_at: i64,
    members: std.array_list.Managed(ProjectMember),
    invites: std.array_list.Managed(ProjectInvite),
    is_public: bool = false,
    max_members: u32 = 10,
};

pub const CollaborationConfig = struct {
    max_projects_per_user: u32 = 5,
    max_members_per_project: u32 = 20,
    invite_expiry_days: u32 = 7,
    enable_public_projects: bool = true,
};

pub const CollaborationManager = struct {
    allocator: std.mem.Allocator,
    config: CollaborationConfig,
    projects: std.array_list.Managed(CollaborativeProject),
    next_project_id: u64,
    next_invite_id: u64,

    pub fn init(allocator: std.mem.Allocator, config: CollaborationConfig) CollaborationManager {
        return CollaborationManager{
            .allocator = allocator,
            .config = config,
            .projects = std.array_list.Managed(CollaborativeProject).init(allocator),
            .next_project_id = 1,
            .next_invite_id = 1,
        };
    }

    pub fn createProject(self: *CollaborationManager, owner_id: u64, name: []const u8, description: []const u8) !u64 {
        const now = std.time.timestamp();
        const project = CollaborativeProject{
            .id = self.next_project_id,
            .name = try self.allocator.dupe(u8, name),
            .description = try self.allocator.dupe(u8, description),
            .owner_id = owner_id,
            .created_at = now,
            .updated_at = now,
            .members = std.array_list.Managed(ProjectMember).init(self.allocator),
            .invites = std.array_list.Managed(ProjectInvite).init(self.allocator),
        };
        try self.projects.append(project);
        self.next_project_id += 1;
        return project.id;
    }

    pub fn inviteToProject(self: *CollaborationManager, project_id: u64, inviter_id: u64, invitee_email: []const u8, role: ProjectRole, message: ?[]const u8) !u64 {
        const project = self.findProject(project_id) orelse return error.ProjectNotFound;

        const now = std.time.timestamp();
        const expires_at = now + (@as(i64, @intCast(self.config.invite_expiry_days)) * 24 * 60 * 60);

        const invite = ProjectInvite{
            .id = self.next_invite_id,
            .project_id = project_id,
            .inviter_id = inviter_id,
            .invitee_email = try self.allocator.dupe(u8, invitee_email),
            .role = role,
            .status = .pending,
            .created_at = now,
            .expires_at = expires_at,
            .message = if (message) |msg| try self.allocator.dupe(u8, msg) else null,
        };

        try project.invites.append(invite);
        self.next_invite_id += 1;
        return invite.id;
    }

    pub fn acceptInvite(self: *CollaborationManager, invite_id: u64, user_id: u64, username: []const u8) !void {
        for (self.projects.items) |*project| {
            for (project.invites.items) |*invite| {
                if (invite.id == invite_id and invite.status == .pending) {
                    // Check if invite is expired
                    if (std.time.timestamp() > invite.expires_at) {
                        invite.status = .expired;
                        return error.InviteExpired;
                    }

                    // Add member to project
                    const member = ProjectMember{
                        .user_id = user_id,
                        .username = try self.allocator.dupe(u8, username),
                        .role = invite.role,
                        .joined_at = std.time.timestamp(),
                        .last_active = std.time.timestamp(),
                        .permissions = &.{},
                    };
                    try project.members.append(member);
                    invite.status = .accepted;
                    return;
                }
            }
        }
        return error.InviteNotFound;
    }

    pub fn removeFromProject(self: *CollaborationManager, project_id: u64, user_id: u64, remover_id: u64) !void {
        const project = self.findProject(project_id) orelse return error.ProjectNotFound;

        // Check permissions (only owner/admin can remove members)
        if (!self.canManageMembers(project, remover_id)) {
            return error.InsufficientPermissions;
        }

        for (project.members.items, 0..) |member, i| {
            if (member.user_id == user_id) {
                self.allocator.free(member.username);
                _ = project.members.swapRemove(i);
                return;
            }
        }
        return error.MemberNotFound;
    }

    pub fn updateMemberRole(self: *CollaborationManager, project_id: u64, user_id: u64, new_role: ProjectRole, updater_id: u64) !void {
        const project = self.findProject(project_id) orelse return error.ProjectNotFound;

        // Check permissions
        if (!self.canManageMembers(project, updater_id)) {
            return error.InsufficientPermissions;
        }

        for (project.members.items) |*member| {
            if (member.user_id == user_id) {
                member.role = new_role;
                return;
            }
        }
        return error.MemberNotFound;
    }

    pub fn getUserProjects(self: *const CollaborationManager, user_id: u64, results: *std.array_list.Managed(CollaborativeProject)) !void {
        results.clearRetainingCapacity();
        for (self.projects.items) |project| {
            if (project.owner_id == user_id) {
                try results.append(project);
                continue;
            }

            for (project.members.items) |member| {
                if (member.user_id == user_id) {
                    try results.append(project);
                    break;
                }
            }
        }
    }

    pub fn getProjectMembers(self: *const CollaborationManager, project_id: u64) ?[]const ProjectMember {
        const project = self.findProject(project_id) orelse return null;
        return project.members.items;
    }

    pub fn getPendingInvites(self: *const CollaborationManager, user_email: []const u8, results: *std.array_list.Managed(ProjectInvite)) !void {
        results.clearRetainingCapacity();
        for (self.projects.items) |project| {
            for (project.invites.items) |invite| {
                if (std.mem.eql(u8, invite.invitee_email, user_email) and invite.status == .pending) {
                    try results.append(invite);
                }
            }
        }
    }

    fn findProject(self: *const CollaborationManager, project_id: u64) ?*CollaborativeProject {
        for (self.projects.items) |*project| {
            if (project.id == project_id) {
                return project;
            }
        }
        return null;
    }

    fn canManageMembers(self: *const CollaborationManager, project: *const CollaborativeProject, user_id: u64) bool {
        _ = self;
        if (project.owner_id == user_id) return true;

        for (project.members.items) |member| {
            if (member.user_id == user_id and (member.role == .admin or member.role == .owner)) {
                return true;
            }
        }
        return false;
    }

    pub fn deinit(self: *CollaborationManager) void {
        for (self.projects.items) |project| {
            self.allocator.free(project.name);
            self.allocator.free(project.description);

            for (project.members.items) |member| {
                self.allocator.free(member.username);
            }
            project.members.deinit();

            for (project.invites.items) |invite| {
                self.allocator.free(invite.invitee_email);
                if (invite.message) |msg| {
                    self.allocator.free(msg);
                }
            }
            project.invites.deinit();
        }
        self.projects.deinit();
    }
};
