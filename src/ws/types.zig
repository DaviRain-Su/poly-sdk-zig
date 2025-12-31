// WebSocket 消息类型定义
//
// Polymarket CLOB WebSocket API 消息格式
// 端点: wss://ws-subscriptions-clob.polymarket.com/ws/
//
// 支持的频道:
// - market: 公开市场数据（订单簿、价格变化、成交）
// - user: 用户私有数据（订单状态、交易状态）

const std = @import("std");

/// WebSocket 端点配置
pub const Endpoints = struct {
    /// 主网 WebSocket URL
    pub const mainnet = "wss://ws-subscriptions-clob.polymarket.com";

    /// Market Channel 路径
    pub const market_path = "/ws/market";

    /// User Channel 路径
    pub const user_path = "/ws/user";

    /// 完整 Market Channel URL
    pub fn marketUrl() []const u8 {
        return mainnet ++ market_path;
    }

    /// 完整 User Channel URL
    pub fn userUrl() []const u8 {
        return mainnet ++ user_path;
    }
};

/// 频道类型
pub const ChannelType = enum {
    market,
    user,

    pub fn toString(self: ChannelType) []const u8 {
        return switch (self) {
            .market => "market",
            .user => "user",
        };
    }
};

/// 事件类型
pub const EventType = enum {
    book,
    price_change,
    last_trade_price,
    best_bid_ask,
    tick_size_change,
    new_market,
    market_resolved,
    order,
    trade,

    pub fn fromString(s: []const u8) ?EventType {
        if (std.mem.eql(u8, s, "book")) return .book;
        if (std.mem.eql(u8, s, "price_change")) return .price_change;
        if (std.mem.eql(u8, s, "last_trade_price")) return .last_trade_price;
        if (std.mem.eql(u8, s, "best_bid_ask")) return .best_bid_ask;
        if (std.mem.eql(u8, s, "tick_size_change")) return .tick_size_change;
        if (std.mem.eql(u8, s, "new_market")) return .new_market;
        if (std.mem.eql(u8, s, "market_resolved")) return .market_resolved;
        if (std.mem.eql(u8, s, "order")) return .order;
        if (std.mem.eql(u8, s, "trade")) return .trade;
        return null;
    }
};

/// 订单簿层级
pub const BookLevel = struct {
    price: []const u8,
    size: []const u8,
};

/// Book 消息 - 订单簿快照
pub const BookMessage = struct {
    event_type: []const u8 = "book",
    asset_id: []const u8,
    market: []const u8,
    bids: []const BookLevel,
    asks: []const BookLevel,
    timestamp: []const u8,
    hash: ?[]const u8 = null,
};

/// 价格变化项
pub const PriceChangeItem = struct {
    asset_id: []const u8,
    price: []const u8,
    size: []const u8,
    side: []const u8,
    hash: []const u8,
    best_bid: ?[]const u8 = null,
    best_ask: ?[]const u8 = null,
};

/// Price Change 消息
pub const PriceChangeMessage = struct {
    event_type: []const u8 = "price_change",
    market: []const u8,
    price_changes: []const PriceChangeItem,
    timestamp: []const u8,
};

/// Last Trade Price 消息
pub const LastTradePriceMessage = struct {
    event_type: []const u8 = "last_trade_price",
    asset_id: []const u8,
    market: []const u8,
    price: []const u8,
    size: []const u8,
    side: []const u8,
    fee_rate_bps: ?[]const u8 = null,
    timestamp: []const u8,
};

/// Best Bid Ask 消息
pub const BestBidAskMessage = struct {
    event_type: []const u8 = "best_bid_ask",
    asset_id: []const u8,
    market: []const u8,
    best_bid: []const u8,
    best_ask: []const u8,
    spread: ?[]const u8 = null,
    timestamp: []const u8,
};

/// Tick Size Change 消息
pub const TickSizeChangeMessage = struct {
    event_type: []const u8 = "tick_size_change",
    asset_id: []const u8,
    market: []const u8,
    old_tick_size: []const u8,
    new_tick_size: []const u8,
    timestamp: []const u8,
};

/// 订单类型 (User Channel)
pub const OrderType = enum {
    PLACEMENT,
    UPDATE,
    CANCELLATION,

    pub fn fromString(s: []const u8) ?OrderType {
        if (std.mem.eql(u8, s, "PLACEMENT")) return .PLACEMENT;
        if (std.mem.eql(u8, s, "UPDATE")) return .UPDATE;
        if (std.mem.eql(u8, s, "CANCELLATION")) return .CANCELLATION;
        return null;
    }
};

/// 交易状态 (User Channel)
pub const TradeStatus = enum {
    MATCHED,
    MINED,
    CONFIRMED,
    RETRYING,
    FAILED,

    pub fn fromString(s: []const u8) ?TradeStatus {
        if (std.mem.eql(u8, s, "MATCHED")) return .MATCHED;
        if (std.mem.eql(u8, s, "MINED")) return .MINED;
        if (std.mem.eql(u8, s, "CONFIRMED")) return .CONFIRMED;
        if (std.mem.eql(u8, s, "RETRYING")) return .RETRYING;
        if (std.mem.eql(u8, s, "FAILED")) return .FAILED;
        return null;
    }
};

/// Order 消息 (User Channel)
pub const OrderMessage = struct {
    event_type: []const u8 = "order",
    id: []const u8,
    asset_id: []const u8,
    market: []const u8,
    type: []const u8, // PLACEMENT, UPDATE, CANCELLATION
    side: []const u8, // BUY, SELL
    price: []const u8,
    original_size: []const u8,
    size_matched: []const u8,
    outcome: ?[]const u8 = null, // YES, NO
    owner: ?[]const u8 = null,
    order_owner: ?[]const u8 = null,
    timestamp: []const u8,
    associate_trades: ?[]const u8 = null,
};

/// Maker Order (Trade 消息中的)
pub const MakerOrder = struct {
    asset_id: []const u8,
    matched_amount: []const u8,
    order_id: []const u8,
    outcome: []const u8,
    owner: []const u8,
    price: []const u8,
};

/// Trade 消息 (User Channel)
pub const TradeMessage = struct {
    event_type: []const u8 = "trade",
    id: []const u8,
    asset_id: []const u8,
    market: []const u8,
    status: []const u8, // MATCHED, MINED, CONFIRMED, RETRYING, FAILED
    side: []const u8, // BUY, SELL
    price: []const u8,
    size: []const u8,
    outcome: ?[]const u8 = null, // YES, NO
    owner: ?[]const u8 = null,
    trade_owner: ?[]const u8 = null,
    taker_order_id: ?[]const u8 = null,
    maker_orders: ?[]const MakerOrder = null,
    matchtime: ?[]const u8 = null,
    last_update: ?[]const u8 = null,
    timestamp: []const u8,
    type: ?[]const u8 = null, // TRADE
};

// ============================================================================
// 订阅消息
// ============================================================================

/// Market Channel 订阅消息
pub const MarketSubscribeMessage = struct {
    assets_ids: []const []const u8,
    type: []const u8 = "market",
    custom_feature_enabled: bool = false,
};

/// 认证信息 (User Channel)
pub const AuthInfo = struct {
    apiKey: []const u8,
    secret: []const u8,
    passphrase: []const u8,
};

/// User Channel 订阅消息
pub const UserSubscribeMessage = struct {
    auth: AuthInfo,
    markets: []const []const u8,
    type: []const u8 = "user",
};

/// 动态订阅/取消订阅操作
pub const SubscriptionOperation = enum {
    subscribe,
    unsubscribe,

    pub fn toString(self: SubscriptionOperation) []const u8 {
        return switch (self) {
            .subscribe => "subscribe",
            .unsubscribe => "unsubscribe",
        };
    }
};

/// 动态订阅消息
pub const DynamicSubscribeMessage = struct {
    assets_ids: ?[]const []const u8 = null,
    markets: ?[]const []const u8 = null,
    operation: []const u8,
    custom_feature_enabled: bool = false,
};

// ============================================================================
// 通用消息包装
// ============================================================================

/// 原始 WebSocket 消息
pub const RawMessage = struct {
    data: []const u8,
    timestamp: i64,
};

/// 解析后的消息
pub const ParsedMessage = union(enum) {
    book: BookMessage,
    price_change: PriceChangeMessage,
    last_trade_price: LastTradePriceMessage,
    best_bid_ask: BestBidAskMessage,
    tick_size_change: TickSizeChangeMessage,
    order: OrderMessage,
    trade: TradeMessage,
    pong: void, // PONG 响应
    unknown: []const u8, // 未知消息
};

// ============================================================================
// 回调类型
// ============================================================================

/// Book 消息回调
pub const OnBookCallback = *const fn (message: BookMessage) void;

/// Price Change 消息回调
pub const OnPriceChangeCallback = *const fn (message: PriceChangeMessage) void;

/// Last Trade Price 消息回调
pub const OnLastTradePriceCallback = *const fn (message: LastTradePriceMessage) void;

/// Best Bid Ask 消息回调
pub const OnBestBidAskCallback = *const fn (message: BestBidAskMessage) void;

/// Order 消息回调 (User Channel)
pub const OnOrderCallback = *const fn (message: OrderMessage) void;

/// Trade 消息回调 (User Channel)
pub const OnTradeCallback = *const fn (message: TradeMessage) void;

/// 错误回调
pub const OnErrorCallback = *const fn (err: anyerror) void;

/// 连接状态回调
pub const OnConnectionCallback = *const fn (connected: bool) void;

// ============================================================================
// 配置
// ============================================================================

/// Market Channel 配置
pub const MarketChannelConfig = struct {
    /// 要订阅的资产 ID 列表
    assets_ids: []const []const u8 = &.{},

    /// 启用额外功能 (best_bid_ask, new_market, market_resolved)
    custom_feature_enabled: bool = false,

    /// 回调函数
    on_book: ?OnBookCallback = null,
    on_price_change: ?OnPriceChangeCallback = null,
    on_last_trade_price: ?OnLastTradePriceCallback = null,
    on_best_bid_ask: ?OnBestBidAskCallback = null,
    on_error: ?OnErrorCallback = null,
    on_connection: ?OnConnectionCallback = null,

    /// 自动重连
    auto_reconnect: bool = true,
    max_reconnect_attempts: u32 = 5,
    reconnect_delay_ms: u64 = 1000,

    /// 心跳间隔 (毫秒)
    heartbeat_interval_ms: u64 = 10000,
};

/// User Channel 配置
pub const UserChannelConfig = struct {
    /// API 凭证
    api_key: []const u8,
    api_secret: []const u8,
    api_passphrase: []const u8,

    /// 要订阅的市场 ID (condition_id) 列表
    markets: []const []const u8 = &.{},

    /// 回调函数
    on_order: ?OnOrderCallback = null,
    on_trade: ?OnTradeCallback = null,
    on_error: ?OnErrorCallback = null,
    on_connection: ?OnConnectionCallback = null,

    /// 自动重连
    auto_reconnect: bool = true,
    max_reconnect_attempts: u32 = 5,
    reconnect_delay_ms: u64 = 1000,

    /// 心跳间隔 (毫秒)
    heartbeat_interval_ms: u64 = 10000,
};

// ============================================================================
// 测试
// ============================================================================

test "EventType.fromString" {
    try std.testing.expectEqual(EventType.book, EventType.fromString("book").?);
    try std.testing.expectEqual(EventType.price_change, EventType.fromString("price_change").?);
    try std.testing.expectEqual(EventType.order, EventType.fromString("order").?);
    try std.testing.expectEqual(EventType.trade, EventType.fromString("trade").?);
    try std.testing.expect(EventType.fromString("invalid") == null);
}

test "ChannelType.toString" {
    try std.testing.expectEqualStrings("market", ChannelType.market.toString());
    try std.testing.expectEqualStrings("user", ChannelType.user.toString());
}

test "OrderType.fromString" {
    try std.testing.expectEqual(OrderType.PLACEMENT, OrderType.fromString("PLACEMENT").?);
    try std.testing.expectEqual(OrderType.UPDATE, OrderType.fromString("UPDATE").?);
    try std.testing.expectEqual(OrderType.CANCELLATION, OrderType.fromString("CANCELLATION").?);
    try std.testing.expect(OrderType.fromString("INVALID") == null);
}

test "TradeStatus.fromString" {
    try std.testing.expectEqual(TradeStatus.MATCHED, TradeStatus.fromString("MATCHED").?);
    try std.testing.expectEqual(TradeStatus.CONFIRMED, TradeStatus.fromString("CONFIRMED").?);
    try std.testing.expectEqual(TradeStatus.FAILED, TradeStatus.fromString("FAILED").?);
    try std.testing.expect(TradeStatus.fromString("INVALID") == null);
}

test "Endpoints" {
    try std.testing.expectEqualStrings(
        "wss://ws-subscriptions-clob.polymarket.com/ws/market",
        Endpoints.marketUrl(),
    );
    try std.testing.expectEqualStrings(
        "wss://ws-subscriptions-clob.polymarket.com/ws/user",
        Endpoints.userUrl(),
    );
}

test "SubscriptionOperation.toString" {
    try std.testing.expectEqualStrings("subscribe", SubscriptionOperation.subscribe.toString());
    try std.testing.expectEqualStrings("unsubscribe", SubscriptionOperation.unsubscribe.toString());
}
