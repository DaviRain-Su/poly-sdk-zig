//! BTC 15分钟市场订单簿监控工具
//!
//! 功能：
//! - 自动检测当前活跃的 BTC 15分钟涨跌市场
//! - 实时显示 Up (YES) 和 Down (NO) 两边的订单簿
//! - 显示买卖盘深度、最佳价格、价差等信息
//! - 持续刷新，直到市场结束
//!
//! 运行: zig build run-btc_orderbook_monitor
//!
//! 配置（.env 文件）：
//! - POLY_PRIVATE_KEY: 钱包私钥（可选，用于显示钱包地址）

const std = @import("std");
const poly = @import("poly_sdk_zig");

const ClobClient = poly.ClobClient;
const Wallet = poly.Wallet;
const Decimal = poly.Decimal;

// ============================================================================
// 配置
// ============================================================================

const Config = struct {
    /// 刷新间隔（秒）
    refresh_interval_sec: u64 = 2,

    /// 显示的订单簿深度（每边显示多少档）
    orderbook_depth: usize = 10,

    /// 是否使用测试网
    use_testnet: bool = false,
};

// ============================================================================
// 市场信息
// ============================================================================

const MarketInfo = struct {
    condition_id_buf: [128]u8 = undefined,
    condition_id_len: usize = 0,
    yes_token_id_buf: [128]u8 = undefined,
    yes_token_id_len: usize = 0,
    no_token_id_buf: [128]u8 = undefined,
    no_token_id_len: usize = 0,
    slug_buf: [64]u8 = undefined,
    slug_len: usize = 0,
    end_timestamp: i64,
    remaining_seconds: i64,

    pub fn getConditionId(self: *const MarketInfo) []const u8 {
        return self.condition_id_buf[0..self.condition_id_len];
    }

    pub fn getYesTokenId(self: *const MarketInfo) []const u8 {
        return self.yes_token_id_buf[0..self.yes_token_id_len];
    }

    pub fn getNoTokenId(self: *const MarketInfo) []const u8 {
        return self.no_token_id_buf[0..self.no_token_id_len];
    }

    pub fn getSlug(self: *const MarketInfo) []const u8 {
        return self.slug_buf[0..self.slug_len];
    }

    pub fn getRemainingMinutes(self: *const MarketInfo) i64 {
        return @divFloor(self.remaining_seconds, 60);
    }

    pub fn getRemainingSecondsRemainder(self: *const MarketInfo) i64 {
        return @mod(self.remaining_seconds, 60);
    }
};

// ============================================================================
// 辅助函数
// ============================================================================

fn log(comptime fmt: []const u8, args: anytype) void {
    const timestamp = std.time.timestamp();
    std.debug.print("[{d}] " ++ fmt ++ "\n", .{timestamp} ++ args);
}

fn isBtc15mMarket(slug: []const u8) bool {
    return std.mem.indexOf(u8, slug, "btc-") != null and
        std.mem.indexOf(u8, slug, "-15m-") != null;
}

fn parseTimestampFromSlug(slug: []const u8) i64 {
    // 格式: btc-updown-15m-1767238200
    var it = std.mem.splitBackwardsSequence(u8, slug, "-");
    if (it.next()) |ts_str| {
        return std.fmt.parseInt(i64, ts_str, 10) catch 0;
    }
    return 0;
}

fn getNextMarketTime() i64 {
    const now = std.time.timestamp();
    // 15分钟 = 900秒
    const interval: i64 = 900;
    // 下一个15分钟整点
    return (@divFloor(now, interval) + 1) * interval;
}

fn formatTimeUntil(seconds: i64) struct { mins: i64, secs: i64 } {
    return .{
        .mins = @divFloor(seconds, 60),
        .secs = @mod(seconds, 60),
    };
}

fn toLower(input: []const u8) [64]u8 {
    var result: [64]u8 = undefined;
    const len = @min(input.len, 64);
    for (0..len) |i| {
        result[i] = std.ascii.toLower(input[i]);
    }
    for (len..64) |i| {
        result[i] = 0;
    }
    return result;
}

fn parsePrice(price_str: []const u8) f64 {
    return std.fmt.parseFloat(f64, price_str) catch 0.0;
}

fn parseSize(size_str: []const u8) f64 {
    return std.fmt.parseFloat(f64, size_str) catch 0.0;
}

// ============================================================================
// 订单簿显示
// ============================================================================

const OrderBookDisplay = struct {
    allocator: std.mem.Allocator,
    config: Config,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: Config) Self {
        return .{
            .allocator = allocator,
            .config = config,
        };
    }

    /// 打印单个订单簿
    pub fn printOrderBook(
        self: *Self,
        name: []const u8,
        book: *const poly.clob.types.OrderBookSummary,
    ) void {
        _ = self;

        // 标题
        std.debug.print("\n", .{});
        std.debug.print("══════════════════════ {s} ══════════════════════\n", .{name});

        // 获取 bids 和 asks
        const bids = book.bids orelse &[_]poly.clob.types.OrderSummary{};
        const asks = book.asks orelse &[_]poly.clob.types.OrderSummary{};

        // 计算最佳价格
        const best_bid = if (bids.len > 0) parsePrice(bids[0].price) else 0.0;
        const best_ask = if (asks.len > 0) parsePrice(asks[0].price) else 0.0;
        const spread = if (best_bid > 0 and best_ask > 0) best_ask - best_bid else 0.0;
        const mid_price = if (best_bid > 0 and best_ask > 0) (best_bid + best_ask) / 2.0 else 0.0;

        // 计算总深度
        var total_bid_size: f64 = 0.0;
        for (bids) |bid| {
            total_bid_size += parseSize(bid.size);
        }

        var total_ask_size: f64 = 0.0;
        for (asks) |ask| {
            total_ask_size += parseSize(ask.size);
        }

        // 打印摘要
        std.debug.print("  最佳买价: {d:.4}  |  最佳卖价: {d:.4}  |  价差: {d:.4}\n", .{ best_bid, best_ask, spread });
        std.debug.print("  中间价: {d:.4}  |  买盘深度: {d:.2}  |  卖盘深度: {d:.2}\n", .{ mid_price, total_bid_size, total_ask_size });
        std.debug.print("\n", .{});

        // 打印表头
        std.debug.print("     BID SIZE     BID PRICE  |   ASK PRICE    ASK SIZE\n", .{});
        std.debug.print("  ------------ ------------ | ------------ ------------\n", .{});

        // 打印订单簿
        const max_rows = 10;
        for (0..max_rows) |i| {
            const bid_price = if (i < bids.len) bids[i].price else "      -";
            const bid_size = if (i < bids.len) bids[i].size else "      -";
            const ask_price = if (i < asks.len) asks[i].price else "      -";
            const ask_size = if (i < asks.len) asks[i].size else "      -";

            std.debug.print("  {s:>12} {s:>12} | {s:<12} {s:<12}\n", .{ bid_size, bid_price, ask_price, ask_size });
        }

        if (bids.len > max_rows or asks.len > max_rows) {
            std.debug.print("  ... 更多 ({d} 买单, {d} 卖单)\n", .{ bids.len, asks.len });
        }
    }

    /// 打印双边订单簿对比
    pub fn printDualOrderBooks(
        self: *Self,
        market: MarketInfo,
        up_book: *const poly.clob.types.OrderBookSummary,
        down_book: *const poly.clob.types.OrderBookSummary,
    ) void {
        // 清屏
        std.debug.print("\x1B[2J\x1B[H", .{});

        const now = std.time.timestamp();
        const remaining = market.end_timestamp - now;
        const mins = @divFloor(remaining, 60);
        const secs = @mod(remaining, 60);

        // 标题
        std.debug.print("\n", .{});
        std.debug.print("╔══════════════════════════════════════════════════════════════════════════════╗\n", .{});
        std.debug.print("║          BTC 15分钟市场订单簿监控 - Polymarket                               ║\n", .{});
        std.debug.print("╠══════════════════════════════════════════════════════════════════════════════╣\n", .{});
        std.debug.print("║  市场: {s:<68} ║\n", .{market.getSlug()});
        std.debug.print("║  剩余时间: {d:>2} 分 {d:>2} 秒                                                       ║\n", .{ mins, secs });
        std.debug.print("╚══════════════════════════════════════════════════════════════════════════════╝\n", .{});

        // 获取价格信息
        const up_bids = up_book.bids orelse &[_]poly.clob.types.OrderSummary{};
        const up_asks = up_book.asks orelse &[_]poly.clob.types.OrderSummary{};
        const down_bids = down_book.bids orelse &[_]poly.clob.types.OrderSummary{};
        const down_asks = down_book.asks orelse &[_]poly.clob.types.OrderSummary{};

        const up_best_bid = if (up_bids.len > 0) parsePrice(up_bids[0].price) else 0.0;
        const up_best_ask = if (up_asks.len > 0) parsePrice(up_asks[0].price) else 0.0;
        const down_best_bid = if (down_bids.len > 0) parsePrice(down_bids[0].price) else 0.0;
        const down_best_ask = if (down_asks.len > 0) parsePrice(down_asks[0].price) else 0.0;

        // 计算隐含概率
        const up_mid = if (up_best_bid > 0 and up_best_ask > 0) (up_best_bid + up_best_ask) / 2.0 else 0.0;
        const down_mid = if (down_best_bid > 0 and down_best_ask > 0) (down_best_bid + down_best_ask) / 2.0 else 0.0;

        // 价格摘要
        std.debug.print("\n", .{});
        std.debug.print("┌─────────────────────────────────────┬─────────────────────────────────────┐\n", .{});
        std.debug.print("│            🟢 UP (涨)               │            🔴 DOWN (跌)             │\n", .{});
        std.debug.print("├─────────────────────────────────────┼─────────────────────────────────────┤\n", .{});
        std.debug.print("│  买价: {d:.4}  卖价: {d:.4}          │  买价: {d:.4}  卖价: {d:.4}          │\n", .{ up_best_bid, up_best_ask, down_best_bid, down_best_ask });
        std.debug.print("│  中间价: {d:.4}  ({d:.1}%)            │  中间价: {d:.4}  ({d:.1}%)            │\n", .{ up_mid, up_mid * 100, down_mid, down_mid * 100 });
        std.debug.print("└─────────────────────────────────────┴─────────────────────────────────────┘\n", .{});

        // 市场健康状态检查
        const up_spread = if (up_best_ask > up_best_bid) up_best_ask - up_best_bid else 0.0;
        const down_spread = if (down_best_ask > down_best_bid) down_best_ask - down_best_bid else 0.0;

        std.debug.print("\n", .{});

        // 检查价差是否过大
        if (up_spread > 0.5 or down_spread > 0.5) {
            std.debug.print("  ⚠️  警告: 价差过大! UP价差: {d:.2}, DOWN价差: {d:.2}\n", .{ up_spread, down_spread });
            std.debug.print("  ⚠️  市场流动性不足，不建议交易\n", .{});
        } else if (up_spread > 0.2 or down_spread > 0.2) {
            std.debug.print("  ⚡ 注意: 价差较大 (UP: {d:.2}, DOWN: {d:.2})，交易需谨慎\n", .{ up_spread, down_spread });
        } else {
            std.debug.print("  ✅ 市场健康: 价差正常 (UP: {d:.4}, DOWN: {d:.4})\n", .{ up_spread, down_spread });
        }

        // 套利机会检测
        const total_mid = up_mid + down_mid;
        if (total_mid > 0) {
            if (total_mid < 0.98) {
                std.debug.print("  💰 套利机会! UP + DOWN = {d:.4} < 1.00 (买入两边可套利)\n", .{total_mid});
            } else if (total_mid > 1.02) {
                std.debug.print("  💰 套利机会! UP + DOWN = {d:.4} > 1.00 (卖出两边可套利)\n", .{total_mid});
            } else {
                std.debug.print("  📊 UP + DOWN = {d:.4} (正常范围)\n", .{total_mid});
            }
        }

        // 打印订单簿详情
        self.printOrderBook("🟢 UP (BTC 涨)", up_book);
        self.printOrderBook("🔴 DOWN (BTC 跌)", down_book);

        // 底部信息
        std.debug.print("\n", .{});
        std.debug.print("─────────────────────────────────────────────────────────────────────────────────\n", .{});
        std.debug.print("  刷新间隔: {d}秒  |  按 Ctrl+C 退出\n", .{self.config.refresh_interval_sec});
        std.debug.print("─────────────────────────────────────────────────────────────────────────────────\n", .{});
    }
};

fn printLine(char: []const u8, count: usize) void {
    for (0..count) |_| {
        std.debug.print("{s}", .{char});
    }
}

// ============================================================================
// 主监控器
// ============================================================================

const OrderBookMonitor = struct {
    allocator: std.mem.Allocator,
    client: *ClobClient,
    config: Config,
    display: OrderBookDisplay,
    running: bool = true,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, client: *ClobClient, config: Config) Self {
        return .{
            .allocator = allocator,
            .client = client,
            .config = config,
            .display = OrderBookDisplay.init(allocator, config),
        };
    }

    /// 寻找 BTC 15m 市场 (使用 Gamma API)
    /// 市场 slug 格式是 btc-updown-15m-{开始时间戳}
    pub fn findBtc15mMarket(self: *Self) !?MarketInfo {
        const now = std.time.timestamp();

        // 计算时间戳
        const interval: i64 = 900; // 15 分钟
        const current_slot = @divFloor(now, interval) * interval;
        const next_slot = current_slot + interval;

        // 优先选择正在进行的市场
        const slots = [_]i64{ current_slot, next_slot };

        for (slots) |slot| {
            // 构建 market slug: btc-updown-15m-{开始时间戳}
            var slug_buf: [64]u8 = undefined;
            const slug = std.fmt.bufPrint(&slug_buf, "btc-updown-15m-{d}", .{slot}) catch continue;

            // 使用 Gamma API 查询市场
            if (self.fetchMarketFromGamma(slug)) |market_info| {
                const remaining = market_info.end_timestamp - now;

                // 检查市场是否还有时间
                if (remaining <= 0) {
                    continue;
                }

                std.debug.print("[{d}] 找到活跃市场: {s}，剩余 {d} 分钟 {d} 秒\n", .{
                    now,
                    slug,
                    @divFloor(remaining, 60),
                    @mod(remaining, 60),
                });
                return market_info;
            } else |_| {
                continue;
            }
        }

        return null;
    }

    /// 从 Gamma API 获取市场信息
    fn fetchMarketFromGamma(self: *Self, slug: []const u8) !MarketInfo {
        // 构建 Gamma API URL
        var url_buf: [256]u8 = undefined;
        const url = std.fmt.bufPrint(&url_buf, "https://gamma-api.polymarket.com/events?slug={s}", .{slug}) catch return error.BufferTooSmall;

        // 使用 curl 获取数据
        const argv: []const []const u8 = &.{
            "curl",
            "-s",
            "-f",
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

        // 解析 JSON 响应
        return self.parseGammaResponse(response.items, slug);
    }

    /// 解析 Gamma API 响应
    fn parseGammaResponse(self: *Self, json_data: []const u8, slug: []const u8) !MarketInfo {
        _ = self;

        // 简单解析 JSON 来提取需要的字段
        // clobTokenIds 是一个 JSON 字符串: "clobTokenIds":"[\"token1\", \"token2\"]"
        // 需要找到 "clobTokenIds":"[\" 然后解析
        const clob_tokens_start = std.mem.indexOf(u8, json_data, "\"clobTokenIds\":\"[\\\"") orelse return error.TokensNotFound;
        const tokens_data = json_data[clob_tokens_start + 19 ..]; // skip "clobTokenIds":"[\"

        // 提取第一个 token (Up) - 结束于 \"
        const first_token_end = std.mem.indexOf(u8, tokens_data, "\\\"") orelse return error.ParseError;
        const up_token = tokens_data[0..first_token_end];

        // 提取第二个 token (Down) - 跳过 \", \" 然后找下一个 \"
        const rest = tokens_data[first_token_end + 6 ..]; // skip \", \"
        const second_token_end = std.mem.indexOf(u8, rest, "\\\"") orelse return error.ParseError;
        const down_token = rest[0..second_token_end];

        // 提取 conditionId
        const condition_start = std.mem.indexOf(u8, json_data, "\"conditionId\":\"") orelse return error.ConditionNotFound;
        const condition_data = json_data[condition_start + 15 ..];
        const condition_end = std.mem.indexOf(u8, condition_data, "\"") orelse return error.ParseError;
        const condition_id = condition_data[0..condition_end];

        // 从 slug 解析开始时间戳，然后计算结束时间
        const start_timestamp = parseTimestampFromSlug(slug);
        if (start_timestamp == 0) return error.InvalidTimestamp;
        const end_timestamp = start_timestamp + 900; // 15分钟后结束

        const now = std.time.timestamp();
        const remaining = end_timestamp - now;

        // 创建 MarketInfo 并复制字符串到内部缓冲区
        var info = MarketInfo{
            .end_timestamp = end_timestamp,
            .remaining_seconds = remaining,
        };

        // 复制 condition_id
        if (condition_id.len > info.condition_id_buf.len) return error.BufferTooSmall;
        @memcpy(info.condition_id_buf[0..condition_id.len], condition_id);
        info.condition_id_len = condition_id.len;

        // 复制 up_token
        if (up_token.len > info.yes_token_id_buf.len) return error.BufferTooSmall;
        @memcpy(info.yes_token_id_buf[0..up_token.len], up_token);
        info.yes_token_id_len = up_token.len;

        // 复制 down_token
        if (down_token.len > info.no_token_id_buf.len) return error.BufferTooSmall;
        @memcpy(info.no_token_id_buf[0..down_token.len], down_token);
        info.no_token_id_len = down_token.len;

        // 复制 slug
        if (slug.len > info.slug_buf.len) return error.BufferTooSmall;
        @memcpy(info.slug_buf[0..slug.len], slug);
        info.slug_len = slug.len;

        return info;
    }

    /// 运行监控
    pub fn run(self: *Self) !void {
        std.debug.print("\n", .{});
        std.debug.print("╔══════════════════════════════════════════════════════════════╗\n", .{});
        std.debug.print("║     BTC 15分钟市场订单簿监控工具 - Polymarket                 ║\n", .{});
        std.debug.print("╚══════════════════════════════════════════════════════════════╝\n", .{});
        std.debug.print("\n", .{});

        while (self.running) {
            // 寻找市场
            const market_opt = try self.findBtc15mMarket();

            if (market_opt) |market| {
                // 监控这个市场直到结束
                try self.monitorMarket(market);
            } else {
                const now = std.time.timestamp();
                const next_market = getNextMarketTime();
                const time_until = formatTimeUntil(next_market - now);

                std.debug.print("\x1B[2J\x1B[H", .{}); // 清屏
                std.debug.print("\n", .{});
                std.debug.print("╔══════════════════════════════════════════════════════════════╗\n", .{});
                std.debug.print("║     BTC 15分钟市场订单簿监控工具 - Polymarket                 ║\n", .{});
                std.debug.print("╚══════════════════════════════════════════════════════════════╝\n", .{});
                std.debug.print("\n", .{});
                std.debug.print("  状态: 等待新市场创建...\n", .{});
                std.debug.print("\n", .{});
                std.debug.print("  下一个市场预计时间: 每15分钟整点 (xx:00, xx:15, xx:30, xx:45)\n", .{});
                std.debug.print("  预计等待: {d} 分 {d} 秒\n", .{ time_until.mins, time_until.secs });
                std.debug.print("\n", .{});
                std.debug.print("  提示: 市场创建后会自动开始监控订单簿\n", .{});
                std.debug.print("\n", .{});
                std.Thread.sleep(3 * std.time.ns_per_s);
            }
        }
    }

    /// 监控单个市场
    fn monitorMarket(self: *Self, market: MarketInfo) !void {
        log("开始监控市场: {s}", .{market.getSlug()});
        log("UP Token: {s}", .{market.getYesTokenId()});
        log("DOWN Token: {s}", .{market.getNoTokenId()});

        while (self.running) {
            const now = std.time.timestamp();
            const remaining = market.end_timestamp - now;

            if (remaining <= 0) {
                std.debug.print("\n市场已结束，寻找下一个市场...\n", .{});
                break;
            }

            // 获取订单簿
            const up_book = self.client.getOrderBook(market.getYesTokenId()) catch |err| {
                log("获取 UP 订单簿失败: {}", .{err});
                std.Thread.sleep(self.config.refresh_interval_sec * std.time.ns_per_s);
                continue;
            };
            defer up_book.deinit();

            const down_book = self.client.getOrderBook(market.getNoTokenId()) catch |err| {
                log("获取 DOWN 订单簿失败: {}", .{err});
                std.Thread.sleep(self.config.refresh_interval_sec * std.time.ns_per_s);
                continue;
            };
            defer down_book.deinit();

            // 更新市场信息
            var updated_market = market;
            updated_market.remaining_seconds = remaining;

            // 显示订单簿
            self.display.printDualOrderBooks(updated_market, &up_book.value, &down_book.value);

            // 等待下一次刷新
            std.Thread.sleep(self.config.refresh_interval_sec * std.time.ns_per_s);
        }
    }
};

// ============================================================================
// 入口
// ============================================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 加载配置
    const config = Config{};

    // 初始化客户端
    var client = ClobClient.init(allocator, .{
        .base_url = if (config.use_testnet)
            "https://clob.polymarket.com" // 测试网暂时也用主网
        else
            "https://clob.polymarket.com",
    });
    defer client.deinit();

    // 尝试加载钱包（用于显示地址）
    if (std.process.getEnvVarOwned(allocator, "POLY_PRIVATE_KEY")) |pk| {
        defer allocator.free(pk);
        if (Wallet.fromPrivateKeyHex(pk)) |wallet| {
            std.debug.print("钱包地址: {s}\n", .{wallet.getAddressChecksumHex()});
        } else |_| {}
    } else |_| {}

    // 创建监控器
    var monitor = OrderBookMonitor.init(allocator, &client, config);

    // 运行
    try monitor.run();
}
