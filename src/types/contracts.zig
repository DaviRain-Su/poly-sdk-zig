//! Polymarket 合约配置
//!
//! 提供 Polygon 网络上 Polymarket 合约的地址配置。
//!
//! 支持:
//! - Polygon 主网 (Chain ID: 137)
//! - Polygon Amoy 测试网 (Chain ID: 80002)
//! - 标准市场和 Neg Risk 市场
//!
//! 示例:
//! ```zig
//! const contracts = @import("types/contracts.zig");
//!
//! // 获取主网配置
//! const config = contracts.getConfig(.polygon, false);
//!
//! // 获取 Neg Risk 配置
//! const neg_risk_config = contracts.getConfig(.polygon, true);
//! ```

const std = @import("std");

/// 合约配置
///
/// 包含 Polymarket 交易所所需的三个核心合约地址。
pub const ContractConfig = struct {
    /// 订单匹配交易所合约地址 (CTF Exchange)
    exchange: [42]u8,

    /// 抵押品代币合约地址 (USDC ERC20)
    collateral: [42]u8,

    /// 条件代币合约地址 (ERC1155)
    conditional_tokens: [42]u8,

    const Self = @This();

    /// 从字符串字面量创建配置
    pub fn init(
        exchange: *const [42]u8,
        collateral: *const [42]u8,
        conditional_tokens: *const [42]u8,
    ) Self {
        return Self{
            .exchange = exchange.*,
            .collateral = collateral.*,
            .conditional_tokens = conditional_tokens.*,
        };
    }

    /// 获取交易所地址
    pub fn getExchange(self: *const Self) []const u8 {
        return &self.exchange;
    }

    /// 获取抵押品地址
    pub fn getCollateral(self: *const Self) []const u8 {
        return &self.collateral;
    }

    /// 获取条件代币地址
    pub fn getConditionalTokens(self: *const Self) []const u8 {
        return &self.conditional_tokens;
    }
};

/// 链 ID 枚举
pub const Chain = enum(u64) {
    /// Polygon 主网
    polygon = 137,
    /// Polygon Amoy 测试网
    amoy = 80002,

    /// 从整数转换
    pub fn fromChainId(chain_id: u64) ?Chain {
        return switch (chain_id) {
            137 => .polygon,
            80002 => .amoy,
            else => null,
        };
    }

    /// 转换为整数
    pub fn toChainId(self: Chain) u64 {
        return @intFromEnum(self);
    }
};

// =============================================================================
// Polygon 主网配置 (Chain ID: 137)
// =============================================================================

/// Polygon 主网标准市场配置
pub const POLYGON_MAINNET = ContractConfig{
    .exchange = "0x4bFb41d5B3570DeFd03C39a9A4D8dE6Bd8B8982E".*,
    .collateral = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174".*, // USDC
    .conditional_tokens = "0x4D97DCd97eC945f40cF65F87097ACe5EA0476045".*,
};

/// Polygon 主网 Neg Risk 市场配置
pub const POLYGON_MAINNET_NEG_RISK = ContractConfig{
    .exchange = "0xC5d563A36AE78145C45a50134d48A1215220f80a".*,
    .collateral = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174".*, // USDC
    .conditional_tokens = "0x4D97DCd97eC945f40cF65F87097ACe5EA0476045".*,
};

// =============================================================================
// Polygon Amoy 测试网配置 (Chain ID: 80002)
// =============================================================================

/// Polygon Amoy 测试网标准市场配置
pub const AMOY_TESTNET = ContractConfig{
    .exchange = "0xdFE02Eb6733538f8Ea35D585af8DE5958AD99E40".*,
    .collateral = "0x9c4e1703476e875070ee25b56a58b008cfb8fa78".*, // 测试 USDC
    .conditional_tokens = "0x69308FB512518e39F9b16112fA8d994F4e2Bf8bB".*,
};

/// Polygon Amoy 测试网 Neg Risk 市场配置
pub const AMOY_TESTNET_NEG_RISK = ContractConfig{
    .exchange = "0xd91E80cF2E7be2e162c6513ceD06f1dD0dA35296".*,
    .collateral = "0x9c4e1703476e875070ee25b56a58b008cfb8fa78".*, // 测试 USDC
    .conditional_tokens = "0x69308FB512518e39F9b16112fA8d994F4e2Bf8bB".*,
};

// =============================================================================
// 其他地址常量
// =============================================================================

/// Neg Risk Adapter 地址 (主网)
pub const NEG_RISK_ADAPTER_MAINNET = "0xd91E80cF2E7be2e162c6513ceD06f1dD0dA35296";

/// CLOB API 基础 URL (主网)
pub const CLOB_API_MAINNET = "https://clob.polymarket.com";

/// CLOB API 基础 URL (测试网)
pub const CLOB_API_TESTNET = "https://clob-testnet.polymarket.com";

/// Gamma API 基础 URL
pub const GAMMA_API = "https://gamma-api.polymarket.com";

// =============================================================================
// 辅助函数
// =============================================================================

/// 获取合约配置
///
/// 根据链和是否为 Neg Risk 市场返回对应的配置。
pub fn getConfig(chain: Chain, neg_risk: bool) ContractConfig {
    return switch (chain) {
        .polygon => if (neg_risk) POLYGON_MAINNET_NEG_RISK else POLYGON_MAINNET,
        .amoy => if (neg_risk) AMOY_TESTNET_NEG_RISK else AMOY_TESTNET,
    };
}

/// 根据链 ID 获取合约配置
///
/// 如果链 ID 不支持，返回 null。
pub fn getConfigByChainId(chain_id: u64, neg_risk: bool) ?ContractConfig {
    const chain = Chain.fromChainId(chain_id) orelse return null;
    return getConfig(chain, neg_risk);
}

/// 获取 CLOB API URL
pub fn getClobApiUrl(chain: Chain) []const u8 {
    return switch (chain) {
        .polygon => CLOB_API_MAINNET,
        .amoy => CLOB_API_TESTNET,
    };
}

// =============================================================================
// 测试
// =============================================================================

test "ContractConfig basic" {
    const config = POLYGON_MAINNET;

    try std.testing.expectEqualStrings("0x4bFb41d5B3570DeFd03C39a9A4D8dE6Bd8B8982E", config.getExchange());
    try std.testing.expectEqualStrings("0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174", config.getCollateral());
    try std.testing.expectEqualStrings("0x4D97DCd97eC945f40cF65F87097ACe5EA0476045", config.getConditionalTokens());
}

test "Chain enum" {
    try std.testing.expectEqual(@as(u64, 137), Chain.polygon.toChainId());
    try std.testing.expectEqual(@as(u64, 80002), Chain.amoy.toChainId());

    try std.testing.expectEqual(Chain.polygon, Chain.fromChainId(137).?);
    try std.testing.expectEqual(Chain.amoy, Chain.fromChainId(80002).?);
    try std.testing.expectEqual(@as(?Chain, null), Chain.fromChainId(1));
}

test "getConfig polygon mainnet" {
    const config = getConfig(.polygon, false);
    try std.testing.expectEqualStrings("0x4bFb41d5B3570DeFd03C39a9A4D8dE6Bd8B8982E", config.getExchange());
}

test "getConfig polygon neg_risk" {
    const config = getConfig(.polygon, true);
    try std.testing.expectEqualStrings("0xC5d563A36AE78145C45a50134d48A1215220f80a", config.getExchange());
}

test "getConfig amoy" {
    const config = getConfig(.amoy, false);
    try std.testing.expectEqualStrings("0xdFE02Eb6733538f8Ea35D585af8DE5958AD99E40", config.getExchange());
}

test "getConfigByChainId" {
    const config = getConfigByChainId(137, false);
    try std.testing.expect(config != null);
    try std.testing.expectEqualStrings("0x4bFb41d5B3570DeFd03C39a9A4D8dE6Bd8B8982E", config.?.getExchange());

    const invalid = getConfigByChainId(1, false);
    try std.testing.expect(invalid == null);
}

test "getClobApiUrl" {
    try std.testing.expectEqualStrings(CLOB_API_MAINNET, getClobApiUrl(.polygon));
    try std.testing.expectEqualStrings(CLOB_API_TESTNET, getClobApiUrl(.amoy));
}

test "Constants" {
    try std.testing.expectEqualStrings("https://clob.polymarket.com", CLOB_API_MAINNET);
    try std.testing.expectEqualStrings("https://clob-testnet.polymarket.com", CLOB_API_TESTNET);
    try std.testing.expectEqualStrings("https://gamma-api.polymarket.com", GAMMA_API);
}
