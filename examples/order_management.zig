//! 订单管理示例
//!
//! 演示如何创建、发布和管理订单。
//!
//! 注意: 此示例需要有效的 API 凭证和网络连接。
//!
//! 运行: zig build run-example-orders

const std = @import("std");

// 导入模块
// 以下类型在实际使用时需要
// const root = @import("../src/root.zig");
// const ClobClient = root.clob.ClobClient;
// const Wallet = root.signer.Wallet;
// const ApiCreds = root.auth.ApiCreds;
// const Decimal = root.types.Decimal;
// const OrderBuilder = root.order.OrderBuilder;
// const Side = root.clob.types.Side;

pub fn main() !void {
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    _ = gpa.allocator(); // 实际使用时需要

    std.debug.print("=== Polymarket 订单管理示例 ===\n\n", .{});

    // =========================================================================
    // 1. 设置客户端
    // =========================================================================
    std.debug.print("1. 设置认证客户端\n", .{});
    std.debug.print("   ```\n", .{});
    std.debug.print("   const wallet = try Wallet.fromPrivateKeyHex(\"0x...\");\n", .{});
    std.debug.print("   var creds = try ApiCreds.init(allocator, key, secret, pass);\n", .{});
    std.debug.print("   var client = ClobClient.initWithAuth(\n", .{});
    std.debug.print("       allocator, .{{}}, &wallet, &creds\n", .{});
    std.debug.print("   );\n", .{});
    std.debug.print("   ```\n\n", .{});

    // =========================================================================
    // 2. 创建限价单
    // =========================================================================
    std.debug.print("2. 创建限价单\n\n", .{});

    std.debug.print("   方法 1: 使用 OrderBuilder\n", .{});
    std.debug.print("   ```\n", .{});
    std.debug.print("   const builder = OrderBuilder.init(&wallet, .{{ .chain_id = 137 }});\n", .{});
    std.debug.print("   const order = try builder.createOrder(.{{\n", .{});
    std.debug.print("       .token_id = \"token_id_here\",\n", .{});
    std.debug.print("       .price = try Decimal.fromString(\"0.65\"),\n", .{});
    std.debug.print("       .size = try Decimal.fromString(\"100\"),\n", .{});
    std.debug.print("       .side = .buy,\n", .{});
    std.debug.print("   }}, .{{}});\n", .{});
    std.debug.print("   ```\n\n", .{});

    std.debug.print("   方法 2: 使用 ClobClient.createOrder\n", .{});
    std.debug.print("   ```\n", .{});
    std.debug.print("   const order = try client.createOrder(.{{\n", .{});
    std.debug.print("       .token_id = \"token_id_here\",\n", .{});
    std.debug.print("       .price = try Decimal.fromString(\"0.65\"),\n", .{});
    std.debug.print("       .size = try Decimal.fromString(\"100\"),\n", .{});
    std.debug.print("       .side = .buy,\n", .{});
    std.debug.print("   }});\n", .{});
    std.debug.print("   ```\n\n", .{});

    // =========================================================================
    // 3. 发布订单
    // =========================================================================
    std.debug.print("3. 发布订单\n\n", .{});

    std.debug.print("   发布单个订单:\n", .{});
    std.debug.print("   ```\n", .{});
    std.debug.print("   const response = try client.postOrder(&order, .GTC);\n", .{});
    std.debug.print("   // response.orderID - 订单 ID\n", .{});
    std.debug.print("   // response.status - 订单状态\n", .{});
    std.debug.print("   ```\n\n", .{});

    std.debug.print("   批量发布订单:\n", .{});
    std.debug.print("   ```\n", .{});
    std.debug.print("   const orders = &[_]*const SignedOrder{{ &order1, &order2 }};\n", .{});
    std.debug.print("   const responses = try client.postOrders(orders, .GTC);\n", .{});
    std.debug.print("   ```\n\n", .{});

    std.debug.print("   创建并发布 (一步完成):\n", .{});
    std.debug.print("   ```\n", .{});
    std.debug.print("   const response = try client.createAndPostOrder(.{{\n", .{});
    std.debug.print("       .token_id = token_id,\n", .{});
    std.debug.print("       .price = price,\n", .{});
    std.debug.print("       .size = size,\n", .{});
    std.debug.print("       .side = .buy,\n", .{});
    std.debug.print("   }}, .GTC);\n", .{});
    std.debug.print("   ```\n\n", .{});

    // =========================================================================
    // 4. 订单类型
    // =========================================================================
    std.debug.print("4. 订单类型\n\n", .{});

    std.debug.print("   GTC (Good Till Cancelled):\n", .{});
    std.debug.print("     - 订单保持有效直到被取消或成交\n", .{});
    std.debug.print("     - 适合: 限价单，不急于成交\n\n", .{});

    std.debug.print("   GTD (Good Till Date):\n", .{});
    std.debug.print("     - 订单在指定日期前有效\n", .{});
    std.debug.print("     - 需要设置 expiration 参数\n\n", .{});

    std.debug.print("   FOK (Fill Or Kill):\n", .{});
    std.debug.print("     - 必须完全成交，否则取消\n", .{});
    std.debug.print("     - 适合: 市价单，需要全部成交\n\n", .{});

    std.debug.print("   FAK (Fill And Kill):\n", .{});
    std.debug.print("     - 尽可能成交，剩余取消\n", .{});
    std.debug.print("     - 适合: 市价单，接受部分成交\n\n", .{});

    // =========================================================================
    // 5. 市价单
    // =========================================================================
    std.debug.print("5. 市价单\n\n", .{});

    std.debug.print("   创建市价单需要订单簿信息:\n", .{});
    std.debug.print("   ```\n", .{});
    std.debug.print("   // 获取订单簿\n", .{});
    std.debug.print("   const book = try client.getOrderBook(token_id);\n", .{});
    std.debug.print("   defer book.deinit();\n", .{});
    std.debug.print("   \n", .{});
    std.debug.print("   // 创建市价单\n", .{});
    std.debug.print("   const order = try client.createMarketOrder(.{{\n", .{});
    std.debug.print("       .token_id = token_id,\n", .{});
    std.debug.print("       .amount = try Decimal.fromString(\"100\"),  // 美元金额\n", .{});
    std.debug.print("       .side = .buy,\n", .{});
    std.debug.print("   }}, &book.value, .{{ .time_in_force = .FOK }});\n", .{});
    std.debug.print("   ```\n\n", .{});

    std.debug.print("   创建并发布市价单:\n", .{});
    std.debug.print("   ```\n", .{});
    std.debug.print("   const response = try client.createAndPostMarketOrder(\n", .{});
    std.debug.print("       .{{ .token_id = id, .amount = amount, .side = .buy }},\n", .{});
    std.debug.print("       &book.value,\n", .{});
    std.debug.print("       .{{ .time_in_force = .FOK }}\n", .{});
    std.debug.print("   );\n", .{});
    std.debug.print("   ```\n\n", .{});

    // =========================================================================
    // 6. 查询订单
    // =========================================================================
    std.debug.print("6. 查询订单\n\n", .{});

    std.debug.print("   获取所有挂单:\n", .{});
    std.debug.print("   ```\n", .{});
    std.debug.print("   const orders = try client.getOpenOrders(.{{}});\n", .{});
    std.debug.print("   defer orders.deinit();\n", .{});
    std.debug.print("   for (orders.value) |order| {{\n", .{});
    std.debug.print("       // order.id, order.price, order.size, order.side...\n", .{});
    std.debug.print("   }}\n", .{});
    std.debug.print("   ```\n\n", .{});

    std.debug.print("   按市场过滤:\n", .{});
    std.debug.print("   ```\n", .{});
    std.debug.print("   const orders = try client.getOpenOrders(.{{\n", .{});
    std.debug.print("       .market = condition_id,\n", .{});
    std.debug.print("   }});\n", .{});
    std.debug.print("   ```\n\n", .{});

    std.debug.print("   获取单个订单:\n", .{});
    std.debug.print("   ```\n", .{});
    std.debug.print("   const order = try client.getOrder(order_id);\n", .{});
    std.debug.print("   defer order.deinit();\n", .{});
    std.debug.print("   ```\n\n", .{});

    // =========================================================================
    // 7. 取消订单
    // =========================================================================
    std.debug.print("7. 取消订单\n\n", .{});

    std.debug.print("   取消单个订单:\n", .{});
    std.debug.print("   ```\n", .{});
    std.debug.print("   const result = try client.cancelOrder(order_id);\n", .{});
    std.debug.print("   // result.canceled - 是否成功取消\n", .{});
    std.debug.print("   ```\n\n", .{});

    std.debug.print("   批量取消订单:\n", .{});
    std.debug.print("   ```\n", .{});
    std.debug.print("   const results = try client.cancelOrders(&[_][]const u8{{\n", .{});
    std.debug.print("       order_id_1, order_id_2\n", .{});
    std.debug.print("   }});\n", .{});
    std.debug.print("   ```\n\n", .{});

    std.debug.print("   取消所有订单:\n", .{});
    std.debug.print("   ```\n", .{});
    std.debug.print("   const result = try client.cancelAll();\n", .{});
    std.debug.print("   ```\n\n", .{});

    std.debug.print("   取消特定市场的订单:\n", .{});
    std.debug.print("   ```\n", .{});
    std.debug.print("   const result = try client.cancelMarketOrders(condition_id);\n", .{});
    std.debug.print("   ```\n\n", .{});

    // =========================================================================
    // 8. 交易历史
    // =========================================================================
    std.debug.print("8. 交易历史\n\n", .{});

    std.debug.print("   获取交易历史:\n", .{});
    std.debug.print("   ```\n", .{});
    std.debug.print("   const trades = try client.getTrades(.{{}});\n", .{});
    std.debug.print("   defer trades.deinit();\n", .{});
    std.debug.print("   for (trades.value) |trade| {{\n", .{});
    std.debug.print("       // trade.id, trade.price, trade.size, trade.side...\n", .{});
    std.debug.print("   }}\n", .{});
    std.debug.print("   ```\n\n", .{});

    std.debug.print("   按市场过滤:\n", .{});
    std.debug.print("   ```\n", .{});
    std.debug.print("   const trades = try client.getTrades(.{{\n", .{});
    std.debug.print("       .market = condition_id,\n", .{});
    std.debug.print("   }});\n", .{});
    std.debug.print("   ```\n\n", .{});

    // =========================================================================
    // 9. Heartbeat (做市商)
    // =========================================================================
    std.debug.print("9. Heartbeat (做市商必须)\n\n", .{});

    std.debug.print("   做市商需要定期发送心跳，否则订单会被取消:\n", .{});
    std.debug.print("   ```\n", .{});
    std.debug.print("   // 每 5-8 秒发送一次心跳\n", .{});
    std.debug.print("   while (running) {{\n", .{});
    std.debug.print("       _ = try client.postHeartbeat();\n", .{});
    std.debug.print("       std.time.sleep(5 * std.time.ns_per_s);\n", .{});
    std.debug.print("   }}\n", .{});
    std.debug.print("   ```\n\n", .{});

    std.debug.print("   注意: 10 秒内不发送心跳会导致所有订单被取消！\n\n", .{});

    std.debug.print("=== 完成 ===\n", .{});
}
