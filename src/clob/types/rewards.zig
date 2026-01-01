// 奖励和分析相关类型
//
// 用于订单评分、市场分析等功能

const std = @import("std");

/// 订单评分参数
pub const OrderScoringParams = struct {
    /// 订单 ID
    order_id: []const u8,

    /// 转换为查询参数
    pub fn toQueryParams(self: OrderScoringParams, buf: []u8) ![]const u8 {
        return try std.fmt.bufPrint(buf, "orderId={s}", .{self.order_id});
    }
};

/// 批量订单评分参数
pub const OrdersScoringParams = struct {
    /// 订单 ID 列表
    order_ids: []const []const u8,
};

/// 订单评分结果
pub const OrderScoringResult = struct {
    /// 订单 ID
    order_id: []const u8 = "",

    /// 是否正在评分
    scoring: bool = false,
};

/// 批量订单评分结果
pub const OrdersScoringResults = struct {
    /// 结果列表
    results: []const OrderScoringResult = &.{},
};

/// 市场交易事件
pub const MarketTradeEvent = struct {
    /// 事件 ID
    id: ?[]const u8 = null,

    /// 条件 ID (市场 ID)
    condition_id: ?[]const u8 = null,

    /// 资产 ID (代币 ID)
    asset_id: ?[]const u8 = null,

    /// 交易方向: BUY, SELL
    side: ?[]const u8 = null,

    /// 价格
    price: ?[]const u8 = null,

    /// 数量
    size: ?[]const u8 = null,

    /// 做市商地址
    maker: ?[]const u8 = null,

    /// 吃单者地址
    taker: ?[]const u8 = null,

    /// 时间戳
    timestamp: ?[]const u8 = null,

    /// 交易哈希
    tx_hash: ?[]const u8 = null,

    /// 结果代币 (YES/NO)
    outcome: ?[]const u8 = null,
};

/// 市场交易事件列表
pub const MarketTradeEvents = struct {
    /// 事件列表
    events: []const MarketTradeEvent = &.{},

    /// 是否有更多
    has_more: bool = false,

    /// 下一页游标
    next_cursor: ?[]const u8 = null,
};

/// 市场交易事件查询参数
pub const MarketTradeEventsParams = struct {
    /// 条件 ID (路径参数)
    condition_id: []const u8,

    /// 限制数量
    limit: ?u32 = null,

    /// 偏移量
    offset: ?u32 = null,

    /// 开始时间戳
    start_ts: ?i64 = null,

    /// 结束时间戳
    end_ts: ?i64 = null,
};

/// 费率响应
pub const FeeRateResponse = struct {
    /// 费率 (基点)
    fee_rate_bps: []const u8 = "0",

    /// 做市商费率
    maker_fee_rate_bps: ?[]const u8 = null,

    /// 吃单者费率
    taker_fee_rate_bps: ?[]const u8 = null,
};

/// 费率查询参数
pub const FeeRateParams = struct {
    /// 代币 ID (可选)
    token_id: ?[]const u8 = null,

    /// 条件 ID (可选)
    condition_id: ?[]const u8 = null,
};

// ============================================================================
// 批量端点类型
// ============================================================================

/// 批量订单簿请求
pub const BooksRequest = struct {
    /// 代币 ID 列表
    token_ids: []const []const u8,
};

/// 批量中间价请求
pub const MidpointsRequest = struct {
    /// 代币 ID 列表
    token_ids: []const []const u8,
};

/// 批量价格请求
pub const PricesRequest = struct {
    /// 代币 ID 列表
    token_ids: []const []const u8,

    /// 交易方向
    side: ?[]const u8 = null,
};

/// 批量价差请求
pub const SpreadsRequest = struct {
    /// 代币 ID 列表
    token_ids: []const []const u8,
};

/// 批量最后成交价请求
pub const LastTradesPricesRequest = struct {
    /// 代币 ID 列表
    token_ids: []const []const u8,
};

/// 价格响应
pub const PriceResponse = struct {
    /// 代币 ID
    token_id: []const u8 = "",

    /// 价格
    price: []const u8 = "0",
};

/// 中间价响应
pub const MidpointResponse = struct {
    /// 代币 ID
    token_id: []const u8 = "",

    /// 中间价
    midpoint: []const u8 = "0",
};

/// 价差响应
pub const SpreadResponse = struct {
    /// 代币 ID
    token_id: []const u8 = "",

    /// 价差
    spread: []const u8 = "0",
};

/// 最后成交价响应
pub const LastTradePriceResponse = struct {
    /// 代币 ID
    token_id: []const u8 = "",

    /// 最后成交价
    last_trade_price: []const u8 = "0",
};

// ============================================================================
// API Key 管理类型
// ============================================================================

/// API Key 信息
pub const ApiKeyInfo = struct {
    /// API Key
    api_key: []const u8 = "",

    /// 创建时间
    created_at: ?[]const u8 = null,

    /// 最后使用时间
    last_used_at: ?[]const u8 = null,

    /// 是否活跃
    is_active: bool = true,

    /// 权限列表
    permissions: ?[]const []const u8 = null,
};

/// API Key 列表响应
pub const ApiKeysResponse = struct {
    /// API Key 列表
    api_keys: []const ApiKeyInfo = &.{},
};

/// 删除 API Key 响应
pub const DeleteApiKeyResponse = struct {
    /// 是否成功
    success: bool = false,

    /// 消息
    message: ?[]const u8 = null,
};

/// Closed Only 模式状态
pub const ClosedOnlyModeResponse = struct {
    /// 是否处于 closed only 模式
    closed_only: bool = false,

    /// 原因
    reason: ?[]const u8 = null,
};

/// 余额授权更新响应
pub const UpdateBalanceAllowanceResponse = struct {
    /// 是否成功
    success: bool = false,

    /// 新余额
    balance: ?[]const u8 = null,

    /// 新授权额度
    allowance: ?[]const u8 = null,
};

// ============================================================================
// Readonly API Key 类型
// ============================================================================

/// Readonly API Key 信息
pub const ReadonlyApiKeyInfo = struct {
    /// API Key
    api_key: []const u8 = "",

    /// 创建时间
    created_at: ?[]const u8 = null,

    /// 过期时间
    expires_at: ?[]const u8 = null,

    /// 是否活跃
    is_active: bool = true,

    /// 描述
    description: ?[]const u8 = null,
};

/// 创建 Readonly API Key 请求参数
pub const CreateReadonlyApiKeyParams = struct {
    /// 描述 (可选)
    description: ?[]const u8 = null,

    /// 过期时间 (可选, Unix 时间戳)
    expires_at: ?i64 = null,
};

/// 创建 Readonly API Key 响应
pub const CreateReadonlyApiKeyResponse = struct {
    /// API Key
    api_key: []const u8 = "",

    /// 创建时间
    created_at: ?[]const u8 = null,

    /// 是否成功
    success: bool = true,
};

/// 删除 Readonly API Key 响应
pub const DeleteReadonlyApiKeyResponse = struct {
    /// 是否成功
    success: bool = false,

    /// 消息
    message: ?[]const u8 = null,
};

/// 验证 Readonly API Key 响应
pub const ValidateReadonlyApiKeyResponse = struct {
    /// 是否有效
    valid: bool = false,

    /// 关联的钱包地址
    address: ?[]const u8 = null,

    /// 过期时间
    expires_at: ?[]const u8 = null,
};

// ============================================================================
// 流动性奖励类型 (Liquidity Rewards)
// ============================================================================

/// 用户收益记录
pub const UserEarning = struct {
    /// 日期
    date: []const u8 = "",

    /// 条件 ID (市场 ID)
    condition_id: []const u8 = "",

    /// 资产地址
    asset_address: []const u8 = "",

    /// 做市商地址
    maker_address: []const u8 = "",

    /// 收益金额
    earnings: f64 = 0,

    /// 资产费率
    asset_rate: f64 = 0,
};

/// 用户收益查询参数
pub const UserEarningsParams = struct {
    /// 日期 (格式: YYYY-MM-DD)
    date: ?[]const u8 = null,

    /// 条件 ID (可选)
    condition_id: ?[]const u8 = null,
};

/// 用户总收益响应
pub const UserTotalEarningsResponse = struct {
    /// 总收益
    total_earnings: f64 = 0,

    /// 日期
    date: []const u8 = "",

    /// 明细列表
    earnings: []const UserEarning = &.{},
};

/// 奖励百分比响应
pub const RewardPercentagesResponse = struct {
    /// 做市商百分比
    maker_percentage: f64 = 0,

    /// 吃单者百分比
    taker_percentage: f64 = 0,

    /// 协议费率百分比
    protocol_fee_percentage: f64 = 0,
};

/// 奖励配置
pub const RewardsConfig = struct {
    /// 资产地址
    asset_address: []const u8 = "",

    /// 开始日期
    start_date: []const u8 = "",

    /// 结束日期
    end_date: []const u8 = "",

    /// 每日费率
    rate_per_day: f64 = 0,

    /// 总奖励
    total_rewards: f64 = 0,
};

/// 市场奖励信息
pub const MarketReward = struct {
    /// 条件 ID
    condition_id: []const u8 = "",

    /// 问题
    question: []const u8 = "",

    /// 市场 slug
    market_slug: []const u8 = "",

    /// 事件 slug
    event_slug: []const u8 = "",

    /// 图片 URL
    image: []const u8 = "",

    /// 奖励最大价差
    rewards_max_spread: f64 = 0,

    /// 奖励最小数量
    rewards_min_size: f64 = 0,

    /// 代币列表 (JSON 数组)
    tokens: ?[]const u8 = null,

    /// 奖励配置列表
    rewards_config: []const RewardsConfig = &.{},
};

/// 当前市场奖励列表响应
pub const CurrentRewardsResponse = struct {
    /// 市场奖励列表
    markets: []const MarketReward = &.{},
};

/// 原始市场奖励响应
pub const RawMarketRewardResponse = struct {
    /// 条件 ID
    condition_id: []const u8 = "",

    /// 奖励数据 (JSON 格式)
    data: ?[]const u8 = null,

    /// 奖励配置
    rewards_config: []const RewardsConfig = &.{},
};

/// 用户市场收益配置响应
pub const UserEarningsAndMarketsConfigResponse = struct {
    /// 用户收益列表
    earnings: []const UserEarning = &.{},

    /// 市场奖励配置
    markets: []const MarketReward = &.{},

    /// 总收益
    total_earnings: f64 = 0,
};

// ============================================================================
// 测试
// ============================================================================

test "OrderScoringParams.toQueryParams" {
    var buf: [256]u8 = undefined;
    const params = OrderScoringParams{ .order_id = "order-123" };
    const query = try params.toQueryParams(&buf);
    try std.testing.expectEqualStrings("orderId=order-123", query);
}

test "OrderScoringResult defaults" {
    const result = OrderScoringResult{};
    try std.testing.expectEqualStrings("", result.order_id);
    try std.testing.expect(!result.scoring);
}

test "MarketTradeEvent defaults" {
    const event = MarketTradeEvent{};
    try std.testing.expect(event.id == null);
    try std.testing.expect(event.price == null);
    try std.testing.expect(event.side == null);
}

test "FeeRateResponse defaults" {
    const response = FeeRateResponse{};
    try std.testing.expectEqualStrings("0", response.fee_rate_bps);
}

test "ApiKeyInfo struct" {
    const info = ApiKeyInfo{
        .api_key = "test-key",
        .is_active = true,
    };
    try std.testing.expectEqualStrings("test-key", info.api_key);
    try std.testing.expect(info.is_active);
}

test "ClosedOnlyModeResponse defaults" {
    const response = ClosedOnlyModeResponse{};
    try std.testing.expect(!response.closed_only);
}

test "PriceResponse struct" {
    const response = PriceResponse{
        .token_id = "token-123",
        .price = "0.65",
    };
    try std.testing.expectEqualStrings("token-123", response.token_id);
    try std.testing.expectEqualStrings("0.65", response.price);
}

test "ReadonlyApiKeyInfo defaults" {
    const info = ReadonlyApiKeyInfo{};
    try std.testing.expectEqualStrings("", info.api_key);
    try std.testing.expect(info.is_active);
}

test "CreateReadonlyApiKeyParams defaults" {
    const params = CreateReadonlyApiKeyParams{};
    try std.testing.expect(params.description == null);
    try std.testing.expect(params.expires_at == null);
}

test "ValidateReadonlyApiKeyResponse defaults" {
    const response = ValidateReadonlyApiKeyResponse{};
    try std.testing.expect(!response.valid);
    try std.testing.expect(response.address == null);
}

test "UserEarning defaults" {
    const earning = UserEarning{};
    try std.testing.expectEqualStrings("", earning.date);
    try std.testing.expectEqualStrings("", earning.condition_id);
    try std.testing.expectEqual(@as(f64, 0), earning.earnings);
}

test "RewardsConfig defaults" {
    const config = RewardsConfig{};
    try std.testing.expectEqualStrings("", config.asset_address);
    try std.testing.expectEqual(@as(f64, 0), config.rate_per_day);
}

test "MarketReward defaults" {
    const reward = MarketReward{};
    try std.testing.expectEqualStrings("", reward.condition_id);
    try std.testing.expectEqual(@as(f64, 0), reward.rewards_max_spread);
}

test "UserTotalEarningsResponse defaults" {
    const response = UserTotalEarningsResponse{};
    try std.testing.expectEqual(@as(f64, 0), response.total_earnings);
}

test "RewardPercentagesResponse defaults" {
    const response = RewardPercentagesResponse{};
    try std.testing.expectEqual(@as(f64, 0), response.maker_percentage);
}
