//! Builder API 类型定义
//!
//! 定义 Builder 程序相关的类型，用于做市商专用认证和交易。
//!
//! Builder 是 Polymarket 的做市商程序，具有特殊权限：
//! - 独立的 API Key 管理
//! - 专用的交易历史查询
//! - 更高的请求限制

const std = @import("std");

/// Builder API Key 创建响应
///
/// 调用 POST /auth/builder-api-key 返回的响应。
pub const BuilderApiKeyResponse = struct {
    /// API Key
    api_key: []const u8 = "",

    /// API Secret（用于签名）
    api_secret: []const u8 = "",

    /// Passphrase
    passphrase: []const u8 = "",

    /// 创建时间（ISO 8601 格式）
    created_at: ?[]const u8 = null,

    // JSON 字段映射
    pub const jsonFieldNames = .{
        .api_key = "apiKey",
        .api_secret = "apiSecret",
    };
};

/// Builder API Key 信息
///
/// 获取 Builder API Keys 列表时返回的单个 Key 信息。
pub const BuilderApiKeyInfo = struct {
    /// API Key
    api_key: []const u8 = "",

    /// 创建时间（ISO 8601 格式）
    created_at: ?[]const u8 = null,

    /// 上次使用时间
    last_used_at: ?[]const u8 = null,

    /// 是否已撤销
    revoked: bool = false,

    // JSON 字段映射
    pub const jsonFieldNames = .{
        .api_key = "apiKey",
        .created_at = "createdAt",
        .last_used_at = "lastUsedAt",
    };
};

/// Builder 交易查询参数
pub const BuilderTradesParams = struct {
    /// 市场 condition ID
    market: ?[]const u8 = null,

    /// Token ID
    asset_id: ?[]const u8 = null,

    /// 开始时间（Unix 时间戳）
    before: ?i64 = null,

    /// 结束时间（Unix 时间戳）
    after: ?i64 = null,

    /// 分页游标
    next_cursor: ?[]const u8 = null,

    /// 每页数量
    limit: ?u32 = null,
};

/// Builder 交易记录
///
/// Builder 专用交易记录，包含额外的 Builder 相关字段。
pub const BuilderTrade = struct {
    /// 交易 ID
    id: []const u8 = "",

    /// 市场 condition ID
    market: ?[]const u8 = null,

    /// Token ID
    asset_id: ?[]const u8 = null,

    /// 交易方向
    side: ?[]const u8 = null,

    /// 价格
    price: ?[]const u8 = null,

    /// 数量
    size: ?[]const u8 = null,

    /// 成交金额
    fee: ?[]const u8 = null,

    /// 交易时间
    timestamp: ?[]const u8 = null,

    /// 关联的订单 ID
    order_id: ?[]const u8 = null,

    /// 订单类型（maker/taker）
    trader_side: ?[]const u8 = null,

    /// Builder ID（如果适用）
    builder_id: ?[]const u8 = null,

    // JSON 字段映射
    pub const jsonFieldNames = .{
        .asset_id = "assetId",
        .order_id = "orderId",
        .trader_side = "traderSide",
        .builder_id = "builderId",
    };
};

/// Builder 交易分页响应
pub const PaginatedBuilderTrades = struct {
    /// 交易列表
    data: []BuilderTrade = &.{},

    /// 下一页游标
    next_cursor: ?[]const u8 = null,

    /// 总数量（如果有）
    count: ?u64 = null,

    // JSON 字段映射
    pub const jsonFieldNames = .{
        .next_cursor = "nextCursor",
    };
};

/// 撤销 Builder API Key 请求
pub const RevokeBuilderApiKeyRequest = struct {
    /// 要撤销的 API Key
    api_key: []const u8,

    // JSON 字段映射
    pub const jsonFieldNames = .{
        .api_key = "apiKey",
    };
};

/// 撤销 Builder API Key 响应
pub const RevokeBuilderApiKeyResponse = struct {
    /// 是否成功
    success: bool = false,

    /// 消息
    message: ?[]const u8 = null,
};

// ============================================================================
// 测试
// ============================================================================

test "BuilderApiKeyResponse struct" {
    const response = BuilderApiKeyResponse{
        .api_key = "builder-key-123",
        .api_secret = "secret-abc",
        .passphrase = "pass-xyz",
        .created_at = "2024-01-01T00:00:00Z",
    };

    try std.testing.expectEqualStrings("builder-key-123", response.api_key);
    try std.testing.expectEqualStrings("secret-abc", response.api_secret);
    try std.testing.expectEqualStrings("pass-xyz", response.passphrase);
    try std.testing.expectEqualStrings("2024-01-01T00:00:00Z", response.created_at.?);
}

test "BuilderApiKeyInfo struct" {
    const info = BuilderApiKeyInfo{
        .api_key = "key-456",
        .created_at = "2024-01-01T00:00:00Z",
        .revoked = false,
    };

    try std.testing.expectEqualStrings("key-456", info.api_key);
    try std.testing.expect(!info.revoked);
}

test "BuilderTradesParams defaults" {
    const params = BuilderTradesParams{};

    try std.testing.expectEqual(@as(?[]const u8, null), params.market);
    try std.testing.expectEqual(@as(?[]const u8, null), params.asset_id);
    try std.testing.expectEqual(@as(?i64, null), params.before);
    try std.testing.expectEqual(@as(?u32, null), params.limit);
}

test "BuilderTrade struct" {
    const trade = BuilderTrade{
        .id = "trade-789",
        .market = "0x123",
        .side = "BUY",
        .price = "0.65",
        .size = "100",
        .builder_id = "builder-1",
    };

    try std.testing.expectEqualStrings("trade-789", trade.id);
    try std.testing.expectEqualStrings("0x123", trade.market.?);
    try std.testing.expectEqualStrings("builder-1", trade.builder_id.?);
}

test "RevokeBuilderApiKeyResponse struct" {
    const response = RevokeBuilderApiKeyResponse{
        .success = true,
        .message = "Key revoked successfully",
    };

    try std.testing.expect(response.success);
    try std.testing.expectEqualStrings("Key revoked successfully", response.message.?);
}
