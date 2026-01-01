//! L2 认证
//!
//! L2 认证使用 HMAC-SHA256 签名 API 请求，用于所有需要认证的端点：
//! - 订单管理（创建、取消、查询）
//! - 交易历史查询
//! - 账户余额查询
//! - 通知管理
//!
//! 示例:
//! ```zig
//! const l2 = L2Auth.init(&creds);
//!
//! // 生成 L2 Header
//! const header = try l2.generateHeader(.{
//!     .method = "POST",
//!     .path = "/order",
//!     .body = order_json,
//! });
//!
//! // 使用 header 调用 API
//! const http_headers = header.toHttpHeaders();
//! ```

const std = @import("std");
const root = @import("../root.zig");

const hmac = root.crypto.hmac;
const ApiCreds = @import("api_creds.zig").ApiCreds;
const L2PolyHeader = @import("headers.zig").L2PolyHeader;

/// L2 认证错误
pub const L2AuthError = error{
    /// 时间获取失败
    TimeError,
    /// 签名失败
    SigningFailed,
};

/// L2 认证请求选项
pub const L2AuthRequestOptions = struct {
    /// HTTP 方法（大写，如 "GET", "POST", "DELETE"）
    method: []const u8,
    /// 请求路径（如 "/order", "/data/orders"）
    path: []const u8,
    /// 请求体（可选，用于 POST/PUT 请求）
    body: ?[]const u8 = null,
};

/// L2 认证器
///
/// 使用 API 凭证和 HMAC-SHA256 签名生成 L2 认证 Header。
pub const L2Auth = struct {
    /// API 凭证引用
    creds: *const ApiCreds,

    const Self = @This();

    /// 初始化 L2 认证器
    pub fn init(creds: *const ApiCreds) Self {
        return Self{
            .creds = creds,
        };
    }

    /// 生成 L2 认证 Header
    ///
    /// 使用当前时间戳生成 Header。
    pub fn generateHeader(self: *const Self, options: L2AuthRequestOptions) L2AuthError!L2PolyHeader {
        const timestamp = std.time.timestamp();
        return self.generateHeaderWithTimestamp(options, timestamp);
    }

    /// 使用指定时间戳生成 L2 认证 Header（用于测试）
    pub fn generateHeaderWithTimestamp(
        self: *const Self,
        options: L2AuthRequestOptions,
        timestamp: i64,
    ) L2AuthError!L2PolyHeader {
        // 格式化时间戳
        var timestamp_buf: [20]u8 = undefined;
        const timestamp_str = std.fmt.bufPrint(&timestamp_buf, "{d}", .{timestamp}) catch unreachable;

        // 计算 HMAC 签名
        var sig_buf: [44]u8 = undefined;
        const signature = self.computeSignature(
            timestamp_str,
            options.method,
            options.path,
            options.body,
            &sig_buf,
        );

        // 构建 Header
        var header = L2PolyHeader{
            .poly_api_key = self.creds.getApiKey(),
            .poly_signature = undefined,
            .poly_timestamp = undefined,
            .poly_timestamp_len = timestamp_str.len,
            .poly_passphrase = self.creds.getApiPassphrase(),
        };

        @memcpy(&header.poly_signature, signature);
        @memcpy(header.poly_timestamp[0..timestamp_str.len], timestamp_str);

        return header;
    }

    /// 计算 HMAC-SHA256 签名
    ///
    /// 签名消息格式: timestamp + method + path + body
    ///
    /// 注意：Polymarket API 的 secret 是 Base64 编码的，需要先解码
    /// 签名输出使用 URL-safe Base64 编码
    fn computeSignature(
        self: *const Self,
        timestamp: []const u8,
        method: []const u8,
        path: []const u8,
        body: ?[]const u8,
        out: *[44]u8,
    ) []const u8 {
        // 1. 解码 API secret（它是 Base64 编码的）
        var secret_buffer: [hmac.BASE64_DECODED_MAX_LENGTH]u8 = undefined;
        const decoded_secret = hmac.decodeBase64Secret(self.creds.getApiSecret(), &secret_buffer) orelse {
            // 如果解码失败，使用原始字符串（向后兼容）
            var h = hmac.Hmac.init(self.creds.getApiSecret());
            h.update(timestamp);
            h.update(method);
            h.update(path);
            if (body) |b| {
                h.update(b);
            }
            const mac = h.final();
            return hmac.toBase64UrlSafe(&mac, out);
        };

        // 2. 使用解码后的 secret 计算 HMAC
        var h = hmac.Hmac.init(decoded_secret);
        h.update(timestamp);
        h.update(method);
        h.update(path);
        if (body) |b| {
            h.update(b);
        }
        const mac = h.final();

        // 3. 使用 URL-safe Base64 编码输出
        return hmac.toBase64UrlSafe(&mac, out);
    }

    /// 获取 API Key
    pub fn getApiKey(self: *const Self) []const u8 {
        return self.creds.getApiKey();
    }

    /// 获取 API Passphrase
    pub fn getApiPassphrase(self: *const Self) []const u8 {
        return self.creds.getApiPassphrase();
    }
};

/// 计算 L2 签名消息
///
/// 返回签名消息的组成部分，用于调试。
pub fn buildSignatureMessage(
    allocator: std.mem.Allocator,
    timestamp: []const u8,
    method: []const u8,
    path: []const u8,
    body: ?[]const u8,
) ![]u8 {
    const body_len = if (body) |b| b.len else 0;
    const total_len = timestamp.len + method.len + path.len + body_len;

    var result = try allocator.alloc(u8, total_len);
    var offset: usize = 0;

    @memcpy(result[offset .. offset + timestamp.len], timestamp);
    offset += timestamp.len;

    @memcpy(result[offset .. offset + method.len], method);
    offset += method.len;

    @memcpy(result[offset .. offset + path.len], path);
    offset += path.len;

    if (body) |b| {
        @memcpy(result[offset .. offset + b.len], b);
    }

    return result;
}

// ============================================================================
// 测试
// ============================================================================

test "L2Auth.init" {
    const allocator = std.testing.allocator;

    var creds = try ApiCreds.init(
        allocator,
        "test-api-key",
        "test-api-secret",
        "test-passphrase",
    );
    defer creds.deinit();

    const l2 = L2Auth.init(&creds);
    try std.testing.expectEqualStrings("test-api-key", l2.getApiKey());
    try std.testing.expectEqualStrings("test-passphrase", l2.getApiPassphrase());
}

test "L2Auth.generateHeaderWithTimestamp GET" {
    const allocator = std.testing.allocator;

    var creds = try ApiCreds.init(
        allocator,
        "my-api-key",
        "my-secret",
        "my-passphrase",
    );
    defer creds.deinit();

    const l2 = L2Auth.init(&creds);

    const header = try l2.generateHeaderWithTimestamp(.{
        .method = "GET",
        .path = "/data/orders",
        .body = null,
    }, 1704067200);

    // 验证基本字段
    try std.testing.expectEqualStrings("my-api-key", header.getApiKey());
    try std.testing.expectEqualStrings("1704067200", header.getTimestamp());
    try std.testing.expectEqualStrings("my-passphrase", header.getPassphrase());

    // 验证签名存在且是 Base64 格式
    const sig = header.getSignature();
    try std.testing.expectEqual(@as(usize, 44), sig.len);
}

test "L2Auth.generateHeaderWithTimestamp POST with body" {
    const allocator = std.testing.allocator;

    var creds = try ApiCreds.init(
        allocator,
        "api-key",
        "secret123",
        "pass456",
    );
    defer creds.deinit();

    const l2 = L2Auth.init(&creds);

    const body = "{\"tokenId\":\"123\",\"side\":\"BUY\"}";

    const header = try l2.generateHeaderWithTimestamp(.{
        .method = "POST",
        .path = "/order",
        .body = body,
    }, 1704067200);

    try std.testing.expectEqualStrings("1704067200", header.getTimestamp());
    try std.testing.expectEqual(@as(usize, 44), header.getSignature().len);
}

test "L2Auth signature determinism" {
    const allocator = std.testing.allocator;

    var creds = try ApiCreds.init(
        allocator,
        "key",
        "secret",
        "pass",
    );
    defer creds.deinit();

    const l2 = L2Auth.init(&creds);

    // 相同参数应产生相同签名
    const header1 = try l2.generateHeaderWithTimestamp(.{
        .method = "GET",
        .path = "/test",
        .body = null,
    }, 1704067200);

    const header2 = try l2.generateHeaderWithTimestamp(.{
        .method = "GET",
        .path = "/test",
        .body = null,
    }, 1704067200);

    try std.testing.expectEqualStrings(header1.getSignature(), header2.getSignature());
}

test "L2Auth signature differs with different params" {
    const allocator = std.testing.allocator;

    var creds = try ApiCreds.init(
        allocator,
        "key",
        "secret",
        "pass",
    );
    defer creds.deinit();

    const l2 = L2Auth.init(&creds);

    // 不同时间戳应产生不同签名
    const header1 = try l2.generateHeaderWithTimestamp(.{
        .method = "GET",
        .path = "/test",
        .body = null,
    }, 1704067200);

    const header2 = try l2.generateHeaderWithTimestamp(.{
        .method = "GET",
        .path = "/test",
        .body = null,
    }, 1704067201);

    try std.testing.expect(!std.mem.eql(u8, header1.getSignature(), header2.getSignature()));

    // 不同路径应产生不同签名
    const header3 = try l2.generateHeaderWithTimestamp(.{
        .method = "GET",
        .path = "/other",
        .body = null,
    }, 1704067200);

    try std.testing.expect(!std.mem.eql(u8, header1.getSignature(), header3.getSignature()));

    // 不同方法应产生不同签名
    const header4 = try l2.generateHeaderWithTimestamp(.{
        .method = "POST",
        .path = "/test",
        .body = null,
    }, 1704067200);

    try std.testing.expect(!std.mem.eql(u8, header1.getSignature(), header4.getSignature()));
}

test "L2Auth signature with body vs without" {
    const allocator = std.testing.allocator;

    var creds = try ApiCreds.init(
        allocator,
        "key",
        "secret",
        "pass",
    );
    defer creds.deinit();

    const l2 = L2Auth.init(&creds);

    const header1 = try l2.generateHeaderWithTimestamp(.{
        .method = "POST",
        .path = "/order",
        .body = null,
    }, 1704067200);

    const header2 = try l2.generateHeaderWithTimestamp(.{
        .method = "POST",
        .path = "/order",
        .body = "{}",
    }, 1704067200);

    // 有无 body 应产生不同签名
    try std.testing.expect(!std.mem.eql(u8, header1.getSignature(), header2.getSignature()));
}

test "L2Auth.toHttpHeaders" {
    const allocator = std.testing.allocator;

    var creds = try ApiCreds.init(
        allocator,
        "api-key",
        "secret",
        "passphrase",
    );
    defer creds.deinit();

    const l2 = L2Auth.init(&creds);

    const header = try l2.generateHeaderWithTimestamp(.{
        .method = "GET",
        .path = "/test",
        .body = null,
    }, 1704067200);

    const http_headers = header.toHttpHeaders();

    try std.testing.expectEqual(@as(usize, 4), http_headers.len);
    try std.testing.expectEqualStrings("POLY_API_KEY", http_headers[0].name);
    try std.testing.expectEqualStrings("POLY_SIGNATURE", http_headers[1].name);
    try std.testing.expectEqualStrings("POLY_TIMESTAMP", http_headers[2].name);
    try std.testing.expectEqualStrings("POLY_PASSPHRASE", http_headers[3].name);
}

test "buildSignatureMessage" {
    const allocator = std.testing.allocator;

    // 测试无 body
    {
        const msg = try buildSignatureMessage(allocator, "12345", "GET", "/test", null);
        defer allocator.free(msg);
        try std.testing.expectEqualStrings("12345GET/test", msg);
    }

    // 测试有 body
    {
        const msg = try buildSignatureMessage(allocator, "12345", "POST", "/order", "{\"a\":1}");
        defer allocator.free(msg);
        try std.testing.expectEqualStrings("12345POST/order{\"a\":1}", msg);
    }
}

test "L2Auth signature matches expected format" {
    const allocator = std.testing.allocator;

    var creds = try ApiCreds.init(
        allocator,
        "test-key",
        "test-secret",
        "test-pass",
    );
    defer creds.deinit();

    const l2 = L2Auth.init(&creds);

    const header = try l2.generateHeaderWithTimestamp(.{
        .method = "GET",
        .path = "/",
        .body = null,
    }, 1704067200);

    // 签名应该是 URL-safe Base64 格式
    const sig = header.getSignature();
    try std.testing.expectEqual(@as(usize, 44), sig.len);

    // 验证不包含标准 Base64 的特殊字符
    for (sig) |c| {
        // URL-safe base64 只包含: A-Z, a-z, 0-9, -, _, =
        try std.testing.expect(c == '-' or c == '_' or c == '=' or
            (c >= 'A' and c <= 'Z') or
            (c >= 'a' and c <= 'z') or
            (c >= '0' and c <= '9'));
    }
}

test "L2Auth signature matches Rust reference implementation" {
    // 这个测试用例来自 Rust 参考实现 (rs-clob-client/src/auth.rs)
    // 测试数据:
    //   secret: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" (全 0 的 32 字节)
    //   timestamp: 1
    //   method: GET
    //   path: /
    //   body: null
    //   expected signature: "eHaylCwqRSOa2LFD77Nt_SaTpbsxzN8eTEI3LryhEj4="
    const allocator = std.testing.allocator;

    var creds = try ApiCreds.init(
        allocator,
        "00000000-0000-0000-0000-000000000000", // Uuid::nil()
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=", // Base64 encoded 32 zeros
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    );
    defer creds.deinit();

    const l2 = L2Auth.init(&creds);

    const header = try l2.generateHeaderWithTimestamp(.{
        .method = "GET",
        .path = "/",
        .body = null,
    }, 1); // timestamp = 1

    // 这个预期值来自 Rust 测试: l2_headers_should_succeed
    try std.testing.expectEqualStrings("eHaylCwqRSOa2LFD77Nt_SaTpbsxzN8eTEI3LryhEj4=", header.getSignature());
}
