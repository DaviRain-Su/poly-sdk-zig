//! BTC 15分钟市场智能自动交易系统
//!
//! 策略：概率偏差交易
//! - 当 UP 概率 >= 阈值时买入 UP（看涨）
//! - 当 UP 概率 <= (1-阈值) 时买入 DOWN（看跌）
//! - 检测套利机会：当 UP + DOWN 偏离 1.00 时
//!
//! 运行: zig build run-smart_auto_trade
//!
//! 配置（.env 文件）：
//! - POLY_PRIVATE_KEY: 钱包私钥
//! - SMART_TRADER_DRY_RUN: 模拟模式（默认 true）
//! - SMART_TRADER_PROB_THRESHOLD: 概率偏差阈值（默认 0.55）
//! - SMART_TRADER_ORDER_SIZE: 单次订单金额（默认 5.0）

const std = @import("std");
const poly = @import("poly_sdk_zig");

const ClobClient = poly.ClobClient;
const Wallet = poly.Wallet;
const Decimal = poly.Decimal;
const ApiCreds = poly.ApiCreds;
const OrderBuilder = poly.OrderBuilder;
const SignatureType = poly.order.types.SignatureType;

// ============================================================================
// 配置
// ============================================================================

const SmartTraderConfig = struct {
    /// 模拟模式（不实际下单）
    dry_run: bool = true,

    /// 最小剩余时间（分钟）
    min_remaining_minutes: i64 = 3,

    /// 边缘价格阈值（忽略低于此价格的买单和高于 1-此价格 的卖单）
    edge_price_threshold: f64 = 0.15,

    /// 概率偏差阈值（触发交易的 UP 概率阈值）
    prob_bias_threshold: f64 = 0.55,

    /// 单次订单金额
    order_size: f64 = 5.0,

    /// 最大仓位
    max_position: f64 = 50.0,

    /// 最大价差（超过此价差不交易）
    max_spread: f64 = 0.15,

    /// 是否使用测试网
    use_testnet: bool = false,

    /// 签名类型
    signature_type: SignatureType = .POLY_GNOSIS_SAFE,

    /// Funder/Proxy 地址
    funder: ?[20]u8 = null,
};

// ============================================================================
// 市场信息
// ============================================================================

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

// ============================================================================
// 实时订单簿状态
// ============================================================================

const LiveOrderBook = struct {
    // UP Token
    up_best_bid: f64 = 0,
    up_best_ask: f64 = 1,
    up_mid_price: f64 = 0.5,

    // DOWN Token
    down_best_bid: f64 = 0,
    down_best_ask: f64 = 1,
    down_mid_price: f64 = 0.5,

    // 更新时间戳
    last_update: i64 = 0,
    update_count: u64 = 0,

    pub fn upPrice(self: *const LiveOrderBook) f64 {
        return self.up_mid_price;
    }

    pub fn downPrice(self: *const LiveOrderBook) f64 {
        return self.down_mid_price;
    }

    pub fn probabilitySum(self: *const LiveOrderBook) f64 {
        return self.up_mid_price + self.down_mid_price;
    }

    pub fn hasArbitrage(self: *const LiveOrderBook, threshold: f64) bool {
        const sum = self.probabilitySum();
        return sum < (1.0 - threshold) or sum > (1.0 + threshold);
    }
};

// ============================================================================
// 持仓状态
// ============================================================================

const Position = struct {
    up_shares: f64 = 0,
    up_cost: f64 = 0,
    down_shares: f64 = 0,
    down_cost: f64 = 0,

    pub fn totalCost(self: *const Position) f64 {
        return self.up_cost + self.down_cost;
    }

    pub fn reset(self: *Position) void {
        self.up_shares = 0;
        self.up_cost = 0;
        self.down_shares = 0;
        self.down_cost = 0;
    }
};

// ============================================================================
// 交易统计
// ============================================================================

const TradingStats = struct {
    markets_traded: u32 = 0,
    total_trades: u32 = 0,
    up_buys: u32 = 0,
    down_buys: u32 = 0,
    signals_generated: u32 = 0,
};

// ============================================================================
// 全局状态
// ============================================================================

var g_live_book: LiveOrderBook = .{};
var g_edge_threshold: f64 = 0.15;

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
    running: bool,

    // 价格历史
    price_history: [60]f64 = [_]f64{0} ** 60,
    price_idx: usize = 0,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        client: *ClobClient,
        wallet: ?*const Wallet,
        config: SmartTraderConfig,
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
            .position = .{},
            .stats = .{},
            .running = true,
        };
    }

    pub fn deinit(self: *Self) void {
        self.running = false;
        g_live_book = .{};
    }

    pub fn run(self: *Self) !void {
        self.printBanner();

        while (self.running) {
            log("", .{});
            log("════════════════════════════════════════════════════════════════", .{});
            log("  寻找 BTC 15分钟市场...", .{});
            log("════════════════════════════════════════════════════════════════", .{});

            if (try self.findSuitableMarket()) |market| {
                log("", .{});
                log("  找到市场: {s}", .{market.getSlug()});
                log("  UP Token: {s}...", .{market.getUpTokenId()[0..@min(20, market.up_token_id_len)]});
                log("  DOWN Token: {s}...", .{market.getDownTokenId()[0..@min(20, market.down_token_id_len)]});

                // 执行策略
                try self.executeStrategy(market);

                // 清理
                self.position.reset();
                self.stats.markets_traded += 1;
            } else {
                self.showWaitingStatus();
                std.Thread.sleep(10 * std.time.ns_per_s);
            }
        }

        self.printFinalStats();
    }

    /// 执行策略
    fn executeStrategy(self: *Self, market: MarketInfo) !void {
        var last_print_time: i64 = 0;

        // 先获取一次初始数据
        self.fetchOrderBook(market) catch {};

        while (self.running) {
            const now = std.time.timestamp();
            const remaining = market.end_timestamp - now;

            // 检查剩余时间
            if (remaining < 30) {
                log("  剩余时间不足 30 秒，停止交易", .{});
                break;
            }

            // 获取订单簿数据
            self.fetchOrderBook(market) catch |err| {
                log("  获取订单簿失败: {}", .{err});
                std.Thread.sleep(1 * std.time.ns_per_s);
                continue;
            };

            // 更新价格历史
            if (g_live_book.up_mid_price > 0) {
                self.price_history[self.price_idx] = g_live_book.up_mid_price;
                self.price_idx = (self.price_idx + 1) % 60;
            }

            // 定期打印状态（每 2 秒）
            if (now - last_print_time >= 2) {
                last_print_time = now;
                self.printLiveStatus(market);
            }

            // 检查并执行交易信号
            try self.checkAndExecuteSignals(market);

            // 休眠
            std.Thread.sleep(500 * std.time.ns_per_ms);
        }
    }

    /// 获取订单簿
    fn fetchOrderBook(self: *Self, market: MarketInfo) !void {
        const up_book = self.client.getOrderBook(market.getUpTokenId()) catch return;
        defer up_book.deinit();

        const down_book = self.client.getOrderBook(market.getDownTokenId()) catch return;
        defer down_book.deinit();

        // 分析 UP 订单簿
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

        // 分析 DOWN 订单簿
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
        g_live_book.up_mid_price = if (up_best_bid > 0 and up_best_ask < 1)
            (up_best_bid + up_best_ask) / 2.0
        else
            0.5;

        g_live_book.down_best_bid = down_best_bid;
        g_live_book.down_best_ask = down_best_ask;
        g_live_book.down_mid_price = if (down_best_bid > 0 and down_best_ask < 1)
            (down_best_bid + down_best_ask) / 2.0
        else
            0.5;

        g_live_book.last_update = std.time.timestamp();
        g_live_book.update_count += 1;
    }

    /// 检查并执行交易信号
    fn checkAndExecuteSignals(self: *Self, market: MarketInfo) !void {
        // 检查是否有足够的数据
        if (g_live_book.update_count < 2) return;

        // 检查仓位限制
        if (self.position.totalCost() >= self.config.max_position) return;

        // 检查价差
        const up_spread = g_live_book.up_best_ask - g_live_book.up_best_bid;
        const down_spread = g_live_book.down_best_ask - g_live_book.down_best_bid;

        if (up_spread > self.config.max_spread or down_spread > self.config.max_spread) {
            return; // 价差过大，不交易
        }

        const up_prob = g_live_book.up_mid_price;
        const prob_sum = g_live_book.probabilitySum();

        // 1. 套利检查
        if (prob_sum < 0.98) {
            log("  💰 套利机会! UP + DOWN = {d:.4}", .{prob_sum});
            self.stats.signals_generated += 1;
        }

        // 2. 概率偏差检查 - 看涨
        if (up_prob >= self.config.prob_bias_threshold) {
            log("  📈 信号: 强烈看涨 (UP={d:.1}%)", .{up_prob * 100});
            self.stats.signals_generated += 1;

            try self.executeBuy(market, .up);
        }
        // 3. 概率偏差检查 - 看跌
        else if (up_prob <= (1.0 - self.config.prob_bias_threshold)) {
            log("  📉 信号: 强烈看跌 (UP={d:.1}%)", .{up_prob * 100});
            self.stats.signals_generated += 1;

            try self.executeBuy(market, .down);
        }
    }

    /// 执行买入
    fn executeBuy(self: *Self, market: MarketInfo, side: enum { up, down }) !void {
        const token_id = if (side == .up) market.getUpTokenId() else market.getDownTokenId();
        const buy_price = if (side == .up) g_live_book.up_best_ask else g_live_book.down_best_ask;

        // 计算股数
        var shares = self.config.order_size / buy_price;

        // 确保订单金额 >= $1
        const actual_amount = shares * buy_price;
        if (actual_amount < 1.0) {
            shares = @ceil(1.0 / buy_price);
        }

        const int_shares: u64 = @intFromFloat(@ceil(shares));
        const final_amount = @as(f64, @floatFromInt(int_shares)) * buy_price;

        log("  📈 买入 {s}: {d} 股 @ {d:.4}, 金额: ${d:.2}", .{
            if (side == .up) "UP" else "DOWN",
            int_shares,
            buy_price,
            final_amount,
        });

        if (self.config.dry_run) {
            // 模拟模式
            if (side == .up) {
                self.position.up_shares += @as(f64, @floatFromInt(int_shares));
                self.position.up_cost += final_amount;
                self.stats.up_buys += 1;
            } else {
                self.position.down_shares += @as(f64, @floatFromInt(int_shares));
                self.position.down_cost += final_amount;
                self.stats.down_buys += 1;
            }
            self.stats.total_trades += 1;
            log("  ✅ [模拟] 买入成功!", .{});
        } else {
            // 实盘下单
            if (self.builder) |*builder| {
                const price_str = try std.fmt.allocPrint(self.allocator, "{d:.2}", .{buy_price});
                defer self.allocator.free(price_str);
                const size_str = try std.fmt.allocPrint(self.allocator, "{d}", .{int_shares});
                defer self.allocator.free(size_str);

                const order = try builder.createOrder(.{
                    .token_id = token_id,
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
                    std.Thread.sleep(3 * std.time.ns_per_s);
                    return;
                };

                if (response.success) {
                    if (side == .up) {
                        self.position.up_shares += @as(f64, @floatFromInt(int_shares));
                        self.position.up_cost += final_amount;
                        self.stats.up_buys += 1;
                    } else {
                        self.position.down_shares += @as(f64, @floatFromInt(int_shares));
                        self.position.down_cost += final_amount;
                        self.stats.down_buys += 1;
                    }
                    self.stats.total_trades += 1;
                    log("  ✅ 订单成功!", .{});
                } else {
                    log("  ❌ 订单被拒绝", .{});
                    std.Thread.sleep(3 * std.time.ns_per_s);
                }
            }
        }
    }

    /// 打印实时状态
    fn printLiveStatus(self: *Self, market: MarketInfo) void {
        const remaining = market.getRemainingSeconds();
        const mins = @divFloor(remaining, 60);
        const secs = @mod(remaining, 60);

        // 清屏
        std.debug.print("\x1B[2J\x1B[H", .{});

        std.debug.print("\n", .{});
        std.debug.print("╔═══════════════════════════════════════════════════════════════════════════╗\n", .{});
        std.debug.print("║     BTC 15分钟 智能概率交易系统 - {s}     ║\n", .{if (self.config.dry_run) "模拟模式" else "实盘模式"});
        std.debug.print("╠═══════════════════════════════════════════════════════════════════════════╣\n", .{});
        std.debug.print("║  市场: {s:<64} ║\n", .{market.getSlug()});
        std.debug.print("║  剩余: {d:>2}:{d:0>2}    更新: {d} 次                                          ║\n", .{
            mins,
            secs,
            g_live_book.update_count,
        });

        std.debug.print("╠═══════════════════════════════════════════════════════════════════════════╣\n", .{});
        std.debug.print("║                          概 率 监 控                                      ║\n", .{});
        std.debug.print("╠═══════════════════════════════════════════════════════════════════════════╣\n", .{});

        const up_prob = g_live_book.up_mid_price;
        const down_prob = g_live_book.down_mid_price;
        const prob_sum = g_live_book.probabilitySum();

        std.debug.print("║  UP 概率:   {d:.2}%   (买: {d:.4}, 卖: {d:.4})                            ║\n", .{
            up_prob * 100,
            g_live_book.up_best_bid,
            g_live_book.up_best_ask,
        });
        std.debug.print("║  DOWN 概率: {d:.2}%   (买: {d:.4}, 卖: {d:.4})                            ║\n", .{
            down_prob * 100,
            g_live_book.down_best_bid,
            g_live_book.down_best_ask,
        });
        std.debug.print("║  概率和:    {d:.4}                                                        ║\n", .{prob_sum});

        // 市场情绪
        std.debug.print("║  市场情绪: ", .{});
        if (up_prob >= 0.60) {
            std.debug.print("🚀 极度看涨                                                ║\n", .{});
        } else if (up_prob >= self.config.prob_bias_threshold) {
            std.debug.print("📈 看涨 (触发买入 UP)                                      ║\n", .{});
        } else if (up_prob <= 0.40) {
            std.debug.print("💥 极度看跌                                                ║\n", .{});
        } else if (up_prob <= (1.0 - self.config.prob_bias_threshold)) {
            std.debug.print("📉 看跌 (触发买入 DOWN)                                    ║\n", .{});
        } else {
            std.debug.print("➡️  中性                                                   ║\n", .{});
        }

        std.debug.print("╠═══════════════════════════════════════════════════════════════════════════╣\n", .{});
        std.debug.print("║                          仓 位 状 态                                      ║\n", .{});
        std.debug.print("╠═══════════════════════════════════════════════════════════════════════════╣\n", .{});
        std.debug.print("║  UP 持仓:   {d:>7.2} 股   成本: ${d:>7.2}                                 ║\n", .{
            self.position.up_shares,
            self.position.up_cost,
        });
        std.debug.print("║  DOWN 持仓: {d:>7.2} 股   成本: ${d:>7.2}                                 ║\n", .{
            self.position.down_shares,
            self.position.down_cost,
        });
        std.debug.print("║  总成本:    ${d:>7.2}   交易: {d} 次   信号: {d} 次                       ║\n", .{
            self.position.totalCost(),
            self.stats.total_trades,
            self.stats.signals_generated,
        });

        std.debug.print("╠═══════════════════════════════════════════════════════════════════════════╣\n", .{});
        std.debug.print("║  阈值: prob={d:.2}  spread={d:.2}  orderSize=${d:.0}                       ║\n", .{
            self.config.prob_bias_threshold,
            self.config.max_spread,
            self.config.order_size,
        });
        std.debug.print("╚═══════════════════════════════════════════════════════════════════════════╝\n", .{});

        // 套利检测
        if (g_live_book.hasArbitrage(0.02)) {
            std.debug.print("\n  💰 套利机会! UP + DOWN = {d:.4}\n", .{prob_sum});
        }
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

        const argv: []const []const u8 = &.{
            "curl",
            "-s",
            "-f",
            "--retry",
            "3",
            url,
        };

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

    fn showWaitingStatus(self: *Self) void {
        _ = self;
        const now = std.time.timestamp();
        const interval: i64 = 900;
        const next_slot = (@divFloor(now, interval) + 1) * interval;
        const wait_seconds = next_slot - now;

        std.debug.print("\x1B[2J\x1B[H", .{});
        std.debug.print("\n", .{});
        std.debug.print("╔═══════════════════════════════════════════════════════════════╗\n", .{});
        std.debug.print("║     BTC 15分钟 智能概率交易系统                                ║\n", .{});
        std.debug.print("╠═══════════════════════════════════════════════════════════════╣\n", .{});
        std.debug.print("║  状态: 等待新市场创建...                                       ║\n", .{});
        std.debug.print("║  预计等待: {d} 分 {d} 秒                                        ║\n", .{
            @divFloor(wait_seconds, 60),
            @mod(wait_seconds, 60),
        });
        std.debug.print("╚═══════════════════════════════════════════════════════════════╝\n", .{});
    }

    fn printBanner(self: *Self) void {
        std.debug.print("\n", .{});
        std.debug.print("╔══════════════════════════════════════════════════════════════════╗\n", .{});
        std.debug.print("║   BTC 15分钟 智能概率交易系统 - Polymarket                        ║\n", .{});
        std.debug.print("╠══════════════════════════════════════════════════════════════════╣\n", .{});
        std.debug.print("║  模式: {s:<58} ║\n", .{if (self.config.dry_run) "模拟交易" else "实盘交易"});
        std.debug.print("║  策略: 概率偏差交易 (阈值: {d:.0}%)                                ║\n", .{self.config.prob_bias_threshold * 100});
        std.debug.print("╚══════════════════════════════════════════════════════════════════╝\n", .{});
    }

    fn printFinalStats(self: *Self) void {
        std.debug.print("\n", .{});
        std.debug.print("╔══════════════════════════════════════════════════════════════════╗\n", .{});
        std.debug.print("║                        最终交易统计                               ║\n", .{});
        std.debug.print("╚══════════════════════════════════════════════════════════════════╝\n", .{});
        std.debug.print("  交易市场数: {d}\n", .{self.stats.markets_traded});
        std.debug.print("  总交易次数: {d}\n", .{self.stats.total_trades});
        std.debug.print("  UP 买入: {d} 次\n", .{self.stats.up_buys});
        std.debug.print("  DOWN 买入: {d} 次\n", .{self.stats.down_buys});
        std.debug.print("  信号数: {d}\n", .{self.stats.signals_generated});
    }

    pub fn stop(self: *Self) void {
        self.running = false;
    }
};

// ============================================================================
// 辅助函数
// ============================================================================

fn parseTimestampFromSlug(slug: []const u8) i64 {
    var it = std.mem.splitBackwardsSequence(u8, slug, "-");
    if (it.next()) |ts_str| {
        return std.fmt.parseInt(i64, ts_str, 10) catch 0;
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
        result[i] = std.fmt.parseInt(u8, clean[i * 2 .. i * 2 + 2], 16) catch return null;
    }
    return result;
}

// ============================================================================
// 入口
// ============================================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 加载环境变量
    var env = poly.loadEnvOrEmpty(allocator, ".env");
    defer env.deinit();

    // 解析签名类型
    const sig_type_val = env.getInt(u8, "SMART_TRADER_SIGNATURE_TYPE", 2);
    const signature_type = SignatureType.fromU8(sig_type_val) orelse .POLY_GNOSIS_SAFE;

    // 解析 funder 地址
    var funder: ?[20]u8 = null;
    if (env.get("POLY_FUNDER_ADDRESS") orelse env.get("POLY_ADDRESS")) |funder_hex| {
        funder = parseFunderAddress(funder_hex);
    }

    // 解析配置
    const config = SmartTraderConfig{
        .dry_run = env.getBool("SMART_TRADER_DRY_RUN", true),
        .min_remaining_minutes = env.getInt(i64, "SMART_TRADER_MIN_REMAINING", 3),
        .edge_price_threshold = env.getFloat(f64, "SMART_TRADER_EDGE_THRESHOLD", 0.15),
        .prob_bias_threshold = env.getFloat(f64, "SMART_TRADER_PROB_THRESHOLD", 0.55),
        .order_size = env.getFloat(f64, "SMART_TRADER_ORDER_SIZE", 5.0),
        .max_position = env.getFloat(f64, "SMART_TRADER_MAX_POSITION", 50.0),
        .max_spread = env.getFloat(f64, "SMART_TRADER_MAX_SPREAD", 0.15),
        .use_testnet = env.getBool("POLY_USE_TESTNET", false),
        .signature_type = signature_type,
        .funder = funder,
    };

    // 初始化客户端配置
    const client_config = poly.clob.client.Config{
        .base_url = if (config.use_testnet) poly.clob.client.BASE_URL_TESTNET else poly.clob.client.BASE_URL_MAINNET,
    };

    // 初始化钱包和客户端
    var wallet: ?Wallet = null;
    var client: ClobClient = undefined;
    var creds: ?ApiCreds = null;

    if (env.get("POLY_PRIVATE_KEY")) |pk| {
        wallet = Wallet.fromPrivateKeyHex(pk) catch |err| {
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
        if (!config.dry_run) {
            const bal_result = client.getBalanceAllowance(.{
                .asset_type = .COLLATERAL,
                .signature_type = @intFromEnum(config.signature_type),
            }) catch |err| {
                std.debug.print("查询余额失败: {}\n", .{err});
                if (creds) |*c| c.deinit();
                client.deinit();
                return err;
            };
            defer bal_result.deinit();

            const bal_str = bal_result.value.balance orelse "0";
            const bal_val = std.fmt.parseInt(u64, bal_str, 10) catch 0;
            const bal_usdc = @as(f64, @floatFromInt(bal_val)) / 1_000_000.0;

            std.debug.print("\n账户余额: ${d:.2} USDC\n", .{bal_usdc});

            if (bal_usdc < config.order_size) {
                std.debug.print("\n⚠️  余额不足\n", .{});
                if (creds) |*c| c.deinit();
                client.deinit();
                return error.InsufficientBalance;
            }
        }

        std.debug.print("\n", .{});
    } else {
        client = ClobClient.init(allocator, client_config);
    }
    defer client.deinit();
    defer if (creds) |*c| c.deinit();

    // 创建交易系统
    var trader = SmartTrader.init(
        allocator,
        &client,
        if (wallet) |*w| w else null,
        config,
    );
    defer trader.deinit();

    // 运行
    try trader.run();
}
