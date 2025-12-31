//! 订单模块
//!
//! 提供 Polymarket 订单构建和签名功能：
//! - 订单类型定义
//! - 金额和价格计算
//! - 订单构建器
//!
//! ## 快速开始
//!
//! ```zig
//! const poly = @import("poly-sdk-zig");
//! const order = poly.order;
//!
//! // 创建钱包
//! const wallet = try poly.Wallet.fromPrivateKeyHex("0x...");
//!
//! // 创建订单构建器
//! var builder = order.OrderBuilder.init(&wallet, .{ .chain_id = 137 });
//!
//! // 创建限价单
//! const signed_order = try builder.createOrder(.{
//!     .token_id = "123456789",
//!     .price = try poly.Decimal.fromString("0.65"),
//!     .size = try poly.Decimal.fromString("100"),
//!     .side = .BUY,
//! }, .{
//!     .tick_size = .@"0.01",
//!     .neg_risk = false,
//! });
//! ```

const std = @import("std");

/// 订单类型定义
pub const types = @import("types.zig");

/// 金额和价格计算
pub const calculator = @import("calculator.zig");

/// 订单构建器
pub const builder = @import("builder.zig");

// ============================================================================
// 便捷类型导出
// ============================================================================

// 订单类型
pub const Side = types.Side;
pub const SignatureType = types.SignatureType;
pub const TickSize = types.TickSize;
pub const TimeInForce = types.TimeInForce;
pub const OrderArgs = types.OrderArgs;
pub const MarketOrderArgs = types.MarketOrderArgs;
pub const MarketOrderOptions = types.MarketOrderOptions;
pub const CreateOrderOptions = types.CreateOrderOptions;
pub const SignedOrder = types.SignedOrder;

// 常量
pub const USDC_DECIMALS = types.USDC_DECIMALS;
pub const CT_DECIMALS = types.CT_DECIMALS;
pub const USDC_UNIT = types.USDC_UNIT;
pub const CT_UNIT = types.CT_UNIT;

// 计算器
pub const CalculatorError = calculator.CalculatorError;
pub const MarketPriceResult = calculator.MarketPriceResult;
pub const calculateMakerAmount = calculator.calculateMakerAmount;
pub const calculateTakerAmount = calculator.calculateTakerAmount;
pub const calculateMarketPrice = calculator.calculateMarketPrice;
pub const validateSlippage = calculator.validateSlippage;
pub const decimalToU256 = calculator.decimalToU256;
pub const u256ToDecimal = calculator.u256ToDecimal;
pub const roundToTickSize = calculator.roundToTickSize;
pub const parseTokenId = calculator.parseTokenId;
pub const validatePrice = calculator.validatePrice;
pub const validateSize = calculator.validateSize;
pub const generateSalt = calculator.generateSalt;

// 订单构建器
pub const OrderBuilder = builder.OrderBuilder;
pub const OrderBuilderOptions = builder.OrderBuilderOptions;
pub const OrderBuilderError = builder.OrderBuilderError;

// ============================================================================
// 测试
// ============================================================================

test "order module exports" {
    const root = @import("../root.zig");
    const Decimal = root.types.Decimal;

    // 创建钱包
    const wallet = try root.Wallet.fromPrivateKeyHex(
        "0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318",
    );

    // 创建构建器
    const order_builder = OrderBuilder.init(&wallet, .{ .chain_id = 137 });
    try std.testing.expectEqual(@as(u64, 137), order_builder.getChainId());

    // 创建订单
    const order = try order_builder.createOrderWithSalt(.{
        .token_id = "12345",
        .price = try Decimal.fromString("0.5"),
        .size = try Decimal.fromString("100"),
        .side = .BUY,
    }, .{}, 99999);

    try std.testing.expectEqual(@as(u256, 99999), order.salt);
    try std.testing.expectEqual(Side.BUY, order.side);
}

test "order module calculator" {
    const root = @import("../root.zig");
    const Decimal = root.types.Decimal;

    // 测试金额计算
    const size = try Decimal.fromString("100");
    const price = try Decimal.fromString("0.65");

    const maker = try calculateMakerAmount(.BUY, size, price);
    try std.testing.expectEqual(@as(u256, 65_000_000), maker);

    const taker = try calculateTakerAmount(.BUY, size, price);
    try std.testing.expectEqual(@as(u256, 100_000_000), taker);
}

test "order module types" {
    // 测试类型
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(Side.BUY));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(Side.SELL));

    const tick = TickSize.@"0.01".toDecimal();
    try std.testing.expectEqual(@as(u8, 2), tick.scale);
}

test "all submodules" {
    _ = @import("types.zig");
    _ = @import("calculator.zig");
    _ = @import("builder.zig");
}
