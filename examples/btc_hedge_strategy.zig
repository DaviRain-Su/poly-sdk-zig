//! BTC 二元期权对冲套利策略
//!
//! 策略概述:
//! 针对 Polymarket 上 "BTC价格在下一个15分钟内是否上涨" 的二元期权市场,
//! 实现两步对冲套利策略,捕捉短期暴跌带来的低价机会。
//!
//! 核心逻辑:
//! 1. 第一步 - 捕捉暴跌买入 YES: 当检测到价格快速大幅下跌时,买入 YES 股份
//! 2. 第二步 - 反弹后对冲锁定: 价格反弹后,卖出等量 NO 股份,锁定利润
//!
//! 利润来源:
//! - YES + NO = 1 美元 (完全对冲)
//! - 若 YES 买入均价 0.20,对冲时涨到 0.35,则锁定 0.15 利润/份
//!
//! 风险提示:
//! - 这是真实交易代码,会涉及资金风险
//! - 仅用于教育目的,非投资建议
//! - 建议先在测试网或小额验证
//!
//! 运行前准备:
//! 方法一: 使用 .env 文件 (推荐)
//!   1. 复制 .env.example 为 .env
//!   2. 填入你的配置值
//!   3. 运行程序
//!
//! 方法二: 使用环境变量
//!   1. 设置环境变量 POLY_PRIVATE_KEY (钱包私钥)
//!   2. 设置环境变量 POLY_API_KEY, POLY_API_SECRET, POLY_API_PASSPHRASE
//!   3. 设置市场 Token ID 和 Condition ID
//!   4. 确保钱包有足够的 USDC 余额
//!
//! 配置说明:
//! - POLY_PRIVATE_KEY: 钱包私钥 (不带 0x 前缀)
//! - POLY_API_KEY: Polymarket API Key
//! - POLY_API_SECRET: Polymarket API Secret
//! - POLY_API_PASSPHRASE: Polymarket API Passphrase
//! - POLY_YES_TOKEN: YES Token ID (从市场页面获取)
//! - POLY_NO_TOKEN: NO Token ID (从市场页面获取)
//! - POLY_CONDITION_ID: 市场 Condition ID
//! - POLY_USE_TESTNET: 是否使用测试网 (true/false, 默认 false)
//!
//! 策略参数:
//! - STRATEGY_SUM_TARGET: 累计买入目标 (0-1, 默认 0.3)
//! - STRATEGY_MOVE_THRESHOLD: 下跌触发阈值 (0-1, 默认 0.01)
//! - STRATEGY_MIN_BUY_PRICE: 最低买入价格 (0-1, 默认 0.15)
//! - STRATEGY_HEDGE_SPREAD: 对冲价差 (0-1, 默认 0.05)
//! - STRATEGY_MAX_POSITION: 最大仓位 USDC (默认 100)
//! - STRATEGY_POLL_INTERVAL: 监控间隔毫秒 (默认 500)

const std = @import("std");
const poly = @import("poly_sdk_zig");

// 导入核心类型
const ClobClient = poly.ClobClient;
const Wallet = poly.Wallet;
const ApiCreds = poly.ApiCreds;
const Decimal = poly.Decimal;
const OrderBuilder = poly.OrderBuilder;
const Side = poly.Side;
const TickSize = poly.TickSize;
const DotEnv = poly.DotEnv;

// ============================================================================
// 策略配置
// ============================================================================

/// 策略配置参数
const StrategyConfig = struct {
    /// YES Token ID (需要从市场获取)
    yes_token_id: []const u8,

    /// NO Token ID (需要从市场获取)
    no_token_id: []const u8,

    /// 市场 Condition ID
    condition_id: []const u8,

    /// 累计买入目标 (0-1)
    /// 值越小越保守,只在极低价时重仓
    /// 推荐: 0.3 (保守) - 0.6 (激进)
    sum_target: f64 = 0.3,

    /// 触发监控的价格下跌幅度 (0-1)
    /// 例如 0.01 表示价格下跌 1% 时开始监控
    move_threshold: f64 = 0.01,

    /// 最低买入价格阈值
    /// 价格低于此值才考虑买入
    min_buy_price: f64 = 0.15,

    /// 对冲触发的最小价差
    /// 当前价格 - 买入均价 > 此值时触发对冲
    hedge_spread: f64 = 0.05,

    /// 单次最大买入金额 (USDC)
    max_position_size: f64 = 100.0,

    /// 价格监控间隔 (毫秒)
    poll_interval_ms: u64 = 500,

    /// 是否使用测试网
    use_testnet: bool = false,
};

/// 策略状态
const StrategyState = struct {
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

    /// 历史最高价 (用于检测下跌)
    high_water_mark: f64 = 0,

    /// 策略是否运行中
    running: bool = true,

    /// 更新买入均价
    fn updateAvgPrice(self: *StrategyState, new_size: f64, new_price: f64) void {
        const new_cost = new_size * new_price;
        self.yes_cost += new_cost;
        self.yes_position += new_size;
        if (self.yes_position > 0) {
            self.yes_avg_price = self.yes_cost / self.yes_position;
        }
    }

    /// 重置状态 (新一轮交易)
    fn reset(self: *StrategyState) void {
        self.yes_position = 0;
        self.yes_cost = 0;
        self.yes_avg_price = 0;
        self.is_hedged = false;
        self.high_water_mark = 0;
    }
};

// ============================================================================
// 策略核心逻辑
// ============================================================================

/// BTC 对冲策略
const BtcHedgeStrategy = struct {
    allocator: std.mem.Allocator,
    config: StrategyConfig,
    state: StrategyState,
    client: *ClobClient,
    builder: OrderBuilder,

    const Self = @This();

    /// 初始化策略
    pub fn init(
        allocator: std.mem.Allocator,
        client: *ClobClient,
        wallet: *const Wallet,
        config: StrategyConfig,
    ) Self {
        return Self{
            .allocator = allocator,
            .config = config,
            .state = StrategyState{},
            .client = client,
            .builder = OrderBuilder.init(wallet, .{
                .chain_id = if (config.use_testnet) 80002 else 137,
            }),
        };
    }

    /// 获取当前 YES 价格
    fn getYesPrice(self: *Self) !f64 {
        const price_resp = self.client.getPrice(
            self.config.yes_token_id,
            .BUY,
        ) catch |err| {
            log("获取价格失败: {}", .{err});
            return err;
        };

        if (price_resp.price) |price_str| {
            return parsePrice(price_str);
        }
        return error.NoPriceAvailable;
    }

    /// 获取订单簿
    fn getOrderBook(self: *Self, token_id: []const u8) !std.json.Parsed(poly.clob.types.OrderBookSummary) {
        return self.client.getOrderBook(token_id);
    }

    /// 检测是否发生暴跌
    fn detectCrash(self: *Self, current_price: f64) bool {
        // 更新高水位
        if (current_price > self.state.high_water_mark) {
            self.state.high_water_mark = current_price;
        }

        // 计算从高点的跌幅
        if (self.state.high_water_mark > 0) {
            const drop = (self.state.high_water_mark - current_price) / self.state.high_water_mark;
            return drop >= self.config.move_threshold;
        }

        return false;
    }

    /// 计算应该买入的数量
    fn calculateBuySize(self: *Self, current_price: f64) f64 {
        // 基于价格的动态仓位
        // 价格越低,买入越多
        if (current_price >= self.config.min_buy_price) {
            return 0; // 价格不够低
        }

        // 计算累计买入比例
        const current_sum = self.state.yes_position * self.state.yes_avg_price;
        const target_sum = self.config.sum_target * self.config.max_position_size;

        if (current_sum >= target_sum) {
            return 0; // 已达到目标
        }

        // 剩余可买入金额
        const remaining = target_sum - current_sum;

        // 计算买入股数 (金额 / 价格)
        const size = remaining / current_price;

        // 限制单次买入量
        return @min(size, self.config.max_position_size / current_price * 0.1);
    }

    /// 检测是否应该对冲
    fn shouldHedge(self: *Self, current_price: f64) bool {
        if (self.state.is_hedged or self.state.yes_position == 0) {
            return false;
        }

        // 检查价差是否足够
        const spread = current_price - self.state.yes_avg_price;
        return spread >= self.config.hedge_spread;
    }

    /// 执行买入 YES
    fn executeBuyYes(self: *Self, size: f64, price: f64) !void {
        log("准备买入 YES: 数量={d:.2}, 价格={d:.4}", .{ size, price });

        // 构建订单
        const price_decimal = try Decimal.fromString(try std.fmt.allocPrint(self.allocator, "{d:.4}", .{price}));
        const size_decimal = try Decimal.fromString(try std.fmt.allocPrint(self.allocator, "{d:.2}", .{size}));

        const order = try self.builder.createOrder(.{
            .token_id = self.config.yes_token_id,
            .price = price_decimal,
            .size = size_decimal,
            .side = .BUY,
        }, .{
            .tick_size = .@"0.01",
            .neg_risk = false,
        });

        // 发布订单 (FAK - Fill And Kill, 尽可能成交)
        const response = try self.client.postOrder(&order, .FAK);

        if (response.success) {
            log("YES 买入成功! 订单ID: {s}", .{response.orderID orelse "N/A"});
            self.state.updateAvgPrice(size, price);
        } else {
            log("YES 买入失败: {s}", .{response.errorMsg orelse "未知错误"});
        }
    }

    /// 执行卖出 NO (对冲)
    fn executeHedge(self: *Self, current_yes_price: f64) !void {
        // NO 价格 = 1 - YES 价格
        const no_price = 1.0 - current_yes_price;
        const size = self.state.yes_position;

        log("准备对冲卖出 NO: 数量={d:.2}, NO价格={d:.4}", .{ size, no_price });

        // 构建卖出 NO 的订单
        const price_decimal = try Decimal.fromString(try std.fmt.allocPrint(self.allocator, "{d:.4}", .{no_price}));
        const size_decimal = try Decimal.fromString(try std.fmt.allocPrint(self.allocator, "{d:.2}", .{size}));

        const order = try self.builder.createOrder(.{
            .token_id = self.config.no_token_id,
            .price = price_decimal,
            .size = size_decimal,
            .side = .SELL,
        }, .{
            .tick_size = .@"0.01",
            .neg_risk = false,
        });

        // 发布订单
        const response = try self.client.postOrder(&order, .FAK);

        if (response.success) {
            // 计算锁定利润
            // 每份锁定价值 = 1 美元
            // 成本 = YES 成本 + NO 卖出收入 (负数因为是卖出)
            // 利润 = 持仓数量 * 1 - YES 成本 - NO 成本
            const locked_value = size * 1.0;
            const profit = locked_value - self.state.yes_cost;

            self.state.is_hedged = true;
            self.state.locked_profit = profit;

            log("对冲成功! 锁定利润: ${d:.2}", .{profit});
            log("  YES 均价: {d:.4}, 对冲时价格: {d:.4}", .{ self.state.yes_avg_price, current_yes_price });
        } else {
            log("对冲失败: {s}", .{response.errorMsg orelse "未知错误"});
        }
    }

    /// 运行策略主循环
    pub fn run(self: *Self) !void {
        log("=== BTC 对冲策略启动 ===", .{});
        log("配置:", .{});
        log("  YES Token: {s}", .{self.config.yes_token_id});
        log("  NO Token: {s}", .{self.config.no_token_id});
        log("  目标累计: {d:.1}%", .{self.config.sum_target * 100});
        log("  下跌阈值: {d:.1}%", .{self.config.move_threshold * 100});
        log("  最低买入价: {d:.2}", .{self.config.min_buy_price});
        log("  对冲价差: {d:.2}", .{self.config.hedge_spread});
        log("", .{});

        var last_price: f64 = 0;
        var iteration: u64 = 0;

        while (self.state.running) {
            iteration += 1;

            // 获取当前价格
            const current_price = self.getYesPrice() catch |err| {
                log("获取价格失败: {}, 重试中...", .{err});
                std.Thread.sleep(self.config.poll_interval_ms * std.time.ns_per_ms);
                continue;
            };

            // 价格变化日志
            if (@abs(current_price - last_price) > 0.001) {
                log("[{d}] YES价格: {d:.4} (均价: {d:.4}, 持仓: {d:.2})", .{
                    iteration,
                    current_price,
                    self.state.yes_avg_price,
                    self.state.yes_position,
                });
                last_price = current_price;
            }

            // 策略逻辑
            if (!self.state.is_hedged) {
                // 阶段1: 寻找买入机会
                if (self.detectCrash(current_price)) {
                    const buy_size = self.calculateBuySize(current_price);
                    if (buy_size > 0) {
                        log("检测到暴跌! 当前价格: {d:.4}", .{current_price});
                        self.executeBuyYes(buy_size, current_price) catch |err| {
                            log("买入执行失败: {}", .{err});
                        };
                    }
                }

                // 阶段2: 检查对冲时机
                if (self.shouldHedge(current_price)) {
                    log("触发对冲! 当前价格: {d:.4}, 买入均价: {d:.4}", .{
                        current_price,
                        self.state.yes_avg_price,
                    });
                    self.executeHedge(current_price) catch |err| {
                        log("对冲执行失败: {}", .{err});
                    };
                }
            } else {
                // 已对冲,可以考虑结束或等待下一轮
                log("已完成对冲,利润已锁定: ${d:.2}", .{self.state.locked_profit});

                // 等待市场结算或手动退出
                // 实际交易中,这里可以选择:
                // 1. 等待期权到期自动结算
                // 2. 如果有更好机会,可以平仓后开始新一轮
                self.state.running = false;
            }

            // 等待下一次检查
            std.Thread.sleep(self.config.poll_interval_ms * std.time.ns_per_ms);
        }

        log("=== 策略结束 ===", .{});
        self.printSummary();
    }

    /// 打印交易总结
    fn printSummary(self: *Self) void {
        log("", .{});
        log("=== 交易总结 ===", .{});
        log("YES 持仓: {d:.2} 份", .{self.state.yes_position});
        log("YES 成本: ${d:.2}", .{self.state.yes_cost});
        log("YES 均价: {d:.4}", .{self.state.yes_avg_price});
        log("是否对冲: {}", .{self.state.is_hedged});
        log("锁定利润: ${d:.2}", .{self.state.locked_profit});
        if (self.state.yes_cost > 0) {
            const roi = self.state.locked_profit / self.state.yes_cost * 100;
            log("投资回报率: {d:.1}%", .{roi});
        }
    }

    /// 停止策略
    pub fn stop(self: *Self) void {
        self.state.running = false;
    }
};

// ============================================================================
// 辅助函数
// ============================================================================

/// 解析价格字符串
fn parsePrice(price_str: []const u8) f64 {
    return std.fmt.parseFloat(f64, price_str) catch 0;
}

/// 日志输出
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

    std.debug.print("\n", .{});
    std.debug.print("╔══════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║     BTC 二元期权对冲套利策略 - Polymarket Trading Bot        ║\n", .{});
    std.debug.print("╠══════════════════════════════════════════════════════════════╣\n", .{});
    std.debug.print("║  策略: 抄底 YES + 反弹对冲 NO                                 ║\n", .{});
    std.debug.print("║  目标: 捕捉短期暴跌,锁定无风险利润                           ║\n", .{});
    std.debug.print("╚══════════════════════════════════════════════════════════════╝\n", .{});
    std.debug.print("\n", .{});

    // =========================================================================
    // 1. 加载环境变量 (优先从 .env 文件, 然后是系统环境变量)
    // =========================================================================

    std.debug.print("1. 加载配置...\n", .{});

    // 加载 .env 文件 (如果存在)
    var env = poly.loadEnvOrEmpty(allocator, ".env");
    defer env.deinit();

    // 检查是否成功加载 .env
    if (env.count() > 0) {
        std.debug.print("   从 .env 文件加载了 {d} 个配置项\n", .{env.count()});
    } else {
        std.debug.print("   未找到 .env 文件，使用系统环境变量\n", .{});
    }

    // 从 .env 或系统环境变量获取凭证
    const private_key = env.get("POLY_PRIVATE_KEY") orelse {
        std.debug.print("\n", .{});
        std.debug.print("   错误: 请设置 POLY_PRIVATE_KEY\n", .{});
        std.debug.print("\n", .{});
        std.debug.print("   方法一: 创建 .env 文件\n", .{});
        std.debug.print("   $ cp .env.example .env\n", .{});
        std.debug.print("   $ vim .env  # 编辑填入你的私钥\n", .{});
        std.debug.print("\n", .{});
        std.debug.print("   方法二: 设置环境变量\n", .{});
        std.debug.print("   $ export POLY_PRIVATE_KEY=your_private_key_without_0x\n", .{});
        std.debug.print("\n", .{});
        return error.MissingCredentials;
    };

    const api_key = env.get("POLY_API_KEY") orelse {
        std.debug.print("   错误: 请设置 POLY_API_KEY\n", .{});
        std.debug.print("   提示: 可通过 Polymarket API 或客户端获取\n", .{});
        return error.MissingCredentials;
    };

    const api_secret = env.get("POLY_API_SECRET") orelse {
        std.debug.print("   错误: 请设置 POLY_API_SECRET\n", .{});
        return error.MissingCredentials;
    };

    const api_passphrase = env.get("POLY_API_PASSPHRASE") orelse {
        std.debug.print("   错误: 请设置 POLY_API_PASSPHRASE\n", .{});
        return error.MissingCredentials;
    };

    // 市场配置 (需要替换为实际的 BTC 15分钟期权市场)
    const yes_token = env.get("POLY_YES_TOKEN") orelse {
        std.debug.print("\n", .{});
        std.debug.print("   错误: 请设置 POLY_YES_TOKEN (YES Token ID)\n", .{});
        std.debug.print("\n", .{});
        std.debug.print("   获取方法:\n", .{});
        std.debug.print("   1. 访问 Polymarket 市场页面\n", .{});
        std.debug.print("   2. 打开浏览器开发者工具 (F12)\n", .{});
        std.debug.print("   3. 在 Network 标签中找到 API 请求\n", .{});
        std.debug.print("   4. 查找 token_id 或 clob_token_ids\n", .{});
        std.debug.print("\n", .{});
        return error.MissingCredentials;
    };

    const no_token = env.get("POLY_NO_TOKEN") orelse {
        std.debug.print("   错误: 请设置 POLY_NO_TOKEN (NO Token ID)\n", .{});
        return error.MissingCredentials;
    };

    const condition_id = env.get("POLY_CONDITION_ID") orelse {
        std.debug.print("   错误: 请设置 POLY_CONDITION_ID (市场 Condition ID)\n", .{});
        return error.MissingCredentials;
    };

    // 从环境变量读取策略参数 (使用默认值)
    const use_testnet = env.getBool("POLY_USE_TESTNET", false);
    const sum_target = env.getFloat(f64, "STRATEGY_SUM_TARGET", 0.3);
    const move_threshold = env.getFloat(f64, "STRATEGY_MOVE_THRESHOLD", 0.01);
    const min_buy_price = env.getFloat(f64, "STRATEGY_MIN_BUY_PRICE", 0.15);
    const hedge_spread = env.getFloat(f64, "STRATEGY_HEDGE_SPREAD", 0.05);
    const max_position_size = env.getFloat(f64, "STRATEGY_MAX_POSITION", 100.0);
    const poll_interval_ms = env.getInt(u64, "STRATEGY_POLL_INTERVAL", 500);

    std.debug.print("   配置加载完成\n", .{});
    std.debug.print("   网络: {s}\n", .{if (use_testnet) "测试网 (Amoy)" else "主网 (Polygon)"});
    std.debug.print("\n", .{});

    // =========================================================================
    // 2. 初始化钱包和客户端
    // =========================================================================

    std.debug.print("2. 初始化钱包...\n", .{});

    // 创建钱包
    const wallet = Wallet.fromPrivateKeyHex(private_key) catch |err| {
        std.debug.print("   钱包初始化失败: {}\n", .{err});
        return err;
    };

    std.debug.print("   钱包地址: 0x", .{});
    for (wallet.address_bytes) |b| {
        std.debug.print("{x:0>2}", .{b});
    }
    std.debug.print("\n\n", .{});

    // 创建 API 凭证
    std.debug.print("3. 初始化 API 凭证...\n", .{});
    var creds = try ApiCreds.init(allocator, api_key, api_secret, api_passphrase);
    defer creds.deinit();
    std.debug.print("   API 凭证初始化完成\n\n", .{});

    // 创建客户端
    std.debug.print("4. 初始化 CLOB 客户端...\n", .{});
    var client = ClobClient.initWithAuth(allocator, .{}, &wallet, &creds);
    defer client.deinit();
    std.debug.print("   客户端初始化完成\n\n", .{});

    // =========================================================================
    // 3. 检查余额
    // =========================================================================

    std.debug.print("5. 检查账户余额...\n", .{});
    // 注意: 实际运行需要网络连接
    // const balance = try client.getBalanceAllowance(.{});
    // std.debug.print("   USDC 余额: {s}\n", .{balance.value.balance});
    std.debug.print("   (需要网络连接)\n\n", .{});

    // =========================================================================
    // 4. 策略配置
    // =========================================================================

    std.debug.print("6. 配置策略参数...\n", .{});

    const config = StrategyConfig{
        .yes_token_id = yes_token,
        .no_token_id = no_token,
        .condition_id = condition_id,

        // 从环境变量或 .env 文件读取，使用默认值作为后备
        .sum_target = sum_target,
        .move_threshold = move_threshold,
        .min_buy_price = min_buy_price,
        .hedge_spread = hedge_spread,
        .max_position_size = max_position_size,
        .poll_interval_ms = poll_interval_ms,
        .use_testnet = use_testnet,
    };

    std.debug.print("   累计目标: {d:.0}%\n", .{config.sum_target * 100});
    std.debug.print("   下跌阈值: {d:.1}%\n", .{config.move_threshold * 100});
    std.debug.print("   最低买价: {d:.2}\n", .{config.min_buy_price});
    std.debug.print("   对冲价差: {d:.2}\n", .{config.hedge_spread});
    std.debug.print("   最大仓位: ${d:.0}\n\n", .{config.max_position_size});

    // =========================================================================
    // 5. 启动策略
    // =========================================================================

    std.debug.print("7. 启动策略...\n", .{});
    std.debug.print("   按 Ctrl+C 停止\n\n", .{});

    var strategy = BtcHedgeStrategy.init(allocator, &client, &wallet, config);

    // 设置信号处理 (Ctrl+C)
    // 注意: Zig 标准库不直接支持信号处理,实际使用可能需要其他方式

    // 运行策略
    strategy.run() catch |err| {
        std.debug.print("策略运行错误: {}\n", .{err});
    };

    std.debug.print("\n策略已停止。\n", .{});
}

// ============================================================================
// 测试
// ============================================================================

test "parsePrice" {
    try std.testing.expectApproxEqAbs(@as(f64, 0.65), parsePrice("0.65"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.15), parsePrice("0.15"), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), parsePrice("invalid"), 0.001);
}

test "StrategyState.updateAvgPrice" {
    var state = StrategyState{};

    // 第一次买入: 100 份 @ 0.20
    state.updateAvgPrice(100, 0.20);
    try std.testing.expectApproxEqAbs(@as(f64, 100), state.yes_position, 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, 0.20), state.yes_avg_price, 0.001);

    // 第二次买入: 100 份 @ 0.10
    state.updateAvgPrice(100, 0.10);
    try std.testing.expectApproxEqAbs(@as(f64, 200), state.yes_position, 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, 0.15), state.yes_avg_price, 0.001); // (20+10)/200 = 0.15
}

test "StrategyConfig defaults" {
    const config = StrategyConfig{
        .yes_token_id = "123",
        .no_token_id = "456",
        .condition_id = "789",
    };

    try std.testing.expectApproxEqAbs(@as(f64, 0.3), config.sum_target, 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, 0.01), config.move_threshold, 0.001);
}
