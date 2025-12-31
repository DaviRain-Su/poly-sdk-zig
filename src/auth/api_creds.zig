//! API 凭证类型
//!
//! 用于存储 Polymarket API 认证所需的凭证信息。
//! 敏感字段使用 Secret 类型包装，防止意外泄露。
//!
//! 示例:
//! ```zig
//! const creds = try ApiCreds.fromJson(allocator, json_response);
//! defer creds.deinit(allocator);
//!
//! // 使用 API Key 进行 L2 认证
//! const hmac = creds.computeHmac(message);
//! ```

const std = @import("std");
const root = @import("../root.zig");

const Secret = root.types.Secret;
const Allocator = std.mem.Allocator;

/// API 凭证
///
/// 用于 L2 认证的 API 凭证，包含 API Key、Secret 和 Passphrase。
/// Secret 和 Passphrase 使用 Secret 类型包装，防止日志泄露。
pub const ApiCreds = struct {
    /// API Key（公开标识符）
    api_key: []const u8,

    /// API Secret（用于 HMAC 签名）
    api_secret: Secret([]const u8),

    /// API Passphrase（附加验证）
    api_passphrase: Secret([]const u8),

    /// 内存分配器（用于释放）
    allocator: Allocator,

    const Self = @This();

    /// 从 JSON 响应解析 API 凭证
    ///
    /// 期望的 JSON 格式:
    /// ```json
    /// {
    ///     "apiKey": "...",
    ///     "secret": "...",
    ///     "passphrase": "..."
    /// }
    /// ```
    pub fn fromJson(allocator: Allocator, json_str: []const u8) !Self {
        const parsed = std.json.parseFromSlice(JsonResponse, allocator, json_str, .{}) catch {
            return error.InvalidJson;
        };
        defer parsed.deinit();

        const response = parsed.value;

        // 复制字符串，因为 parsed 会被释放
        const api_key = try allocator.dupe(u8, response.apiKey);
        errdefer allocator.free(api_key);

        const api_secret = try allocator.dupe(u8, response.secret);
        errdefer allocator.free(api_secret);

        const api_passphrase = try allocator.dupe(u8, response.passphrase);
        errdefer allocator.free(api_passphrase);

        return Self{
            .api_key = api_key,
            .api_secret = Secret([]const u8).init(api_secret),
            .api_passphrase = Secret([]const u8).init(api_passphrase),
            .allocator = allocator,
        };
    }

    /// 创建 API 凭证（手动构造）
    pub fn init(
        allocator: Allocator,
        api_key: []const u8,
        api_secret: []const u8,
        api_passphrase: []const u8,
    ) !Self {
        const key_copy = try allocator.dupe(u8, api_key);
        errdefer allocator.free(key_copy);

        const secret_copy = try allocator.dupe(u8, api_secret);
        errdefer allocator.free(secret_copy);

        const passphrase_copy = try allocator.dupe(u8, api_passphrase);
        errdefer allocator.free(passphrase_copy);

        return Self{
            .api_key = key_copy,
            .api_secret = Secret([]const u8).init(secret_copy),
            .api_passphrase = Secret([]const u8).init(passphrase_copy),
            .allocator = allocator,
        };
    }

    /// 释放资源
    ///
    /// 会先清零敏感数据，然后释放内存。
    pub fn deinit(self: *Self) void {
        // 清零敏感数据
        self.zeroize();

        // 释放内存
        self.allocator.free(self.api_key);
        self.allocator.free(self.api_secret.reveal());
        self.allocator.free(self.api_passphrase.reveal());
    }

    /// 安全清零敏感数据
    ///
    /// 在释放内存前调用，防止敏感数据残留。
    pub fn zeroize(self: *Self) void {
        // 清零 secret
        const secret_slice = @as([*]u8, @ptrCast(@constCast(self.api_secret.reveal().ptr)));
        @memset(secret_slice[0..self.api_secret.reveal().len], 0);

        // 清零 passphrase
        const passphrase_slice = @as([*]u8, @ptrCast(@constCast(self.api_passphrase.reveal().ptr)));
        @memset(passphrase_slice[0..self.api_passphrase.reveal().len], 0);
    }

    /// 获取 API Key（用于 Header）
    pub fn getApiKey(self: *const Self) []const u8 {
        return self.api_key;
    }

    /// 获取 API Secret（用于 HMAC 签名）
    pub fn getApiSecret(self: *const Self) []const u8 {
        return self.api_secret.reveal();
    }

    /// 获取 API Passphrase（用于 Header）
    pub fn getApiPassphrase(self: *const Self) []const u8 {
        return self.api_passphrase.reveal();
    }

    /// JSON 响应结构
    const JsonResponse = struct {
        apiKey: []const u8,
        secret: []const u8,
        passphrase: []const u8,
    };
};

/// API 凭证错误
pub const ApiCredsError = error{
    /// 无效的 JSON 格式
    InvalidJson,
    /// 内存分配失败
    OutOfMemory,
};

// ============================================================================
// 测试
// ============================================================================

test "ApiCreds.fromJson valid" {
    const allocator = std.testing.allocator;

    const json =
        \\{"apiKey":"test-key","secret":"test-secret","passphrase":"test-pass"}
    ;

    var creds = try ApiCreds.fromJson(allocator, json);
    defer creds.deinit();

    try std.testing.expectEqualStrings("test-key", creds.api_key);
    try std.testing.expectEqualStrings("test-secret", creds.getApiSecret());
    try std.testing.expectEqualStrings("test-pass", creds.getApiPassphrase());
}

test "ApiCreds.fromJson invalid" {
    const allocator = std.testing.allocator;

    const result = ApiCreds.fromJson(allocator, "not json");
    try std.testing.expectError(error.InvalidJson, result);
}

test "ApiCreds.init" {
    const allocator = std.testing.allocator;

    var creds = try ApiCreds.init(
        allocator,
        "my-key",
        "my-secret",
        "my-passphrase",
    );
    defer creds.deinit();

    try std.testing.expectEqualStrings("my-key", creds.getApiKey());
    try std.testing.expectEqualStrings("my-secret", creds.getApiSecret());
    try std.testing.expectEqualStrings("my-passphrase", creds.getApiPassphrase());
}

test "ApiCreds secret is protected" {
    const allocator = std.testing.allocator;

    var creds = try ApiCreds.init(
        allocator,
        "key",
        "secret",
        "passphrase",
    );
    defer creds.deinit();

    // Secret 类型格式化输出 [REDACTED]
    var buffer: [64]u8 = undefined;
    const formatted = std.fmt.bufPrint(&buffer, "{f}", .{creds.api_secret}) catch unreachable;
    try std.testing.expectEqualStrings("[REDACTED]", formatted);
}

test "ApiCreds.zeroize" {
    const allocator = std.testing.allocator;

    var creds = try ApiCreds.init(
        allocator,
        "key",
        "secret123",
        "pass456",
    );

    // 获取指向 secret 的指针（在 zeroize 前）
    const secret_ptr = creds.api_secret.reveal().ptr;
    const passphrase_ptr = creds.api_passphrase.reveal().ptr;

    // 清零
    creds.zeroize();

    // 验证已清零
    const secret_slice = @as([*]const u8, @ptrCast(secret_ptr))[0..9];
    const passphrase_slice = @as([*]const u8, @ptrCast(passphrase_ptr))[0..7];

    for (secret_slice) |byte| {
        try std.testing.expectEqual(@as(u8, 0), byte);
    }
    for (passphrase_slice) |byte| {
        try std.testing.expectEqual(@as(u8, 0), byte);
    }

    // 仍然需要释放内存
    creds.deinit();
}
