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

    /// 内存分配器（用于释放，可选）
    /// 如果为 null，表示凭证由 initFromStrings() 创建，不需要释放
    allocator: ?Allocator = null,

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

    /// 创建 API 凭证（手动构造，会复制内存）
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

    /// 从字符串直接创建 API 凭证（不复制内存）
    ///
    /// 用于从环境变量或配置文件加载凭证，不需要分配器。
    /// 注意：调用者必须确保传入的字符串生命周期足够长。
    /// 此方法创建的凭证不需要调用 deinit()（调用也是安全的）。
    ///
    /// 示例:
    /// ```zig
    /// const api_key = env.get("POLY_API_KEY") orelse return error.MissingCredentials;
    /// const api_secret = env.get("POLY_API_SECRET") orelse return error.MissingCredentials;
    /// const passphrase = env.get("POLY_PASSPHRASE") orelse return error.MissingCredentials;
    ///
    /// var creds = ApiCreds.initFromStrings(api_key, api_secret, passphrase);
    /// client.setApiCreds(&creds);
    /// ```
    pub fn initFromStrings(
        api_key: []const u8,
        api_secret: []const u8,
        api_passphrase: []const u8,
    ) Self {
        return Self{
            .api_key = api_key,
            .api_secret = Secret([]const u8).init(api_secret),
            .api_passphrase = Secret([]const u8).init(api_passphrase),
            .allocator = null, // No allocator needed for borrowed strings
        };
    }

    /// 释放资源
    ///
    /// 会先清零敏感数据，然后释放内存。
    /// 对于 initFromStrings() 创建的凭证，此方法不会释放内存（因为内存不是由此结构分配的）。
    pub fn deinit(self: *Self) void {
        // 只有当有 allocator 时才清零和释放内存
        // initFromStrings() 创建的凭证使用借用的字符串，可能是只读的，不能清零
        if (self.allocator) |alloc| {
            // 清零敏感数据
            self.zeroize();
            // 释放内存
            alloc.free(self.api_key);
            alloc.free(self.api_secret.reveal());
            alloc.free(self.api_passphrase.reveal());
        }
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

test "ApiCreds.initFromStrings" {
    // 使用静态字符串创建凭证
    var creds = ApiCreds.initFromStrings(
        "static-key",
        "static-secret",
        "static-passphrase",
    );

    // 验证字段
    try std.testing.expectEqualStrings("static-key", creds.getApiKey());
    try std.testing.expectEqualStrings("static-secret", creds.getApiSecret());
    try std.testing.expectEqualStrings("static-passphrase", creds.getApiPassphrase());

    // allocator 应该是 null
    try std.testing.expectEqual(@as(?std.mem.Allocator, null), creds.allocator);

    // deinit 应该是安全的（不会尝试释放内存）
    creds.deinit();
}

test "ApiCreds.initFromStrings with deinit is safe" {
    // 验证对 initFromStrings 创建的凭证调用 deinit 是安全的
    var creds = ApiCreds.initFromStrings(
        "key1",
        "secret1",
        "pass1",
    );
    defer creds.deinit(); // 应该不会崩溃

    try std.testing.expectEqualStrings("key1", creds.getApiKey());
}
