//! 测试下单 - 调试用

const std = @import("std");
const poly = @import("poly_sdk_zig");

const Wallet = poly.signer.Wallet;
const ClobClient = poly.clob.client.ClobClient;
const OrderBuilder = poly.OrderBuilder;
const Decimal = poly.Decimal;
const SignatureType = poly.order.types.SignatureType;

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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var env = poly.loadEnvOrEmpty(allocator, ".env");
    defer env.deinit();

    const private_key = env.get("POLY_PRIVATE_KEY") orelse return error.MissingCredentials;
    const wallet = Wallet.fromPrivateKeyHex(private_key) catch return error.InvalidKey;

    std.debug.print("EOA: {s}\n", .{wallet.getAddressChecksumHex()});

    const sig_type_val = env.getInt(u8, "WS_TRADER_SIGNATURE_TYPE", 2);
    const signature_type = SignatureType.fromU8(sig_type_val) orelse .POLY_GNOSIS_SAFE;
    const funder = if (env.get("POLY_ADDRESS")) |addr| parseFunderAddress(addr) else null;

    std.debug.print("签名类型: {d}\n", .{sig_type_val});
    if (funder != null) {
        std.debug.print("Funder: 已设置\n", .{});
    }

    var client = ClobClient.init(allocator, .{});
    defer client.deinit();
    client.setWallet(&wallet);

    var creds = client.createOrDeriveApiKey() catch return error.ApiError;
    defer creds.deinit();
    client.setApiCreds(&creds);

    // 检查余额
    std.debug.print("\n=== 余额 ===\n", .{});
    const bal_result = client.getBalanceAllowance(.{
        .asset_type = .COLLATERAL,
        .signature_type = sig_type_val,
    }) catch return error.ApiError;
    defer bal_result.deinit();

    const bal_val = std.fmt.parseInt(u64, bal_result.value.balance orelse "0", 10) catch 0;
    const allow_val = std.fmt.parseInt(u64, bal_result.value.allowance orelse "0", 10) catch 0;

    std.debug.print("余额: ${d:.2}\n", .{@as(f64, @floatFromInt(bal_val)) / 1_000_000.0});
    std.debug.print("Allowance: ${d:.2}\n", .{@as(f64, @floatFromInt(allow_val)) / 1_000_000.0});

    if (allow_val == 0) {
        std.debug.print("\n⚠️ Allowance 为 0，无法下单！\n", .{});
        std.debug.print("请在 Polymarket 网站授权 USDC\n", .{});
        return;
    }

    // 硬编码一个测试 token ID (用你实际的市场)
    const test_token_id = "52114319501245915516055106046884209969926127482827954674443846427813813222426";

    std.debug.print("\n=== 创建订单 ===\n", .{});
    var builder = OrderBuilder.init(&wallet, .{
        .chain_id = 137,
        .funder = funder,
    });

    const order = builder.createOrder(.{
        .token_id = test_token_id,
        .price = try Decimal.fromString("0.01"), // 极低价格，不会成交
        .size = try Decimal.fromString("1"),
        .side = .BUY,
    }, .{
        .tick_size = .@"0.01",
        .neg_risk = false,
        .signature_type = signature_type,
    }) catch |err| {
        std.debug.print("创建订单失败: {}\n", .{err});
        return;
    };

    var buffers = poly.order.types.SignedOrder.OrderDataBuffers{};
    const od = order.toOrderData(&buffers);
    std.debug.print("maker: {s}\n", .{od.maker});
    std.debug.print("signer: {s}\n", .{od.signer});
    std.debug.print("signatureType: {d}\n", .{od.signatureType});

    std.debug.print("\n=== 提交订单 ===\n", .{});
    const response = client.postOrder(&order, .GTC) catch |err| {
        std.debug.print("下单失败: {}\n", .{err});
        return;
    };

    if (response.success) {
        std.debug.print("✅ 成功! ID: {s}\n", .{response.orderID orelse "N/A"});
    } else {
        std.debug.print("❌ 失败: {s}\n", .{response.errorMsg orelse "未知"});
    }
}
