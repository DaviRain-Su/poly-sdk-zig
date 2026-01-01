//! BTC 15分钟市场自动交易系统
//!
//! 功能：
//! - 自动监控并发现 BTC 15分钟涨跌市场
//! - 评估市场适用性（剩余时间分析）
//! - 自动配置并执行对冲策略
//! - 市场结束后自动切换到下一个市场
//!
//! 工作流程：
//! 1. 监控阶段：寻找新的 BTC 15m 市场
//! 2. 评估阶段：检查剩余时间是否足够（>=7分钟）
//! 3. 策略阶段：执行两步对冲（买 YES + 卖 NO）
//! 4. 等待阶段：等待下一个市场创建
//! 5. 循环...
//!
//! 运行: zig build run-btc_auto_trader
//!
//! 配置（.env 文件）：
//! - POLY_PRIVATE_KEY: 钱包私钥
//! - POLY_API_KEY, POLY_API_SECRET, POLY_API_PASSPHRASE: API 凭证
//! - AUTO_TRADER_MIN_REMAINING_MINUTES: 最小剩余时间（默认 7）
//! - AUTO_TRADER_DRY_RUN: 模拟模式，不实际下单（默认 true）

const std = @import("std");
const poly = @import("poly_sdk_zig");

const ClobClient = poly.ClobClient;
const Wallet = poly.Wallet;
const ApiCreds = poly.ApiCreds;
const Decimal = poly.Decimal;
const OrderBuilder = poly.OrderBuilder;
const Side = poly.Side;

// ============================================================================
// 配置
// ============================================================================

/// 自动交易配置
const AutoTraderConfig = struct {
    /// 最小剩余时间（分钟）- 低于此时间不入场
    min_remaining_minutes: i64 = 7,

    /// 市场扫描间隔（秒）
    scan_interval_sec: u64 = 5,

    /// 价格监控间隔（毫秒）
    price_poll_interval_ms: u64 = 500,

    /// 是否为模拟模式（不实际下单）
    dry_run: bool = true,

    /// 目标累计买入比例 (0-1)
    sum_target: f64 = 0.3,

    /// 触发监控的价格下跌幅度 (0-1)
    move_threshold: f64 = 0.01,

    /// 最低买入价格阈值
    min_buy_price: f64 = 0.15,

    /// 对冲触发的最小价差
    hedge_spread: f64 = 0.05,

    /// 单次最大买入金额 (USDC)
    max_position_size: f64 = 100.0,

    /// 是否使用测试网
    use_testnet: bool = false,
};

/// 市场信息
const MarketInfo = struct {
    condition_id: []const u8,
    yes_token_id: []const u8,
    no_token_id: []const u8,
    slug: []const u8,
    end_timestamp: i64,
    remaining_seconds: i64,

    pub fn getRemainingMinutes(self: MarketInfo) i64 {
        return @divFloor(self.remaining_seconds, 60);
    }
};

/// 策略评级
const StrategyRating = enum {
    optimal, // >10分钟
    acceptable, // 7-10分钟
    risky, // 4-7分钟
    not_recommended, // <4分钟
    expired, // 已结束

    pub fn fromRemainingSeconds(remaining: i64) StrategyRating {
        if (remaining <= 0) return .expired;
        if (remaining < 4 * 60) return .not_recommended;
        if (remaining < 7 * 60) return .risky;
        if (remaining < 10 * 60) return .acceptable;
        return .optimal;
    }

    pub fn getEmoji(self: StrategyRating) []const u8 {
        return switch (self) {
            .optimal => "✅",
            .acceptable => "⚠️",
            .risky => "🔶",
            .not_recommended => "❌",
            .expired => "⏹️",
        };
    }

    pub fn isTradeWorthy(self: StrategyRating) bool {
        return self == .optimal or self == .acceptable;
    }
};

/// 交易状态
const TradeState = struct {
    /// 当前持有的 YES 股份数量
    yes_position: f64 = 0,
    /// YES 买入总成本
    yes_cost: f64 = 0,
    /// YES 买入均价
    yes_avg_price: f64 = 0,
    /// 是否已对冲
    is_hedged: bool = false,
    /// 已锁定利润
    locked_profit: f64 = 0,
    /// 历史最高价
    high_water_mark: f64 = 0,

    pub fn updateAvgPrice(self: *TradeState, new_size: f64, new_price: f64) void {
        const new_cost = new_size * new_price;
        self.yes_cost += new_cost;
        self.yes_position += new_size;
        if (self.yes_position > 0) {
            self.yes_avg_price = self.yes_cost / self.yes_position;
        }
    }

    pub fn reset(self: *TradeState) void {
        self.yes_position = 0;
        self.yes_cost = 0;
        self.yes_avg_price = 0;
        self.is_hedged = false;
        self.locked_profit = 0;
        self.high_water_mark = 0;
    }
};

/// 交易统计
const TradingStats = struct {
    markets_traded: u32 = 0,
    total_profit: f64 = 0,
    total_cost: f64 = 0,
    successful_hedges: u32 = 0,
    failed_hedges: u32 = 0,
};

// ============================================================================
// 自动交易系统
// ============================================================================

const AutoTrader = struct {
    allocator: std.mem.Allocator,
    config: AutoTraderConfig,
    client: *ClobClient,
    wallet: ?*const Wallet,
    builder: ?OrderBuilder,
    state: TradeState,
    stats: TradingStats,
    current_market: ?MarketInfo,
    running: bool,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        client: *ClobClient,
        wallet: ?*const Wallet,
        config: AutoTraderConfig,
    ) Self {
        return Self{
            .allocator = allocator,
            .config = config,
            .client = client,
            .wallet = wallet,
            .builder = if (wallet) |w| OrderBuilder.init(w, .{
                .chain_id = if (config.use_testnet) 80002 else 137,
            }) else null,
            .state = TradeState{},
            .stats = TradingStats{},
            .current_market = null,
            .running = true,
        };
    }

    /// 主运行循环
    pub fn run(self: *Self) !void {
        self.printBanner();

        while (self.running) {
            // 阶段 1: 寻找市场
            log("", .{});
            log("═══════════════════════════════════════════════════════════", .{});
            log("阶段 1: 寻找 BTC 15m 市场...", .{});
            log("═══════════════════════════════════════════════════════════", .{});

            const market = self.findSuitableMarket() catch |err| {
                log("扫描市场失败: {}, 等待重试...", .{err});
                std.Thread.sleep(self.config.scan_interval_sec * std.time.ns_per_s);
                continue;
            };

            if (market) |m| {
                self.current_market = m;
                log("", .{});
                log("🎯 发现适合的市场!", .{});
                log("   Slug: {s}", .{m.slug});
                log("   剩余时间: {d} 分钟", .{m.getRemainingMinutes()});
                log("   YES Token: {s}", .{m.yes_token_id});
                log("   NO Token: {s}", .{m.no_token_id});

                // 阶段 2: 执行策略
                log("", .{});
                log("═══════════════════════════════════════════════════════════", .{});
                log("阶段 2: 执行对冲策略...", .{});
                log("═══════════════════════════════════════════════════════════", .{});

                self.executeStrategy(m) catch |err| {
                    log("策略执行失败: {}", .{err});
                    self.stats.failed_hedges += 1;
                };

                // 阶段 3: 等待市场结束
                log("", .{});
                log("═══════════════════════════════════════════════════════════", .{});
                log("阶段 3: 等待市场结束...", .{});
                log("═══════════════════════════════════════════════════════════", .{});

                self.waitForMarketEnd(m);

                // 重置状态，准备下一轮
                self.state.reset();
                self.current_market = null;
                self.stats.markets_traded += 1;
            } else {
                // 没有找到合适的市场，显示下一个预期时间
                self.showNextExpectedMarket();
                std.Thread.sleep(self.config.scan_interval_sec * std.time.ns_per_s);
            }
        }

        self.printFinalStats();
    }

    /// 寻找适合的市场
    fn findSuitableMarket(self: *Self) !?MarketInfo {
        const markets = self.client.getMarkets(.{}) catch |err| {
            return err;
        };
        defer markets.deinit();

        const now = std.time.timestamp();

        for (markets.value.data) |market| {
            const slug = market.market_slug orelse continue;

            // 检查是否是 BTC 15m 市场
            if (!isBtc15mMarket(slug)) continue;

            // 检查是否活跃
            const is_active = market.accepting_orders orelse false;
            if (!is_active) continue;

            // 解析时间戳
            const end_timestamp = parseTimestampFromSlug(slug);
            if (end_timestamp == 0) continue;

            const remaining = end_timestamp - now;
            const rating = StrategyRating.fromRemainingSeconds(remaining);

            // 检查是否满足最小时间要求
            if (remaining < self.config.min_remaining_minutes * 60) {
                log("跳过市场 {s}: 剩余 {d} 分钟 (需要 >={d})", .{
                    slug,
                    @divFloor(remaining, 60),
                    self.config.min_remaining_minutes,
                });
                continue;
            }

            // 找到合适的市场
            log("评估市场: {s} - {s} 剩余 {d} 分钟", .{
                slug,
                rating.getEmoji(),
                @divFloor(remaining, 60),
            });

            // 获取 Token 信息
            const tokens = market.tokens orelse continue;
            if (tokens.len < 2) continue;

            var yes_token: ?[]const u8 = null;
            var no_token: ?[]const u8 = null;

            for (tokens) |token| {
                const outcome_lower = toLower(token.outcome);
                const is_yes = std.mem.indexOf(u8, &outcome_lower, "yes") != null or
                    std.mem.indexOf(u8, &outcome_lower, "up") != null;

                if (is_yes) {
                    yes_token = token.token_id;
                } else {
                    no_token = token.token_id;
                }
            }

            if (yes_token == null or no_token == null) continue;

            return MarketInfo{
                .condition_id = market.condition_id,
                .yes_token_id = yes_token.?,
                .no_token_id = no_token.?,
                .slug = slug,
                .end_timestamp = end_timestamp,
                .remaining_seconds = remaining,
            };
        }

        return null;
    }

    /// 执行对冲策略
    fn executeStrategy(self: *Self, market: MarketInfo) !void {
        const end_time = market.end_timestamp;
        var iteration: u64 = 0;

        while (self.running and !self.state.is_hedged) {
            iteration += 1;
            const now = std.time.timestamp();
            const remaining = end_time - now;

            // 检查是否还有足够时间
            if (remaining < 2 * 60) { // 剩余不到 2 分钟，停止交易
                log("⏰ 剩余时间不足 2 分钟，停止策略", .{});
                break;
            }

            // 获取当前价格
            const current_price = self.getYesPrice(market.yes_token_id) catch |err| {
                log("获取价格失败: {}, 重试...", .{err});
                std.Thread.sleep(self.config.price_poll_interval_ms * std.time.ns_per_ms);
                continue;
            };

            // 定期日志
            if (iteration % 20 == 1) {
                const mins = @divFloor(remaining, 60);
                const secs = @mod(remaining, 60);
                log("[{d}] YES={d:.4} 均价={d:.4} 持仓={d:.2} 剩余={d}:{d:0>2}", .{
                    iteration,
                    current_price,
                    self.state.yes_avg_price,
                    self.state.yes_position,
                    mins,
                    secs,
                });
            }

            // 策略逻辑：买入
            if (self.detectCrash(current_price)) {
                const buy_size = self.calculateBuySize(current_price);
                if (buy_size > 0) {
                    log("🔻 检测到暴跌! 价格={d:.4}", .{current_price});
                    try self.executeBuy(market, buy_size, current_price);
                }
            }

            // 策略逻辑：对冲
            if (self.shouldHedge(current_price)) {
                log("📈 触发对冲! 价格={d:.4} 均价={d:.4}", .{
                    current_price,
                    self.state.yes_avg_price,
                });
                try self.executeHedge(market, current_price);
            }

            std.Thread.sleep(self.config.price_poll_interval_ms * std.time.ns_per_ms);
        }

        // 打印本轮结果
        self.printRoundSummary();
    }

    /// 获取 YES 价格
    fn getYesPrice(self: *Self, token_id: []const u8) !f64 {
        const price_resp = self.client.getPrice(token_id, .BUY) catch |err| {
            return err;
        };

        if (price_resp.price) |price_str| {
            return std.fmt.parseFloat(f64, price_str) catch 0;
        }
        return error.NoPriceAvailable;
    }

    /// 检测暴跌
    fn detectCrash(self: *Self, current_price: f64) bool {
        if (current_price > self.state.high_water_mark) {
            self.state.high_water_mark = current_price;
        }

        if (self.state.high_water_mark > 0) {
            const drop = (self.state.high_water_mark - current_price) / self.state.high_water_mark;
            return drop >= self.config.move_threshold;
        }

        return false;
    }

    /// 计算买入量
    fn calculateBuySize(self: *Self, current_price: f64) f64 {
        if (current_price >= self.config.min_buy_price) {
            return 0;
        }

        const current_sum = self.state.yes_position * self.state.yes_avg_price;
        const target_sum = self.config.sum_target * self.config.max_position_size;

        if (current_sum >= target_sum) {
            return 0;
        }

        const remaining = target_sum - current_sum;
        const size = remaining / current_price;
        return @min(size, self.config.max_position_size / current_price * 0.1);
    }

    /// 检查是否应该对冲
    fn shouldHedge(self: *Self, current_price: f64) bool {
        if (self.state.is_hedged or self.state.yes_position == 0) {
            return false;
        }
        const spread = current_price - self.state.yes_avg_price;
        return spread >= self.config.hedge_spread;
    }

    /// 执行买入
    fn executeBuy(self: *Self, market: MarketInfo, size: f64, price: f64) !void {
        log("准备买入 YES: 数量={d:.2} 价格={d:.4}", .{ size, price });

        if (self.config.dry_run) {
            log("【模拟模式】跳过实际下单", .{});
            self.state.updateAvgPrice(size, price);
            return;
        }

        if (self.builder) |*builder| {
            const price_str = try std.fmt.allocPrint(self.allocator, "{d:.4}", .{price});
            defer self.allocator.free(price_str);
            const size_str = try std.fmt.allocPrint(self.allocator, "{d:.2}", .{size});
            defer self.allocator.free(size_str);

            const price_decimal = try Decimal.fromString(price_str);
            const size_decimal = try Decimal.fromString(size_str);

            const order = try builder.createOrder(.{
                .token_id = market.yes_token_id,
                .price = price_decimal,
                .size = size_decimal,
                .side = .BUY,
            }, .{
                .tick_size = .@"0.01",
                .neg_risk = false,
            });

            const response = try self.client.postOrder(&order, .FAK);

            if (response.success) {
                log("✅ YES 买入成功! 订单ID: {s}", .{response.orderID orelse "N/A"});
                self.state.updateAvgPrice(size, price);
            } else {
                log("❌ YES 买入失败: {s}", .{response.errorMsg orelse "未知错误"});
            }
        }
    }

    /// 执行对冲
    fn executeHedge(self: *Self, market: MarketInfo, current_yes_price: f64) !void {
        const no_price = 1.0 - current_yes_price;
        const size = self.state.yes_position;

        log("准备对冲卖出 NO: 数量={d:.2} NO价格={d:.4}", .{ size, no_price });

        if (self.config.dry_run) {
            log("【模拟模式】跳过实际下单", .{});
            const locked_value = size * 1.0;
            const profit = locked_value - self.state.yes_cost;
            self.state.is_hedged = true;
            self.state.locked_profit = profit;
            self.stats.successful_hedges += 1;
            self.stats.total_profit += profit;
            self.stats.total_cost += self.state.yes_cost;
            log("【模拟】对冲成功! 锁定利润: ${d:.2}", .{profit});
            return;
        }

        if (self.builder) |*builder| {
            const price_str = try std.fmt.allocPrint(self.allocator, "{d:.4}", .{no_price});
            defer self.allocator.free(price_str);
            const size_str = try std.fmt.allocPrint(self.allocator, "{d:.2}", .{size});
            defer self.allocator.free(size_str);

            const price_decimal = try Decimal.fromString(price_str);
            const size_decimal = try Decimal.fromString(size_str);

            const order = try builder.createOrder(.{
                .token_id = market.no_token_id,
                .price = price_decimal,
                .size = size_decimal,
                .side = .SELL,
            }, .{
                .tick_size = .@"0.01",
                .neg_risk = false,
            });

            const response = try self.client.postOrder(&order, .FAK);

            if (response.success) {
                const locked_value = size * 1.0;
                const profit = locked_value - self.state.yes_cost;
                self.state.is_hedged = true;
                self.state.locked_profit = profit;
                self.stats.successful_hedges += 1;
                self.stats.total_profit += profit;
                self.stats.total_cost += self.state.yes_cost;
                log("✅ 对冲成功! 锁定利润: ${d:.2}", .{profit});
            } else {
                log("❌ 对冲失败: {s}", .{response.errorMsg orelse "未知错误"});
                self.stats.failed_hedges += 1;
            }
        }
    }

    /// 等待市场结束
    fn waitForMarketEnd(self: *Self, market: MarketInfo) void {
        _ = self;
        const end_time = market.end_timestamp;

        while (true) {
            const now = std.time.timestamp();
            const remaining = end_time - now;

            if (remaining <= 0) {
                log("市场已结束", .{});
                break;
            }

            const mins = @divFloor(remaining, 60);
            const secs = @mod(remaining, 60);
            log("等待市场结束... 剩余 {d}:{d:0>2}", .{ mins, secs });

            // 每 30 秒检查一次
            const sleep_time: u64 = @min(@as(u64, @intCast(remaining)), 30);
            std.Thread.sleep(sleep_time * @as(u64, std.time.ns_per_s));
        }
    }

    /// 显示下一个预期市场时间
    fn showNextExpectedMarket(self: *Self) void {
        _ = self;
        const now = std.time.timestamp();
        const interval: i64 = 900; // 15 分钟
        const next_timestamp = (@divFloor(now, interval) + 1) * interval;
        const wait_seconds = next_timestamp - now;

        const minutes = @divFloor(wait_seconds, 60);
        const seconds = @mod(wait_seconds, 60);

        log("未找到适合的市场", .{});
        log("下一个预期市场: btc-updown-15m-{d}", .{next_timestamp});
        log("距离开始: {d} 分 {d} 秒", .{ minutes, seconds });
    }

    /// 打印本轮总结
    fn printRoundSummary(self: *Self) void {
        log("", .{});
        log("--- 本轮交易总结 ---", .{});
        log("YES 持仓: {d:.2}", .{self.state.yes_position});
        log("YES 成本: ${d:.2}", .{self.state.yes_cost});
        log("YES 均价: {d:.4}", .{self.state.yes_avg_price});
        log("对冲状态: {s}", .{if (self.state.is_hedged) "已对冲" else "未对冲"});
        log("锁定利润: ${d:.2}", .{self.state.locked_profit});
    }

    /// 打印最终统计
    fn printFinalStats(self: *Self) void {
        log("", .{});
        log("╔══════════════════════════════════════════════════════════════╗", .{});
        log("║                      最终交易统计                             ║", .{});
        log("╚══════════════════════════════════════════════════════════════╝", .{});
        log("交易市场数: {d}", .{self.stats.markets_traded});
        log("成功对冲: {d}", .{self.stats.successful_hedges});
        log("失败对冲: {d}", .{self.stats.failed_hedges});
        log("总成本: ${d:.2}", .{self.stats.total_cost});
        log("总利润: ${d:.2}", .{self.stats.total_profit});
        if (self.stats.total_cost > 0) {
            const roi = self.stats.total_profit / self.stats.total_cost * 100;
            log("总收益率: {d:.1}%", .{roi});
        }
    }

    fn printBanner(self: *Self) void {
        std.debug.print("\n", .{});
        std.debug.print("╔══════════════════════════════════════════════════════════════╗\n", .{});
        std.debug.print("║     BTC 15分钟市场自动交易系统 - Polymarket                   ║\n", .{});
        std.debug.print("╠══════════════════════════════════════════════════════════════╣\n", .{});
        std.debug.print("║  功能: 自动监控 -> 发现市场 -> 执行策略 -> 循环               ║\n", .{});
        std.debug.print("╚══════════════════════════════════════════════════════════════╝\n", .{});
        std.debug.print("\n", .{});
        std.debug.print("配置:\n", .{});
        std.debug.print("  模式: {s}\n", .{if (self.config.dry_run) "模拟交易 (DRY RUN)" else "实盘交易"});
        std.debug.print("  最小剩余时间: {d} 分钟\n", .{self.config.min_remaining_minutes});
        std.debug.print("  目标累计: {d:.0}%\n", .{self.config.sum_target * 100});
        std.debug.print("  下跌阈值: {d:.0}%\n", .{self.config.move_threshold * 100});
        std.debug.print("  最低买入价: {d:.2}\n", .{self.config.min_buy_price});
        std.debug.print("  对冲价差: {d:.2}\n", .{self.config.hedge_spread});
        std.debug.print("  网络: {s}\n", .{if (self.config.use_testnet) "测试网" else "主网"});
        std.debug.print("\n", .{});

        if (self.config.dry_run) {
            std.debug.print("⚠️  模拟模式：不会实际下单，仅用于测试策略逻辑\n", .{});
            std.debug.print("   要启用实盘交易，请设置 AUTO_TRADER_DRY_RUN=false\n", .{});
            std.debug.print("\n", .{});
        }
    }

    pub fn stop(self: *Self) void {
        self.running = false;
    }
};

// ============================================================================
// 辅助函数
// ============================================================================

fn isBtc15mMarket(slug: []const u8) bool {
    const lower = toLower(slug);
    if (std.mem.indexOf(u8, &lower, "btc-updown-15m") != null) return true;
    if (std.mem.indexOf(u8, &lower, "btc-up-down-15m") != null) return true;
    if (std.mem.indexOf(u8, &lower, "bitcoin-updown-15m") != null) return true;
    if (std.mem.indexOf(u8, &lower, "btc-15m") != null) return true;
    return false;
}

fn parseTimestampFromSlug(slug: []const u8) i64 {
    var last_dash: ?usize = null;
    for (slug, 0..) |c, i| {
        if (c == '-') last_dash = i;
    }

    if (last_dash) |pos| {
        if (pos + 1 < slug.len) {
            const num_str = slug[pos + 1 ..];
            const timestamp = std.fmt.parseInt(i64, num_str, 10) catch return 0;
            if (timestamp > 1577836800 and timestamp < 1893456000) {
                return timestamp;
            }
        }
    }
    return 0;
}

fn toLower(s: []const u8) [256]u8 {
    var buf: [256]u8 = undefined;
    const len = @min(s.len, buf.len);
    for (s[0..len], 0..) |c, i| {
        buf[i] = std.ascii.toLower(c);
    }
    // 填充剩余
    for (len..256) |i| {
        buf[i] = 0;
    }
    return buf;
}

fn log(comptime fmt: []const u8, args: anytype) void {
    const timestamp = std.time.timestamp();
    std.debug.print("[{d}] " ++ fmt ++ "\n", .{timestamp} ++ args);
}

// ============================================================================
// 主程序
// ============================================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 加载配置
    var env = poly.loadEnvOrEmpty(allocator, ".env");
    defer env.deinit();

    // 解析配置
    const config = AutoTraderConfig{
        .min_remaining_minutes = env.getInt(i64, "AUTO_TRADER_MIN_REMAINING_MINUTES", 7),
        .dry_run = env.getBool("AUTO_TRADER_DRY_RUN", true),
        .sum_target = env.getFloat(f64, "STRATEGY_SUM_TARGET", 0.3),
        .move_threshold = env.getFloat(f64, "STRATEGY_MOVE_THRESHOLD", 0.01),
        .min_buy_price = env.getFloat(f64, "STRATEGY_MIN_BUY_PRICE", 0.15),
        .hedge_spread = env.getFloat(f64, "STRATEGY_HEDGE_SPREAD", 0.05),
        .max_position_size = env.getFloat(f64, "STRATEGY_MAX_POSITION", 100.0),
        .use_testnet = env.getBool("POLY_USE_TESTNET", false),
    };

    // 创建客户端配置
    const client_config = poly.clob.client.Config{
        .base_url = if (config.use_testnet) poly.clob.client.BASE_URL_TESTNET else poly.clob.client.BASE_URL_MAINNET,
    };

    // 如果不是模拟模式，需要加载凭证
    var wallet: ?Wallet = null;
    var creds: ?ApiCreds = null;
    var client: ClobClient = undefined;

    if (!config.dry_run) {
        const private_key = env.get("POLY_PRIVATE_KEY") orelse {
            std.debug.print("错误: 实盘模式需要设置 POLY_PRIVATE_KEY\n", .{});
            std.debug.print("提示: 设置 AUTO_TRADER_DRY_RUN=true 可使用模拟模式\n", .{});
            return error.MissingCredentials;
        };

        wallet = Wallet.fromPrivateKeyHex(private_key) catch |err| {
            std.debug.print("钱包初始化失败: {}\n", .{err});
            return err;
        };

        std.debug.print("钱包地址: 0x", .{});
        for (wallet.?.address_bytes) |b| {
            std.debug.print("{x:0>2}", .{b});
        }
        std.debug.print("\n\n", .{});

        // 检查是否提供了 API 凭证，如果没有则自动获取
        const api_key = env.get("POLY_API_KEY");
        const api_secret = env.get("POLY_API_SECRET");
        const api_passphrase = env.get("POLY_API_PASSPHRASE");

        if (api_key != null and api_secret != null and api_passphrase != null) {
            // 使用提供的凭证
            std.debug.print("使用已配置的 API 凭证\n", .{});
            creds = try ApiCreds.init(allocator, api_key.?, api_secret.?, api_passphrase.?);
            client = ClobClient.initWithAuth(allocator, client_config, &wallet.?, &creds.?);
        } else {
            // 自动获取 API 凭证
            std.debug.print("未配置 API 凭证，正在通过 L1 认证自动获取...\n", .{});

            // 先创建一个只有钱包的客户端用于 L1 认证
            client = ClobClient.init(allocator, client_config);
            client.setWallet(&wallet.?);

            // 创建或派生 API Key
            creds = client.createOrDeriveApiKey() catch |err| {
                std.debug.print("获取 API 凭证失败: {}\n", .{err});
                std.debug.print("\n提示: 你可以手动设置 API 凭证:\n", .{});
                std.debug.print("  POLY_API_KEY=xxx\n", .{});
                std.debug.print("  POLY_API_SECRET=xxx\n", .{});
                std.debug.print("  POLY_API_PASSPHRASE=xxx\n", .{});
                return err;
            };

            std.debug.print("✅ API 凭证获取成功!\n", .{});
            std.debug.print("   API Key: {s}...\n", .{creds.?.api_key[0..8]});

            // 设置凭证到客户端
            client.setApiCreds(&creds.?);
        }
    } else {
        // 模拟模式，不需要认证
        client = ClobClient.init(allocator, client_config);
    }
    defer client.deinit();
    defer if (creds) |*c| c.deinit();

    // 创建自动交易系统
    var trader = AutoTrader.init(
        allocator,
        &client,
        if (wallet) |*w| w else null,
        config,
    );

    // 设置信号处理（优雅退出）
    // 注意：Zig 标准库没有简单的信号处理，这里用 Ctrl+C 自然退出

    // 运行
    try trader.run();
}
