// Market Channel 高级包装器
//
// 提供简化的 API 来订阅 Polymarket 公开市场数据
//
// 用法:
// ```zig
// var channel = try MarketChannel.init(allocator, .{
//     .on_book = myBookHandler,
//     .on_price_change = myPriceHandler,
// });
// defer channel.deinit();
//
// try channel.subscribe(&.{ "token_id_1", "token_id_2" });
// try channel.run();
// ```

const std = @import("std");
const types = @import("types.zig");
const client = @import("client.zig");
const parser = @import("parser.zig");

const Allocator = std.mem.Allocator;

/// Market Channel 错误
pub const MarketChannelError = error{
    ConnectionFailed,
    SubscriptionFailed,
    NotConnected,
    SendFailed,
    AlreadyConnected,
    OutOfMemory,
};

/// Market Channel 状态
pub const ChannelState = enum {
    disconnected,
    connecting,
    connected,
    subscribed,
    error_state,
};

/// Market Channel 配置
pub const MarketChannelOptions = struct {
    /// 启用额外功能 (best_bid_ask, new_market, market_resolved)
    custom_feature_enabled: bool = false,

    /// 自动重连
    auto_reconnect: bool = true,

    /// 最大重连次数
    max_reconnect_attempts: u32 = 5,

    /// 重连延迟 (毫秒)
    reconnect_delay_ms: u64 = 1000,

    /// 心跳间隔 (毫秒)
    heartbeat_interval_ms: u64 = 10000,

    /// 回调函数
    on_book: ?*const fn (types.BookMessage) void = null,
    on_price_change: ?*const fn (types.PriceChangeMessage) void = null,
    on_last_trade_price: ?*const fn (types.LastTradePriceMessage) void = null,
    on_best_bid_ask: ?*const fn (types.BestBidAskMessage) void = null,
    on_tick_size_change: ?*const fn (types.TickSizeChangeMessage) void = null,
    on_error: ?*const fn (anyerror) void = null,
    on_connection: ?*const fn (bool) void = null,
    on_raw_message: ?*const fn ([]const u8) void = null,
};

/// Market Channel 包装器
pub const MarketChannel = struct {
    allocator: Allocator,
    options: MarketChannelOptions,
    state: ChannelState,
    ws_client: ?client.WebSocketClient,
    subscribed_assets: std.ArrayList([]const u8),
    msg_parser: parser.MessageParser,
    running: bool,

    const Self = @This();

    /// 初始化 Market Channel
    pub fn init(allocator: Allocator, options: MarketChannelOptions) !Self {
        return Self{
            .allocator = allocator,
            .options = options,
            .state = .disconnected,
            .ws_client = null,
            .subscribed_assets = .{},
            .msg_parser = parser.MessageParser.init(allocator),
            .running = false,
        };
    }

    /// 释放资源
    pub fn deinit(self: *Self) void {
        self.running = false;

        if (self.ws_client) |*ws| {
            ws.deinit();
            self.ws_client = null;
        }

        self.subscribed_assets.deinit(self.allocator);
        self.state = .disconnected;
    }

    /// 连接到 Market Channel
    pub fn connect(self: *Self) !void {
        if (self.state == .connected or self.state == .subscribed) {
            return MarketChannelError.AlreadyConnected;
        }

        self.state = .connecting;

        // 创建 WebSocket 客户端
        self.ws_client = try client.WebSocketClient.init(
            self.allocator,
            types.Endpoints.marketUrl(),
        );

        if (self.ws_client) |*ws| {
            ws.auto_reconnect = self.options.auto_reconnect;
            ws.max_reconnect_attempts = self.options.max_reconnect_attempts;
            ws.reconnect_delay_ms = self.options.reconnect_delay_ms;
            ws.heartbeat_interval_ms = self.options.heartbeat_interval_ms;

            try ws.connect();
        }

        self.state = .connected;

        if (self.options.on_connection) |callback| {
            callback(true);
        }
    }

    /// 订阅资产
    pub fn subscribe(self: *Self, asset_ids: []const []const u8) !void {
        if (self.state != .connected and self.state != .subscribed) {
            return MarketChannelError.NotConnected;
        }

        const ws = &(self.ws_client orelse return MarketChannelError.NotConnected);

        // 序列化订阅消息
        const msg = try client.serializeMarketSubscribe(
            self.allocator,
            asset_ids,
            self.options.custom_feature_enabled,
        );
        defer self.allocator.free(msg);

        // 发送订阅消息
        try ws.send(msg);

        // 记录已订阅的资产
        for (asset_ids) |id| {
            try self.subscribed_assets.append(self.allocator, id);
        }

        self.state = .subscribed;
    }

    /// 动态订阅更多资产
    pub fn subscribeMore(self: *Self, asset_ids: []const []const u8) !void {
        if (self.state != .subscribed) {
            return MarketChannelError.NotConnected;
        }

        const ws = &(self.ws_client orelse return MarketChannelError.NotConnected);

        const msg = try client.serializeDynamicSubscribe(
            self.allocator,
            .subscribe,
            asset_ids,
        );
        defer self.allocator.free(msg);

        try ws.send(msg);

        for (asset_ids) |id| {
            try self.subscribed_assets.append(self.allocator, id);
        }
    }

    /// 取消订阅资产
    pub fn unsubscribe(self: *Self, asset_ids: []const []const u8) !void {
        if (self.state != .subscribed) {
            return MarketChannelError.NotConnected;
        }

        const ws = &(self.ws_client orelse return MarketChannelError.NotConnected);

        const msg = try client.serializeDynamicSubscribe(
            self.allocator,
            .unsubscribe,
            asset_ids,
        );
        defer self.allocator.free(msg);

        try ws.send(msg);

        // 从已订阅列表中移除
        // （简化实现，实际应该进行精确匹配移除）
    }

    /// 发送 PING
    pub fn sendPing(self: *Self) !void {
        const ws = &(self.ws_client orelse return MarketChannelError.NotConnected);
        try ws.sendPing();
    }

    /// 接收并处理一条消息
    pub fn receiveOne(self: *Self) !bool {
        const ws = &(self.ws_client orelse return MarketChannelError.NotConnected);

        const raw_msg = try ws.receive() orelse return true;
        defer self.allocator.free(raw_msg);

        // 回调原始消息
        if (self.options.on_raw_message) |callback| {
            callback(raw_msg);
        }

        // 解析消息
        const result = self.msg_parser.parse(raw_msg) catch |err| {
            if (self.options.on_error) |callback| {
                callback(err);
            }
            return true;
        };

        // 分发到对应的回调
        switch (result) {
            .book => |msg| {
                if (self.options.on_book) |callback| callback(msg);
            },
            .price_change => |msg| {
                if (self.options.on_price_change) |callback| callback(msg);
            },
            .last_trade_price => |msg| {
                if (self.options.on_last_trade_price) |callback| callback(msg);
            },
            .best_bid_ask => |msg| {
                if (self.options.on_best_bid_ask) |callback| callback(msg);
            },
            .tick_size_change => |msg| {
                if (self.options.on_tick_size_change) |callback| callback(msg);
            },
            .pong => {
                // PONG 响应，不需要特殊处理
            },
            else => {
                // 忽略其他消息类型
            },
        }

        return true;
    }

    /// 运行消息循环（阻塞）
    pub fn run(self: *Self) !void {
        self.running = true;

        while (self.running) {
            _ = self.receiveOne() catch |err| {
                if (self.options.on_error) |callback| {
                    callback(err);
                }

                // 尝试重连
                if (self.options.auto_reconnect) {
                    if (self.ws_client) |*ws| {
                        ws.reconnect() catch {
                            self.running = false;
                            return;
                        };
                    }
                } else {
                    self.running = false;
                    return;
                }
            };
        }
    }

    /// 停止消息循环
    pub fn stop(self: *Self) void {
        self.running = false;
    }

    /// 断开连接
    pub fn disconnect(self: *Self) void {
        self.running = false;

        if (self.ws_client) |*ws| {
            ws.close() catch {};
        }

        self.state = .disconnected;

        if (self.options.on_connection) |callback| {
            callback(false);
        }
    }

    /// 获取当前状态
    pub fn getState(self: *const Self) ChannelState {
        return self.state;
    }

    /// 获取已订阅的资产列表
    pub fn getSubscribedAssets(self: *const Self) []const []const u8 {
        return self.subscribed_assets.items;
    }
};

// ============================================================================
// 测试
// ============================================================================

test "MarketChannel.init" {
    const allocator = std.testing.allocator;
    var channel = try MarketChannel.init(allocator, .{});
    defer channel.deinit();

    try std.testing.expectEqual(ChannelState.disconnected, channel.getState());
    try std.testing.expectEqual(@as(usize, 0), channel.getSubscribedAssets().len);
}

test "MarketChannelOptions defaults" {
    const options = MarketChannelOptions{};

    try std.testing.expect(!options.custom_feature_enabled);
    try std.testing.expect(options.auto_reconnect);
    try std.testing.expectEqual(@as(u32, 5), options.max_reconnect_attempts);
    try std.testing.expectEqual(@as(u64, 1000), options.reconnect_delay_ms);
    try std.testing.expectEqual(@as(u64, 10000), options.heartbeat_interval_ms);
    try std.testing.expect(options.on_book == null);
    try std.testing.expect(options.on_error == null);
}

test "ChannelState enum" {
    try std.testing.expectEqual(@as(u3, 0), @intFromEnum(ChannelState.disconnected));
    try std.testing.expectEqual(@as(u3, 1), @intFromEnum(ChannelState.connecting));
    try std.testing.expectEqual(@as(u3, 2), @intFromEnum(ChannelState.connected));
    try std.testing.expectEqual(@as(u3, 3), @intFromEnum(ChannelState.subscribed));
}
