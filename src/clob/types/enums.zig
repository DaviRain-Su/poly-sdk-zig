//! Enumeration types for Polymarket CLOB API.

const std = @import("std");

/// Order type - determines order behavior
pub const OrderType = enum {
    /// Good Till Cancelled - order stays until filled or cancelled
    GTC,
    /// Good Till Date - order stays until expiration date
    GTD,
    /// Fill Or Kill - entire order must fill immediately or cancel
    FOK,
    /// Fill And Kill - partial fill allowed, rest cancelled
    FAK,

    pub fn toString(self: OrderType) []const u8 {
        return switch (self) {
            .GTC => "GTC",
            .GTD => "GTD",
            .FOK => "FOK",
            .FAK => "FAK",
        };
    }

    pub fn jsonStringify(self: OrderType, options: std.json.StringifyOptions, writer: anytype) !void {
        _ = options;
        try writer.writeByte('"');
        try writer.writeAll(self.toString());
        try writer.writeByte('"');
    }
};

/// Trade side - buy or sell
pub const Side = enum {
    BUY,
    SELL,

    pub fn toString(self: Side) []const u8 {
        return switch (self) {
            .BUY => "BUY",
            .SELL => "SELL",
        };
    }

    pub fn jsonStringify(self: Side, options: std.json.StringifyOptions, writer: anytype) !void {
        _ = options;
        try writer.writeByte('"');
        try writer.writeAll(self.toString());
        try writer.writeByte('"');
    }
};

/// Asset type for balance queries
pub const AssetType = enum {
    /// USDC collateral
    COLLATERAL,
    /// Conditional token
    CONDITIONAL,

    pub fn toString(self: AssetType) []const u8 {
        return switch (self) {
            .COLLATERAL => "COLLATERAL",
            .CONDITIONAL => "CONDITIONAL",
        };
    }
};

/// Signature type - determines how signatures are verified
pub const SignatureType = enum(u8) {
    /// Standard EOA (MetaMask, hardware wallets)
    EOA = 0,
    /// Email/Magic wallet (delegated signing)
    POLY_PROXY = 1,
    /// Browser wallet proxy (Gnosis Safe)
    POLY_GNOSIS_SAFE = 2,
};

/// Tick size - price precision
pub const TickSize = enum {
    /// 0.1
    @"0.1",
    /// 0.01
    @"0.01",
    /// 0.001
    @"0.001",
    /// 0.0001
    @"0.0001",

    pub fn toString(self: TickSize) []const u8 {
        return switch (self) {
            .@"0.1" => "0.1",
            .@"0.01" => "0.01",
            .@"0.001" => "0.001",
            .@"0.0001" => "0.0001",
        };
    }

    pub fn decimals(self: TickSize) u8 {
        return switch (self) {
            .@"0.1" => 1,
            .@"0.01" => 2,
            .@"0.001" => 3,
            .@"0.0001" => 4,
        };
    }
};

/// Trader side in a trade
pub const TraderSide = enum {
    TAKER,
    MAKER,
};

// ============================================================================
// Tests
// ============================================================================

test "OrderType toString" {
    try std.testing.expectEqualStrings("GTC", OrderType.GTC.toString());
    try std.testing.expectEqualStrings("FOK", OrderType.FOK.toString());
}

test "Side toString" {
    try std.testing.expectEqualStrings("BUY", Side.BUY.toString());
    try std.testing.expectEqualStrings("SELL", Side.SELL.toString());
}

test "TickSize decimals" {
    try std.testing.expectEqual(@as(u8, 1), TickSize.@"0.1".decimals());
    try std.testing.expectEqual(@as(u8, 4), TickSize.@"0.0001".decimals());
}

test "SignatureType values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(SignatureType.EOA));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(SignatureType.POLY_PROXY));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(SignatureType.POLY_GNOSIS_SAFE));
}
