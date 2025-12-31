//! RFQ (Request for Quote) 类型定义
//!
//! RFQ 系统用于大宗交易的询价功能。用户可以发起询价请求，
//! 做市商提供报价，用户选择最优报价执行交易。
//!
//! ## 工作流程
//!
//! 1. 用户创建 RFQ 请求 (`createRfqRequest`)
//! 2. 做市商看到请求并创建报价 (`createRfqQuote`)
//! 3. 用户获取报价列表 (`getRfqQuotes`) 或最佳报价 (`getRfqBestQuote`)
//! 4. 用户接受报价 (`acceptRfqQuote`)
//! 5. 做市商批准订单 (`approveRfqOrder`)

const std = @import("std");

/// RFQ 匹配类型
pub const RfqMatchType = enum {
    /// 互补匹配: BUY <> SELL
    COMPLEMENTARY,
    /// 合并匹配: BUY <> BUY 或 SELL <> SELL
    MERGE,
    /// 铸造匹配
    MINT,

    const Self = @This();

    /// 从字符串解析
    pub fn fromString(str: []const u8) ?Self {
        if (std.mem.eql(u8, str, "COMPLEMENTARY")) return .COMPLEMENTARY;
        if (std.mem.eql(u8, str, "MERGE")) return .MERGE;
        if (std.mem.eql(u8, str, "MINT")) return .MINT;
        return null;
    }

    /// 转换为字符串
    pub fn toString(self: Self) []const u8 {
        return switch (self) {
            .COMPLEMENTARY => "COMPLEMENTARY",
            .MERGE => "MERGE",
            .MINT => "MINT",
        };
    }
};

/// RFQ 请求状态
pub const RfqRequestState = enum {
    /// 等待报价
    PENDING,
    /// 已接受报价
    ACCEPTED,
    /// 已取消
    CANCELLED,
    /// 已过期
    EXPIRED,
    /// 已完成
    FILLED,

    const Self = @This();

    pub fn fromString(str: []const u8) ?Self {
        if (std.mem.eql(u8, str, "PENDING")) return .PENDING;
        if (std.mem.eql(u8, str, "ACCEPTED")) return .ACCEPTED;
        if (std.mem.eql(u8, str, "CANCELLED")) return .CANCELLED;
        if (std.mem.eql(u8, str, "EXPIRED")) return .EXPIRED;
        if (std.mem.eql(u8, str, "FILLED")) return .FILLED;
        return null;
    }

    pub fn toString(self: Self) []const u8 {
        return switch (self) {
            .PENDING => "PENDING",
            .ACCEPTED => "ACCEPTED",
            .CANCELLED => "CANCELLED",
            .EXPIRED => "EXPIRED",
            .FILLED => "FILLED",
        };
    }
};

/// RFQ 报价状态
pub const RfqQuoteState = enum {
    /// 等待接受
    PENDING,
    /// 已接受
    ACCEPTED,
    /// 已取消
    CANCELLED,
    /// 已过期
    EXPIRED,
    /// 已拒绝
    REJECTED,

    const Self = @This();

    pub fn fromString(str: []const u8) ?Self {
        if (std.mem.eql(u8, str, "PENDING")) return .PENDING;
        if (std.mem.eql(u8, str, "ACCEPTED")) return .ACCEPTED;
        if (std.mem.eql(u8, str, "CANCELLED")) return .CANCELLED;
        if (std.mem.eql(u8, str, "EXPIRED")) return .EXPIRED;
        if (std.mem.eql(u8, str, "REJECTED")) return .REJECTED;
        return null;
    }

    pub fn toString(self: Self) []const u8 {
        return switch (self) {
            .PENDING => "PENDING",
            .ACCEPTED => "ACCEPTED",
            .CANCELLED => "CANCELLED",
            .EXPIRED => "EXPIRED",
            .REJECTED => "REJECTED",
        };
    }
};

/// RFQ 请求
pub const RfqRequest = struct {
    /// 请求 ID
    request_id: []const u8 = "",

    /// 用户地址
    user_address: []const u8 = "",

    /// 代理地址
    proxy_address: []const u8 = "",

    /// Token ID
    token: []const u8 = "",

    /// 互补 Token ID
    complement: []const u8 = "",

    /// 市场 condition ID
    condition: []const u8 = "",

    /// 交易方向
    side: []const u8 = "",

    /// 输入数量
    size_in: []const u8 = "",

    /// 输出数量
    size_out: []const u8 = "",

    /// 价格
    price: ?f64 = null,

    /// 已接受的报价 ID
    accepted_quote_id: ?[]const u8 = null,

    /// 状态
    state: []const u8 = "",

    /// 过期时间
    expiry: []const u8 = "",

    /// 创建时间
    created_at: []const u8 = "",

    /// 更新时间
    updated_at: []const u8 = "",

    // JSON 字段映射
    pub const jsonFieldNames = .{
        .request_id = "requestId",
        .user_address = "userAddress",
        .proxy_address = "proxyAddress",
        .size_in = "sizeIn",
        .size_out = "sizeOut",
        .accepted_quote_id = "acceptedQuoteId",
        .created_at = "createdAt",
        .updated_at = "updatedAt",
    };
};

/// RFQ 报价
pub const RfqQuote = struct {
    /// 报价 ID
    quote_id: []const u8 = "",

    /// 请求 ID
    request_id: []const u8 = "",

    /// 用户地址（做市商）
    user_address: []const u8 = "",

    /// 代理地址
    proxy_address: []const u8 = "",

    /// Token ID
    token: []const u8 = "",

    /// 互补 Token ID
    complement: []const u8 = "",

    /// 市场 condition ID
    condition: []const u8 = "",

    /// 交易方向
    side: []const u8 = "",

    /// 输入数量
    size_in: []const u8 = "",

    /// 输出数量
    size_out: []const u8 = "",

    /// 价格
    price: ?f64 = null,

    /// 状态
    state: []const u8 = "",

    /// 匹配类型
    match_type: []const u8 = "",

    /// 过期时间
    expiry: []const u8 = "",

    /// 创建时间
    created_at: []const u8 = "",

    /// 更新时间
    updated_at: []const u8 = "",

    // JSON 字段映射
    pub const jsonFieldNames = .{
        .quote_id = "quoteId",
        .request_id = "requestId",
        .user_address = "userAddress",
        .proxy_address = "proxyAddress",
        .size_in = "sizeIn",
        .size_out = "sizeOut",
        .match_type = "matchType",
        .created_at = "createdAt",
        .updated_at = "updatedAt",
    };
};

/// 创建 RFQ 请求参数
pub const CreateRfqRequestParams = struct {
    /// 输入资产（如 "USDC" 或 token_id）
    asset_in: []const u8,

    /// 输出资产（如 token_id 或 "USDC"）
    asset_out: []const u8,

    /// 输入数量
    amount_in: []const u8,

    /// 输出数量（0 表示由做市商报价）
    amount_out: []const u8 = "0",

    /// 用户类型 (0 = EOA, 1 = Proxy)
    user_type: u8 = 0,

    // JSON 字段映射
    pub const jsonFieldNames = .{
        .asset_in = "assetIn",
        .asset_out = "assetOut",
        .amount_in = "amountIn",
        .amount_out = "amountOut",
        .user_type = "userType",
    };
};

/// 创建 RFQ 报价参数（做市商用）
pub const CreateRfqQuoteParams = struct {
    /// 请求 ID
    request_id: []const u8,

    /// 价格
    price: []const u8,

    /// 过期时间（Unix 时间戳）
    expiration: i64,

    /// 匹配类型
    match_type: []const u8 = "COMPLEMENTARY",

    // JSON 字段映射
    pub const jsonFieldNames = .{
        .request_id = "requestId",
        .match_type = "matchType",
    };
};

/// 接受 RFQ 报价参数
pub const AcceptRfqQuoteParams = struct {
    /// 请求 ID
    request_id: []const u8,

    /// 报价 ID
    quote_id: []const u8,

    /// 过期时间（Unix 时间戳）
    expiration: i64,

    // JSON 字段映射
    pub const jsonFieldNames = .{
        .request_id = "requestId",
        .quote_id = "quoteId",
    };
};

/// 批准 RFQ 订单参数（做市商用）
pub const ApproveRfqOrderParams = struct {
    /// 报价 ID
    quote_id: []const u8,

    // JSON 字段映射
    pub const jsonFieldNames = .{
        .quote_id = "quoteId",
    };
};

/// 获取 RFQ 请求列表参数
pub const GetRfqRequestsParams = struct {
    /// 市场 condition ID
    market: ?[]const u8 = null,

    /// 状态筛选
    state: ?[]const u8 = null,

    /// 分页游标
    next_cursor: ?[]const u8 = null,

    /// 每页数量
    limit: ?u32 = null,
};

/// 获取 RFQ 报价列表参数
pub const GetRfqQuotesParams = struct {
    /// 请求 ID
    request_id: ?[]const u8 = null,

    /// 市场 condition ID
    market: ?[]const u8 = null,

    /// 状态筛选
    state: ?[]const u8 = null,

    /// 分页游标
    next_cursor: ?[]const u8 = null,

    /// 每页数量
    limit: ?u32 = null,
};

/// 取消 RFQ 请求参数
pub const CancelRfqRequestParams = struct {
    /// 请求 ID
    request_id: []const u8,

    // JSON 字段映射
    pub const jsonFieldNames = .{
        .request_id = "requestId",
    };
};

/// 取消 RFQ 报价参数
pub const CancelRfqQuoteParams = struct {
    /// 报价 ID
    quote_id: []const u8,

    // JSON 字段映射
    pub const jsonFieldNames = .{
        .quote_id = "quoteId",
    };
};

/// RFQ 请求响应
pub const RfqRequestResponse = struct {
    /// 请求数据
    data: ?RfqRequest = null,

    /// 是否成功
    success: bool = false,

    /// 错误消息
    message: ?[]const u8 = null,
};

/// RFQ 报价响应
pub const RfqQuoteResponse = struct {
    /// 报价数据
    data: ?RfqQuote = null,

    /// 是否成功
    success: bool = false,

    /// 错误消息
    message: ?[]const u8 = null,
};

/// 分页 RFQ 请求列表
pub const PaginatedRfqRequests = struct {
    /// 请求列表
    data: []RfqRequest = &.{},

    /// 下一页游标
    next_cursor: ?[]const u8 = null,

    /// 总数量
    count: ?u64 = null,

    // JSON 字段映射
    pub const jsonFieldNames = .{
        .next_cursor = "nextCursor",
    };
};

/// 分页 RFQ 报价列表
pub const PaginatedRfqQuotes = struct {
    /// 报价列表
    data: []RfqQuote = &.{},

    /// 下一页游标
    next_cursor: ?[]const u8 = null,

    /// 总数量
    count: ?u64 = null,

    // JSON 字段映射
    pub const jsonFieldNames = .{
        .next_cursor = "nextCursor",
    };
};

/// 接受报价响应
pub const AcceptRfqQuoteResponse = struct {
    /// 是否成功
    success: bool = false,

    /// 消息
    message: ?[]const u8 = null,

    /// 订单 ID
    order_id: ?[]const u8 = null,

    // JSON 字段映射
    pub const jsonFieldNames = .{
        .order_id = "orderId",
    };
};

/// 批准订单响应
pub const ApproveRfqOrderResponse = struct {
    /// 是否成功
    success: bool = false,

    /// 消息
    message: ?[]const u8 = null,
};

/// 取消响应
pub const CancelRfqResponse = struct {
    /// 是否成功
    success: bool = false,

    /// 消息
    message: ?[]const u8 = null,
};

/// RFQ 配置
pub const RfqConfig = struct {
    /// 最小请求金额
    min_request_amount: ?[]const u8 = null,

    /// 最大请求金额
    max_request_amount: ?[]const u8 = null,

    /// 报价有效期（秒）
    quote_validity_seconds: ?u64 = null,

    /// 请求有效期（秒）
    request_validity_seconds: ?u64 = null,

    /// 是否启用
    enabled: bool = true,

    // JSON 字段映射
    pub const jsonFieldNames = .{
        .min_request_amount = "minRequestAmount",
        .max_request_amount = "maxRequestAmount",
        .quote_validity_seconds = "quoteValiditySeconds",
        .request_validity_seconds = "requestValiditySeconds",
    };
};

// ============================================================================
// 测试
// ============================================================================

test "RfqMatchType fromString and toString" {
    try std.testing.expectEqual(RfqMatchType.COMPLEMENTARY, RfqMatchType.fromString("COMPLEMENTARY").?);
    try std.testing.expectEqual(RfqMatchType.MERGE, RfqMatchType.fromString("MERGE").?);
    try std.testing.expectEqual(RfqMatchType.MINT, RfqMatchType.fromString("MINT").?);
    try std.testing.expectEqual(@as(?RfqMatchType, null), RfqMatchType.fromString("INVALID"));

    try std.testing.expectEqualStrings("COMPLEMENTARY", RfqMatchType.COMPLEMENTARY.toString());
    try std.testing.expectEqualStrings("MERGE", RfqMatchType.MERGE.toString());
    try std.testing.expectEqualStrings("MINT", RfqMatchType.MINT.toString());
}

test "RfqRequestState fromString and toString" {
    try std.testing.expectEqual(RfqRequestState.PENDING, RfqRequestState.fromString("PENDING").?);
    try std.testing.expectEqual(RfqRequestState.ACCEPTED, RfqRequestState.fromString("ACCEPTED").?);
    try std.testing.expectEqual(RfqRequestState.CANCELLED, RfqRequestState.fromString("CANCELLED").?);
    try std.testing.expectEqual(RfqRequestState.EXPIRED, RfqRequestState.fromString("EXPIRED").?);
    try std.testing.expectEqual(RfqRequestState.FILLED, RfqRequestState.fromString("FILLED").?);

    try std.testing.expectEqualStrings("PENDING", RfqRequestState.PENDING.toString());
}

test "RfqQuoteState fromString and toString" {
    try std.testing.expectEqual(RfqQuoteState.PENDING, RfqQuoteState.fromString("PENDING").?);
    try std.testing.expectEqual(RfqQuoteState.ACCEPTED, RfqQuoteState.fromString("ACCEPTED").?);
    try std.testing.expectEqual(RfqQuoteState.REJECTED, RfqQuoteState.fromString("REJECTED").?);

    try std.testing.expectEqualStrings("REJECTED", RfqQuoteState.REJECTED.toString());
}

test "RfqRequest struct" {
    const request = RfqRequest{
        .request_id = "req-123",
        .user_address = "0x1234",
        .token = "token-456",
        .side = "BUY",
        .size_in = "10000",
        .state = "PENDING",
    };

    try std.testing.expectEqualStrings("req-123", request.request_id);
    try std.testing.expectEqualStrings("BUY", request.side);
    try std.testing.expectEqualStrings("PENDING", request.state);
}

test "RfqQuote struct" {
    const quote = RfqQuote{
        .quote_id = "quote-789",
        .request_id = "req-123",
        .price = 0.65,
        .match_type = "COMPLEMENTARY",
        .state = "PENDING",
    };

    try std.testing.expectEqualStrings("quote-789", quote.quote_id);
    try std.testing.expectEqualStrings("req-123", quote.request_id);
    try std.testing.expect(quote.price.? == 0.65);
}

test "CreateRfqRequestParams struct" {
    const params = CreateRfqRequestParams{
        .asset_in = "USDC",
        .asset_out = "token-123",
        .amount_in = "10000",
        .amount_out = "0",
        .user_type = 0,
    };

    try std.testing.expectEqualStrings("USDC", params.asset_in);
    try std.testing.expectEqualStrings("10000", params.amount_in);
    try std.testing.expectEqual(@as(u8, 0), params.user_type);
}

test "AcceptRfqQuoteParams struct" {
    const params = AcceptRfqQuoteParams{
        .request_id = "req-123",
        .quote_id = "quote-456",
        .expiration = 1704067200,
    };

    try std.testing.expectEqualStrings("req-123", params.request_id);
    try std.testing.expectEqualStrings("quote-456", params.quote_id);
    try std.testing.expectEqual(@as(i64, 1704067200), params.expiration);
}

test "RfqConfig struct" {
    const config = RfqConfig{
        .min_request_amount = "1000",
        .max_request_amount = "1000000",
        .quote_validity_seconds = 300,
        .request_validity_seconds = 600,
        .enabled = true,
    };

    try std.testing.expectEqualStrings("1000", config.min_request_amount.?);
    try std.testing.expect(config.enabled);
}

test "GetRfqRequestsParams defaults" {
    const params = GetRfqRequestsParams{};

    try std.testing.expectEqual(@as(?[]const u8, null), params.market);
    try std.testing.expectEqual(@as(?[]const u8, null), params.state);
    try std.testing.expectEqual(@as(?u32, null), params.limit);
}

test "GetRfqQuotesParams defaults" {
    const params = GetRfqQuotesParams{};

    try std.testing.expectEqual(@as(?[]const u8, null), params.request_id);
    try std.testing.expectEqual(@as(?[]const u8, null), params.market);
}
