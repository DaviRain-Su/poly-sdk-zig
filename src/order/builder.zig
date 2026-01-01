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
const TimeInForce = types.TimeInForce;
const OrderArgs = types.OrderArgs;
const MarketOrderArgs = types.MarketOrderArgs;
const MarketOrderOptions = types.MarketOrderOptions;
const CreateOrderOptions = types.CreateOrderOptions;
const SignedOrder = types.SignedOrder;

// 导入订单簿类型
const clob_types = @import("../clob/types/mod.zig");
const OrderBookSummary = clob_types.OrderBookSummary;

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
    /// 订单簿深度不足
    InsufficientLiquidity,
    /// 滑点超限
    SlippageExceeded,
    /// 无效的 TimeInForce (市价单只支持 FOK/FAK)
    InvalidTimeInForce,
};

/// 订单构建器选项
pub const OrderBuilderOptions = struct {
    /// 链 ID (137 = Polygon mainnet, 80002 = Amoy testnet)
    chain_id: u64 = 137,
    /// Funder 地址（用于 Proxy 钱包，如 POLY_PROXY 或 POLY_GNOSIS_SAFE）
    /// 如果为 null，则使用 wallet 地址
    funder: ?[20]u8 = null,
};

/// 订单构建器
///
/// 用于创建和签名 Polymarket 订单。
pub const OrderBuilder = struct {
    /// 钱包引用
    wallet: *const Wallet,
    /// 链 ID
    chain_id: u64,
    /// Funder 地址（用于 Proxy 钱包）
    funder: ?[20]u8,

    const Self = @This();

    /// 初始化订单构建器
    pub fn init(wallet: *const Wallet, options: OrderBuilderOptions) Self {
        return Self{
            .wallet = wallet,
            .chain_id = options.chain_id,
            .funder = options.funder,
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
        // 对于 EOA: maker == signer
        // 对于 Proxy (POLY_PROXY, POLY_GNOSIS_SAFE): maker = funder (proxy 地址), signer = EOA
        const maker = self.funder orelse self.wallet.address_bytes;
        const signer = self.wallet.address_bytes;
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

    /// 创建市价单
    ///
    /// 根据订单簿深度计算最优价格并创建订单。
    /// 市价单使用 FOK 或 FAK 类型。
    ///
    /// 参数:
    ///   - args: 市价单参数
    ///   - order_book: 订单簿摘要（用于计算价格）
    ///   - options: 市价单选项
    ///
    /// 返回: 签名后的订单
    pub fn createMarketOrder(
        self: *const Self,
        args: MarketOrderArgs,
        order_book: *const OrderBookSummary,
        options: MarketOrderOptions,
    ) OrderBuilderError!SignedOrder {
        return self.createMarketOrderWithSalt(args, order_book, options, calculator.generateSalt());
    }

    /// 创建市价单（使用指定 salt，用于测试）
    pub fn createMarketOrderWithSalt(
        self: *const Self,
        args: MarketOrderArgs,
        order_book: *const OrderBookSummary,
        options: MarketOrderOptions,
        salt: u256,
    ) OrderBuilderError!SignedOrder {
        // 验证 TimeInForce（市价单只支持 FOK/FAK）
        switch (options.time_in_force) {
            .FOK, .FAK => {},
            .GTC, .GTD => return OrderBuilderError.InvalidTimeInForce,
        }

        // 验证数量
        calculator.validateSize(args.amount) catch {
            return OrderBuilderError.InvalidSize;
        };

        // 计算市价
        const price = if (args.price) |p|
            p
        else blk: {
            const result = calculator.calculateMarketPrice(order_book, args.side, args.amount) catch {
                return OrderBuilderError.InsufficientLiquidity;
            };

            if (!result.fully_fillable and options.time_in_force == .FOK) {
                // FOK 需要完全成交
                return OrderBuilderError.InsufficientLiquidity;
            }

            // 验证滑点
            if (args.max_slippage) |max_slip| {
                // 使用中间价作为预期价格（简化处理）
                const mid_price = if (order_book.bids != null and order_book.asks != null) blk2: {
                    const bids = order_book.bids.?;
                    const asks = order_book.asks.?;
                    if (bids.len > 0 and asks.len > 0) {
                        const best_bid = Decimal.fromString(bids[0].price) catch break :blk2 result.price;
                        const best_ask = Decimal.fromString(asks[0].price) catch break :blk2 result.price;
                        break :blk2 best_bid.add(best_ask).div(Decimal.fromParts(2, 0)) catch result.price;
                    }
                    break :blk2 result.price;
                } else result.price;

                calculator.validateSlippage(mid_price, result.price, max_slip, args.side) catch {
                    return OrderBuilderError.SlippageExceeded;
                };
            }

            break :blk result.price;
        };

        // 验证价格
        calculator.validatePrice(price) catch {
            return OrderBuilderError.InvalidPrice;
        };

        // 舍入价格到 tick size
        const rounded_price = calculator.roundToTickSize(price, options.tick_size);

        // 解析 token ID
        const token_id = calculator.parseTokenId(args.token_id) catch {
            return OrderBuilderError.InvalidTokenId;
        };

        // 计算 size（对于市价单，需要根据金额和价格计算）
        const size = switch (args.side) {
            .BUY => args.amount.div(rounded_price) catch return OrderBuilderError.Overflow,
            .SELL => args.amount,
        };

        // 计算金额
        const maker_amount = calculator.calculateMakerAmount(args.side, size, rounded_price) catch {
            return OrderBuilderError.Overflow;
        };
        const taker_amount = calculator.calculateTakerAmount(args.side, size, rounded_price) catch {
            return OrderBuilderError.Overflow;
        };

        // 获取地址
        const maker = self.wallet.address_bytes;
        const signer = maker;
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

test "OrderBuilder.createMarketOrderWithSalt FOK" {
    const wallet = try Wallet.fromPrivateKeyHex("0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318");
    const builder = OrderBuilder.init(&wallet, .{ .chain_id = 137 });

    // 模拟订单簿
    var asks = [_]clob_types.OrderSummary{
        .{ .price = "0.55", .size = "100" },
        .{ .price = "0.60", .size = "200" },
    };
    const book = OrderBookSummary{
        .asks = &asks,
    };

    // 创建市价买单: 55 USDC，预期价格 0.55
    const order = try builder.createMarketOrderWithSalt(.{
        .token_id = "123456789",
        .amount = try Decimal.fromString("55"),
        .side = .BUY,
    }, &book, .{
        .time_in_force = .FOK,
        .tick_size = .@"0.01",
    }, 12345);

    // 验证基本字段
    try std.testing.expectEqual(@as(u256, 12345), order.salt);
    try std.testing.expectEqual(@as(u256, 123456789), order.token_id);
    try std.testing.expectEqual(Side.BUY, order.side);
}

test "OrderBuilder.createMarketOrderWithSalt FAK" {
    const wallet = try Wallet.fromPrivateKeyHex("0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318");
    const builder = OrderBuilder.init(&wallet, .{ .chain_id = 137 });

    // 模拟订单簿
    var bids = [_]clob_types.OrderSummary{
        .{ .price = "0.50", .size = "100" },
        .{ .price = "0.45", .size = "200" },
    };
    const book = OrderBookSummary{
        .bids = &bids,
    };

    // 创建市价卖单: 50 tokens
    const order = try builder.createMarketOrderWithSalt(.{
        .token_id = "123456789",
        .amount = try Decimal.fromString("50"),
        .side = .SELL,
    }, &book, .{
        .time_in_force = .FAK,
        .tick_size = .@"0.01",
    }, 54321);

    try std.testing.expectEqual(@as(u256, 54321), order.salt);
    try std.testing.expectEqual(Side.SELL, order.side);
}

test "OrderBuilder.createMarketOrderWithSalt with explicit price" {
    const wallet = try Wallet.fromPrivateKeyHex("0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318");
    const builder = OrderBuilder.init(&wallet, .{ .chain_id = 137 });

    // 使用显式价格，不需要订单簿
    const empty_book = OrderBookSummary{};

    const order = try builder.createMarketOrderWithSalt(.{
        .token_id = "123456789",
        .amount = try Decimal.fromString("100"),
        .side = .BUY,
        .price = try Decimal.fromString("0.55"), // 显式指定价格
    }, &empty_book, .{
        .time_in_force = .FOK,
    }, 99999);

    try std.testing.expectEqual(@as(u256, 99999), order.salt);
}

test "OrderBuilder.createMarketOrderWithSalt invalid TimeInForce" {
    const wallet = try Wallet.fromPrivateKeyHex("0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318");
    const builder = OrderBuilder.init(&wallet, .{ .chain_id = 137 });

    const empty_book = OrderBookSummary{};

    // GTC 不是有效的市价单类型
    const result = builder.createMarketOrderWithSalt(.{
        .token_id = "123",
        .amount = try Decimal.fromString("100"),
        .side = .BUY,
        .price = try Decimal.fromString("0.5"),
    }, &empty_book, .{
        .time_in_force = .GTC, // 无效
    }, 1);

    try std.testing.expectError(OrderBuilderError.InvalidTimeInForce, result);
}

test "OrderBuilder.createMarketOrderWithSalt insufficient liquidity" {
    const wallet = try Wallet.fromPrivateKeyHex("0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318");
    const builder = OrderBuilder.init(&wallet, .{ .chain_id = 137 });

    // 空订单簿
    const empty_book = OrderBookSummary{};

    const result = builder.createMarketOrderWithSalt(.{
        .token_id = "123",
        .amount = try Decimal.fromString("100"),
        .side = .BUY,
        // 没有指定价格，需要从订单簿计算
    }, &empty_book, .{
        .time_in_force = .FOK,
    }, 1);

    try std.testing.expectError(OrderBuilderError.InsufficientLiquidity, result);
}
