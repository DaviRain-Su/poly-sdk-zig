//! WebSocket 客户端
//!
//! 基于 Zig 标准库实现的 WebSocket 客户端
//! 支持 TLS (wss://) 和非安全 (ws://) 连接
//! 用于 Polymarket CLOB WebSocket API

const std = @import("std");
const types = @import("types.zig");
const tls = std.crypto.tls;
const Certificate = std.crypto.Certificate;
const net = std.net;
const Io = std.Io;

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

/// 读取帧结果
const ReadFrameResult = struct {
    opcode: Opcode,
    payload: ?[]const u8,
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
    TlsInitializationFailed,
    CertificateError,
    OutOfMemory,
};

/// TLS 缓冲区大小
const TLS_BUFFER_SIZE = tls.Client.min_buffer_len;

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
    tcp_stream: ?net.Stream,

    // TLS 相关
    tls_client: ?tls.Client,
    stream_reader: ?net.Stream.Reader,
    stream_writer: ?net.Stream.Writer,

    // 缓冲区（动态分配）
    tls_read_buffer: []u8,
    tls_write_buffer: []u8,
    socket_read_buffer: []u8,
    socket_write_buffer: []u8,

    // CA 证书
    ca_bundle: ?Certificate.Bundle,

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

    // 内部读取缓冲区
    read_buffer: [8192]u8,

    const Self = @This();

    /// 初始化 WebSocket 客户端
    pub fn init(allocator: Allocator, url: []const u8) !Self {
        // 解析 URL
        const parsed = try parseWebSocketUrl(url);

        // 分配缓冲区
        const tls_read_buffer = try allocator.alloc(u8, TLS_BUFFER_SIZE);
        errdefer allocator.free(tls_read_buffer);

        const tls_write_buffer = try allocator.alloc(u8, TLS_BUFFER_SIZE);
        errdefer allocator.free(tls_write_buffer);

        const socket_read_buffer = try allocator.alloc(u8, TLS_BUFFER_SIZE);
        errdefer allocator.free(socket_read_buffer);

        const socket_write_buffer = try allocator.alloc(u8, TLS_BUFFER_SIZE);
        errdefer allocator.free(socket_write_buffer);

        // 加载系统 CA 证书
        var ca_bundle: ?Certificate.Bundle = null;
        if (parsed.is_secure) {
            ca_bundle = Certificate.Bundle{};
            ca_bundle.?.rescan(allocator) catch {
                // 如果无法加载系统证书，使用无验证模式
                ca_bundle = null;
            };
        }

        return Self{
            .allocator = allocator,
            .state = .disconnected,
            .host = parsed.host,
            .port = parsed.port,
            .path = parsed.path,
            .is_secure = parsed.is_secure,
            .tcp_stream = null,
            .tls_client = null,
            .stream_reader = null,
            .stream_writer = null,
            .tls_read_buffer = tls_read_buffer,
            .tls_write_buffer = tls_write_buffer,
            .socket_read_buffer = socket_read_buffer,
            .socket_write_buffer = socket_write_buffer,
            .ca_bundle = ca_bundle,
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
            .read_buffer = undefined,
        };
    }

    /// 释放资源
    pub fn deinit(self: *Self) void {
        self.close() catch {};

        if (self.ca_bundle) |*bundle| {
            bundle.deinit(self.allocator);
        }

        self.allocator.free(self.tls_read_buffer);
        self.allocator.free(self.tls_write_buffer);
        self.allocator.free(self.socket_read_buffer);
        self.allocator.free(self.socket_write_buffer);
    }

    /// 连接到 WebSocket 服务器
    pub fn connect(self: *Self) !void {
        if (self.state == .connected) return;

        self.state = .connecting;

        // 解析主机名并建立 TCP 连接
        // 使用 tcpConnectToHost 支持域名解析
        self.tcp_stream = net.tcpConnectToHost(self.allocator, self.host, self.port) catch {
            // 如果域名解析失败，尝试作为 IP 地址解析
            const address = net.Address.resolveIp(self.host, self.port) catch {
                return WebSocketError.ConnectionFailed;
            };
            self.tcp_stream = net.tcpConnectToAddress(address) catch {
                return WebSocketError.ConnectionFailed;
            };
            if (self.tcp_stream == null) return WebSocketError.ConnectionFailed;
            return;
        };

        const stream = self.tcp_stream.?;

        // 创建流读写器
        self.stream_reader = stream.reader(self.socket_read_buffer);
        self.stream_writer = stream.writer(self.socket_write_buffer);

        // 如果是安全连接，初始化 TLS
        if (self.is_secure) {
            try self.initTls();
        }

        // 发送 WebSocket 握手
        try self.performHandshake();

        self.state = .connected;
        self.reconnect_attempts = 0;

        if (self.on_connection) |callback| {
            callback(true);
        }
    }

    /// 初始化 TLS 连接
    fn initTls(self: *Self) !void {
        var reader = &self.stream_reader.?;
        var writer = &self.stream_writer.?;

        // 初始化 TLS 客户端
        self.tls_client = tls.Client.init(
            reader.interface(),
            &writer.interface,
            .{
                .host = if (self.ca_bundle != null)
                    .{ .explicit = self.host }
                else
                    .no_verification,
                .ca = if (self.ca_bundle) |bundle|
                    .{ .bundle = bundle }
                else
                    .no_verification,
                .read_buffer = self.tls_read_buffer,
                .write_buffer = self.tls_write_buffer,
                .allow_truncation_attacks = true,
            },
        ) catch return WebSocketError.TlsInitializationFailed;
    }

    /// 关闭连接
    pub fn close(self: *Self) !void {
        if (self.state == .closed or self.state == .disconnected) return;

        self.state = .closing;

        // 发送关闭帧
        self.sendCloseFrame() catch {};

        // 清理 TLS
        self.tls_client = null;
        self.stream_reader = null;
        self.stream_writer = null;

        // 关闭 TCP
        if (self.tcp_stream) |stream| {
            stream.close();
            self.tcp_stream = null;
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

    /// 重连
    pub fn reconnect(self: *Self) !void {
        if (!self.auto_reconnect) return;

        if (self.reconnect_attempts >= self.max_reconnect_attempts) {
            return WebSocketError.MaxReconnectAttemptsExceeded;
        }

        self.reconnect_attempts += 1;

        // 关闭现有连接
        self.close() catch {};

        // 等待一段时间
        std.time.sleep(self.reconnect_delay_ms * std.time.ns_per_ms);

        // 重新连接
        try self.connect();
    }

    // ========================================================================
    // 内部方法
    // ========================================================================

    /// 写入数据（支持 TLS 和普通 TCP）
    fn writeData(self: *Self, data: []const u8) !void {
        if (self.is_secure) {
            if (self.tls_client) |*tls_client| {
                tls_client.writer.writeAll(data) catch return WebSocketError.SendFailed;
            } else {
                return WebSocketError.ConnectionFailed;
            }
        } else {
            if (self.stream_writer) |*writer| {
                writer.interface.writeAll(data) catch return WebSocketError.SendFailed;
            } else {
                return WebSocketError.ConnectionFailed;
            }
        }
    }

    /// 读取数据（支持 TLS 和普通 TCP）
    fn readData(self: *Self, buffer: []u8) !usize {
        if (self.is_secure) {
            if (self.tls_client) |*tls_client| {
                return tls_client.reader.readSliceShort(buffer) catch return WebSocketError.ReceiveFailed;
            } else {
                return WebSocketError.ConnectionFailed;
            }
        } else {
            if (self.stream_reader) |*reader| {
                return reader.interface().readSliceShort(buffer) catch return WebSocketError.ReceiveFailed;
            } else {
                return WebSocketError.ConnectionFailed;
            }
        }
    }

    /// 执行 WebSocket 握手
    fn performHandshake(self: *Self) !void {
        // 生成 WebSocket Key
        var key_bytes: [16]u8 = undefined;
        std.crypto.random.bytes(&key_bytes);

        // Base64 编码
        var ws_key_buf: [24]u8 = undefined;
        const ws_key = std.base64.standard.Encoder.encode(&ws_key_buf, &key_bytes);

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
        try self.writeData(request);

        // 读取响应
        var response_buf: [1024]u8 = undefined;
        const bytes_read = try self.readData(&response_buf);
        if (bytes_read == 0) return WebSocketError.HandshakeFailed;

        const response = response_buf[0..bytes_read];

        // 验证响应
        if (!std.mem.startsWith(u8, response, "HTTP/1.1 101")) {
            return WebSocketError.HandshakeFailed;
        }
    }

    /// 发送 WebSocket 帧
    fn sendFrame(self: *Self, opcode: Opcode, data: []const u8) !void {
        var frame_buf: [14 + 65535]u8 = undefined;
        var frame_len: usize = 0;

        // 第一个字节: FIN + opcode
        frame_buf[0] = 0x80 | @as(u8, @intFromEnum(opcode));
        frame_len += 1;

        // 第二个字节: MASK + payload length
        const payload_len = data.len;
        if (payload_len <= 125) {
            frame_buf[1] = 0x80 | @as(u8, @intCast(payload_len));
            frame_len += 1;
        } else if (payload_len <= 65535) {
            frame_buf[1] = 0x80 | 126;
            frame_buf[2] = @intCast((payload_len >> 8) & 0xFF);
            frame_buf[3] = @intCast(payload_len & 0xFF);
            frame_len += 3;
        } else {
            return WebSocketError.SendFailed; // 暂不支持超大帧
        }

        // 生成掩码
        var mask_key: [4]u8 = undefined;
        std.crypto.random.bytes(&mask_key);
        @memcpy(frame_buf[frame_len..][0..4], &mask_key);
        frame_len += 4;

        // 复制并掩码数据
        for (data, 0..) |byte, i| {
            frame_buf[frame_len + i] = byte ^ mask_key[i % 4];
        }
        frame_len += payload_len;

        // 发送帧
        try self.writeData(frame_buf[0..frame_len]);
    }

    /// 发送关闭帧
    fn sendCloseFrame(self: *Self) !void {
        try self.sendFrame(.close, "");
    }

    /// 读取 WebSocket 帧
    fn readFrame(self: *Self) !ReadFrameResult {
        // 读取前两个字节
        var header_buf: [2]u8 = undefined;
        var total_read: usize = 0;

        while (total_read < 2) {
            const n = try self.readData(header_buf[total_read..]);
            if (n == 0) return WebSocketError.ConnectionClosed;
            total_read += n;
        }

        const fin = (header_buf[0] & 0x80) != 0;
        _ = fin;
        const opcode: Opcode = @enumFromInt(@as(u4, @truncate(header_buf[0] & 0x0F)));
        const masked = (header_buf[1] & 0x80) != 0;
        var payload_len: u64 = header_buf[1] & 0x7F;

        // 读取扩展长度
        if (payload_len == 126) {
            var len_buf: [2]u8 = undefined;
            total_read = 0;
            while (total_read < 2) {
                const n = try self.readData(len_buf[total_read..]);
                if (n == 0) return WebSocketError.ConnectionClosed;
                total_read += n;
            }
            payload_len = (@as(u64, len_buf[0]) << 8) | @as(u64, len_buf[1]);
        } else if (payload_len == 127) {
            var len_buf: [8]u8 = undefined;
            total_read = 0;
            while (total_read < 8) {
                const n = try self.readData(len_buf[total_read..]);
                if (n == 0) return WebSocketError.ConnectionClosed;
                total_read += n;
            }
            payload_len = std.mem.readInt(u64, &len_buf, .big);
        }

        // 读取掩码（如果有）
        var mask_key: ?[4]u8 = null;
        if (masked) {
            var mask_buf: [4]u8 = undefined;
            total_read = 0;
            while (total_read < 4) {
                const n = try self.readData(mask_buf[total_read..]);
                if (n == 0) return WebSocketError.ConnectionClosed;
                total_read += n;
            }
            mask_key = mask_buf;
        }

        // 读取 payload
        if (payload_len == 0) {
            return ReadFrameResult{ .opcode = opcode, .payload = null };
        }

        if (payload_len > self.read_buffer.len) {
            return WebSocketError.InvalidFrame;
        }

        total_read = 0;
        while (total_read < payload_len) {
            const n = try self.readData(self.read_buffer[total_read..@intCast(payload_len)]);
            if (n == 0) return WebSocketError.ConnectionClosed;
            total_read += n;
        }

        // 解除掩码
        if (mask_key) |key| {
            for (self.read_buffer[0..@intCast(payload_len)], 0..) |*byte, i| {
                byte.* ^= key[i % 4];
            }
        }

        return ReadFrameResult{
            .opcode = opcode,
            .payload = self.allocator.dupe(u8, self.read_buffer[0..@intCast(payload_len)]) catch null,
        };
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
    var rest: []const u8 = undefined;

    if (std.mem.startsWith(u8, url, "wss://")) {
        is_secure = true;
        rest = url[6..];
    } else if (std.mem.startsWith(u8, url, "ws://")) {
        is_secure = false;
        rest = url[5..];
    } else {
        return WebSocketError.InvalidUrl;
    }

    // 分离 host:port 和 path
    var path: []const u8 = "/";
    var host_port = rest;

    if (std.mem.indexOf(u8, rest, "/")) |idx| {
        host_port = rest[0..idx];
        path = rest[idx..];
    }

    // 分离 host 和 port
    var host: []const u8 = host_port;
    var port: u16 = if (is_secure) 443 else 80;

    if (std.mem.lastIndexOf(u8, host_port, ":")) |idx| {
        host = host_port[0..idx];
        port = std.fmt.parseInt(u16, host_port[idx + 1 ..], 10) catch port;
    }

    return .{
        .host = host,
        .port = port,
        .path = path,
        .is_secure = is_secure,
    };
}

/// 序列化 Market 订阅消息
pub fn serializeMarketSubscribe(
    allocator: Allocator,
    asset_ids: []const []const u8,
    custom_feature_enabled: bool,
) ![]const u8 {
    var buffer = try std.ArrayList(u8).initCapacity(allocator, 256);
    defer buffer.deinit(allocator);

    try buffer.appendSlice(allocator, "{\"type\":\"subscribe\",\"assets_ids\":[");

    for (asset_ids, 0..) |id, i| {
        if (i > 0) try buffer.append(allocator, ',');
        try buffer.append(allocator, '"');
        try buffer.appendSlice(allocator, id);
        try buffer.append(allocator, '"');
    }

    try buffer.appendSlice(allocator, "],\"custom_feature_enabled\":");
    if (custom_feature_enabled) {
        try buffer.appendSlice(allocator, "true}");
    } else {
        try buffer.appendSlice(allocator, "false}");
    }

    return try buffer.toOwnedSlice(allocator);
}

/// 动态订阅类型
pub const DynamicSubscribeType = enum {
    subscribe,
    unsubscribe,
};

/// 序列化 User Channel 订阅消息
pub fn serializeUserSubscribe(
    allocator: Allocator,
    market_ids: []const []const u8,
    api_key: []const u8,
    api_secret: []const u8,
    api_passphrase: []const u8,
) ![]const u8 {
    var buffer = try std.ArrayList(u8).initCapacity(allocator, 512);
    defer buffer.deinit(allocator);

    try buffer.appendSlice(allocator, "{\"type\":\"subscribe\",\"markets\":[");

    for (market_ids, 0..) |id, i| {
        if (i > 0) try buffer.append(allocator, ',');
        try buffer.append(allocator, '"');
        try buffer.appendSlice(allocator, id);
        try buffer.append(allocator, '"');
    }

    try buffer.appendSlice(allocator, "],\"auth\":{\"apiKey\":\"");
    try buffer.appendSlice(allocator, api_key);
    try buffer.appendSlice(allocator, "\",\"secret\":\"");
    try buffer.appendSlice(allocator, api_secret);
    try buffer.appendSlice(allocator, "\",\"passphrase\":\"");
    try buffer.appendSlice(allocator, api_passphrase);
    try buffer.appendSlice(allocator, "\"}}");

    return try buffer.toOwnedSlice(allocator);
}

/// 序列化动态订阅消息
pub fn serializeDynamicSubscribe(
    allocator: Allocator,
    action: DynamicSubscribeType,
    asset_ids: []const []const u8,
) ![]const u8 {
    var buffer = try std.ArrayList(u8).initCapacity(allocator, 256);
    defer buffer.deinit(allocator);

    const type_str = switch (action) {
        .subscribe => "market_asset_subscribe",
        .unsubscribe => "market_asset_unsubscribe",
    };

    try buffer.appendSlice(allocator, "{\"type\":\"");
    try buffer.appendSlice(allocator, type_str);
    try buffer.appendSlice(allocator, "\",\"assets_ids\":[");

    for (asset_ids, 0..) |id, i| {
        if (i > 0) try buffer.append(allocator, ',');
        try buffer.append(allocator, '"');
        try buffer.appendSlice(allocator, id);
        try buffer.append(allocator, '"');
    }

    try buffer.appendSlice(allocator, "]}");

    return try buffer.toOwnedSlice(allocator);
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

test "parseWebSocketUrl - ws" {
    const result = try parseWebSocketUrl("ws://localhost:8080/ws");
    try std.testing.expectEqualStrings("localhost", result.host);
    try std.testing.expectEqual(@as(u16, 8080), result.port);
    try std.testing.expectEqualStrings("/ws", result.path);
    try std.testing.expect(!result.is_secure);
}

test "serializeMarketSubscribe" {
    const allocator = std.testing.allocator;
    const msg = try serializeMarketSubscribe(allocator, &.{ "token1", "token2" }, false);
    defer allocator.free(msg);

    try std.testing.expectEqualStrings(
        "{\"type\":\"subscribe\",\"assets_ids\":[\"token1\",\"token2\"],\"custom_feature_enabled\":false}",
        msg,
    );
}

test "serializeUserSubscribe" {
    const allocator = std.testing.allocator;
    const msg = try serializeUserSubscribe(allocator, &.{"market1"}, "key", "secret", "pass");
    defer allocator.free(msg);

    try std.testing.expectEqualStrings(
        "{\"type\":\"subscribe\",\"markets\":[\"market1\"],\"auth\":{\"apiKey\":\"key\",\"secret\":\"secret\",\"passphrase\":\"pass\"}}",
        msg,
    );
}
