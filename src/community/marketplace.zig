const std = @import("std");

pub const AssetCategory = enum {
    models,
    textures,
    audio,
    scripts,
    materials,
    animations,
    templates,
    tools,
};

pub const PricingModel = enum {
    free,
    one_time,
    subscription,
    pay_what_you_want,
};

pub const AssetListing = struct {
    id: u64,
    seller_id: u64,
    title: []const u8,
    description: []const u8,
    category: AssetCategory,
    pricing_model: PricingModel,
    price: f64,
    currency: []const u8,
    downloads: u32,
    rating: f32,
    review_count: u32,
    created_at: i64,
    updated_at: i64,
    file_size: u64,
    preview_images: [][]const u8,
    tags: [][]const u8,
    featured: bool = false,
};

pub const Purchase = struct {
    id: u64,
    buyer_id: u64,
    asset_id: u64,
    amount: f64,
    currency: []const u8,
    purchased_at: i64,
    license_type: []const u8,
};

pub const Review = struct {
    id: u64,
    asset_id: u64,
    reviewer_id: u64,
    rating: u8, // 1-5 stars
    title: []const u8,
    content: []const u8,
    created_at: i64,
    helpful_votes: u32,
};

pub const MarketplaceConfig = struct {
    commission_rate: f32 = 0.30, // 30% commission
    min_price: f64 = 0.99,
    max_file_size: u64 = 1024 * 1024 * 1024, // 1GB
    enable_reviews: bool = true,
    enable_wishlists: bool = true,
};

pub const Marketplace = struct {
    allocator: std.mem.Allocator,
    config: MarketplaceConfig,
    assets: std.array_list.Managed(AssetListing),
    purchases: std.array_list.Managed(Purchase),
    reviews: std.array_list.Managed(Review),
    next_asset_id: u64,
    next_purchase_id: u64,
    next_review_id: u64,

    pub fn init(allocator: std.mem.Allocator, config: MarketplaceConfig) Marketplace {
        return Marketplace{
            .allocator = allocator,
            .config = config,
            .assets = std.array_list.Managed(AssetListing).init(allocator),
            .purchases = std.array_list.Managed(Purchase).init(allocator),
            .reviews = std.array_list.Managed(Review).init(allocator),
            .next_asset_id = 1,
            .next_purchase_id = 1,
            .next_review_id = 1,
        };
    }

    pub fn listAsset(self: *Marketplace, seller_id: u64, title: []const u8, description: []const u8, category: AssetCategory, pricing_model: PricingModel, price: f64) !u64 {
        const now = std.time.timestamp();
        const asset = AssetListing{
            .id = self.next_asset_id,
            .seller_id = seller_id,
            .title = try self.allocator.dupe(u8, title),
            .description = try self.allocator.dupe(u8, description),
            .category = category,
            .pricing_model = pricing_model,
            .price = price,
            .currency = try self.allocator.dupe(u8, "USD"),
            .downloads = 0,
            .rating = 0.0,
            .review_count = 0,
            .created_at = now,
            .updated_at = now,
            .file_size = 0,
            .preview_images = &.{},
            .tags = &.{},
        };
        try self.assets.append(asset);
        self.next_asset_id += 1;
        return asset.id;
    }

    pub fn purchaseAsset(self: *Marketplace, buyer_id: u64, asset_id: u64) !u64 {
        // Find the asset
        var asset_found = false;
        var asset_price: f64 = 0;
        for (self.assets.items) |*asset| {
            if (asset.id == asset_id) {
                asset_found = true;
                asset_price = asset.price;
                asset.downloads += 1;
                break;
            }
        }

        if (!asset_found) return error.AssetNotFound;

        const purchase = Purchase{
            .id = self.next_purchase_id,
            .buyer_id = buyer_id,
            .asset_id = asset_id,
            .amount = asset_price,
            .currency = try self.allocator.dupe(u8, "USD"),
            .purchased_at = std.time.timestamp(),
            .license_type = try self.allocator.dupe(u8, "Standard"),
        };
        try self.purchases.append(purchase);
        self.next_purchase_id += 1;
        return purchase.id;
    }

    pub fn addReview(self: *Marketplace, asset_id: u64, reviewer_id: u64, rating: u8, title: []const u8, content: []const u8) !u64 {
        const review = Review{
            .id = self.next_review_id,
            .asset_id = asset_id,
            .reviewer_id = reviewer_id,
            .rating = rating,
            .title = try self.allocator.dupe(u8, title),
            .content = try self.allocator.dupe(u8, content),
            .created_at = std.time.timestamp(),
            .helpful_votes = 0,
        };
        try self.reviews.append(review);
        self.next_review_id += 1;

        // Update asset rating
        try self.updateAssetRating(asset_id);
        return review.id;
    }

    pub fn searchAssets(self: *const Marketplace, query: []const u8, category: ?AssetCategory, results: *std.array_list.Managed(AssetListing)) !void {
        results.clearRetainingCapacity();
        for (self.assets.items) |asset| {
            var matches = false;

            // Check category filter
            if (category) |cat| {
                if (asset.category != cat) continue;
            }

            // Check text search
            if (std.mem.indexOf(u8, asset.title, query) != null or
                std.mem.indexOf(u8, asset.description, query) != null)
            {
                matches = true;
            }

            if (matches) {
                try results.append(asset);
            }
        }
    }

    pub fn getFeaturedAssets(self: *const Marketplace, results: *std.array_list.Managed(AssetListing)) !void {
        results.clearRetainingCapacity();
        for (self.assets.items) |asset| {
            if (asset.featured) {
                try results.append(asset);
            }
        }
    }

    pub fn getAssetReviews(self: *const Marketplace, asset_id: u64, results: *std.array_list.Managed(Review)) !void {
        results.clearRetainingCapacity();
        for (self.reviews.items) |review| {
            if (review.asset_id == asset_id) {
                try results.append(review);
            }
        }
    }

    pub fn getUserPurchases(self: *const Marketplace, user_id: u64, results: *std.array_list.Managed(Purchase)) !void {
        results.clearRetainingCapacity();
        for (self.purchases.items) |purchase| {
            if (purchase.buyer_id == user_id) {
                try results.append(purchase);
            }
        }
    }

    fn updateAssetRating(self: *Marketplace, asset_id: u64) !void {
        var total_rating: f32 = 0;
        var count: u32 = 0;

        for (self.reviews.items) |review| {
            if (review.asset_id == asset_id) {
                total_rating += @as(f32, @floatFromInt(review.rating));
                count += 1;
            }
        }

        for (self.assets.items) |*asset| {
            if (asset.id == asset_id) {
                asset.rating = if (count > 0) total_rating / @as(f32, @floatFromInt(count)) else 0.0;
                asset.review_count = count;
                break;
            }
        }
    }

    pub fn deinit(self: *Marketplace) void {
        for (self.assets.items) |asset| {
            self.allocator.free(asset.title);
            self.allocator.free(asset.description);
            self.allocator.free(asset.currency);
        }
        self.assets.deinit();

        for (self.purchases.items) |purchase| {
            self.allocator.free(purchase.currency);
            self.allocator.free(purchase.license_type);
        }
        self.purchases.deinit();

        for (self.reviews.items) |review| {
            self.allocator.free(review.title);
            self.allocator.free(review.content);
        }
        self.reviews.deinit();
    }
};
