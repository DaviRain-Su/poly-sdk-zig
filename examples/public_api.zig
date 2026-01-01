//! 公共 API 使用示例
//!
//! 演示如何使用 CLOB 客户端访问公共端点（无需认证）。
//! 这些端点提供市场数据、订单簿、价格等信息。
//!
//! 注意: 此示例需要网络连接到 Polymarket API。
//!
//! 运行: zig build run-public_api

const std = @import("std");
const poly = @import("poly_sdk_zig");

// 导入模块
const ClobClient = poly.ClobClient;
const Decimal = poly.Decimal;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Polymarket 公共 API 示例 ===\n\n", .{});

    // 创建客户端（默认连接主网）
    var client = ClobClient.init(allocator, .{});
    defer client.deinit();

    // 也可以连接测试网
    // var client = ClobClient.init(allocator, .{
    //     .base_url = "https://clob-testnet.polymarket.com",
    // });

    std.debug.print("1. 检查服务器状态\n", .{});
    std.debug.print("   端点: GET /\n", .{});
    // 注意: 实际调用需要网络连接
    // const ok = try client.getOk();
    // defer client.freeOkResponse(&ok);
    // std.debug.print("   响应: {s}\n\n", .{ok.body});
    std.debug.print("   (跳过 - 需要网络连接)\n\n", .{});

    std.debug.print("2. 获取服务器时间\n", .{});
    std.debug.print("   端点: GET /time\n", .{});
    // const time = try client.getServerTime();
    // std.debug.print("   时间戳: {d}\n\n", .{time.timestamp.?});
    std.debug.print("   (跳过 - 需要网络连接)\n\n", .{});

    std.debug.print("3. 获取市场列表\n", .{});
    std.debug.print("   端点: GET /markets\n", .{});
    // const markets = try client.getMarkets(.{});
    // defer markets.deinit();
    // std.debug.print("   市场数量: {d}\n", .{markets.value.len});
    // if (markets.value.len > 0) {
    //     std.debug.print("   第一个市场: {s}\n\n", .{markets.value[0].question});
    // }
    std.debug.print("   (跳过 - 需要网络连接)\n\n", .{});

    std.debug.print("4. 获取订单簿\n", .{});
    std.debug.print("   端点: GET /book?token_id=...\n", .{});
    std.debug.print("   示例代码:\n", .{});
    std.debug.print("   ```\n", .{});
    std.debug.print("   const book = try client.getOrderBook(token_id);\n", .{});
    std.debug.print("   defer book.deinit();\n", .{});
    std.debug.print("   // book.value.bids - 买单列表\n", .{});
    std.debug.print("   // book.value.asks - 卖单列表\n", .{});
    std.debug.print("   ```\n\n", .{});

    std.debug.print("5. 获取价格\n", .{});
    std.debug.print("   端点: GET /price?token_id=...&side=...\n", .{});
    std.debug.print("   示例代码:\n", .{});
    std.debug.print("   ```\n", .{});
    std.debug.print("   const price = try client.getPrice(token_id, .buy);\n", .{});
    std.debug.print("   // price.price - 当前最优价格\n", .{});
    std.debug.print("   ```\n\n", .{});

    std.debug.print("6. 获取中间价\n", .{});
    std.debug.print("   端点: GET /midpoint?token_id=...\n", .{});
    std.debug.print("   示例代码:\n", .{});
    std.debug.print("   ```\n", .{});
    std.debug.print("   const midpoint = try client.getMidpoint(token_id);\n", .{});
    std.debug.print("   // midpoint.midpoint - 买卖中间价\n", .{});
    std.debug.print("   ```\n\n", .{});

    std.debug.print("7. 获取价差\n", .{});
    std.debug.print("   端点: GET /spread?token_id=...\n", .{});
    std.debug.print("   示例代码:\n", .{});
    std.debug.print("   ```\n", .{});
    std.debug.print("   const spread = try client.getSpread(token_id);\n", .{});
    std.debug.print("   // spread.spread - 买卖价差\n", .{});
    std.debug.print("   ```\n\n", .{});

    std.debug.print("8. 批量获取订单簿\n", .{});
    std.debug.print("   端点: POST /books\n", .{});
    std.debug.print("   示例代码:\n", .{});
    std.debug.print("   ```\n", .{});
    std.debug.print("   const books = try client.getOrderBooks(&.{{ token1, token2 }});\n", .{});
    std.debug.print("   defer books.deinit();\n", .{});
    std.debug.print("   ```\n\n", .{});

    std.debug.print("=== 可用的公共端点 ===\n\n", .{});
    std.debug.print("服务器状态:\n", .{});
    std.debug.print("  - getOk()           GET /\n", .{});
    std.debug.print("  - getServerTime()   GET /time\n\n", .{});

    std.debug.print("市场数据:\n", .{});
    std.debug.print("  - getMarkets()              GET /markets\n", .{});
    std.debug.print("  - getMarket(id)             GET /markets/{{id}}\n", .{});
    std.debug.print("  - getSimplifiedMarkets()    GET /simplified-markets\n", .{});
    std.debug.print("  - getSamplingMarkets()      GET /sampling-markets\n\n", .{});

    std.debug.print("价格和订单簿:\n", .{});
    std.debug.print("  - getOrderBook(token_id)    GET /book\n", .{});
    std.debug.print("  - getPrice(token_id, side)  GET /price\n", .{});
    std.debug.print("  - getMidpoint(token_id)     GET /midpoint\n", .{});
    std.debug.print("  - getSpread(token_id)       GET /spread\n", .{});
    std.debug.print("  - getTickSize(token_id)     GET /tick-size\n", .{});
    std.debug.print("  - getNegRisk(token_id)      GET /neg-risk\n", .{});
    std.debug.print("  - getLastTradePrice(id)     GET /last-trade-price\n", .{});
    std.debug.print("  - getFeeRateBps(token_id)   GET /fee-rate\n\n", .{});

    std.debug.print("批量端点:\n", .{});
    std.debug.print("  - getOrderBooks(ids)        POST /books\n", .{});
    std.debug.print("  - getMidpoints(ids)         POST /midpoints\n", .{});
    std.debug.print("  - getPrices(ids, side)      POST /prices\n", .{});
    std.debug.print("  - getSpreads(ids)           POST /spreads\n", .{});
    std.debug.print("  - getLastTradesPrices(ids)  POST /last-trades-prices\n\n", .{});

    std.debug.print("=== 完成 ===\n", .{});
}
