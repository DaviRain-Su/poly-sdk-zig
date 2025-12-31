//! 订单金额和价格计算
//!
//! 提供订单金额计算功能：
//! - Maker/Taker 金额计算
//! - 价格舍入到 tick size
//! - Decimal 到 u256 转换
//! - Token ID 解析

const std = @import("std");
const root = @import("../root.zig");

const Decimal = root.types.Decimal;
const types = @import("types.zig");
const Side = types.Side;
const TickSize = types.TickSize;
const USDC_DECIMALS = types.USDC_DECIMALS;
const CT_DECIMALS = types.CT_DECIMALS;

/// 计算错误
pub const CalculatorError = error{
    /// 无效的价格（必须在 0 到 1 之间）
    InvalidPrice,
    /// 无效的数量（必须大于 0）
    InvalidSize,
    /// 无效的 Token ID
    InvalidTokenId,
    /// 数值溢出
    Overflow,
    /// 精度损失
    PrecisionLoss,
};

/// 计算 Maker 金额
///
/// BUY: maker_amount = price * size (支付 USDC)
/// SELL: maker_amount = size (支付 token)
///
/// 返回值是以最小单位 (10^-6) 表示的金额
pub fn calculateMakerAmount(side: Side, size: Decimal, price: Decimal) CalculatorError!u256 {
    return switch (side) {
        .BUY => {
            // 买入：支付 USDC = price * size
            const amount = size.mul(price);
            return decimalToU256(amount, USDC_DECIMALS);
        },
        .SELL => {
            // 卖出：支付 token = size
            return decimalToU256(size, CT_DECIMALS);
        },
    };
}

/// 计算 Taker 金额
///
/// BUY: taker_amount = size (获得 token)
/// SELL: taker_amount = price * size (获得 USDC)
///
/// 返回值是以最小单位 (10^-6) 表示的金额
pub fn calculateTakerAmount(side: Side, size: Decimal, price: Decimal) CalculatorError!u256 {
    return switch (side) {
        .BUY => {
            // 买入：获得 token = size
            return decimalToU256(size, CT_DECIMALS);
        },
        .SELL => {
            // 卖出：获得 USDC = price * size
            const amount = size.mul(price);
            return decimalToU256(amount, USDC_DECIMALS);
        },
    };
}

/// 将 Decimal 转换为 u256（以指定小数位数）
///
/// 例如: Decimal "100.5" 转换为 6 位小数 = 100500000
pub fn decimalToU256(value: Decimal, decimals: u8) CalculatorError!u256 {
    // 确保值为正
    if (value.mantissa < 0) {
        return CalculatorError.InvalidSize;
    }

    const mantissa: u128 = @intCast(value.mantissa);
    const scale = value.scale;

    if (scale <= decimals) {
        // 需要乘以 10^(decimals - scale)
        const multiplier = std.math.pow(u128, 10, decimals - scale);
        const result = std.math.mul(u128, mantissa, multiplier) catch {
            return CalculatorError.Overflow;
        };
        return @as(u256, result);
    } else {
        // 需要除以 10^(scale - decimals)，可能有精度损失
        const divisor = std.math.pow(u128, 10, scale - decimals);
        return @as(u256, mantissa / divisor);
    }
}

/// 将 u256 转换为 Decimal（以指定小数位数）
pub fn u256ToDecimal(value: u256, decimals: u8) Decimal {
    // 确保不会溢出 i128
    const max_i128: u256 = @intCast(std.math.maxInt(i128));
    if (value > max_i128) {
        // 如果溢出，尝试缩小（会损失精度）
        const divisor: u256 = std.math.pow(u256, 10, decimals);
        const reduced = value / divisor;
        if (reduced > max_i128) {
            return Decimal.fromParts(std.math.maxInt(i128), 0);
        }
        return Decimal.fromParts(@intCast(reduced), 0);
    }
    return Decimal.fromParts(@intCast(value), decimals);
}

/// 将价格舍入到 tick size
///
/// 价格必须是 tick size 的整数倍
pub fn roundToTickSize(price: Decimal, tick_size: TickSize) Decimal {
    const tick = tick_size.toDecimal();
    const tick_decimals = tick_size.decimals();

    // price / tick
    const scaled_price = price.rescale(tick_decimals);
    const scaled_tick = tick.rescale(tick_decimals);

    // 整数除法
    const quotient = @divTrunc(scaled_price.mantissa, scaled_tick.mantissa);

    // 重新构建
    return Decimal.fromParts(quotient * scaled_tick.mantissa, tick_decimals);
}

/// 解析 Token ID 字符串为 u256
pub fn parseTokenId(token_id: []const u8) CalculatorError!u256 {
    if (token_id.len == 0) {
        return CalculatorError.InvalidTokenId;
    }

    var result: u256 = 0;
    for (token_id) |c| {
        if (c < '0' or c > '9') {
            return CalculatorError.InvalidTokenId;
        }
        const digit: u256 = c - '0';
        result = std.math.mul(u256, result, 10) catch {
            return CalculatorError.Overflow;
        };
        result = std.math.add(u256, result, digit) catch {
            return CalculatorError.Overflow;
        };
    }
    return result;
}

/// 验证价格是否有效（0 < price < 1）
pub fn validatePrice(price: Decimal) CalculatorError!void {
    if (price.mantissa <= 0) {
        return CalculatorError.InvalidPrice;
    }

    // price < 1 (compare returns -1 if self < other)
    const one = Decimal.ONE;
    if (price.compare(one) >= 0) {
        return CalculatorError.InvalidPrice;
    }
}

/// 验证数量是否有效（size > 0）
pub fn validateSize(size: Decimal) CalculatorError!void {
    if (size.mantissa <= 0) {
        return CalculatorError.InvalidSize;
    }
}

/// 生成随机 salt
pub fn generateSalt() u256 {
    var buf: [32]u8 = undefined;
    std.crypto.random.bytes(&buf);
    return std.mem.readInt(u256, &buf, .big);
}

// ============================================================================
// 测试
// ============================================================================

test "calculateMakerAmount BUY" {
    // 买入 100 个 token，价格 0.65
    // maker_amount = 0.65 * 100 = 65 USDC = 65000000
    const size = try Decimal.fromString("100");
    const price = try Decimal.fromString("0.65");

    const maker_amount = try calculateMakerAmount(.BUY, size, price);
    try std.testing.expectEqual(@as(u256, 65_000_000), maker_amount);
}

test "calculateMakerAmount SELL" {
    // 卖出 100 个 token
    // maker_amount = 100 tokens = 100000000
    const size = try Decimal.fromString("100");
    const price = try Decimal.fromString("0.65");

    const maker_amount = try calculateMakerAmount(.SELL, size, price);
    try std.testing.expectEqual(@as(u256, 100_000_000), maker_amount);
}

test "calculateTakerAmount BUY" {
    // 买入 100 个 token
    // taker_amount = 100 tokens = 100000000
    const size = try Decimal.fromString("100");
    const price = try Decimal.fromString("0.65");

    const taker_amount = try calculateTakerAmount(.BUY, size, price);
    try std.testing.expectEqual(@as(u256, 100_000_000), taker_amount);
}

test "calculateTakerAmount SELL" {
    // 卖出 100 个 token，价格 0.65
    // taker_amount = 0.65 * 100 = 65 USDC = 65000000
    const size = try Decimal.fromString("100");
    const price = try Decimal.fromString("0.65");

    const taker_amount = try calculateTakerAmount(.SELL, size, price);
    try std.testing.expectEqual(@as(u256, 65_000_000), taker_amount);
}

test "decimalToU256" {
    // 100.5 with 6 decimals = 100500000
    const d1 = try Decimal.fromString("100.5");
    const r1 = try decimalToU256(d1, 6);
    try std.testing.expectEqual(@as(u256, 100_500_000), r1);

    // 0.65 with 6 decimals = 650000
    const d2 = try Decimal.fromString("0.65");
    const r2 = try decimalToU256(d2, 6);
    try std.testing.expectEqual(@as(u256, 650_000), r2);

    // 1 with 6 decimals = 1000000
    const d3 = Decimal.ONE;
    const r3 = try decimalToU256(d3, 6);
    try std.testing.expectEqual(@as(u256, 1_000_000), r3);
}

test "u256ToDecimal" {
    // 65000000 with 6 decimals = 65.0
    const d1 = u256ToDecimal(65_000_000, 6);
    try std.testing.expectEqual(@as(i128, 65_000_000), d1.mantissa);
    try std.testing.expectEqual(@as(u8, 6), d1.scale);
}

test "roundToTickSize" {
    // 0.654 rounded to 0.01 tick = 0.65
    const price1 = try Decimal.fromString("0.654");
    const rounded1 = roundToTickSize(price1, .@"0.01");
    try std.testing.expectEqual(@as(i128, 65), rounded1.mantissa);
    try std.testing.expectEqual(@as(u8, 2), rounded1.scale);

    // 0.6567 rounded to 0.001 tick = 0.656
    const price2 = try Decimal.fromString("0.6567");
    const rounded2 = roundToTickSize(price2, .@"0.001");
    try std.testing.expectEqual(@as(i128, 656), rounded2.mantissa);
    try std.testing.expectEqual(@as(u8, 3), rounded2.scale);
}

test "parseTokenId" {
    const id1 = try parseTokenId("123456789");
    try std.testing.expectEqual(@as(u256, 123456789), id1);

    const id2 = try parseTokenId("0");
    try std.testing.expectEqual(@as(u256, 0), id2);

    try std.testing.expectError(CalculatorError.InvalidTokenId, parseTokenId(""));
    try std.testing.expectError(CalculatorError.InvalidTokenId, parseTokenId("abc"));
}

test "validatePrice" {
    try validatePrice(try Decimal.fromString("0.5"));
    try validatePrice(try Decimal.fromString("0.01"));
    try validatePrice(try Decimal.fromString("0.99"));

    try std.testing.expectError(CalculatorError.InvalidPrice, validatePrice(Decimal.ZERO));
    try std.testing.expectError(CalculatorError.InvalidPrice, validatePrice(Decimal.ONE));
    try std.testing.expectError(CalculatorError.InvalidPrice, validatePrice(try Decimal.fromString("1.5")));
}

test "validateSize" {
    try validateSize(try Decimal.fromString("100"));
    try validateSize(try Decimal.fromString("0.001"));

    try std.testing.expectError(CalculatorError.InvalidSize, validateSize(Decimal.ZERO));
}

test "generateSalt" {
    const salt1 = generateSalt();
    const salt2 = generateSalt();

    // 两个随机 salt 应该不同
    try std.testing.expect(salt1 != salt2);
}
