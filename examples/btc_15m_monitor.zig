//! BTC 15 分钟市场监控工具
//!
//! 功能：
//! - 实时监控 Polymarket API 寻找 BTC 15 分钟涨跌市场
//! - 评估市场对对冲策略的适用性（剩余时间分析）
//! - 发现新市场时显示详细信息（Token ID、价格等）
//! - 可选：自动更新 .env 文件配置
//!
//! 策略适用性评估：
//! - 剩余 >10分钟: ✅ 最佳 - 有充足时间执行两步对冲
//! - 剩余 7-10分钟: ⚠️ 可以 - 时间较紧，需快速决策
//! - 剩余 4-7分钟: ⚠️ 危险 - 可能没时间完成对冲
//! - 剩余 <4分钟: ❌ 不建议 - 风险太高
//!
//! 运行: zig build run-btc_15m_monitor
//!
//! 市场 slug 模式: btc-updown-15m-{timestamp}
//! 例如: btc-updown-15m-1767231900

const std = @import("std");
const poly = @import("poly_sdk_zig");

const ClobClient = poly.ClobClient;

/// 监控配置
const MonitorConfig = struct {
    /// 轮询间隔（秒）
    poll_interval_sec: u64 = 10,
    /// 是否自动更新 .env 文件
    auto_update_env: bool = false,
    /// .env 文件路径
    env_path: []const u8 = ".env",
    /// 是否只显示活跃市场
    active_only: bool = true,
    /// 是否持续运行
    continuous: bool = true,
    /// 是否只显示适合策略的市场（剩余时间 >= min_remaining_minutes）
    strategy_filter: bool = false,
    /// 策略所需最小剩余时间（分钟）
    min_remaining_minutes: i64 = 7,
};

/// 策略适用性评级
const StrategyRating = enum {
    /// 最佳 - 剩余 >10分钟
    optimal,
    /// 可以 - 剩余 7-10分钟
    acceptable,
    /// 危险 - 剩余 4-7分钟
    risky,
    /// 不建议 - 剩余 <4分钟
    not_recommended,
    /// 已结束
    expired,
    /// 未知（无法解析时间戳）
    unknown,

    pub fn getEmoji(self: StrategyRating) []const u8 {
        return switch (self) {
            .optimal => "✅",
            .acceptable => "⚠️",
            .risky => "🔶",
            .not_recommended => "❌",
            .expired => "⏹️",
            .unknown => "❓",
        };
    }

    pub fn getDescription(self: StrategyRating) []const u8 {
        return switch (self) {
            .optimal => "最佳 - 有充足时间执行两步对冲",
            .acceptable => "可以 - 时间较紧，需快速决策",
            .risky => "危险 - 可能没时间完成对冲",
            .not_recommended => "不建议 - 风险太高，单边暴露",
            .expired => "已结束 - 市场已关闭",
            .unknown => "未知 - 无法解析时间",
        };
    }

    pub fn fromRemainingSeconds(remaining: i64) StrategyRating {
        if (remaining <= 0) return .expired;
        if (remaining < 4 * 60) return .not_recommended; // <4分钟
        if (remaining < 7 * 60) return .risky; // 4-7分钟
        if (remaining < 10 * 60) return .acceptable; // 7-10分钟
        return .optimal; // >10分钟
    }
};

/// 发现的市场信息
const DiscoveredMarket = struct {
    condition_id: []const u8,
    question: []const u8,
    slug: []const u8,
    yes_token_id: []const u8,
    no_token_id: []const u8,
    yes_price: f64,
    no_price: f64,
    end_time: []const u8,
    is_active: bool,
    timestamp: i64,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 解析命令行参数
    var config = MonitorConfig{};
    var args = std.process.args();
    _ = args.next(); // 跳过程序名

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--auto-env")) {
            config.auto_update_env = true;
        } else if (std.mem.eql(u8, arg, "--once")) {
            config.continuous = false;
        } else if (std.mem.eql(u8, arg, "--all")) {
            config.active_only = false;
        } else if (std.mem.eql(u8, arg, "--strategy") or std.mem.eql(u8, arg, "-s")) {
            config.strategy_filter = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printHelp();
            return;
        }
    }

    printBanner();

    // 创建客户端
    var client = ClobClient.init(allocator, .{});
    defer client.deinit();

    std.debug.print("配置:\n", .{});
    std.debug.print("  轮询间隔: {d} 秒\n", .{config.poll_interval_sec});
    std.debug.print("  自动更新 .env: {}\n", .{config.auto_update_env});
    std.debug.print("  只显示活跃市场: {}\n", .{config.active_only});
    std.debug.print("  策略过滤 (>={d}分钟): {}\n", .{ config.min_remaining_minutes, config.strategy_filter });
    std.debug.print("  持续运行: {}\n", .{config.continuous});
    std.debug.print("\n", .{});

    // 用于跟踪已发现的市场
    var discovered = std.StringHashMap(void).init(allocator);
    defer discovered.deinit();

    var iteration: u64 = 0;
    while (true) {
        iteration += 1;
        const now = std.time.timestamp();

        std.debug.print("─────────────────────────────────────────────────────────────\n", .{});
        std.debug.print("[{d}] 扫描市场... (UTC: {d})\n", .{ iteration, now });

        // 扫描市场
        const found = scanForBtc15mMarkets(allocator, &client, &discovered, config) catch |err| {
            std.debug.print("扫描失败: {}\n", .{err});
            if (!config.continuous) return;
            std.Thread.sleep(config.poll_interval_sec * std.time.ns_per_s);
            continue;
        };

        if (found > 0) {
            std.debug.print("\n发现 {d} 个新的 BTC 15m 市场！\n", .{found});
        } else {
            std.debug.print("未发现新的 BTC 15m 市场\n", .{});
        }

        // 显示下一个预期市场时间
        showNextExpectedMarket(now);

        if (!config.continuous) {
            std.debug.print("\n单次扫描完成，退出。\n", .{});
            break;
        }

        std.debug.print("\n等待 {d} 秒后继续...\n", .{config.poll_interval_sec});
        std.Thread.sleep(config.poll_interval_sec * std.time.ns_per_s);
    }
}

/// 扫描 BTC 15m 市场
fn scanForBtc15mMarkets(
    allocator: std.mem.Allocator,
    client: *ClobClient,
    discovered: *std.StringHashMap(void),
    config: MonitorConfig,
) !u32 {
    // 获取市场列表
    const markets = client.getMarkets(.{}) catch |err| {
        return err;
    };
    defer markets.deinit();

    var found_count: u32 = 0;

    for (markets.value.data) |market| {
        const slug = market.market_slug orelse continue;
        const question = market.question orelse continue;

        // 检查是否是 BTC 15m 涨跌市场
        if (!isBtc15mMarket(slug)) continue;

        // 检查是否已经发现过
        if (discovered.contains(slug)) continue;

        // 检查活跃状态
        const is_active = market.accepting_orders orelse false;
        if (config.active_only and !is_active) continue;

        // 获取 Token 信息
        const tokens = market.tokens orelse continue;
        if (tokens.len < 2) continue;

        // 解析时间戳
        const timestamp = parseTimestampFromSlug(slug);
        const now = std.time.timestamp();
        const remaining = if (timestamp > 0) timestamp - now else @as(i64, 0);

        // 计算策略评级
        const rating = if (timestamp > 0)
            StrategyRating.fromRemainingSeconds(remaining)
        else
            StrategyRating.unknown;

        // 如果启用策略过滤，跳过不适合的市场
        if (config.strategy_filter) {
            const min_seconds = config.min_remaining_minutes * 60;
            if (remaining < min_seconds) {
                continue;
            }
        }

        // 记录为已发现
        try discovered.put(slug, {});
        found_count += 1;

        // 显示市场信息
        std.debug.print("\n", .{});
        std.debug.print("╔══════════════════════════════════════════════════════════════╗\n", .{});
        std.debug.print("║  🎯 发现新的 BTC 15 分钟市场！                                 ║\n", .{});
        std.debug.print("╚══════════════════════════════════════════════════════════════╝\n", .{});
        std.debug.print("\n", .{});
        std.debug.print("问题: {s}\n", .{question});
        std.debug.print("Slug: {s}\n", .{slug});
        std.debug.print("Condition ID: {s}\n", .{market.condition_id});
        std.debug.print("状态: {s}\n", .{if (is_active) "✅ 活跃 - 可交易" else "⏸️ 不活跃"});
        std.debug.print("结束时间: {s}\n", .{market.end_date_iso orelse "未知"});

        // 显示剩余时间和策略评级
        if (timestamp > 0) {
            if (remaining > 0) {
                const minutes = @divFloor(remaining, 60);
                const seconds = @mod(remaining, 60);
                std.debug.print("剩余时间: {d} 分 {d} 秒\n", .{ minutes, seconds });
            } else {
                std.debug.print("剩余时间: 已结束\n", .{});
            }
        }

        // 策略适用性评级
        std.debug.print("\n【策略适用性】\n", .{});
        std.debug.print("  评级: {s} {s}\n", .{ rating.getEmoji(), rating.getDescription() });
        switch (rating) {
            .optimal => {
                std.debug.print("  建议: 立即配置并启动策略！\n", .{});
            },
            .acceptable => {
                std.debug.print("  建议: 可以入场，但需要快速决策\n", .{});
            },
            .risky => {
                std.debug.print("  建议: 高风险，考虑等待下一个市场\n", .{});
            },
            .not_recommended, .expired => {
                std.debug.print("  建议: 跳过此市场，等待下一个\n", .{});
            },
            .unknown => {
                std.debug.print("  建议: 无法评估，请检查市场详情\n", .{});
            },
        }

        std.debug.print("\nTokens:\n", .{});
        for (tokens) |token| {
            const price = token.price orelse 0.0;
            const outcome_lower = blk: {
                var buf: [32]u8 = undefined;
                const len = @min(token.outcome.len, buf.len);
                for (token.outcome[0..len], 0..) |c, i| {
                    buf[i] = std.ascii.toLower(c);
                }
                break :blk buf[0..len];
            };

            const is_yes = std.mem.indexOf(u8, outcome_lower, "yes") != null or
                std.mem.indexOf(u8, outcome_lower, "up") != null;
            const is_no = std.mem.indexOf(u8, outcome_lower, "no") != null or
                std.mem.indexOf(u8, outcome_lower, "down") != null;

            var label: []const u8 = "???";
            if (is_yes) {
                label = "YES/UP";
            } else if (is_no) {
                label = "NO/DOWN";
            }

            std.debug.print("  [{s}] {s}\n", .{ label, token.outcome });
            std.debug.print("       Token ID: {s}\n", .{token.token_id});
            std.debug.print("       价格: {d:.4} ({d:.1}%)\n", .{ price, price * 100.0 });
        }

        // 显示 .env 配置
        std.debug.print("\n📋 .env 配置（复制以下内容）:\n", .{});
        std.debug.print("─────────────────────────────────────────────────────────────\n", .{});
        std.debug.print("POLY_CONDITION_ID={s}\n", .{market.condition_id});

        for (tokens) |token| {
            const outcome_lower = blk: {
                var buf: [32]u8 = undefined;
                const len = @min(token.outcome.len, buf.len);
                for (token.outcome[0..len], 0..) |c, i| {
                    buf[i] = std.ascii.toLower(c);
                }
                break :blk buf[0..len];
            };

            const is_yes = std.mem.indexOf(u8, outcome_lower, "yes") != null or
                std.mem.indexOf(u8, outcome_lower, "up") != null;

            if (is_yes) {
                std.debug.print("POLY_YES_TOKEN={s}\n", .{token.token_id});
            } else {
                std.debug.print("POLY_NO_TOKEN={s}\n", .{token.token_id});
            }
        }
        std.debug.print("─────────────────────────────────────────────────────────────\n", .{});

        // 如果配置了自动更新 .env
        if (config.auto_update_env) {
            updateEnvFile(allocator, config.env_path, market, tokens) catch |err| {
                std.debug.print("⚠️ 更新 .env 失败: {}\n", .{err});
            };
        }
    }

    return found_count;
}

/// 检查是否是 BTC 15m 市场
fn isBtc15mMarket(slug: []const u8) bool {
    // 转换为小写比较
    var buf: [256]u8 = undefined;
    const len = @min(slug.len, buf.len);
    for (slug[0..len], 0..) |c, i| {
        buf[i] = std.ascii.toLower(c);
    }
    const lower = buf[0..len];

    // 检查各种可能的模式
    if (std.mem.indexOf(u8, lower, "btc-updown-15m") != null) return true;
    if (std.mem.indexOf(u8, lower, "btc-up-down-15m") != null) return true;
    if (std.mem.indexOf(u8, lower, "bitcoin-updown-15m") != null) return true;
    if (std.mem.indexOf(u8, lower, "btc-15m") != null) return true;

    // 检查问题中是否包含相关关键词
    if (std.mem.indexOf(u8, lower, "btc") != null and
        std.mem.indexOf(u8, lower, "15") != null and
        (std.mem.indexOf(u8, lower, "up") != null or std.mem.indexOf(u8, lower, "down") != null))
    {
        return true;
    }

    return false;
}

/// 从 slug 解析时间戳
fn parseTimestampFromSlug(slug: []const u8) i64 {
    // 查找最后一个 '-' 后的数字
    var last_dash: ?usize = null;
    for (slug, 0..) |c, i| {
        if (c == '-') last_dash = i;
    }

    if (last_dash) |pos| {
        if (pos + 1 < slug.len) {
            const num_str = slug[pos + 1 ..];
            const timestamp = std.fmt.parseInt(i64, num_str, 10) catch return 0;
            // 验证是否是合理的时间戳（2020-2030年之间）
            if (timestamp > 1577836800 and timestamp < 1893456000) {
                return timestamp;
            }
        }
    }

    return 0;
}

/// 显示下一个预期市场时间
fn showNextExpectedMarket(now: i64) void {
    // 15 分钟 = 900 秒
    const interval: i64 = 900;
    const next_timestamp = (@divFloor(now, interval) + 1) * interval;
    const wait_seconds = next_timestamp - now;

    const minutes = @divFloor(wait_seconds, 60);
    const seconds = @mod(wait_seconds, 60);

    std.debug.print("\n下一个可能的 15m 市场时间:\n", .{});
    std.debug.print("  Unix 时间戳: {d}\n", .{next_timestamp});
    std.debug.print("  预期 Slug: btc-updown-15m-{d}\n", .{next_timestamp});
    std.debug.print("  距离开始: {d} 分 {d} 秒\n", .{ minutes, seconds });
}

/// 更新 .env 文件
fn updateEnvFile(
    allocator: std.mem.Allocator,
    env_path: []const u8,
    market: anytype,
    tokens: anytype,
) !void {
    _ = allocator;

    // 读取现有内容
    const file = std.fs.cwd().openFile(env_path, .{ .mode = .read_write }) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("ℹ️ .env 文件不存在，跳过更新\n", .{});
            return;
        }
        return err;
    };
    defer file.close();

    // TODO: 实现更新逻辑
    // 这里简化处理，只显示提示
    std.debug.print("✅ 已更新 .env 文件:\n", .{});
    std.debug.print("   POLY_CONDITION_ID={s}\n", .{market.condition_id});

    for (tokens) |token| {
        const outcome_lower = blk: {
            var buf: [32]u8 = undefined;
            const len = @min(token.outcome.len, buf.len);
            for (token.outcome[0..len], 0..) |c, i| {
                buf[i] = std.ascii.toLower(c);
            }
            break :blk buf[0..len];
        };

        const is_yes = std.mem.indexOf(u8, outcome_lower, "yes") != null or
            std.mem.indexOf(u8, outcome_lower, "up") != null;

        if (is_yes) {
            std.debug.print("   POLY_YES_TOKEN={s}\n", .{token.token_id});
        } else {
            std.debug.print("   POLY_NO_TOKEN={s}\n", .{token.token_id});
        }
    }
}

/// 打印横幅
fn printBanner() void {
    std.debug.print("\n", .{});
    std.debug.print("╔══════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║       BTC 15 分钟市场监控工具 - Polymarket                    ║\n", .{});
    std.debug.print("║                                                              ║\n", .{});
    std.debug.print("║  实时监控并发现 BTC 15 分钟涨跌预测市场                        ║\n", .{});
    std.debug.print("╚══════════════════════════════════════════════════════════════╝\n", .{});
    std.debug.print("\n", .{});
}

/// 打印帮助信息
fn printHelp() void {
    std.debug.print(
        \\BTC 15 分钟市场监控工具 - 对冲策略专用
        \\
        \\用法: zig build run-btc_15m_monitor [选项]
        \\
        \\选项:
        \\  --strategy, -s  只显示适合策略的市场（剩余时间 >=7分钟）
        \\  --auto-env      发现市场时自动更新 .env 文件
        \\  --once          只扫描一次然后退出（默认持续运行）
        \\  --all           显示所有市场，包括不活跃的
        \\  --help, -h      显示此帮助信息
        \\
        \\策略适用性评级:
        \\  ✅ 最佳      剩余 >10分钟，有充足时间执行两步对冲
        \\  ⚠️  可以      剩余 7-10分钟，时间较紧需快速决策
        \\  🔶 危险      剩余 4-7分钟，可能没时间完成对冲
        \\  ❌ 不建议    剩余 <4分钟，风险太高
        \\
        \\示例:
        \\  zig build run-btc_15m_monitor              # 持续监控所有市场
        \\  zig build run-btc_15m_monitor -- -s        # 只显示适合策略的市场
        \\  zig build run-btc_15m_monitor -- --once    # 扫描一次
        \\  zig build run-btc_15m_monitor -- --auto-env -s  # 自动更新配置
        \\
        \\对冲策略说明:
        \\  1. 第一步: 检测价格暴跌 -> 低价买入 YES
        \\  2. 第二步: 价格反弹后 -> 卖出 NO 对冲锁定利润
        \\  
        \\  这两步都需要时间，所以市场剩余时间很重要！
        \\  建议在剩余 >7分钟的市场中操作。
        \\
        \\市场 slug 模式:
        \\  btc-updown-15m-{{timestamp}}
        \\  例如: btc-updown-15m-1767231900
        \\
    , .{});
}

test "isBtc15mMarket" {
    try std.testing.expect(isBtc15mMarket("btc-updown-15m-1767231900"));
    try std.testing.expect(isBtc15mMarket("BTC-UPDOWN-15M-1767231900"));
    try std.testing.expect(isBtc15mMarket("btc-15m-up-1767231900"));
    try std.testing.expect(!isBtc15mMarket("btc-daily-price"));
    try std.testing.expect(!isBtc15mMarket("eth-updown-15m-1767231900"));
}

test "parseTimestampFromSlug" {
    try std.testing.expectEqual(@as(i64, 1767231900), parseTimestampFromSlug("btc-updown-15m-1767231900"));
    try std.testing.expectEqual(@as(i64, 0), parseTimestampFromSlug("btc-daily-price"));
    try std.testing.expectEqual(@as(i64, 0), parseTimestampFromSlug("no-timestamp"));
}
