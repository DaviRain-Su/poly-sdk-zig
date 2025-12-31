//! HMAC-SHA256 封装
//!
//! 提供 HMAC-SHA256 消息认证码功能，用于：
//! - L2 API 请求签名
//! - 消息认证
//!
//! 示例:
//! ```zig
//! const mac = hmacSha256("secret_key", "message");
//! const base64_mac = toBase64(&mac);
//! ```

const std = @import("std");

/// HMAC-SHA256 输出长度（32 字节 = 256 位）
pub const MAC_LENGTH: usize = 32;

/// HMAC-SHA256 消息认证码类型
pub const Mac = [MAC_LENGTH]u8;

/// 底层 HMAC-SHA256 实现
const HmacSha256Impl = std.crypto.auth.hmac.sha2.HmacSha256;

/// Base64 编码后的最大长度（44 字节，包含填充）
pub const BASE64_ENCODED_LENGTH: usize = 44;

/// 计算 HMAC-SHA256
///
/// 参数:
///   - key: 密钥
///   - message: 消息
///
/// 返回: 32 字节的 MAC 值
pub fn hmacSha256(key: []const u8, message: []const u8) Mac {
    var mac: Mac = undefined;
    HmacSha256Impl.create(&mac, message, key);
    return mac;
}

/// HMAC-SHA256 增量计算器
pub const Hmac = struct {
    inner: HmacSha256Impl,

    const Self = @This();

    /// 使用密钥初始化
    pub fn init(key: []const u8) Self {
        return .{
            .inner = HmacSha256Impl.init(key),
        };
    }

    /// 更新消息数据
    pub fn update(self: *Self, data: []const u8) void {
        self.inner.update(data);
    }

    /// 完成计算并返回 MAC
    pub fn final(self: *Self) Mac {
        var mac: Mac = undefined;
        self.inner.final(&mac);
        return mac;
    }

    /// 完成计算，输出到指定缓冲区
    pub fn finalTo(self: *Self, out: *Mac) void {
        self.inner.final(out);
    }
};

/// 将 MAC 编码为 Base64 字符串
///
/// 参数:
///   - mac: 32 字节 MAC 值
///   - buffer: 输出缓冲区（至少 44 字节）
///
/// 返回: Base64 编码后的字符串切片
pub fn toBase64(mac: *const Mac, buffer: *[BASE64_ENCODED_LENGTH]u8) []const u8 {
    const encoder = std.base64.Base64Encoder.init(
        std.base64.standard.alphabet_chars,
        std.base64.standard.pad_char,
    );
    return encoder.encode(buffer, mac);
}

/// 将 MAC 编码为 Base64 字符串（分配内存）
///
/// 参数:
///   - allocator: 内存分配器
///   - mac: 32 字节 MAC 值
///
/// 返回: Base64 编码后的字符串（调用者负责释放）
pub fn toBase64Alloc(allocator: std.mem.Allocator, mac: *const Mac) ![]u8 {
    const encoder = std.base64.Base64Encoder.init(
        std.base64.standard.alphabet_chars,
        std.base64.standard.pad_char,
    );
    const encoded = try allocator.alloc(u8, BASE64_ENCODED_LENGTH);
    _ = encoder.encode(encoded, mac);
    return encoded;
}

/// 将 MAC 格式化为十六进制字符串
///
/// 参数:
///   - mac: 32 字节 MAC 值
///   - buffer: 输出缓冲区（至少 64 字节）
///
/// 返回: 十六进制字符串切片
pub fn toHex(mac: *const Mac, buffer: *[64]u8) []const u8 {
    _ = std.fmt.bufPrint(buffer, "{x}", .{mac.*}) catch unreachable;
    return buffer[0..64];
}

/// 验证 MAC
///
/// 参数:
///   - key: 密钥
///   - message: 消息
///   - expected: 期望的 MAC 值
///
/// 返回: MAC 是否匹配
pub fn verify(key: []const u8, message: []const u8, expected: *const Mac) bool {
    const computed = hmacSha256(key, message);
    return std.crypto.timing_safe.eql(Mac, computed, expected.*);
}

// ============================================================================
// 测试
// ============================================================================

test "hmacSha256 basic" {
    const mac = hmacSha256("secret", "message");
    var buffer: [64]u8 = undefined;
    const hex = toHex(&mac, &buffer);
    // 已知值 (与其他实现对比验证)
    try std.testing.expectEqualStrings("8b5f48702995c1598c573db1e21866a9b825d4a794d169d7060a03605796360b", hex);
}

test "hmacSha256 empty message" {
    const mac = hmacSha256("key", "");
    var buffer: [64]u8 = undefined;
    const hex = toHex(&mac, &buffer);
    // 已知值
    try std.testing.expectEqualStrings("5d5d139563c95b5967b9bd9a8c9b233a9dedb45072794cd232dc1b74832607d0", hex);
}

test "hmacSha256 empty key" {
    const mac = hmacSha256("", "message");
    var buffer: [64]u8 = undefined;
    const hex = toHex(&mac, &buffer);
    // 已知值 (Python: hmac.new(b'', b'message', hashlib.sha256).hexdigest())
    try std.testing.expectEqualStrings("eb08c1f56d5ddee07f7bdf80468083da06b64cf4fac64fe3a90883df5feacae4", hex);
}

test "Hmac incremental" {
    var hmac = Hmac.init("secret");
    hmac.update("mes");
    hmac.update("sage");
    const mac = hmac.final();

    const expected = hmacSha256("secret", "message");
    try std.testing.expectEqualSlices(u8, &expected, &mac);
}

test "toBase64" {
    const mac = hmacSha256("secret", "message");
    var buffer: [BASE64_ENCODED_LENGTH]u8 = undefined;
    const base64 = toBase64(&mac, &buffer);
    // Base64 编码验证
    try std.testing.expectEqualStrings("i19IcCmVwVmMVz2x4hhmqbgl1KeU0WnXBgoDYFeWNgs=", base64);
}

test "toBase64Alloc" {
    const allocator = std.testing.allocator;
    const mac = hmacSha256("secret", "message");
    const base64 = try toBase64Alloc(allocator, &mac);
    defer allocator.free(base64);
    try std.testing.expectEqualStrings("i19IcCmVwVmMVz2x4hhmqbgl1KeU0WnXBgoDYFeWNgs=", base64);
}

test "verify success" {
    const mac = hmacSha256("secret", "message");
    try std.testing.expect(verify("secret", "message", &mac));
}

test "verify failure wrong message" {
    const mac = hmacSha256("secret", "message");
    try std.testing.expect(!verify("secret", "wrong", &mac));
}

test "verify failure wrong key" {
    const mac = hmacSha256("secret", "message");
    try std.testing.expect(!verify("wrong", "message", &mac));
}

test "L2 auth signature example" {
    // 模拟 L2 认证签名
    // message = timestamp + method + path + body
    const timestamp = "1704067200";
    const method = "POST";
    const path = "/order";
    const body = "{\"tokenId\":\"123\"}";

    var hmac = Hmac.init("api_secret");
    hmac.update(timestamp);
    hmac.update(method);
    hmac.update(path);
    hmac.update(body);
    const mac = hmac.final();

    var buffer: [BASE64_ENCODED_LENGTH]u8 = undefined;
    const signature = toBase64(&mac, &buffer);

    // 验证签名格式正确
    try std.testing.expect(signature.len > 0);
    try std.testing.expect(signature[signature.len - 1] == '='); // Base64 填充
}
