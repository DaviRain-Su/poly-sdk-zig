const std = @import("std");
const poly_sdk_zig = @import("poly_sdk_zig");

pub fn main() !void {
    std.debug.print("Polymarket CLOB API Client for Zig\n", .{});
    std.debug.print("===================================\n\n", .{});
    std.debug.print("Version: 0.6.0\n", .{});
    std.debug.print("Zig Version: 0.15.2+\n\n", .{});

    std.debug.print("Modules:\n", .{});
    std.debug.print("  - types:  Core types (Decimal, Secret, Address, UUID)\n", .{});
    std.debug.print("  - clob:   CLOB API client\n", .{});
    std.debug.print("  - auth:   Authentication (L1/L2)\n", .{});
    std.debug.print("  - signer: Wallet and EIP-712 signing\n", .{});
    std.debug.print("  - order:  Order builder\n", .{});
    std.debug.print("  - rfq:    RFQ (Request for Quote) client\n", .{});
    std.debug.print("  - ws:     WebSocket client\n", .{});
    std.debug.print("  - crypto: Cryptographic primitives\n\n", .{});

    std.debug.print("For usage examples, see examples/ directory.\n", .{});
    std.debug.print("For documentation, see docs/ directory.\n", .{});

    // Show available types
    _ = poly_sdk_zig.types;
    _ = poly_sdk_zig.clob;
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
