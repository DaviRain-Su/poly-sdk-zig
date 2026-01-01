//! 简单订单测试
//! 直接测试订单提交并打印详细错误信息

const std = @import("std");
const poly = @import("poly_sdk_zig");

const Wallet = poly.signer.Wallet;
const OrderBuilder = poly.order.OrderBuilder;
const ClobClient = poly.clob.client.ClobClient;
const Decimal = poly.types.Decimal;

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

    // 使用一个已知活跃的市场 (US recession in 2025?)
    // Token ID 从 Gamma API 获取的 clobTokenIds
    const token_id = "104173557214744537570424345347209544585775842950109756851652855913015295701992";
    const market_question = "US recession in 2025?";

    std.debug.print("\n使用活跃市场...\n", .{});
    std.debug.print("市场: {s}\n", .{market_question});
    std.debug.print("使用 Token ID: {s}\n", .{token_id});

    // 创建一个低价买单（不会成交）
    // 注意: 最小订单金额是 $1，所以 price * size >= 1
    std.debug.print("\n创建订单...\n", .{});
    const builder = OrderBuilder.init(&wallet, .{ .chain_id = 137 });

    const order = builder.createOrder(.{
        .token_id = token_id,
        .price = try Decimal.fromString("0.01"), // 非常低的价格，不会成交
        .size = try Decimal.fromString("100"), // 100 tokens * $0.01 = $1 最小金额
        .side = .BUY,
    }, .{
        .tick_size = .@"0.01",
        .neg_risk = false,
    }) catch |err| {
        std.debug.print("创建订单失败: {}\n", .{err});
        return err;
    };

    // 打印订单详情
    var buffers = poly.order.types.SignedOrder.OrderDataBuffers{};
    const order_data = order.toOrderData(&buffers);

    std.debug.print("\n订单数据:\n", .{});
    std.debug.print("  salt: {d}\n", .{order_data.salt});
    std.debug.print("  maker: {s}\n", .{order_data.maker});
    std.debug.print("  tokenId: {s}\n", .{order_data.tokenId});
    std.debug.print("  makerAmount: {s}\n", .{order_data.makerAmount});
    std.debug.print("  takerAmount: {s}\n", .{order_data.takerAmount});
    std.debug.print("  side: {s}\n", .{order_data.side});
    std.debug.print("  signatureType: {d}\n", .{order_data.signatureType});

    // 生成 JSON
    const request_body = .{
        .order = order_data,
        .owner = creds.getApiKey(),
        .orderType = "GTC",
    };

    const json = try std.json.Stringify.valueAlloc(allocator, request_body, .{});
    defer allocator.free(json);

    std.debug.print("\nJSON 请求体:\n{s}\n", .{json});

    // 提交订单
    std.debug.print("\n提交订单...\n", .{});
    const result = client.postOrder(&order, .GTC) catch |err| {
        std.debug.print("订单提交失败: {}\n", .{err});
        return err;
    };

    std.debug.print("\n订单提交成功!\n", .{});
    std.debug.print("  success: {}\n", .{result.success});
    if (result.orderID) |id| {
        std.debug.print("  orderID: {s}\n", .{id});
    }
    if (result.errorMsg) |msg| {
        std.debug.print("  errorMsg: {s}\n", .{msg});
    }
}
