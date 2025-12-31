//! 订单相关类型定义
//!
//! 定义订单发布、查询和取消相关的请求/响应类型。

const std = @import("std");
const enums = @import("enums.zig");

const OrderType = enums.OrderType;
const Side = enums.Side;

// ============================================================================
// 订单发布
// ============================================================================

/// 订单发布请求体中的订单数据
pub const OrderData = struct {
    /// 随机盐值
    salt: []const u8,
    /// 订单创建者地址
    maker: []const u8,
    /// 签名者地址
    signer: []const u8,
    /// 接单者地址（零地址 = 公开订单）
    taker: []const u8,
    /// Token ID
    tokenId: []const u8,
    /// Maker 金额（最小单位字符串）
    makerAmount: []const u8,
    /// Taker 金额（最小单位字符串）
    takerAmount: []const u8,
    /// 过期时间戳
    expiration: []const u8,
    /// Nonce
    nonce: []const u8,
    /// 费率（基点）
    feeRateBps: []const u8,
    /// 交易方向
    side: []const u8,
    /// 签名类型
    signatureType: u8,
    /// EIP-712 签名
    signature: []const u8,
};

/// 单个订单发布请求
pub const PostOrderRequest = struct {
    /// 订单数据
    order: OrderData,
    /// 订单类型 (GTC, GTD, FOK, FAK)
    orderType: []const u8,
    /// 所有者地址（可选）
    owner: ?[]const u8 = null,
};

/// 批量订单发布请求
pub const PostOrdersRequest = struct {
    /// 订单列表
    orders: []const OrderData,
    /// 订单类型
    orderType: []const u8,
};

/// 订单发布响应
pub const PostOrderResponse = struct {
    /// 是否成功
    success: bool = false,
    /// 错误消息（如果失败）
    errorMsg: ?[]const u8 = null,
    /// 订单 ID
    orderID: ?[]const u8 = null,
    /// 交易哈希列表
    transactionsHashes: ?[]const []const u8 = null,
    /// 状态信息
    status: ?[]const u8 = null,
};

/// 批量订单发布响应
pub const PostOrdersResponse = struct {
    /// 是否成功
    success: bool = false,
    /// 错误消息（如果失败）
    errorMsg: ?[]const u8 = null,
    /// 订单 ID 列表
    orderIDs: ?[]const []const u8 = null,
    /// 交易哈希列表
    transactionsHashes: ?[]const []const u8 = null,
};

// ============================================================================
// 订单查询
// ============================================================================

/// 开放订单查询参数
pub const OpenOrdersParams = struct {
    /// 按订单 ID 过滤
    id: ?[]const u8 = null,
    /// 按市场 ID 过滤
    market: ?[]const u8 = null,
    /// 按资产 ID 过滤
    asset_id: ?[]const u8 = null,
    /// 分页游标
    next_cursor: ?[]const u8 = null,
};

/// 开放订单
pub const OpenOrder = struct {
    /// 订单 ID
    id: []const u8,
    /// 状态
    status: ?[]const u8 = null,
    /// 所有者地址
    owner: ?[]const u8 = null,
    /// 市场 ID (condition_id)
    market: ?[]const u8 = null,
    /// 资产 ID (token_id)
    asset_id: ?[]const u8 = null,
    /// 交易方向
    side: ?[]const u8 = null,
    /// 原始数量
    original_size: ?[]const u8 = null,
    /// 剩余数量
    size_matched: ?[]const u8 = null,
    /// 价格
    price: ?[]const u8 = null,
    /// 结果代币
    outcome: ?[]const u8 = null,
    /// 关联订单 ID
    associate_trades: ?[]const []const u8 = null,
    /// 创建时间戳
    created_at: ?[]const u8 = null,
    /// 过期时间戳
    expiration: ?[]const u8 = null,
    /// 订单类型
    type: ?[]const u8 = null,
};

/// 分页响应
pub fn PaginatedResponse(comptime T: type) type {
    return struct {
        /// 每页数量限制
        limit: u32 = 0,
        /// 当前页数量
        count: u32 = 0,
        /// 下一页游标
        next_cursor: ?[]const u8 = null,
        /// 数据列表
        data: []const T = &.{},
    };
}

/// 分页订单响应
pub const PaginatedOrders = PaginatedResponse(OpenOrder);

// ============================================================================
// 订单取消
// ============================================================================

/// 取消订单请求
pub const CancelOrderRequest = struct {
    /// 订单 ID
    orderID: []const u8,
};

/// 批量取消订单请求
pub const CancelOrdersRequest = struct {
    /// 订单 ID 列表
    orderIDs: []const []const u8,
};

/// 取消市场订单请求
pub const CancelMarketOrdersRequest = struct {
    /// 市场 ID (condition_id)
    market: ?[]const u8 = null,
    /// 资产 ID (token_id)
    asset_id: ?[]const u8 = null,
};

/// 取消订单响应
pub const CancelOrderResponse = struct {
    /// 是否成功
    success: bool = false,
    /// 错误消息
    errorMsg: ?[]const u8 = null,
    /// 被取消的订单 ID
    canceled: ?[]const []const u8 = null,
    /// 未取消的订单 ID
    not_canceled: ?[]const []const u8 = null,
};

// ============================================================================
// 分页常量
// ============================================================================

/// 初始分页游标
pub const INITIAL_CURSOR = "MA==";

/// 结束分页游标
pub const END_CURSOR = "LTE=";

// ============================================================================
// 测试
// ============================================================================

test "PostOrderResponse" {
    const json_str =
        \\{"success":true,"orderID":"0x123","transactionsHashes":["0xabc"]}
    ;

    const parsed = try std.json.parseFromSlice(PostOrderResponse, std.testing.allocator, json_str, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    try std.testing.expect(parsed.value.success);
    try std.testing.expectEqualStrings("0x123", parsed.value.orderID.?);
}

test "OpenOrder" {
    const json_str =
        \\{"id":"order123","status":"LIVE","side":"BUY","price":"0.65"}
    ;

    const parsed = try std.json.parseFromSlice(OpenOrder, std.testing.allocator, json_str, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    try std.testing.expectEqualStrings("order123", parsed.value.id);
    try std.testing.expectEqualStrings("LIVE", parsed.value.status.?);
}

test "PaginatedOrders" {
    const json_str =
        \\{"limit":100,"count":2,"next_cursor":"abc","data":[{"id":"1"},{"id":"2"}]}
    ;

    const parsed = try std.json.parseFromSlice(PaginatedOrders, std.testing.allocator, json_str, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    try std.testing.expectEqual(@as(u32, 100), parsed.value.limit);
    try std.testing.expectEqual(@as(u32, 2), parsed.value.count);
    try std.testing.expectEqual(@as(usize, 2), parsed.value.data.len);
}

test "CancelOrderResponse" {
    const json_str =
        \\{"success":true,"canceled":["order1","order2"]}
    ;

    const parsed = try std.json.parseFromSlice(CancelOrderResponse, std.testing.allocator, json_str, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    try std.testing.expect(parsed.value.success);
    try std.testing.expectEqual(@as(usize, 2), parsed.value.canceled.?.len);
}

test "pagination constants" {
    try std.testing.expectEqualStrings("MA==", INITIAL_CURSOR);
    try std.testing.expectEqualStrings("LTE=", END_CURSOR);
}
