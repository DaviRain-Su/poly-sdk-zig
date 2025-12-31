//! 交易相关类型定义
//!
//! 定义交易历史查询相关的请求/响应类型。

const std = @import("std");
const order = @import("order.zig");

const PaginatedResponse = order.PaginatedResponse;

// ============================================================================
// 交易查询
// ============================================================================

/// 交易查询参数
pub const TradesParams = struct {
    /// 按交易 ID 过滤
    id: ?[]const u8 = null,
    /// 按 maker 地址过滤
    maker_address: ?[]const u8 = null,
    /// 按市场 ID 过滤
    market: ?[]const u8 = null,
    /// 按资产 ID 过滤
    asset_id: ?[]const u8 = null,
    /// 时间范围 - 之前
    before: ?[]const u8 = null,
    /// 时间范围 - 之后
    after: ?[]const u8 = null,
    /// 分页游标
    next_cursor: ?[]const u8 = null,
};

/// 交易记录
pub const Trade = struct {
    /// 交易 ID
    id: []const u8,
    /// 交易者地址
    taker_order_id: ?[]const u8 = null,
    /// 市场 ID
    market: ?[]const u8 = null,
    /// 资产 ID
    asset_id: ?[]const u8 = null,
    /// 交易方向
    side: ?[]const u8 = null,
    /// 交易数量
    size: ?[]const u8 = null,
    /// 费用金额
    fee_rate_bps: ?[]const u8 = null,
    /// 成交价格
    price: ?[]const u8 = null,
    /// 状态
    status: ?[]const u8 = null,
    /// 匹配时间
    match_time: ?[]const u8 = null,
    /// 最后更新时间
    last_update: ?[]const u8 = null,
    /// 结果代币
    outcome: ?[]const u8 = null,
    /// Bucket 索引
    bucket_index: ?u32 = null,
    /// 所有者地址
    owner: ?[]const u8 = null,
    /// Maker 地址
    maker_address: ?[]const u8 = null,
    /// 交易哈希
    transaction_hash: ?[]const u8 = null,
    /// 交易者角色 (MAKER/TAKER)
    trader_side: ?[]const u8 = null,
    /// 类型
    type: ?[]const u8 = null,
};

/// 分页交易响应
pub const PaginatedTrades = PaginatedResponse(Trade);

/// 用户交易统计
pub const UserTradeStats = struct {
    /// 交易总数
    total_trades: u64 = 0,
    /// 总交易量（USDC）
    total_volume: ?[]const u8 = null,
    /// 总费用
    total_fees: ?[]const u8 = null,
};

// ============================================================================
// 测试
// ============================================================================

test "Trade" {
    const json_str =
        \\{"id":"trade123","side":"BUY","size":"100","price":"0.65"}
    ;

    const parsed = try std.json.parseFromSlice(Trade, std.testing.allocator, json_str, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    try std.testing.expectEqualStrings("trade123", parsed.value.id);
    try std.testing.expectEqualStrings("BUY", parsed.value.side.?);
    try std.testing.expectEqualStrings("100", parsed.value.size.?);
}

test "PaginatedTrades" {
    const json_str =
        \\{"limit":50,"count":1,"data":[{"id":"t1","price":"0.5"}]}
    ;

    const parsed = try std.json.parseFromSlice(PaginatedTrades, std.testing.allocator, json_str, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    try std.testing.expectEqual(@as(u32, 50), parsed.value.limit);
    try std.testing.expectEqual(@as(usize, 1), parsed.value.data.len);
}

test "TradesParams defaults" {
    const params = TradesParams{};
    try std.testing.expect(params.id == null);
    try std.testing.expect(params.market == null);
}
