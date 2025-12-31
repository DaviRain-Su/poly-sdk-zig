//! UUID (Universally Unique Identifier) type.
//!
//! Supports UUID v4 (random) format as used by Polymarket for order IDs,
//! trade IDs, and other identifiers.
//!
//! Standard format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
//!
//! ```zig
//! const id = try UUID.fromString("550e8400-e29b-41d4-a716-446655440000");
//! std.debug.print("{f}", .{id});  // "550e8400-e29b-41d4-a716-446655440000"
//!
//! const random = UUID.v4();  // Generate random UUID v4
//! ```

const std = @import("std");

/// UUID (16 bytes / 128 bits)
pub const UUID = struct {
    bytes: [16]u8,

    /// Nil UUID (all zeros)
    pub const NIL = UUID{ .bytes = [_]u8{0} ** 16 };

    /// Parse UUID from string format.
    ///
    /// Accepts standard format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    /// Also accepts without hyphens: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
    pub fn fromString(str: []const u8) !UUID {
        if (str.len == 36) {
            // Standard format with hyphens: 8-4-4-4-12
            if (str[8] != '-' or str[13] != '-' or str[18] != '-' or str[23] != '-') {
                return error.InvalidUUIDFormat;
            }
            return parseHexBytes(&[_][]const u8{
                str[0..8],
                str[9..13],
                str[14..18],
                str[19..23],
                str[24..36],
            });
        } else if (str.len == 32) {
            // Compact format without hyphens
            return parseHexBytes(&[_][]const u8{str[0..32]});
        } else {
            return error.InvalidUUIDLength;
        }
    }

    /// Parse from multiple hex segments
    fn parseHexBytes(segments: []const []const u8) !UUID {
        var bytes: [16]u8 = undefined;
        var byte_idx: usize = 0;

        for (segments) |segment| {
            var i: usize = 0;
            while (i < segment.len) : (i += 2) {
                const hi = hexCharToNibble(segment[i]) orelse return error.InvalidHexCharacter;
                const lo = hexCharToNibble(segment[i + 1]) orelse return error.InvalidHexCharacter;
                bytes[byte_idx] = (hi << 4) | lo;
                byte_idx += 1;
            }
        }

        return UUID{ .bytes = bytes };
    }

    /// Create UUID from raw bytes.
    pub fn fromBytes(bytes: [16]u8) UUID {
        return UUID{ .bytes = bytes };
    }

    /// Create UUID from a byte slice.
    pub fn fromSlice(slice: []const u8) !UUID {
        if (slice.len != 16) {
            return error.InvalidUUIDLength;
        }
        var bytes: [16]u8 = undefined;
        @memcpy(&bytes, slice);
        return UUID{ .bytes = bytes };
    }

    /// Generate a random UUID v4.
    ///
    /// UUID v4 format:
    /// - bits 48-51: version (4)
    /// - bits 64-65: variant (10 binary)
    pub fn v4() UUID {
        var bytes: [16]u8 = undefined;
        std.crypto.random.bytes(&bytes);

        // Set version to 4 (bits 48-51)
        bytes[6] = (bytes[6] & 0x0F) | 0x40;

        // Set variant to RFC 4122 (bits 64-65 = 10)
        bytes[8] = (bytes[8] & 0x3F) | 0x80;

        return UUID{ .bytes = bytes };
    }

    /// Generate a random UUID v4 using a specific random source.
    pub fn v4WithRandom(random: std.Random) UUID {
        var bytes: [16]u8 = undefined;
        random.bytes(&bytes);

        // Set version to 4
        bytes[6] = (bytes[6] & 0x0F) | 0x40;

        // Set variant to RFC 4122
        bytes[8] = (bytes[8] & 0x3F) | 0x80;

        return UUID{ .bytes = bytes };
    }

    /// Get raw bytes.
    pub fn toBytes(self: UUID) [16]u8 {
        return self.bytes;
    }

    /// Get as byte slice.
    pub fn asSlice(self: *const UUID) []const u8 {
        return &self.bytes;
    }

    /// Convert to standard string format (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx).
    pub fn toString(self: UUID) [36]u8 {
        var result: [36]u8 = undefined;

        // Positions: 8-4-4-4-12
        inline for (0..4) |i| {
            result[i * 2] = hexDigit(self.bytes[i] >> 4);
            result[i * 2 + 1] = hexDigit(self.bytes[i] & 0x0F);
        }
        result[8] = '-';

        inline for (0..2) |i| {
            result[9 + i * 2] = hexDigit(self.bytes[4 + i] >> 4);
            result[9 + i * 2 + 1] = hexDigit(self.bytes[4 + i] & 0x0F);
        }
        result[13] = '-';

        inline for (0..2) |i| {
            result[14 + i * 2] = hexDigit(self.bytes[6 + i] >> 4);
            result[14 + i * 2 + 1] = hexDigit(self.bytes[6 + i] & 0x0F);
        }
        result[18] = '-';

        inline for (0..2) |i| {
            result[19 + i * 2] = hexDigit(self.bytes[8 + i] >> 4);
            result[19 + i * 2 + 1] = hexDigit(self.bytes[8 + i] & 0x0F);
        }
        result[23] = '-';

        inline for (0..6) |i| {
            result[24 + i * 2] = hexDigit(self.bytes[10 + i] >> 4);
            result[24 + i * 2 + 1] = hexDigit(self.bytes[10 + i] & 0x0F);
        }

        return result;
    }

    /// Convert to compact string format (no hyphens).
    pub fn toCompactString(self: UUID) [32]u8 {
        var result: [32]u8 = undefined;
        for (self.bytes, 0..) |byte, i| {
            result[i * 2] = hexDigit(byte >> 4);
            result[i * 2 + 1] = hexDigit(byte & 0x0F);
        }
        return result;
    }

    /// Get UUID version (4 for v4, etc.).
    pub fn getVersion(self: UUID) u4 {
        return @intCast(self.bytes[6] >> 4);
    }

    /// Get UUID variant.
    /// Returns:
    /// - 0: Reserved (NCS backward compatible)
    /// - 1: RFC 4122
    /// - 2: Reserved (Microsoft backward compatible)
    /// - 3: Reserved (future)
    pub fn getVariant(self: UUID) u2 {
        const byte = self.bytes[8];
        if ((byte & 0x80) == 0) return 0;
        if ((byte & 0xC0) == 0x80) return 1;
        if ((byte & 0xE0) == 0xC0) return 2;
        return 3;
    }

    /// Check if this is a nil UUID.
    pub fn isNil(self: UUID) bool {
        for (self.bytes) |byte| {
            if (byte != 0) return false;
        }
        return true;
    }

    /// Check equality with another UUID.
    pub fn eql(self: UUID, other: UUID) bool {
        return std.mem.eql(u8, &self.bytes, &other.bytes);
    }

    /// Compare two UUIDs (lexicographic byte comparison).
    pub fn compare(self: UUID, other: UUID) std.math.Order {
        return std.mem.order(u8, &self.bytes, &other.bytes);
    }

    /// Format for output (standard format with hyphens).
    /// Supports Zig 0.15's simplified format with {f}.
    pub fn format(self: UUID, writer: anytype) !void {
        const str = self.toString();
        try writer.writeAll(&str);
    }

    /// JSON serialization (as quoted string).
    pub fn jsonStringify(self: UUID, options: std.json.StringifyOptions, writer: anytype) !void {
        _ = options;
        try writer.writeByte('"');
        const str = self.toString();
        try writer.writeAll(&str);
        try writer.writeByte('"');
    }

    /// JSON deserialization.
    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !UUID {
        _ = allocator;
        _ = options;
        const str = try source.nextString();
        return fromString(str);
    }
};

// Helper functions

fn hexCharToNibble(c: u8) ?u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => null,
    };
}

fn hexDigit(nibble: u8) u8 {
    if (nibble < 10) {
        return '0' + nibble;
    } else {
        return 'a' + nibble - 10;
    }
}

// ============================================================================
// Tests
// ============================================================================

test "uuid from string with hyphens" {
    const uuid = try UUID.fromString("550e8400-e29b-41d4-a716-446655440000");
    try std.testing.expectEqual(@as(u8, 0x55), uuid.bytes[0]);
    try std.testing.expectEqual(@as(u8, 0x0e), uuid.bytes[1]);
    try std.testing.expectEqual(@as(u8, 0x84), uuid.bytes[2]);
    try std.testing.expectEqual(@as(u8, 0x00), uuid.bytes[3]);
}

test "uuid from string without hyphens" {
    const uuid = try UUID.fromString("550e8400e29b41d4a716446655440000");
    try std.testing.expectEqual(@as(u8, 0x55), uuid.bytes[0]);
}

test "uuid invalid format" {
    // Wrong hyphen position
    try std.testing.expectError(error.InvalidUUIDFormat, UUID.fromString("550e8400-e29b-41d4-a71-6446655440000"));

    // Wrong length
    try std.testing.expectError(error.InvalidUUIDLength, UUID.fromString("550e8400"));

    // Invalid hex character
    try std.testing.expectError(error.InvalidHexCharacter, UUID.fromString("550e8400-e29b-41d4-a716-44665544000g"));
}

test "uuid toString" {
    const uuid = try UUID.fromString("550e8400-e29b-41d4-a716-446655440000");
    const str = uuid.toString();
    try std.testing.expectEqualStrings("550e8400-e29b-41d4-a716-446655440000", &str);
}

test "uuid toCompactString" {
    const uuid = try UUID.fromString("550e8400-e29b-41d4-a716-446655440000");
    const str = uuid.toCompactString();
    try std.testing.expectEqualStrings("550e8400e29b41d4a716446655440000", &str);
}

test "uuid roundtrip" {
    const original = "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11";
    const uuid = try UUID.fromString(original);
    const result = uuid.toString();
    try std.testing.expectEqualStrings(original, &result);
}

test "uuid v4 generation" {
    const uuid = UUID.v4();

    // Check version is 4
    try std.testing.expectEqual(@as(u4, 4), uuid.getVersion());

    // Check variant is RFC 4122 (1)
    try std.testing.expectEqual(@as(u2, 1), uuid.getVariant());
}

test "uuid v4 uniqueness" {
    const uuid1 = UUID.v4();
    const uuid2 = UUID.v4();

    // Two random UUIDs should not be equal
    try std.testing.expect(!uuid1.eql(uuid2));
}

test "uuid nil" {
    const nil = UUID.NIL;
    try std.testing.expect(nil.isNil());

    const non_nil = try UUID.fromString("550e8400-e29b-41d4-a716-446655440000");
    try std.testing.expect(!non_nil.isNil());
}

test "uuid equality" {
    const uuid1 = try UUID.fromString("550e8400-e29b-41d4-a716-446655440000");
    const uuid2 = try UUID.fromString("550e8400-e29b-41d4-a716-446655440000");
    const uuid3 = try UUID.fromString("550e8400-e29b-41d4-a716-446655440001");

    try std.testing.expect(uuid1.eql(uuid2));
    try std.testing.expect(!uuid1.eql(uuid3));
}

test "uuid compare" {
    const uuid_a = try UUID.fromString("00000000-0000-0000-0000-000000000001");
    const uuid_b = try UUID.fromString("00000000-0000-0000-0000-000000000002");

    try std.testing.expectEqual(std.math.Order.lt, uuid_a.compare(uuid_b));
    try std.testing.expectEqual(std.math.Order.gt, uuid_b.compare(uuid_a));
    try std.testing.expectEqual(std.math.Order.eq, uuid_a.compare(uuid_a));
}

test "uuid format" {
    const uuid = try UUID.fromString("550e8400-e29b-41d4-a716-446655440000");

    var buffer: [48]u8 = undefined;
    const result = try std.fmt.bufPrint(&buffer, "{f}", .{uuid});

    try std.testing.expectEqualStrings("550e8400-e29b-41d4-a716-446655440000", result);
}

test "uuid from bytes" {
    var bytes: [16]u8 = [_]u8{0} ** 16;
    bytes[0] = 0x55;
    bytes[1] = 0x0e;

    const uuid = UUID.fromBytes(bytes);
    try std.testing.expectEqual(@as(u8, 0x55), uuid.bytes[0]);
    try std.testing.expectEqual(@as(u8, 0x0e), uuid.bytes[1]);
}

test "uuid from slice" {
    var slice: [16]u8 = [_]u8{0} ** 16;
    slice[0] = 0xAB;

    const uuid = try UUID.fromSlice(&slice);
    try std.testing.expectEqual(@as(u8, 0xAB), uuid.bytes[0]);

    // Wrong length should error
    var short: [8]u8 = [_]u8{0} ** 8;
    try std.testing.expectError(error.InvalidUUIDLength, UUID.fromSlice(&short));
}

test "uuid case insensitive parsing" {
    const lower = try UUID.fromString("550e8400-e29b-41d4-a716-446655440000");
    const upper = try UUID.fromString("550E8400-E29B-41D4-A716-446655440000");
    const mixed = try UUID.fromString("550e8400-E29B-41d4-A716-446655440000");

    try std.testing.expect(lower.eql(upper));
    try std.testing.expect(lower.eql(mixed));
}
