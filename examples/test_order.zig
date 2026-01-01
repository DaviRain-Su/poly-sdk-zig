//! 测试真实下单
//!
//! 用于调试订单提交问题

const std = @import("std");
const poly = @import("poly_sdk_zig");

const Wallet = poly.signer.Wallet;
const OrderBuilder = poly.order.OrderBuilder;
const ClobClient = poly.clob.client.ClobClient;
const ApiCreds = poly.auth.ApiCreds;
const Decimal = poly.types.Decimal;
const Side = poly.order.types.Side;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 加载配置
    var env = poly.loadEnvOrEmpty(allocator, ".env");
    defer env.deinit();

    const private_key = env.get("POLY_PRIVATE_KEY") orelse {
        std.debug.print("错误: 需要设置 POLY_PRIVATE_KEY\n", .{});
        return error.MissingCredentials;
    };

    // 初始化钱包
    const wallet = Wallet.fromPrivateKeyHex(private_key) catch |err| {
        std.debug.print("钱包初始化失败: {}\n", .{err});
        return err;
    };

    std.debug.print("钱包地址: {s}\n", .{wallet.getAddressChecksumHex()});

    // 初始化客户端
    var client = ClobClient.init(allocator, .{});
    defer client.deinit();
    client.setWallet(&wallet);

    // 获取 API 凭证
    std.debug.print("正在获取 API 凭证...\n", .{});
    var creds = client.createOrDeriveApiKey() catch |err| {
        std.debug.print("获取 API 凭证失败: {}\n", .{err});
        return err;
    };
    defer creds.deinit();

    std.debug.print("API Key: {s}\n", .{creds.getApiKey()});
    client.setApiCreds(&creds);

    // 获取一个活跃的市场
    std.debug.print("\n正在获取市场列表...\n", .{});
    const markets_result = client.getMarkets(.{}) catch |err| {
        std.debug.print("获取市场失败: {}\n", .{err});
        return err;
    };
    defer markets_result.deinit();

    if (markets_result.value.data.len == 0) {
        std.debug.print("没有找到活跃的市场\n", .{});
        return error.NoMarkets;
    }

    // 查找一个有有效 token 的市场
    var token_id: ?[]const u8 = null;
    var market_question: []const u8 = "";

    for (markets_result.value.data) |market| {
        if (market.tokens) |tokens| {
            if (tokens.len > 0) {
                token_id = tokens[0].token_id;
                market_question = market.question orelse "Unknown";
                break;
            }
        }
    }

    if (token_id == null) {
        std.debug.print("没有找到有效的 token\n", .{});
        return error.NoTokens;
    }

    std.debug.print("市场: {s}\n", .{market_question});
    std.debug.print("Token ID: {s}\n", .{token_id.?});

    // 获取订单簿
    std.debug.print("\n获取订单簿...\n", .{});
    const book = client.getOrderBook(token_id.?) catch |err| {
        std.debug.print("获取订单簿失败: {}\n", .{err});
        return err;
    };
    defer book.deinit();

    // 获取最佳买卖价
    var best_bid: ?Decimal = null;
    var best_ask: ?Decimal = null;

    if (book.value.bids) |bids| {
        if (bids.len > 0) {
            best_bid = Decimal.fromString(bids[0].price) catch null;
        }
    }
    if (book.value.asks) |asks| {
        if (asks.len > 0) {
            best_ask = Decimal.fromString(asks[0].price) catch null;
        }
    }

    if (best_bid) |b| {
        std.debug.print("  最佳买价: {d}.{d:0>6}\n", .{ @divFloor(b.mantissa, std.math.pow(i128, 10, b.scale)), @abs(@rem(b.mantissa, std.math.pow(i128, 10, b.scale))) });
    } else {
        std.debug.print("  最佳买价: null\n", .{});
    }
    if (best_ask) |a| {
        std.debug.print("  最佳卖价: {d}.{d:0>6}\n", .{ @divFloor(a.mantissa, std.math.pow(i128, 10, a.scale)), @abs(@rem(a.mantissa, std.math.pow(i128, 10, a.scale))) });
    } else {
        std.debug.print("  最佳卖价: null\n", .{});
    }

    // 确定下单价格：使用一个很低的买价（不会实际成交）
    const order_price = if (best_bid) |b| blk: {
        // 使用比最佳买价低 0.10 的价格，确保不会成交
        if (b.mantissa > 10 * std.math.pow(i128, 10, b.scale)) {
            const low_price = b.sub(try Decimal.fromString("0.10"));
            break :blk low_price;
        }
        break :blk try Decimal.fromString("0.01");
    } else try Decimal.fromString("0.01");

    std.debug.print("  订单价格: {d}.{d:0>6}\n", .{ @divFloor(order_price.mantissa, std.math.pow(i128, 10, order_price.scale)), @abs(@rem(order_price.mantissa, std.math.pow(i128, 10, order_price.scale))) });

    // 创建订单
    std.debug.print("\n正在创建订单...\n", .{});
    const builder = OrderBuilder.init(&wallet, .{ .chain_id = 137 });

    const order = builder.createOrder(.{
        .token_id = token_id.?,
        .price = order_price,
        .size = try Decimal.fromString("1"), // 最小订单
        .side = .BUY,
    }, .{
        .tick_size = .@"0.01",
        .neg_risk = false,
    }) catch |err| {
        std.debug.print("创建订单失败: {}\n", .{err});
        return err;
    };

    std.debug.print("订单创建成功!\n", .{});

    // 打印订单详情
    var buffers = poly.order.types.SignedOrder.OrderDataBuffers{};
    const order_data = order.toOrderData(&buffers);

    std.debug.print("\n订单详情:\n", .{});
    std.debug.print("  salt: {d}\n", .{order_data.salt});
    std.debug.print("  maker: {s}\n", .{order_data.maker});
    std.debug.print("  tokenId: {s}\n", .{order_data.tokenId});
    std.debug.print("  makerAmount: {s}\n", .{order_data.makerAmount});
    std.debug.print("  takerAmount: {s}\n", .{order_data.takerAmount});
    std.debug.print("  side: {s}\n", .{order_data.side});
    std.debug.print("  signatureType: {d}\n", .{order_data.signatureType});

    // 使用客户端提交订单
    std.debug.print("\n正在提交订单...\n", .{});
    const result = client.postOrder(&order, .GTC) catch |err| {
        std.debug.print("订单提交失败: {}\n", .{err});
        return err;
    };

    std.debug.print("\n订单提交成功!\n", .{});
    std.debug.print("  success: {}\n", .{result.success});

    // 打印订单 ID
    if (result.orderID) |order_id| {
        std.debug.print("订单 ID: {s}\n", .{order_id});

        // 取消订单
        std.debug.print("\n取消订单...\n", .{});
        const cancel_result = client.cancelOrder(order_id) catch |err| {
            std.debug.print("取消订单失败: {}\n", .{err});
            return err;
        };
        _ = cancel_result;
        std.debug.print("取消成功!\n", .{});
    }

    if (result.errorMsg) |msg| {
        std.debug.print("  错误: {s}\n", .{msg});
    }
}
