//! 检查钱包余额和 allowance

const std = @import("std");
const poly = @import("poly_sdk_zig");

const Wallet = poly.signer.Wallet;
const ClobClient = poly.clob.client.ClobClient;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 加载配置
    var env = poly.loadEnvOrEmpty(allocator, ".env");
    defer env.deinit();

    const private_key = env.get("POLY_PRIVATE_KEY") orelse {
        std.debug.print("错误: 需要设置 POLY_PRIVATE_KEY\n", .{});
        return error.MissingCredentials;
    };

    // 初始化钱包
    const wallet = Wallet.fromPrivateKeyHex(private_key) catch |err| {
        std.debug.print("钱包初始化失败: {}\n", .{err});
        return err;
    };

    const addr = wallet.getAddressChecksumHex();
    std.debug.print("钱包地址: {s}\n", .{addr});

    // 初始化客户端
    var client = ClobClient.init(allocator, .{});
    defer client.deinit();
    client.setWallet(&wallet);

    // 获取 API 凭证
    std.debug.print("\n正在获取 API 凭证...\n", .{});
    var creds = client.createOrDeriveApiKey() catch |err| {
        std.debug.print("获取 API 凭证失败: {}\n", .{err});
        return err;
    };
    defer creds.deinit();

    client.setApiCreds(&creds);

    // 获取 USDC 余额 (COLLATERAL 类型)
    std.debug.print("\n查询 USDC 余额...\n", .{});
    var usdc_balance_parsed = client.getBalanceAllowance(.{
        .asset_type = .COLLATERAL,
    }) catch |err| {
        std.debug.print("查询 USDC 余额失败: {}\n", .{err});
        return err;
    };
    defer usdc_balance_parsed.deinit();
    const usdc_balance = usdc_balance_parsed.value;

    // 解析并显示余额
    const balance_str = usdc_balance.balance orelse "0";
    const allowance_str = usdc_balance.allowance orelse "0";

    std.debug.print("\n", .{});
    std.debug.print("╔═══════════════════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║                           钱 包 状 态                                     ║\n", .{});
    std.debug.print("╠═══════════════════════════════════════════════════════════════════════════╣\n", .{});
    std.debug.print("║  地址: {s}                     ║\n", .{addr});
    std.debug.print("╠═══════════════════════════════════════════════════════════════════════════╣\n", .{});
    std.debug.print("║  余额 (原始):     {s}\n", .{balance_str});
    std.debug.print("║  Allowance (原始): {s}\n", .{allowance_str});
    std.debug.print("╚═══════════════════════════════════════════════════════════════════════════╝\n", .{});

    // 转换为可读格式 (除以 10^6)
    const balance_val = std.fmt.parseInt(u64, balance_str, 10) catch 0;
    const balance_usdc = @as(f64, @floatFromInt(balance_val)) / 1_000_000.0;

    std.debug.print("\n诊断结果:\n", .{});
    if (balance_val == 0) {
        std.debug.print("  余额为 0 - 需要向钱包转入 USDC\n", .{});
        std.debug.print("\n  解决方法:\n", .{});
        std.debug.print("  1. 在 Polygon 网络上向以下地址转入 USDC:\n", .{});
        std.debug.print("     {s}\n", .{addr});
        std.debug.print("  2. 可以通过以下方式获取 Polygon USDC:\n", .{});
        std.debug.print("     - 从中心化交易所提取到 Polygon\n", .{});
        std.debug.print("     - 使用跨链桥\n", .{});
        std.debug.print("     - 使用 Polymarket 充值功能\n", .{});
    } else {
        std.debug.print("  余额: ${d:.6} USDC\n", .{balance_usdc});
    }

    std.debug.print("\n相关链接:\n", .{});
    std.debug.print("  Polygonscan: https://polygonscan.com/address/{s}\n", .{addr});
    std.debug.print("  Polymarket:  https://polymarket.com\n", .{});
}
