// Gamma API 类型定义
//
// Gamma API 是 Polymarket 的市场元数据 API
// Base URL: https://gamma-api.polymarket.com

const std = @import("std");

// ============================================================================
// Gamma Market 类型
// ============================================================================

/// Gamma 市场信息
pub const GammaMarket = struct {
    /// 市场 ID
    id: []const u8 = "",

    /// 问题
    question: []const u8 = "",

    /// 描述
    description: []const u8 = "",

    /// 条件 ID
    condition_id: []const u8 = "",

    /// 是否活跃
    active: bool = false,

    /// 是否已关闭
    closed: bool = false,

    /// 是否已归档
    archived: bool = false,

    /// 是否已资助
    funded: bool = false,

    /// 结束日期
    end_date: []const u8 = "",

    /// 结果选项 (JSON 数组字符串)
    outcomes: []const u8 = "[]",

    /// 结果价格 (JSON 数组字符串)
    outcome_prices: []const u8 = "[]",

    /// CLOB Token IDs (JSON 数组字符串)
    clob_token_ids: []const u8 = "[]",

    /// 交易量
    volume: f64 = 0,

    /// 价差
    spread: f64 = 0,

    /// 奖励最小数量
    rewards_min_size: f64 = 0,

    /// 奖励最大价差
    rewards_max_spread: f64 = 0,

    /// 市场 slug
    slug: []const u8 = "",

    /// 图片 URL
    image: []const u8 = "",

    /// 图标 URL
    icon: []const u8 = "",

    /// 创建时间
    created_at: []const u8 = "",

    /// 更新时间
    updated_at: []const u8 = "",
};

/// 标签
pub const Tag = struct {
    /// 标签 ID
    id: []const u8 = "",

    /// 标签名称
    label: []const u8 = "",

    /// 标签 slug
    slug: []const u8 = "",
};

/// Gamma 事件信息
pub const GammaEvent = struct {
    /// 事件 ID
    id: []const u8 = "",

    /// 股票代号
    ticker: []const u8 = "",

    /// 事件 slug
    slug: []const u8 = "",

    /// 标题
    title: []const u8 = "",

    /// 描述
    description: []const u8 = "",

    /// 是否活跃
    active: bool = false,

    /// 是否已关闭
    closed: bool = false,

    /// 是否已归档
    archived: bool = false,

    /// 是否新建
    new: bool = false,

    /// 是否精选
    featured: bool = false,

    /// 是否受限
    restricted: bool = false,

    /// 结束日期
    end_date: []const u8 = "",

    /// 图片 URL
    image: []const u8 = "",

    /// 图标 URL
    icon: []const u8 = "",

    /// 创建时间
    created_at: []const u8 = "",

    /// 更新时间
    updated_at: []const u8 = "",

    /// 关联的市场列表 (在嵌套响应中)
    /// 注意: 这是可选的，因为不是所有响应都包含
    markets: ?[]const GammaMarket = null,

    /// 标签列表
    tags: ?[]const Tag = null,
};

// ============================================================================
// 查询参数
// ============================================================================

/// Gamma 市场查询参数
pub const GammaMarketsParams = struct {
    /// 是否活跃
    active: ?bool = null,

    /// 是否已关闭
    closed: ?bool = null,

    /// 是否已归档
    archived: ?bool = null,

    /// 返回数量限制
    limit: ?u32 = null,

    /// 分页偏移
    offset: ?u32 = null,

    /// 是否启用订单簿筛选
    enable_order_book: ?bool = null,

    /// 按 CLOB Token ID 查询
    clob_token_ids: ?[]const u8 = null,

    /// 按条件 ID 查询
    condition_id: ?[]const u8 = null,

    /// 按 slug 查询
    slug: ?[]const u8 = null,

    /// 转换为查询字符串
    pub fn toQueryString(self: GammaMarketsParams, buf: []u8) ![]const u8 {
        var stream = std.io.fixedBufferStream(buf);
        var writer = stream.writer();
        var first = true;

        if (self.active) |v| {
            if (!first) try writer.writeByte('&');
            try writer.print("active={}", .{v});
            first = false;
        }
        if (self.closed) |v| {
            if (!first) try writer.writeByte('&');
            try writer.print("closed={}", .{v});
            first = false;
        }
        if (self.archived) |v| {
            if (!first) try writer.writeByte('&');
            try writer.print("archived={}", .{v});
            first = false;
        }
        if (self.limit) |v| {
            if (!first) try writer.writeByte('&');
            try writer.print("limit={d}", .{v});
            first = false;
        }
        if (self.offset) |v| {
            if (!first) try writer.writeByte('&');
            try writer.print("offset={d}", .{v});
            first = false;
        }
        if (self.enable_order_book) |v| {
            if (!first) try writer.writeByte('&');
            try writer.print("enableOrderBook={}", .{v});
            first = false;
        }
        if (self.clob_token_ids) |v| {
            if (!first) try writer.writeByte('&');
            try writer.print("clob_token_ids={s}", .{v});
            first = false;
        }
        if (self.condition_id) |v| {
            if (!first) try writer.writeByte('&');
            try writer.print("condition_id={s}", .{v});
            first = false;
        }
        if (self.slug) |v| {
            if (!first) try writer.writeByte('&');
            try writer.print("slug={s}", .{v});
            first = false;
        }

        return buf[0..stream.pos];
    }
};

/// Gamma 事件查询参数
pub const GammaEventsParams = struct {
    /// 是否活跃
    active: ?bool = null,

    /// 是否已关闭
    closed: ?bool = null,

    /// 是否已归档
    archived: ?bool = null,

    /// 是否精选
    featured: ?bool = null,

    /// 返回数量限制
    limit: ?u32 = null,

    /// 分页偏移
    offset: ?u32 = null,

    /// 按 slug 查询
    slug: ?[]const u8 = null,

    /// 按标签查询
    tag: ?[]const u8 = null,

    /// 转换为查询字符串
    pub fn toQueryString(self: GammaEventsParams, buf: []u8) ![]const u8 {
        var stream = std.io.fixedBufferStream(buf);
        var writer = stream.writer();
        var first = true;

        if (self.active) |v| {
            if (!first) try writer.writeByte('&');
            try writer.print("active={}", .{v});
            first = false;
        }
        if (self.closed) |v| {
            if (!first) try writer.writeByte('&');
            try writer.print("closed={}", .{v});
            first = false;
        }
        if (self.archived) |v| {
            if (!first) try writer.writeByte('&');
            try writer.print("archived={}", .{v});
            first = false;
        }
        if (self.featured) |v| {
            if (!first) try writer.writeByte('&');
            try writer.print("featured={}", .{v});
            first = false;
        }
        if (self.limit) |v| {
            if (!first) try writer.writeByte('&');
            try writer.print("limit={d}", .{v});
            first = false;
        }
        if (self.offset) |v| {
            if (!first) try writer.writeByte('&');
            try writer.print("offset={d}", .{v});
            first = false;
        }
        if (self.slug) |v| {
            if (!first) try writer.writeByte('&');
            try writer.print("slug={s}", .{v});
            first = false;
        }
        if (self.tag) |v| {
            if (!first) try writer.writeByte('&');
            try writer.print("tag={s}", .{v});
            first = false;
        }

        return buf[0..stream.pos];
    }
};

// ============================================================================
// 测试
// ============================================================================

test "GammaMarket defaults" {
    const market = GammaMarket{};
    try std.testing.expectEqualStrings("", market.id);
    try std.testing.expectEqualStrings("", market.question);
    try std.testing.expect(!market.active);
    try std.testing.expect(!market.closed);
}

test "GammaEvent defaults" {
    const event = GammaEvent{};
    try std.testing.expectEqualStrings("", event.id);
    try std.testing.expectEqualStrings("", event.title);
    try std.testing.expect(!event.active);
    try std.testing.expect(!event.featured);
}

test "Tag defaults" {
    const tag = Tag{};
    try std.testing.expectEqualStrings("", tag.id);
    try std.testing.expectEqualStrings("", tag.label);
}

test "GammaMarketsParams.toQueryString" {
    var buf: [512]u8 = undefined;

    // 测试空参数
    const empty_params = GammaMarketsParams{};
    const empty_query = try empty_params.toQueryString(&buf);
    try std.testing.expectEqualStrings("", empty_query);

    // 测试带参数
    const params = GammaMarketsParams{
        .active = true,
        .limit = 10,
    };
    const query = try params.toQueryString(&buf);
    try std.testing.expectEqualStrings("active=true&limit=10", query);
}

test "GammaEventsParams.toQueryString" {
    var buf: [512]u8 = undefined;

    const params = GammaEventsParams{
        .active = true,
        .featured = true,
        .limit = 5,
    };
    const query = try params.toQueryString(&buf);
    try std.testing.expectEqualStrings("active=true&featured=true&limit=5", query);
}
