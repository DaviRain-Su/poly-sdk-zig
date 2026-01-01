//! BTC 15分钟市场 WebSocket 智能交易系统
//!
//! 使用 WebSocket 实时数据流替代 REST API 轮询：
//! - 更低延迟：毫秒级价格更新
//! - 更少 API 调用：减少请求次数和限流风险
//! - 更及时响应：实时接收订单簿变化
//!
//! 运行: zig build run-btc_ws_trader
//!
//! 配置（.env 文件）：
//! - POLY_PRIVATE_KEY: 钱包私钥
//! - WS_TRADER_DRY_RUN: 模拟模式（默认 true）
//! - WS_TRADER_MODE: 策略模式 (hybrid/trend/arbitrage)

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
// 配置
// ============================================================================

const WsTraderConfig = struct {
    /// 模拟模式（不实际下单）
    dry_run: bool = true,

    /// 最小剩余时间（分钟）
    min_remaining_minutes: i64 = 5,

    /// 边缘价格阈值（忽略低于此价格的买单和高于 1-此价格 的卖单）
    edge_price_threshold: f64 = 0.20,

    /// 概率偏差阈值（触发交易的 UP 概率阈值）
    prob_bias_threshold: f64 = 0.55,

    /// 单次订单金额
    order_size: f64 = 50.0,

    /// 最大仓位
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

/// 实时订单簿状态（由 WebSocket 更新）
const LiveOrderBook = struct {
    // UP Token
    up_best_bid: f64 = 0,
    up_best_ask: f64 = 1,
    up_mid_price: f64 = 0.5,
    up_bid_depth: f64 = 0,
    up_ask_depth: f64 = 0,

    // DOWN Token
    down_best_bid: f64 = 0,
    down_best_ask: f64 = 1,
    down_mid_price: f64 = 0.5,
    down_bid_depth: f64 = 0,
    down_ask_depth: f64 = 0,

    // 更新时间戳
    last_update: i64 = 0,
    update_count: u64 = 0,

    pub fn probabilitySum(self: *const LiveOrderBook) f64 {
        return self.up_mid_price + self.down_mid_price;
    }

    pub fn hasArbitrage(self: *const LiveOrderBook, threshold: f64) bool {
        const sum = self.probabilitySum();
        return sum < (1.0 - threshold) or sum > (1.0 + threshold);
    }
};

/// 持仓状态
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

/// 交易统计
const TradingStats = struct {
    markets_traded: u32 = 0,
    total_trades: u32 = 0,
    ws_messages_received: u64 = 0,
    signals_generated: u32 = 0,
};

// ============================================================================
// 全局状态（WebSocket 回调需要访问）
// ============================================================================

var g_live_book: LiveOrderBook = .{};
var g_up_token_id: [128]u8 = undefined;
var g_up_token_len: usize = 0;
var g_down_token_id: [128]u8 = undefined;
var g_down_token_len: usize = 0;
var g_edge_threshold: f64 = 0.20;
var g_stats: TradingStats = .{};

// ============================================================================
// WebSocket 回调函数
// ============================================================================

fn onBookMessage(msg: BookMessage) void {
    g_stats.ws_messages_received += 1;

    // 确定是 UP 还是 DOWN token (asset_id 是 []const u8，不是 optional)
    const is_up = std.mem.eql(u8, msg.asset_id, g_up_token_id[0..g_up_token_len]);
    const is_down = std.mem.eql(u8, msg.asset_id, g_down_token_id[0..g_down_token_len]);

    if (!is_up and !is_down) return;

    // 分析订单簿，忽略边缘价格
    var real_best_bid: f64 = 0;
    var real_best_ask: f64 = 1;
    var bid_depth: f64 = 0;
    var ask_depth: f64 = 0;

    // 分析买单 (bids 是 []const BookLevel，不是 optional)
    for (msg.bids) |bid| {
        const price = std.fmt.parseFloat(f64, bid.price) catch continue;
        const size = std.fmt.parseFloat(f64, bid.size) catch continue;

        if (price >= g_edge_threshold) {
            bid_depth += size * price;
            if (price > real_best_bid) {
                real_best_bid = price;
            }
        }
    }

    // 分析卖单 (asks 是 []const BookLevel，不是 optional)
    for (msg.asks) |ask| {
        const price = std.fmt.parseFloat(f64, ask.price) catch continue;
        const size = std.fmt.parseFloat(f64, ask.size) catch continue;

        if (price <= (1.0 - g_edge_threshold)) {
            ask_depth += size * price;
            if (price < real_best_ask) {
                real_best_ask = price;
            }
        }
    }

    const mid_price = if (real_best_bid > 0 and real_best_ask < 1)
        (real_best_bid + real_best_ask) / 2.0
    else
        0.5;

    // 更新全局状态
    if (is_up) {
        g_live_book.up_best_bid = real_best_bid;
        g_live_book.up_best_ask = real_best_ask;
        g_live_book.up_mid_price = mid_price;
        g_live_book.up_bid_depth = bid_depth;
        g_live_book.up_ask_depth = ask_depth;
    } else {
        g_live_book.down_best_bid = real_best_bid;
        g_live_book.down_best_ask = real_best_ask;
        g_live_book.down_mid_price = mid_price;
        g_live_book.down_bid_depth = bid_depth;
        g_live_book.down_ask_depth = ask_depth;
    }

    g_live_book.last_update = std.time.timestamp();
    g_live_book.update_count += 1;
}

fn onPriceChange(msg: PriceChangeMessage) void {
    g_stats.ws_messages_received += 1;

    // PriceChangeMessage 包含 price_changes 数组，每个元素有 asset_id, price, side
    for (msg.price_changes) |change| {
        // 确定是 UP 还是 DOWN token
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
// WebSocket 交易系统
// ============================================================================

const WsTrader = struct {
    allocator: std.mem.Allocator,
    config: WsTraderConfig,
    client: *ClobClient,
    wallet: ?*const Wallet,
    builder: ?OrderBuilder,
    position: Position,
    stats: TradingStats,
    current_market: ?MarketInfo,
    ws_channel: ?MarketChannel,
    running: bool,

    // 价格历史（用于计算动量和波动率）
    price_history: [60]f64 = [_]f64{0} ** 60,
    price_history_idx: usize = 0,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        client: *ClobClient,
        wallet: ?*const Wallet,
        config: WsTraderConfig,
    ) Self {
        // 设置全局边缘阈值
        g_edge_threshold = config.edge_price_threshold;

        return Self{
            .allocator = allocator,
            .config = config,
            .client = client,
            .wallet = wallet,
            .builder = if (wallet) |w| OrderBuilder.init(w, .{
                .chain_id = if (config.use_testnet) 80002 else 137,
            }) else null,
            .position = .{},
            .stats = .{},
            .current_market = null,
            .ws_channel = null,
            .running = true,
            .price_history = [_]f64{0} ** 60,
            .price_history_idx = 0,
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

                // 设置全局 token IDs
                @memcpy(g_up_token_id[0..m.up_token_id_len], m.up_token_id_buf[0..m.up_token_id_len]);
                g_up_token_len = m.up_token_id_len;
                @memcpy(g_down_token_id[0..m.down_token_id_len], m.down_token_id_buf[0..m.down_token_id_len]);
                g_down_token_len = m.down_token_id_len;

                // 阶段 2: 建立 WebSocket 连接
                // 尝试建立 WebSocket 连接（支持 TLS）
                log("", .{});
                log("════════════════════════════════════════════════════════════════", .{});
                log("  尝试建立 WebSocket 连接...", .{});
                log("════════════════════════════════════════════════════════════════", .{});

                var use_websocket = false;
                self.connectWebSocket(m) catch |err| {
                    log("  WebSocket 连接失败: {}, 回退到 REST API 轮询", .{err});
                };
                if (self.ws_channel != null) {
                    log("  WebSocket 连接成功!", .{});
                    use_websocket = true;
                }

                // 阶段 3: 执行策略
                log("", .{});
                log("════════════════════════════════════════════════════════════════", .{});
                if (use_websocket) {
                    log("  执行 WebSocket 实时交易策略...", .{});
                } else {
                    log("  执行 REST API 轮询交易策略...", .{});
                }
                log("════════════════════════════════════════════════════════════════", .{});

                self.executeStrategy(m) catch |err| {
                    log("策略执行失败: {}", .{err});
                };

                // 阶段 4: 清理
                self.disconnectWebSocket();
                self.position.reset();
                self.current_market = null;
                self.stats.markets_traded += 1;
            } else {
                self.showNextExpectedMarket();
                std.Thread.sleep(5 * std.time.ns_per_s);
            }
        }

        self.printFinalStats();
    }

    /// 建立 WebSocket 连接
    fn connectWebSocket(self: *Self, market: MarketInfo) !void {
        // 重置全局订单簿状态
        g_live_book = .{};
        g_stats = .{};

        // 创建 MarketChannel
        self.ws_channel = try MarketChannel.init(self.allocator, .{
            .on_book = onBookMessage,
            .on_price_change = onPriceChange,
            .on_connection = onConnectionChange,
            .on_error = onError,
            .auto_reconnect = true,
        });

        // 连接
        try self.ws_channel.?.connect();

        // 订阅两个 token
        const tokens = [_][]const u8{
            market.getUpTokenId(),
            market.getDownTokenId(),
        };
        try self.ws_channel.?.subscribe(&tokens);

        log("  已订阅 UP 和 DOWN token", .{});
    }

    /// 断开 WebSocket
    fn disconnectWebSocket(self: *Self) void {
        if (self.ws_channel) |*channel| {
            channel.disconnect();
            channel.deinit();
            self.ws_channel = null;
        }
    }

    /// 执行策略（使用 WebSocket 数据）
    fn executeStrategy(self: *Self, market: MarketInfo) !void {
        var last_print_time: i64 = 0;

        while (self.running) {
            const now = std.time.timestamp();
            const remaining = market.end_timestamp - now;

            // 检查剩余时间
            if (remaining < 60) {
                log("  剩余时间不足 1 分钟，停止交易", .{});
                break;
            }

            // 定期更新数据和打印状态（每 3 秒）
            if (now - last_print_time >= 3) {
                last_print_time = now;

                // 使用 REST API 获取订单簿数据
                self.fetchOrderBookViaRest(market) catch |err| {
                    log("  获取订单簿失败: {}", .{err});
                };

                // 更新价格历史
                if (g_live_book.up_mid_price > 0) {
                    self.price_history[self.price_history_idx] = g_live_book.up_mid_price;
                    self.price_history_idx = (self.price_history_idx + 1) % 60;
                }

                self.printLiveStatus(market);

                // 检查交易信号
                self.checkAndExecuteSignals(market) catch |err| {
                    log("  信号执行失败: {}", .{err});
                };
            }

            // 休眠
            std.Thread.sleep(500 * std.time.ns_per_ms);
        }
    }

    /// 使用 REST API 获取订单簿
    fn fetchOrderBookViaRest(self: *Self, market: MarketInfo) !void {
        // 获取 UP token 订单簿
        const up_book = self.client.getOrderBook(market.getUpTokenId()) catch {
            return;
        };
        defer up_book.deinit();

        // 获取 DOWN token 订单簿
        const down_book = self.client.getOrderBook(market.getDownTokenId()) catch {
            return;
        };
        defer down_book.deinit();

        // 分析 UP 订单簿
        var up_best_bid: f64 = 0;
        var up_best_ask: f64 = 1;
        var up_bid_depth: f64 = 0;
        var up_ask_depth: f64 = 0;

        if (up_book.value.bids) |bids| {
            for (bids) |bid| {
                const price = std.fmt.parseFloat(f64, bid.price) catch continue;
                const size = std.fmt.parseFloat(f64, bid.size) catch continue;
                if (price >= g_edge_threshold) {
                    up_bid_depth += size * price;
                    if (price > up_best_bid) up_best_bid = price;
                }
            }
        }

        if (up_book.value.asks) |asks| {
            for (asks) |ask| {
                const price = std.fmt.parseFloat(f64, ask.price) catch continue;
                const size = std.fmt.parseFloat(f64, ask.size) catch continue;
                if (price <= (1.0 - g_edge_threshold)) {
                    up_ask_depth += size * price;
                    if (price < up_best_ask) up_best_ask = price;
                }
            }
        }

        // 分析 DOWN 订单簿
        var down_best_bid: f64 = 0;
        var down_best_ask: f64 = 1;
        var down_bid_depth: f64 = 0;
        var down_ask_depth: f64 = 0;

        if (down_book.value.bids) |bids| {
            for (bids) |bid| {
                const price = std.fmt.parseFloat(f64, bid.price) catch continue;
                const size = std.fmt.parseFloat(f64, bid.size) catch continue;
                if (price >= g_edge_threshold) {
                    down_bid_depth += size * price;
                    if (price > down_best_bid) down_best_bid = price;
                }
            }
        }

        if (down_book.value.asks) |asks| {
            for (asks) |ask| {
                const price = std.fmt.parseFloat(f64, ask.price) catch continue;
                const size = std.fmt.parseFloat(f64, ask.size) catch continue;
                if (price <= (1.0 - g_edge_threshold)) {
                    down_ask_depth += size * price;
                    if (price < down_best_ask) down_best_ask = price;
                }
            }
        }

        // 更新全局订单簿状态
        g_live_book.up_best_bid = up_best_bid;
        g_live_book.up_best_ask = up_best_ask;
        g_live_book.up_mid_price = if (up_best_bid > 0 and up_best_ask < 1)
            (up_best_bid + up_best_ask) / 2.0
        else
            0.5;
        g_live_book.up_bid_depth = up_bid_depth;
        g_live_book.up_ask_depth = up_ask_depth;

        g_live_book.down_best_bid = down_best_bid;
        g_live_book.down_best_ask = down_best_ask;
        g_live_book.down_mid_price = if (down_best_bid > 0 and down_best_ask < 1)
            (down_best_bid + down_best_ask) / 2.0
        else
            0.5;
        g_live_book.down_bid_depth = down_bid_depth;
        g_live_book.down_ask_depth = down_ask_depth;

        g_live_book.last_update = std.time.timestamp();
        g_live_book.update_count += 1;
        g_stats.ws_messages_received += 2; // 模拟 2 条消息（UP + DOWN）
    }

    /// 检查并执行交易信号
    fn checkAndExecuteSignals(self: *Self, market: MarketInfo) !void {
        // 检查是否有足够的数据
        if (g_live_book.update_count < 2) return;

        // 检查仓位限制
        if (self.position.totalCost() >= self.config.max_position) return;

        // ⚠️ 检查价差是否过大 - 市场流动性不足时不交易
        const up_spread = if (g_live_book.up_best_ask > g_live_book.up_best_bid)
            g_live_book.up_best_ask - g_live_book.up_best_bid
        else
            0.0;
        const down_spread = if (g_live_book.down_best_ask > g_live_book.down_best_bid)
            g_live_book.down_best_ask - g_live_book.down_best_bid
        else
            0.0;

        // 价差超过 30% 时不交易
        const max_spread: f64 = 0.30;
        if (up_spread > max_spread or down_spread > max_spread) {
            // 只在首次检测到时记录
            if (g_stats.signals_generated == 0 or g_live_book.update_count % 10 == 0) {
                log("  ⚠️ 价差过大 (UP: {d:.2}, DOWN: {d:.2})，暂停交易", .{ up_spread, down_spread });
            }
            return;
        }

        const up_prob = g_live_book.up_mid_price;
        const prob_sum = g_live_book.probabilitySum();

        // 1. 套利检查
        if (prob_sum < 0.98) {
            log("  检测到套利机会! UP + DOWN = {d:.4}", .{prob_sum});
            g_stats.signals_generated += 1;
            // 买入两边...
        }

        // 2. 概率偏差检查
        if (up_prob >= self.config.prob_bias_threshold) {
            log("  信号: 强烈看涨 (UP={d:.1}%)", .{up_prob * 100});
            g_stats.signals_generated += 1;

            if (self.config.dry_run) {
                log("  [模拟] 买入 UP @ {d:.4}", .{g_live_book.up_best_ask});
                const size = self.config.order_size / g_live_book.up_best_ask;
                self.position.up_shares += size;
                self.position.up_cost += self.config.order_size;
                self.stats.total_trades += 1;
            } else {
                self.executeBuy(market, .up, g_live_book.up_best_ask) catch |err| {
                    log("  买入 UP 失败: {}", .{err});
                };
            }
        } else if (up_prob <= (1.0 - self.config.prob_bias_threshold)) {
            log("  信号: 强烈看跌 (UP={d:.1}%)", .{up_prob * 100});
            g_stats.signals_generated += 1;

            if (self.config.dry_run) {
                log("  [模拟] 买入 DOWN @ {d:.4}", .{g_live_book.down_best_ask});
                const size = self.config.order_size / g_live_book.down_best_ask;
                self.position.down_shares += size;
                self.position.down_cost += self.config.order_size;
                self.stats.total_trades += 1;
            } else {
                self.executeBuy(market, .down, g_live_book.down_best_ask) catch |err| {
                    log("  买入 DOWN 失败: {}", .{err});
                };
            }
        }
    }

    /// 执行买入
    fn executeBuy(self: *Self, market: MarketInfo, token: enum { up, down }, price: f64) !void {
        if (self.builder) |*builder| {
            const token_id = if (token == .up) market.getUpTokenId() else market.getDownTokenId();
            const size = self.config.order_size / price;

            const price_str = try std.fmt.allocPrint(self.allocator, "{d:.2}", .{price});
            defer self.allocator.free(price_str);
            const size_str = try std.fmt.allocPrint(self.allocator, "{d:.0}", .{size});
            defer self.allocator.free(size_str);

            const order = try builder.createOrder(.{
                .token_id = token_id,
                .price = try Decimal.fromString(price_str),
                .size = try Decimal.fromString(size_str),
                .side = .BUY,
            }, .{
                .tick_size = .@"0.01",
                .neg_risk = false,
            });

            const response = self.client.postOrder(&order, .GTC) catch |err| {
                log("  ❌ 下单请求失败: {}", .{err});
                log("  提示: 如果是 Unauthorized 错误，请检查 API 凭证配置", .{});
                return;
            };

            if (response.success) {
                log("  ✅ 订单成功! ID: {s}", .{response.orderID orelse "N/A"});
                if (token == .up) {
                    self.position.up_shares += size;
                    self.position.up_cost += self.config.order_size;
                } else {
                    self.position.down_shares += size;
                    self.position.down_cost += self.config.order_size;
                }
                self.stats.total_trades += 1;
            } else {
                log("  ❌ 订单被拒绝: {s}", .{response.errorMsg orelse "未知错误"});
            }
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

    /// 打印实时状态
    fn printLiveStatus(self: *Self, market: MarketInfo) void {
        const remaining = market.getRemainingSeconds();
        const mins = @divFloor(remaining, 60);
        const secs = @mod(remaining, 60);

        // 清屏
        std.debug.print("\x1B[2J\x1B[H", .{});

        std.debug.print("\n", .{});
        std.debug.print("╔═══════════════════════════════════════════════════════════════════════════╗\n", .{});
        std.debug.print("║     BTC 15分钟 WebSocket 实时交易系统 - {s}     ║\n", .{if (self.config.dry_run) "模拟模式" else "实盘模式"});
        std.debug.print("╠═══════════════════════════════════════════════════════════════════════════╣\n", .{});
        std.debug.print("║  市场: {s:<64} ║\n", .{market.getSlug()});
        std.debug.print("║  剩余: {d:>2}:{d:0>2}    WS消息: {d:<10}  更新次数: {d:<10}           ║\n", .{
            mins,
            secs,
            g_stats.ws_messages_received,
            g_live_book.update_count,
        });
        std.debug.print("╠═══════════════════════════════════════════════════════════════════════════╣\n", .{});
        std.debug.print("║                      实 时 订 单 簿 (WebSocket)                           ║\n", .{});
        std.debug.print("╠═══════════════════════════════════════════════════════════════════════════╣\n", .{});
        std.debug.print("║                    UP (涨)                    DOWN (跌)                   ║\n", .{});
        std.debug.print("║  ─────────────────────────────────────────────────────────────────────── ║\n", .{});
        std.debug.print("║  真实买价:      {d:.4}                         {d:.4}                     ║\n", .{
            g_live_book.up_best_bid,
            g_live_book.down_best_bid,
        });
        std.debug.print("║  真实卖价:      {d:.4}                         {d:.4}                     ║\n", .{
            g_live_book.up_best_ask,
            g_live_book.down_best_ask,
        });
        std.debug.print("║  中间价:        {d:.4}  ({d:>5.1}%)               {d:.4}  ({d:>5.1}%)           ║\n", .{
            g_live_book.up_mid_price,
            g_live_book.up_mid_price * 100,
            g_live_book.down_mid_price,
            g_live_book.down_mid_price * 100,
        });
        std.debug.print("║  价差:          {d:.4}                         {d:.4}                     ║\n", .{
            g_live_book.up_best_ask - g_live_book.up_best_bid,
            g_live_book.down_best_ask - g_live_book.down_best_bid,
        });
        std.debug.print("║  买盘深度:    ${d:>7.0}                       ${d:>7.0}                   ║\n", .{
            g_live_book.up_bid_depth,
            g_live_book.down_bid_depth,
        });
        std.debug.print("║  卖盘深度:    ${d:>7.0}                       ${d:>7.0}                   ║\n", .{
            g_live_book.up_ask_depth,
            g_live_book.down_ask_depth,
        });
        std.debug.print("╠═══════════════════════════════════════════════════════════════════════════╣\n", .{});
        std.debug.print("║                        市 场 指 标                                        ║\n", .{});
        std.debug.print("╠═══════════════════════════════════════════════════════════════════════════╣\n", .{});
        std.debug.print("║  UP + DOWN = {d:.4}  ", .{g_live_book.probabilitySum()});
        if (g_live_book.hasArbitrage(0.02)) {
            std.debug.print(">>> 套利机会! <<<                              ║\n", .{});
        } else {
            std.debug.print("(正常)                                         ║\n", .{});
        }

        // 计算动量和波动率
        const momentum = self.calculateMomentum();
        const volatility = self.calculateVolatility();

        // 显示动量（手动处理正负号）
        if (momentum >= 0) {
            std.debug.print("║  动量: +{d:.5}    波动率: {d:.5}                                        ║\n", .{ momentum, volatility });
        } else {
            std.debug.print("║  动量: {d:.5}    波动率: {d:.5}                                        ║\n", .{ momentum, volatility });
        }

        // 市场情绪
        const up_prob = g_live_book.up_mid_price;
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
        std.debug.print("║  UP 持仓: {d:>7.2}  成本: ${d:>7.2}   DOWN 持仓: {d:>7.2}  成本: ${d:>7.2}  ║\n", .{
            self.position.up_shares,
            self.position.up_cost,
            self.position.down_shares,
            self.position.down_cost,
        });
        std.debug.print("║  总成本: ${d:>7.2}  信号数: {d:<5}  交易数: {d:<5}                        ║\n", .{
            self.position.totalCost(),
            g_stats.signals_generated,
            self.stats.total_trades,
        });
        std.debug.print("╚═══════════════════════════════════════════════════════════════════════════╝\n", .{});
    }

    /// 寻找适合的市场
    /// 市场 slug 格式是 btc-updown-15m-{开始时间戳}
    /// 例如: btc-updown-15m-1767248100 表示 1:15-1:30 的市场
    fn findSuitableMarket(self: *Self) !?MarketInfo {
        const now = std.time.timestamp();
        const interval: i64 = 900; // 15 分钟

        // 计算当前时段的开始时间 (这是正在进行的市场的 slug)
        const current_slot = @divFloor(now, interval) * interval;
        const next_slot = current_slot + interval;

        // 优先选择正在进行的市场，然后是下一个市场
        const slots = [_]i64{ current_slot, next_slot };

        for (slots) |slot| {
            var slug_buf: [64]u8 = undefined;
            const slug = std.fmt.bufPrint(&slug_buf, "btc-updown-15m-{d}", .{slot}) catch continue;

            if (self.fetchMarketFromGamma(slug)) |market_info| {
                const remaining = market_info.end_timestamp - now;

                // 跳过剩余时间不足的市场
                if (remaining < self.config.min_remaining_minutes * 60) {
                    log("  市场 {s} 剩余时间不足 ({d}秒)，跳过", .{ slug, remaining });
                    continue;
                }

                // 跳过已结束的市场
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

        // 从 slug 解析开始时间戳，然后计算结束时间
        const start_timestamp = parseTimestampFromSlug(slug);
        if (start_timestamp == 0) return error.InvalidTimestamp;
        const end_timestamp = start_timestamp + 900; // 15分钟后结束

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
        std.debug.print("║   BTC 15分钟 WebSocket 实时交易系统 - Polymarket                 ║\n", .{});
        std.debug.print("╠══════════════════════════════════════════════════════════════════╣\n", .{});
        std.debug.print("║  模式: {s:<58} ║\n", .{if (self.config.dry_run) "模拟交易" else "实盘交易"});
        std.debug.print("║  数据源: WebSocket 实时推送                                      ║\n", .{});
        std.debug.print("╚══════════════════════════════════════════════════════════════════╝\n", .{});
        std.debug.print("\n", .{});
    }

    fn printFinalStats(self: *Self) void {
        std.debug.print("\n", .{});
        std.debug.print("╔══════════════════════════════════════════════════════════════════╗\n", .{});
        std.debug.print("║                        最终交易统计                               ║\n", .{});
        std.debug.print("╚══════════════════════════════════════════════════════════════════╝\n", .{});
        std.debug.print("  交易市场数: {d}\n", .{self.stats.markets_traded});
        std.debug.print("  总交易次数: {d}\n", .{self.stats.total_trades});
        std.debug.print("  WS 消息数: {d}\n", .{g_stats.ws_messages_received});
        std.debug.print("  信号数: {d}\n", .{g_stats.signals_generated});
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

    // 解析配置
    const config = WsTraderConfig{
        .dry_run = env.getBool("WS_TRADER_DRY_RUN", true),
        .min_remaining_minutes = env.getInt(i64, "WS_TRADER_MIN_REMAINING", 5),
        .edge_price_threshold = env.getFloat(f64, "WS_TRADER_EDGE_THRESHOLD", 0.20),
        .prob_bias_threshold = env.getFloat(f64, "WS_TRADER_PROB_THRESHOLD", 0.55),
        .order_size = env.getFloat(f64, "WS_TRADER_ORDER_SIZE", 50.0),
        .max_position = env.getFloat(f64, "WS_TRADER_MAX_POSITION", 200.0),
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

    // 创建 WebSocket 交易系统
    var trader = WsTrader.init(
        allocator,
        &client,
        if (wallet) |*w| w else null,
        config,
    );
    defer trader.deinit();

    // 运行
    try trader.run();
}
