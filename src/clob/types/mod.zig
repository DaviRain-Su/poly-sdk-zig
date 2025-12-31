//! CLOB API types module.
//!
//! This module exports all types used by the Polymarket CLOB API.

pub const enums = @import("enums.zig");
pub const market = @import("market.zig");
pub const book = @import("book.zig");
pub const order = @import("order.zig");
pub const trade = @import("trade.zig");
pub const account = @import("account.zig");

// Re-export commonly used types - enums
pub const OrderType = enums.OrderType;
pub const Side = enums.Side;
pub const AssetType = enums.AssetType;
pub const SignatureType = enums.SignatureType;
pub const TickSize = enums.TickSize;
pub const TraderSide = enums.TraderSide;

// Re-export market types
pub const Token = market.Token;
pub const Market = market.Market;
pub const SimplifiedMarket = market.SimplifiedMarket;
pub const SamplingMarket = market.SamplingMarket;
pub const MarketsParams = market.MarketsParams;

// Re-export book types
pub const OrderSummary = book.OrderSummary;
pub const OrderBookSummary = book.OrderBookSummary;
pub const BookParams = book.BookParams;
pub const PriceResponse = book.PriceResponse;
pub const MidpointResponse = book.MidpointResponse;
pub const SpreadResponse = book.SpreadResponse;
pub const TickSizeResponse = book.TickSizeResponse;
pub const NegRiskResponse = book.NegRiskResponse;
pub const LastTradePriceResponse = book.LastTradePriceResponse;

// Re-export order types
pub const OrderData = order.OrderData;
pub const PostOrderRequest = order.PostOrderRequest;
pub const PostOrdersRequest = order.PostOrdersRequest;
pub const PostOrderResponse = order.PostOrderResponse;
pub const PostOrdersResponse = order.PostOrdersResponse;
pub const OpenOrdersParams = order.OpenOrdersParams;
pub const OpenOrder = order.OpenOrder;
pub const PaginatedResponse = order.PaginatedResponse;
pub const PaginatedOrders = order.PaginatedOrders;
pub const CancelOrderRequest = order.CancelOrderRequest;
pub const CancelOrdersRequest = order.CancelOrdersRequest;
pub const CancelMarketOrdersRequest = order.CancelMarketOrdersRequest;
pub const CancelOrderResponse = order.CancelOrderResponse;
pub const INITIAL_CURSOR = order.INITIAL_CURSOR;
pub const END_CURSOR = order.END_CURSOR;

// Re-export trade types
pub const TradesParams = trade.TradesParams;
pub const Trade = trade.Trade;
pub const PaginatedTrades = trade.PaginatedTrades;

// Re-export account types
pub const BalanceAllowanceParams = account.BalanceAllowanceParams;
pub const BalanceAllowanceResponse = account.BalanceAllowanceResponse;
pub const ApiKeyInfo = account.ApiKeyInfo;
pub const DeleteApiKeyResponse = account.DeleteApiKeyResponse;
pub const BanStatusResponse = account.BanStatusResponse;
pub const Notification = account.Notification;
pub const DropNotificationsRequest = account.DropNotificationsRequest;
pub const DropNotificationsResponse = account.DropNotificationsResponse;

// ============================================================================
// Tests
// ============================================================================

test "all type modules" {
    _ = enums;
    _ = market;
    _ = book;
    _ = order;
    _ = trade;
    _ = account;
}

test "type exports" {
    _ = OrderType.GTC;
    _ = Side.BUY;
    _ = Token{ .token_id = "1", .outcome = "Yes" };
    _ = OrderSummary{ .price = "0.5", .size = "10" };
}

test "order type exports" {
    _ = PostOrderResponse{ .success = true };
    _ = OpenOrder{ .id = "123" };
    _ = CancelOrderResponse{ .success = true };
}

test "trade type exports" {
    _ = Trade{ .id = "trade1" };
    _ = TradesParams{};
}

test "account type exports" {
    _ = BalanceAllowanceResponse{};
    _ = ApiKeyInfo{ .apiKey = "key" };
    _ = Notification{ .id = "n1" };
}
