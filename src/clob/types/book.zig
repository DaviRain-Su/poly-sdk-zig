//! Order book types for Polymarket CLOB API.

const std = @import("std");

/// Price level in order book (bid or ask)
pub const OrderSummary = struct {
    /// Price at this level (as string)
    price: []const u8,
    /// Total size at this price level (as string)
    size: []const u8,
};

/// Order book summary
pub const OrderBookSummary = struct {
    /// Market condition ID
    market: ?[]const u8 = null,
    /// Token/Asset ID
    asset_id: ?[]const u8 = null,
    /// Timestamp
    timestamp: ?[]const u8 = null,
    /// Bid orders (buy side)
    bids: ?[]OrderSummary = null,
    /// Ask orders (sell side)
    asks: ?[]OrderSummary = null,
    /// Minimum order size (as string)
    min_order_size: ?[]const u8 = null,
    /// Tick size (e.g., "0.01")
    tick_size: ?[]const u8 = null,
    /// Is neg risk market
    neg_risk: ?bool = null,
    /// Order book hash
    hash: ?[]const u8 = null,
};

/// Order book query parameters
pub const BookParams = struct {
    /// Token ID to query
    token_id: []const u8,
};

/// Price response
pub const PriceResponse = struct {
    /// Price (as string)
    price: ?[]const u8 = null,
};

/// Midpoint response
pub const MidpointResponse = struct {
    /// Midpoint price (as string)
    mid: ?[]const u8 = null,
};

/// Spread response
pub const SpreadResponse = struct {
    /// Spread value (as string)
    spread: ?[]const u8 = null,
};

/// Tick size response
pub const TickSizeResponse = struct {
    /// Minimum tick size
    minimum_tick_size: ?[]const u8 = null,
};

/// Neg risk response
pub const NegRiskResponse = struct {
    /// Is neg risk market
    neg_risk: ?bool = null,
};

/// Last trade price response
pub const LastTradePriceResponse = struct {
    /// Last trade price (as string)
    price: ?[]const u8 = null,
};

// ============================================================================
// Tests
// ============================================================================

test "OrderSummary struct" {
    const order = OrderSummary{
        .price = "0.65",
        .size = "100",
    };
    try std.testing.expectEqualStrings("0.65", order.price);
    try std.testing.expectEqualStrings("100", order.size);
}

test "OrderBookSummary struct" {
    const book = OrderBookSummary{
        .market = "0xabc",
        .asset_id = "12345",
        .tick_size = "0.01",
        .neg_risk = false,
    };
    try std.testing.expectEqualStrings("0xabc", book.market.?);
    try std.testing.expect(!book.neg_risk.?);
}

test "BookParams struct" {
    const params = BookParams{
        .token_id = "12345",
    };
    try std.testing.expectEqualStrings("12345", params.token_id);
}
