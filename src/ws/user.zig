// User Channel 高级包装器
//
// 提供简化的 API 来订阅 Polymarket 用户私有数据
// 需要 API 凭证进行认证
//
// 用法:
// ```zig
// var channel = try UserChannel.init(allocator, .{
//     .api_key = "your-api-key",
//     .api_secret = "your-api-secret",
//     .api_passphrase = "your-passphrase",
//     .on_order = myOrderHandler,
//     .on_trade = myTradeHandler,
// });
// defer channel.deinit();
//
// try channel.subscribe(&.{ "condition_id_1" });
// try channel.run();
// ```

const std = @import("std");
const types = @import("types.zig");
const client = @import("client.zig");
const parser = @import("parser.zig");

const Allocator = std.mem.Allocator;

/// User Channel 错误
pub const UserChannelError = error{
    ConnectionFailed,
    AuthenticationFailed,
    SubscriptionFailed,
    NotConnected,
    SendFailed,
    AlreadyConnected,
    MissingCredentials,
    OutOfMemory,
};

/// User Channel 状态
pub const ChannelState = enum {
    disconnected,
    connecting,
    authenticating,
    authenticated,
    subscribed,
    error_state,
};

/// User Channel 配置
pub const UserChannelOptions = struct {
    /// API Key
    api_key: []const u8,

    /// API Secret
    api_secret: []const u8,

    /// API Passphrase
    api_passphrase: []const u8,

    /// 自动重连
    auto_reconnect: bool = true,

    /// 最大重连次数
    max_reconnect_attempts: u32 = 5,

    /// 重连延迟 (毫秒)
    reconnect_delay_ms: u64 = 1000,

    /// 心跳间隔 (毫秒)
    heartbeat_interval_ms: u64 = 10000,

    /// 回调函数
    on_order: ?*const fn (types.OrderMessage) void = null,
    on_trade: ?*const fn (types.TradeMessage) void = null,
    on_error: ?*const fn (anyerror) void = null,
    on_connection: ?*const fn (bool) void = null,
    on_raw_message: ?*const fn ([]const u8) void = null,
};

/// User Channel 包装器
pub const UserChannel = struct {
    allocator: Allocator,
    options: UserChannelOptions,
    state: ChannelState,
    ws_client: ?client.WebSocketClient,
    subscribed_markets: std.ArrayList([]const u8),
    msg_parser: parser.MessageParser,
    running: bool,

    const Self = @This();

    /// 初始化 User Channel
    pub fn init(allocator: Allocator, options: UserChannelOptions) !Self {
        // 验证凭证
        if (options.api_key.len == 0 or options.api_secret.len == 0 or options.api_passphrase.len == 0) {
            return UserChannelError.MissingCredentials;
        }

        return Self{
            .allocator = allocator,
            .options = options,
            .state = .disconnected,
            .ws_client = null,
            .subscribed_markets = .{},
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

        self.subscribed_markets.deinit(self.allocator);
        self.state = .disconnected;
    }

    /// 连接并订阅
    pub fn connect(self: *Self, markets: []const []const u8) !void {
        if (self.state == .authenticated or self.state == .subscribed) {
            return UserChannelError.AlreadyConnected;
        }

        self.state = .connecting;

        // 创建 WebSocket 客户端
        self.ws_client = try client.WebSocketClient.init(
            self.allocator,
            types.Endpoints.userUrl(),
        );

        if (self.ws_client) |*ws| {
            ws.auto_reconnect = self.options.auto_reconnect;
            ws.max_reconnect_attempts = self.options.max_reconnect_attempts;
            ws.reconnect_delay_ms = self.options.reconnect_delay_ms;
            ws.heartbeat_interval_ms = self.options.heartbeat_interval_ms;

            try ws.connect();
        }

        self.state = .authenticating;

        // 发送认证订阅消息
        try self.sendAuthSubscribe(markets);

        self.state = .subscribed;

        // 记录已订阅的市场
        for (markets) |market| {
            try self.subscribed_markets.append(self.allocator, market);
        }

        if (self.options.on_connection) |callback| {
            callback(true);
        }
    }

    /// 发送认证订阅消息
    fn sendAuthSubscribe(self: *Self, markets: []const []const u8) !void {
        const ws = &(self.ws_client orelse return UserChannelError.NotConnected);

        const msg = try client.serializeUserSubscribe(
            self.allocator,
            self.options.api_key,
            self.options.api_secret,
            self.options.api_passphrase,
            markets,
        );
        defer self.allocator.free(msg);

        try ws.send(msg);
    }

    /// 订阅更多市场
    pub fn subscribeMore(self: *Self, markets: []const []const u8) !void {
        if (self.state != .subscribed) {
            return UserChannelError.NotConnected;
        }

        const ws = &(self.ws_client orelse return UserChannelError.NotConnected);

        // User channel 使用完整的认证订阅消息
        // 需要包含所有已订阅的市场
        var all_markets = try std.ArrayList([]const u8).initCapacity(
            self.allocator,
            self.subscribed_markets.items.len + markets.len,
        );
        defer all_markets.deinit(self.allocator);

        // 添加已有的市场
        for (self.subscribed_markets.items) |m| {
            try all_markets.append(self.allocator, m);
        }

        // 添加新市场
        for (markets) |m| {
            try all_markets.append(self.allocator, m);
        }

        const msg = try client.serializeUserSubscribe(
            self.allocator,
            self.options.api_key,
            self.options.api_secret,
            self.options.api_passphrase,
            all_markets.items,
        );
        defer self.allocator.free(msg);

        try ws.send(msg);

        // 记录新订阅的市场
        for (markets) |m| {
            try self.subscribed_markets.append(self.allocator, m);
        }
    }

    /// 发送 PING
    pub fn sendPing(self: *Self) !void {
        const ws = &(self.ws_client orelse return UserChannelError.NotConnected);
        try ws.sendPing();
    }

    /// 接收并处理一条消息
    pub fn receiveOne(self: *Self) !bool {
        const ws = &(self.ws_client orelse return UserChannelError.NotConnected);

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
            .order => |msg| {
                if (self.options.on_order) |callback| callback(msg);
            },
            .trade => |msg| {
                if (self.options.on_trade) |callback| callback(msg);
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
                    self.reconnect() catch {
                        self.running = false;
                        return;
                    };
                } else {
                    self.running = false;
                    return;
                }
            };
        }
    }

    /// 重连
    fn reconnect(self: *Self) !void {
        if (self.ws_client) |*ws| {
            try ws.reconnect();

            // 重新发送认证订阅
            try self.sendAuthSubscribe(self.subscribed_markets.items);
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

    /// 获取已订阅的市场列表
    pub fn getSubscribedMarkets(self: *const Self) []const []const u8 {
        return self.subscribed_markets.items;
    }
};

// ============================================================================
// 测试
// ============================================================================

test "UserChannel.init with valid credentials" {
    const allocator = std.testing.allocator;
    var channel = try UserChannel.init(allocator, .{
        .api_key = "test-key",
        .api_secret = "test-secret",
        .api_passphrase = "test-pass",
    });
    defer channel.deinit();

    try std.testing.expectEqual(ChannelState.disconnected, channel.getState());
    try std.testing.expectEqual(@as(usize, 0), channel.getSubscribedMarkets().len);
}

test "UserChannel.init with missing credentials" {
    const allocator = std.testing.allocator;

    // 空 API key
    const result1 = UserChannel.init(allocator, .{
        .api_key = "",
        .api_secret = "secret",
        .api_passphrase = "pass",
    });
    try std.testing.expectError(UserChannelError.MissingCredentials, result1);

    // 空 secret
    const result2 = UserChannel.init(allocator, .{
        .api_key = "key",
        .api_secret = "",
        .api_passphrase = "pass",
    });
    try std.testing.expectError(UserChannelError.MissingCredentials, result2);

    // 空 passphrase
    const result3 = UserChannel.init(allocator, .{
        .api_key = "key",
        .api_secret = "secret",
        .api_passphrase = "",
    });
    try std.testing.expectError(UserChannelError.MissingCredentials, result3);
}

test "UserChannelOptions defaults" {
    const options = UserChannelOptions{
        .api_key = "key",
        .api_secret = "secret",
        .api_passphrase = "pass",
    };

    try std.testing.expect(options.auto_reconnect);
    try std.testing.expectEqual(@as(u32, 5), options.max_reconnect_attempts);
    try std.testing.expectEqual(@as(u64, 1000), options.reconnect_delay_ms);
    try std.testing.expectEqual(@as(u64, 10000), options.heartbeat_interval_ms);
    try std.testing.expect(options.on_order == null);
    try std.testing.expect(options.on_trade == null);
}

test "ChannelState enum" {
    try std.testing.expectEqual(@as(u3, 0), @intFromEnum(ChannelState.disconnected));
    try std.testing.expectEqual(@as(u3, 1), @intFromEnum(ChannelState.connecting));
    try std.testing.expectEqual(@as(u3, 2), @intFromEnum(ChannelState.authenticating));
    try std.testing.expectEqual(@as(u3, 3), @intFromEnum(ChannelState.authenticated));
    try std.testing.expectEqual(@as(u3, 4), @intFromEnum(ChannelState.subscribed));
}
