//! 订单类型定义
//!
//! 定义订单相关的核心类型，包括：
//! - Side (买/卖)
//! - SignatureType (签名类型)
//! - TickSize (价格精度)
//! - TimeInForce (订单有效期类型)
//! - SignedOrder (签名后的订单)

const std = @import("std");
const root = @import("../root.zig");

const Decimal = root.types.Decimal;
const Address = root.types.Address;
const Signature = root.crypto.Signature;

/// 交易方向
pub const Side = enum(u8) {
    /// 买入
    BUY = 0,
    /// 卖出
    SELL = 1,

    /// 从字符串解析
    pub fn fromString(str: []const u8) ?Side {
        if (std.mem.eql(u8, str, "BUY") or std.mem.eql(u8, str, "buy")) {
            return .BUY;
        } else if (std.mem.eql(u8, str, "SELL") or std.mem.eql(u8, str, "sell")) {
            return .SELL;
        }
        return null;
    }

    /// 转换为字符串
    pub fn toString(self: Side) []const u8 {
        return switch (self) {
            .BUY => "BUY",
            .SELL => "SELL",
        };
    }

    /// 获取相反方向
    pub fn opposite(self: Side) Side {
        return switch (self) {
            .BUY => .SELL,
            .SELL => .BUY,
        };
    }
};

/// 签名类型
pub const SignatureType = enum(u8) {
    /// 外部账户 (MetaMask, 硬件钱包等)
    EOA = 0,
    /// Polymarket 代理钱包 (Email/Magic)
    POLY_PROXY = 1,
    /// Polymarket Gnosis Safe
    POLY_GNOSIS_SAFE = 2,

    /// 从数值解析
    pub fn fromU8(value: u8) ?SignatureType {
        return switch (value) {
            0 => .EOA,
            1 => .POLY_PROXY,
            2 => .POLY_GNOSIS_SAFE,
            else => null,
        };
    }
};

/// 价格精度 (Tick Size)
pub const TickSize = enum {
    /// 0.1 精度
    @"0.1",
    /// 0.01 精度
    @"0.01",
    /// 0.001 精度
    @"0.001",
    /// 0.0001 精度
    @"0.0001",

    /// 转换为 Decimal
    pub fn toDecimal(self: TickSize) Decimal {
        return switch (self) {
            .@"0.1" => Decimal.fromParts(1, 1),
            .@"0.01" => Decimal.fromParts(1, 2),
            .@"0.001" => Decimal.fromParts(1, 3),
            .@"0.0001" => Decimal.fromParts(1, 4),
        };
    }

    /// 获取小数位数
    pub fn decimals(self: TickSize) u8 {
        return switch (self) {
            .@"0.1" => 1,
            .@"0.01" => 2,
            .@"0.001" => 3,
            .@"0.0001" => 4,
        };
    }

    /// 从字符串解析
    pub fn fromString(str: []const u8) ?TickSize {
        if (std.mem.eql(u8, str, "0.1")) return .@"0.1";
        if (std.mem.eql(u8, str, "0.01")) return .@"0.01";
        if (std.mem.eql(u8, str, "0.001")) return .@"0.001";
        if (std.mem.eql(u8, str, "0.0001")) return .@"0.0001";
        return null;
    }
};

/// 订单有效期类型
pub const TimeInForce = enum {
    /// Good Till Cancelled (限价单)
    GTC,
    /// Good Till Date (限价单，指定过期时间)
    GTD,
    /// Fill Or Kill (市价单，全部成交或取消)
    FOK,
    /// Fill And Kill / Immediate Or Cancel (市价单，尽可能成交)
    FAK,
};

/// 订单参数 (用于创建限价单)
pub const OrderArgs = struct {
    /// Token ID
    token_id: []const u8,
    /// 价格 (0 < price < 1)
    price: Decimal,
    /// 数量
    size: Decimal,
    /// 交易方向
    side: Side,
    /// 费率 (基点，可选，默认 0)
    fee_rate_bps: u16 = 0,
    /// 过期时间 (Unix 时间戳，可选，默认 0 = 永不过期)
    expiration: u64 = 0,
    /// Nonce (可选，默认 0)
    nonce: u64 = 0,
    /// 接单者地址 (可选，默认零地址 = 公开订单)
    taker: ?[20]u8 = null,
};

/// 市价单参数
pub const MarketOrderArgs = struct {
    /// Token ID
    token_id: []const u8,
    /// 金额 (USDC)
    amount: Decimal,
    /// 交易方向
    side: Side,
    /// 费率 (基点，可选)
    fee_rate_bps: u16 = 0,
    /// 最大滑点 (可选，默认无限制)
    max_slippage: ?Decimal = null,
};

/// 创建订单选项
pub const CreateOrderOptions = struct {
    /// 价格精度
    tick_size: TickSize = .@"0.01",
    /// 是否为 Neg Risk 市场
    neg_risk: bool = false,
    /// 签名类型
    signature_type: SignatureType = .EOA,
};

/// 签名后的订单
pub const SignedOrder = struct {
    /// 随机盐值
    salt: u256,
    /// 订单创建者地址
    maker: [20]u8,
    /// 签名者地址
    signer: [20]u8,
    /// 接单者地址
    taker: [20]u8,
    /// Token ID (作为 u256)
    token_id: u256,
    /// Maker 金额 (最小单位)
    maker_amount: u256,
    /// Taker 金额 (最小单位)
    taker_amount: u256,
    /// 过期时间戳
    expiration: u256,
    /// Nonce
    nonce: u256,
    /// 费率 (基点)
    fee_rate_bps: u256,
    /// 交易方向
    side: Side,
    /// 签名类型
    signature_type: SignatureType,
    /// EIP-712 签名
    signature: Signature,

    const Self = @This();

    /// 零地址 (公开订单)
    pub const ZERO_ADDRESS: [20]u8 = [_]u8{0} ** 20;

    /// 转换为 EIP-712 Order 结构（用于哈希）
    pub fn toEip712Order(self: *const Self) root.signer.eip712.Order {
        return .{
            .salt = self.salt,
            .maker = self.maker,
            .signer = self.signer,
            .taker = self.taker,
            .token_id = self.token_id,
            .maker_amount = self.maker_amount,
            .taker_amount = self.taker_amount,
            .expiration = self.expiration,
            .nonce = self.nonce,
            .fee_rate_bps = self.fee_rate_bps,
            .side = @intFromEnum(self.side),
            .signature_type = @intFromEnum(self.signature_type),
        };
    }

    /// 获取订单哈希
    pub fn getOrderHash(self: *const Self, chain_id: u64, neg_risk: bool) [32]u8 {
        const eip712_order = self.toEip712Order();
        return root.signer.eip712.hashPolymarketOrder(&eip712_order, chain_id, neg_risk);
    }

    /// 获取签名的 hex 字符串
    pub fn getSignatureHex(self: *const Self, buffer: *[132]u8) []const u8 {
        return self.signature.toHex(buffer);
    }
};

// ============================================================================
// 常量
// ============================================================================

/// USDC 小数位数 (Polygon 上的 USDC 是 6 位)
pub const USDC_DECIMALS: u8 = 6;

/// Conditional Token 小数位数
pub const CT_DECIMALS: u8 = 6;

/// 单位换算: 1 USDC = 10^6 最小单位
pub const USDC_UNIT: u256 = 1_000_000;

/// 单位换算: 1 CT = 10^6 最小单位
pub const CT_UNIT: u256 = 1_000_000;

// ============================================================================
// 测试
// ============================================================================

test "Side" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(Side.BUY));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(Side.SELL));

    try std.testing.expectEqual(Side.BUY, Side.fromString("BUY").?);
    try std.testing.expectEqual(Side.SELL, Side.fromString("sell").?);
    try std.testing.expect(Side.fromString("invalid") == null);

    try std.testing.expectEqualStrings("BUY", Side.BUY.toString());
    try std.testing.expectEqualStrings("SELL", Side.SELL.toString());

    try std.testing.expectEqual(Side.SELL, Side.BUY.opposite());
    try std.testing.expectEqual(Side.BUY, Side.SELL.opposite());
}

test "SignatureType" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(SignatureType.EOA));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(SignatureType.POLY_PROXY));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(SignatureType.POLY_GNOSIS_SAFE));

    try std.testing.expectEqual(SignatureType.EOA, SignatureType.fromU8(0).?);
    try std.testing.expect(SignatureType.fromU8(99) == null);
}

test "TickSize" {
    const tick_01 = TickSize.@"0.1".toDecimal();
    try std.testing.expectEqual(@as(i128, 1), tick_01.mantissa);
    try std.testing.expectEqual(@as(u8, 1), tick_01.scale);

    const tick_001 = TickSize.@"0.01".toDecimal();
    try std.testing.expectEqual(@as(i128, 1), tick_001.mantissa);
    try std.testing.expectEqual(@as(u8, 2), tick_001.scale);

    try std.testing.expectEqual(@as(u8, 2), TickSize.@"0.01".decimals());
    try std.testing.expectEqual(@as(u8, 4), TickSize.@"0.0001".decimals());

    try std.testing.expectEqual(TickSize.@"0.01", TickSize.fromString("0.01").?);
    try std.testing.expect(TickSize.fromString("0.5") == null);
}

test "TimeInForce" {
    _ = TimeInForce.GTC;
    _ = TimeInForce.GTD;
    _ = TimeInForce.FOK;
    _ = TimeInForce.FAK;
}

test "SignedOrder.ZERO_ADDRESS" {
    for (SignedOrder.ZERO_ADDRESS) |byte| {
        try std.testing.expectEqual(@as(u8, 0), byte);
    }
}

test "constants" {
    try std.testing.expectEqual(@as(u8, 6), USDC_DECIMALS);
    try std.testing.expectEqual(@as(u8, 6), CT_DECIMALS);
    try std.testing.expectEqual(@as(u256, 1_000_000), USDC_UNIT);
}
