//! Split/Merge 套利机器人
//!
//! 利用 Polymarket 的 Split/Merge 机制进行无风险套利：
//!
//! 1. Split 套利：当 YES_ask + NO_ask > $1 时
//!    - 用 $1 Split 成 1 YES + 1 NO
//!    - 卖出 YES 和 NO
//!    - 收入 > $1，净赚价差
//!
//! 2. Merge 套利：当 YES_ask + NO_ask < $1 时
//!    - 买入 YES 和 NO
//!    - Merge 成 $1
//!    - 净赚价差
//!
//! 运行：zig build run-split_merge_arb
//!
//! 配置（.env）:
//!   POLY_PRIVATE_KEY=your_private_key
//!   ARB_DRY_RUN=true              # 模拟模式
//!   ARB_MIN_PROFIT=0.02           # 最小利润阈值（$）
//!   ARB_ORDER_SIZE=10             # 每次套利金额（$）
//!   ARB_RPC_URL=https://polygon-rpc.com

const std = @import("std");
const poly = @import("poly_sdk_zig");

const ClobClient = poly.ClobClient;
const Wallet = poly.Wallet;
const OrderBuilder = poly.OrderBuilder;
const Decimal = poly.Decimal;
const CtfClient = poly.CtfClient;

// ============================================================================
// 全局状态
// ============================================================================

var g_live_book: LiveOrderBook = .{};

const LiveOrderBook = struct {
    up_best_bid: f64 = 0,
    up_best_ask: f64 = 1,
    down_best_bid: f64 = 0,
    down_best_ask: f64 = 1,
    last_update: i64 = 0,
};

// ============================================================================
// 配置
// ============================================================================

const ArbConfig = struct {
    dry_run: bool = true,
    min_profit: f64 = 0.02, // 最小利润 2%
    order_size: f64 = 10.0, // 每次套利 $10
    rpc_url: []const u8 = "https://polygon-rpc.com",
    use_testnet: bool = false,
    // Split/Merge 套利必须使用 EOA 模式！
    // 因为 CTF 链上操作和 CLOB 卖单都需要使用同一个钱包
    signature_type: poly.SignatureType = .EOA,
    funder: ?[20]u8 = null,
};

// ============================================================================
// 市场信息
// ============================================================================

const MarketInfo = struct {
    slug_buf: [128]u8 = undefined,
    slug_len: usize = 0,
    condition_id_buf: [128]u8 = undefined,
    condition_id_len: usize = 0,
    up_token_id_buf: [128]u8 = undefined,
    up_token_id_len: usize = 0,
    down_token_id_buf: [128]u8 = undefined,
    down_token_id_len: usize = 0,
    end_time: i64 = 0,

    pub fn getSlug(self: *const MarketInfo) []const u8 {
        return self.slug_buf[0..self.slug_len];
    }

    pub fn getConditionId(self: *const MarketInfo) []const u8 {
        return self.condition_id_buf[0..self.condition_id_len];
    }

    pub fn getUpTokenId(self: *const MarketInfo) []const u8 {
        return self.up_token_id_buf[0..self.up_token_id_len];
    }

    pub fn getDownTokenId(self: *const MarketInfo) []const u8 {
        return self.down_token_id_buf[0..self.down_token_id_len];
    }
};

// ============================================================================
// 套利机会
// ============================================================================

const ArbOpportunity = struct {
    arb_type: ArbType,
    expected_profit: f64,
    yes_price: f64,
    no_price: f64,
    total_price: f64,
    shares: f64,

    const ArbType = enum {
        split_and_sell, // YES + NO > $1，Split 后卖出
        buy_and_merge, // YES + NO < $1，买入后 Merge
        none,
    };
};

// ============================================================================
// 套利机器人
// ============================================================================

const SplitMergeArbBot = struct {
    allocator: std.mem.Allocator,
    config: ArbConfig,
    client: *ClobClient,
    wallet: ?*const Wallet,
    builder: ?OrderBuilder,
    ctf_client: ?CtfClient,

    // 统计
    total_profit: f64 = 0,
    total_trades: u32 = 0,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        client: *ClobClient,
        wallet: ?*const Wallet,
        config: ArbConfig,
    ) Self {
        return Self{
            .allocator = allocator,
            .config = config,
            .client = client,
            .wallet = wallet,
            .builder = if (wallet) |w| OrderBuilder.init(w, .{
                .chain_id = if (config.use_testnet) 80002 else 137,
                .funder = config.funder,
            }) else null,
            .ctf_client = if (wallet) |w| CtfClient.init(allocator, w, .{
                .rpc_url = config.rpc_url,
                .chain_id = if (config.use_testnet) 80002 else 137,
            }) else null,
        };
    }

    /// 运行套利循环
    pub fn run(self: *Self, market: MarketInfo) !void {
        log("", .{});
        log("========================================", .{});
        log("  Split/Merge 套利机器人", .{});
        log("========================================", .{});
        log("  市场: {s}", .{market.getSlug()});
        log("  模式: {s}", .{if (self.config.dry_run) "模拟" else "实盘"});
        log("  最小利润: ${d:.2}", .{self.config.min_profit});
        log("  每次金额: ${d:.2}", .{self.config.order_size});
        log("========================================", .{});
        log("", .{});

        while (true) {
            // 检查市场是否已结束
            const now = std.time.timestamp();
            if (now >= market.end_time) {
                log("市场已结束", .{});
                break;
            }

            // 获取订单簿
            try self.fetchOrderBook(market);

            // 分析套利机会
            const opportunity = self.analyzeOpportunity();

            // 打印状态
            self.printStatus(market, opportunity);

            // 执行套利
            if (opportunity.arb_type != .none and opportunity.expected_profit >= self.config.min_profit) {
                try self.executeArbitrage(market, opportunity);
            }

            // 休眠
            std.Thread.sleep(1 * std.time.ns_per_s);
        }
    }

    /// 分析套利机会
    fn analyzeOpportunity(self: *Self) ArbOpportunity {
        const yes_ask = g_live_book.up_best_ask;
        const no_ask = g_live_book.down_best_ask;
        const yes_bid = g_live_book.up_best_bid;
        const no_bid = g_live_book.down_best_bid;

        // 检查数据有效性
        if (yes_ask <= 0 or no_ask <= 0 or yes_bid <= 0 or no_bid <= 0) {
            return .{
                .arb_type = .none,
                .expected_profit = 0,
                .yes_price = 0,
                .no_price = 0,
                .total_price = 0,
                .shares = 0,
            };
        }

        // 安全检查：价格应该在 0-1 之间
        if (yes_ask > 1.0 or yes_bid > 1.0 or no_ask > 1.0 or no_bid > 1.0) {
            return .{
                .arb_type = .none,
                .expected_profit = 0,
                .yes_price = 0,
                .no_price = 0,
                .total_price = 0,
                .shares = 0,
            };
        }

        // 安全检查：bid 应该小于等于 ask（正常市场规则）
        if (yes_bid > yes_ask or no_bid > no_ask) {
            // 订单簿数据异常，跳过
            return .{
                .arb_type = .none,
                .expected_profit = 0,
                .yes_price = 0,
                .no_price = 0,
                .total_price = 0,
                .shares = 0,
            };
        }

        const shares = self.config.order_size;

        // 检查 Split 套利机会：YES_bid + NO_bid > $1
        // Split $1 得到 1 YES + 1 NO，然后以 bid 价卖出
        const sell_total = yes_bid + no_bid;
        if (sell_total > 1.0) {
            const profit_per_share = sell_total - 1.0;
            const total_profit = profit_per_share * shares;
            return .{
                .arb_type = .split_and_sell,
                .expected_profit = total_profit,
                .yes_price = yes_bid,
                .no_price = no_bid,
                .total_price = sell_total,
                .shares = shares,
            };
        }

        // 检查 Merge 套利机会：YES_ask + NO_ask < $1
        // 以 ask 价买入 YES 和 NO，然后 Merge 成 $1
        const buy_total = yes_ask + no_ask;
        if (buy_total < 1.0) {
            const profit_per_share = 1.0 - buy_total;
            const total_profit = profit_per_share * shares;
            return .{
                .arb_type = .buy_and_merge,
                .expected_profit = total_profit,
                .yes_price = yes_ask,
                .no_price = no_ask,
                .total_price = buy_total,
                .shares = shares,
            };
        }

        return .{
            .arb_type = .none,
            .expected_profit = 0,
            .yes_price = 0,
            .no_price = 0,
            .total_price = 0,
            .shares = 0,
        };
    }

    /// 执行套利
    fn executeArbitrage(self: *Self, market: MarketInfo, opp: ArbOpportunity) !void {
        switch (opp.arb_type) {
            .split_and_sell => {
                log("", .{});
                log("  ========================================", .{});
                log("  💰 发现 Split 套利机会!", .{});
                log("  ========================================", .{});
                log("  YES bid: ${d:.4}, NO bid: ${d:.4}", .{ opp.yes_price, opp.no_price });
                log("  总价: ${d:.4} > $1.00", .{opp.total_price});
                log("  预期利润: ${d:.4}", .{opp.expected_profit});
                log("", .{});

                if (self.config.dry_run) {
                    log("  [模拟] Split ${d:.2} -> {d:.0} YES + {d:.0} NO", .{ opp.shares, opp.shares, opp.shares });
                    log("  [模拟] 卖出 YES: {d:.0} 股 @ ${d:.4} = ${d:.2}", .{ opp.shares, opp.yes_price, opp.shares * opp.yes_price });
                    log("  [模拟] 卖出 NO:  {d:.0} 股 @ ${d:.4} = ${d:.2}", .{ opp.shares, opp.no_price, opp.shares * opp.no_price });
                    log("  [模拟] 总收入: ${d:.2}, 成本: ${d:.2}", .{ opp.shares * opp.total_price, opp.shares });
                    log("  [模拟] 利润: ${d:.2}", .{opp.expected_profit});
                    self.total_profit += opp.expected_profit;
                    self.total_trades += 1;
                } else {
                    // 实盘执行
                    try self.executeSplitAndSell(market, opp);
                }
            },
            .buy_and_merge => {
                log("", .{});
                log("  ========================================", .{});
                log("  💰 发现 Merge 套利机会!", .{});
                log("  ========================================", .{});
                log("  YES ask: ${d:.4}, NO ask: ${d:.4}", .{ opp.yes_price, opp.no_price });
                log("  总价: ${d:.4} < $1.00", .{opp.total_price});
                log("  预期利润: ${d:.4}", .{opp.expected_profit});
                log("", .{});

                if (self.config.dry_run) {
                    log("  [模拟] 买入 YES: {d:.0} 股 @ ${d:.4} = ${d:.2}", .{ opp.shares, opp.yes_price, opp.shares * opp.yes_price });
                    log("  [模拟] 买入 NO:  {d:.0} 股 @ ${d:.4} = ${d:.2}", .{ opp.shares, opp.no_price, opp.shares * opp.no_price });
                    log("  [模拟] Merge {d:.0} 股 -> ${d:.2}", .{ opp.shares, opp.shares });
                    log("  [模拟] 总成本: ${d:.2}, 收入: ${d:.2}", .{ opp.shares * opp.total_price, opp.shares });
                    log("  [模拟] 利润: ${d:.2}", .{opp.expected_profit});
                    self.total_profit += opp.expected_profit;
                    self.total_trades += 1;
                } else {
                    // 实盘执行
                    try self.executeBuyAndMerge(market, opp);
                }
            },
            .none => {},
        }
    }

    /// 执行 Split 后卖出
    fn executeSplitAndSell(self: *Self, market: MarketInfo, opp: ArbOpportunity) !void {
        // 1. Split USDC -> YES + NO
        if (self.ctf_client) |*ctf| {
            const amount: u64 = @intFromFloat(opp.shares * 1_000_000); // USDC 6位小数

            // 1a. 检查 USDC 余额和 allowance
            // 注意: CTF 链上操作是从 EOA 发起的，所以检查 EOA 的余额
            // (CLOB 订单通过 Polymarket API，使用 proxy 钱包，但那是另一回事)
            if (self.wallet) |wallet| {
                const amount_u256: u256 = @intCast(amount);
                const eoa_addr = wallet.getAddressChecksumHex();

                // 检查 EOA 的 USDC 余额（CTF 交易从 EOA 发起）
                const balance = ctf.getUsdcBalance(&eoa_addr) catch 0;
                if (balance < amount_u256) {
                    const bal_usdc = @as(f64, @floatFromInt(@as(u64, @truncate(balance)))) / 1_000_000.0;
                    log("  ❌ USDC 余额不足: ${d:.2} < ${d:.2}", .{ bal_usdc, opp.shares });
                    return;
                }

                // 检查 EOA 的 USDC allowance
                const allowance = ctf.getUsdcAllowance(&eoa_addr) catch 0;
                if (allowance < amount_u256) {
                    log("  📝 授权 USDC 给 CTF 合约...", .{});
                    // 授权最大值
                    const max_u256: u256 = @as(u256, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
                    const approve_tx = ctf.approveUsdc(max_u256) catch |err| {
                        log("  ❌ USDC 授权失败: {}", .{err});
                        return;
                    };
                    log("  ⏳ 等待 USDC 授权确认: {s}", .{approve_tx});

                    const approve_confirmed = ctf.waitForTransaction(approve_tx, 30) catch |err| {
                        log("  ❌ 等待 USDC 授权确认失败: {}", .{err});
                        return;
                    };

                    if (!approve_confirmed) {
                        log("  ❌ USDC 授权交易失败!", .{});
                        return;
                    }
                    log("  ✅ USDC 授权成功!", .{});
                }
            }

            log("  执行 Split: ${d:.2} USDC -> {d:.0} YES + {d:.0} NO", .{ opp.shares, opp.shares, opp.shares });

            const split_result = ctf.split(market.getConditionId(), amount) catch |err| {
                log("  ❌ Split 失败: {}", .{err});
                return;
            };
            log("  ✅ Split 交易已发送: {s}", .{split_result.tx_hash});

            // 2. 等待交易确认
            log("  ⏳ 等待交易确认...", .{});
            const confirmed = ctf.waitForTransaction(split_result.tx_hash, 30) catch |err| {
                log("  ❌ 等待交易确认失败: {}", .{err});
                return;
            };

            if (!confirmed) {
                log("  ❌ Split 交易失败!", .{});
                return;
            }
            log("  ✅ Split 交易已确认!", .{});

            // 3. 检查并授权 CTF Exchange（如果需要）
            // CTF 代币在 EOA 地址，需要 EOA 授权 CTF Exchange
            {
                const check_addr = self.wallet.?.getAddressChecksumHex();
                const is_approved = ctf.isApprovedForAll(&check_addr, poly.ctf.CTF_EXCHANGE) catch false;

                if (!is_approved) {
                    log("  📝 授权 CTF Exchange...", .{});
                    const approve_tx = ctf.setApprovalForAll(poly.ctf.CTF_EXCHANGE, true) catch |err| {
                        log("  ❌ 授权失败: {}", .{err});
                        return;
                    };
                    log("  ⏳ 等待授权确认: {s}", .{approve_tx});

                    const approve_confirmed = ctf.waitForTransaction(approve_tx, 30) catch |err| {
                        log("  ❌ 等待授权确认失败: {}", .{err});
                        return;
                    };

                    if (!approve_confirmed) {
                        log("  ❌ 授权交易失败!", .{});
                        return;
                    }
                    log("  ✅ CTF Exchange 授权成功!", .{});
                }
            }

            // 4. 卖出 YES 和 NO
            if (self.builder) |*builder| {
                // 卖出 YES
                const yes_order = try builder.createOrder(.{
                    .token_id = market.getUpTokenId(),
                    .price = try Decimal.fromFloat(opp.yes_price),
                    .size = try Decimal.fromFloat(opp.shares),
                    .side = .SELL,
                }, .{
                    .tick_size = .@"0.01",
                    .neg_risk = false,
                    .signature_type = self.config.signature_type,
                });

                const yes_response = self.client.postOrder(&yes_order, .GTC) catch |err| {
                    log("  ❌ 卖出 YES 失败: {}", .{err});
                    return;
                };

                if (yes_response.success) {
                    log("  ✅ 卖出 YES 成功", .{});
                } else {
                    log("  ❌ 卖出 YES 被拒绝", .{});
                    return;
                }

                // 卖出 NO
                const no_order = try builder.createOrder(.{
                    .token_id = market.getDownTokenId(),
                    .price = try Decimal.fromFloat(opp.no_price),
                    .size = try Decimal.fromFloat(opp.shares),
                    .side = .SELL,
                }, .{
                    .tick_size = .@"0.01",
                    .neg_risk = false,
                    .signature_type = self.config.signature_type,
                });

                const no_response = self.client.postOrder(&no_order, .GTC) catch |err| {
                    log("  ❌ 卖出 NO 失败: {}", .{err});
                    return;
                };

                if (no_response.success) {
                    log("  ✅ 卖出 NO 成功", .{});
                } else {
                    log("  ❌ 卖出 NO 被拒绝", .{});
                    return;
                }

                self.total_profit += opp.expected_profit;
                self.total_trades += 1;
                log("  💰 套利完成! 利润: ${d:.2}", .{opp.expected_profit});
            }
        }
    }

    /// 执行买入后 Merge
    fn executeBuyAndMerge(self: *Self, market: MarketInfo, opp: ArbOpportunity) !void {
        if (self.builder) |*builder| {
            // 1. 买入 YES
            log("  买入 YES: {d:.0} 股 @ ${d:.4}", .{ opp.shares, opp.yes_price });

            const yes_order = try builder.createOrder(.{
                .token_id = market.getUpTokenId(),
                .price = try Decimal.fromFloat(opp.yes_price),
                .size = try Decimal.fromFloat(opp.shares),
                .side = .BUY,
            }, .{
                .tick_size = .@"0.01",
                .neg_risk = false,
                .signature_type = self.config.signature_type,
            });

            const yes_response = self.client.postOrder(&yes_order, .GTC) catch |err| {
                log("  ❌ 买入 YES 失败: {}", .{err});
                return;
            };

            if (!yes_response.success) {
                log("  ❌ 买入 YES 被拒绝", .{});
                return;
            }
            log("  ✅ 买入 YES 成功", .{});

            // 2. 买入 NO
            log("  买入 NO: {d:.0} 股 @ ${d:.4}", .{ opp.shares, opp.no_price });

            const no_order = try builder.createOrder(.{
                .token_id = market.getDownTokenId(),
                .price = try Decimal.fromFloat(opp.no_price),
                .size = try Decimal.fromFloat(opp.shares),
                .side = .BUY,
            }, .{
                .tick_size = .@"0.01",
                .neg_risk = false,
                .signature_type = self.config.signature_type,
            });

            const no_response = self.client.postOrder(&no_order, .GTC) catch |err| {
                log("  ❌ 买入 NO 失败: {}", .{err});
                return;
            };

            if (!no_response.success) {
                log("  ❌ 买入 NO 被拒绝", .{});
                return;
            }
            log("  ✅ 买入 NO 成功", .{});

            // 3. Merge YES + NO -> USDC
            if (self.ctf_client) |*ctf| {
                const amount: u64 = @intFromFloat(opp.shares * 1_000_000);
                log("  执行 Merge: {d:.0} YES + {d:.0} NO -> ${d:.2}", .{ opp.shares, opp.shares, opp.shares });

                const merge_result = ctf.merge(market.getConditionId(), amount) catch |err| {
                    log("  ❌ Merge 失败: {}", .{err});
                    return;
                };
                log("  ✅ Merge 成功: {s}", .{merge_result.tx_hash});

                self.total_profit += opp.expected_profit;
                self.total_trades += 1;
                log("  💰 套利完成! 利润: ${d:.2}", .{opp.expected_profit});
            }
        }
    }

    /// 获取订单簿
    fn fetchOrderBook(self: *Self, market: MarketInfo) !void {
        const up_book = self.client.getOrderBook(market.getUpTokenId()) catch return;
        defer up_book.deinit();

        const down_book = self.client.getOrderBook(market.getDownTokenId()) catch return;
        defer down_book.deinit();

        // ⚠️ 重要：每次都重置订单簿数据，避免过时数据
        var up_best_bid: f64 = 0;
        var up_best_ask: f64 = 1;
        var down_best_bid: f64 = 0;
        var down_best_ask: f64 = 1;

        // 解析 UP 订单簿
        if (up_book.value.bids) |bids| {
            for (bids) |bid| {
                const price = std.fmt.parseFloat(f64, bid.price) catch continue;
                if (price > up_best_bid) {
                    up_best_bid = price;
                }
            }
        }

        if (up_book.value.asks) |asks| {
            for (asks) |ask| {
                const price = std.fmt.parseFloat(f64, ask.price) catch continue;
                if (price < up_best_ask) {
                    up_best_ask = price;
                }
            }
        }

        // 解析 DOWN 订单簿
        if (down_book.value.bids) |bids| {
            for (bids) |bid| {
                const price = std.fmt.parseFloat(f64, bid.price) catch continue;
                if (price > down_best_bid) {
                    down_best_bid = price;
                }
            }
        }

        if (down_book.value.asks) |asks| {
            for (asks) |ask| {
                const price = std.fmt.parseFloat(f64, ask.price) catch continue;
                if (price < down_best_ask) {
                    down_best_ask = price;
                }
            }
        }

        // 更新全局状态
        g_live_book.up_best_bid = up_best_bid;
        g_live_book.up_best_ask = up_best_ask;
        g_live_book.down_best_bid = down_best_bid;
        g_live_book.down_best_ask = down_best_ask;
        g_live_book.last_update = std.time.timestamp();
    }

    /// 打印状态
    fn printStatus(self: *Self, market: MarketInfo, opp: ArbOpportunity) void {
        // 清屏
        std.debug.print("\x1B[2J\x1B[H", .{});

        const now = std.time.timestamp();
        const remaining = market.end_time - now;
        const mins = @divFloor(remaining, 60);
        const secs = @mod(remaining, 60);

        std.debug.print("╔═══════════════════════════════════════════════════════════════════════════╗\n", .{});
        std.debug.print("║     Split/Merge 套利机器人 - {s}模式     ║\n", .{if (self.config.dry_run) "模拟" else "实盘"});
        std.debug.print("╠═══════════════════════════════════════════════════════════════════════════╣\n", .{});
        std.debug.print("║  市场: {s:<50}    ║\n", .{market.getSlug()});
        std.debug.print("║  剩余: {d:>2}:{d:0>2}                                                          ║\n", .{ mins, secs });
        std.debug.print("╠═══════════════════════════════════════════════════════════════════════════╣\n", .{});
        std.debug.print("║                          订 单 簿                                         ║\n", .{});
        std.debug.print("╠═══════════════════════════════════════════════════════════════════════════╣\n", .{});
        std.debug.print("║  YES:  bid ${d:.4}  |  ask ${d:.4}                                    ║\n", .{
            g_live_book.up_best_bid,
            g_live_book.up_best_ask,
        });
        std.debug.print("║  NO:   bid ${d:.4}  |  ask ${d:.4}                                    ║\n", .{
            g_live_book.down_best_bid,
            g_live_book.down_best_ask,
        });
        std.debug.print("╠═══════════════════════════════════════════════════════════════════════════╣\n", .{});
        std.debug.print("║                          套 利 分 析                                      ║\n", .{});
        std.debug.print("╠═══════════════════════════════════════════════════════════════════════════╣\n", .{});

        const sell_total = g_live_book.up_best_bid + g_live_book.down_best_bid;
        const buy_total = g_live_book.up_best_ask + g_live_book.down_best_ask;

        std.debug.print("║  Split 后卖出: YES_bid + NO_bid = ${d:.4}                            ║\n", .{sell_total});
        if (sell_total > 1.0) {
            std.debug.print("║    🟢 可套利! 利润/股: ${d:.4}                                       ║\n", .{sell_total - 1.0});
        } else {
            std.debug.print("║    🔴 无利润 (需 > $1.00)                                            ║\n", .{});
        }

        std.debug.print("║  买入后 Merge: YES_ask + NO_ask = ${d:.4}                            ║\n", .{buy_total});
        if (buy_total < 1.0) {
            std.debug.print("║    🟢 可套利! 利润/股: ${d:.4}                                       ║\n", .{1.0 - buy_total});
        } else {
            std.debug.print("║    🔴 无利润 (需 < $1.00)                                            ║\n", .{});
        }

        std.debug.print("╠═══════════════════════════════════════════════════════════════════════════╣\n", .{});
        std.debug.print("║                          统 计                                            ║\n", .{});
        std.debug.print("╠═══════════════════════════════════════════════════════════════════════════╣\n", .{});
        std.debug.print("║  总交易: {d:<5}  总利润: ${d:>10.2}                                   ║\n", .{
            self.total_trades,
            self.total_profit,
        });

        if (opp.arb_type != .none) {
            std.debug.print("║  当前机会: {s:<15}  预期利润: ${d:>7.4}                      ║\n", .{
                @tagName(opp.arb_type),
                opp.expected_profit,
            });
        }

        std.debug.print("╚═══════════════════════════════════════════════════════════════════════════╝\n", .{});
    }
};

// ============================================================================
// 辅助函数
// ============================================================================

fn hexCharToNibble(c: u8) ?u4 {
    return switch (c) {
        '0'...'9' => @intCast(c - '0'),
        'a'...'f' => @intCast(c - 'a' + 10),
        'A'...'F' => @intCast(c - 'A' + 10),
        else => null,
    };
}

fn log(comptime fmt: []const u8, args: anytype) void {
    const timestamp = std.time.timestamp();
    const hours = @mod(@divFloor(timestamp, 3600), 24) + 8; // UTC+8
    const minutes = @mod(@divFloor(timestamp, 60), 60);
    const seconds = @mod(timestamp, 60);

    std.debug.print("[{d:0>2}:{d:0>2}:{d:0>2}] ", .{ hours, minutes, seconds });
    std.debug.print(fmt ++ "\n", args);
}

/// Gamma API Base URL
const GAMMA_API_BASE_URL = "https://gamma-api.polymarket.com";

/// 从 Gamma API 获取市场信息
fn fetchMarketFromGamma(allocator: std.mem.Allocator, slug: []const u8, end_time: i64) !MarketInfo {
    var url_buf: [256]u8 = undefined;
    const url = std.fmt.bufPrint(&url_buf, "{s}/events?slug={s}", .{ GAMMA_API_BASE_URL, slug }) catch return error.BufferTooSmall;

    const argv: []const []const u8 = &.{ "curl", "-s", "-f", url };

    var child = std.process.Child.init(argv, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    child.spawn() catch return error.SpawnFailed;

    const stdout = child.stdout.?;
    var read_buffer: [8192]u8 = undefined;
    var response = try std.ArrayList(u8).initCapacity(allocator, 4096);
    defer response.deinit(allocator);

    while (true) {
        const n = stdout.read(&read_buffer) catch return error.ReadFailed;
        if (n == 0) break;
        response.appendSlice(allocator, read_buffer[0..n]) catch return error.OutOfMemory;
    }

    const result = child.wait() catch return error.WaitFailed;
    if (result != .Exited or result.Exited != 0) {
        return error.CurlFailed;
    }

    return parseGammaResponse(response.items, slug, end_time);
}

/// 解析 Gamma API 响应
fn parseGammaResponse(json_data: []const u8, slug: []const u8, end_time: i64) !MarketInfo {
    // 查找 clobTokenIds
    const clob_tokens_start = std.mem.indexOf(u8, json_data, "\"clobTokenIds\":\"[\\\"") orelse return error.TokensNotFound;
    const tokens_data = json_data[clob_tokens_start + 19 ..];

    const first_token_end = std.mem.indexOf(u8, tokens_data, "\\\"") orelse return error.ParseError;
    const up_token = tokens_data[0..first_token_end];

    const rest = tokens_data[first_token_end + 6 ..];
    const second_token_end = std.mem.indexOf(u8, rest, "\\\"") orelse return error.ParseError;
    const down_token = rest[0..second_token_end];

    // 查找 conditionId
    const condition_start = std.mem.indexOf(u8, json_data, "\"conditionId\":\"") orelse return error.ConditionNotFound;
    const condition_data = json_data[condition_start + 15 ..];
    const condition_end = std.mem.indexOf(u8, condition_data, "\"") orelse return error.ParseError;
    const condition_id = condition_data[0..condition_end];

    // 使用固定大小缓冲区
    var info = MarketInfo{
        .end_time = end_time,
    };

    // 复制数据到缓冲区
    if (slug.len > info.slug_buf.len) return error.BufferTooSmall;
    @memcpy(info.slug_buf[0..slug.len], slug);
    info.slug_len = slug.len;

    if (condition_id.len > info.condition_id_buf.len) return error.BufferTooSmall;
    @memcpy(info.condition_id_buf[0..condition_id.len], condition_id);
    info.condition_id_len = condition_id.len;

    if (up_token.len > info.up_token_id_buf.len) return error.BufferTooSmall;
    @memcpy(info.up_token_id_buf[0..up_token.len], up_token);
    info.up_token_id_len = up_token.len;

    if (down_token.len > info.down_token_id_buf.len) return error.BufferTooSmall;
    @memcpy(info.down_token_id_buf[0..down_token.len], down_token);
    info.down_token_id_len = down_token.len;

    return info;
}

// ============================================================================
// 主函数
// ============================================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 加载环境变量
    var env = poly.loadEnvOrEmpty(allocator, ".env");
    defer env.deinit();

    // 解析配置
    const config = ArbConfig{
        .dry_run = env.getBool("ARB_DRY_RUN", true),
        .min_profit = env.getFloat(f64, "ARB_MIN_PROFIT", 0.02),
        .order_size = env.getFloat(f64, "ARB_ORDER_SIZE", 10.0),
        .rpc_url = env.get("ARB_RPC_URL") orelse "https://polygon-rpc.com",
        .use_testnet = env.getBool("USE_TESTNET", false),
        // Split/Merge 套利必须使用 EOA 模式！
        // CTF 链上操作和 CLOB 卖单必须使用同一个钱包
        // 忽略 WS_TRADER_SIGNATURE_TYPE 和 POLY_ADDRESS 环境变量
        .signature_type = .EOA,
        .funder = null, // EOA 模式不需要 funder
    };

    // 初始化钱包
    const private_key_hex = env.get("POLY_PRIVATE_KEY") orelse {
        std.debug.print("错误: 请设置 POLY_PRIVATE_KEY 环境变量\n", .{});
        return;
    };

    var wallet = Wallet.fromPrivateKeyHex(private_key_hex) catch {
        std.debug.print("错误: 无效的私钥\n", .{});
        return;
    };

    // 初始化 CLOB 客户端
    const client_config = poly.clob.client.Config{
        .base_url = if (config.use_testnet) poly.clob.client.BASE_URL_TESTNET else poly.clob.client.BASE_URL_MAINNET,
    };

    var creds: ?poly.ApiCreds = null;

    // 检查是否提供了 API 凭证
    const api_key = env.get("POLY_API_KEY");
    const api_secret = env.get("POLY_API_SECRET");
    const api_passphrase = env.get("POLY_API_PASSPHRASE");

    var client: ClobClient = undefined;

    if (!config.dry_run) {
        if (api_key != null and api_secret != null and api_passphrase != null) {
            creds = try poly.ApiCreds.init(allocator, api_key.?, api_secret.?, api_passphrase.?);
            client = ClobClient.initWithAuth(allocator, client_config, &wallet, &creds.?);
        } else {
            client = ClobClient.init(allocator, client_config);
            client.setWallet(&wallet);

            log("正在获取 API 凭证...", .{});
            creds = client.createOrDeriveApiKey() catch |err| {
                std.debug.print("获取 API 凭证失败: {}\n", .{err});
                return;
            };

            log("API 凭证获取成功!", .{});
            client.setApiCreds(&creds.?);
        }
    } else {
        client = ClobClient.init(allocator, client_config);
    }
    defer client.deinit();
    defer if (creds) |*c| c.deinit();

    // 创建机器人
    var bot = SplitMergeArbBot.init(allocator, &client, &wallet, config);

    // 主循环 - 持续寻找并交易市场
    while (true) {
        log("", .{});
        log("════════════════════════════════════════════════════════════════", .{});
        log("  寻找 BTC 15分钟市场...", .{});
        log("════════════════════════════════════════════════════════════════", .{});

        // 查找 BTC 15分钟市场
        const now = std.time.timestamp();
        const interval: i64 = 900;
        const current_slot = @divFloor(now, interval) * interval;
        const next_slot = current_slot + interval;

        // 尝试 current_slot 和 next_slot
        const slots = [_]i64{ current_slot, next_slot };
        var market: ?MarketInfo = null;

        for (slots) |slot| {
            var slug_buf: [64]u8 = undefined;
            const slug = std.fmt.bufPrint(&slug_buf, "btc-updown-15m-{d}", .{slot}) catch continue;

            log("尝试查找市场: {s}", .{slug});

            if (fetchMarketFromGamma(allocator, slug, slot + interval)) |m| {
                const remaining = m.end_time - now;
                const started = now >= slot;

                if (!started) {
                    const wait = slot - now;
                    log("  市场 {s} 还未开始，等待 {d} 秒", .{ slug, wait });
                    continue;
                }

                if (remaining <= 60) { // 至少剩余1分钟
                    log("  市场 {s} 剩余时间不足 ({d}秒)，跳过", .{ slug, remaining });
                    continue;
                }

                log("  找到活跃市场: {s}，剩余 {d} 分钟", .{ slug, @divFloor(remaining, 60) });
                market = m;
                break;
            } else |_| {
                log("  市场 {s} 不存在", .{slug});
                continue;
            }
        }

        if (market == null) {
            // 计算下一个市场开始时间
            const next_market_time = next_slot;
            const wait_seconds = next_market_time - now;
            log("未找到适合的市场", .{});
            log("下一个市场: btc-updown-15m-{d}", .{next_market_time});
            log("等待 {d} 分 {d} 秒后重试...", .{ @divFloor(wait_seconds, 60), @mod(wait_seconds, 60) });

            // 等待一段时间后重试（每5秒检查一次）
            std.Thread.sleep(5 * std.time.ns_per_s);
            continue;
        }

        const m = market.?;

        log("市场: {s}", .{m.getSlug()});
        log("Condition ID: {s}", .{m.getConditionId()});
        log("UP Token: {s}", .{m.getUpTokenId()});
        log("DOWN Token: {s}", .{m.getDownTokenId()});

        // 运行机器人
        bot.run(m) catch |err| {
            log("机器人运行出错: {}", .{err});
        };

        // 市场结束后，短暂等待再寻找下一个市场
        log("", .{});
        log("当前市场已结束，寻找下一个市场...", .{});
        std.Thread.sleep(2 * std.time.ns_per_s);
    }
}
