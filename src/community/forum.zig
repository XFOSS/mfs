const std = @import("std");

pub const PostType = enum {
    discussion,
    question,
    announcement,
    showcase,
    tutorial,
};

pub const UserRole = enum {
    guest,
    member,
    moderator,
    admin,
};

pub const Post = struct {
    id: u64,
    author_id: u64,
    title: []const u8,
    content: []const u8,
    post_type: PostType,
    category_id: u64,
    created_at: i64,
    updated_at: i64,
    likes: u32,
    replies: u32,
    pinned: bool = false,
    locked: bool = false,
};

pub const Category = struct {
    id: u64,
    name: []const u8,
    description: []const u8,
    color: [3]u8,
    post_count: u32,
    moderator_only: bool = false,
};

pub const User = struct {
    id: u64,
    username: []const u8,
    display_name: []const u8,
    email: []const u8,
    role: UserRole,
    reputation: i32,
    post_count: u32,
    joined_at: i64,
    last_active: i64,
    avatar_url: ?[]const u8 = null,
};

pub const ForumConfig = struct {
    max_post_length: u32 = 10000,
    posts_per_page: u32 = 20,
    enable_reputation: bool = true,
    enable_moderation: bool = true,
    allow_guest_posts: bool = false,
};

pub const Forum = struct {
    allocator: std.mem.Allocator,
    config: ForumConfig,
    posts: std.array_list.Managed(Post),
    categories: std.array_list.Managed(Category),
    users: std.array_list.Managed(User),
    next_post_id: u64,
    next_category_id: u64,
    next_user_id: u64,

    pub fn init(allocator: std.mem.Allocator, config: ForumConfig) Forum {
        return Forum{
            .allocator = allocator,
            .config = config,
            .posts = std.array_list.Managed(Post).init(allocator),
            .categories = std.array_list.Managed(Category).init(allocator),
            .users = std.array_list.Managed(User).init(allocator),
            .next_post_id = 1,
            .next_category_id = 1,
            .next_user_id = 1,
        };
    }

    pub fn createCategory(self: *Forum, name: []const u8, description: []const u8, color: [3]u8) !u64 {
        const category = Category{
            .id = self.next_category_id,
            .name = try self.allocator.dupe(u8, name),
            .description = try self.allocator.dupe(u8, description),
            .color = color,
            .post_count = 0,
        };
        try self.categories.append(category);
        self.next_category_id += 1;
        return category.id;
    }

    pub fn createPost(self: *Forum, author_id: u64, title: []const u8, content: []const u8, post_type: PostType, category_id: u64) !u64 {
        const now = std.time.timestamp();
        const post = Post{
            .id = self.next_post_id,
            .author_id = author_id,
            .title = try self.allocator.dupe(u8, title),
            .content = try self.allocator.dupe(u8, content),
            .post_type = post_type,
            .category_id = category_id,
            .created_at = now,
            .updated_at = now,
            .likes = 0,
            .replies = 0,
        };
        try self.posts.append(post);
        self.next_post_id += 1;
        return post.id;
    }

    pub fn registerUser(self: *Forum, username: []const u8, email: []const u8, display_name: []const u8) !u64 {
        const now = std.time.timestamp();
        const user = User{
            .id = self.next_user_id,
            .username = try self.allocator.dupe(u8, username),
            .display_name = try self.allocator.dupe(u8, display_name),
            .email = try self.allocator.dupe(u8, email),
            .role = .member,
            .reputation = 0,
            .post_count = 0,
            .joined_at = now,
            .last_active = now,
        };
        try self.users.append(user);
        self.next_user_id += 1;
        return user.id;
    }

    pub fn getPostsByCategory(self: *const Forum, category_id: u64, results: *std.array_list.Managed(Post)) !void {
        results.clearRetainingCapacity();
        for (self.posts.items) |post| {
            if (post.category_id == category_id) {
                try results.append(post);
            }
        }
    }

    pub fn searchPosts(self: *const Forum, query: []const u8, results: *std.array_list.Managed(Post)) !void {
        results.clearRetainingCapacity();
        for (self.posts.items) |post| {
            if (std.mem.indexOf(u8, post.title, query) != null or
                std.mem.indexOf(u8, post.content, query) != null)
            {
                try results.append(post);
            }
        }
    }

    pub fn likePost(self: *Forum, post_id: u64, user_id: u64) !void {
        _ = user_id; // TODO: Track who liked what
        for (self.posts.items) |*post| {
            if (post.id == post_id) {
                post.likes += 1;
                return;
            }
        }
        return error.PostNotFound;
    }

    pub fn getCategories(self: *const Forum) []const Category {
        return self.categories.items;
    }

    pub fn getUsers(self: *const Forum) []const User {
        return self.users.items;
    }

    pub fn deinit(self: *Forum) void {
        for (self.posts.items) |post| {
            self.allocator.free(post.title);
            self.allocator.free(post.content);
        }
        self.posts.deinit();

        for (self.categories.items) |category| {
            self.allocator.free(category.name);
            self.allocator.free(category.description);
        }
        self.categories.deinit();

        for (self.users.items) |user| {
            self.allocator.free(user.username);
            self.allocator.free(user.display_name);
            self.allocator.free(user.email);
            if (user.avatar_url) |url| {
                self.allocator.free(url);
            }
        }
        self.users.deinit();
    }
};
