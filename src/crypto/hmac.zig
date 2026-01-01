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

/// Base64 解码后的最大长度（用于 API secret）
pub const BASE64_DECODED_MAX_LENGTH: usize = 64;

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

/// 将 MAC 编码为 Base64 字符串（标准 Base64）
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

/// 将 MAC 编码为 URL-safe Base64 字符串
///
/// Polymarket API 要求使用 URL-safe Base64 编码:
/// - '+' -> '-'
/// - '/' -> '_'
/// - 保留 '=' 填充
///
/// 参数:
///   - mac: 32 字节 MAC 值
///   - buffer: 输出缓冲区（至少 44 字节）
///
/// 返回: URL-safe Base64 编码后的字符串切片
pub fn toBase64UrlSafe(mac: *const Mac, buffer: *[BASE64_ENCODED_LENGTH]u8) []const u8 {
    // 使用 URL-safe 字母表（但保留 = 填充）
    const encoder = std.base64.Base64Encoder.init(
        std.base64.url_safe.alphabet_chars,
        std.base64.url_safe.pad_char,
    );
    return encoder.encode(buffer, mac);
}

/// 从 Base64 解码密钥（支持标准和 URL-safe Base64）
///
/// Polymarket 的 API secret 是 Base64 编码的，需要先解码才能用于 HMAC
///
/// 参数:
///   - encoded: Base64 编码的字符串
///   - buffer: 输出缓冲区
///
/// 返回: 解码后的字节切片，或 null 如果解码失败
pub fn decodeBase64Secret(encoded: []const u8, buffer: *[BASE64_DECODED_MAX_LENGTH]u8) ?[]const u8 {
    // 先尝试 URL-safe Base64
    const url_safe_decoder = std.base64.url_safe;
    if (url_safe_decoder.Decoder.calcSizeForSlice(encoded)) |size| {
        if (size <= BASE64_DECODED_MAX_LENGTH) {
            if (url_safe_decoder.Decoder.decode(buffer[0..size], encoded)) |_| {
                return buffer[0..size];
            } else |_| {}
        }
    } else |_| {}

    // 尝试标准 Base64
    const standard_decoder = std.base64.standard;
    if (standard_decoder.Decoder.calcSizeForSlice(encoded)) |size| {
        if (size <= BASE64_DECODED_MAX_LENGTH) {
            if (standard_decoder.Decoder.decode(buffer[0..size], encoded)) |_| {
                return buffer[0..size];
            } else |_| {}
        }
    } else |_| {}

    return null;
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

test "decodeBase64Secret standard base64" {
    var buffer: [BASE64_DECODED_MAX_LENGTH]u8 = undefined;

    // 全 0 的 32 字节，Base64 编码
    const encoded = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    const decoded = decodeBase64Secret(encoded, &buffer).?;

    try std.testing.expectEqual(@as(usize, 32), decoded.len);
    for (decoded) |b| {
        try std.testing.expectEqual(@as(u8, 0), b);
    }
}

test "decodeBase64Secret url-safe base64" {
    var buffer: [BASE64_DECODED_MAX_LENGTH]u8 = undefined;

    // URL-safe Base64 - 使用有效的 Base64 字符串
    // "Hello" 的 URL-safe Base64 编码
    const encoded = "SGVsbG8=";
    const decoded = decodeBase64Secret(encoded, &buffer);

    try std.testing.expect(decoded != null);
    try std.testing.expectEqualStrings("Hello", decoded.?);
}

test "toBase64UrlSafe" {
    // 使用一个会产生 + 和 / 的 MAC 值来测试 URL-safe 转换
    const mac = hmacSha256("test-key", "test-message");
    var buffer: [BASE64_ENCODED_LENGTH]u8 = undefined;
    const url_safe = toBase64UrlSafe(&mac, &buffer);

    // 验证不包含 + 和 /
    for (url_safe) |c| {
        try std.testing.expect(c != '+');
        try std.testing.expect(c != '/');
    }

    // 验证长度正确
    try std.testing.expectEqual(@as(usize, 44), url_safe.len);
}

test "L2 auth with decoded secret matches Rust" {
    // 来自 Rust 测试的数据
    const base64_secret = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    const message = "1GET/"; // timestamp=1, method=GET, path=/

    // 解码 secret
    var secret_buffer: [BASE64_DECODED_MAX_LENGTH]u8 = undefined;
    const decoded_secret = decodeBase64Secret(base64_secret, &secret_buffer).?;

    // 计算 HMAC
    const mac = hmacSha256(decoded_secret, message);

    // URL-safe Base64 编码
    var sig_buffer: [BASE64_ENCODED_LENGTH]u8 = undefined;
    const signature = toBase64UrlSafe(&mac, &sig_buffer);

    // 与 Rust 参考实现比较
    // 预期值来自 rs-clob-client/src/auth.rs 测试
    try std.testing.expectEqualStrings("eHaylCwqRSOa2LFD77Nt_SaTpbsxzN8eTEI3LryhEj4=", signature);
}
