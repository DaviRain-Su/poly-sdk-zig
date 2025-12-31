//! Ethereum address type with EIP-55 checksum support.
//!
//! An Ethereum address is a 20-byte (160-bit) value typically represented as
//! a 40 hexadecimal character string prefixed with "0x".
//!
//! EIP-55 defines a checksum scheme using mixed-case hexadecimal encoding.
//! This helps detect typos when addresses are manually entered.
//!
//! ```zig
//! const addr = try Address.fromHex("0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045");
//! std.debug.print("{}", .{addr});  // "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
//! ```

const std = @import("std");
const Keccak256 = std.crypto.hash.sha3.Keccak256;

/// Ethereum address (20 bytes)
pub const Address = struct {
    bytes: [20]u8,

    /// Zero address (0x0000...0000)
    pub const ZERO = Address{ .bytes = [_]u8{0} ** 20 };

    /// Parse address from hexadecimal string.
    ///
    /// Accepts:
    /// - With "0x" prefix: "0x1234...abcd"
    /// - Without prefix: "1234...abcd"
    /// - Mixed case (EIP-55 checksummed or lowercase)
    ///
    /// Returns error if:
    /// - String is wrong length
    /// - String contains invalid hex characters
    /// - EIP-55 checksum validation fails (for mixed-case input)
    pub fn fromHex(hex: []const u8) !Address {
        const input = if (hex.len >= 2 and std.mem.eql(u8, hex[0..2], "0x"))
            hex[2..]
        else
            hex;

        if (input.len != 40) {
            return error.InvalidAddressLength;
        }

        // Check if input is all lowercase or all uppercase (no checksum validation needed)
        // or mixed case (checksum validation required)
        var has_upper = false;
        var has_lower = false;

        for (input) |c| {
            if (c >= 'A' and c <= 'F') has_upper = true;
            if (c >= 'a' and c <= 'f') has_lower = true;
        }

        // Parse hex bytes
        var bytes: [20]u8 = undefined;
        for (0..20) |i| {
            const hi = hexCharToNibble(input[i * 2]) orelse return error.InvalidHexCharacter;
            const lo = hexCharToNibble(input[i * 2 + 1]) orelse return error.InvalidHexCharacter;
            bytes[i] = (hi << 4) | lo;
        }

        const addr = Address{ .bytes = bytes };

        // If mixed case, validate EIP-55 checksum
        if (has_upper and has_lower) {
            const checksummed = addr.toChecksumHex();
            // Compare without "0x" prefix
            if (!std.mem.eql(u8, input, checksummed[2..])) {
                return error.InvalidChecksum;
            }
        }

        return addr;
    }

    /// Parse address from hexadecimal string without checksum validation.
    ///
    /// Use this when you trust the input source and don't need checksum validation.
    pub fn fromHexUnchecked(hex: []const u8) !Address {
        const input = if (hex.len >= 2 and std.mem.eql(u8, hex[0..2], "0x"))
            hex[2..]
        else
            hex;

        if (input.len != 40) {
            return error.InvalidAddressLength;
        }

        var bytes: [20]u8 = undefined;
        for (0..20) |i| {
            const hi = hexCharToNibble(input[i * 2]) orelse return error.InvalidHexCharacter;
            const lo = hexCharToNibble(input[i * 2 + 1]) orelse return error.InvalidHexCharacter;
            bytes[i] = (hi << 4) | lo;
        }

        return Address{ .bytes = bytes };
    }

    /// Create address from raw bytes.
    pub fn fromBytes(bytes: [20]u8) Address {
        return Address{ .bytes = bytes };
    }

    /// Create address from a byte slice.
    pub fn fromSlice(slice: []const u8) !Address {
        if (slice.len != 20) {
            return error.InvalidAddressLength;
        }
        var bytes: [20]u8 = undefined;
        @memcpy(&bytes, slice);
        return Address{ .bytes = bytes };
    }

    /// Get raw bytes.
    pub fn toBytes(self: Address) [20]u8 {
        return self.bytes;
    }

    /// Get as byte slice.
    pub fn asSlice(self: *const Address) []const u8 {
        return &self.bytes;
    }

    /// Convert to lowercase hex string (without checksum).
    pub fn toLowerHex(self: Address) [42]u8 {
        var result: [42]u8 = undefined;
        result[0] = '0';
        result[1] = 'x';

        for (self.bytes, 0..) |byte, i| {
            result[2 + i * 2] = hexDigit(byte >> 4, false);
            result[2 + i * 2 + 1] = hexDigit(byte & 0x0F, false);
        }

        return result;
    }

    /// Convert to EIP-55 checksummed hex string.
    ///
    /// EIP-55 mixes uppercase and lowercase letters based on the hash of the address.
    /// This provides error detection without adding extra characters.
    pub fn toChecksumHex(self: Address) [42]u8 {
        var result: [42]u8 = undefined;
        result[0] = '0';
        result[1] = 'x';

        // First, get lowercase hex (without 0x prefix) for hashing
        var lowercase: [40]u8 = undefined;
        for (self.bytes, 0..) |byte, i| {
            lowercase[i * 2] = hexDigit(byte >> 4, false);
            lowercase[i * 2 + 1] = hexDigit(byte & 0x0F, false);
        }

        // Hash the lowercase hex string
        var hash: [32]u8 = undefined;
        Keccak256.hash(&lowercase, &hash, .{});

        // Apply checksum: uppercase if corresponding hash nibble >= 8
        for (0..40) |i| {
            const hash_byte = hash[i / 2];
            const hash_nibble = if (i % 2 == 0) hash_byte >> 4 else hash_byte & 0x0F;
            const uppercase = hash_nibble >= 8;
            result[2 + i] = if (uppercase) toUppercase(lowercase[i]) else lowercase[i];
        }

        return result;
    }

    /// Format for output (EIP-55 checksummed format).
    /// Supports Zig 0.15's simplified format with {f}.
    pub fn format(self: Address, writer: anytype) !void {
        const checksummed = self.toChecksumHex();
        try writer.writeAll(&checksummed);
    }

    /// JSON serialization (as quoted checksummed string).
    pub fn jsonStringify(self: Address, options: std.json.StringifyOptions, writer: anytype) !void {
        _ = options;
        try writer.writeByte('"');
        const checksummed = self.toChecksumHex();
        try writer.writeAll(&checksummed);
        try writer.writeByte('"');
    }

    /// JSON deserialization.
    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !Address {
        _ = allocator;
        _ = options;
        const str = try source.nextString();
        return fromHex(str);
    }

    /// Check if this is the zero address.
    pub fn isZero(self: Address) bool {
        for (self.bytes) |byte| {
            if (byte != 0) return false;
        }
        return true;
    }

    /// Check equality with another address.
    pub fn eql(self: Address, other: Address) bool {
        return std.mem.eql(u8, &self.bytes, &other.bytes);
    }

    /// Compare two addresses (lexicographic byte comparison).
    pub fn compare(self: Address, other: Address) std.math.Order {
        return std.mem.order(u8, &self.bytes, &other.bytes);
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

fn hexDigit(nibble: u8, uppercase: bool) u8 {
    if (nibble < 10) {
        return '0' + nibble;
    } else if (uppercase) {
        return 'A' + nibble - 10;
    } else {
        return 'a' + nibble - 10;
    }
}

fn toUppercase(c: u8) u8 {
    if (c >= 'a' and c <= 'f') {
        return c - 'a' + 'A';
    }
    return c;
}

// ============================================================================
// Tests
// ============================================================================

test "address from hex with prefix" {
    const addr = try Address.fromHex("0xd8da6bf26964af9d7eed9e03e53415d37aa96045");
    try std.testing.expectEqual(@as(u8, 0xd8), addr.bytes[0]);
    try std.testing.expectEqual(@as(u8, 0xda), addr.bytes[1]);
    try std.testing.expectEqual(@as(u8, 0x45), addr.bytes[19]);
}

test "address from hex without prefix" {
    const addr = try Address.fromHex("d8da6bf26964af9d7eed9e03e53415d37aa96045");
    try std.testing.expectEqual(@as(u8, 0xd8), addr.bytes[0]);
}

test "address invalid length" {
    try std.testing.expectError(error.InvalidAddressLength, Address.fromHex("0x1234"));
    try std.testing.expectError(error.InvalidAddressLength, Address.fromHex("1234"));
}

test "address invalid hex character" {
    try std.testing.expectError(error.InvalidHexCharacter, Address.fromHex("0xd8da6bf26964af9d7eed9e03e53415d37aa9604g"));
}

test "address EIP-55 checksum generation" {
    // Test case from EIP-55: Vitalik's address
    const addr = try Address.fromHexUnchecked("d8da6bf26964af9d7eed9e03e53415d37aa96045");
    const checksummed = addr.toChecksumHex();
    try std.testing.expectEqualStrings("0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045", &checksummed);
}

test "address EIP-55 checksum validation" {
    // Valid checksummed address (Vitalik's)
    _ = try Address.fromHex("0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045");

    // Invalid checksum (one letter wrong case)
    try std.testing.expectError(error.InvalidChecksum, Address.fromHex("0xd8Da6BF26964aF9D7eEd9e03E53415D37aA96045"));
}

test "address lowercase bypasses checksum" {
    // All lowercase should not validate checksum
    _ = try Address.fromHex("0xd8da6bf26964af9d7eed9e03e53415d37aa96045");
}

test "address uppercase bypasses checksum" {
    // All uppercase should not validate checksum
    _ = try Address.fromHex("0xD8DA6BF26964AF9D7EED9E03E53415D37AA96045");
}

test "address zero" {
    const zero = Address.ZERO;
    try std.testing.expect(zero.isZero());

    const non_zero = try Address.fromHex("0x0000000000000000000000000000000000000001");
    try std.testing.expect(!non_zero.isZero());
}

test "address equality" {
    const a1 = try Address.fromHex("0xd8da6bf26964af9d7eed9e03e53415d37aa96045");
    const a2 = try Address.fromHex("0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045");
    const a3 = try Address.fromHex("0x0000000000000000000000000000000000000001");

    try std.testing.expect(a1.eql(a2));
    try std.testing.expect(!a1.eql(a3));
}

test "address format" {
    const addr = try Address.fromHexUnchecked("d8da6bf26964af9d7eed9e03e53415d37aa96045");

    var buffer: [64]u8 = undefined;
    const result = try std.fmt.bufPrint(&buffer, "{f}", .{addr});

    try std.testing.expectEqualStrings("0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045", result);
}

test "address from bytes" {
    var bytes: [20]u8 = undefined;
    bytes[0] = 0xd8;
    bytes[1] = 0xda;
    for (2..20) |i| {
        bytes[i] = 0;
    }

    const addr = Address.fromBytes(bytes);
    try std.testing.expectEqual(@as(u8, 0xd8), addr.bytes[0]);
    try std.testing.expectEqual(@as(u8, 0xda), addr.bytes[1]);
}

test "address to lower hex" {
    const addr = try Address.fromHexUnchecked("D8DA6BF26964AF9D7EED9E03E53415D37AA96045");
    const lower = addr.toLowerHex();
    try std.testing.expectEqualStrings("0xd8da6bf26964af9d7eed9e03e53415d37aa96045", &lower);
}

test "address compare" {
    const a1 = try Address.fromHex("0x0000000000000000000000000000000000000001");
    const a2 = try Address.fromHex("0x0000000000000000000000000000000000000002");

    try std.testing.expectEqual(std.math.Order.lt, a1.compare(a2));
    try std.testing.expectEqual(std.math.Order.gt, a2.compare(a1));
    try std.testing.expectEqual(std.math.Order.eq, a1.compare(a1));
}

test "address more EIP-55 test cases" {
    // Test cases from EIP-55 specification

    // All caps
    const addr1 = try Address.fromHexUnchecked("52908400098527886E0F7030069857D2E4169EE7");
    try std.testing.expectEqualStrings("0x52908400098527886E0F7030069857D2E4169EE7", &addr1.toChecksumHex());

    // All lower
    const addr2 = try Address.fromHexUnchecked("de709f2102306220921060314715629080e2fb77");
    try std.testing.expectEqualStrings("0xde709f2102306220921060314715629080e2fb77", &addr2.toChecksumHex());

    // Normal cases
    const addr3 = try Address.fromHexUnchecked("5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed");
    try std.testing.expectEqualStrings("0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed", &addr3.toChecksumHex());

    const addr4 = try Address.fromHexUnchecked("fB6916095ca1df60bB79Ce92cE3Ea74c37c5d359");
    try std.testing.expectEqualStrings("0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359", &addr4.toChecksumHex());
}
