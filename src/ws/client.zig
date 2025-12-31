// WebSocket 客户端实现
//
// 基于 Zig 标准库实现的 WebSocket 客户端
// 支持 Polymarket CLOB WebSocket API
//
// 注意: Zig 0.15 标准库没有内置 WebSocket 支持，
// 这里使用 TCP + WebSocket 协议实现

const std = @import("std");
const types = @import("types.zig");

const Allocator = std.mem.Allocator;

/// WebSocket 操作码
const Opcode = enum(u4) {
    continuation = 0x0,
    text = 0x1,
    binary = 0x2,
    close = 0x8,
    ping = 0x9,
    pong = 0xA,
};

/// WebSocket 帧头
const FrameHeader = struct {
    fin: bool,
    opcode: Opcode,
    masked: bool,
    payload_len: u64,
    mask_key: ?[4]u8,
};

/// WebSocket 连接状态
pub const ConnectionState = enum {
    disconnected,
    connecting,
    connected,
    closing,
    closed,
};

/// WebSocket 错误
pub const WebSocketError = error{
    ConnectionFailed,
    HandshakeFailed,
    InvalidFrame,
    ConnectionClosed,
    SendFailed,
    ReceiveFailed,
    InvalidUrl,
    ProtocolError,
    Timeout,
    MaxReconnectAttemptsExceeded,
};

/// WebSocket 客户端
pub const WebSocketClient = struct {
    allocator: Allocator,
    state: ConnectionState,

    // 连接信息
    host: []const u8,
    port: u16,
    path: []const u8,
    is_secure: bool,

    // 底层流
    stream: ?std.net.Stream,

    // 配置
    auto_reconnect: bool,
    max_reconnect_attempts: u32,
    reconnect_delay_ms: u64,
    heartbeat_interval_ms: u64,

    // 统计
    reconnect_attempts: u32,
    last_ping_time: i64,
    last_pong_time: i64,

    // 回调
    on_message: ?*const fn (data: []const u8) void,
    on_error: ?*const fn (err: anyerror) void,
    on_connection: ?*const fn (connected: bool) void,

    const Self = @This();

    /// 初始化 WebSocket 客户端
    pub fn init(allocator: Allocator, url: []const u8) !Self {
        // 解析 URL
        const parsed = try parseWebSocketUrl(url);

        return Self{
            .allocator = allocator,
            .state = .disconnected,
            .host = parsed.host,
            .port = parsed.port,
            .path = parsed.path,
            .is_secure = parsed.is_secure,
            .stream = null,
            .auto_reconnect = true,
            .max_reconnect_attempts = 5,
            .reconnect_delay_ms = 1000,
            .heartbeat_interval_ms = 10000,
            .reconnect_attempts = 0,
            .last_ping_time = 0,
            .last_pong_time = 0,
            .on_message = null,
            .on_error = null,
            .on_connection = null,
        };
    }

    /// 释放资源
    pub fn deinit(self: *Self) void {
        self.close() catch {};
    }

    /// 连接到 WebSocket 服务器
    pub fn connect(self: *Self) !void {
        if (self.state == .connected) return;

        self.state = .connecting;

        // 建立 TCP 连接
        const address = try std.net.Address.resolveIp(self.host, self.port);
        self.stream = try std.net.tcpConnectToAddress(address);

        // 发送 WebSocket 握手
        try self.performHandshake();

        self.state = .connected;
        self.reconnect_attempts = 0;

        if (self.on_connection) |callback| {
            callback(true);
        }
    }

    /// 关闭连接
    pub fn close(self: *Self) !void {
        if (self.state == .closed or self.state == .disconnected) return;

        self.state = .closing;

        // 发送关闭帧
        if (self.stream) |stream| {
            self.sendCloseFrame() catch {};
            stream.close();
            self.stream = null;
        }

        self.state = .closed;

        if (self.on_connection) |callback| {
            callback(false);
        }
    }

    /// 发送文本消息
    pub fn send(self: *Self, data: []const u8) !void {
        if (self.state != .connected) return WebSocketError.ConnectionClosed;

        try self.sendFrame(.text, data);
    }

    /// 发送 PING
    pub fn sendPing(self: *Self) !void {
        if (self.state != .connected) return WebSocketError.ConnectionClosed;

        try self.sendFrame(.ping, "PING");
        self.last_ping_time = std.time.milliTimestamp();
    }

    /// 接收消息（阻塞）
    pub fn receive(self: *Self) !?[]const u8 {
        if (self.state != .connected) return WebSocketError.ConnectionClosed;

        const frame = try self.readFrame();

        switch (frame.opcode) {
            .text, .binary => {
                return frame.payload;
            },
            .ping => {
                // 自动响应 PONG
                try self.sendFrame(.pong, frame.payload orelse "");
                return null;
            },
            .pong => {
                self.last_pong_time = std.time.milliTimestamp();
                return null;
            },
            .close => {
                self.state = .closed;
                return WebSocketError.ConnectionClosed;
            },
            else => return null,
        }
    }

    // ========================================================================
    // 内部方法
    // ========================================================================

    /// 执行 WebSocket 握手
    fn performHandshake(self: *Self) !void {
        const stream = self.stream orelse return WebSocketError.ConnectionFailed;

        // 生成 WebSocket Key
        var key_bytes: [16]u8 = undefined;
        std.crypto.random.bytes(&key_bytes);
        const ws_key = std.base64.standard.Encoder.encode(&key_bytes);

        // 构建握手请求
        var request_buf: [1024]u8 = undefined;
        const request = try std.fmt.bufPrint(&request_buf,
            \\GET {s} HTTP/1.1
            \\Host: {s}
            \\Upgrade: websocket
            \\Connection: Upgrade
            \\Sec-WebSocket-Key: {s}
            \\Sec-WebSocket-Version: 13
            \\
            \\
        , .{ self.path, self.host, ws_key });

        // 发送请求
        _ = try stream.write(request);

        // 读取响应
        var response_buf: [1024]u8 = undefined;
        const bytes_read = try stream.read(&response_buf);
        if (bytes_read == 0) return WebSocketError.HandshakeFailed;

        const response = response_buf[0..bytes_read];

        // 验证响应
        if (!std.mem.startsWith(u8, response, "HTTP/1.1 101")) {
            return WebSocketError.HandshakeFailed;
        }
    }

    /// 发送 WebSocket 帧
    fn sendFrame(self: *Self, opcode: Opcode, data: []const u8) !void {
        const stream = self.stream orelse return WebSocketError.ConnectionFailed;

        // 生成掩码
        var mask_key: [4]u8 = undefined;
        std.crypto.random.bytes(&mask_key);

        // 构建帧头
        var header_buf: [14]u8 = undefined;
        var header_len: usize = 2;

        // 第一个字节: FIN + opcode
        header_buf[0] = 0x80 | @as(u8, @intFromEnum(opcode));

        // 第二个字节: MASK + payload length
        if (data.len < 126) {
            header_buf[1] = 0x80 | @as(u8, @intCast(data.len));
        } else if (data.len < 65536) {
            header_buf[1] = 0x80 | 126;
            header_buf[2] = @intCast((data.len >> 8) & 0xFF);
            header_buf[3] = @intCast(data.len & 0xFF);
            header_len = 4;
        } else {
            header_buf[1] = 0x80 | 127;
            const len64: u64 = data.len;
            header_buf[2] = @intCast((len64 >> 56) & 0xFF);
            header_buf[3] = @intCast((len64 >> 48) & 0xFF);
            header_buf[4] = @intCast((len64 >> 40) & 0xFF);
            header_buf[5] = @intCast((len64 >> 32) & 0xFF);
            header_buf[6] = @intCast((len64 >> 24) & 0xFF);
            header_buf[7] = @intCast((len64 >> 16) & 0xFF);
            header_buf[8] = @intCast((len64 >> 8) & 0xFF);
            header_buf[9] = @intCast(len64 & 0xFF);
            header_len = 10;
        }

        // 添加掩码
        @memcpy(header_buf[header_len..][0..4], &mask_key);
        header_len += 4;

        // 发送帧头
        _ = try stream.write(header_buf[0..header_len]);

        // 发送掩码后的数据
        var masked_data = try self.allocator.alloc(u8, data.len);
        defer self.allocator.free(masked_data);

        for (data, 0..) |byte, i| {
            masked_data[i] = byte ^ mask_key[i % 4];
        }

        _ = try stream.write(masked_data);
    }

    /// 发送关闭帧
    fn sendCloseFrame(self: *Self) !void {
        try self.sendFrame(.close, "");
    }

    /// 读取 WebSocket 帧
    fn readFrame(self: *Self) !struct { opcode: Opcode, payload: ?[]const u8 } {
        const stream = self.stream orelse return WebSocketError.ConnectionFailed;

        // 读取前两个字节
        var header: [2]u8 = undefined;
        const header_read = try stream.read(&header);
        if (header_read < 2) return WebSocketError.InvalidFrame;

        const fin = (header[0] & 0x80) != 0;
        _ = fin;
        const opcode: Opcode = @enumFromInt(header[0] & 0x0F);
        const masked = (header[1] & 0x80) != 0;
        var payload_len: u64 = header[1] & 0x7F;

        // 读取扩展长度
        if (payload_len == 126) {
            var ext_len: [2]u8 = undefined;
            _ = try stream.read(&ext_len);
            payload_len = (@as(u64, ext_len[0]) << 8) | ext_len[1];
        } else if (payload_len == 127) {
            var ext_len: [8]u8 = undefined;
            _ = try stream.read(&ext_len);
            payload_len = 0;
            for (ext_len) |b| {
                payload_len = (payload_len << 8) | b;
            }
        }

        // 读取掩码
        var mask_key: [4]u8 = undefined;
        if (masked) {
            _ = try stream.read(&mask_key);
        }

        // 读取载荷
        if (payload_len == 0) {
            return .{ .opcode = opcode, .payload = null };
        }

        const payload = try self.allocator.alloc(u8, @intCast(payload_len));
        _ = try stream.read(payload);

        // 解除掩码
        if (masked) {
            for (payload, 0..) |*byte, i| {
                byte.* ^= mask_key[i % 4];
            }
        }

        return .{ .opcode = opcode, .payload = payload };
    }

    /// 重连
    pub fn reconnect(self: *Self) !void {
        if (!self.auto_reconnect) return WebSocketError.ConnectionClosed;

        while (self.reconnect_attempts < self.max_reconnect_attempts) {
            self.reconnect_attempts += 1;

            std.time.sleep(self.reconnect_delay_ms * std.time.ns_per_ms);

            self.connect() catch continue;
            return;
        }

        return WebSocketError.MaxReconnectAttemptsExceeded;
    }
};

/// 解析 WebSocket URL
fn parseWebSocketUrl(url: []const u8) !struct {
    host: []const u8,
    port: u16,
    path: []const u8,
    is_secure: bool,
} {
    var is_secure = false;
    var rest = url;

    // 检查协议
    if (std.mem.startsWith(u8, url, "wss://")) {
        is_secure = true;
        rest = url[6..];
    } else if (std.mem.startsWith(u8, url, "ws://")) {
        rest = url[5..];
    } else {
        return WebSocketError.InvalidUrl;
    }

    // 查找路径分隔符
    const path_start = std.mem.indexOf(u8, rest, "/") orelse rest.len;
    const host_port = rest[0..path_start];
    const path = if (path_start < rest.len) rest[path_start..] else "/";

    // 解析主机和端口
    var host: []const u8 = undefined;
    var port: u16 = undefined;

    if (std.mem.indexOf(u8, host_port, ":")) |colon_pos| {
        host = host_port[0..colon_pos];
        port = std.fmt.parseInt(u16, host_port[colon_pos + 1 ..], 10) catch {
            return WebSocketError.InvalidUrl;
        };
    } else {
        host = host_port;
        port = if (is_secure) 443 else 80;
    }

    return .{
        .host = host,
        .port = port,
        .path = path,
        .is_secure = is_secure,
    };
}

// ============================================================================
// JSON 序列化辅助
// ============================================================================

/// 序列化 Market Channel 订阅消息
pub fn serializeMarketSubscribe(
    allocator: Allocator,
    assets_ids: []const []const u8,
    custom_feature_enabled: bool,
) ![]u8 {
    var list = try std.ArrayList(u8).initCapacity(allocator, 256);
    errdefer list.deinit(allocator);

    try list.appendSlice(allocator, "{\"assets_ids\":[");

    for (assets_ids, 0..) |id, i| {
        if (i > 0) try list.append(allocator, ',');
        try list.append(allocator, '"');
        try list.appendSlice(allocator, id);
        try list.append(allocator, '"');
    }

    try list.appendSlice(allocator, "],\"type\":\"market\"");

    if (custom_feature_enabled) {
        try list.appendSlice(allocator, ",\"custom_feature_enabled\":true");
    }

    try list.append(allocator, '}');

    return try list.toOwnedSlice(allocator);
}

/// 序列化 User Channel 订阅消息
pub fn serializeUserSubscribe(
    allocator: Allocator,
    api_key: []const u8,
    api_secret: []const u8,
    api_passphrase: []const u8,
    markets: []const []const u8,
) ![]u8 {
    var list = try std.ArrayList(u8).initCapacity(allocator, 512);
    errdefer list.deinit(allocator);

    try list.appendSlice(allocator, "{\"auth\":{\"apiKey\":\"");
    try list.appendSlice(allocator, api_key);
    try list.appendSlice(allocator, "\",\"secret\":\"");
    try list.appendSlice(allocator, api_secret);
    try list.appendSlice(allocator, "\",\"passphrase\":\"");
    try list.appendSlice(allocator, api_passphrase);
    try list.appendSlice(allocator, "\"},\"markets\":[");

    for (markets, 0..) |market, i| {
        if (i > 0) try list.append(allocator, ',');
        try list.append(allocator, '"');
        try list.appendSlice(allocator, market);
        try list.append(allocator, '"');
    }

    try list.appendSlice(allocator, "],\"type\":\"user\"}");

    return try list.toOwnedSlice(allocator);
}

/// 序列化动态订阅消息
pub fn serializeDynamicSubscribe(
    allocator: Allocator,
    operation: types.SubscriptionOperation,
    assets_ids: ?[]const []const u8,
) ![]u8 {
    var list = try std.ArrayList(u8).initCapacity(allocator, 256);
    errdefer list.deinit(allocator);

    try list.append(allocator, '{');

    if (assets_ids) |ids| {
        try list.appendSlice(allocator, "\"assets_ids\":[");
        for (ids, 0..) |id, i| {
            if (i > 0) try list.append(allocator, ',');
            try list.append(allocator, '"');
            try list.appendSlice(allocator, id);
            try list.append(allocator, '"');
        }
        try list.appendSlice(allocator, "],");
    }

    try list.appendSlice(allocator, "\"operation\":\"");
    try list.appendSlice(allocator, operation.toString());
    try list.appendSlice(allocator, "\"}");

    return try list.toOwnedSlice(allocator);
}

// ============================================================================
// 测试
// ============================================================================

test "parseWebSocketUrl - wss" {
    const result = try parseWebSocketUrl("wss://ws-subscriptions-clob.polymarket.com/ws/market");
    try std.testing.expectEqualStrings("ws-subscriptions-clob.polymarket.com", result.host);
    try std.testing.expectEqual(@as(u16, 443), result.port);
    try std.testing.expectEqualStrings("/ws/market", result.path);
    try std.testing.expect(result.is_secure);
}

test "parseWebSocketUrl - ws with port" {
    const result = try parseWebSocketUrl("ws://localhost:8080/test");
    try std.testing.expectEqualStrings("localhost", result.host);
    try std.testing.expectEqual(@as(u16, 8080), result.port);
    try std.testing.expectEqualStrings("/test", result.path);
    try std.testing.expect(!result.is_secure);
}

test "parseWebSocketUrl - invalid" {
    const result = parseWebSocketUrl("http://example.com");
    try std.testing.expectError(WebSocketError.InvalidUrl, result);
}

test "serializeMarketSubscribe" {
    const allocator = std.testing.allocator;
    const assets = &[_][]const u8{ "asset1", "asset2" };
    const json = try serializeMarketSubscribe(allocator, assets, true);
    defer allocator.free(json);

    try std.testing.expectEqualStrings(
        "{\"assets_ids\":[\"asset1\",\"asset2\"],\"type\":\"market\",\"custom_feature_enabled\":true}",
        json,
    );
}

test "serializeMarketSubscribe - no custom feature" {
    const allocator = std.testing.allocator;
    const assets = &[_][]const u8{"asset1"};
    const json = try serializeMarketSubscribe(allocator, assets, false);
    defer allocator.free(json);

    try std.testing.expectEqualStrings(
        "{\"assets_ids\":[\"asset1\"],\"type\":\"market\"}",
        json,
    );
}

test "serializeUserSubscribe" {
    const allocator = std.testing.allocator;
    const markets = &[_][]const u8{"0xabc123"};
    const json = try serializeUserSubscribe(allocator, "key", "secret", "pass", markets);
    defer allocator.free(json);

    try std.testing.expectEqualStrings(
        "{\"auth\":{\"apiKey\":\"key\",\"secret\":\"secret\",\"passphrase\":\"pass\"},\"markets\":[\"0xabc123\"],\"type\":\"user\"}",
        json,
    );
}

test "serializeDynamicSubscribe" {
    const allocator = std.testing.allocator;
    const assets = &[_][]const u8{"asset1"};
    const json = try serializeDynamicSubscribe(allocator, .subscribe, assets);
    defer allocator.free(json);

    try std.testing.expectEqualStrings(
        "{\"assets_ids\":[\"asset1\"],\"operation\":\"subscribe\"}",
        json,
    );
}

test "WebSocketClient.init" {
    const allocator = std.testing.allocator;
    var client = try WebSocketClient.init(allocator, "wss://example.com/ws");
    defer client.deinit();

    try std.testing.expectEqualStrings("example.com", client.host);
    try std.testing.expectEqual(@as(u16, 443), client.port);
    try std.testing.expectEqualStrings("/ws", client.path);
    try std.testing.expect(client.is_secure);
    try std.testing.expectEqual(ConnectionState.disconnected, client.state);
}
