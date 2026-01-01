//! BTC 15分钟市场两步对冲套利机器人
//!
//! 策略核心逻辑：
//! 1. 第一步：捕捉早期暴跌，低价买入 YES(UP) 股份
//!    - 持续监控市场概率（YES 股份价格，范围 0-1）
//!    - 当检测到价格快速大幅下跌（由 move 参数控制）
//!    - 在价格跌到足够低时（由 sumTarget 控制累计买入量）买入 YES
//!
//! 2. 第二步：价格反弹后，对冲卖出 NO(DOWN) 股份锁定利润
//!    - 买入 YES 后继续监控价格
//!    - 价格反弹高于买入均价时，卖出等量 NO 股份
//!    - 效果：YES + NO = 1，锁定利润
//!
//! 关键参数：
//! - sumTarget: 目标累计买入量（0.3 保守，0.6 激进）
//! - move: 触发监控的价格下跌幅度（如 0.01 = 1%）
//!
//! 运行: zig build run-btc_ws_trader
//!
//! 配置（.env 文件）：
//! - POLY_PRIVATE_KEY: 钱包私钥
//! - WS_TRADER_DRY_RUN: 模拟模式（默认 true）
//! - WS_TRADER_SUM_TARGET: 目标累计买入量（默认 0.3）
//! - WS_TRADER_MOVE: 触发下跌幅度（默认 0.01）

const std = @import("std");
const poly = @import("poly_sdk_zig");

const ClobClient = poly.ClobClient;
const Wallet = poly.Wallet;
const ApiCreds = poly.ApiCreds;
const Decimal = poly.Decimal;
const OrderBuilder = poly.OrderBuilder;
const Side = poly.Side;

// WebSocket 相关
const ws = poly.ws;
const MarketChannel = ws.MarketChannel;
const BookMessage = ws.BookMessage;
const PriceChangeMessage = ws.PriceChangeMessage;

// ============================================================================
// 策略配置
// ============================================================================

/// 签名类型 (0=EOA, 1=POLY_PROXY, 2=POLY_GNOSIS_SAFE)
const SignatureType = poly.order.types.SignatureType;

const StrategyConfig = struct {
    /// 模拟模式（不实际下单）
    dry_run: bool = true,

    /// ========== 核心策略参数 ==========
    /// sumTarget: 目标累计买入量（控制激进程度）
    /// - 0.3 = 保守，只在极低价时才重仓买入
    /// - 0.6 = 激进，可能导致大幅亏损
    /// 建议从 0.3 开始
    sum_target: f64 = 0.3,

    /// move: 触发监控的价格下跌幅度
    /// - 0.01 = 1% 下跌触发
    /// - 0.02 = 2% 下跌触发
    move_threshold: f64 = 0.01,

    /// 对冲触发条件：价格反弹超过买入均价的比例
    /// - 0.05 = 价格比买入均价高 5% 时对冲
    hedge_profit_threshold: f64 = 0.05,

    /// ========== 风险管理参数 ==========
    /// 止损阈值：亏损超过此比例时强制平仓
    /// - 0.30 = 亏损 30% 时止损
    stop_loss_threshold: f64 = 0.30,

    /// 无流动性时强制平仓的剩余时间（秒）
    /// - 当 bid=0 且剩余时间少于此值时，尝试以任何价格卖出
    force_exit_remaining: i64 = 120,

    /// 止盈阈值：对冲后如果 YES 价格涨到此值以上，卖出 YES
    /// - 0.90 = YES 价格涨到 90% 以上时卖出
    take_profit_threshold: f64 = 0.90,

    /// 最高买入价格：只在价格低于此值时买入
    /// - 0.50 = 只在 YES 价格 < 50% 时买入（保守）
    /// - 0.60 = 只在 YES 价格 < 60% 时买入（激进）
    max_buy_price: f64 = 0.50,

    /// ========== 交易参数 ==========
    /// 单次最小订单金额（美元）
    min_order_size: f64 = 5.0,

    /// 单次最大订单金额（美元）
    max_order_size: f64 = 50.0,

    /// 最大总仓位（美元）
    max_position: f64 = 200.0,

    /// ========== 市场参数 ==========
    /// 最小剩余时间（分钟）
    min_remaining_minutes: i64 = 3,

    /// 边缘价格阈值（忽略低于此价格的买单）
    edge_price_threshold: f64 = 0.05,

    /// 最大价差（超过则不交易）
    max_spread: f64 = 0.10,

    /// ========== 系统参数 ==========
    /// 是否使用测试网
    use_testnet: bool = false,

    /// 签名类型
    signature_type: SignatureType = .EOA,

    /// Funder/Proxy 地址
    funder: ?[20]u8 = null,
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
    start_timestamp: i64,
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

/// 实时订单簿状态
const LiveOrderBook = struct {
    // UP Token (YES)
    up_best_bid: f64 = 0,
    up_best_ask: f64 = 1,
    up_mid_price: f64 = 0.5,

    // DOWN Token (NO)
    down_best_bid: f64 = 0,
    down_best_ask: f64 = 1,
    down_mid_price: f64 = 0.5,

    // 更新时间戳
    last_update: i64 = 0,
    update_count: u64 = 0,

    pub fn yesPrice(self: *const LiveOrderBook) f64 {
        return self.up_mid_price;
    }

    pub fn noPrice(self: *const LiveOrderBook) f64 {
        return self.down_mid_price;
    }
};

/// 策略阶段
const StrategyPhase = enum {
    /// 等待暴跌信号
    waiting_for_crash,
    /// 暴跌中，正在买入 YES
    buying_yes,
    /// 持有 YES，等待反弹对冲
    waiting_for_rebound,
    /// 已对冲，锁定利润
    hedged,
};

/// YES 持仓状态
const YesPosition = struct {
    /// 持有的 YES 股数
    shares: f64 = 0,
    /// 总成本（美元）
    total_cost: f64 = 0,
    /// 买入次数
    buy_count: u32 = 0,

    /// 买入均价
    pub fn avgPrice(self: *const YesPosition) f64 {
        if (self.shares <= 0) return 0;
        return self.total_cost / self.shares;
    }

    /// 添加买入
    pub fn addBuy(self: *YesPosition, shares: f64, cost: f64) void {
        self.shares += shares;
        self.total_cost += cost;
        self.buy_count += 1;
    }

    /// 重置
    pub fn reset(self: *YesPosition) void {
        self.shares = 0;
        self.total_cost = 0;
        self.buy_count = 0;
    }
};

/// NO 对冲仓位
const NoPosition = struct {
    /// 卖出的 NO 股数（做空）
    shares: f64 = 0,
    /// 卖出收入（美元）
    total_revenue: f64 = 0,

    /// 添加卖出
    pub fn addSell(self: *NoPosition, shares: f64, revenue: f64) void {
        self.shares += shares;
        self.total_revenue += revenue;
    }

    /// 重置
    pub fn reset(self: *NoPosition) void {
        self.shares = 0;
        self.total_revenue = 0;
    }
};

/// 交易统计
const TradingStats = struct {
    markets_traded: u32 = 0,
    crashes_detected: u32 = 0,
    yes_buys: u32 = 0,
    hedges_executed: u32 = 0,
    total_profit: f64 = 0,
};

// ============================================================================
// 全局状态
// ============================================================================

var g_live_book: LiveOrderBook = .{};
var g_up_token_id: [128]u8 = undefined;
var g_up_token_len: usize = 0;
var g_down_token_id: [128]u8 = undefined;
var g_down_token_len: usize = 0;
var g_edge_threshold: f64 = 0.05;

// ============================================================================
// WebSocket 回调
// ============================================================================

fn onBookMessage(msg: BookMessage) void {
    const is_up = std.mem.eql(u8, msg.asset_id, g_up_token_id[0..g_up_token_len]);
    const is_down = std.mem.eql(u8, msg.asset_id, g_down_token_id[0..g_down_token_len]);

    if (!is_up and !is_down) return;

    var real_best_bid: f64 = 0;
    var real_best_ask: f64 = 1;

    for (msg.bids) |bid| {
        const price = std.fmt.parseFloat(f64, bid.price) catch continue;
        if (price >= g_edge_threshold and price > real_best_bid) {
            real_best_bid = price;
        }
    }

    for (msg.asks) |ask| {
        const price = std.fmt.parseFloat(f64, ask.price) catch continue;
        if (price <= (1.0 - g_edge_threshold) and price < real_best_ask) {
            real_best_ask = price;
        }
    }

    // 中间价：始终使用实际值，即使 bid=0 或 ask=1
    // 只有在完全没有数据时才使用默认值
    const mid_price = if (real_best_ask > real_best_bid)
        (real_best_bid + real_best_ask) / 2.0
    else if (real_best_bid > 0)
        real_best_bid // 只有 bid
    else if (real_best_ask < 1)
        real_best_ask // 只有 ask
    else
        0.5; // 完全无数据

    if (is_up) {
        g_live_book.up_best_bid = real_best_bid;
        g_live_book.up_best_ask = real_best_ask;
        g_live_book.up_mid_price = mid_price;
    } else {
        g_live_book.down_best_bid = real_best_bid;
        g_live_book.down_best_ask = real_best_ask;
        g_live_book.down_mid_price = mid_price;
    }

    g_live_book.last_update = std.time.timestamp();
    g_live_book.update_count += 1;
}

fn onPriceChange(msg: PriceChangeMessage) void {
    for (msg.price_changes) |change| {
        const is_up = std.mem.eql(u8, change.asset_id, g_up_token_id[0..g_up_token_len]);
        const is_down = std.mem.eql(u8, change.asset_id, g_down_token_id[0..g_down_token_len]);

        if (!is_up and !is_down) continue;

        const price = std.fmt.parseFloat(f64, change.price) catch continue;
        const side = change.side;

        if (is_up) {
            if (std.mem.eql(u8, side, "BUY") or std.mem.eql(u8, side, "buy")) {
                if (price >= g_edge_threshold) {
                    g_live_book.up_best_bid = @max(g_live_book.up_best_bid, price);
                }
            } else {
                if (price <= (1.0 - g_edge_threshold)) {
                    g_live_book.up_best_ask = @min(g_live_book.up_best_ask, price);
                }
            }
            g_live_book.up_mid_price = (g_live_book.up_best_bid + g_live_book.up_best_ask) / 2.0;
        } else {
            if (std.mem.eql(u8, side, "BUY") or std.mem.eql(u8, side, "buy")) {
                if (price >= g_edge_threshold) {
                    g_live_book.down_best_bid = @max(g_live_book.down_best_bid, price);
                }
            } else {
                if (price <= (1.0 - g_edge_threshold)) {
                    g_live_book.down_best_ask = @min(g_live_book.down_best_ask, price);
                }
            }
            g_live_book.down_mid_price = (g_live_book.down_best_bid + g_live_book.down_best_ask) / 2.0;
        }
    }

    g_live_book.last_update = std.time.timestamp();
    g_live_book.update_count += 1;
}

fn onConnectionChange(connected: bool) void {
    if (connected) {
        log("WebSocket 已连接", .{});
    } else {
        log("WebSocket 断开连接", .{});
    }
}

fn onError(err: anyerror) void {
    log("WebSocket 错误: {}", .{err});
}

// ============================================================================
// 两步对冲套利策略
// ============================================================================

const HedgeArbitrageBot = struct {
    allocator: std.mem.Allocator,
    config: StrategyConfig,
    client: *ClobClient,
    wallet: ?*const Wallet,
    builder: ?OrderBuilder,

    // 策略状态
    phase: StrategyPhase,
    yes_position: YesPosition,
    no_position: NoPosition,
    stats: TradingStats,

    // 价格监控
    initial_yes_price: f64, // 市场开始时的 YES 价格
    peak_yes_price: f64, // 观察到的最高 YES 价格
    crash_start_price: f64, // 暴跌开始时的价格
    price_history: [120]f64, // 2分钟的价格历史（每秒一个）
    price_idx: usize,

    // 市场和连接
    current_market: ?MarketInfo,
    ws_channel: ?MarketChannel,
    running: bool,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        client: *ClobClient,
        wallet: ?*const Wallet,
        config: StrategyConfig,
    ) Self {
        g_edge_threshold = config.edge_price_threshold;

        return Self{
            .allocator = allocator,
            .config = config,
            .client = client,
            .wallet = wallet,
            .builder = if (wallet) |w| OrderBuilder.init(w, .{
                .chain_id = if (config.use_testnet) 80002 else 137,
                .funder = config.funder,
            }) else null,
            .phase = .waiting_for_crash,
            .yes_position = .{},
            .no_position = .{},
            .stats = .{},
            .initial_yes_price = 0.5,
            .peak_yes_price = 0.5,
            .crash_start_price = 0,
            .price_history = [_]f64{0} ** 120,
            .price_idx = 0,
            .current_market = null,
            .ws_channel = null,
            .running = true,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.ws_channel) |*channel| {
            channel.deinit();
        }
    }

    /// 主运行循环
    pub fn run(self: *Self) !void {
        self.printBanner();

        while (self.running) {
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

                // 设置全局 token IDs
                @memcpy(g_up_token_id[0..m.up_token_id_len], m.up_token_id_buf[0..m.up_token_id_len]);
                g_up_token_len = m.up_token_id_len;
                @memcpy(g_down_token_id[0..m.down_token_id_len], m.down_token_id_buf[0..m.down_token_id_len]);
                g_down_token_len = m.down_token_id_len;

                // 重置策略状态
                self.resetForNewMarket();

                // 执行策略
                log("", .{});
                log("════════════════════════════════════════════════════════════════", .{});
                log("  执行两步对冲套利策略...", .{});
                log("  参数: sumTarget={d:.2}, move={d:.2}%", .{ self.config.sum_target, self.config.move_threshold * 100 });
                log("════════════════════════════════════════════════════════════════", .{});

                self.executeStrategy(m) catch |err| {
                    log("策略执行失败: {}", .{err});
                };

                // 清理
                self.disconnectWebSocket();
                self.printMarketSummary();
                self.stats.markets_traded += 1;
            } else {
                self.showNextExpectedMarket();
                std.Thread.sleep(5 * std.time.ns_per_s);
            }
        }

        self.printFinalStats();
    }

    /// 重置市场状态
    fn resetForNewMarket(self: *Self) void {
        self.phase = .waiting_for_crash;
        self.yes_position.reset();
        self.no_position.reset();
        self.initial_yes_price = 0.5;
        self.peak_yes_price = 0.5;
        self.crash_start_price = 0;
        self.price_history = [_]f64{0} ** 120;
        self.price_idx = 0;
        g_live_book = .{};
    }

    /// 执行两步对冲策略
    fn executeStrategy(self: *Self, market: MarketInfo) !void {
        var last_print_time: i64 = 0;
        var last_warning_time: i64 = 0; // 警告冷却
        var first_price_received = false;
        var use_websocket = false;

        // 尝试连接 WebSocket 获取实时数据
        self.connectWebSocket(market) catch |err| {
            log("  WebSocket 连接失败: {}，使用 HTTP 轮询", .{err});
        };
        if (self.ws_channel != null) {
            use_websocket = true;
            log("  ✅ WebSocket 已连接，使用实时数据", .{});
            // 等待 WebSocket 接收初始数据
            std.Thread.sleep(1 * std.time.ns_per_s);
        }

        // 先获取一次初始订单簿数据
        self.fetchOrderBook(market) catch {};

        while (self.running) {
            const now = std.time.timestamp();
            const remaining = market.end_timestamp - now;

            // 检查剩余时间
            if (remaining < 30) {
                log("  剩余时间不足 30 秒，停止交易", .{});
                break;
            }

            // ⚠️ 紧急流动性检查 - 当持仓且没有买家时（每30秒警告一次）
            if (remaining < 300 and self.yes_position.shares > 0 and g_live_book.up_best_bid <= 0.01 and (now - last_warning_time) >= 30) {
                last_warning_time = now;
                log("", .{});
                log("  ⚠️⚠️⚠️ 紧急警告 ⚠️⚠️⚠️", .{});
                log("  剩余 {d} 秒，UP bid = {d:.4}，几乎没有买家!", .{ remaining, g_live_book.up_best_bid });
                log("  持仓 {d:.2} 股，成本 ${d:.2}", .{ self.yes_position.shares, self.yes_position.total_cost });
                log("  按当前 bid 估值: ${d:.2}", .{g_live_book.up_best_bid * self.yes_position.shares});
                log("  ⚠️ 考虑手动平仓或等待市场结算!", .{});
                log("", .{});
            }

            // 如果使用 WebSocket，只需偶尔同步一次；否则每次轮询
            if (!use_websocket or g_live_book.update_count == 0 or (now - g_live_book.last_update) > 5) {
                // HTTP 轮询获取订单簿数据
                self.fetchOrderBook(market) catch |err| {
                    log("  获取订单簿失败: {}", .{err});
                    std.Thread.sleep(500 * std.time.ns_per_ms);
                    continue;
                };
            }

            const yes_price = g_live_book.yesPrice();

            // 记录初始价格
            if (!first_price_received and yes_price > 0 and yes_price < 1) {
                self.initial_yes_price = yes_price;
                self.peak_yes_price = yes_price;
                first_price_received = true;
                log("  初始 YES 价格: {d:.4}", .{yes_price});
            }

            // 更新峰值价格
            if (yes_price > self.peak_yes_price) {
                self.peak_yes_price = yes_price;
            }

            // 记录价格历史
            self.price_history[self.price_idx] = yes_price;
            self.price_idx = (self.price_idx + 1) % 120;

            // 定期打印状态（每 2 秒）
            if (now - last_print_time >= 2) {
                last_print_time = now;
                self.printLiveStatus(market);
            }

            // ========== 风险管理 ==========

            // 1. 止损检查：亏损超过阈值时强制对冲
            if (self.yes_position.shares > 0 and self.phase != .hedged) {
                const current_value = yes_price * self.yes_position.shares;
                const loss_ratio = (self.yes_position.total_cost - current_value) / self.yes_position.total_cost;

                if (loss_ratio >= self.config.stop_loss_threshold) {
                    log("", .{});
                    log("  🛑 触发止损! 亏损 {d:.1}% >= {d:.1}%", .{ loss_ratio * 100, self.config.stop_loss_threshold * 100 });
                    log("  成本: ${d:.2}, 当前价值: ${d:.2}", .{ self.yes_position.total_cost, current_value });

                    // 尝试对冲锁定剩余价值
                    const hedge_success = try self.executeHedge(market, yes_price);
                    if (hedge_success) {
                        self.phase = .hedged;
                        log("  ✅ 止损对冲成功，锁定剩余价值", .{});
                    } else {
                        log("  ⚠️ 止损对冲失败，将继续尝试", .{});
                    }
                }
            }

            // 2. 无流动性强制退出：当 bid=0 且时间紧迫时
            if (self.yes_position.shares > 0 and g_live_book.up_best_bid <= 0.001 and remaining <= self.config.force_exit_remaining) {
                log("", .{});
                log("  🆘 无流动性紧急处理! bid=0, 剩余 {d} 秒", .{remaining});

                // 尝试对冲（买入 NO）
                if (self.phase != .hedged and g_live_book.down_best_ask < 1.0) {
                    log("  尝试紧急对冲（买入 NO）...", .{});
                    const hedge_success = try self.executeHedge(market, yes_price);
                    if (hedge_success) {
                        self.phase = .hedged;
                        log("  ✅ 紧急对冲成功!", .{});
                    }
                }
            }

            // 3. 止盈检查：对冲后如果 YES 价格涨到很高，可以卖出 YES
            if (self.phase == .hedged and yes_price >= self.config.take_profit_threshold and g_live_book.up_best_bid > 0) {
                log("", .{});
                log("  💰 触发止盈! YES 价格 {d:.4} >= {d:.2}", .{ yes_price, self.config.take_profit_threshold });
                log("  建议手动卖出 YES 锁定利润（自动卖出功能待实现）", .{});
                // TODO: 实现自动卖出 YES
            }

            // ========== 策略核心逻辑 ==========

            switch (self.phase) {
                .waiting_for_crash => {
                    // 检测暴跌
                    if (self.detectCrash(yes_price)) {
                        self.phase = .buying_yes;
                        self.crash_start_price = yes_price;
                        self.stats.crashes_detected += 1;
                        log("", .{});
                        log("  🚨 检测到暴跌! 当前价格: {d:.4}, 峰值: {d:.4}, 跌幅: {d:.2}%", .{
                            yes_price,
                            self.peak_yes_price,
                            (self.peak_yes_price - yes_price) / self.peak_yes_price * 100,
                        });
                        log("  ➡️ 进入第一步：买入 YES", .{});
                    }
                },

                .buying_yes => {
                    // 第一步：继续买入 YES，直到达到 sumTarget
                    try self.executeBuyYes(market, yes_price);

                    // 检查是否已买够
                    const current_sum = self.yes_position.total_cost / self.config.max_position;
                    if (current_sum >= self.config.sum_target) {
                        self.phase = .waiting_for_rebound;
                        log("", .{});
                        log("  ✅ 第一步完成! 已买入 YES: {d:.2} 股, 成本: ${d:.2}, 均价: {d:.4}", .{
                            self.yes_position.shares,
                            self.yes_position.total_cost,
                            self.yes_position.avgPrice(),
                        });
                        log("  ➡️ 进入第二步：等待反弹对冲", .{});
                    }
                },

                .waiting_for_rebound => {
                    // 第二步：等待能够盈利对冲的机会
                    const avg_buy_price = self.yes_position.avgPrice();
                    const no_ask_price = g_live_book.down_best_ask;

                    // 🔴 关键检查：对冲后是否盈利？
                    // YES成本 + NO成本 必须 < $1 才能盈利！
                    const total_cost_per_share = avg_buy_price + no_ask_price;
                    const expected_profit_per_share = 1.0 - total_cost_per_share;

                    // 只有当预期利润 > 0 时才对冲
                    if (expected_profit_per_share > 0) {
                        log("", .{});
                        log("  📊 对冲机会分析:", .{});
                        log("    YES 均价: {d:.4}, NO 卖价: {d:.4}", .{ avg_buy_price, no_ask_price });
                        log("    总成本/股: ${d:.4}, 预期利润/股: ${d:.4}", .{ total_cost_per_share, expected_profit_per_share });

                        const hedge_success = try self.executeHedge(market, yes_price);
                        if (hedge_success) {
                            self.phase = .hedged;
                            log("", .{});
                            log("  ✅ 对冲完成! 锁定利润", .{});
                            log("  YES 成本: ${d:.2}, NO 成本: ${d:.2}", .{
                                self.yes_position.total_cost,
                                self.no_position.total_revenue,
                            });
                            // 利润 = 锁定价值($1/股) - YES成本 - NO成本
                            const locked_value = self.yes_position.shares;
                            const total_cost = self.yes_position.total_cost + self.no_position.total_revenue;
                            log("  锁定价值: ${d:.2}, 总成本: ${d:.2}, 利润: ${d:.2}", .{
                                locked_value,
                                total_cost,
                                locked_value - total_cost,
                            });
                        }
                    }
                    // 如果不盈利，继续等待更好的机会
                },

                .hedged => {
                    // 已对冲，等待市场结束
                    // 可以考虑追加对冲或提前退出
                },
            }

            // 休眠 - WebSocket 模式下更快响应
            if (use_websocket) {
                std.Thread.sleep(100 * std.time.ns_per_ms); // 100ms
            } else {
                std.Thread.sleep(500 * std.time.ns_per_ms); // 500ms
            }
        }
    }

    /// 检测暴跌
    fn detectCrash(self: *Self, current_price: f64) bool {
        // 方法1：与峰值比较
        if (self.peak_yes_price > 0) {
            const drop_from_peak = (self.peak_yes_price - current_price) / self.peak_yes_price;
            if (drop_from_peak >= self.config.move_threshold) {
                return true;
            }
        }

        // 方法2：与短期均价比较（最近 10 秒）
        var sum: f64 = 0;
        var count: f64 = 0;
        for (self.price_history) |p| {
            if (p > 0) {
                sum += p;
                count += 1;
            }
        }
        if (count >= 5) {
            const avg = sum / count;
            const drop_from_avg = (avg - current_price) / avg;
            if (drop_from_avg >= self.config.move_threshold) {
                return true;
            }
        }

        return false;
    }

    /// 执行买入 YES
    fn executeBuyYes(self: *Self, market: MarketInfo, current_price: f64) !void {
        // 🔴 关键检查：只在低价时买入！
        // 这是套利策略，不是追涨 - 只在价格足够低时才买
        if (current_price > self.config.max_buy_price) {
            // 价格太高，等待更低的价格
            return;
        }

        // 检查价差
        const spread = g_live_book.up_best_ask - g_live_book.up_best_bid;
        if (spread > self.config.max_spread) {
            return; // 价差过大，不买
        }

        // 检查仓位限制
        if (self.yes_position.total_cost >= self.config.max_position * self.config.sum_target) {
            return; // 已达目标
        }

        // 计算买入金额（价格越低买越多）
        // 使用累进买入：价格越低，买入量越大
        const price_factor = 1.0 - current_price; // 价格 0.2 -> factor 0.8
        var buy_amount = self.config.min_order_size + (self.config.max_order_size - self.config.min_order_size) * price_factor;

        // 限制不超过剩余额度
        const remaining_budget = self.config.max_position * self.config.sum_target - self.yes_position.total_cost;

        // 如果剩余预算小于最小订单，但大于 $1，则买入剩余预算完成目标
        if (remaining_budget < self.config.min_order_size) {
            if (remaining_budget >= 1.0) {
                // 剩余预算不多但足够下单，完成买入
                buy_amount = remaining_budget;
                log("  📦 剩余预算 ${d:.2} < 最小订单，完成最后买入", .{remaining_budget});
            } else {
                // 剩余预算太小，跳过
                return;
            }
        } else {
            buy_amount = @min(buy_amount, remaining_budget);
        }

        if (buy_amount < 1.0) {
            return; // 金额太小（API 最低 $1）
        }

        // 计算股数
        const buy_price = g_live_book.up_best_ask; // 以卖一价买入
        var shares = buy_amount / buy_price;

        // 确保订单金额 >= $1 (API 最低要求)
        const min_api_amount: f64 = 1.0;
        const actual_amount = shares * buy_price;
        if (actual_amount < min_api_amount) {
            // 调整股数以满足最低金额要求
            shares = @ceil(min_api_amount / buy_price);
        }

        const final_amount = shares * buy_price;
        log("  📈 买入 YES: {d:.2} 股 @ {d:.4}, 金额: ${d:.2}", .{ shares, buy_price, final_amount });

        if (self.config.dry_run) {
            // 模拟模式
            self.yes_position.addBuy(shares, final_amount);
            self.stats.yes_buys += 1;
            log("  ✅ [模拟] 买入成功!", .{});
        } else {
            // 实盘下单
            if (self.builder) |*builder| {
                const price_str = try std.fmt.allocPrint(self.allocator, "{d:.2}", .{buy_price});
                defer self.allocator.free(price_str);
                // 使用整数股数（向上取整确保金额足够）
                // Polymarket CLOB 最小订单为 5 股
                var int_shares: u64 = @intFromFloat(@ceil(shares));
                if (int_shares < 5) {
                    int_shares = 5;
                }
                const size_str = try std.fmt.allocPrint(self.allocator, "{d}", .{int_shares});
                defer self.allocator.free(size_str);

                const order = try builder.createOrder(.{
                    .token_id = market.getUpTokenId(),
                    .price = try Decimal.fromString(price_str),
                    .size = try Decimal.fromString(size_str),
                    .side = .BUY,
                }, .{
                    .tick_size = .@"0.01",
                    .neg_risk = false,
                    .signature_type = self.config.signature_type,
                });

                const response = self.client.postOrder(&order, .GTC) catch |err| {
                    log("  ❌ 下单失败: {}", .{err});
                    std.Thread.sleep(5 * std.time.ns_per_s); // 暂停5秒让用户看到错误
                    return;
                };

                if (response.success) {
                    const order_shares = @as(f64, @floatFromInt(int_shares));
                    const order_cost = order_shares * buy_price;
                    self.yes_position.addBuy(order_shares, order_cost);
                    self.stats.yes_buys += 1;
                    log("  ✅ 订单成功!", .{});
                } else {
                    log("  ❌ 订单被拒绝", .{});
                    std.Thread.sleep(5 * std.time.ns_per_s); // 暂停5秒让用户看到错误
                }
            }
        }
    }

    /// 执行对冲（买入 NO）
    /// 返回 true 表示对冲成功，false 表示失败
    ///
    /// 对冲原理：持有 YES 后，买入等量 NO
    /// 因为 YES + NO = $1（结算时），无论结果如何都能锁定价值
    /// 利润 = $1 - YES成本 - NO成本
    fn executeHedge(self: *Self, market: MarketInfo, _: f64) !bool {
        // 买入等量的 NO 股份（使用整数）
        const int_shares: u64 = @intFromFloat(@floor(self.yes_position.shares));
        if (int_shares == 0) {
            log("  ⚠️ 没有足够的 YES 持仓进行对冲", .{});
            return false;
        }

        // Polymarket CLOB 最小订单为 5 股
        if (int_shares < 5) {
            log("  ⚠️ YES 持仓 {d} 股 < 5 股，无法对冲（最低 5 股）", .{int_shares});
            return false;
        }

        const shares_to_buy = @as(f64, @floatFromInt(int_shares));
        const no_buy_price = g_live_book.down_best_ask; // 以卖一价买入
        const cost = shares_to_buy * no_buy_price;

        // 确保订单金额 >= $1 (API 最低要求)
        if (cost < 1.0) {
            log("  ⚠️ 对冲金额 ${d:.2} 小于最低要求 $1，跳过", .{cost});
            return false;
        }

        log("  📈 对冲买入 NO: {d:.0} 股 @ {d:.4}, 成本: ${d:.2}", .{ shares_to_buy, no_buy_price, cost });

        if (self.config.dry_run) {
            // 模拟模式
            self.no_position.shares += shares_to_buy;
            self.no_position.total_revenue = cost; // 这里改为记录成本
            self.stats.hedges_executed += 1;

            // 计算利润
            // YES + NO = $1（结算时）
            // 锁定价值 = shares * $1 = shares
            // 利润 = 锁定价值 - YES成本 - NO成本
            const locked_value = shares_to_buy;
            const profit = locked_value - self.yes_position.total_cost - cost;
            self.stats.total_profit += profit;
            log("  ✅ [模拟] 对冲成功! 锁定利润: ${d:.2}", .{profit});
            return true;
        } else {
            // 实盘下单 - 买入 NO
            if (self.builder) |*builder| {
                const price_str = try std.fmt.allocPrint(self.allocator, "{d:.2}", .{no_buy_price});
                defer self.allocator.free(price_str);
                const size_str = try std.fmt.allocPrint(self.allocator, "{d}", .{int_shares});
                defer self.allocator.free(size_str);

                const order = try builder.createOrder(.{
                    .token_id = market.getDownTokenId(),
                    .price = try Decimal.fromString(price_str),
                    .size = try Decimal.fromString(size_str),
                    .side = .BUY, // 买入 NO（不是卖出！）
                }, .{
                    .tick_size = .@"0.01",
                    .neg_risk = false,
                    .signature_type = self.config.signature_type,
                });

                const response = self.client.postOrder(&order, .GTC) catch |err| {
                    log("  ❌ 对冲下单失败: {}", .{err});
                    std.Thread.sleep(5 * std.time.ns_per_s); // 暂停5秒让用户看到错误
                    return false;
                };

                if (response.success) {
                    self.no_position.shares += shares_to_buy;
                    self.no_position.total_revenue = cost;
                    self.stats.hedges_executed += 1;

                    const locked_value = shares_to_buy;
                    const profit = locked_value - self.yes_position.total_cost - cost;
                    self.stats.total_profit += profit;

                    log("  ✅ 对冲成功!", .{});
                    return true;
                } else {
                    log("  ❌ 对冲被拒绝", .{});
                    std.Thread.sleep(5 * std.time.ns_per_s); // 暂停5秒让用户看到错误
                    return false;
                }
            }
            return false;
        }
    }

    /// 获取订单簿
    fn fetchOrderBook(self: *Self, market: MarketInfo) !void {
        const up_book = self.client.getOrderBook(market.getUpTokenId()) catch return;
        defer up_book.deinit();

        const down_book = self.client.getOrderBook(market.getDownTokenId()) catch return;
        defer down_book.deinit();

        // 解析 UP 订单簿
        var up_best_bid: f64 = 0;
        var up_best_ask: f64 = 1;

        if (up_book.value.bids) |bids| {
            for (bids) |bid| {
                const price = std.fmt.parseFloat(f64, bid.price) catch continue;
                if (price >= g_edge_threshold and price > up_best_bid) {
                    up_best_bid = price;
                }
            }
        }

        if (up_book.value.asks) |asks| {
            for (asks) |ask| {
                const price = std.fmt.parseFloat(f64, ask.price) catch continue;
                if (price <= (1.0 - g_edge_threshold) and price < up_best_ask) {
                    up_best_ask = price;
                }
            }
        }

        // 解析 DOWN 订单簿
        var down_best_bid: f64 = 0;
        var down_best_ask: f64 = 1;

        if (down_book.value.bids) |bids| {
            for (bids) |bid| {
                const price = std.fmt.parseFloat(f64, bid.price) catch continue;
                if (price >= g_edge_threshold and price > down_best_bid) {
                    down_best_bid = price;
                }
            }
        }

        if (down_book.value.asks) |asks| {
            for (asks) |ask| {
                const price = std.fmt.parseFloat(f64, ask.price) catch continue;
                if (price <= (1.0 - g_edge_threshold) and price < down_best_ask) {
                    down_best_ask = price;
                }
            }
        }

        // 更新全局状态
        g_live_book.up_best_bid = up_best_bid;
        g_live_book.up_best_ask = up_best_ask;
        // 中间价：始终使用实际值
        g_live_book.up_mid_price = if (up_best_ask > up_best_bid)
            (up_best_bid + up_best_ask) / 2.0
        else if (up_best_bid > 0)
            up_best_bid
        else if (up_best_ask < 1)
            up_best_ask
        else
            0.5;

        g_live_book.down_best_bid = down_best_bid;
        g_live_book.down_best_ask = down_best_ask;
        g_live_book.down_mid_price = if (down_best_ask > down_best_bid)
            (down_best_bid + down_best_ask) / 2.0
        else if (down_best_bid > 0)
            down_best_bid
        else if (down_best_ask < 1)
            down_best_ask
        else
            0.5;

        g_live_book.last_update = std.time.timestamp();
        g_live_book.update_count += 1;
    }

    /// 打印实时状态
    fn printLiveStatus(self: *Self, market: MarketInfo) void {
        const remaining = market.getRemainingSeconds();
        const mins = @divFloor(remaining, 60);
        const secs = @mod(remaining, 60);
        const yes_price = g_live_book.yesPrice();

        // 清屏
        std.debug.print("\x1B[2J\x1B[H", .{});

        std.debug.print("\n", .{});
        std.debug.print("╔═══════════════════════════════════════════════════════════════════════════╗\n", .{});
        std.debug.print("║     BTC 15分钟 两步对冲套利机器人 - {s}     ║\n", .{if (self.config.dry_run) "模拟模式" else "实盘模式"});
        std.debug.print("╠═══════════════════════════════════════════════════════════════════════════╣\n", .{});
        std.debug.print("║  市场: {s:<64} ║\n", .{market.getSlug()});
        std.debug.print("║  剩余: {d:>2}:{d:0>2}    策略阶段: {s:<25}                ║\n", .{
            mins,
            secs,
            @tagName(self.phase),
        });
        // 显示数据源和更新次数
        const now = std.time.timestamp();
        const data_age = now - g_live_book.last_update;
        const data_source = if (self.ws_channel != null) "WebSocket" else "HTTP轮询";
        std.debug.print("║  数据源: {s:<10} 更新: {d} 次  延迟: {d}s                       ║\n", .{
            data_source,
            g_live_book.update_count,
            data_age,
        });
        std.debug.print("╠═══════════════════════════════════════════════════════════════════════════╣\n", .{});
        std.debug.print("║                          价 格 监 控                                      ║\n", .{});
        std.debug.print("╠═══════════════════════════════════════════════════════════════════════════╣\n", .{});
        std.debug.print("║  YES 价格: {d:.4}   (初始: {d:.4}, 峰值: {d:.4})                       ║\n", .{
            yes_price,
            self.initial_yes_price,
            self.peak_yes_price,
        });
        std.debug.print("║  NO  价格: {d:.4}                                                        ║\n", .{
            g_live_book.noPrice(),
        });

        // 显示暴跌检测状态
        if (self.peak_yes_price > 0) {
            const drop = (self.peak_yes_price - yes_price) / self.peak_yes_price * 100;
            std.debug.print("║  从峰值跌幅: {d:>5.2}%   (触发阈值: {d:.2}%)                             ║\n", .{
                drop,
                self.config.move_threshold * 100,
            });
        }

        std.debug.print("╠═══════════════════════════════════════════════════════════════════════════╣\n", .{});
        std.debug.print("║                          仓 位 状 态                                      ║\n", .{});
        std.debug.print("╠═══════════════════════════════════════════════════════════════════════════╣\n", .{});
        std.debug.print("║  YES 持仓: {d:>7.2} 股   成本: ${d:>7.2}   均价: {d:.4}                 ║\n", .{
            self.yes_position.shares,
            self.yes_position.total_cost,
            self.yes_position.avgPrice(),
        });
        std.debug.print("║  NO  对冲: {d:>7.2} 股   成本: ${d:>7.2}                                 ║\n", .{
            self.no_position.shares,
            self.no_position.total_revenue,
        });

        // 显示进度
        const progress = self.yes_position.total_cost / (self.config.max_position * self.config.sum_target) * 100;
        std.debug.print("║  买入进度: {d:>5.1}% / {d:.0}%                                              ║\n", .{
            progress,
            self.config.sum_target * 100,
        });

        // 显示对冲分析
        if (self.yes_position.shares > 0 and self.phase != .hedged) {
            const avg_buy = self.yes_position.avgPrice();
            const no_ask = g_live_book.down_best_ask;
            const total_cost_per_share = avg_buy + no_ask;
            const hedge_profit_per_share = 1.0 - total_cost_per_share;
            const total_hedge_profit = hedge_profit_per_share * self.yes_position.shares;

            // 显示当前浮盈（按 bid 价）
            const sell_price = g_live_book.up_best_bid;
            const current_value = sell_price * self.yes_position.shares;
            const unrealized_pnl = current_value - self.yes_position.total_cost;

            std.debug.print("║  当前浮盈: ${d:>7.2}   (按bid={d:.2})                                ║\n", .{
                unrealized_pnl,
                sell_price,
            });

            // 显示如果现在对冲的预期盈亏
            if (hedge_profit_per_share > 0) {
                std.debug.print("║  🟢 如对冲: ${d:>7.2}   (YES {d:.2} + NO {d:.2} = {d:.2} < $1)       ║\n", .{
                    total_hedge_profit,
                    avg_buy,
                    no_ask,
                    total_cost_per_share,
                });
            } else {
                std.debug.print("║  🔴 如对冲: ${d:>7.2}   (YES {d:.2} + NO {d:.2} = {d:.2} > $1)       ║\n", .{
                    total_hedge_profit,
                    avg_buy,
                    no_ask,
                    total_cost_per_share,
                });
            }
        }

        if (self.phase == .hedged) {
            std.debug.print("║  ✅ 已锁定利润: ${d:>7.2}                                              ║\n", .{
                self.stats.total_profit,
            });
        }

        std.debug.print("╠═══════════════════════════════════════════════════════════════════════════╣\n", .{});
        std.debug.print("║  参数: sumTarget={d:.2}  move={d:.2}%  hedge={d:.2}%                        ║\n", .{
            self.config.sum_target,
            self.config.move_threshold * 100,
            self.config.hedge_profit_threshold * 100,
        });
        std.debug.print("╚═══════════════════════════════════════════════════════════════════════════╝\n", .{});

        // ========== 订单簿显示 ==========
        const up_spread = g_live_book.up_best_ask - g_live_book.up_best_bid;
        const down_spread = g_live_book.down_best_ask - g_live_book.down_best_bid;
        const total_mid = g_live_book.up_mid_price + g_live_book.down_mid_price;

        std.debug.print("\n", .{});
        std.debug.print("┌─────────────────────────────────────┬─────────────────────────────────────┐\n", .{});
        std.debug.print("│          🟢 UP (涨)                 │          🔴 DOWN (跌)               │\n", .{});
        std.debug.print("├─────────────────────────────────────┼─────────────────────────────────────┤\n", .{});
        std.debug.print("│  买价: {d:.4}   卖价: {d:.4}        │  买价: {d:.4}   卖价: {d:.4}        │\n", .{
            g_live_book.up_best_bid,
            g_live_book.up_best_ask,
            g_live_book.down_best_bid,
            g_live_book.down_best_ask,
        });
        std.debug.print("│  中间价: {d:.4}  价差: {d:.4}       │  中间价: {d:.4}  价差: {d:.4}       │\n", .{
            g_live_book.up_mid_price,
            up_spread,
            g_live_book.down_mid_price,
            down_spread,
        });
        std.debug.print("└─────────────────────────────────────┴─────────────────────────────────────┘\n", .{});

        // ⚠️ 流动性危机警告 - 当持有仓位但 bid=0 时
        if (self.yes_position.shares > 0 and g_live_book.up_best_bid <= 0.001) {
            std.debug.print("  🚨 严重警告: UP 没有买家 (bid={d:.4})! 仓位可能无法卖出!\n", .{g_live_book.up_best_bid});
            std.debug.print("  💀 按 bid 价估值: ${d:.2} (成本 ${d:.2})\n", .{
                g_live_book.up_best_bid * self.yes_position.shares,
                self.yes_position.total_cost,
            });
        }
        if (self.no_position.shares > 0 and g_live_book.down_best_bid <= 0.001) {
            std.debug.print("  🚨 严重警告: DOWN 没有买家 (bid={d:.4})! 仓位可能无法卖出!\n", .{g_live_book.down_best_bid});
        }

        // 市场健康状态
        if (up_spread > 0.5 or down_spread > 0.5) {
            std.debug.print("  ⚠️  警告: 价差过大! 流动性不足\n", .{});
        } else if (up_spread > 0.2 or down_spread > 0.2) {
            std.debug.print("  ⚡ 注意: 价差较大，交易需谨慎\n", .{});
        } else if (up_spread > 0 and down_spread > 0) {
            std.debug.print("  ✅ 市场健康: 价差正常\n", .{});
        }

        // 套利机会检测
        if (total_mid > 0) {
            if (total_mid < 0.98) {
                std.debug.print("  💰 套利机会! UP + DOWN = {d:.4} < 1.00\n", .{total_mid});
            } else if (total_mid > 1.02) {
                std.debug.print("  💰 套利机会! UP + DOWN = {d:.4} > 1.00\n", .{total_mid});
            } else {
                std.debug.print("  📊 UP + DOWN = {d:.4} (正常)\n", .{total_mid});
            }
        }
    }

    /// 打印市场总结
    fn printMarketSummary(self: *Self) void {
        log("", .{});
        log("════════════════════════════════════════════════════════════════", .{});
        log("  市场结束总结", .{});
        log("════════════════════════════════════════════════════════════════", .{});
        log("  最终阶段: {s}", .{@tagName(self.phase)});
        log("  YES 买入: {d} 次, 共 {d:.2} 股, 成本 ${d:.2}", .{
            self.yes_position.buy_count,
            self.yes_position.shares,
            self.yes_position.total_cost,
        });
        if (self.no_position.shares > 0) {
            log("  NO 对冲: {d:.2} 股, 收入 ${d:.2}", .{
                self.no_position.shares,
                self.no_position.total_revenue,
            });
        }
        log("════════════════════════════════════════════════════════════════", .{});
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
                const started = now >= market_info.start_timestamp;

                // 检查市场是否已开始
                if (!started) {
                    const wait = market_info.start_timestamp - now;
                    log("  市场 {s} 还未开始，等待 {d} 秒", .{ slug, wait });
                    continue;
                }

                if (remaining < self.config.min_remaining_minutes * 60) {
                    log("  市场 {s} 剩余时间不足 ({d}秒)，跳过", .{ slug, remaining });
                    continue;
                }

                if (remaining <= 0) {
                    continue;
                }

                log("  找到活跃市场: {s}，剩余 {d} 分钟", .{ slug, @divFloor(remaining, 60) });
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

        const start_timestamp = parseTimestampFromSlug(slug);
        if (start_timestamp == 0) return error.InvalidTimestamp;
        const end_timestamp = start_timestamp + 900;

        var info = MarketInfo{
            .start_timestamp = start_timestamp,
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

    fn connectWebSocket(self: *Self, market: MarketInfo) !void {
        g_live_book = .{};

        self.ws_channel = try MarketChannel.init(self.allocator, .{
            .on_book = onBookMessage,
            .on_price_change = onPriceChange,
            .on_connection = onConnectionChange,
            .on_error = onError,
            .auto_reconnect = true,
        });

        try self.ws_channel.?.connect();

        const tokens = [_][]const u8{
            market.getUpTokenId(),
            market.getDownTokenId(),
        };
        try self.ws_channel.?.subscribe(&tokens);
    }

    fn disconnectWebSocket(self: *Self) void {
        if (self.ws_channel) |*channel| {
            channel.disconnect();
            channel.deinit();
            self.ws_channel = null;
        }
    }

    fn printBanner(self: *Self) void {
        std.debug.print("\n", .{});
        std.debug.print("╔══════════════════════════════════════════════════════════════════╗\n", .{});
        std.debug.print("║   BTC 15分钟 两步对冲套利机器人 - Polymarket                     ║\n", .{});
        std.debug.print("╠══════════════════════════════════════════════════════════════════╣\n", .{});
        std.debug.print("║  策略: 暴跌买入 YES -> 反弹对冲 NO -> 锁定利润                   ║\n", .{});
        std.debug.print("╠══════════════════════════════════════════════════════════════════╣\n", .{});
        std.debug.print("║  模式: {s:<58} ║\n", .{if (self.config.dry_run) "模拟交易" else "实盘交易"});
        std.debug.print("║  sumTarget: {d:<5.2}  (目标买入比例)                              ║\n", .{self.config.sum_target});
        std.debug.print("║  move: {d:<5.2}%  (暴跌触发阈值)                                  ║\n", .{self.config.move_threshold * 100});
        std.debug.print("║  hedge: {d:<5.2}%  (反弹对冲阈值)                                 ║\n", .{self.config.hedge_profit_threshold * 100});
        std.debug.print("╚══════════════════════════════════════════════════════════════════╝\n", .{});
        std.debug.print("\n", .{});
    }

    fn printFinalStats(self: *Self) void {
        std.debug.print("\n", .{});
        std.debug.print("╔══════════════════════════════════════════════════════════════════╗\n", .{});
        std.debug.print("║                        最终交易统计                               ║\n", .{});
        std.debug.print("╚══════════════════════════════════════════════════════════════════╝\n", .{});
        std.debug.print("  交易市场数: {d}\n", .{self.stats.markets_traded});
        std.debug.print("  暴跌检测数: {d}\n", .{self.stats.crashes_detected});
        std.debug.print("  YES 买入数: {d}\n", .{self.stats.yes_buys});
        std.debug.print("  对冲执行数: {d}\n", .{self.stats.hedges_executed});
        std.debug.print("  累计利润: ${d:.2}\n", .{self.stats.total_profit});
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

fn parseFunderAddress(hex: []const u8) ?[20]u8 {
    const clean = if (hex.len >= 2 and hex[0] == '0' and (hex[1] == 'x' or hex[1] == 'X'))
        hex[2..]
    else
        hex;

    if (clean.len != 40) return null;

    var result: [20]u8 = undefined;
    for (0..20) |i| {
        const high = std.fmt.charToDigit(clean[i * 2], 16) catch return null;
        const low = std.fmt.charToDigit(clean[i * 2 + 1], 16) catch return null;
        result[i] = (high << 4) | low;
    }
    return result;
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

    // 解析签名类型
    const sig_type_val = env.getInt(u8, "WS_TRADER_SIGNATURE_TYPE", 2);
    const signature_type = SignatureType.fromU8(sig_type_val) orelse .POLY_GNOSIS_SAFE;

    // 解析 funder/proxy 地址
    var funder: ?[20]u8 = null;
    if (env.get("POLY_FUNDER_ADDRESS") orelse env.get("POLY_ADDRESS")) |funder_hex| {
        funder = parseFunderAddress(funder_hex);
        if (funder == null) {
            std.debug.print("警告: POLY_FUNDER_ADDRESS 格式无效: {s}\n", .{funder_hex});
        }
    }

    // 解析策略配置
    const config = StrategyConfig{
        .dry_run = env.getBool("WS_TRADER_DRY_RUN", true),

        // 核心策略参数
        .sum_target = env.getFloat(f64, "WS_TRADER_SUM_TARGET", 0.3),
        .move_threshold = env.getFloat(f64, "WS_TRADER_MOVE", 0.01),
        .hedge_profit_threshold = env.getFloat(f64, "WS_TRADER_HEDGE_THRESHOLD", 0.05),

        // 风险管理参数
        .stop_loss_threshold = env.getFloat(f64, "WS_TRADER_STOP_LOSS", 0.30),
        .force_exit_remaining = env.getInt(i64, "WS_TRADER_FORCE_EXIT_TIME", 120),
        .take_profit_threshold = env.getFloat(f64, "WS_TRADER_TAKE_PROFIT", 0.90),
        .max_buy_price = env.getFloat(f64, "WS_TRADER_MAX_BUY_PRICE", 0.50),

        // 交易参数
        .min_order_size = env.getFloat(f64, "WS_TRADER_MIN_ORDER", 5.0),
        .max_order_size = env.getFloat(f64, "WS_TRADER_MAX_ORDER", 50.0),
        .max_position = env.getFloat(f64, "WS_TRADER_MAX_POSITION", 200.0),

        // 市场参数
        .min_remaining_minutes = env.getInt(i64, "WS_TRADER_MIN_REMAINING", 3),
        .edge_price_threshold = env.getFloat(f64, "WS_TRADER_EDGE_THRESHOLD", 0.05),
        .max_spread = env.getFloat(f64, "WS_TRADER_MAX_SPREAD", 0.10),

        // 系统参数
        .use_testnet = env.getBool("POLY_USE_TESTNET", false),
        .signature_type = signature_type,
        .funder = funder,
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

        // 检查余额
        const bal_result = client.getBalanceAllowance(.{
            .asset_type = .COLLATERAL,
            .signature_type = @intFromEnum(config.signature_type),
        }) catch |err| {
            std.debug.print("查询余额失败: {}\n", .{err});
            // 清理已分配的资源
            if (creds) |*c| c.deinit();
            client.deinit();
            return err;
        };
        defer bal_result.deinit();

        const bal_str = bal_result.value.balance orelse "0";
        const allow_str = bal_result.value.allowance orelse "0";
        const bal_val = std.fmt.parseInt(u64, bal_str, 10) catch 0;
        const allow_val = std.fmt.parseInt(u64, allow_str, 10) catch 0;
        const bal_usdc = @as(f64, @floatFromInt(bal_val)) / 1_000_000.0;
        const allow_usdc = @as(f64, @floatFromInt(allow_val)) / 1_000_000.0;

        std.debug.print("\n账户状态:\n", .{});
        std.debug.print("  余额:     ${d:.2} USDC\n", .{bal_usdc});
        std.debug.print("  Allowance: ${d:.2} USDC\n", .{allow_usdc});
        std.debug.print("  最大仓位: ${d:.2}\n", .{config.max_position});

        if (allow_val == 0) {
            std.debug.print("\n⚠️  Allowance 为 0！下单可能失败\n", .{});
        }

        if (bal_usdc < config.max_order_size) {
            std.debug.print("\n⚠️  余额不足\n", .{});
            // 清理已分配的资源
            if (creds) |*c| c.deinit();
            client.deinit();
            return error.InsufficientBalance;
        }

        std.debug.print("\n", .{});
    } else {
        client = ClobClient.init(allocator, client_config);
    }
    defer client.deinit();
    defer if (creds) |*c| c.deinit();

    // 创建机器人
    var bot = HedgeArbitrageBot.init(
        allocator,
        &client,
        if (wallet) |*w| w else null,
        config,
    );
    defer bot.deinit();

    // 运行
    try bot.run();
}
