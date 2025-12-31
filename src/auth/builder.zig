//! Builder 认证模块
//!
//! Builder 是 Polymarket 的做市商程序，具有独立的认证流程。
//! Builder 认证使用与 L2 类似的 HMAC-SHA256 签名机制，但使用独立的凭证。
//!
//! ## 使用示例
//!
//! ```zig
//! const auth = @import("auth");
//!
//! // 创建 Builder 凭证
//! var builder_creds = try auth.BuilderCreds.init(
//!     allocator,
//!     "builder-api-key",
//!     "builder-api-secret",
//!     "builder-passphrase",
//! );
//! defer builder_creds.deinit();
//!
//! // 创建 Builder 认证器
//! const builder_auth = auth.BuilderAuth.init(&builder_creds);
//!
//! // 生成 Builder Header
//! const header = try builder_auth.generateHeader(.{
//!     .method = "GET",
//!     .path = "/builder/trades",
//!     .body = null,
//! });
//!
//! // 获取 HTTP Headers
//! const http_headers = header.toHttpHeaders();
//! ```
//!
//! ## Builder Header 格式
//!
//! Builder 请求需要以下 HTTP Headers：
//! - `POLY-BUILDER-API-KEY`: Builder API Key
//! - `POLY-BUILDER-TIMESTAMP`: Unix 时间戳（秒）
//! - `POLY-BUILDER-PASSPHRASE`: Builder Passphrase
//! - `POLY-BUILDER-SIGNATURE`: HMAC-SHA256 签名（Base64 编码）

const std = @import("std");
const root = @import("../root.zig");

const hmac = root.crypto.hmac;
const Secret = root.types.Secret;

/// Builder 认证错误
pub const BuilderAuthError = error{
    /// 时间获取失败
    TimeError,
    /// 签名失败
    SigningFailed,
    /// 无效的凭证
    InvalidCredentials,
};

/// Builder API 凭证
///
/// 存储 Builder 的 API 认证信息。
/// 敏感字段使用 Secret 类型包装，防止意外泄露。
pub const BuilderCreds = struct {
    allocator: std.mem.Allocator,

    /// Builder API Key
    api_key: []const u8,

    /// Builder API Secret（用于签名）
    api_secret: Secret([]const u8),

    /// Builder Passphrase
    passphrase: Secret([]const u8),

    const Self = @This();

    /// 初始化 Builder 凭证
    pub fn init(
        allocator: std.mem.Allocator,
        api_key: []const u8,
        api_secret: []const u8,
        passphrase: []const u8,
    ) !Self {
        // 复制字符串以确保所有权
        const key_copy = try allocator.dupe(u8, api_key);
        errdefer allocator.free(key_copy);

        const secret_copy = try allocator.dupe(u8, api_secret);
        errdefer allocator.free(secret_copy);

        const pass_copy = try allocator.dupe(u8, passphrase);
        errdefer allocator.free(pass_copy);

        return Self{
            .allocator = allocator,
            .api_key = key_copy,
            .api_secret = Secret([]const u8).init(secret_copy),
            .passphrase = Secret([]const u8).init(pass_copy),
        };
    }

    /// 释放资源
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.api_key);
        self.allocator.free(self.api_secret.reveal());
        self.allocator.free(self.passphrase.reveal());
    }

    /// 获取 API Key
    pub fn getApiKey(self: *const Self) []const u8 {
        return self.api_key;
    }

    /// 获取 API Secret
    pub fn getApiSecret(self: *const Self) []const u8 {
        return self.api_secret.reveal();
    }

    /// 获取 Passphrase
    pub fn getPassphrase(self: *const Self) []const u8 {
        return self.passphrase.reveal();
    }

    /// 验证凭证是否有效
    pub fn isValid(self: *const Self) bool {
        return self.api_key.len > 0 and
            self.api_secret.reveal().len > 0 and
            self.passphrase.reveal().len > 0;
    }
};

/// Builder 认证 Header
///
/// 用于 Builder 认证的 HTTP Header。
pub const BuilderPolyHeader = struct {
    /// Builder API Key
    poly_builder_api_key: []const u8,

    /// HMAC-SHA256 签名（Base64 编码，44 字符）
    poly_builder_signature: [44]u8,

    /// Unix 时间戳（秒）
    poly_builder_timestamp: [20]u8,
    poly_builder_timestamp_len: usize,

    /// Builder Passphrase
    poly_builder_passphrase: []const u8,

    const Self = @This();

    /// Header 名称常量
    pub const HEADER_API_KEY = "POLY-BUILDER-API-KEY";
    pub const HEADER_SIGNATURE = "POLY-BUILDER-SIGNATURE";
    pub const HEADER_TIMESTAMP = "POLY-BUILDER-TIMESTAMP";
    pub const HEADER_PASSPHRASE = "POLY-BUILDER-PASSPHRASE";

    /// 获取 API Key
    pub fn getApiKey(self: *const Self) []const u8 {
        return self.poly_builder_api_key;
    }

    /// 获取签名
    pub fn getSignature(self: *const Self) []const u8 {
        return &self.poly_builder_signature;
    }

    /// 获取时间戳
    pub fn getTimestamp(self: *const Self) []const u8 {
        return self.poly_builder_timestamp[0..self.poly_builder_timestamp_len];
    }

    /// 获取 Passphrase
    pub fn getPassphrase(self: *const Self) []const u8 {
        return self.poly_builder_passphrase;
    }

    /// 转换为 HTTP Header 数组
    pub fn toHttpHeaders(self: *const Self) [4]std.http.Header {
        return [4]std.http.Header{
            .{ .name = HEADER_API_KEY, .value = self.getApiKey() },
            .{ .name = HEADER_SIGNATURE, .value = self.getSignature() },
            .{ .name = HEADER_TIMESTAMP, .value = self.getTimestamp() },
            .{ .name = HEADER_PASSPHRASE, .value = self.getPassphrase() },
        };
    }
};

/// Builder 认证请求选项
pub const BuilderAuthRequestOptions = struct {
    /// HTTP 方法（大写，如 "GET", "POST", "DELETE"）
    method: []const u8,
    /// 请求路径（如 "/builder/trades"）
    path: []const u8,
    /// 请求体（可选，用于 POST/PUT 请求）
    body: ?[]const u8 = null,
};

/// Builder 认证器
///
/// 使用 Builder 凭证和 HMAC-SHA256 签名生成认证 Header。
pub const BuilderAuth = struct {
    /// Builder 凭证引用
    creds: *const BuilderCreds,

    const Self = @This();

    /// 初始化 Builder 认证器
    pub fn init(creds: *const BuilderCreds) Self {
        return Self{
            .creds = creds,
        };
    }

    /// 生成 Builder 认证 Header
    ///
    /// 使用当前时间戳生成 Header。
    pub fn generateHeader(self: *const Self, options: BuilderAuthRequestOptions) BuilderAuthError!BuilderPolyHeader {
        const timestamp = std.time.timestamp();
        return self.generateHeaderWithTimestamp(options, timestamp);
    }

    /// 使用指定时间戳生成 Builder 认证 Header（用于测试）
    pub fn generateHeaderWithTimestamp(
        self: *const Self,
        options: BuilderAuthRequestOptions,
        timestamp: i64,
    ) BuilderAuthError!BuilderPolyHeader {
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
        var header = BuilderPolyHeader{
            .poly_builder_api_key = self.creds.getApiKey(),
            .poly_builder_signature = undefined,
            .poly_builder_timestamp = undefined,
            .poly_builder_timestamp_len = timestamp_str.len,
            .poly_builder_passphrase = self.creds.getPassphrase(),
        };

        @memcpy(&header.poly_builder_signature, signature);
        @memcpy(header.poly_builder_timestamp[0..timestamp_str.len], timestamp_str);

        return header;
    }

    /// 计算 HMAC-SHA256 签名
    ///
    /// 签名消息格式: timestamp + method + path + body
    fn computeSignature(
        self: *const Self,
        timestamp: []const u8,
        method: []const u8,
        path: []const u8,
        body: ?[]const u8,
        out: *[44]u8,
    ) []const u8 {
        // 使用增量 HMAC 计算
        var h = hmac.Hmac.init(self.creds.getApiSecret());
        h.update(timestamp);
        h.update(method);
        h.update(path);
        if (body) |b| {
            h.update(b);
        }
        const mac = h.final();

        // Base64 编码
        return hmac.toBase64(&mac, out);
    }

    /// 获取 API Key
    pub fn getApiKey(self: *const Self) []const u8 {
        return self.creds.getApiKey();
    }

    /// 获取 Passphrase
    pub fn getPassphrase(self: *const Self) []const u8 {
        return self.creds.getPassphrase();
    }
};

// ============================================================================
// 测试
// ============================================================================

test "BuilderCreds.init and deinit" {
    const allocator = std.testing.allocator;

    var creds = try BuilderCreds.init(
        allocator,
        "builder-key",
        "builder-secret",
        "builder-pass",
    );
    defer creds.deinit();

    try std.testing.expectEqualStrings("builder-key", creds.getApiKey());
    try std.testing.expectEqualStrings("builder-secret", creds.getApiSecret());
    try std.testing.expectEqualStrings("builder-pass", creds.getPassphrase());
}

test "BuilderCreds.isValid" {
    const allocator = std.testing.allocator;

    var valid_creds = try BuilderCreds.init(
        allocator,
        "key",
        "secret",
        "pass",
    );
    defer valid_creds.deinit();

    try std.testing.expect(valid_creds.isValid());
}

test "BuilderAuth.init" {
    const allocator = std.testing.allocator;

    var creds = try BuilderCreds.init(
        allocator,
        "builder-api-key",
        "builder-api-secret",
        "builder-passphrase",
    );
    defer creds.deinit();

    const auth = BuilderAuth.init(&creds);
    try std.testing.expectEqualStrings("builder-api-key", auth.getApiKey());
    try std.testing.expectEqualStrings("builder-passphrase", auth.getPassphrase());
}

test "BuilderAuth.generateHeaderWithTimestamp GET" {
    const allocator = std.testing.allocator;

    var creds = try BuilderCreds.init(
        allocator,
        "my-builder-key",
        "my-builder-secret",
        "my-builder-pass",
    );
    defer creds.deinit();

    const auth = BuilderAuth.init(&creds);

    const header = try auth.generateHeaderWithTimestamp(.{
        .method = "GET",
        .path = "/builder/trades",
        .body = null,
    }, 1704067200);

    // 验证基本字段
    try std.testing.expectEqualStrings("my-builder-key", header.getApiKey());
    try std.testing.expectEqualStrings("1704067200", header.getTimestamp());
    try std.testing.expectEqualStrings("my-builder-pass", header.getPassphrase());

    // 验证签名存在且是 Base64 格式
    const sig = header.getSignature();
    try std.testing.expectEqual(@as(usize, 44), sig.len);
}

test "BuilderAuth.generateHeaderWithTimestamp POST with body" {
    const allocator = std.testing.allocator;

    var creds = try BuilderCreds.init(
        allocator,
        "builder-key",
        "secret123",
        "pass456",
    );
    defer creds.deinit();

    const auth = BuilderAuth.init(&creds);

    const body = "{\"apiKey\":\"old-key\"}";

    const header = try auth.generateHeaderWithTimestamp(.{
        .method = "DELETE",
        .path = "/auth/builder-api-key",
        .body = body,
    }, 1704067200);

    try std.testing.expectEqualStrings("1704067200", header.getTimestamp());
    try std.testing.expectEqual(@as(usize, 44), header.getSignature().len);
}

test "BuilderAuth signature determinism" {
    const allocator = std.testing.allocator;

    var creds = try BuilderCreds.init(
        allocator,
        "key",
        "secret",
        "pass",
    );
    defer creds.deinit();

    const auth = BuilderAuth.init(&creds);

    // 相同参数应产生相同签名
    const header1 = try auth.generateHeaderWithTimestamp(.{
        .method = "GET",
        .path = "/test",
        .body = null,
    }, 1704067200);

    const header2 = try auth.generateHeaderWithTimestamp(.{
        .method = "GET",
        .path = "/test",
        .body = null,
    }, 1704067200);

    try std.testing.expectEqualStrings(header1.getSignature(), header2.getSignature());
}

test "BuilderAuth signature differs with different params" {
    const allocator = std.testing.allocator;

    var creds = try BuilderCreds.init(
        allocator,
        "key",
        "secret",
        "pass",
    );
    defer creds.deinit();

    const auth = BuilderAuth.init(&creds);

    // 不同时间戳应产生不同签名
    const header1 = try auth.generateHeaderWithTimestamp(.{
        .method = "GET",
        .path = "/test",
        .body = null,
    }, 1704067200);

    const header2 = try auth.generateHeaderWithTimestamp(.{
        .method = "GET",
        .path = "/test",
        .body = null,
    }, 1704067201);

    try std.testing.expect(!std.mem.eql(u8, header1.getSignature(), header2.getSignature()));
}

test "BuilderPolyHeader.toHttpHeaders" {
    const allocator = std.testing.allocator;

    var creds = try BuilderCreds.init(
        allocator,
        "builder-key",
        "secret",
        "passphrase",
    );
    defer creds.deinit();

    const auth = BuilderAuth.init(&creds);

    const header = try auth.generateHeaderWithTimestamp(.{
        .method = "GET",
        .path = "/test",
        .body = null,
    }, 1704067200);

    const http_headers = header.toHttpHeaders();

    try std.testing.expectEqual(@as(usize, 4), http_headers.len);
    try std.testing.expectEqualStrings("POLY-BUILDER-API-KEY", http_headers[0].name);
    try std.testing.expectEqualStrings("POLY-BUILDER-SIGNATURE", http_headers[1].name);
    try std.testing.expectEqualStrings("POLY-BUILDER-TIMESTAMP", http_headers[2].name);
    try std.testing.expectEqualStrings("POLY-BUILDER-PASSPHRASE", http_headers[3].name);
}

test "BuilderPolyHeader header name constants" {
    try std.testing.expectEqualStrings("POLY-BUILDER-API-KEY", BuilderPolyHeader.HEADER_API_KEY);
    try std.testing.expectEqualStrings("POLY-BUILDER-SIGNATURE", BuilderPolyHeader.HEADER_SIGNATURE);
    try std.testing.expectEqualStrings("POLY-BUILDER-TIMESTAMP", BuilderPolyHeader.HEADER_TIMESTAMP);
    try std.testing.expectEqualStrings("POLY-BUILDER-PASSPHRASE", BuilderPolyHeader.HEADER_PASSPHRASE);
}

test "BuilderAuth signature matches expected format" {
    const allocator = std.testing.allocator;

    var creds = try BuilderCreds.init(
        allocator,
        "test-key",
        "test-secret",
        "test-pass",
    );
    defer creds.deinit();

    const auth = BuilderAuth.init(&creds);

    const header = try auth.generateHeaderWithTimestamp(.{
        .method = "GET",
        .path = "/builder/trades",
        .body = null,
    }, 1704067200);

    // 手动计算预期签名
    const message = "1704067200GET/builder/trades";
    const expected_mac = hmac.hmacSha256("test-secret", message);
    var expected_sig: [44]u8 = undefined;
    const expected = hmac.toBase64(&expected_mac, &expected_sig);

    try std.testing.expectEqualStrings(expected, header.getSignature());
}
