# WebSocket 模块

> Polymarket CLOB WebSocket API 客户端

## 概述

WebSocket 模块提供实时数据订阅功能，支持：

- **Market Channel**: 公开市场数据（订单簿、价格变化、成交）
- **User Channel**: 用户私有数据（订单状态、交易状态）

## 端点

| 频道 | URL | 认证 |
|------|-----|------|
| Market | `wss://ws-subscriptions-clob.polymarket.com/ws/market` | 无需 |
| User | `wss://ws-subscriptions-clob.polymarket.com/ws/user` | 需要 API Key |

## 快速开始

### 低级 API

```zig
const poly = @import("poly-sdk-zig");
const ws = poly.ws;

// 创建 WebSocket 客户端
var client = try ws.WebSocketClient.init(allocator, ws.Endpoints.marketUrl());
defer client.deinit();

// 连接
try client.connect();

// 订阅
const msg = try ws.serializeMarketSubscribe(allocator, &.{"token_id"}, false);
defer allocator.free(msg);
try client.send(msg);

// 接收消息
while (true) {
    if (try client.receive()) |raw_msg| {
        defer allocator.free(raw_msg);
        // 处理消息...
    }
}
```

### 高级 API - Market Channel

```zig
const poly = @import("poly-sdk-zig");
const ws = poly.ws;

fn onBookUpdate(book: ws.BookMessage) void {
    std.debug.print("Book: {s}\n", .{book.asset_id});
}

fn onPriceChange(change: ws.PriceChangeMessage) void {
    std.debug.print("Price change: {s}\n", .{change.market});
}

pub fn main() !void {
    var channel = try ws.MarketChannel.init(allocator, .{
        .on_book = onBookUpdate,
        .on_price_change = onPriceChange,
        .custom_feature_enabled = true,
    });
    defer channel.deinit();

    try channel.connect();
    try channel.subscribe(&.{
        "71321045679252212594626385532706912750332728571942532289631379312455583992563",
    });
    try channel.run();
}
```

### 高级 API - User Channel

```zig
const poly = @import("poly-sdk-zig");
const ws = poly.ws;

fn onOrderUpdate(order: ws.OrderMessage) void {
    std.debug.print("Order {s}: {s}\n", .{ order.id, order.type });
}

fn onTradeUpdate(trade: ws.TradeMessage) void {
    std.debug.print("Trade {s}: {s}\n", .{ trade.id, trade.status });
}

pub fn main() !void {
    var channel = try ws.UserChannel.init(allocator, .{
        .api_key = "your-api-key",
        .api_secret = "your-api-secret",
        .api_passphrase = "your-passphrase",
        .on_order = onOrderUpdate,
        .on_trade = onTradeUpdate,
    });
    defer channel.deinit();

    try channel.connect(&.{
        "0xbd31dc8a20211944f6b70f31557f1001557b59905b7738480ca09bd4532f84af",
    });
    try channel.run();
}
```

## 消息类型

### Market Channel 消息

| 类型 | 结构体 | 触发时机 |
|------|--------|---------|
| `book` | `BookMessage` | 首次订阅、有成交 |
| `price_change` | `PriceChangeMessage` | 下单、取消 |
| `last_trade_price` | `LastTradePriceMessage` | 成交时 |
| `best_bid_ask` | `BestBidAskMessage` | 价格变化 (需启用) |
| `tick_size_change` | `TickSizeChangeMessage` | 价格 > 0.96 或 < 0.04 |

### User Channel 消息

| 类型 | 结构体 | 触发时机 |
|------|--------|---------|
| `order` | `OrderMessage` | 下单、更新、取消 |
| `trade` | `TradeMessage` | 成交、确认、失败 |

## 消息格式

### BookMessage

```zig
pub const BookMessage = struct {
    event_type: []const u8,  // "book"
    asset_id: []const u8,
    market: []const u8,
    bids: []const BookLevel,
    asks: []const BookLevel,
    timestamp: []const u8,
    hash: ?[]const u8,
};

pub const BookLevel = struct {
    price: []const u8,
    size: []const u8,
};
```

### OrderMessage

```zig
pub const OrderMessage = struct {
    event_type: []const u8,  // "order"
    id: []const u8,
    asset_id: []const u8,
    market: []const u8,
    type: []const u8,        // "PLACEMENT", "UPDATE", "CANCELLATION"
    side: []const u8,        // "BUY", "SELL"
    price: []const u8,
    original_size: []const u8,
    size_matched: []const u8,
    timestamp: []const u8,
    // ...
};
```

### TradeMessage

```zig
pub const TradeMessage = struct {
    event_type: []const u8,  // "trade"
    id: []const u8,
    asset_id: []const u8,
    market: []const u8,
    status: []const u8,      // "MATCHED", "MINED", "CONFIRMED", "FAILED"
    side: []const u8,        // "BUY", "SELL"
    price: []const u8,
    size: []const u8,
    timestamp: []const u8,
    // ...
};
```

## 配置选项

### MarketChannelOptions

```zig
pub const MarketChannelOptions = struct {
    // 启用额外功能 (best_bid_ask, new_market, market_resolved)
    custom_feature_enabled: bool = false,

    // 自动重连
    auto_reconnect: bool = true,
    max_reconnect_attempts: u32 = 5,
    reconnect_delay_ms: u64 = 1000,

    // 心跳间隔 (毫秒)
    heartbeat_interval_ms: u64 = 10000,

    // 回调函数
    on_book: ?*const fn (BookMessage) void = null,
    on_price_change: ?*const fn (PriceChangeMessage) void = null,
    on_last_trade_price: ?*const fn (LastTradePriceMessage) void = null,
    on_best_bid_ask: ?*const fn (BestBidAskMessage) void = null,
    on_error: ?*const fn (anyerror) void = null,
    on_connection: ?*const fn (bool) void = null,
};
```

### UserChannelOptions

```zig
pub const UserChannelOptions = struct {
    // API 凭证 (必填)
    api_key: []const u8,
    api_secret: []const u8,
    api_passphrase: []const u8,

    // 自动重连
    auto_reconnect: bool = true,
    max_reconnect_attempts: u32 = 5,
    reconnect_delay_ms: u64 = 1000,

    // 心跳间隔 (毫秒)
    heartbeat_interval_ms: u64 = 10000,

    // 回调函数
    on_order: ?*const fn (OrderMessage) void = null,
    on_trade: ?*const fn (TradeMessage) void = null,
    on_error: ?*const fn (anyerror) void = null,
    on_connection: ?*const fn (bool) void = null,
};
```

## 解析器

### 快速检测

```zig
const ws = poly.ws;

// 检测事件类型
if (ws.detectEventType(raw_message)) |event_type| {
    switch (event_type) {
        .book => { /* ... */ },
        .price_change => { /* ... */ },
        .order => { /* ... */ },
        .trade => { /* ... */ },
        else => {},
    }
}

// 检查是否是 PONG
if (ws.isPong(raw_message)) {
    // 心跳响应
}

// 快速提取字段
if (ws.extractAssetId(raw_message)) |asset_id| {
    std.debug.print("Asset: {s}\n", .{asset_id});
}
```

### 完整解析

```zig
const ws = poly.ws;

var parser = ws.MessageParser.init(allocator);

const result = try parser.parse(raw_message);
switch (result) {
    .book => |msg| { /* ... */ },
    .price_change => |msg| { /* ... */ },
    .last_trade_price => |msg| { /* ... */ },
    .order => |msg| { /* ... */ },
    .trade => |msg| { /* ... */ },
    .pong => { /* 心跳响应 */ },
    .unknown => |raw| { /* 未知消息 */ },
}
```

## 心跳机制

WebSocket 连接需要每 10 秒发送一次 PING 保持活跃：

```zig
// 高级 API 自动处理心跳
var channel = try ws.MarketChannel.init(allocator, .{
    .heartbeat_interval_ms = 10000,  // 默认 10 秒
});

// 低级 API 手动发送
try client.sendPing();
```

## 动态订阅

```zig
// 连接后动态订阅更多资产
try channel.subscribeMore(&.{ "new_token_id_1", "new_token_id_2" });

// 取消订阅
try channel.unsubscribe(&.{ "old_token_id" });
```

## 错误处理

```zig
fn onError(err: anyerror) void {
    std.debug.print("WebSocket error: {}\n", .{err});
}

var channel = try ws.MarketChannel.init(allocator, .{
    .on_error = onError,
    .auto_reconnect = true,
    .max_reconnect_attempts = 5,
});
```

## 文件结构

```
src/ws/
├── mod.zig      # 模块导出
├── types.zig    # 消息类型定义
├── client.zig   # 低级 WebSocket 客户端
├── parser.zig   # 消息解析器
├── market.zig   # Market Channel 包装器
└── user.zig     # User Channel 包装器
```

## 注意事项

1. **心跳**: 必须每 10 秒发送 PING，否则连接会被关闭
2. **重连**: 建议启用自动重连以处理网络问题
3. **内存**: 接收到的消息需要调用者释放
4. **安全**: User Channel 需要 API 凭证，不要泄露

## 参考资料

- [Polymarket WebSocket 文档](https://docs.polymarket.com/#websockets)
- [RFC 6455 - WebSocket 协议](https://tools.ietf.org/html/rfc6455)
