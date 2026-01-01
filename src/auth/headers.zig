//! 认证 Header 类型
//!
//! 定义 L1 和 L2 认证所需的 HTTP Header 类型。
//!
//! L1 认证使用 EIP-712 签名，用于 API Key 管理。
//! L2 认证使用 HMAC-SHA256 签名，用于常规 API 请求。

const std = @import("std");

/// L1 认证 Header
///
/// 用于 L1 认证的 HTTP Header，包含钱包地址、EIP-712 签名、时间戳和 nonce。
/// L1 认证仅用于 API Key 的创建和派生。
pub const L1PolyHeader = struct {
    /// 钱包地址（带 0x 前缀，EIP-55 校验和格式）
    poly_address: [42]u8,

    /// EIP-712 签名（带 0x 前缀，132 字符: 0x + r(64) + s(64) + v(2)）
    poly_signature: [132]u8,

    /// Unix 时间戳（秒）
    poly_timestamp: [20]u8,
    poly_timestamp_len: usize,

    /// 随机 nonce（防重放攻击）
    poly_nonce: [20]u8,
    poly_nonce_len: usize,

    const Self = @This();

    /// Header 名称常量
    pub const HEADER_ADDRESS = "POLY_ADDRESS";
    pub const HEADER_SIGNATURE = "POLY_SIGNATURE";
    pub const HEADER_TIMESTAMP = "POLY_TIMESTAMP";
    pub const HEADER_NONCE = "POLY_NONCE";

    /// 获取地址字符串
    pub fn getAddress(self: *const Self) []const u8 {
        return &self.poly_address;
    }

    /// 获取签名字符串
    pub fn getSignature(self: *const Self) []const u8 {
        return &self.poly_signature;
    }

    /// 获取时间戳字符串
    pub fn getTimestamp(self: *const Self) []const u8 {
        return self.poly_timestamp[0..self.poly_timestamp_len];
    }

    /// 获取 nonce 字符串
    pub fn getNonce(self: *const Self) []const u8 {
        return self.poly_nonce[0..self.poly_nonce_len];
    }

    /// 转换为 HTTP Header 数组
    ///
    /// 返回可用于 HTTP 请求的 Header 数组。
    pub fn toHttpHeaders(self: *const Self) [4]std.http.Header {
        return [4]std.http.Header{
            .{ .name = HEADER_ADDRESS, .value = self.getAddress() },
            .{ .name = HEADER_SIGNATURE, .value = self.getSignature() },
            .{ .name = HEADER_TIMESTAMP, .value = self.getTimestamp() },
            .{ .name = HEADER_NONCE, .value = self.getNonce() },
        };
    }
};

/// L2 认证 Header
///
/// 用于 L2 认证的 HTTP Header，包含 API Key、HMAC 签名、时间戳和 passphrase。
/// L2 认证用于所有需要认证的 API 请求。
pub const L2PolyHeader = struct {
    /// API Key
    poly_api_key: []const u8,

    /// HMAC-SHA256 签名（Base64 编码）
    poly_signature: [44]u8, // Base64 of 32 bytes = 44 chars

    /// Unix 时间戳（秒）
    poly_timestamp: [20]u8,
    poly_timestamp_len: usize,

    /// API Passphrase
    poly_passphrase: []const u8,

    const Self = @This();

    /// Header 名称常量
    pub const HEADER_API_KEY = "POLY_API_KEY";
    pub const HEADER_SIGNATURE = "POLY_SIGNATURE";
    pub const HEADER_TIMESTAMP = "POLY_TIMESTAMP";
    pub const HEADER_PASSPHRASE = "POLY_PASSPHRASE";

    /// 获取 API Key
    pub fn getApiKey(self: *const Self) []const u8 {
        return self.poly_api_key;
    }

    /// 获取签名
    pub fn getSignature(self: *const Self) []const u8 {
        return &self.poly_signature;
    }

    /// 获取时间戳
    pub fn getTimestamp(self: *const Self) []const u8 {
        return self.poly_timestamp[0..self.poly_timestamp_len];
    }

    /// 获取 passphrase
    pub fn getPassphrase(self: *const Self) []const u8 {
        return self.poly_passphrase;
    }

    /// 转换为 HTTP Header 数组
    pub fn toHttpHeaders(self: *const Self) [4]std.http.Header {
        return [4]std.http.Header{
            .{ .name = HEADER_API_KEY, .value = self.getApiKey() },
            .{ .name = HEADER_SIGNATURE, .value = self.getSignature() },
            .{ .name = HEADER_TIMESTAMP, .value = self.getTimestamp() },
            .{ .name = HEADER_PASSPHRASE, .value = self.getPassphrase() },
        };
    }
};

// ============================================================================
// 测试
// ============================================================================

test "L1PolyHeader creation and access" {
    var header = L1PolyHeader{
        .poly_address = undefined,
        .poly_signature = undefined,
        .poly_timestamp = undefined,
        .poly_timestamp_len = 0,
        .poly_nonce = undefined,
        .poly_nonce_len = 0,
    };

    // 设置地址
    const addr = "0x1234567890123456789012345678901234567890";
    @memcpy(&header.poly_address, addr);

    // 设置签名（132 字符）
    const sig = "0x" ++ "a" ** 128 ++ "1b";
    @memcpy(&header.poly_signature, sig);

    // 设置时间戳
    const ts = "1704067200";
    @memcpy(header.poly_timestamp[0..ts.len], ts);
    header.poly_timestamp_len = ts.len;

    // 设置 nonce
    const nonce = "12345";
    @memcpy(header.poly_nonce[0..nonce.len], nonce);
    header.poly_nonce_len = nonce.len;

    // 验证
    try std.testing.expectEqualStrings(addr, header.getAddress());
    try std.testing.expectEqualStrings(sig, header.getSignature());
    try std.testing.expectEqualStrings(ts, header.getTimestamp());
    try std.testing.expectEqualStrings(nonce, header.getNonce());
}

test "L1PolyHeader.toHttpHeaders" {
    var header = L1PolyHeader{
        .poly_address = undefined,
        .poly_signature = undefined,
        .poly_timestamp = undefined,
        .poly_timestamp_len = 10,
        .poly_nonce = undefined,
        .poly_nonce_len = 5,
    };

    const addr = "0x1234567890123456789012345678901234567890";
    @memcpy(&header.poly_address, addr);

    const sig = "0x" ++ "b" ** 128 ++ "1c";
    @memcpy(&header.poly_signature, sig);

    @memcpy(header.poly_timestamp[0..10], "1704067200");
    @memcpy(header.poly_nonce[0..5], "99999");

    const headers = header.toHttpHeaders();

    try std.testing.expectEqual(@as(usize, 4), headers.len);
    try std.testing.expectEqualStrings("POLY_ADDRESS", headers[0].name);
    try std.testing.expectEqualStrings("POLY_SIGNATURE", headers[1].name);
    try std.testing.expectEqualStrings("POLY_TIMESTAMP", headers[2].name);
    try std.testing.expectEqualStrings("POLY_NONCE", headers[3].name);
}

test "L2PolyHeader creation" {
    const api_key = "test-api-key";
    const passphrase = "test-passphrase";

    var header = L2PolyHeader{
        .poly_api_key = api_key,
        .poly_signature = undefined,
        .poly_timestamp = undefined,
        .poly_timestamp_len = 10,
        .poly_passphrase = passphrase,
    };

    // 设置签名（44 字符 Base64）
    const sig = "YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXoxMjM0NTY=";
    @memcpy(&header.poly_signature, sig);

    @memcpy(header.poly_timestamp[0..10], "1704067200");

    try std.testing.expectEqualStrings(api_key, header.getApiKey());
    try std.testing.expectEqualStrings(sig, header.getSignature());
    try std.testing.expectEqualStrings("1704067200", header.getTimestamp());
    try std.testing.expectEqualStrings(passphrase, header.getPassphrase());
}

test "L2PolyHeader.toHttpHeaders" {
    const api_key = "my-key";
    const passphrase = "my-pass";

    var header = L2PolyHeader{
        .poly_api_key = api_key,
        .poly_signature = undefined,
        .poly_timestamp = undefined,
        .poly_timestamp_len = 10,
        .poly_passphrase = passphrase,
    };

    @memcpy(&header.poly_signature, "YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXoxMjM0NTY=");
    @memcpy(header.poly_timestamp[0..10], "1704067200");

    const headers = header.toHttpHeaders();

    try std.testing.expectEqual(@as(usize, 4), headers.len);
    try std.testing.expectEqualStrings("POLY_API_KEY", headers[0].name);
    try std.testing.expectEqualStrings("POLY_SIGNATURE", headers[1].name);
    try std.testing.expectEqualStrings("POLY_TIMESTAMP", headers[2].name);
    try std.testing.expectEqualStrings("POLY_PASSPHRASE", headers[3].name);
}

test "Header name constants" {
    try std.testing.expectEqualStrings("POLY_ADDRESS", L1PolyHeader.HEADER_ADDRESS);
    try std.testing.expectEqualStrings("POLY_SIGNATURE", L1PolyHeader.HEADER_SIGNATURE);
    try std.testing.expectEqualStrings("POLY_TIMESTAMP", L1PolyHeader.HEADER_TIMESTAMP);
    try std.testing.expectEqualStrings("POLY_NONCE", L1PolyHeader.HEADER_NONCE);

    try std.testing.expectEqualStrings("POLY_API_KEY", L2PolyHeader.HEADER_API_KEY);
    try std.testing.expectEqualStrings("POLY_PASSPHRASE", L2PolyHeader.HEADER_PASSPHRASE);
}
