//! Secret type for protecting sensitive data from accidental logging.
//!
//! This wrapper prevents API keys, private keys, and passphrases from being
//! accidentally leaked through debug logging or error messages.
//!
//! ```zig
//! const creds = Credentials{
//!     .api_key = Secret([]const u8).init("sk_live_xxx"),
//! };
//! std.log.info("{}", .{creds.api_key});  // prints "[REDACTED]"
//! const key = creds.api_key.reveal();     // "sk_live_xxx"
//! ```

const std = @import("std");

/// A wrapper type that protects sensitive data from accidental exposure.
///
/// When formatted (e.g., in logs), it outputs "[REDACTED]" instead of the actual value.
/// Use `reveal()` to intentionally access the secret value.
pub fn Secret(comptime T: type) type {
    return struct {
        const Self = @This();

        /// The wrapped secret value
        value: T,

        /// Create a new Secret wrapping the given value
        pub fn init(value: T) Self {
            return .{ .value = value };
        }

        /// Intentionally reveal the secret value.
        ///
        /// This method name is designed to be easily grep-able in code reviews
        /// to find all places where secrets are accessed.
        pub fn reveal(self: Self) T {
            return self.value;
        }

        /// Compare two secrets for equality without revealing them.
        ///
        /// Uses constant-time comparison for slice types to prevent timing attacks.
        pub fn eql(self: Self, other: Self) bool {
            if (comptime isSliceType(T)) {
                return constantTimeEql(self.value, other.value);
            } else {
                return self.value == other.value;
            }
        }

        /// Format always outputs "[REDACTED]" to prevent accidental logging.
        /// Supports both Zig 0.15's simplified format and legacy format.
        pub fn format(self: Self, writer: anytype) !void {
            _ = self;
            try writer.writeAll("[REDACTED]");
        }

        /// JSON serialization - outputs "[REDACTED]" as a JSON string
        pub fn jsonStringify(self: Self, options: std.json.StringifyOptions, writer: anytype) !void {
            _ = self;
            _ = options;
            try writer.writeAll("\"[REDACTED]\"");
        }

        // Check if T is a slice type
        fn isSliceType(comptime U: type) bool {
            const info = @typeInfo(U);
            return info == .pointer and info.pointer.size == .slice;
        }

        // Constant-time comparison for slices (prevents timing attacks)
        fn constantTimeEql(a: T, b: T) bool {
            if (a.len != b.len) {
                return false;
            }
            var result: u8 = 0;
            for (a, b) |x, y| {
                result |= x ^ y;
            }
            return result == 0;
        }
    };
}

/// Convenience type alias for secret strings
pub const SecretString = Secret([]const u8);

// ============================================================================
// Tests
// ============================================================================

test "secret init and reveal" {
    const secret = Secret([]const u8).init("my_api_key");
    try std.testing.expectEqualStrings("my_api_key", secret.reveal());
}

test "secret format outputs redacted" {
    const secret = Secret([]const u8).init("super_secret_key");

    var buffer: [64]u8 = undefined;
    const result = try std.fmt.bufPrint(&buffer, "{f}", .{secret});

    try std.testing.expectEqualStrings("[REDACTED]", result);
}

test "secret equality" {
    const s1 = Secret([]const u8).init("password123");
    const s2 = Secret([]const u8).init("password123");
    const s3 = Secret([]const u8).init("different");

    try std.testing.expect(s1.eql(s2));
    try std.testing.expect(!s1.eql(s3));
}

test "secret with integer type" {
    const secret = Secret(u64).init(12345);
    try std.testing.expectEqual(@as(u64, 12345), secret.reveal());

    var buffer: [64]u8 = undefined;
    const result = try std.fmt.bufPrint(&buffer, "{f}", .{secret});
    try std.testing.expectEqualStrings("[REDACTED]", result);
}

test "secret integer equality" {
    const s1 = Secret(u64).init(42);
    const s2 = Secret(u64).init(42);
    const s3 = Secret(u64).init(99);

    try std.testing.expect(s1.eql(s2));
    try std.testing.expect(!s1.eql(s3));
}

test "secret in struct" {
    const Credentials = struct {
        api_key: Secret([]const u8),
        passphrase: Secret([]const u8),
    };

    const creds = Credentials{
        .api_key = Secret([]const u8).init("sk_live_xxx"),
        .passphrase = Secret([]const u8).init("secret123"),
    };

    // Should be able to reveal
    try std.testing.expectEqualStrings("sk_live_xxx", creds.api_key.reveal());
    try std.testing.expectEqualStrings("secret123", creds.passphrase.reveal());

    // Formatting should show redacted
    var buffer: [64]u8 = undefined;
    const result = try std.fmt.bufPrint(&buffer, "{f}", .{creds.api_key});
    try std.testing.expectEqualStrings("[REDACTED]", result);
}

test "secret constant time comparison" {
    // Test that comparison works correctly for different lengths
    const s1 = Secret([]const u8).init("short");
    const s2 = Secret([]const u8).init("longer_string");

    try std.testing.expect(!s1.eql(s2));
}

test "SecretString alias" {
    const secret = SecretString.init("test_key");
    try std.testing.expectEqualStrings("test_key", secret.reveal());

    var buffer: [64]u8 = undefined;
    const result = try std.fmt.bufPrint(&buffer, "{f}", .{secret});
    try std.testing.expectEqualStrings("[REDACTED]", result);
}
