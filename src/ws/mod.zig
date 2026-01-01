// WebSocket 模块
//
// Polymarket CLOB WebSocket API 客户端
//
// 支持的频道:
// - Market Channel: 公开市场数据（订单簿、价格变化、成交）
// - User Channel: 用户私有数据（订单状态、交易状态）
//
// ## 简单用法 (低级 API)
//
// ```zig
// const ws = @import("poly-sdk-zig").ws;
//
// var client = try ws.WebSocketClient.init(allocator, ws.Endpoints.marketUrl());
// defer client.deinit();
// try client.connect();
//
// const subscribe_msg = try ws.serializeMarketSubscribe(allocator, &.{"token_id"}, false);
// defer allocator.free(subscribe_msg);
// try client.send(subscribe_msg);
//
// while (true) {
//     if (try client.receive()) |msg| {
//         // 处理消息
//         allocator.free(msg);
//     }
// }
// ```
//
// ## 高级用法 (Channel API)
//
// ```zig
// const ws = @import("poly-sdk-zig").ws;
//
// // Market Channel
// var market = try ws.MarketChannel.init(allocator, .{
//     .on_book = myBookHandler,
//     .on_price_change = myPriceHandler,
// });
// defer market.deinit();
// try market.connect();
// try market.subscribe(&.{ "token_id" });
// try market.run();
//
// // User Channel
// var user = try ws.UserChannel.init(allocator, .{
//     .api_key = "key",
//     .api_secret = "secret",
//     .api_passphrase = "pass",
//     .on_order = myOrderHandler,
//     .on_trade = myTradeHandler,
// });
// defer user.deinit();
// try user.connect(&.{ "condition_id" });
// try user.run();
// ```

const std = @import("std");

// 子模块
pub const types = @import("types.zig");
pub const client = @import("client.zig");
pub const parser = @import("parser.zig");
pub const market = @import("market.zig");
pub const user = @import("user.zig");

// ============================================================================
// 低级 API - WebSocket 客户端
// ============================================================================

/// WebSocket 客户端
pub const WebSocketClient = client.WebSocketClient;

/// WebSocket 错误
pub const WebSocketError = client.WebSocketError;

/// 连接状态
pub const ConnectionState = client.ConnectionState;

// ============================================================================
// 高级 API - Channel 包装器
// ============================================================================

/// Market Channel (公开市场数据)
pub const MarketChannel = market.MarketChannel;

/// Market Channel 配置
pub const MarketChannelOptions = market.MarketChannelOptions;

/// Market Channel 错误
pub const MarketChannelError = market.MarketChannelError;

/// User Channel (用户私有数据)
pub const UserChannel = user.UserChannel;

/// User Channel 配置
pub const UserChannelOptions = user.UserChannelOptions;

/// User Channel 错误
pub const UserChannelError = user.UserChannelError;

// ============================================================================
// 消息类型
// ============================================================================

/// 订单簿快照消息
pub const BookMessage = types.BookMessage;

/// 价格变化消息
pub const PriceChangeMessage = types.PriceChangeMessage;

/// 最新成交价消息
pub const LastTradePriceMessage = types.LastTradePriceMessage;

/// 最佳买卖价消息
pub const BestBidAskMessage = types.BestBidAskMessage;

/// Tick Size 变化消息
pub const TickSizeChangeMessage = types.TickSizeChangeMessage;

/// 订单消息 (User Channel)
pub const OrderMessage = types.OrderMessage;

/// 交易消息 (User Channel)
pub const TradeMessage = types.TradeMessage;

/// 订单簿层级
pub const BookLevel = types.BookLevel;

// ============================================================================
// 解析器
// ============================================================================

/// 消息解析器
pub const MessageParser = parser.MessageParser;

/// 解析结果
pub const ParseResult = parser.ParseResult;

/// 带资源管理的解析结果
pub const ParsedMessage = parser.ParsedMessage;

/// 解析错误
pub const ParseError = parser.ParseError;

/// 快速检测事件类型
pub const detectEventType = parser.detectEventType;

/// 检查是否是 PONG
pub const isPong = parser.isPong;

/// 提取 asset_id
pub const extractAssetId = parser.extractAssetId;

/// 提取 market
pub const extractMarket = parser.extractMarket;

// ============================================================================
// 配置和常量
// ============================================================================

/// WebSocket 端点
pub const Endpoints = types.Endpoints;

/// 频道类型
pub const ChannelType = types.ChannelType;

/// 事件类型
pub const EventType = types.EventType;

/// 订单类型 (User Channel)
pub const OrderType = types.OrderType;

/// 交易状态 (User Channel)
pub const TradeStatus = types.TradeStatus;

// ============================================================================
// 序列化函数
// ============================================================================

/// 序列化 Market Channel 订阅消息
pub const serializeMarketSubscribe = client.serializeMarketSubscribe;

/// 序列化 User Channel 订阅消息
pub const serializeUserSubscribe = client.serializeUserSubscribe;

/// 序列化动态订阅/取消订阅消息
pub const serializeDynamicSubscribe = client.serializeDynamicSubscribe;

// ============================================================================
// 测试
// ============================================================================

test {
    // 运行所有子模块测试
    std.testing.refAllDecls(@This());
}

test "module exports - low level API" {
    // 验证低级 API 类型导出
    _ = WebSocketClient;
    _ = WebSocketError;
    _ = ConnectionState;

    // 验证序列化函数
    _ = serializeMarketSubscribe;
    _ = serializeUserSubscribe;
    _ = serializeDynamicSubscribe;
}

test "module exports - high level API" {
    // 验证高级 API 类型导出
    _ = MarketChannel;
    _ = MarketChannelOptions;
    _ = MarketChannelError;
    _ = UserChannel;
    _ = UserChannelOptions;
    _ = UserChannelError;
}

test "module exports - message types" {
    // 验证消息类型导出
    _ = BookMessage;
    _ = PriceChangeMessage;
    _ = LastTradePriceMessage;
    _ = BestBidAskMessage;
    _ = TickSizeChangeMessage;
    _ = OrderMessage;
    _ = TradeMessage;
    _ = BookLevel;
}

test "module exports - parser" {
    // 验证解析器导出
    _ = MessageParser;
    _ = ParseResult;
    _ = ParseError;
    _ = detectEventType;
    _ = isPong;
    _ = extractAssetId;
    _ = extractMarket;
}

test "module exports - constants" {
    // 验证常量和枚举导出
    _ = Endpoints;
    _ = ChannelType;
    _ = EventType;
    _ = OrderType;
    _ = TradeStatus;

    // 验证端点 URL
    try std.testing.expectEqualStrings(
        "wss://ws-subscriptions-clob.polymarket.com/ws/market",
        Endpoints.marketUrl(),
    );
    try std.testing.expectEqualStrings(
        "wss://ws-subscriptions-clob.polymarket.com/ws/user",
        Endpoints.userUrl(),
    );
}
