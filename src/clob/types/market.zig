//! Market-related types for Polymarket CLOB API.

const std = @import("std");

/// Token information in a market
pub const Token = struct {
    /// Token ID
    token_id: []const u8,
    /// Outcome name (e.g., "Yes", "No")
    outcome: []const u8,
    /// Current price (as string, parse with Decimal)
    price: ?[]const u8 = null,
    /// Winner status
    winner: ?bool = null,
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
    /// Minimum order size
    minimum_order_size: ?[]const u8 = null,
    /// Minimum tick size
    minimum_tick_size: ?[]const u8 = null,
    /// Condition ID
    condition_id_field: ?[]const u8 = null,
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
    /// Maker base fee
    maker_base_fee: ?[]const u8 = null,
    /// Taker base fee
    taker_base_fee: ?[]const u8 = null,
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
    /// Rewards min size
    rewards_min_size: ?[]const u8 = null,
    /// Rewards max spread
    rewards_max_spread: ?[]const u8 = null,
    /// Spread
    spread: ?[]const u8 = null,
    /// Order price min tick size
    order_price_min_tick_size: ?[]const u8 = null,
    /// Tags
    tags: ?[][]const u8 = null,
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

// ============================================================================
// Tests
// ============================================================================

test "Token struct" {
    const token = Token{
        .token_id = "12345",
        .outcome = "Yes",
        .price = "0.65",
    };
    try std.testing.expectEqualStrings("12345", token.token_id);
    try std.testing.expectEqualStrings("Yes", token.outcome);
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
