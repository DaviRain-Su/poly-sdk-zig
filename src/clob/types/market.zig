//! Market-related types for Polymarket CLOB API.

const std = @import("std");

/// Token information in a market
pub const Token = struct {
    /// Token ID
    token_id: []const u8,
    /// Outcome name (e.g., "Yes", "No")
    outcome: []const u8,
    /// Current price (0.0 to 1.0)
    price: ?f64 = null,
    /// Winner status
    winner: ?bool = null,
};

/// Rewards info in a market
pub const MarketRewards = struct {
    /// Rates can be null, an array, or other JSON types - use json.Value for flexibility
    rates: ?std.json.Value = null,
    min_size: ?f64 = null,
    max_spread: ?f64 = null,
};

/// Market information
pub const Market = struct {
    /// Condition ID (unique identifier)
    condition_id: []const u8,
    /// Question text
    question: ?[]const u8 = null,
    /// Market description
    description: ?[]const u8 = null,
    /// Tokens in this market
    tokens: ?[]Token = null,
    /// End date (ISO string)
    end_date_iso: ?[]const u8 = null,
    /// Game start time
    game_start_time: ?[]const u8 = null,
    /// Is market active
    active: ?bool = null,
    /// Is market closed
    closed: ?bool = null,
    /// Is market archived
    archived: ?bool = null,
    /// Accept orders
    accepting_orders: ?bool = null,
    /// Accept order timestamp
    accepting_order_timestamp: ?[]const u8 = null,
    /// Minimum order size (numeric)
    minimum_order_size: ?f64 = null,
    /// Minimum tick size (numeric)
    minimum_tick_size: ?f64 = null,
    /// Question ID
    question_id: ?[]const u8 = null,
    /// Is market funded
    funded: ?bool = null,
    /// Market maker address
    market_maker_address: ?[]const u8 = null,
    /// Market slug
    market_slug: ?[]const u8 = null,
    /// Event slug
    event_slug: ?[]const u8 = null,
    /// Maker base fee (numeric)
    maker_base_fee: ?f64 = null,
    /// Taker base fee (numeric)
    taker_base_fee: ?f64 = null,
    /// Notifications enabled
    notifications_enabled: ?bool = null,
    /// Neg risk
    neg_risk: ?bool = null,
    /// Neg risk market ID
    neg_risk_market_id: ?[]const u8 = null,
    /// Neg risk request ID
    neg_risk_request_id: ?[]const u8 = null,
    /// Icon URL
    icon: ?[]const u8 = null,
    /// Image URL
    image: ?[]const u8 = null,
    /// Spread (numeric)
    spread: ?f64 = null,
    /// Order price min tick size (numeric)
    order_price_min_tick_size: ?f64 = null,
    /// Tags
    tags: ?[][]const u8 = null,
    /// Enable order book
    enable_order_book: ?bool = null,
    /// Seconds delay
    seconds_delay: ?i64 = null,
    /// FPMM address
    fpmm: ?[]const u8 = null,
    /// Rewards info
    rewards: ?MarketRewards = null,
    /// Is 50/50 outcome
    is_50_50_outcome: ?bool = null,
};

/// Simplified market (less fields)
pub const SimplifiedMarket = struct {
    condition_id: []const u8,
    tokens: []Token,
};

/// Sampling market for random market selection
pub const SamplingMarket = struct {
    condition_id: []const u8,
    tokens: []Token,
    rewards_min_size: ?[]const u8 = null,
    rewards_max_spread: ?[]const u8 = null,
    spread: ?[]const u8 = null,
};

/// Markets query parameters
pub const MarketsParams = struct {
    /// Filter by condition ID
    next_cursor: ?[]const u8 = null,
};

/// API response wrapper for markets list
pub const MarketsResponse = struct {
    /// List of markets
    data: []Market,
    /// Cursor for pagination
    next_cursor: ?[]const u8 = null,
    /// Limit per page
    limit: ?u32 = null,
    /// Total count
    count: ?u32 = null,
};

/// API response wrapper for simplified markets list
pub const SimplifiedMarketsResponse = struct {
    /// List of simplified markets
    data: []SimplifiedMarket,
    /// Cursor for pagination
    next_cursor: ?[]const u8 = null,
    /// Limit per page
    limit: ?u32 = null,
    /// Total count
    count: ?u32 = null,
};

// ============================================================================
// Tests
// ============================================================================

test "Token struct" {
    const token = Token{
        .token_id = "12345",
        .outcome = "Yes",
        .price = 0.65,
    };
    try std.testing.expectEqualStrings("12345", token.token_id);
    try std.testing.expectEqualStrings("Yes", token.outcome);
    try std.testing.expectApproxEqAbs(0.65, token.price.?, 0.001);
}

test "Market struct" {
    const market = Market{
        .condition_id = "0xabc123",
        .question = "Will it rain tomorrow?",
        .active = true,
    };
    try std.testing.expectEqualStrings("0xabc123", market.condition_id);
    try std.testing.expect(market.active.?);
}
