//! 加密模块
//!
//! 提供 Polymarket 所需的加密原语：
//! - Keccak256 哈希（以太坊兼容）
//! - secp256k1 ECDSA 签名
//! - HMAC-SHA256 消息认证
//!
//! 示例:
//! ```zig
//! const crypto = @import("crypto");
//!
//! // Keccak256 哈希
//! const hash = crypto.keccak256("hello");
//!
//! // ECDSA 签名
//! const private_key = try crypto.PrivateKey.fromHex("0x...");
//! const signature = try private_key.sign(&message_hash);
//!
//! // HMAC-SHA256
//! const mac = crypto.hmacSha256("secret", "message");
//! ```

const std = @import("std");

// 导出子模块
pub const keccak = @import("keccak.zig");
pub const hmac = @import("hmac.zig");
pub const ecdsa = @import("ecdsa.zig");

// ============================================================================
// Keccak256 便捷导出
// ============================================================================

/// Keccak256 哈希类型
pub const Hash = keccak.Hash;

/// Keccak256 哈希器
pub const Hasher = keccak.Hasher;

/// 计算 Keccak256 哈希
pub const keccak256 = keccak.keccak256;

/// 计算多个数据块的 Keccak256 哈希
pub const keccak256Multi = keccak.keccak256Multi;

// ============================================================================
// HMAC-SHA256 便捷导出
// ============================================================================

/// HMAC-SHA256 消息认证码类型
pub const Mac = hmac.Mac;

/// HMAC-SHA256 认证器
pub const Hmac = hmac.Hmac;

/// 计算 HMAC-SHA256
pub const hmacSha256 = hmac.hmacSha256;

/// 将 MAC 编码为 Base64
pub const macToBase64 = hmac.toBase64;

/// 将 MAC 编码为 Base64（分配内存）
pub const macToBase64Alloc = hmac.toBase64Alloc;

/// 验证 HMAC
pub const hmacVerify = hmac.verify;

// ============================================================================
// ECDSA 便捷导出
// ============================================================================

/// 私钥
pub const PrivateKey = ecdsa.PrivateKey;

/// 公钥
pub const PublicKey = ecdsa.PublicKey;

/// 签名
pub const Signature = ecdsa.Signature;

/// 签名错误
pub const SignError = ecdsa.SignError;

/// 验证错误
pub const VerifyError = ecdsa.VerifyError;

// ============================================================================
// 常量
// ============================================================================

/// 私钥长度
pub const PRIVATE_KEY_LENGTH = ecdsa.PRIVATE_KEY_LENGTH;

/// 未压缩公钥长度
pub const PUBLIC_KEY_UNCOMPRESSED_LENGTH = ecdsa.PUBLIC_KEY_UNCOMPRESSED_LENGTH;

/// 压缩公钥长度
pub const PUBLIC_KEY_COMPRESSED_LENGTH = ecdsa.PUBLIC_KEY_COMPRESSED_LENGTH;

/// 签名长度
pub const SIGNATURE_LENGTH = ecdsa.SIGNATURE_LENGTH;

/// 地址长度
pub const ADDRESS_LENGTH = ecdsa.ADDRESS_LENGTH;

/// 哈希长度
pub const HASH_LENGTH = keccak.HASH_LENGTH;

/// MAC 长度
pub const MAC_LENGTH = hmac.MAC_LENGTH;

/// Base64 编码后的 MAC 长度
pub const MAC_BASE64_LENGTH = hmac.BASE64_ENCODED_LENGTH;

// ============================================================================
// 测试
// ============================================================================

test "crypto module exports" {
    // 测试 keccak256
    const hash = keccak256("hello");
    try std.testing.expectEqual(@as(usize, 32), hash.len);

    // 测试 hmacSha256
    const mac = hmacSha256("secret", "message");
    try std.testing.expectEqual(@as(usize, 32), mac.len);

    // 测试 PrivateKey
    const pk = try PrivateKey.fromHex("0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef");
    const pub_key = pk.publicKey();
    const address = pub_key.toAddress();
    try std.testing.expectEqual(@as(usize, 20), address.len);
}

test "end-to-end signing flow" {
    // 1. 生成或加载私钥
    const private_key = try PrivateKey.fromHex("0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318");

    // 2. 获取公钥和地址
    const public_key = private_key.publicKey();
    const address = public_key.toAddress();
    var addr_buf: [42]u8 = undefined;
    const addr_hex = PublicKey.addressToHex(&address, &addr_buf);
    try std.testing.expectEqualStrings("0x2c7536e3605d9c16a7a3d7b1898e529396a65c23", addr_hex);

    // 3. 创建消息哈希（模拟 EIP-712）
    const message = "Hello, Polymarket!";
    const message_hash = keccak256(message);

    // 4. 签名
    const signature = try private_key.sign(&message_hash);

    // 5. 验证签名
    try public_key.verify(&message_hash, &signature);

    // 6. 序列化签名
    var sig_buf: [132]u8 = undefined;
    const sig_hex = signature.toHex(&sig_buf);
    try std.testing.expect(sig_hex.len == 132);
    try std.testing.expectEqualStrings("0x", sig_hex[0..2]);
}

test "L2 auth signature flow" {
    // 模拟 L2 认证签名流程
    const api_secret = "my_api_secret";
    const timestamp = "1704067200";
    const method = "POST";
    const path = "/order";
    const body = "{\"tokenId\":\"123\"}";

    // 构建签名消息
    var hmac_ctx = Hmac.init(api_secret);
    hmac_ctx.update(timestamp);
    hmac_ctx.update(method);
    hmac_ctx.update(path);
    hmac_ctx.update(body);
    const mac = hmac_ctx.final();

    // 编码为 Base64
    var base64_buf: [MAC_BASE64_LENGTH]u8 = undefined;
    const signature = macToBase64(&mac, &base64_buf);

    try std.testing.expect(signature.len > 0);
}

// 运行所有子模块测试
comptime {
    _ = keccak;
    _ = hmac;
    _ = ecdsa;
}
