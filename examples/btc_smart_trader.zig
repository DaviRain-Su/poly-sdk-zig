//! BTC 15分钟市场智能交易系统 v2
//!
//! 改进版策略：
//! 1. 真实价差分析 - 忽略边缘订单，找到真正的买卖价差
//! 2. 做市商策略 - 在价差两侧挂单赚取价差
//! 3. 概率偏差检测 - 当 UP + DOWN != 1.0 时套利
//! 4. 趋势跟随 - 跟随中间价格趋势
//!
//! 运行: zig build run-btc_smart_trader
//!
//! 配置（.env 文件）：
//! - POLY_PRIVATE_KEY: 钱包私钥
//! - POLY_API_KEY, POLY_API_SECRET, POLY_API_PASSPHRASE: API 凭证
//! - SMART_TRADER_MODE: 策略模式 (market_maker/trend/arbitrage)
//! - SMART_TRADER_DRY_RUN: 模拟模式（默认 true）

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

/// 策略模式
const StrategyMode = enum {
    /// 做市商模式：在价差两侧挂单
    market_maker,
    /// 趋势跟随：跟随价格趋势
    trend_follower,
    /// 套利模式：利用 UP + DOWN != 1.0 套利
    arbitrage,
    /// 混合模式：同时使用多种策略
    hybrid,
};

/// 智能交易配置
const SmartTraderConfig = struct {
    /// 策略模式
    mode: StrategyMode = .hybrid,

    /// 模拟模式（不实际下单）
    dry_run: bool = true,

    /// 最小剩余时间（分钟）
    min_remaining_minutes: i64 = 5,

    /// 价格刷新间隔（毫秒）
    refresh_interval_ms: u64 = 1000,

    /// 忽略边缘价格的阈值（低于此价格或高于 1-此价格 的订单被忽略）
    edge_price_threshold: f64 = 0.20,

    /// 做市商：最小价差要求
    mm_min_spread: f64 = 0.02,

    /// 做市商：单边挂单量 (USDC)
    mm_order_size: f64 = 50.0,

    /// 套利：UP + DOWN 偏离 1.0 的阈值
    arb_threshold: f64 = 0.02,

    /// 趋势：触发交易的价格变化阈值
    trend_threshold: f64 = 0.05,

    /// 最大仓位 (USDC)
    max_position: f64 = 200.0,

    /// 是否使用测试网
    use_testnet: bool = false,
};

/// 市场信息
const MarketInfo = struct {
    condition_id_buf: [128]u8 = undefined,
    condition_id_len: usize = 0,
    up_token_id_buf: [128]u8 = undefined,
    up_token_id_len: usize = 0,
    down_token_id_buf: [128]u8 = undefined,
    down_token_id_len: usize = 0,
    slug_buf: [64]u8 = undefined,
    slug_len: usize = 0,
    end_timestamp: i64,

    pub fn getConditionId(self: *const MarketInfo) []const u8 {
        return self.condition_id_buf[0..self.condition_id_len];
    }

    pub fn getUpTokenId(self: *const MarketInfo) []const u8 {
        return self.up_token_id_buf[0..self.up_token_id_len];
    }

    pub fn getDownTokenId(self: *const MarketInfo) []const u8 {
        return self.down_token_id_buf[0..self.down_token_id_len];
    }

    pub fn getSlug(self: *const MarketInfo) []const u8 {
        return self.slug_buf[0..self.slug_len];
    }

    pub fn getRemainingSeconds(self: *const MarketInfo) i64 {
        return self.end_timestamp - std.time.timestamp();
    }
};

/// 订单簿分析结果
const OrderBookAnalysis = struct {
    /// 真实最高买价（忽略边缘订单）
    real_best_bid: f64,
    /// 真实最低卖价（忽略边缘订单）
    real_best_ask: f64,
    /// 真实价差
    real_spread: f64,
    /// 中间价
    mid_price: f64,
    /// 边缘买价深度（0.01-0.20）
    edge_bid_depth: f64,
    /// 边缘卖价深度（0.80-0.99）
    edge_ask_depth: f64,
    /// 中间区域买盘深度
    mid_bid_depth: f64,
    /// 中间区域卖盘深度
    mid_ask_depth: f64,
    /// 是否有有效订单簿
    is_valid: bool,
};

/// 市场状态快照
const MarketSnapshot = struct {
    timestamp: i64,
    up_analysis: OrderBookAnalysis,
    down_analysis: OrderBookAnalysis,
    /// UP 中间价 + DOWN 中间价（理论上应该 = 1.0）
    probability_sum: f64,
    /// 套利机会类型
    arb_opportunity: ArbOpportunity,
};

/// 套利机会
const ArbOpportunity = enum {
    none,
    /// UP + DOWN < 1.0，买入两边可套利
    buy_both,
    /// UP + DOWN > 1.0，卖出两边可套利
    sell_both,
};

/// 交易信号
const TradeSignal = struct {
    action: Action,
    token: Token,
    price: f64,
    size: f64,
    reason: []const u8,

    const Action = enum { buy, sell, cancel };
    const Token = enum { up, down };
};

/// 持仓状态
const Position = struct {
    up_shares: f64 = 0,
    up_avg_price: f64 = 0,
    up_cost: f64 = 0,
    down_shares: f64 = 0,
    down_avg_price: f64 = 0,
    down_cost: f64 = 0,
    /// 活跃的限价单
    pending_orders: u32 = 0,

    pub fn totalCost(self: *const Position) f64 {
        return self.up_cost + self.down_cost;
    }

    pub fn updateUp(self: *Position, shares: f64, price: f64) void {
        const cost = shares * price;
        self.up_cost += cost;
        self.up_shares += shares;
        if (self.up_shares > 0) {
            self.up_avg_price = self.up_cost / self.up_shares;
        }
    }

    pub fn updateDown(self: *Position, shares: f64, price: f64) void {
        const cost = shares * price;
        self.down_cost += cost;
        self.down_shares += shares;
        if (self.down_shares > 0) {
            self.down_avg_price = self.down_cost / self.down_shares;
        }
    }

    pub fn reset(self: *Position) void {
        self.up_shares = 0;
        self.up_avg_price = 0;
        self.up_cost = 0;
        self.down_shares = 0;
        self.down_avg_price = 0;
        self.down_cost = 0;
        self.pending_orders = 0;
    }
};

/// 交易统计
const TradingStats = struct {
    markets_traded: u32 = 0,
    total_trades: u32 = 0,
    winning_trades: u32 = 0,
    losing_trades: u32 = 0,
    total_profit: f64 = 0,
    total_cost: f64 = 0,
    max_drawdown: f64 = 0,

    pub fn winRate(self: *const TradingStats) f64 {
        const total = self.winning_trades + self.losing_trades;
        if (total == 0) return 0;
        return @as(f64, @floatFromInt(self.winning_trades)) / @as(f64, @floatFromInt(total)) * 100.0;
    }
};

// ============================================================================
// 智能交易系统
// ============================================================================

const SmartTrader = struct {
    allocator: std.mem.Allocator,
    config: SmartTraderConfig,
    client: *ClobClient,
    wallet: ?*const Wallet,
    builder: ?OrderBuilder,
    position: Position,
    stats: TradingStats,
    current_market: ?MarketInfo,
    last_snapshot: ?MarketSnapshot,
    price_history: [60]f64, // 最近 60 个价格样本
    price_history_idx: usize,
    running: bool,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        client: *ClobClient,
        wallet: ?*const Wallet,
        config: SmartTraderConfig,
    ) Self {
        return Self{
            .allocator = allocator,
            .config = config,
            .client = client,
            .wallet = wallet,
            .builder = if (wallet) |w| OrderBuilder.init(w, .{
                .chain_id = if (config.use_testnet) 80002 else 137,
            }) else null,
            .position = Position{},
            .stats = TradingStats{},
            .current_market = null,
            .last_snapshot = null,
            .price_history = [_]f64{0} ** 60,
            .price_history_idx = 0,
            .running = true,
        };
    }

    /// 主运行循环
    pub fn run(self: *Self) !void {
        self.printBanner();

        while (self.running) {
            // 阶段 1: 寻找市场
            log("", .{});
            log("════════════════════════════════════════════════════════════════", .{});
            log("  寻找 BTC 15分钟市场...", .{});
            log("════════════════════════════════════════════════════════════════", .{});

            const market = self.findSuitableMarket() catch |err| {
                log("扫描市场失败: {}, 5秒后重试...", .{err});
                std.Thread.sleep(5 * std.time.ns_per_s);
                continue;
            };

            if (market) |m| {
                self.current_market = m;
                const remaining = m.getRemainingSeconds();

                log("", .{});
                log("  发现市场: {s}", .{m.getSlug()});
                log("  剩余时间: {d} 分 {d} 秒", .{ @divFloor(remaining, 60), @mod(remaining, 60) });
                log("  UP Token: {s}...", .{m.getUpTokenId()[0..20]});
                log("  DOWN Token: {s}...", .{m.getDownTokenId()[0..20]});

                // 阶段 2: 执行策略
                log("", .{});
                log("════════════════════════════════════════════════════════════════", .{});
                log("  执行 {s} 策略...", .{@tagName(self.config.mode)});
                log("════════════════════════════════════════════════════════════════", .{});

                self.executeStrategy(m) catch |err| {
                    log("策略执行失败: {}", .{err});
                };

                // 阶段 3: 等待市场结束
                self.waitForMarketEnd(m);

                // 重置状态
                self.position.reset();
                self.current_market = null;
                self.last_snapshot = null;
                self.stats.markets_traded += 1;
            } else {
                self.showNextExpectedMarket();
                std.Thread.sleep(5 * std.time.ns_per_s);
            }
        }

        self.printFinalStats();
    }

    /// 分析订单簿
    fn analyzeOrderBook(self: *Self, token_id: []const u8) !OrderBookAnalysis {
        const book_resp = self.client.getOrderBook(token_id) catch |err| {
            return err;
        };
        defer book_resp.deinit();

        const book = &book_resp.value;
        const bids = book.bids orelse return OrderBookAnalysis{
            .real_best_bid = 0,
            .real_best_ask = 1,
            .real_spread = 1,
            .mid_price = 0.5,
            .edge_bid_depth = 0,
            .edge_ask_depth = 0,
            .mid_bid_depth = 0,
            .mid_ask_depth = 0,
            .is_valid = false,
        };
        const asks = book.asks orelse return OrderBookAnalysis{
            .real_best_bid = 0,
            .real_best_ask = 1,
            .real_spread = 1,
            .mid_price = 0.5,
            .edge_bid_depth = 0,
            .edge_ask_depth = 0,
            .mid_bid_depth = 0,
            .mid_ask_depth = 0,
            .is_valid = false,
        };

        var real_best_bid: f64 = 0;
        var real_best_ask: f64 = 1;
        var edge_bid_depth: f64 = 0;
        var edge_ask_depth: f64 = 0;
        var mid_bid_depth: f64 = 0;
        var mid_ask_depth: f64 = 0;

        const threshold = self.config.edge_price_threshold;

        // 分析买单
        for (bids) |bid| {
            const price = std.fmt.parseFloat(f64, bid.price) catch continue;
            const size = std.fmt.parseFloat(f64, bid.size) catch continue;

            if (price < threshold) {
                edge_bid_depth += size * price;
            } else {
                mid_bid_depth += size * price;
                if (price > real_best_bid) {
                    real_best_bid = price;
                }
            }
        }

        // 分析卖单
        for (asks) |ask| {
            const price = std.fmt.parseFloat(f64, ask.price) catch continue;
            const size = std.fmt.parseFloat(f64, ask.size) catch continue;

            if (price > (1.0 - threshold)) {
                edge_ask_depth += size * price;
            } else {
                mid_ask_depth += size * price;
                if (price < real_best_ask) {
                    real_best_ask = price;
                }
            }
        }

        const real_spread = real_best_ask - real_best_bid;
        const mid_price = if (real_best_bid > 0 and real_best_ask < 1)
            (real_best_bid + real_best_ask) / 2.0
        else
            0.5;

        return OrderBookAnalysis{
            .real_best_bid = real_best_bid,
            .real_best_ask = real_best_ask,
            .real_spread = real_spread,
            .mid_price = mid_price,
            .edge_bid_depth = edge_bid_depth,
            .edge_ask_depth = edge_ask_depth,
            .mid_bid_depth = mid_bid_depth,
            .mid_ask_depth = mid_ask_depth,
            .is_valid = real_best_bid > 0 and real_best_ask < 1,
        };
    }

    /// 获取市场快照
    fn getMarketSnapshot(self: *Self, market: MarketInfo) !MarketSnapshot {
        const up_analysis = try self.analyzeOrderBook(market.getUpTokenId());
        const down_analysis = try self.analyzeOrderBook(market.getDownTokenId());

        const probability_sum = up_analysis.mid_price + down_analysis.mid_price;

        var arb_opportunity = ArbOpportunity.none;
        if (probability_sum < (1.0 - self.config.arb_threshold)) {
            arb_opportunity = .buy_both;
        } else if (probability_sum > (1.0 + self.config.arb_threshold)) {
            arb_opportunity = .sell_both;
        }

        return MarketSnapshot{
            .timestamp = std.time.timestamp(),
            .up_analysis = up_analysis,
            .down_analysis = down_analysis,
            .probability_sum = probability_sum,
            .arb_opportunity = arb_opportunity,
        };
    }

    /// 执行策略
    fn executeStrategy(self: *Self, market: MarketInfo) !void {
        var iteration: u64 = 0;
        var last_print_time: i64 = 0;

        while (self.running) {
            iteration += 1;
            const now = std.time.timestamp();
            const remaining = market.end_timestamp - now;

            // 检查剩余时间
            if (remaining < 60) { // 最后 1 分钟停止交易
                log("  剩余时间不足 1 分钟，停止交易", .{});
                break;
            }

            // 获取市场快照
            const snapshot = self.getMarketSnapshot(market) catch |err| {
                log("  获取市场数据失败: {}", .{err});
                std.Thread.sleep(self.config.refresh_interval_ms * std.time.ns_per_ms);
                continue;
            };

            // 更新价格历史
            self.price_history[self.price_history_idx] = snapshot.up_analysis.mid_price;
            self.price_history_idx = (self.price_history_idx + 1) % 60;

            // 定期打印状态（每 5 秒）
            if (now - last_print_time >= 5) {
                last_print_time = now;
                self.printMarketStatus(market, snapshot);
            }

            // 根据策略模式生成信号
            const signals = self.generateSignals(snapshot);

            // 执行信号
            for (signals) |signal_opt| {
                if (signal_opt) |signal| {
                    try self.executeSignal(market, signal);
                }
            }

            self.last_snapshot = snapshot;
            std.Thread.sleep(self.config.refresh_interval_ms * std.time.ns_per_ms);
        }
    }

    /// 计算价格动量（基于最近的价格历史）
    fn calculateMomentum(self: *Self) f64 {
        var sum: f64 = 0;
        var count: f64 = 0;
        var prev: f64 = 0;

        for (self.price_history) |p| {
            if (p > 0) {
                if (prev > 0) {
                    sum += (p - prev);
                    count += 1;
                }
                prev = p;
            }
        }

        if (count > 0) {
            return sum / count;
        }
        return 0;
    }

    /// 计算价格波动率
    fn calculateVolatility(self: *Self) f64 {
        var sum: f64 = 0;
        var sum_sq: f64 = 0;
        var count: f64 = 0;

        for (self.price_history) |p| {
            if (p > 0) {
                sum += p;
                sum_sq += p * p;
                count += 1;
            }
        }

        if (count > 1) {
            const mean = sum / count;
            const variance = (sum_sq / count) - (mean * mean);
            return @sqrt(@max(variance, 0));
        }
        return 0;
    }

    /// 生成交易信号
    fn generateSignals(self: *Self, snapshot: MarketSnapshot) [4]?TradeSignal {
        var signals: [4]?TradeSignal = [_]?TradeSignal{null} ** 4;
        var signal_idx: usize = 0;

        // 计算动量和波动率
        const momentum = self.calculateMomentum();
        const volatility = self.calculateVolatility();

        switch (self.config.mode) {
            .market_maker => {
                // 做市商策略：在价差两侧挂单
                // 只有在波动率较低时才做市
                if (snapshot.up_analysis.real_spread >= self.config.mm_min_spread and
                    volatility < 0.05)
                {
                    if (self.position.pending_orders < 2 and
                        self.position.totalCost() < self.config.max_position)
                    {
                        // 挂买单
                        const buy_price = snapshot.up_analysis.real_best_bid + 0.01;
                        const buy_size = self.config.mm_order_size / buy_price;
                        signals[signal_idx] = TradeSignal{
                            .action = .buy,
                            .token = .up,
                            .price = buy_price,
                            .size = buy_size,
                            .reason = "MM: place bid",
                        };
                        signal_idx += 1;
                    }
                }
            },
            .arbitrage => {
                // 套利策略
                switch (snapshot.arb_opportunity) {
                    .buy_both => {
                        // UP + DOWN < 1.0，买入两边
                        const gap = 1.0 - snapshot.probability_sum;
                        if (gap > self.config.arb_threshold and
                            self.position.totalCost() < self.config.max_position)
                        {
                            const size = self.config.mm_order_size / snapshot.up_analysis.real_best_ask;
                            signals[signal_idx] = TradeSignal{
                                .action = .buy,
                                .token = .up,
                                .price = snapshot.up_analysis.real_best_ask,
                                .size = size,
                                .reason = "ARB: buy UP (sum < 1.0)",
                            };
                            signal_idx += 1;

                            signals[signal_idx] = TradeSignal{
                                .action = .buy,
                                .token = .down,
                                .price = snapshot.down_analysis.real_best_ask,
                                .size = size,
                                .reason = "ARB: buy DOWN (sum < 1.0)",
                            };
                            signal_idx += 1;
                        }
                    },
                    .sell_both => {
                        // UP + DOWN > 1.0，卖出持仓
                        if (self.position.up_shares > 0) {
                            signals[signal_idx] = TradeSignal{
                                .action = .sell,
                                .token = .up,
                                .price = snapshot.up_analysis.real_best_bid,
                                .size = self.position.up_shares,
                                .reason = "ARB: sell UP (sum > 1.0)",
                            };
                            signal_idx += 1;
                        }
                    },
                    .none => {},
                }
            },
            .trend_follower => {
                // 趋势跟随策略 - 使用动量指标
                // 动量 > 0 表示价格上涨趋势，< 0 表示下跌趋势
                if (@abs(momentum) > 0.001 and
                    self.position.totalCost() < self.config.max_position)
                {
                    if (momentum > self.config.trend_threshold) {
                        // 正动量，买入 UP
                        const size = self.config.mm_order_size / snapshot.up_analysis.real_best_ask;
                        signals[signal_idx] = TradeSignal{
                            .action = .buy,
                            .token = .up,
                            .price = snapshot.up_analysis.real_best_ask,
                            .size = size,
                            .reason = "TREND: momentum up",
                        };
                        signal_idx += 1;
                    } else if (momentum < -self.config.trend_threshold) {
                        // 负动量，买入 DOWN
                        const size = self.config.mm_order_size / snapshot.down_analysis.real_best_ask;
                        signals[signal_idx] = TradeSignal{
                            .action = .buy,
                            .token = .down,
                            .price = snapshot.down_analysis.real_best_ask,
                            .size = size,
                            .reason = "TREND: momentum down",
                        };
                        signal_idx += 1;
                    }
                }
            },
            .hybrid => {
                // 混合模式：综合多种策略

                // 1. 优先检查套利机会（UP + DOWN != 1.0）
                switch (snapshot.arb_opportunity) {
                    .buy_both => {
                        const gap = 1.0 - snapshot.probability_sum;
                        if (gap > self.config.arb_threshold and
                            self.position.totalCost() < self.config.max_position)
                        {
                            log("  套利机会! UP + DOWN = {d:.4} (差值: {d:.4})", .{ snapshot.probability_sum, gap });
                            const size = self.config.mm_order_size / snapshot.up_analysis.real_best_ask;
                            signals[signal_idx] = TradeSignal{
                                .action = .buy,
                                .token = .up,
                                .price = snapshot.up_analysis.real_best_ask,
                                .size = size,
                                .reason = "HYBRID-ARB: buy UP",
                            };
                            signal_idx += 1;
                            signals[signal_idx] = TradeSignal{
                                .action = .buy,
                                .token = .down,
                                .price = snapshot.down_analysis.real_best_ask,
                                .size = size,
                                .reason = "HYBRID-ARB: buy DOWN",
                            };
                            signal_idx += 1;
                        }
                    },
                    else => {},
                }

                // 2. 概率偏差策略：当 UP 概率显著偏离 50% 时交易
                // 逻辑：如果 UP > 55%，市场预期 BTC 上涨，买入 UP
                //       如果 UP < 45%，市场预期 BTC 下跌，买入 DOWN
                if (signal_idx == 0 and self.position.totalCost() < self.config.max_position) {
                    const up_prob = snapshot.up_analysis.mid_price;

                    // 强偏差阈值：0.55 或 0.45
                    if (up_prob >= 0.55) {
                        // 市场强烈看涨，跟随买入 UP
                        log("  概率偏差: UP={d:.2}% (看涨), 动量={d:.4}", .{ up_prob * 100, momentum });
                        const size = self.config.mm_order_size / snapshot.up_analysis.real_best_ask;
                        signals[signal_idx] = TradeSignal{
                            .action = .buy,
                            .token = .up,
                            .price = snapshot.up_analysis.real_best_ask,
                            .size = size,
                            .reason = "HYBRID-PROB: UP bias",
                        };
                        signal_idx += 1;
                    } else if (up_prob <= 0.45) {
                        // 市场强烈看跌，买入 DOWN
                        log("  概率偏差: UP={d:.2}% (看跌), 动量={d:.4}", .{ up_prob * 100, momentum });
                        const size = self.config.mm_order_size / snapshot.down_analysis.real_best_ask;
                        signals[signal_idx] = TradeSignal{
                            .action = .buy,
                            .token = .down,
                            .price = snapshot.down_analysis.real_best_ask,
                            .size = size,
                            .reason = "HYBRID-PROB: DOWN bias",
                        };
                        signal_idx += 1;
                    }
                }

                // 3. 动量交易（只有在没有概率偏差时）
                if (signal_idx == 0 and @abs(momentum) > self.config.trend_threshold and
                    self.position.totalCost() < self.config.max_position)
                {
                    if (momentum > 0) {
                        log("  动量信号: 上涨 ({d:.4}), 波动率: {d:.4}", .{ momentum, volatility });
                        const size = self.config.mm_order_size / snapshot.up_analysis.real_best_ask;
                        signals[signal_idx] = TradeSignal{
                            .action = .buy,
                            .token = .up,
                            .price = snapshot.up_analysis.real_best_ask,
                            .size = size,
                            .reason = "HYBRID-MOM: up",
                        };
                        signal_idx += 1;
                    } else {
                        log("  动量信号: 下跌 ({d:.4}), 波动率: {d:.4}", .{ momentum, volatility });
                        const size = self.config.mm_order_size / snapshot.down_analysis.real_best_ask;
                        signals[signal_idx] = TradeSignal{
                            .action = .buy,
                            .token = .down,
                            .price = snapshot.down_analysis.real_best_ask,
                            .size = size,
                            .reason = "HYBRID-MOM: down",
                        };
                        signal_idx += 1;
                    }
                }
            },
        }

        return signals;
    }

    /// 执行交易信号
    fn executeSignal(self: *Self, market: MarketInfo, signal: TradeSignal) !void {
        const token_name = if (signal.token == .up) "UP" else "DOWN";
        const action_name = switch (signal.action) {
            .buy => "买入",
            .sell => "卖出",
            .cancel => "取消",
        };

        log("  信号: {s} {s} @ {d:.4} x {d:.2} ({s})", .{
            action_name,
            token_name,
            signal.price,
            signal.size,
            signal.reason,
        });

        if (self.config.dry_run) {
            log("  [模拟模式] 跳过实际下单", .{});

            // 模拟更新仓位
            if (signal.action == .buy) {
                if (signal.token == .up) {
                    self.position.updateUp(signal.size, signal.price);
                } else {
                    self.position.updateDown(signal.size, signal.price);
                }
                self.stats.total_trades += 1;
            }
            return;
        }

        // 实际下单逻辑
        if (self.builder) |*builder| {
            const token_id = if (signal.token == .up)
                market.getUpTokenId()
            else
                market.getDownTokenId();

            const price_str = try std.fmt.allocPrint(self.allocator, "{d:.2}", .{signal.price});
            defer self.allocator.free(price_str);
            const size_str = try std.fmt.allocPrint(self.allocator, "{d:.0}", .{signal.size});
            defer self.allocator.free(size_str);

            const price_decimal = try Decimal.fromString(price_str);
            const size_decimal = try Decimal.fromString(size_str);

            const side: Side = if (signal.action == .buy) .BUY else .SELL;

            const order = try builder.createOrder(.{
                .token_id = token_id,
                .price = price_decimal,
                .size = size_decimal,
                .side = side,
            }, .{
                .tick_size = .@"0.01",
                .neg_risk = false,
            });

            const response = try self.client.postOrder(&order, .GTC);

            if (response.success) {
                log("  订单成功! ID: {s}", .{response.orderID orelse "N/A"});
                if (signal.token == .up) {
                    self.position.updateUp(signal.size, signal.price);
                } else {
                    self.position.updateDown(signal.size, signal.price);
                }
                self.stats.total_trades += 1;
            } else {
                log("  订单失败: {s}", .{response.errorMsg orelse "未知错误"});
            }
        }
    }

    /// 打印市场状态
    fn printMarketStatus(self: *Self, market: MarketInfo, snapshot: MarketSnapshot) void {
        const remaining = market.getRemainingSeconds();
        const mins = @divFloor(remaining, 60);
        const secs = @mod(remaining, 60);

        // 计算动量和波动率
        const momentum = self.calculateMomentum();
        const volatility = self.calculateVolatility();

        // 清屏
        std.debug.print("\x1B[2J\x1B[H", .{});

        std.debug.print("\n", .{});
        std.debug.print("╔═══════════════════════════════════════════════════════════════════════════╗\n", .{});
        std.debug.print("║        BTC 15分钟智能交易系统 v2 - {s}        ║\n", .{if (self.config.dry_run) "模拟模式" else "实盘模式"});
        std.debug.print("╠═══════════════════════════════════════════════════════════════════════════╣\n", .{});
        std.debug.print("║  市场: {s:<64} ║\n", .{market.getSlug()});
        std.debug.print("║  剩余时间: {d:>2} 分 {d:>2} 秒                                                    ║\n", .{ mins, secs });
        std.debug.print("╠═══════════════════════════════════════════════════════════════════════════╣\n", .{});
        std.debug.print("║                        订 单 簿 分 析                                     ║\n", .{});
        std.debug.print("╠═══════════════════════════════════════════════════════════════════════════╣\n", .{});
        std.debug.print("║                    UP (涨)                    DOWN (跌)                   ║\n", .{});
        std.debug.print("║  ─────────────────────────────────────────────────────────────────────── ║\n", .{});
        std.debug.print("║  真实买价:      {d:.4}                         {d:.4}                     ║\n", .{
            snapshot.up_analysis.real_best_bid,
            snapshot.down_analysis.real_best_bid,
        });
        std.debug.print("║  真实卖价:      {d:.4}                         {d:.4}                     ║\n", .{
            snapshot.up_analysis.real_best_ask,
            snapshot.down_analysis.real_best_ask,
        });
        std.debug.print("║  中间价:        {d:.4}  ({d:>5.1}%)               {d:.4}  ({d:>5.1}%)           ║\n", .{
            snapshot.up_analysis.mid_price,
            snapshot.up_analysis.mid_price * 100,
            snapshot.down_analysis.mid_price,
            snapshot.down_analysis.mid_price * 100,
        });
        std.debug.print("║  价差:          {d:.4}                         {d:.4}                     ║\n", .{
            snapshot.up_analysis.real_spread,
            snapshot.down_analysis.real_spread,
        });
        std.debug.print("║  买盘深度:    ${d:>7.0}                       ${d:>7.0}                   ║\n", .{
            snapshot.up_analysis.mid_bid_depth,
            snapshot.down_analysis.mid_bid_depth,
        });
        std.debug.print("║  卖盘深度:    ${d:>7.0}                       ${d:>7.0}                   ║\n", .{
            snapshot.up_analysis.mid_ask_depth,
            snapshot.down_analysis.mid_ask_depth,
        });
        std.debug.print("╠═══════════════════════════════════════════════════════════════════════════╣\n", .{});
        std.debug.print("║                        市 场 指 标                                        ║\n", .{});
        std.debug.print("╠═══════════════════════════════════════════════════════════════════════════╣\n", .{});
        std.debug.print("║  UP + DOWN = {d:.4}  ", .{snapshot.probability_sum});
        switch (snapshot.arb_opportunity) {
            .none => std.debug.print("(正常，无套利)                                  ║\n", .{}),
            .buy_both => std.debug.print(">>> 套利机会: 买入两边! <<<                    ║\n", .{}),
            .sell_both => std.debug.print(">>> 套利机会: 卖出两边! <<<                    ║\n", .{}),
        }
        // 显示动量（手动处理正负号）
        if (momentum >= 0) {
            std.debug.print("║  动量: +{d:.5}    波动率: {d:.5}                                        ║\n", .{ momentum, volatility });
        } else {
            std.debug.print("║  动量: {d:.5}    波动率: {d:.5}                                        ║\n", .{ momentum, volatility });
        }

        // 市场偏差指示
        const up_prob = snapshot.up_analysis.mid_price;
        std.debug.print("║  市场情绪: ", .{});
        if (up_prob >= 0.55) {
            std.debug.print("强烈看涨 (UP {d:.1}%)                                         ║\n", .{up_prob * 100});
        } else if (up_prob >= 0.52) {
            std.debug.print("略微看涨 (UP {d:.1}%)                                         ║\n", .{up_prob * 100});
        } else if (up_prob <= 0.45) {
            std.debug.print("强烈看跌 (UP {d:.1}%)                                         ║\n", .{up_prob * 100});
        } else if (up_prob <= 0.48) {
            std.debug.print("略微看跌 (UP {d:.1}%)                                         ║\n", .{up_prob * 100});
        } else {
            std.debug.print("中性 (UP {d:.1}%)                                             ║\n", .{up_prob * 100});
        }

        std.debug.print("╠═══════════════════════════════════════════════════════════════════════════╣\n", .{});
        std.debug.print("║                        当 前 仓 位                                        ║\n", .{});
        std.debug.print("╠═══════════════════════════════════════════════════════════════════════════╣\n", .{});
        std.debug.print("║  UP 持仓:  {d:>8.2} 股  均价: {d:.4}  成本: ${d:>7.2}                     ║\n", .{
            self.position.up_shares,
            self.position.up_avg_price,
            self.position.up_cost,
        });
        std.debug.print("║  DOWN 持仓: {d:>7.2} 股  均价: {d:.4}  成本: ${d:>7.2}                     ║\n", .{
            self.position.down_shares,
            self.position.down_avg_price,
            self.position.down_cost,
        });
        std.debug.print("║  总成本: ${d:>7.2}  最大仓位: ${d:>7.0}                                    ║\n", .{
            self.position.totalCost(),
            self.config.max_position,
        });
        std.debug.print("╠═══════════════════════════════════════════════════════════════════════════╣\n", .{});
        std.debug.print("║  交易统计: 市场数 {d}  交易数 {d}  总利润 ${d:.2}                          ║\n", .{
            self.stats.markets_traded,
            self.stats.total_trades,
            self.stats.total_profit,
        });
        std.debug.print("╚═══════════════════════════════════════════════════════════════════════════╝\n", .{});
    }

    /// 寻找适合的市场
    fn findSuitableMarket(self: *Self) !?MarketInfo {
        const now = std.time.timestamp();
        const interval: i64 = 900;
        const current_slot = @divFloor(now, interval) * interval;
        const next_slot = current_slot + interval;

        const slots = [_]i64{ current_slot, next_slot };

        for (slots) |slot| {
            var slug_buf: [64]u8 = undefined;
            const slug = std.fmt.bufPrint(&slug_buf, "btc-updown-15m-{d}", .{slot}) catch continue;

            if (self.fetchMarketFromGamma(slug)) |market_info| {
                const remaining = market_info.end_timestamp - now;

                if (remaining < self.config.min_remaining_minutes * 60) {
                    continue;
                }

                if (remaining <= 0) {
                    continue;
                }

                return market_info;
            } else |_| {
                continue;
            }
        }

        return null;
    }

    /// 从 Gamma API 获取市场信息
    fn fetchMarketFromGamma(self: *Self, slug: []const u8) !MarketInfo {
        var url_buf: [256]u8 = undefined;
        const url = std.fmt.bufPrint(&url_buf, "https://gamma-api.polymarket.com/events?slug={s}", .{slug}) catch return error.BufferTooSmall;

        const argv: []const []const u8 = &.{ "curl", "-s", "-f", url };

        var child = std.process.Child.init(argv, self.allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        child.spawn() catch return error.SpawnFailed;

        const stdout = child.stdout.?;
        var read_buffer: [8192]u8 = undefined;
        var response = try std.ArrayList(u8).initCapacity(self.allocator, 4096);
        defer response.deinit(self.allocator);

        while (true) {
            const n = stdout.read(&read_buffer) catch return error.ReadFailed;
            if (n == 0) break;
            response.appendSlice(self.allocator, read_buffer[0..n]) catch return error.OutOfMemory;
        }

        const result = child.wait() catch return error.WaitFailed;
        if (result != .Exited or result.Exited != 0) {
            return error.CurlFailed;
        }

        return self.parseGammaResponse(response.items, slug);
    }

    /// 解析 Gamma API 响应
    fn parseGammaResponse(self: *Self, json_data: []const u8, slug: []const u8) !MarketInfo {
        _ = self;

        const clob_tokens_start = std.mem.indexOf(u8, json_data, "\"clobTokenIds\":\"[\\\"") orelse return error.TokensNotFound;
        const tokens_data = json_data[clob_tokens_start + 19 ..];

        const first_token_end = std.mem.indexOf(u8, tokens_data, "\\\"") orelse return error.ParseError;
        const up_token = tokens_data[0..first_token_end];

        const rest = tokens_data[first_token_end + 6 ..];
        const second_token_end = std.mem.indexOf(u8, rest, "\\\"") orelse return error.ParseError;
        const down_token = rest[0..second_token_end];

        const condition_start = std.mem.indexOf(u8, json_data, "\"conditionId\":\"") orelse return error.ConditionNotFound;
        const condition_data = json_data[condition_start + 15 ..];
        const condition_end = std.mem.indexOf(u8, condition_data, "\"") orelse return error.ParseError;
        const condition_id = condition_data[0..condition_end];

        const end_timestamp = parseTimestampFromSlug(slug);
        if (end_timestamp == 0) return error.InvalidTimestamp;

        var info = MarketInfo{
            .end_timestamp = end_timestamp,
        };

        if (condition_id.len > info.condition_id_buf.len) return error.BufferTooSmall;
        @memcpy(info.condition_id_buf[0..condition_id.len], condition_id);
        info.condition_id_len = condition_id.len;

        if (up_token.len > info.up_token_id_buf.len) return error.BufferTooSmall;
        @memcpy(info.up_token_id_buf[0..up_token.len], up_token);
        info.up_token_id_len = up_token.len;

        if (down_token.len > info.down_token_id_buf.len) return error.BufferTooSmall;
        @memcpy(info.down_token_id_buf[0..down_token.len], down_token);
        info.down_token_id_len = down_token.len;

        if (slug.len > info.slug_buf.len) return error.BufferTooSmall;
        @memcpy(info.slug_buf[0..slug.len], slug);
        info.slug_len = slug.len;

        return info;
    }

    /// 等待市场结束
    fn waitForMarketEnd(self: *Self, market: MarketInfo) void {
        _ = self;
        const end_time = market.end_timestamp;

        while (true) {
            const now = std.time.timestamp();
            const remaining = end_time - now;

            if (remaining <= 0) {
                log("  市场已结束", .{});
                break;
            }

            std.Thread.sleep(10 * std.time.ns_per_s);
        }
    }

    /// 显示下一个预期市场
    fn showNextExpectedMarket(self: *Self) void {
        _ = self;
        const now = std.time.timestamp();
        const interval: i64 = 900;
        const next_timestamp = (@divFloor(now, interval) + 1) * interval;
        const wait_seconds = next_timestamp - now;

        log("  未找到适合的市场", .{});
        log("  下一个预期市场: btc-updown-15m-{d}", .{next_timestamp});
        log("  距离开始: {d} 分 {d} 秒", .{ @divFloor(wait_seconds, 60), @mod(wait_seconds, 60) });
    }

    fn printBanner(self: *Self) void {
        std.debug.print("\n", .{});
        std.debug.print("╔══════════════════════════════════════════════════════════════════╗\n", .{});
        std.debug.print("║      BTC 15分钟市场智能交易系统 v2 - Polymarket                  ║\n", .{});
        std.debug.print("╠══════════════════════════════════════════════════════════════════╣\n", .{});
        std.debug.print("║  策略: {s:<58} ║\n", .{@tagName(self.config.mode)});
        std.debug.print("║  模式: {s:<58} ║\n", .{if (self.config.dry_run) "模拟交易" else "实盘交易"});
        std.debug.print("╚══════════════════════════════════════════════════════════════════╝\n", .{});
        std.debug.print("\n", .{});

        std.debug.print("配置:\n", .{});
        std.debug.print("  边缘价格阈值: {d:.2}\n", .{self.config.edge_price_threshold});
        std.debug.print("  做市最小价差: {d:.2}\n", .{self.config.mm_min_spread});
        std.debug.print("  套利阈值: {d:.2}\n", .{self.config.arb_threshold});
        std.debug.print("  趋势阈值: {d:.2}\n", .{self.config.trend_threshold});
        std.debug.print("  最大仓位: ${d:.0}\n", .{self.config.max_position});
        std.debug.print("\n", .{});
    }

    fn printFinalStats(self: *Self) void {
        std.debug.print("\n", .{});
        std.debug.print("╔══════════════════════════════════════════════════════════════════╗\n", .{});
        std.debug.print("║                        最终交易统计                               ║\n", .{});
        std.debug.print("╚══════════════════════════════════════════════════════════════════╝\n", .{});
        std.debug.print("  交易市场数: {d}\n", .{self.stats.markets_traded});
        std.debug.print("  总交易次数: {d}\n", .{self.stats.total_trades});
        std.debug.print("  胜率: {d:.1}%\n", .{self.stats.winRate()});
        std.debug.print("  总成本: ${d:.2}\n", .{self.stats.total_cost});
        std.debug.print("  总利润: ${d:.2}\n", .{self.stats.total_profit});
    }

    pub fn stop(self: *Self) void {
        self.running = false;
    }
};

// ============================================================================
// 辅助函数
// ============================================================================

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

    // 解析策略模式
    const mode_str = env.get("SMART_TRADER_MODE") orelse "hybrid";
    const mode: StrategyMode = if (std.mem.eql(u8, mode_str, "market_maker"))
        .market_maker
    else if (std.mem.eql(u8, mode_str, "trend"))
        .trend_follower
    else if (std.mem.eql(u8, mode_str, "arbitrage"))
        .arbitrage
    else
        .hybrid;

    // 解析配置
    const config = SmartTraderConfig{
        .mode = mode,
        .dry_run = env.getBool("SMART_TRADER_DRY_RUN", true),
        .min_remaining_minutes = env.getInt(i64, "SMART_TRADER_MIN_REMAINING", 5),
        .edge_price_threshold = env.getFloat(f64, "SMART_TRADER_EDGE_THRESHOLD", 0.20),
        .mm_min_spread = env.getFloat(f64, "SMART_TRADER_MM_SPREAD", 0.02),
        .mm_order_size = env.getFloat(f64, "SMART_TRADER_ORDER_SIZE", 50.0),
        .arb_threshold = env.getFloat(f64, "SMART_TRADER_ARB_THRESHOLD", 0.02),
        .trend_threshold = env.getFloat(f64, "SMART_TRADER_TREND_THRESHOLD", 0.05),
        .max_position = env.getFloat(f64, "SMART_TRADER_MAX_POSITION", 200.0),
        .use_testnet = env.getBool("POLY_USE_TESTNET", false),
    };

    // 创建客户端配置
    const client_config = poly.clob.client.Config{
        .base_url = if (config.use_testnet) poly.clob.client.BASE_URL_TESTNET else poly.clob.client.BASE_URL_MAINNET,
    };

    // 初始化
    var wallet: ?Wallet = null;
    var creds: ?ApiCreds = null;
    var client: ClobClient = undefined;

    if (!config.dry_run) {
        const private_key = env.get("POLY_PRIVATE_KEY") orelse {
            std.debug.print("错误: 实盘模式需要设置 POLY_PRIVATE_KEY\n", .{});
            std.debug.print("提示: 设置 SMART_TRADER_DRY_RUN=true 可使用模拟模式\n", .{});
            return error.MissingCredentials;
        };

        wallet = Wallet.fromPrivateKeyHex(private_key) catch |err| {
            std.debug.print("钱包初始化失败: {}\n", .{err});
            return err;
        };

        std.debug.print("钱包地址: {s}\n\n", .{wallet.?.getAddressChecksumHex()});

        const api_key = env.get("POLY_API_KEY");
        const api_secret = env.get("POLY_API_SECRET");
        const api_passphrase = env.get("POLY_API_PASSPHRASE");

        if (api_key != null and api_secret != null and api_passphrase != null) {
            creds = try ApiCreds.init(allocator, api_key.?, api_secret.?, api_passphrase.?);
            client = ClobClient.initWithAuth(allocator, client_config, &wallet.?, &creds.?);
        } else {
            client = ClobClient.init(allocator, client_config);
            client.setWallet(&wallet.?);

            creds = client.createOrDeriveApiKey() catch |err| {
                std.debug.print("获取 API 凭证失败: {}\n", .{err});
                return err;
            };

            std.debug.print("API 凭证获取成功!\n", .{});
            client.setApiCreds(&creds.?);
        }
    } else {
        client = ClobClient.init(allocator, client_config);
    }
    defer client.deinit();
    defer if (creds) |*c| c.deinit();

    // 创建智能交易系统
    var trader = SmartTrader.init(
        allocator,
        &client,
        if (wallet) |*w| w else null,
        config,
    );

    // 运行
    try trader.run();
}
