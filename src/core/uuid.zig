//! MFS Engine - UUID Generation
//! UUID (Universally Unique Identifier) generation and utilities
//! @thread-safe UUID generation is thread-safe
//! @symbol UUID

const std = @import("std");

/// UUID structure
pub const UUID = struct {
    bytes: [16]u8,

    const Self = @This();

    /// Generate a new random UUID (Version 4)
    pub fn generate() Self {
        var uuid = Self{ .bytes = undefined };
        std.crypto.random.bytes(&uuid.bytes);

        // Set version (4) and variant bits according to RFC 4122
        uuid.bytes[6] = (uuid.bytes[6] & 0x0f) | 0x40; // Version 4
        uuid.bytes[8] = (uuid.bytes[8] & 0x3f) | 0x80; // Variant 10

        return uuid;
    }

    /// Generate a new UUID from a seed (deterministic)
    pub fn generateFromSeed(seed: u64) Self {
        // The old std.rand API has been removed in recent Zig versions.
        // Use the unified std.Random interface instead to ensure forward-compatibility.

        var prng = std.Random.DefaultPrng.init(seed);
        const random = prng.random();

        var uuid = Self{ .bytes = undefined };
        random.bytes(&uuid.bytes);

        // Set RFC-4122 version (4) and variant bits
        uuid.bytes[6] = (uuid.bytes[6] & 0x0f) | 0x40; // Version 4
        uuid.bytes[8] = (uuid.bytes[8] & 0x3f) | 0x80; // Variant 10

        return uuid;
    }

    /// Create UUID from string representation
    pub fn fromString(str: []const u8) !Self {
        if (str.len != 36) return error.InvalidLength;

        var uuid = Self{ .bytes = undefined };
        var byte_index: usize = 0;
        var i: usize = 0;

        while (i < str.len and byte_index < 16) {
            if (str[i] == '-') {
                i += 1;
                continue;
            }

            if (i + 1 >= str.len) return error.InvalidFormat;

            const high = std.fmt.charToDigit(str[i], 16) catch return error.InvalidCharacter;
            const low = std.fmt.charToDigit(str[i + 1], 16) catch return error.InvalidCharacter;

            uuid.bytes[byte_index] = (high << 4) | low;
            byte_index += 1;
            i += 2;
        }

        if (byte_index != 16) return error.InvalidFormat;
        return uuid;
    }

    /// Convert UUID to string representation
    pub fn toString(self: Self, buf: []u8) ![]u8 {
        if (buf.len < 36) return error.BufferTooSmall;

        return std.fmt.bufPrint(buf, "{x:0>2}{x:0>2}{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}", .{
            self.bytes[0],  self.bytes[1],  self.bytes[2],  self.bytes[3],
            self.bytes[4],  self.bytes[5],  self.bytes[6],  self.bytes[7],
            self.bytes[8],  self.bytes[9],  self.bytes[10], self.bytes[11],
            self.bytes[12], self.bytes[13], self.bytes[14], self.bytes[15],
        });
    }

    /// Convert to uppercase string representation
    pub fn toStringUpper(self: Self, buf: []u8) ![]u8 {
        if (buf.len < 36) return error.BufferTooSmall;

        return std.fmt.bufPrint(buf, "{X:0>2}{X:0>2}{X:0>2}{X:0>2}-{X:0>2}{X:0>2}-{X:0>2}{X:0>2}-{X:0>2}{X:0>2}-{X:0>2}{X:0>2}{X:0>2}{X:0>2}{X:0>2}{X:0>2}", .{
            self.bytes[0],  self.bytes[1],  self.bytes[2],  self.bytes[3],
            self.bytes[4],  self.bytes[5],  self.bytes[6],  self.bytes[7],
            self.bytes[8],  self.bytes[9],  self.bytes[10], self.bytes[11],
            self.bytes[12], self.bytes[13], self.bytes[14], self.bytes[15],
        });
    }

    /// Get UUID as u128
    pub fn asU128(self: Self) u128 {
        return std.mem.readInt(u128, &self.bytes, .big);
    }

    /// Create UUID from u128
    pub fn fromU128(value: u128) Self {
        var uuid = Self{ .bytes = undefined };
        std.mem.writeInt(u128, &uuid.bytes, value, .big);
        return uuid;
    }

    /// Check if UUID is nil (all zeros)
    pub fn isNil(self: Self) bool {
        for (self.bytes) |byte| {
            if (byte != 0) return false;
        }
        return true;
    }

    /// Get nil UUID (all zeros)
    pub fn nil() Self {
        return Self{ .bytes = [_]u8{0} ** 16 };
    }

    /// Compare two UUIDs
    pub fn eql(self: Self, other: Self) bool {
        return std.mem.eql(u8, &self.bytes, &other.bytes);
    }

    /// Hash function for HashMap usage
    pub fn hash(self: Self) u64 {
        return std.hash_map.hashString(&self.bytes);
    }

    /// Get version of UUID
    pub fn getVersion(self: Self) u4 {
        return @as(u4, @truncate(self.bytes[6] >> 4));
    }

    /// Get variant of UUID
    pub fn getVariant(self: Self) u2 {
        return @as(u2, @truncate(self.bytes[8] >> 6));
    }
};

/// UUID generator with thread-local state
pub const UUIDGenerator = struct {
    const Self = @This();

    /// Generate a new UUID
    pub fn generate() UUID {
        return UUID.generate();
    }

    /// Generate multiple UUIDs at once
    pub fn generateBatch(allocator: std.mem.Allocator, count: usize) ![]UUID {
        const uuids = try allocator.alloc(UUID, count);
        for (uuids) |*uuid| {
            uuid.* = UUID.generate();
        }
        return uuids;
    }

    /// Generate UUID with custom namespace (Version 5-like)
    pub fn generateNamespaced(namespace: []const u8, name: []const u8) UUID {
        var hasher = std.crypto.hash.sha2.Sha256.init(.{});
        hasher.update(namespace);
        hasher.update(name);

        var hash_bytes: [32]u8 = undefined;
        hasher.final(&hash_bytes);

        var uuid = UUID{ .bytes = undefined };
        @memcpy(&uuid.bytes, hash_bytes[0..16]);

        // Set version (5) and variant bits
        uuid.bytes[6] = (uuid.bytes[6] & 0x0f) | 0x50;
        uuid.bytes[8] = (uuid.bytes[8] & 0x3f) | 0x80;

        return uuid;
    }
};

test "uuid generation" {
    const testing = std.testing;

    // Test UUID generation
    const uuid1 = UUID.generate();
    const uuid2 = UUID.generate();

    try testing.expect(!uuid1.eql(uuid2));
    try testing.expect(!uuid1.isNil());
    try testing.expect(uuid1.getVersion() == 4);

    // Test nil UUID
    const nil_uuid = UUID.nil();
    try testing.expect(nil_uuid.isNil());

    // Test string conversion
    var buf: [36]u8 = undefined;
    const uuid_str = try uuid1.toString(&buf);
    try testing.expect(uuid_str.len == 36);

    // Test parsing from string
    const parsed_uuid = try UUID.fromString(uuid_str);
    try testing.expect(uuid1.eql(parsed_uuid));
}

test "uuid from seed" {
    const testing = std.testing;

    // Test deterministic generation
    const uuid1 = UUID.generateFromSeed(12345);
    const uuid2 = UUID.generateFromSeed(12345);
    const uuid3 = UUID.generateFromSeed(54321);

    try testing.expect(uuid1.eql(uuid2));
    try testing.expect(!uuid1.eql(uuid3));
}
