//! CLOB API types module.
//!
//! This module exports all types used by the Polymarket CLOB API.

pub const enums = @import("enums.zig");
pub const market = @import("market.zig");
pub const book = @import("book.zig");
pub const order = @import("order.zig");
pub const trade = @import("trade.zig");
pub const account = @import("account.zig");
pub const builder_types = @import("builder.zig");
pub const rewards = @import("rewards.zig");
pub const gamma = @import("gamma.zig");

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
pub const MarketsResponse = market.MarketsResponse;
pub const SimplifiedMarketsResponse = market.SimplifiedMarketsResponse;

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
pub const HeartbeatResponse = account.HeartbeatResponse;

// Re-export builder types
pub const BuilderApiKeyResponse = builder_types.BuilderApiKeyResponse;
pub const BuilderApiKeyInfo = builder_types.BuilderApiKeyInfo;
pub const BuilderTradesParams = builder_types.BuilderTradesParams;
pub const BuilderTrade = builder_types.BuilderTrade;
pub const PaginatedBuilderTrades = builder_types.PaginatedBuilderTrades;
pub const RevokeBuilderApiKeyRequest = builder_types.RevokeBuilderApiKeyRequest;
pub const RevokeBuilderApiKeyResponse = builder_types.RevokeBuilderApiKeyResponse;

// Re-export rewards types
pub const OrderScoringParams = rewards.OrderScoringParams;
pub const OrdersScoringParams = rewards.OrdersScoringParams;
pub const OrderScoringResult = rewards.OrderScoringResult;
pub const OrdersScoringResults = rewards.OrdersScoringResults;
pub const MarketTradeEvent = rewards.MarketTradeEvent;
pub const MarketTradeEvents = rewards.MarketTradeEvents;
pub const MarketTradeEventsParams = rewards.MarketTradeEventsParams;
pub const FeeRateResponse = rewards.FeeRateResponse;
pub const FeeRateParams = rewards.FeeRateParams;
pub const BooksRequest = rewards.BooksRequest;
pub const MidpointsRequest = rewards.MidpointsRequest;
pub const PricesRequest = rewards.PricesRequest;
pub const SpreadsRequest = rewards.SpreadsRequest;
pub const LastTradesPricesRequest = rewards.LastTradesPricesRequest;
pub const ClosedOnlyModeResponse = rewards.ClosedOnlyModeResponse;
pub const UpdateBalanceAllowanceResponse = rewards.UpdateBalanceAllowanceResponse;

// Re-export readonly API key types
pub const ReadonlyApiKeyInfo = rewards.ReadonlyApiKeyInfo;
pub const CreateReadonlyApiKeyParams = rewards.CreateReadonlyApiKeyParams;
pub const CreateReadonlyApiKeyResponse = rewards.CreateReadonlyApiKeyResponse;
pub const DeleteReadonlyApiKeyResponse = rewards.DeleteReadonlyApiKeyResponse;
pub const ValidateReadonlyApiKeyResponse = rewards.ValidateReadonlyApiKeyResponse;

// Re-export liquidity rewards types
pub const UserEarning = rewards.UserEarning;
pub const UserEarningsParams = rewards.UserEarningsParams;
pub const UserTotalEarningsResponse = rewards.UserTotalEarningsResponse;
pub const RewardPercentagesResponse = rewards.RewardPercentagesResponse;
pub const RewardsConfig = rewards.RewardsConfig;
pub const MarketReward = rewards.MarketReward;
pub const CurrentRewardsResponse = rewards.CurrentRewardsResponse;
pub const RawMarketRewardResponse = rewards.RawMarketRewardResponse;
pub const UserEarningsAndMarketsConfigResponse = rewards.UserEarningsAndMarketsConfigResponse;

// Re-export gamma types
pub const GammaMarket = gamma.GammaMarket;
pub const GammaEvent = gamma.GammaEvent;
pub const Tag = gamma.Tag;
pub const GammaMarketsParams = gamma.GammaMarketsParams;
pub const GammaEventsParams = gamma.GammaEventsParams;

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
    _ = builder_types;
    _ = rewards;
    _ = gamma;
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

test "builder type exports" {
    _ = BuilderApiKeyResponse{ .api_key = "key" };
    _ = BuilderApiKeyInfo{ .api_key = "key" };
    _ = BuilderTradesParams{};
    _ = BuilderTrade{ .id = "trade1" };
    _ = RevokeBuilderApiKeyResponse{ .success = true };
}

test "rewards type exports" {
    _ = OrderScoringParams{ .order_id = "order-123" };
    _ = OrdersScoringParams{ .order_ids = &.{} };
    _ = OrderScoringResult{};
    _ = MarketTradeEvent{};
    _ = FeeRateResponse{};
    _ = ClosedOnlyModeResponse{};
}

test "liquidity rewards type exports" {
    _ = UserEarning{};
    _ = UserEarningsParams{};
    _ = UserTotalEarningsResponse{};
    _ = RewardPercentagesResponse{};
    _ = RewardsConfig{};
    _ = MarketReward{};
    _ = CurrentRewardsResponse{};
}

test "gamma type exports" {
    _ = GammaMarket{};
    _ = GammaEvent{};
    _ = Tag{};
    _ = GammaMarketsParams{};
    _ = GammaEventsParams{};
}
