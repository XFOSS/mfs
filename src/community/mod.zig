//! MFS Engine - Community Platform
//! Forums, asset sharing, collaboration tools for ecosystem growth
//! Provides comprehensive community features and social integration

const std = @import("std");
const networking = @import("../networking/mod.zig");

/// Community Platform Manager - coordinates all community features
pub const CommunityPlatform = struct {
    allocator: std.mem.Allocator,

    // Platform components
    forum_system: ForumSystem,
    asset_marketplace: AssetMarketplace,
    collaboration_tools: CollaborationTools,
    user_management: UserManagement,
    social_features: SocialFeatures,

    // Network connection
    network_manager: ?*networking.NetworkManager = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        std.log.info("Initializing MFS Community Platform...", .{});

        return Self{
            .allocator = allocator,
            .forum_system = try ForumSystem.init(allocator),
            .asset_marketplace = try AssetMarketplace.init(allocator),
            .collaboration_tools = try CollaborationTools.init(allocator),
            .user_management = try UserManagement.init(allocator),
            .social_features = try SocialFeatures.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.forum_system.deinit();
        self.asset_marketplace.deinit();
        self.collaboration_tools.deinit();
        self.user_management.deinit();
        self.social_features.deinit();
    }

    /// Connect to the community platform
    pub fn connect(self: *Self, config: PlatformConfig) !void {
        std.log.info("Connecting to community platform...", .{});

        // Initialize network connection
        if (self.network_manager == null) {
            self.network_manager = try self.allocator.create(networking.NetworkManager);
            self.network_manager.?.* = try networking.NetworkManager.init(self.allocator, .client);
        }

        // Connect to platform services
        try self.user_management.authenticate(config.user_credentials);
        try self.forum_system.connect(config.forum_endpoint);
        try self.asset_marketplace.connect(config.marketplace_endpoint);
        try self.collaboration_tools.connect(config.collaboration_endpoint);

        std.log.info("Connected to community platform successfully", .{});
    }

    /// Update all community systems
    pub fn update(self: *Self, delta_time: f32) !void {
        if (self.network_manager) |network| {
            try network.update(delta_time);
        }

        try self.forum_system.update(delta_time);
        try self.asset_marketplace.update(delta_time);
        try self.collaboration_tools.update(delta_time);
        try self.user_management.update(delta_time);
        try self.social_features.update(delta_time);
    }

    /// Render community interface
    pub fn render(self: *Self) !void {
        try self.renderCommunityHub();
    }

    /// Get current user information
    pub fn getCurrentUser(self: *Self) ?User {
        return self.user_management.current_user;
    }

    /// Get community statistics
    pub fn getStats(self: *Self) CommunityStats {
        return CommunityStats{
            .total_users = self.user_management.getTotalUsers(),
            .active_users = self.user_management.getActiveUsers(),
            .total_posts = self.forum_system.getTotalPosts(),
            .total_assets = self.asset_marketplace.getTotalAssets(),
            .active_projects = self.collaboration_tools.getActiveProjects(),
        };
    }

    fn renderCommunityHub(self: *Self) !void {
        // TODO: Implement community hub UI
        _ = self;
    }
};

/// Forum system for community discussions
pub const ForumSystem = struct {
    allocator: std.mem.Allocator,

    // Forum data
    categories: std.ArrayList(ForumCategory),
    posts: std.HashMap(u32, ForumPost, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage),
    next_post_id: u32 = 1,

    // Current state
    current_category: ?u32 = null,
    current_thread: ?u32 = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        var forum = Self{
            .allocator = allocator,
            .categories = std.ArrayList(ForumCategory).init(allocator),
            .posts = std.HashMap(u32, ForumPost, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage).init(allocator),
        };

        // Create default categories
        try forum.createDefaultCategories();

        return forum;
    }

    pub fn deinit(self: *Self) void {
        for (self.categories.items) |*category| {
            category.deinit();
        }
        self.categories.deinit();

        var post_iterator = self.posts.iterator();
        while (post_iterator.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.posts.deinit();
    }

    pub fn connect(self: *Self, endpoint: []const u8) !void {
        _ = self;
        _ = endpoint;
        // TODO: Connect to forum API
        std.log.info("Connected to forum system", .{});
    }

    pub fn update(self: *Self, delta_time: f32) !void {
        _ = self;
        _ = delta_time;
        // Update forum state, check for new posts, etc.
    }

    /// Create a new forum post
    pub fn createPost(self: *Self, author_id: u32, category_id: u32, title: []const u8, content: []const u8) !u32 {
        const post_id = self.next_post_id;
        self.next_post_id += 1;

        const post = ForumPost{
            .id = post_id,
            .author_id = author_id,
            .category_id = category_id,
            .title = try self.allocator.dupe(u8, title),
            .content = try self.allocator.dupe(u8, content),
            .created_at = std.time.timestamp(),
            .replies = std.ArrayList(ForumReply).init(self.allocator),
        };

        try self.posts.put(post_id, post);
        return post_id;
    }

    /// Reply to a forum post
    pub fn replyToPost(self: *Self, post_id: u32, author_id: u32, content: []const u8) !void {
        if (self.posts.getPtr(post_id)) |post| {
            const reply = ForumReply{
                .author_id = author_id,
                .content = try self.allocator.dupe(u8, content),
                .created_at = std.time.timestamp(),
            };

            try post.replies.append(reply);
        } else {
            return error.PostNotFound;
        }
    }

    /// Get posts in a category
    pub fn getPostsInCategory(self: *Self, category_id: u32) std.ArrayList(u32) {
        var result = std.ArrayList(u32).init(self.allocator);

        var post_iterator = self.posts.iterator();
        while (post_iterator.next()) |entry| {
            if (entry.value_ptr.category_id == category_id) {
                result.append(entry.key_ptr.*) catch continue;
            }
        }

        return result;
    }

    pub fn getTotalPosts(self: *Self) u32 {
        return @intCast(self.posts.count());
    }

    fn createDefaultCategories(self: *Self) !void {
        const categories = [_]struct { name: []const u8, description: []const u8 }{
            .{ .name = "General Discussion", .description = "General topics about MFS Engine" },
            .{ .name = "Help & Support", .description = "Get help with MFS Engine" },
            .{ .name = "Showcase", .description = "Show off your projects" },
            .{ .name = "Feature Requests", .description = "Request new features" },
            .{ .name = "Bug Reports", .description = "Report bugs and issues" },
            .{ .name = "Tutorials", .description = "Share and find tutorials" },
            .{ .name = "Assets", .description = "Share and discuss assets" },
            .{ .name = "Jobs", .description = "Job postings and opportunities" },
        };

        for (categories, 0..) |cat, i| {
            const category = ForumCategory{
                .id = @intCast(i + 1),
                .name = try self.allocator.dupe(u8, cat.name),
                .description = try self.allocator.dupe(u8, cat.description),
                .post_count = 0,
            };

            try self.categories.append(category);
        }
    }
};

/// Asset marketplace for sharing and selling assets
pub const AssetMarketplace = struct {
    allocator: std.mem.Allocator,

    // Asset data
    assets: std.HashMap(u32, MarketplaceAsset, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage),
    categories: std.ArrayList(AssetCategory),
    next_asset_id: u32 = 1,

    // Search and filtering
    search_query: []const u8 = "",
    selected_category: ?u32 = null,
    sort_mode: AssetSortMode = .popularity,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        var marketplace = Self{
            .allocator = allocator,
            .assets = std.HashMap(u32, MarketplaceAsset, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage).init(allocator),
            .categories = std.ArrayList(AssetCategory).init(allocator),
        };

        // Create default asset categories
        try marketplace.createDefaultAssetCategories();

        return marketplace;
    }

    pub fn deinit(self: *Self) void {
        var asset_iterator = self.assets.iterator();
        while (asset_iterator.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.assets.deinit();

        for (self.categories.items) |*category| {
            category.deinit();
        }
        self.categories.deinit();

        self.allocator.free(self.search_query);
    }

    pub fn connect(self: *Self, endpoint: []const u8) !void {
        _ = self;
        _ = endpoint;
        // TODO: Connect to marketplace API
        std.log.info("Connected to asset marketplace", .{});
    }

    pub fn update(self: *Self, delta_time: f32) !void {
        _ = self;
        _ = delta_time;
        // Update marketplace state, check for new assets, etc.
    }

    /// Upload an asset to the marketplace
    pub fn uploadAsset(self: *Self, asset_info: AssetUploadInfo) !u32 {
        const asset_id = self.next_asset_id;
        self.next_asset_id += 1;

        const asset = MarketplaceAsset{
            .id = asset_id,
            .name = try self.allocator.dupe(u8, asset_info.name),
            .description = try self.allocator.dupe(u8, asset_info.description),
            .author_id = asset_info.author_id,
            .category_id = asset_info.category_id,
            .price = asset_info.price,
            .file_size = asset_info.file_size,
            .download_count = 0,
            .rating = 0.0,
            .tags = try self.allocator.dupe([]const u8, asset_info.tags),
            .created_at = std.time.timestamp(),
            .updated_at = std.time.timestamp(),
        };

        try self.assets.put(asset_id, asset);
        std.log.info("Asset uploaded: {s} (ID: {})", .{ asset_info.name, asset_id });

        return asset_id;
    }

    /// Download an asset from the marketplace
    pub fn downloadAsset(self: *Self, asset_id: u32, user_id: u32) !void {
        if (self.assets.getPtr(asset_id)) |asset| {
            // Check if user can download (free asset or purchased)
            if (asset.price == 0.0 or self.hasUserPurchased(user_id, asset_id)) {
                asset.download_count += 1;
                std.log.info("Asset downloaded: {} by user {}", .{ asset_id, user_id });
                // TODO: Implement actual file download
            } else {
                return error.PurchaseRequired;
            }
        } else {
            return error.AssetNotFound;
        }
    }

    /// Search assets in the marketplace
    pub fn searchAssets(self: *Self, query: []const u8) !std.ArrayList(u32) {
        var results = std.ArrayList(u32).init(self.allocator);

        var asset_iterator = self.assets.iterator();
        while (asset_iterator.next()) |entry| {
            const asset = entry.value_ptr;

            // Simple text search in name and description
            if (std.mem.indexOf(u8, asset.name, query) != null or
                std.mem.indexOf(u8, asset.description, query) != null)
            {
                try results.append(asset.id);
            }
        }

        return results;
    }

    /// Rate an asset
    pub fn rateAsset(self: *Self, asset_id: u32, user_id: u32, rating: f32) !void {
        _ = user_id; // TODO: Track user ratings

        if (self.assets.getPtr(asset_id)) |asset| {
            // Simple average for now - in a real system, track individual ratings
            asset.rating = (asset.rating + rating) / 2.0;
            std.log.info("Asset {} rated: {d:.1}/5.0", .{ asset_id, rating });
        } else {
            return error.AssetNotFound;
        }
    }

    pub fn getTotalAssets(self: *Self) u32 {
        return @intCast(self.assets.count());
    }

    fn hasUserPurchased(self: *Self, user_id: u32, asset_id: u32) bool {
        _ = self;
        _ = user_id;
        _ = asset_id;
        // TODO: Implement purchase tracking
        return false;
    }

    fn createDefaultAssetCategories(self: *Self) !void {
        const categories = [_]struct { name: []const u8, description: []const u8 }{
            .{ .name = "3D Models", .description = "3D models and meshes" },
            .{ .name = "Textures", .description = "Textures and materials" },
            .{ .name = "Audio", .description = "Sound effects and music" },
            .{ .name = "Scripts", .description = "Code and scripts" },
            .{ .name = "Shaders", .description = "Shader programs" },
            .{ .name = "Animations", .description = "Animation clips" },
            .{ .name = "UI Elements", .description = "User interface assets" },
            .{ .name = "Complete Projects", .description = "Full project templates" },
        };

        for (categories, 0..) |cat, i| {
            const category = AssetCategory{
                .id = @intCast(i + 1),
                .name = try self.allocator.dupe(u8, cat.name),
                .description = try self.allocator.dupe(u8, cat.description),
                .asset_count = 0,
            };

            try self.categories.append(category);
        }
    }
};

/// Collaboration tools for team projects
pub const CollaborationTools = struct {
    allocator: std.mem.Allocator,

    // Project data
    projects: std.HashMap(u32, CollaborativeProject, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage),
    next_project_id: u32 = 1,

    // Current state
    current_project: ?u32 = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        return Self{
            .allocator = allocator,
            .projects = std.HashMap(u32, CollaborativeProject, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var project_iterator = self.projects.iterator();
        while (project_iterator.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.projects.deinit();
    }

    pub fn connect(self: *Self, endpoint: []const u8) !void {
        _ = self;
        _ = endpoint;
        // TODO: Connect to collaboration API
        std.log.info("Connected to collaboration tools", .{});
    }

    pub fn update(self: *Self, delta_time: f32) !void {
        _ = self;
        _ = delta_time;
        // Update collaboration state, sync changes, etc.
    }

    /// Create a new collaborative project
    pub fn createProject(self: *Self, creator_id: u32, name: []const u8, description: []const u8) !u32 {
        const project_id = self.next_project_id;
        self.next_project_id += 1;

        var project = CollaborativeProject{
            .id = project_id,
            .name = try self.allocator.dupe(u8, name),
            .description = try self.allocator.dupe(u8, description),
            .creator_id = creator_id,
            .members = std.ArrayList(ProjectMember).init(self.allocator),
            .tasks = std.ArrayList(ProjectTask).init(self.allocator),
            .created_at = std.time.timestamp(),
            .status = .active,
        };

        // Add creator as project owner
        const creator_member = ProjectMember{
            .user_id = creator_id,
            .role = .owner,
            .joined_at = std.time.timestamp(),
        };
        try project.members.append(creator_member);

        try self.projects.put(project_id, project);
        std.log.info("Collaborative project created: {s} (ID: {})", .{ name, project_id });

        return project_id;
    }

    /// Invite a user to join a project
    pub fn inviteUser(self: *Self, project_id: u32, user_id: u32, role: ProjectRole) !void {
        if (self.projects.getPtr(project_id)) |project| {
            const member = ProjectMember{
                .user_id = user_id,
                .role = role,
                .joined_at = std.time.timestamp(),
            };

            try project.members.append(member);
            std.log.info("User {} invited to project {} as {s}", .{ user_id, project_id, @tagName(role) });
        } else {
            return error.ProjectNotFound;
        }
    }

    /// Create a task in a project
    pub fn createTask(self: *Self, project_id: u32, creator_id: u32, title: []const u8, description: []const u8) !void {
        if (self.projects.getPtr(project_id)) |project| {
            const task = ProjectTask{
                .title = try self.allocator.dupe(u8, title),
                .description = try self.allocator.dupe(u8, description),
                .creator_id = creator_id,
                .assignee_id = null,
                .status = .todo,
                .priority = .medium,
                .created_at = std.time.timestamp(),
            };

            try project.tasks.append(task);
            std.log.info("Task created in project {}: {s}", .{ project_id, title });
        } else {
            return error.ProjectNotFound;
        }
    }

    pub fn getActiveProjects(self: *Self) u32 {
        var count: u32 = 0;
        var project_iterator = self.projects.iterator();
        while (project_iterator.next()) |entry| {
            if (entry.value_ptr.status == .active) {
                count += 1;
            }
        }
        return count;
    }
};

/// User management and authentication
pub const UserManagement = struct {
    allocator: std.mem.Allocator,

    // User data
    users: std.HashMap(u32, User, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage),
    current_user: ?User = null,
    next_user_id: u32 = 1,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        return Self{
            .allocator = allocator,
            .users = std.HashMap(u32, User, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var user_iterator = self.users.iterator();
        while (user_iterator.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.users.deinit();

        if (self.current_user) |*user| {
            user.deinit();
        }
    }

    pub fn authenticate(self: *Self, credentials: UserCredentials) !void {
        _ = self;
        _ = credentials;
        // TODO: Implement authentication
        std.log.info("User authenticated", .{});
    }

    pub fn update(self: *Self, delta_time: f32) !void {
        _ = self;
        _ = delta_time;
        // Update user management state
    }

    /// Register a new user
    pub fn registerUser(self: *Self, username: []const u8, email: []const u8) !u32 {
        const user_id = self.next_user_id;
        self.next_user_id += 1;

        const user = User{
            .id = user_id,
            .username = try self.allocator.dupe(u8, username),
            .email = try self.allocator.dupe(u8, email),
            .display_name = try self.allocator.dupe(u8, username),
            .reputation = 0,
            .join_date = std.time.timestamp(),
            .last_active = std.time.timestamp(),
            .is_online = true,
        };

        try self.users.put(user_id, user);
        std.log.info("User registered: {s} (ID: {})", .{ username, user_id });

        return user_id;
    }

    pub fn getTotalUsers(self: *Self) u32 {
        return @intCast(self.users.count());
    }

    pub fn getActiveUsers(self: *Self) u32 {
        var count: u32 = 0;
        var user_iterator = self.users.iterator();
        while (user_iterator.next()) |entry| {
            if (entry.value_ptr.is_online) {
                count += 1;
            }
        }
        return count;
    }
};

/// Social features like friends, messaging, groups
pub const SocialFeatures = struct {
    allocator: std.mem.Allocator,

    // Social data
    friendships: std.HashMap(u32, std.ArrayList(u32), std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage),
    groups: std.HashMap(u32, SocialGroup, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage),
    next_group_id: u32 = 1,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        return Self{
            .allocator = allocator,
            .friendships = std.HashMap(u32, std.ArrayList(u32), std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage).init(allocator),
            .groups = std.HashMap(u32, SocialGroup, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var friendship_iterator = self.friendships.iterator();
        while (friendship_iterator.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.friendships.deinit();

        var group_iterator = self.groups.iterator();
        while (group_iterator.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.groups.deinit();
    }

    pub fn update(self: *Self, delta_time: f32) !void {
        _ = self;
        _ = delta_time;
        // Update social features
    }

    /// Add a friend relationship
    pub fn addFriend(self: *Self, user_id: u32, friend_id: u32) !void {
        // Add friend to user's list
        const result1 = try self.friendships.getOrPut(user_id);
        if (!result1.found_existing) {
            result1.value_ptr.* = std.ArrayList(u32).init(self.allocator);
        }
        try result1.value_ptr.append(friend_id);

        // Add user to friend's list (bidirectional)
        const result2 = try self.friendships.getOrPut(friend_id);
        if (!result2.found_existing) {
            result2.value_ptr.* = std.ArrayList(u32).init(self.allocator);
        }
        try result2.value_ptr.append(user_id);

        std.log.info("Friendship added: {} <-> {}", .{ user_id, friend_id });
    }

    /// Create a social group
    pub fn createGroup(self: *Self, creator_id: u32, name: []const u8, description: []const u8) !u32 {
        const group_id = self.next_group_id;
        self.next_group_id += 1;

        var group = SocialGroup{
            .id = group_id,
            .name = try self.allocator.dupe(u8, name),
            .description = try self.allocator.dupe(u8, description),
            .creator_id = creator_id,
            .members = std.ArrayList(u32).init(self.allocator),
            .created_at = std.time.timestamp(),
            .is_public = true,
        };

        // Add creator as first member
        try group.members.append(creator_id);

        try self.groups.put(group_id, group);
        std.log.info("Social group created: {s} (ID: {})", .{ name, group_id });

        return group_id;
    }
};

// Supporting types and structures

pub const PlatformConfig = struct {
    user_credentials: UserCredentials,
    forum_endpoint: []const u8 = "https://community.mfsengine.com/forum",
    marketplace_endpoint: []const u8 = "https://community.mfsengine.com/marketplace",
    collaboration_endpoint: []const u8 = "https://community.mfsengine.com/collaborate",
};

pub const UserCredentials = struct {
    username: []const u8,
    password: []const u8, // In practice, this would be hashed
    token: ?[]const u8 = null,
};

pub const User = struct {
    id: u32,
    username: []const u8,
    email: []const u8,
    display_name: []const u8,
    reputation: i32,
    join_date: i64,
    last_active: i64,
    is_online: bool,

    pub fn deinit(self: *User) void {
        _ = self;
        // In a real implementation, free allocated strings
    }
};

pub const CommunityStats = struct {
    total_users: u32,
    active_users: u32,
    total_posts: u32,
    total_assets: u32,
    active_projects: u32,

    pub fn print(self: *const CommunityStats) void {
        std.log.info("=== Community Statistics ===", .{});
        std.log.info("Total Users: {}", .{self.total_users});
        std.log.info("Active Users: {}", .{self.active_users});
        std.log.info("Forum Posts: {}", .{self.total_posts});
        std.log.info("Marketplace Assets: {}", .{self.total_assets});
        std.log.info("Active Projects: {}", .{self.active_projects});
    }
};

pub const ForumCategory = struct {
    id: u32,
    name: []const u8,
    description: []const u8,
    post_count: u32,

    pub fn deinit(self: *ForumCategory) void {
        _ = self;
        // In a real implementation, free allocated strings
    }
};

pub const ForumPost = struct {
    id: u32,
    author_id: u32,
    category_id: u32,
    title: []const u8,
    content: []const u8,
    created_at: i64,
    replies: std.ArrayList(ForumReply),

    pub fn deinit(self: *ForumPost) void {
        self.replies.deinit();
        // In a real implementation, free allocated strings
    }
};

pub const ForumReply = struct {
    author_id: u32,
    content: []const u8,
    created_at: i64,
};

pub const MarketplaceAsset = struct {
    id: u32,
    name: []const u8,
    description: []const u8,
    author_id: u32,
    category_id: u32,
    price: f32,
    file_size: u64,
    download_count: u32,
    rating: f32,
    tags: []const []const u8,
    created_at: i64,
    updated_at: i64,

    pub fn deinit(self: *MarketplaceAsset) void {
        _ = self;
        // In a real implementation, free allocated strings and arrays
    }
};

pub const AssetUploadInfo = struct {
    name: []const u8,
    description: []const u8,
    author_id: u32,
    category_id: u32,
    price: f32,
    file_size: u64,
    tags: []const []const u8,
};

pub const AssetCategory = struct {
    id: u32,
    name: []const u8,
    description: []const u8,
    asset_count: u32,

    pub fn deinit(self: *AssetCategory) void {
        _ = self;
        // In a real implementation, free allocated strings
    }
};

pub const AssetSortMode = enum {
    popularity,
    newest,
    oldest,
    price_low_to_high,
    price_high_to_low,
    rating,
    downloads,
};

pub const CollaborativeProject = struct {
    id: u32,
    name: []const u8,
    description: []const u8,
    creator_id: u32,
    members: std.ArrayList(ProjectMember),
    tasks: std.ArrayList(ProjectTask),
    created_at: i64,
    status: ProjectStatus,

    pub fn deinit(self: *CollaborativeProject) void {
        self.members.deinit();
        for (self.tasks.items) |*task| {
            task.deinit();
        }
        self.tasks.deinit();
        // In a real implementation, free allocated strings
    }
};

pub const ProjectMember = struct {
    user_id: u32,
    role: ProjectRole,
    joined_at: i64,
};

pub const ProjectRole = enum {
    owner,
    admin,
    developer,
    artist,
    designer,
    tester,
    contributor,
};

pub const ProjectStatus = enum {
    active,
    paused,
    completed,
    cancelled,
};

pub const ProjectTask = struct {
    title: []const u8,
    description: []const u8,
    creator_id: u32,
    assignee_id: ?u32,
    status: TaskStatus,
    priority: TaskPriority,
    created_at: i64,

    pub fn deinit(self: *ProjectTask) void {
        _ = self;
        // In a real implementation, free allocated strings
    }
};

pub const TaskStatus = enum {
    todo,
    in_progress,
    review,
    done,
};

pub const TaskPriority = enum {
    low,
    medium,
    high,
    critical,
};

pub const SocialGroup = struct {
    id: u32,
    name: []const u8,
    description: []const u8,
    creator_id: u32,
    members: std.ArrayList(u32),
    created_at: i64,
    is_public: bool,

    pub fn deinit(self: *SocialGroup) void {
        self.members.deinit();
        // In a real implementation, free allocated strings
    }
};
