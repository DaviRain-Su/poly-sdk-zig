//! 订单构建器
//!
//! 提供订单构建功能：
//! - 创建限价单
//! - 创建市价单（待实现）
//! - 签名订单
//!
//! 示例:
//! ```zig
//! var builder = OrderBuilder.init(&wallet, .{ .chain_id = 137 });
//!
//! const order = try builder.createOrder(.{
//!     .token_id = "123456789",
//!     .price = try Decimal.fromString("0.65"),
//!     .size = try Decimal.fromString("100"),
//!     .side = .BUY,
//! }, .{
//!     .tick_size = .@"0.01",
//!     .neg_risk = false,
//! });
//! ```

const std = @import("std");
const root = @import("../root.zig");

const Wallet = root.signer.Wallet;
const eip712 = root.signer.eip712;
const Decimal = root.types.Decimal;

const types = @import("types.zig");
const calculator = @import("calculator.zig");

const Side = types.Side;
const SignatureType = types.SignatureType;
const TickSize = types.TickSize;
const OrderArgs = types.OrderArgs;
const CreateOrderOptions = types.CreateOrderOptions;
const SignedOrder = types.SignedOrder;

/// 订单构建器错误
pub const OrderBuilderError = error{
    /// 无效的价格
    InvalidPrice,
    /// 无效的数量
    InvalidSize,
    /// 无效的 Token ID
    InvalidTokenId,
    /// 签名失败
    SigningFailed,
    /// 数值溢出
    Overflow,
};

/// 订单构建器选项
pub const OrderBuilderOptions = struct {
    /// 链 ID (137 = Polygon mainnet, 80002 = Amoy testnet)
    chain_id: u64 = 137,
};

/// 订单构建器
///
/// 用于创建和签名 Polymarket 订单。
pub const OrderBuilder = struct {
    /// 钱包引用
    wallet: *const Wallet,
    /// 链 ID
    chain_id: u64,

    const Self = @This();

    /// 初始化订单构建器
    pub fn init(wallet: *const Wallet, options: OrderBuilderOptions) Self {
        return Self{
            .wallet = wallet,
            .chain_id = options.chain_id,
        };
    }

    /// 创建限价单
    ///
    /// 根据参数创建并签名订单。
    pub fn createOrder(
        self: *const Self,
        args: OrderArgs,
        options: CreateOrderOptions,
    ) OrderBuilderError!SignedOrder {
        return self.createOrderWithSalt(args, options, calculator.generateSalt());
    }

    /// 创建限价单（使用指定 salt，用于测试）
    pub fn createOrderWithSalt(
        self: *const Self,
        args: OrderArgs,
        options: CreateOrderOptions,
        salt: u256,
    ) OrderBuilderError!SignedOrder {
        // 验证价格
        calculator.validatePrice(args.price) catch {
            return OrderBuilderError.InvalidPrice;
        };

        // 验证数量
        calculator.validateSize(args.size) catch {
            return OrderBuilderError.InvalidSize;
        };

        // 舍入价格到 tick size
        const rounded_price = calculator.roundToTickSize(args.price, options.tick_size);

        // 解析 token ID
        const token_id = calculator.parseTokenId(args.token_id) catch {
            return OrderBuilderError.InvalidTokenId;
        };

        // 计算金额
        const maker_amount = calculator.calculateMakerAmount(args.side, args.size, rounded_price) catch {
            return OrderBuilderError.Overflow;
        };
        const taker_amount = calculator.calculateTakerAmount(args.side, args.size, rounded_price) catch {
            return OrderBuilderError.Overflow;
        };

        // 获取地址
        const maker = self.wallet.address_bytes;
        const signer = maker; // 对于 EOA，maker == signer
        const taker = args.taker orelse SignedOrder.ZERO_ADDRESS;

        // 构建订单
        var order = SignedOrder{
            .salt = salt,
            .maker = maker,
            .signer = signer,
            .taker = taker,
            .token_id = token_id,
            .maker_amount = maker_amount,
            .taker_amount = taker_amount,
            .expiration = args.expiration,
            .nonce = args.nonce,
            .fee_rate_bps = args.fee_rate_bps,
            .side = args.side,
            .signature_type = options.signature_type,
            .signature = undefined,
        };

        // 签名订单
        const eip712_order = order.toEip712Order();
        const digest = eip712.hashPolymarketOrder(&eip712_order, self.chain_id, options.neg_risk);

        order.signature = self.wallet.sign(&digest) catch {
            return OrderBuilderError.SigningFailed;
        };

        return order;
    }

    /// 获取链 ID
    pub fn getChainId(self: *const Self) u64 {
        return self.chain_id;
    }

    /// 获取钱包地址
    pub fn getAddress(self: *const Self) [20]u8 {
        return self.wallet.address_bytes;
    }
};

// ============================================================================
// 测试
// ============================================================================

test "OrderBuilder.init" {
    const wallet = try Wallet.fromPrivateKeyHex("0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318");
    const builder = OrderBuilder.init(&wallet, .{ .chain_id = 137 });

    try std.testing.expectEqual(@as(u64, 137), builder.getChainId());
}

test "OrderBuilder.createOrderWithSalt BUY" {
    const wallet = try Wallet.fromPrivateKeyHex("0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318");
    const builder = OrderBuilder.init(&wallet, .{ .chain_id = 137 });

    const order = try builder.createOrderWithSalt(.{
        .token_id = "123456789",
        .price = try Decimal.fromString("0.65"),
        .size = try Decimal.fromString("100"),
        .side = .BUY,
    }, .{
        .tick_size = .@"0.01",
        .neg_risk = false,
    }, 12345);

    // 验证基本字段
    try std.testing.expectEqual(@as(u256, 12345), order.salt);
    try std.testing.expectEqual(@as(u256, 123456789), order.token_id);
    try std.testing.expectEqual(Side.BUY, order.side);
    try std.testing.expectEqual(SignatureType.EOA, order.signature_type);

    // 验证金额 (BUY: maker=price*size, taker=size)
    // 0.65 * 100 = 65 USDC = 65000000
    try std.testing.expectEqual(@as(u256, 65_000_000), order.maker_amount);
    // 100 tokens = 100000000
    try std.testing.expectEqual(@as(u256, 100_000_000), order.taker_amount);

    // 验证地址
    try std.testing.expectEqualSlices(u8, &wallet.address_bytes, &order.maker);
    try std.testing.expectEqualSlices(u8, &wallet.address_bytes, &order.signer);
    try std.testing.expectEqualSlices(u8, &SignedOrder.ZERO_ADDRESS, &order.taker);
}

test "OrderBuilder.createOrderWithSalt SELL" {
    const wallet = try Wallet.fromPrivateKeyHex("0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318");
    const builder = OrderBuilder.init(&wallet, .{ .chain_id = 137 });

    const order = try builder.createOrderWithSalt(.{
        .token_id = "987654321",
        .price = try Decimal.fromString("0.35"),
        .size = try Decimal.fromString("200"),
        .side = .SELL,
    }, .{
        .tick_size = .@"0.01",
        .neg_risk = false,
    }, 54321);

    // 验证金额 (SELL: maker=size, taker=price*size)
    // 200 tokens = 200000000
    try std.testing.expectEqual(@as(u256, 200_000_000), order.maker_amount);
    // 0.35 * 200 = 70 USDC = 70000000
    try std.testing.expectEqual(@as(u256, 70_000_000), order.taker_amount);
}

test "OrderBuilder.createOrderWithSalt with options" {
    const wallet = try Wallet.fromPrivateKeyHex("0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318");
    const builder = OrderBuilder.init(&wallet, .{ .chain_id = 137 });

    const order = try builder.createOrderWithSalt(.{
        .token_id = "111",
        .price = try Decimal.fromString("0.5"),
        .size = try Decimal.fromString("50"),
        .side = .BUY,
        .fee_rate_bps = 100, // 1%
        .expiration = 1735689600, // 2025-01-01
        .nonce = 42,
    }, .{
        .tick_size = .@"0.01",
        .neg_risk = true,
    }, 99999);

    try std.testing.expectEqual(@as(u256, 100), order.fee_rate_bps);
    try std.testing.expectEqual(@as(u256, 1735689600), order.expiration);
    try std.testing.expectEqual(@as(u256, 42), order.nonce);
}

test "OrderBuilder.createOrderWithSalt with custom taker" {
    const wallet = try Wallet.fromPrivateKeyHex("0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318");
    const builder = OrderBuilder.init(&wallet, .{ .chain_id = 137 });

    var taker: [20]u8 = undefined;
    @memset(&taker, 0xAB);

    const order = try builder.createOrderWithSalt(.{
        .token_id = "222",
        .price = try Decimal.fromString("0.7"),
        .size = try Decimal.fromString("10"),
        .side = .BUY,
        .taker = taker,
    }, .{}, 11111);

    try std.testing.expectEqualSlices(u8, &taker, &order.taker);
}

test "OrderBuilder.createOrderWithSalt invalid price" {
    const wallet = try Wallet.fromPrivateKeyHex("0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318");
    const builder = OrderBuilder.init(&wallet, .{ .chain_id = 137 });

    // 价格 >= 1 无效
    const result1 = builder.createOrderWithSalt(.{
        .token_id = "123",
        .price = Decimal.ONE,
        .size = try Decimal.fromString("100"),
        .side = .BUY,
    }, .{}, 1);
    try std.testing.expectError(OrderBuilderError.InvalidPrice, result1);

    // 价格 <= 0 无效
    const result2 = builder.createOrderWithSalt(.{
        .token_id = "123",
        .price = Decimal.ZERO,
        .size = try Decimal.fromString("100"),
        .side = .BUY,
    }, .{}, 1);
    try std.testing.expectError(OrderBuilderError.InvalidPrice, result2);
}

test "OrderBuilder.createOrderWithSalt invalid size" {
    const wallet = try Wallet.fromPrivateKeyHex("0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318");
    const builder = OrderBuilder.init(&wallet, .{ .chain_id = 137 });

    const result = builder.createOrderWithSalt(.{
        .token_id = "123",
        .price = try Decimal.fromString("0.5"),
        .size = Decimal.ZERO,
        .side = .BUY,
    }, .{}, 1);
    try std.testing.expectError(OrderBuilderError.InvalidSize, result);
}

test "OrderBuilder.createOrderWithSalt invalid token_id" {
    const wallet = try Wallet.fromPrivateKeyHex("0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318");
    const builder = OrderBuilder.init(&wallet, .{ .chain_id = 137 });

    const result = builder.createOrderWithSalt(.{
        .token_id = "invalid",
        .price = try Decimal.fromString("0.5"),
        .size = try Decimal.fromString("100"),
        .side = .BUY,
    }, .{}, 1);
    try std.testing.expectError(OrderBuilderError.InvalidTokenId, result);
}

test "OrderBuilder signature verification" {
    const wallet = try Wallet.fromPrivateKeyHex("0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318");
    const builder = OrderBuilder.init(&wallet, .{ .chain_id = 137 });

    const order = try builder.createOrderWithSalt(.{
        .token_id = "123",
        .price = try Decimal.fromString("0.5"),
        .size = try Decimal.fromString("100"),
        .side = .BUY,
    }, .{
        .neg_risk = false,
    }, 12345);

    // 验证签名
    const digest = order.getOrderHash(137, false);
    try std.testing.expect(wallet.verify(&digest, &order.signature));
}

test "OrderBuilder different chain produces different signature" {
    const wallet = try Wallet.fromPrivateKeyHex("0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318");

    const builder_mainnet = OrderBuilder.init(&wallet, .{ .chain_id = 137 });
    const builder_amoy = OrderBuilder.init(&wallet, .{ .chain_id = 80002 });

    const args = OrderArgs{
        .token_id = "123",
        .price = try Decimal.fromString("0.5"),
        .size = try Decimal.fromString("100"),
        .side = .BUY,
    };

    const order1 = try builder_mainnet.createOrderWithSalt(args, .{}, 12345);
    const order2 = try builder_amoy.createOrderWithSalt(args, .{}, 12345);

    // 签名应该不同（因为链 ID 不同）
    try std.testing.expect(!std.mem.eql(u8, &order1.signature.r, &order2.signature.r));
}
