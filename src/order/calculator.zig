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

// 导入订单簿类型
const clob_types = @import("../clob/types/mod.zig");
const OrderBookSummary = clob_types.OrderBookSummary;
const OrderSummary = clob_types.OrderSummary;

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
    /// 订单簿深度不足
    InsufficientLiquidity,
    /// 滑点超限
    SlippageExceeded,
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
///
/// 注意: Polymarket CLOB API 要求 salt 是一个 JSON number。
/// Python 实现使用 `round(time.now() * random())`，生成约 10 位数字。
/// 我们模拟类似的范围，生成一个 32 位随机数（0 到 ~4.2 billion）。
pub fn generateSalt() u256 {
    // 生成 32 位随机数，与 Python 实现的范围相近
    // Python: round(timestamp * random()) ≈ 0 to ~1.7 billion
    // 我们使用 u32 范围：0 to ~4.2 billion
    var buf: [4]u8 = undefined;
    std.crypto.random.bytes(&buf);
    return @as(u256, std.mem.readInt(u32, &buf, .big));
}

/// 市价计算结果
pub const MarketPriceResult = struct {
    /// 计算出的平均价格
    price: Decimal,
    /// 可以获得的数量
    filled_size: Decimal,
    /// 需要支付的金额
    total_cost: Decimal,
    /// 是否可以完全成交
    fully_fillable: bool,
};

/// 计算市价单的最优价格
///
/// 根据订单簿深度计算市价单的平均成交价格。
///
/// 参数:
///   - order_book: 订单簿摘要
///   - side: 交易方向 (BUY 遍历 asks, SELL 遍历 bids)
///   - amount: 金额 (BUY: USDC 金额, SELL: token 数量)
///
/// 返回: 市价计算结果，包含平均价格和成交信息
pub fn calculateMarketPrice(
    order_book: *const OrderBookSummary,
    side: Side,
    amount: Decimal,
) CalculatorError!MarketPriceResult {
    // 根据方向选择订单列表
    const orders = switch (side) {
        .BUY => order_book.asks orelse return CalculatorError.InsufficientLiquidity,
        .SELL => order_book.bids orelse return CalculatorError.InsufficientLiquidity,
    };

    if (orders.len == 0) {
        return CalculatorError.InsufficientLiquidity;
    }

    var remaining = amount;
    var total_cost = Decimal.ZERO;
    var filled_size = Decimal.ZERO;

    // 遍历订单簿价格层级
    for (orders) |level| {
        const level_price = Decimal.fromString(level.price) catch continue;
        const level_size = Decimal.fromString(level.size) catch continue;

        if (level_price.mantissa == 0) continue;

        if (side == .BUY) {
            // BUY: remaining 是 USDC 金额，计算能买多少 token
            // cost = price * size, so size = remaining / price
            const max_size_at_level = remaining.div(level_price) catch continue;
            const fill_size = if (max_size_at_level.compare(level_size) <= 0)
                max_size_at_level
            else
                level_size;

            const cost = fill_size.mul(level_price);
            filled_size = filled_size.add(fill_size);
            total_cost = total_cost.add(cost);

            // 更新剩余金额
            remaining = remaining.sub(cost);
        } else {
            // SELL: remaining 是 token 数量
            const fill_size = if (remaining.compare(level_size) <= 0)
                remaining
            else
                level_size;

            const proceeds = fill_size.mul(level_price);
            filled_size = filled_size.add(fill_size);
            total_cost = total_cost.add(proceeds);

            // 更新剩余数量
            remaining = remaining.sub(fill_size);
        }

        // 检查是否已完全满足（使用小的阈值处理浮点误差）
        if (remaining.mantissa <= 0 or remaining.compare(Decimal.fromParts(1, 6)) < 0) {
            remaining = Decimal.ZERO;
            break;
        }
    }

    // 计算平均价格（使用更安全的方法）
    var avg_price = Decimal.ZERO;
    if (filled_size.mantissa > 0) {
        // 归一化数值以避免溢出
        const normalized_cost = total_cost.normalize();
        const normalized_size = filled_size.normalize();

        // 使用较低的精度来避免溢出
        const scaled_cost = normalized_cost.rescale(6);
        const scaled_size = normalized_size.rescale(6);

        if (scaled_size.mantissa != 0) {
            // 直接计算: price = cost / size
            // 结果精度为 6 位小数
            const price_mantissa = @divTrunc(scaled_cost.mantissa * 1_000_000, scaled_size.mantissa);
            avg_price = Decimal.fromParts(price_mantissa, 6);
        }
    }

    return MarketPriceResult{
        .price = avg_price,
        .filled_size = filled_size,
        .total_cost = total_cost,
        .fully_fillable = remaining.mantissa <= 0,
    };
}

/// 验证滑点是否在允许范围内
///
/// 参数:
///   - expected_price: 预期价格
///   - actual_price: 实际价格
///   - max_slippage: 最大允许滑点 (例如 0.05 = 5%)
///   - side: 交易方向
///
/// 返回: 如果滑点超限返回错误
pub fn validateSlippage(
    expected_price: Decimal,
    actual_price: Decimal,
    max_slippage: Decimal,
    side: Side,
) CalculatorError!void {
    // 计算滑点: |actual - expected| / expected
    const diff = if (actual_price.compare(expected_price) >= 0)
        actual_price.sub(expected_price)
    else
        expected_price.sub(actual_price);

    const slippage = diff.div(expected_price) catch return;

    if (slippage.compare(max_slippage) > 0) {
        return CalculatorError.SlippageExceeded;
    }

    // 额外检查: BUY 时实际价格不应高于预期 + 滑点
    // SELL 时实际价格不应低于预期 - 滑点
    const allowance = expected_price.mul(max_slippage);
    switch (side) {
        .BUY => {
            const max_price = expected_price.add(allowance);
            if (actual_price.compare(max_price) > 0) {
                return CalculatorError.SlippageExceeded;
            }
        },
        .SELL => {
            const min_price = expected_price.sub(allowance);
            if (actual_price.compare(min_price) < 0) {
                return CalculatorError.SlippageExceeded;
            }
        },
    }
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

test "calculateMarketPrice BUY" {
    // 模拟订单簿: asks = [0.55: 100, 0.60: 200]
    // 100 tokens @ 0.55 = 55 USDC
    // 200 tokens @ 0.60 = 120 USDC
    // 总计: 300 tokens, 175 USDC
    var asks = [_]OrderSummary{
        .{ .price = "0.55", .size = "100" },
        .{ .price = "0.60", .size = "200" },
    };
    const book = OrderBookSummary{
        .asks = &asks,
    };

    // 买入 55 USDC，预期全部在 0.55 成交，获得 100 tokens
    const result1 = try calculateMarketPrice(&book, .BUY, try Decimal.fromString("55"));
    try std.testing.expect(result1.fully_fillable);
    // 55 / 0.55 = 100 tokens
    try std.testing.expectEqual(@as(i128, 100_000_000), result1.filled_size.rescale(6).mantissa);

    // 买入 100 USDC，跨两个价格层级
    // 第一层: 55 USDC 买 100 tokens
    // 第二层: 45 USDC 买 75 tokens (45 / 0.60)
    // 总计: 175 tokens
    const result2 = try calculateMarketPrice(&book, .BUY, try Decimal.fromString("100"));
    try std.testing.expect(result2.fully_fillable);
    try std.testing.expect(result2.filled_size.mantissa > 0);
}

test "calculateMarketPrice SELL" {
    // 模拟订单簿: bids = [0.50: 100, 0.45: 200]
    var bids = [_]OrderSummary{
        .{ .price = "0.50", .size = "100" },
        .{ .price = "0.45", .size = "200" },
    };
    const book = OrderBookSummary{
        .bids = &bids,
    };

    // 卖出 50 tokens，预期全部在 0.50 成交
    const result1 = try calculateMarketPrice(&book, .SELL, try Decimal.fromString("50"));
    try std.testing.expect(result1.fully_fillable);
    // 50 * 0.50 = 25 USDC
    try std.testing.expectEqual(@as(i128, 25_000_000), result1.total_cost.rescale(6).mantissa);
}

test "calculateMarketPrice insufficient liquidity" {
    const empty_book = OrderBookSummary{};

    // 没有订单应该返回错误
    try std.testing.expectError(
        CalculatorError.InsufficientLiquidity,
        calculateMarketPrice(&empty_book, .BUY, try Decimal.fromString("100")),
    );
}

test "validateSlippage within limit" {
    const expected = try Decimal.fromString("0.50");
    const actual = try Decimal.fromString("0.52");
    const max_slippage = try Decimal.fromString("0.05"); // 5%

    // 4% 滑点，应该通过
    try validateSlippage(expected, actual, max_slippage, .BUY);
}

test "validateSlippage exceeded" {
    const expected = try Decimal.fromString("0.50");
    const actual = try Decimal.fromString("0.60");
    const max_slippage = try Decimal.fromString("0.05"); // 5%

    // 20% 滑点，应该失败
    try std.testing.expectError(
        CalculatorError.SlippageExceeded,
        validateSlippage(expected, actual, max_slippage, .BUY),
    );
}
