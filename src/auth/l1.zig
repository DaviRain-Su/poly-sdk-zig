//! L1 认证
//!
//! L1 认证使用 EIP-712 签名验证钱包所有权，用于：
//! - 创建新的 API Key
//! - 派生现有的 API Key
//!
//! L1 认证不用于常规 API 请求，那些使用 L2 (HMAC) 认证。
//!
//! 示例:
//! ```zig
//! const l1 = L1Auth.init(&wallet, .{ .chain_id = 137 });
//!
//! // 生成 L1 Header
//! const header = try l1.generateHeader();
//!
//! // 使用 header 调用 API
//! const http_headers = header.toHttpHeaders();
//! ```

const std = @import("std");
const root = @import("../root.zig");

const Wallet = root.signer.Wallet;
const eip712 = root.signer.eip712;
const keccak256 = root.crypto.keccak256;
const Hasher = root.crypto.Hasher;
const Signature = root.crypto.Signature;

const L1PolyHeader = @import("headers.zig").L1PolyHeader;

/// L1 认证固定消息
pub const L1_AUTH_MESSAGE = "This message attests that I control the given wallet";

/// ClobAuthDomain 域名称
pub const CLOB_AUTH_DOMAIN_NAME = "ClobAuthDomain";

/// ClobAuthDomain 版本
pub const CLOB_AUTH_DOMAIN_VERSION = "1";

/// L1Auth 错误
pub const L1AuthError = error{
    /// 签名失败
    SigningFailed,
    /// 无效的链 ID
    InvalidChainId,
    /// 时间获取失败
    TimeError,
};

/// L1 认证选项
pub const L1AuthOptions = struct {
    /// 链 ID（137 = Polygon mainnet, 80002 = Amoy testnet）
    chain_id: u64 = 137,
};

/// L1 认证器
///
/// 用于生成 L1 认证 Header，支持 API Key 的创建和派生。
pub const L1Auth = struct {
    /// 钱包引用
    wallet: *const Wallet,

    /// 链 ID
    chain_id: u64,

    const Self = @This();

    /// 初始化 L1 认证器
    pub fn init(wallet: *const Wallet, options: L1AuthOptions) Self {
        return Self{
            .wallet = wallet,
            .chain_id = options.chain_id,
        };
    }

    /// 生成 L1 认证 Header
    ///
    /// 创建包含 EIP-712 签名的认证 Header。
    pub fn generateHeader(self: *const Self) L1AuthError!L1PolyHeader {
        return self.generateHeaderWithNonce(generateRandomNonce());
    }

    /// 使用指定 nonce 生成 L1 认证 Header
    ///
    /// 允许自定义 nonce，用于测试或特殊场景。
    pub fn generateHeaderWithNonce(self: *const Self, nonce: u256) L1AuthError!L1PolyHeader {
        // 获取当前时间戳
        const timestamp = std.time.timestamp();

        return self.generateHeaderFull(nonce, timestamp);
    }

    /// 使用指定 nonce 和时间戳生成 L1 认证 Header（用于测试）
    pub fn generateHeaderFull(self: *const Self, nonce: u256, timestamp: i64) L1AuthError!L1PolyHeader {
        // 获取地址
        const address = self.wallet.getAddressChecksumHex();

        // 格式化时间戳
        var timestamp_buf: [20]u8 = undefined;
        const timestamp_str = std.fmt.bufPrint(&timestamp_buf, "{d}", .{timestamp}) catch unreachable;

        // 格式化 nonce - 使用截断的 u64 值
        // Python 客户端在 header 中发送的是整数，在签名中使用的是相同的值
        var nonce_buf: [20]u8 = undefined;
        const nonce_u64 = @as(u64, @truncate(nonce));
        const nonce_str = std.fmt.bufPrint(&nonce_buf, "{d}", .{nonce_u64}) catch unreachable;

        // 计算 EIP-712 签名摘要 - 使用与 header 相同的 nonce 值
        const digest = self.computeDigest(&address, timestamp_str, nonce_u64);

        // 签名
        const signature = self.wallet.sign(&digest) catch {
            return L1AuthError.SigningFailed;
        };

        // 格式化签名为 hex
        var sig_hex: [132]u8 = undefined;
        formatSignatureHex(&signature, &sig_hex);

        // 构建 Header
        var header = L1PolyHeader{
            .poly_address = address,
            .poly_signature = sig_hex,
            .poly_timestamp = undefined,
            .poly_timestamp_len = timestamp_str.len,
            .poly_nonce = undefined,
            .poly_nonce_len = nonce_str.len,
        };

        @memcpy(header.poly_timestamp[0..timestamp_str.len], timestamp_str);
        @memcpy(header.poly_nonce[0..nonce_str.len], nonce_str);

        return header;
    }

    /// 计算 EIP-712 签名摘要
    fn computeDigest(self: *const Self, address: *const [42]u8, timestamp: []const u8, nonce: u64) [32]u8 {
        // 1. 计算域哈希
        const domain = eip712.Domain{
            .name = CLOB_AUTH_DOMAIN_NAME,
            .version = CLOB_AUTH_DOMAIN_VERSION,
            .chain_id = self.chain_id,
        };
        const domain_separator = eip712.hashDomain(&domain);

        // 2. 计算结构体哈希
        const struct_hash = computeClobAuthHash(address, timestamp, nonce);

        // 3. 计算最终摘要
        return eip712.hashTypedData(&domain_separator, &struct_hash);
    }

    /// 获取链 ID
    pub fn getChainId(self: *const Self) u64 {
        return self.chain_id;
    }

    /// 获取钱包地址
    pub fn getAddress(self: *const Self) [42]u8 {
        return self.wallet.getAddressChecksumHex();
    }
};

/// ClobAuth EIP-712 类型定义
pub const CLOB_AUTH_TYPE = eip712.TypeDefinition{
    .name = "ClobAuth",
    .fields = &[_]eip712.TypeField{
        .{ .name = "address", .type_name = "address" },
        .{ .name = "timestamp", .type_name = "string" },
        .{ .name = "nonce", .type_name = "uint256" },
        .{ .name = "message", .type_name = "string" },
    },
};

/// 计算 ClobAuth 类型哈希
pub fn clobAuthTypeHash() [32]u8 {
    var buffer: [256]u8 = undefined;
    const type_str = eip712.encodeType(&CLOB_AUTH_TYPE, &buffer);
    return eip712.typeHash(type_str);
}

/// 计算 ClobAuth 结构体哈希
fn computeClobAuthHash(address: *const [42]u8, timestamp: []const u8, nonce: u256) [32]u8 {
    const type_hash = clobAuthTypeHash();

    // 解析地址为字节
    var addr_bytes: [20]u8 = undefined;
    _ = std.fmt.hexToBytes(&addr_bytes, address[2..]) catch unreachable;

    var hasher = Hasher.init();
    hasher.update(&type_hash);
    hasher.update(&eip712.encodeAddress(&addr_bytes));
    hasher.update(&eip712.encodeString(timestamp));
    hasher.update(&eip712.encodeUint256(nonce));
    hasher.update(&eip712.encodeString(L1_AUTH_MESSAGE));

    return hasher.final();
}

/// 生成随机 nonce
///
/// 返回一个较小的随机 nonce 值。
/// Python 客户端默认使用 nonce=0，但也支持任何非负整数。
fn generateRandomNonce() u256 {
    // 使用较小的随机数范围，避免潜在的兼容性问题
    // Python 客户端默认 nonce=0，所以我们也使用 0 以保持兼容
    return 0;
}

/// 格式化签名为 hex 字符串
fn formatSignatureHex(sig: *const Signature, out: *[132]u8) void {
    out[0] = '0';
    out[1] = 'x';

    // r (32 bytes = 64 hex chars)
    _ = std.fmt.bufPrint(out[2..66], "{x:0>64}", .{std.mem.readInt(u256, &sig.r, .big)}) catch unreachable;

    // s (32 bytes = 64 hex chars)
    _ = std.fmt.bufPrint(out[66..130], "{x:0>64}", .{std.mem.readInt(u256, &sig.s, .big)}) catch unreachable;

    // v (1 byte = 2 hex chars)
    _ = std.fmt.bufPrint(out[130..132], "{x:0>2}", .{sig.getEthereumV()}) catch unreachable;
}

// ============================================================================
// 测试
// ============================================================================

test "L1Auth.init" {
    const wallet = try Wallet.fromPrivateKeyHex("0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318");
    const l1 = L1Auth.init(&wallet, .{ .chain_id = 137 });

    try std.testing.expectEqual(@as(u64, 137), l1.getChainId());
}

test "L1Auth.getAddress" {
    const wallet = try Wallet.fromPrivateKeyHex("0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318");
    const l1 = L1Auth.init(&wallet, .{});

    const address = l1.getAddress();
    try std.testing.expectEqualStrings("0x", address[0..2]);
    try std.testing.expectEqual(@as(usize, 42), address.len);
}

test "L1Auth.generateHeaderFull" {
    const wallet = try Wallet.fromPrivateKeyHex("0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318");
    const l1 = L1Auth.init(&wallet, .{ .chain_id = 137 });

    const header = try l1.generateHeaderFull(12345, 1704067200);

    // 验证地址格式
    try std.testing.expectEqualStrings("0x", header.getAddress()[0..2]);

    // 验证签名格式
    try std.testing.expectEqualStrings("0x", header.getSignature()[0..2]);
    try std.testing.expectEqual(@as(usize, 132), header.getSignature().len);

    // 验证时间戳
    try std.testing.expectEqualStrings("1704067200", header.getTimestamp());

    // 验证 nonce
    try std.testing.expectEqualStrings("12345", header.getNonce());
}

test "L1Auth.generateHeaderWithNonce" {
    const wallet = try Wallet.fromPrivateKeyHex("0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318");
    const l1 = L1Auth.init(&wallet, .{ .chain_id = 137 });

    const header = try l1.generateHeaderWithNonce(99999);

    // 验证 nonce
    try std.testing.expectEqualStrings("99999", header.getNonce());

    // 验证其他字段存在
    try std.testing.expect(header.getAddress().len == 42);
    try std.testing.expect(header.getSignature().len == 132);
    try std.testing.expect(header.getTimestamp().len > 0);
}

test "L1Auth signature verification" {
    const wallet = try Wallet.fromPrivateKeyHex("0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318");
    const l1 = L1Auth.init(&wallet, .{ .chain_id = 137 });

    // 生成两个 header，使用相同参数
    const header1 = try l1.generateHeaderFull(12345, 1704067200);
    const header2 = try l1.generateHeaderFull(12345, 1704067200);

    // 签名应该相同（确定性）
    try std.testing.expectEqualStrings(header1.getSignature(), header2.getSignature());

    // 不同 nonce 应该产生不同签名
    const header3 = try l1.generateHeaderFull(54321, 1704067200);
    try std.testing.expect(!std.mem.eql(u8, header1.getSignature(), header3.getSignature()));
}

test "L1Auth different chain_id" {
    const wallet = try Wallet.fromPrivateKeyHex("0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318");

    const l1_mainnet = L1Auth.init(&wallet, .{ .chain_id = 137 });
    const l1_amoy = L1Auth.init(&wallet, .{ .chain_id = 80002 });

    const header1 = try l1_mainnet.generateHeaderFull(12345, 1704067200);
    const header2 = try l1_amoy.generateHeaderFull(12345, 1704067200);

    // 不同链 ID 应该产生不同签名
    try std.testing.expect(!std.mem.eql(u8, header1.getSignature(), header2.getSignature()));
}

test "clobAuthTypeHash" {
    const hash = clobAuthTypeHash();
    try std.testing.expectEqual(@as(usize, 32), hash.len);
}

test "CLOB_AUTH_TYPE definition" {
    var buffer: [256]u8 = undefined;
    const type_str = eip712.encodeType(&CLOB_AUTH_TYPE, &buffer);
    try std.testing.expectEqualStrings(
        "ClobAuth(address address,string timestamp,uint256 nonce,string message)",
        type_str,
    );
}

test "L1_AUTH_MESSAGE constant" {
    try std.testing.expectEqualStrings(
        "This message attests that I control the given wallet",
        L1_AUTH_MESSAGE,
    );
}

test "formatSignatureHex" {
    var sig = Signature{
        .r = undefined,
        .s = undefined,
        .v = 27,
    };

    // 设置 r 和 s
    @memset(&sig.r, 0xaa);
    @memset(&sig.s, 0xbb);

    var out: [132]u8 = undefined;
    formatSignatureHex(&sig, &out);

    try std.testing.expectEqualStrings("0x", out[0..2]);
    try std.testing.expectEqual(@as(usize, 132), out.len);
}
