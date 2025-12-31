//! 认证示例
//!
//! 演示 L1 (EIP-712) 和 L2 (HMAC) 认证的使用方法。
//!
//! L1 认证: 用于创建/派生 API Key，需要钱包签名
//! L2 认证: 用于常规 API 请求，需要 API 凭证
//!
//! 注意: 此示例需要有效的私钥才能运行。
//!
//! 运行: zig build run-example-auth

const std = @import("std");

// 导入模块
const root = @import("../src/root.zig");
const ClobClient = root.clob.ClobClient;
const Wallet = root.signer.Wallet;
const ApiCreds = root.auth.ApiCreds;
const L1Auth = root.auth.L1Auth;
const L2Auth = root.auth.L2Auth;

pub fn main() !void {
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Polymarket 认证示例 ===\n\n", .{});

    // =========================================================================
    // 1. 创建钱包
    // =========================================================================
    std.debug.print("1. 创建钱包\n", .{});
    std.debug.print("   从私钥创建钱包用于签名\n\n", .{});

    // 示例私钥（请勿在生产环境使用！）
    const private_key_hex = "0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318";
    const wallet = try Wallet.fromPrivateKeyHex(private_key_hex);

    const address = wallet.getAddressChecksumHex();
    std.debug.print("   钱包地址: {s}\n\n", .{&address});

    // =========================================================================
    // 2. L1 认证 - 生成 Header
    // =========================================================================
    std.debug.print("2. L1 认证 (EIP-712 签名)\n", .{});
    std.debug.print("   用于: 创建/派生 API Key\n\n", .{});

    const l1 = L1Auth.init(&wallet, .{ .chain_id = 137 }); // Polygon mainnet
    const l1_header = try l1.generateHeader();

    std.debug.print("   L1 Header:\n", .{});
    std.debug.print("     POLY-ADDRESS:   {s}\n", .{l1_header.getAddress()});
    std.debug.print("     POLY-SIGNATURE: {s}...{s}\n", .{ l1_header.getSignature()[0..10], l1_header.getSignature()[126..132] });
    std.debug.print("     POLY-TIMESTAMP: {s}\n", .{l1_header.getTimestamp()});
    std.debug.print("     POLY-NONCE:     {s}\n\n", .{l1_header.getNonce()});

    // =========================================================================
    // 3. L2 认证 - 生成 Header
    // =========================================================================
    std.debug.print("3. L2 认证 (HMAC-SHA256 签名)\n", .{});
    std.debug.print("   用于: 所有需要认证的 API 请求\n\n", .{});

    // 创建模拟的 API 凭证
    var creds = try ApiCreds.init(
        allocator,
        "example-api-key",
        "example-api-secret-base64",
        "example-passphrase",
    );
    defer creds.deinit();

    const l2 = L2Auth.init(&creds);
    const l2_header = try l2.generateHeader(.{
        .method = "GET",
        .path = "/data/orders",
        .body = null,
    });

    std.debug.print("   L2 Header:\n", .{});
    std.debug.print("     POLY-API-KEY:    {s}\n", .{l2_header.getApiKey()});
    std.debug.print("     POLY-SIGNATURE:  {s}\n", .{l2_header.getSignature()});
    std.debug.print("     POLY-TIMESTAMP:  {s}\n", .{l2_header.getTimestamp()});
    std.debug.print("     POLY-PASSPHRASE: {s}\n\n", .{l2_header.getPassphrase()});

    // =========================================================================
    // 4. 使用 ClobClient 进行认证
    // =========================================================================
    std.debug.print("4. 使用 ClobClient 进行认证\n\n", .{});

    std.debug.print("   方法 1: 初始化时设置认证\n", .{});
    std.debug.print("   ```\n", .{});
    std.debug.print("   var client = ClobClient.initWithAuth(\n", .{});
    std.debug.print("       allocator, .{{}}, &wallet, &creds\n", .{});
    std.debug.print("   );\n", .{});
    std.debug.print("   ```\n\n", .{});

    std.debug.print("   方法 2: 后续设置认证\n", .{});
    std.debug.print("   ```\n", .{});
    std.debug.print("   var client = ClobClient.init(allocator, .{{}});\n", .{});
    std.debug.print("   client.setWallet(&wallet);    // 设置钱包用于 L1\n", .{});
    std.debug.print("   client.setApiCreds(&creds);   // 设置凭证用于 L2\n", .{});
    std.debug.print("   ```\n\n", .{});

    // =========================================================================
    // 5. 获取 API 凭证流程
    // =========================================================================
    std.debug.print("5. 获取 API 凭证流程\n\n", .{});

    std.debug.print("   步骤 1: 创建客户端并设置钱包\n", .{});
    std.debug.print("   ```\n", .{});
    std.debug.print("   var client = ClobClient.init(allocator, .{{}});\n", .{});
    std.debug.print("   client.setWallet(&wallet);\n", .{});
    std.debug.print("   ```\n\n", .{});

    std.debug.print("   步骤 2: 创建或派生 API Key\n", .{});
    std.debug.print("   ```\n", .{});
    std.debug.print("   // 推荐: 先尝试派生，失败则创建\n", .{});
    std.debug.print("   var creds = try client.createOrDeriveApiKey();\n", .{});
    std.debug.print("   defer creds.deinit();\n", .{});
    std.debug.print("   \n", .{});
    std.debug.print("   // 或者单独调用:\n", .{});
    std.debug.print("   // var creds = try client.deriveApiKey();   // 派生已存在的\n", .{});
    std.debug.print("   // var creds = try client.createApiKey();   // 创建新的\n", .{});
    std.debug.print("   ```\n\n", .{});

    std.debug.print("   步骤 3: 设置凭证用于后续请求\n", .{});
    std.debug.print("   ```\n", .{});
    std.debug.print("   client.setApiCreds(&creds);\n", .{});
    std.debug.print("   \n", .{});
    std.debug.print("   // 现在可以调用需要认证的端点\n", .{});
    std.debug.print("   const orders = try client.getOpenOrders(.{{}});\n", .{});
    std.debug.print("   ```\n\n", .{});

    // =========================================================================
    // 6. 认证级别说明
    // =========================================================================
    std.debug.print("6. 认证级别说明\n\n", .{});

    std.debug.print("   L0 (无需认证):\n", .{});
    std.debug.print("     - 市场数据: getMarkets, getOrderBook, getPrice...\n", .{});
    std.debug.print("     - 服务器状态: getOk, getServerTime\n\n", .{});

    std.debug.print("   L1 (需要钱包签名):\n", .{});
    std.debug.print("     - API Key 管理: createApiKey, deriveApiKey\n", .{});
    std.debug.print("     - 订单签名 (EIP-712)\n\n", .{});

    std.debug.print("   L2 (需要 API 凭证):\n", .{});
    std.debug.print("     - 订单管理: postOrder, cancelOrder...\n", .{});
    std.debug.print("     - 交易历史: getTrades\n", .{});
    std.debug.print("     - 账户信息: getBalanceAllowance, getNotifications\n", .{});
    std.debug.print("     - RFQ 操作: createRfqRequest, acceptRfqQuote...\n\n", .{});

    std.debug.print("=== 完成 ===\n", .{});
}
