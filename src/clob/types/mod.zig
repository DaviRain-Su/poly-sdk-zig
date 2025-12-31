//! CLOB API types module.
//!
//! This module exports all types used by the Polymarket CLOB API.

pub const enums = @import("enums.zig");
pub const market = @import("market.zig");
pub const book = @import("book.zig");

// Re-export commonly used types
pub const OrderType = enums.OrderType;
pub const Side = enums.Side;
pub const AssetType = enums.AssetType;
pub const SignatureType = enums.SignatureType;
pub const TickSize = enums.TickSize;
pub const TraderSide = enums.TraderSide;

pub const Token = market.Token;
pub const Market = market.Market;
pub const SimplifiedMarket = market.SimplifiedMarket;
pub const SamplingMarket = market.SamplingMarket;
pub const MarketsParams = market.MarketsParams;

pub const OrderSummary = book.OrderSummary;
pub const OrderBookSummary = book.OrderBookSummary;
pub const BookParams = book.BookParams;
pub const PriceResponse = book.PriceResponse;
pub const MidpointResponse = book.MidpointResponse;
pub const SpreadResponse = book.SpreadResponse;
pub const TickSizeResponse = book.TickSizeResponse;
pub const NegRiskResponse = book.NegRiskResponse;
pub const LastTradePriceResponse = book.LastTradePriceResponse;

// ============================================================================
// Tests
// ============================================================================

test "all type modules" {
    _ = enums;
    _ = market;
    _ = book;
}

test "type exports" {
    _ = OrderType.GTC;
    _ = Side.BUY;
    _ = Token{ .token_id = "1", .outcome = "Yes" };
    _ = OrderSummary{ .price = "0.5", .size = "10" };
}
