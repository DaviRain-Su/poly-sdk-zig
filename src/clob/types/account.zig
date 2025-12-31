//! 账户相关类型定义
//!
//! 定义余额、API Key 和通知相关的请求/响应类型。

const std = @import("std");
const enums = @import("enums.zig");

const AssetType = enums.AssetType;

// ============================================================================
// 余额和 Allowance
// ============================================================================

/// 余额查询参数
pub const BalanceAllowanceParams = struct {
    /// 资产类型
    asset_type: ?AssetType = null,
    /// Token ID（对于 CONDITIONAL 类型）
    token_id: ?[]const u8 = null,
    /// 签名类型
    signature_type: ?u8 = null,
};

/// 余额和 Allowance 响应
pub const BalanceAllowanceResponse = struct {
    /// 余额（最小单位）
    balance: ?[]const u8 = null,
    /// Allowance（最小单位）
    allowance: ?[]const u8 = null,
};

// ============================================================================
// API Key 管理
// ============================================================================

/// API Key 信息
pub const ApiKeyInfo = struct {
    /// API Key
    apiKey: []const u8,
    /// 创建时间
    createdAt: ?[]const u8 = null,
    /// 权限
    permissions: ?[]const []const u8 = null,
    /// 描述
    description: ?[]const u8 = null,
};

/// 删除 API Key 响应
pub const DeleteApiKeyResponse = struct {
    /// 是否成功
    success: bool = false,
    /// 消息
    message: ?[]const u8 = null,
};

/// 封禁状态响应
pub const BanStatusResponse = struct {
    /// 是否仅允许关闭
    closed_only: bool = false,
    /// 原因
    reason: ?[]const u8 = null,
};

// ============================================================================
// 通知
// ============================================================================

/// 通知类型
pub const NotificationType = enum {
    /// 订单成交
    TRADE,
    /// 订单取消
    CANCEL,
    /// 订单过期
    EXPIRED,
    /// 市场结算
    SETTLEMENT,
    /// 系统消息
    SYSTEM,
};

/// 通知
pub const Notification = struct {
    /// 通知 ID
    id: []const u8,
    /// 通知类型
    type: ?[]const u8 = null,
    /// 消息内容
    message: ?[]const u8 = null,
    /// 相关订单 ID
    order_id: ?[]const u8 = null,
    /// 相关交易 ID
    trade_id: ?[]const u8 = null,
    /// 相关市场 ID
    market: ?[]const u8 = null,
    /// 创建时间
    created_at: ?[]const u8 = null,
    /// 是否已读
    read: bool = false,
};

/// 删除通知请求
pub const DropNotificationsRequest = struct {
    /// 要删除的通知 ID 列表
    ids: []const []const u8,
};

/// 删除通知响应
pub const DropNotificationsResponse = struct {
    /// 是否成功
    success: bool = false,
    /// 删除的数量
    count: u32 = 0,
};

// ============================================================================
// Heartbeat
// ============================================================================

/// Heartbeat 响应
pub const HeartbeatResponse = struct {
    /// 是否成功
    success: bool = false,
};

// ============================================================================
// 测试
// ============================================================================

test "BalanceAllowanceResponse" {
    const json_str =
        \\{"balance":"1000000000","allowance":"999999999999"}
    ;

    const parsed = try std.json.parseFromSlice(BalanceAllowanceResponse, std.testing.allocator, json_str, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    try std.testing.expectEqualStrings("1000000000", parsed.value.balance.?);
    try std.testing.expectEqualStrings("999999999999", parsed.value.allowance.?);
}

test "ApiKeyInfo" {
    const json_str =
        \\{"apiKey":"key123","createdAt":"2024-01-01"}
    ;

    const parsed = try std.json.parseFromSlice(ApiKeyInfo, std.testing.allocator, json_str, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    try std.testing.expectEqualStrings("key123", parsed.value.apiKey);
}

test "Notification" {
    const json_str =
        \\{"id":"n1","type":"TRADE","message":"Order filled","read":false}
    ;

    const parsed = try std.json.parseFromSlice(Notification, std.testing.allocator, json_str, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    try std.testing.expectEqualStrings("n1", parsed.value.id);
    try std.testing.expectEqualStrings("TRADE", parsed.value.type.?);
    try std.testing.expect(!parsed.value.read);
}

test "BalanceAllowanceParams defaults" {
    const params = BalanceAllowanceParams{};
    try std.testing.expect(params.asset_type == null);
    try std.testing.expect(params.token_id == null);
}
