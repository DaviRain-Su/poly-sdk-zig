//! L1 认证调试工具
//!
//! 用于调试 L1 认证问题，显示详细的请求和响应信息。
//! 输出中间哈希值，便于与 Python 实现对比。

const std = @import("std");
const poly = @import("poly_sdk_zig");

const Wallet = poly.Wallet;
const L1Auth = poly.auth.L1Auth;
const l1_mod = poly.auth.l1;
const eip712 = poly.signer.eip712;
const keccak256 = poly.crypto.keccak256;
const Hasher = poly.crypto.Hasher;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n", .{});
    std.debug.print("======================================================================\n", .{});
    std.debug.print("L1 认证调试工具 (Zig)\n", .{});
    std.debug.print("======================================================================\n", .{});
    std.debug.print("\n", .{});

    // 加载配置
    var env = poly.loadEnvOrEmpty(allocator, ".env");
    defer env.deinit();

    const private_key = env.get("POLY_PRIVATE_KEY") orelse {
        std.debug.print("错误: 请在 .env 中设置 POLY_PRIVATE_KEY\n", .{});
        return error.MissingCredentials;
    };

    // 创建钱包
    const wallet = Wallet.fromPrivateKeyHex(private_key) catch |err| {
        std.debug.print("钱包创建失败: {}\n", .{err});
        return err;
    };

    const address = wallet.getAddressChecksumHex();
    std.debug.print("地址: {s}\n", .{&address});
    std.debug.print("\n", .{});

    // 使用固定参数便于调试
    const timestamp: i64 = std.time.timestamp();
    const nonce: u256 = 0;
    const chain_id: u64 = 137;
    const message = l1_mod.L1_AUTH_MESSAGE;

    std.debug.print("Timestamp: {d}\n", .{timestamp});
    std.debug.print("Nonce: {d}\n", .{nonce});
    std.debug.print("Chain ID: {d}\n", .{chain_id});
    std.debug.print("Message: {s}\n", .{message});
    std.debug.print("\n", .{});

    // ========================================
    // 域 (Domain) 计算
    // ========================================
    std.debug.print("----------------------------------------------------------------------\n", .{});
    std.debug.print("域 (Domain)\n", .{});
    std.debug.print("----------------------------------------------------------------------\n", .{});
    std.debug.print("  name: {s}\n", .{l1_mod.CLOB_AUTH_DOMAIN_NAME});
    std.debug.print("  version: {s}\n", .{l1_mod.CLOB_AUTH_DOMAIN_VERSION});
    std.debug.print("  chainId: {d}\n", .{chain_id});
    std.debug.print("\n", .{});

    // 域类型字符串
    const domain = eip712.Domain{
        .name = l1_mod.CLOB_AUTH_DOMAIN_NAME,
        .version = l1_mod.CLOB_AUTH_DOMAIN_VERSION,
        .chain_id = chain_id,
    };

    var domain_type_buf: [256]u8 = undefined;
    const domain_type_str = eip712.encodeDomainType(&domain, &domain_type_buf);
    std.debug.print("域类型字符串: {s}\n", .{domain_type_str});

    const domain_type_hash = eip712.typeHash(domain_type_str);
    std.debug.print("域类型哈希: 0x", .{});
    for (domain_type_hash) |b| {
        std.debug.print("{x:0>2}", .{b});
    }
    std.debug.print("\n\n", .{});

    // 域分隔符
    const domain_separator = eip712.hashDomain(&domain);
    std.debug.print("域分隔符哈希 (domain separator): 0x", .{});
    for (domain_separator) |b| {
        std.debug.print("{x:0>2}", .{b});
    }
    std.debug.print("\n\n", .{});

    // ========================================
    // 消息结构 (ClobAuth) 计算
    // ========================================
    std.debug.print("----------------------------------------------------------------------\n", .{});
    std.debug.print("消息结构 (ClobAuth)\n", .{});
    std.debug.print("----------------------------------------------------------------------\n", .{});
    std.debug.print("  address: {s}\n", .{&address});
    std.debug.print("  timestamp: \"{d}\"\n", .{timestamp});
    std.debug.print("  nonce: {d}\n", .{nonce});
    std.debug.print("  message: \"{s}\"\n", .{message});
    std.debug.print("\n", .{});

    // ClobAuth 类型字符串
    var clob_auth_type_buf: [256]u8 = undefined;
    const clob_auth_type_str = eip712.encodeType(&l1_mod.CLOB_AUTH_TYPE, &clob_auth_type_buf);
    std.debug.print("ClobAuth 类型字符串: {s}\n", .{clob_auth_type_str});

    const clob_auth_type_hash = l1_mod.clobAuthTypeHash();
    std.debug.print("ClobAuth 类型哈希: 0x", .{});
    for (clob_auth_type_hash) |b| {
        std.debug.print("{x:0>2}", .{b});
    }
    std.debug.print("\n\n", .{});

    // 字段编码
    std.debug.print("字段编码:\n", .{});

    // address 编码
    var addr_bytes: [20]u8 = undefined;
    _ = std.fmt.hexToBytes(&addr_bytes, address[2..]) catch unreachable;
    const addr_encoded = eip712.encodeAddress(&addr_bytes);
    std.debug.print("  address ABI 编码: 0x", .{});
    for (addr_encoded) |b| {
        std.debug.print("{x:0>2}", .{b});
    }
    std.debug.print("\n", .{});

    // timestamp 编码
    var timestamp_buf: [20]u8 = undefined;
    const timestamp_str = std.fmt.bufPrint(&timestamp_buf, "{d}", .{timestamp}) catch unreachable;
    const timestamp_hash = eip712.encodeString(timestamp_str);
    std.debug.print("  timestamp (keccak256 of \"{s}\"): 0x", .{timestamp_str});
    for (timestamp_hash) |b| {
        std.debug.print("{x:0>2}", .{b});
    }
    std.debug.print("\n", .{});

    // nonce 编码
    const nonce_encoded = eip712.encodeUint256(nonce);
    std.debug.print("  nonce (uint256): 0x", .{});
    for (nonce_encoded) |b| {
        std.debug.print("{x:0>2}", .{b});
    }
    std.debug.print("\n", .{});

    // message 编码
    const message_hash = eip712.encodeString(message);
    std.debug.print("  message (keccak256 of \"{s}\"): 0x", .{message});
    for (message_hash) |b| {
        std.debug.print("{x:0>2}", .{b});
    }
    std.debug.print("\n\n", .{});

    // 计算结构体哈希
    // structHash = keccak256(typeHash || encodeData)
    var struct_hasher = Hasher.init();
    struct_hasher.update(&clob_auth_type_hash);
    struct_hasher.update(&addr_encoded);
    struct_hasher.update(&timestamp_hash);
    struct_hasher.update(&nonce_encoded);
    struct_hasher.update(&message_hash);
    const struct_hash = struct_hasher.final();

    std.debug.print("结构体哈希 (struct hash): 0x", .{});
    for (struct_hash) |b| {
        std.debug.print("{x:0>2}", .{b});
    }
    std.debug.print("\n\n", .{});

    // 计算签名摘要
    // digest = keccak256("\x19\x01" || domainSeparator || structHash)
    const digest = eip712.hashTypedData(&domain_separator, &struct_hash);
    std.debug.print("签名摘要 (digest): 0x", .{});
    for (digest) |b| {
        std.debug.print("{x:0>2}", .{b});
    }
    std.debug.print("\n\n", .{});

    // ========================================
    // 生成签名
    // ========================================
    std.debug.print("----------------------------------------------------------------------\n", .{});
    std.debug.print("签名\n", .{});
    std.debug.print("----------------------------------------------------------------------\n", .{});

    const l1 = L1Auth.init(&wallet, .{ .chain_id = 137 });
    const header = l1.generateHeaderFull(nonce, timestamp) catch |err| {
        std.debug.print("Header 生成失败: {}\n", .{err});
        return err;
    };

    std.debug.print("完整签名: {s}\n", .{header.getSignature()});
    std.debug.print("\n", .{});

    // ========================================
    // HTTP Headers
    // ========================================
    std.debug.print("----------------------------------------------------------------------\n", .{});
    std.debug.print("HTTP Headers\n", .{});
    std.debug.print("----------------------------------------------------------------------\n", .{});
    std.debug.print("POLY_ADDRESS: {s}\n", .{header.getAddress()});
    std.debug.print("POLY_SIGNATURE: {s}\n", .{header.getSignature()});
    std.debug.print("POLY_TIMESTAMP: {s}\n", .{header.getTimestamp()});
    std.debug.print("POLY_NONCE: {s}\n", .{header.getNonce()});
    std.debug.print("\n", .{});

    // ========================================
    // curl 测试
    // ========================================
    std.debug.print("----------------------------------------------------------------------\n", .{});
    std.debug.print("curl 命令\n", .{});
    std.debug.print("----------------------------------------------------------------------\n", .{});

    // 构建 curl 命令
    var curl_cmd = try std.ArrayList(u8).initCapacity(allocator, 1024);
    defer curl_cmd.deinit(allocator);

    try curl_cmd.appendSlice(allocator, "curl -s -X GET 'https://clob.polymarket.com/auth/derive-api-key' \\\n");
    try curl_cmd.appendSlice(allocator, "  -H 'Accept: application/json' \\\n");
    try curl_cmd.appendSlice(allocator, "  -H 'Content-Type: application/json' \\\n");

    try curl_cmd.appendSlice(allocator, "  -H 'POLY_ADDRESS: ");
    try curl_cmd.appendSlice(allocator, header.getAddress());
    try curl_cmd.appendSlice(allocator, "' \\\n");

    try curl_cmd.appendSlice(allocator, "  -H 'POLY_SIGNATURE: ");
    try curl_cmd.appendSlice(allocator, header.getSignature());
    try curl_cmd.appendSlice(allocator, "' \\\n");

    try curl_cmd.appendSlice(allocator, "  -H 'POLY_TIMESTAMP: ");
    try curl_cmd.appendSlice(allocator, header.getTimestamp());
    try curl_cmd.appendSlice(allocator, "' \\\n");

    try curl_cmd.appendSlice(allocator, "  -H 'POLY_NONCE: ");
    try curl_cmd.appendSlice(allocator, header.getNonce());
    try curl_cmd.appendSlice(allocator, "'");

    std.debug.print("{s}\n\n", .{curl_cmd.items});

    // 执行 curl（可选）
    std.debug.print("----------------------------------------------------------------------\n", .{});
    std.debug.print("API 响应\n", .{});
    std.debug.print("----------------------------------------------------------------------\n", .{});

    // 构建单行命令
    var curl_exec = try std.ArrayList(u8).initCapacity(allocator, 1024);
    defer curl_exec.deinit(allocator);

    try curl_exec.appendSlice(allocator, "curl -s -X GET 'https://clob.polymarket.com/auth/derive-api-key' ");
    try curl_exec.appendSlice(allocator, "-H 'Accept: application/json' ");
    try curl_exec.appendSlice(allocator, "-H 'Content-Type: application/json' ");
    try curl_exec.appendSlice(allocator, "-H 'POLY_ADDRESS: ");
    try curl_exec.appendSlice(allocator, header.getAddress());
    try curl_exec.appendSlice(allocator, "' ");
    try curl_exec.appendSlice(allocator, "-H 'POLY_SIGNATURE: ");
    try curl_exec.appendSlice(allocator, header.getSignature());
    try curl_exec.appendSlice(allocator, "' ");
    try curl_exec.appendSlice(allocator, "-H 'POLY_TIMESTAMP: ");
    try curl_exec.appendSlice(allocator, header.getTimestamp());
    try curl_exec.appendSlice(allocator, "' ");
    try curl_exec.appendSlice(allocator, "-H 'POLY_NONCE: ");
    try curl_exec.appendSlice(allocator, header.getNonce());
    try curl_exec.appendSlice(allocator, "'");

    var child = std.process.Child.init(&[_][]const u8{ "sh", "-c", curl_exec.items }, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    const stdout = child.stdout.?.readToEndAlloc(allocator, 10 * 1024) catch "";
    defer if (stdout.len > 0) allocator.free(stdout);

    _ = child.wait() catch |err| {
        std.debug.print("curl 执行失败: {}\n", .{err});
        return err;
    };

    std.debug.print("{s}\n", .{stdout});
}
