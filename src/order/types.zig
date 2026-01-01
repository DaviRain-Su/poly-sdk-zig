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
    /// 金额 (BUY: USDC 金额, SELL: token 数量)
    amount: Decimal,
    /// 交易方向
    side: Side,
    /// 费率 (基点，可选)
    fee_rate_bps: u16 = 0,
    /// 最大滑点 (可选，默认无限制，例如 0.05 = 5%)
    max_slippage: ?Decimal = null,
    /// 指定价格 (可选，不指定则自动计算)
    price: ?Decimal = null,
    /// 过期时间 (Unix 时间戳，可选)
    expiration: u64 = 0,
    /// Nonce (可选)
    nonce: u64 = 0,
    /// 接单者地址 (可选)
    taker: ?[20]u8 = null,
};

/// 市价单选项
pub const MarketOrderOptions = struct {
    /// 订单有效期类型 (FOK 或 FAK)
    time_in_force: TimeInForce = .FOK,
    /// 价格精度
    tick_size: TickSize = .@"0.01",
    /// 是否为 Neg Risk 市场
    neg_risk: bool = false,
    /// 签名类型
    signature_type: SignatureType = .EOA,
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

    /// 格式化地址为 EIP-55 checksum 格式的 0x hex 字符串
    ///
    /// EIP-55 规范：
    /// 1. 将地址转换为小写十六进制（不含 0x 前缀）
    /// 2. 计算小写地址的 keccak256 哈希
    /// 3. 对于地址中的每个字符：如果是字母 (a-f) 且对应的哈希半字节 >= 8，则大写
    fn formatAddress(bytes: [20]u8, buffer: *[42]u8) void {
        buffer[0] = '0';
        buffer[1] = 'x';
        const hex_chars = "0123456789abcdef";

        // 首先生成小写的十六进制地址（用于 keccak256 哈希）
        var addr_hex: [40]u8 = undefined;
        for (bytes, 0..) |byte, i| {
            addr_hex[i * 2] = hex_chars[byte >> 4];
            addr_hex[i * 2 + 1] = hex_chars[byte & 0x0F];
        }

        // 计算 keccak256(lowercase_hex_address)
        const hash = root.crypto.keccak256(&addr_hex);

        // 根据哈希值决定每个字符的大小写
        for (0..40) |i| {
            const char = addr_hex[i];
            if (char >= 'a' and char <= 'f') {
                // 获取哈希中对应的半字节
                const hash_byte = hash[i / 2];
                const hash_nibble: u4 = if (i % 2 == 0) @truncate(hash_byte >> 4) else @truncate(hash_byte & 0x0F);
                // 如果哈希半字节 >= 8，则大写
                if (hash_nibble >= 8) {
                    buffer[2 + i] = char - 32; // 转换为大写
                } else {
                    buffer[2 + i] = char;
                }
            } else {
                buffer[2 + i] = char;
            }
        }
    }

    /// 格式化 u256 为十进制字符串
    fn formatU256(value: u256, buffer: []u8) []const u8 {
        if (value == 0) {
            buffer[0] = '0';
            return buffer[0..1];
        }

        var v = value;
        var len: usize = 0;

        // 计算位数
        var temp = value;
        while (temp > 0) : (temp /= 10) {
            len += 1;
        }

        // 反向填充
        var i: usize = len;
        while (v > 0) : (v /= 10) {
            i -= 1;
            buffer[i] = @as(u8, @intCast(v % 10)) + '0';
        }

        return buffer[0..len];
    }

    /// 转换为 API 请求格式的 JSON 对象
    ///
    /// 返回用于 POST /order 请求的 OrderData 结构。
    /// 注意：返回的结构引用内部缓冲区，需要立即使用或复制。
    ///
    /// 重要：salt 作为 JSON number (u64) 序列化，与官方实现一致。
    pub fn toOrderData(self: *const Self, buffers: *OrderDataBuffers) OrderDataView {
        // 格式化各字段
        const token_id_str = formatU256(self.token_id, &buffers.token_id);
        const maker_amount_str = formatU256(self.maker_amount, &buffers.maker_amount);
        const taker_amount_str = formatU256(self.taker_amount, &buffers.taker_amount);
        const expiration_str = formatU256(self.expiration, &buffers.expiration);
        const nonce_str = formatU256(self.nonce, &buffers.nonce);
        const fee_rate_str = formatU256(self.fee_rate_bps, &buffers.fee_rate_bps);

        formatAddress(self.maker, &buffers.maker);
        formatAddress(self.signer, &buffers.signer);
        formatAddress(self.taker, &buffers.taker);

        var sig_buf: [132]u8 = undefined;
        const sig_hex = self.getSignatureHex(&sig_buf);
        @memcpy(&buffers.signature, sig_hex);

        return OrderDataView{
            // salt 作为数字输出，与 Rust/Python 实现一致
            // API 要求 salt 是 JSON number，不是字符串
            .salt = @truncate(self.salt),
            .maker = &buffers.maker,
            .signer = &buffers.signer,
            .taker = &buffers.taker,
            .tokenId = token_id_str,
            .makerAmount = maker_amount_str,
            .takerAmount = taker_amount_str,
            .expiration = expiration_str,
            .nonce = nonce_str,
            .feeRateBps = fee_rate_str,
            .side = self.side.toString(),
            .signatureType = @intFromEnum(self.signature_type),
            .signature = &buffers.signature,
        };
    }

    /// OrderData 缓冲区
    pub const OrderDataBuffers = struct {
        maker: [42]u8 = undefined,
        signer: [42]u8 = undefined,
        taker: [42]u8 = undefined,
        token_id: [78]u8 = undefined,
        maker_amount: [78]u8 = undefined,
        taker_amount: [78]u8 = undefined,
        expiration: [78]u8 = undefined,
        nonce: [78]u8 = undefined,
        fee_rate_bps: [78]u8 = undefined,
        signature: [132]u8 = undefined,
    };

    /// OrderData 视图（用于 JSON 序列化）
    ///
    /// 注意: salt 是 u64 (JSON number)，与官方 Python/Rust 实现一致。
    /// 其他大数字段使用字符串表示。
    pub const OrderDataView = struct {
        /// Salt - 序列化为 JSON number (u64)
        salt: u64,
        maker: []const u8,
        signer: []const u8,
        taker: []const u8,
        tokenId: []const u8,
        makerAmount: []const u8,
        takerAmount: []const u8,
        expiration: []const u8,
        nonce: []const u8,
        feeRateBps: []const u8,
        side: []const u8,
        signatureType: u8,
        signature: []const u8,
    };
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

test "SignedOrder.formatU256" {
    var buf: [78]u8 = undefined;

    // 测试 0
    const zero = SignedOrder.formatU256(0, &buf);
    try std.testing.expectEqualStrings("0", zero);

    // 测试小数
    const small = SignedOrder.formatU256(12345, &buf);
    try std.testing.expectEqualStrings("12345", small);

    // 测试大数
    const large = SignedOrder.formatU256(100_000_000, &buf);
    try std.testing.expectEqualStrings("100000000", large);
}

test "SignedOrder.formatAddress EIP-55 checksum" {
    var buf: [42]u8 = undefined;

    // 测试一个已知地址的 EIP-55 checksum
    // 地址: 0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed
    // 这是 EIP-55 规范中的示例地址
    const addr1: [20]u8 = [_]u8{
        0x5a, 0xAe, 0xb6, 0x05, 0x3F, 0x3E, 0x94, 0xC9, 0xb9, 0xA0,
        0x9f, 0x33, 0x66, 0x94, 0x35, 0xE7, 0xEf, 0x1B, 0xeA, 0xed,
    };
    SignedOrder.formatAddress(addr1, &buf);
    try std.testing.expectEqualStrings("0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed", &buf);

    // 测试零地址（全部小写，因为没有字母需要大写）
    const zero_addr: [20]u8 = [_]u8{0} ** 20;
    SignedOrder.formatAddress(zero_addr, &buf);
    try std.testing.expectEqualStrings("0x0000000000000000000000000000000000000000", &buf);

    // 测试另一个已知地址
    // 0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359
    const addr2: [20]u8 = [_]u8{
        0xfB, 0x69, 0x16, 0x09, 0x5c, 0xa1, 0xdf, 0x60, 0xbB, 0x79,
        0xCe, 0x92, 0xcE, 0x3E, 0xa7, 0x4c, 0x37, 0xc5, 0xd3, 0x59,
    };
    SignedOrder.formatAddress(addr2, &buf);
    try std.testing.expectEqualStrings("0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359", &buf);
}
