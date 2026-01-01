//! BTC 市场搜索工具
//!
//! 在 Polymarket 上搜索 BTC/Bitcoin 相关的活跃市场。
//! 显示市场详情、Token ID、价格等信息。
//!
//! 运行: zig build run-find_btc_markets
//!
//! 注意: 需要网络连接到 Polymarket API。

const std = @import("std");
const poly = @import("poly_sdk_zig");

const ClobClient = poly.ClobClient;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n", .{});
    std.debug.print("╔══════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║           Polymarket BTC 市场搜索工具                         ║\n", .{});
    std.debug.print("╚══════════════════════════════════════════════════════════════╝\n", .{});
    std.debug.print("\n", .{});

    // 创建客户端
    var client = ClobClient.init(allocator, .{});
    defer client.deinit();

    std.debug.print("正在连接 Polymarket API...\n\n", .{});

    // 获取市场列表
    const markets = client.getMarkets(.{}) catch |err| {
        std.debug.print("获取市场失败: {}\n", .{err});
        std.debug.print("\n", .{});
        std.debug.print("请检查网络连接或稍后重试。\n", .{});
        return;
    };
    defer markets.deinit();

    std.debug.print("共找到 {d} 个市场\n\n", .{markets.value.data.len});

    // 搜索 BTC 相关市场
    var btc_count: usize = 0;

    std.debug.print("=== BTC/Bitcoin 相关市场 ===\n\n", .{});

    for (markets.value.data) |market| {
        // 跳过没有问题文本的市场
        const question = market.question orelse continue;

        const question_lower = blk: {
            var buf: [1024]u8 = undefined;
            const len = @min(question.len, buf.len);
            for (question[0..len], 0..) |c, i| {
                buf[i] = std.ascii.toLower(c);
            }
            break :blk buf[0..len];
        };

        // 检查是否包含 BTC 或 Bitcoin
        if (std.mem.indexOf(u8, question_lower, "btc") != null or
            std.mem.indexOf(u8, question_lower, "bitcoin") != null)
        {
            btc_count += 1;

            const is_active = market.active orelse false;

            std.debug.print("─────────────────────────────────────────────────────────────\n", .{});
            std.debug.print("市场 #{d}\n", .{btc_count});
            std.debug.print("问题: {s}\n", .{question});
            std.debug.print("Condition ID: {s}\n", .{market.condition_id});
            std.debug.print("状态: {s}\n", .{if (is_active) "活跃" else "不活跃"});
            std.debug.print("结束时间: {s}\n", .{market.end_date_iso orelse "未知"});

            // 显示 Token 信息
            if (market.tokens) |tokens| {
                std.debug.print("\nTokens:\n", .{});
                for (tokens) |token| {
                    std.debug.print("  [{s}] ID: {s}\n", .{ token.outcome, token.token_id });
                    if (token.price) |price| {
                        std.debug.print("       价格: {d:.4}\n", .{price});
                    } else {
                        std.debug.print("       价格: N/A\n", .{});
                    }
                }
            }

            // 显示交易信息
            if (market.minimum_order_size) |min_size| {
                std.debug.print("\n最小订单: {d:.2} USDC\n", .{min_size});
            }
            if (market.minimum_tick_size) |tick_size| {
                std.debug.print("最小价格间隔: {d:.4}\n", .{tick_size});
            }

            std.debug.print("\n", .{});
        }
    }

    if (btc_count == 0) {
        std.debug.print("未找到 BTC/Bitcoin 相关的活跃市场。\n\n", .{});
        std.debug.print("提示: Polymarket 的 BTC 价格市场可能是:\n", .{});
        std.debug.print("  - 长期价格预测 (如 \"BTC 达到 $100k\")\n", .{});
        std.debug.print("  - 阶段性事件 (如 \"BTC ETF 批准\")\n", .{});
        std.debug.print("\n", .{});
        std.debug.print("短期涨跌市场 (如 15 分钟) 可能在特定时段才开放。\n", .{});
    } else {
        std.debug.print("─────────────────────────────────────────────────────────────\n", .{});
        std.debug.print("共找到 {d} 个 BTC/Bitcoin 相关市场\n", .{btc_count});
    }

    std.debug.print("\n=== 使用指南 ===\n\n", .{});
    std.debug.print("1. 将 Condition ID 和 Token ID 复制到 .env 文件:\n", .{});
    std.debug.print("   POLY_CONDITION_ID=0x...\n", .{});
    std.debug.print("   POLY_YES_TOKEN=...\n", .{});
    std.debug.print("   POLY_NO_TOKEN=...\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("2. 运行交易策略:\n", .{});
    std.debug.print("   zig build run-btc_hedge_strategy\n", .{});
    std.debug.print("\n", .{});
}

test "find btc markets compiles" {
    // 编译测试
    _ = ClobClient;
}
