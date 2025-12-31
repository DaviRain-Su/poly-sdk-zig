//! Keccak256 哈希封装
//!
//! 提供以太坊兼容的 Keccak256 哈希功能，用于：
//! - EIP-712 结构化数据哈希
//! - 以太坊地址计算
//! - 消息哈希
//!
//! 示例:
//! ```zig
//! const hash = keccak256("hello");
//! // => 0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8
//! ```

const std = @import("std");

/// Keccak256 哈希输出长度（32 字节 = 256 位）
pub const HASH_LENGTH: usize = 32;

/// Keccak256 哈希类型
pub const Hash = [HASH_LENGTH]u8;

/// 底层 Keccak256 实现
const Keccak256Impl = std.crypto.hash.sha3.Keccak256;

/// Keccak256 哈希器，支持流式哈希
pub const Hasher = struct {
    inner: Keccak256Impl,

    const Self = @This();

    /// 初始化哈希器
    pub fn init() Self {
        return .{
            .inner = Keccak256Impl.init(.{}),
        };
    }

    /// 更新哈希数据
    pub fn update(self: *Self, data: []const u8) void {
        self.inner.update(data);
    }

    /// 完成哈希计算并返回结果
    pub fn final(self: *Self) Hash {
        var hash: Hash = undefined;
        self.inner.final(&hash);
        return hash;
    }

    /// 完成哈希计算，输出到指定缓冲区
    pub fn finalTo(self: *Self, out: *Hash) void {
        self.inner.final(out);
    }
};

/// 计算数据的 Keccak256 哈希
///
/// 参数:
///   - data: 要哈希的数据
///
/// 返回: 32 字节的哈希值
pub fn keccak256(data: []const u8) Hash {
    var hash: Hash = undefined;
    Keccak256Impl.hash(data, &hash, .{});
    return hash;
}

/// 计算多个数据块的 Keccak256 哈希
///
/// 参数:
///   - parts: 要哈希的数据块数组
///
/// 返回: 32 字节的哈希值
pub fn keccak256Multi(parts: []const []const u8) Hash {
    var hasher = Hasher.init();
    for (parts) |part| {
        hasher.update(part);
    }
    return hasher.final();
}

/// 将哈希值格式化为十六进制字符串（带 0x 前缀）
///
/// 参数:
///   - hash: 32 字节哈希值
///   - buffer: 输出缓冲区（至少 66 字节: "0x" + 64 hex chars）
///
/// 返回: 格式化后的字符串切片
pub fn toHexString(hash: *const Hash, buffer: *[66]u8) []const u8 {
    buffer[0] = '0';
    buffer[1] = 'x';
    _ = std.fmt.bufPrint(buffer[2..], "{x}", .{hash.*}) catch unreachable;
    return buffer[0..66];
}

/// 从十六进制字符串解析哈希值
///
/// 参数:
///   - hex: 十六进制字符串（可带 0x 前缀）
///
/// 返回: 32 字节哈希值，解析失败返回 null
pub fn fromHexString(hex: []const u8) ?Hash {
    const data = if (hex.len >= 2 and hex[0] == '0' and (hex[1] == 'x' or hex[1] == 'X'))
        hex[2..]
    else
        hex;

    if (data.len != 64) return null;

    var hash: Hash = undefined;
    for (0..32) |i| {
        const high = hexCharToNibble(data[i * 2]) orelse return null;
        const low = hexCharToNibble(data[i * 2 + 1]) orelse return null;
        hash[i] = (@as(u8, high) << 4) | @as(u8, low);
    }
    return hash;
}

fn hexCharToNibble(c: u8) ?u4 {
    return switch (c) {
        '0'...'9' => @intCast(c - '0'),
        'a'...'f' => @intCast(c - 'a' + 10),
        'A'...'F' => @intCast(c - 'A' + 10),
        else => null,
    };
}

// ============================================================================
// 测试
// ============================================================================

test "keccak256 empty string" {
    const hash = keccak256("");
    // 已知值: keccak256("") = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470
    const expected = fromHexString("c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470").?;
    try std.testing.expectEqualSlices(u8, &expected, &hash);
}

test "keccak256 hello" {
    const hash = keccak256("hello");
    // 已知值: keccak256("hello") = 0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8
    const expected = fromHexString("1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8").?;
    try std.testing.expectEqualSlices(u8, &expected, &hash);
}

test "keccak256 Hello, World!" {
    const hash = keccak256("Hello, World!");
    // 已知值
    const expected = fromHexString("acaf3289d7b601cbd114fb36c4d29c85bbfd5e133f14cb355c3fd8d99367964f").?;
    try std.testing.expectEqualSlices(u8, &expected, &hash);
}

test "keccak256Multi" {
    const parts = &[_][]const u8{ "Hello", ", ", "World!" };
    const hash = keccak256Multi(parts);
    const expected = keccak256("Hello, World!");
    try std.testing.expectEqualSlices(u8, &expected, &hash);
}

test "Hasher streaming" {
    var hasher = Hasher.init();
    hasher.update("Hello");
    hasher.update(", ");
    hasher.update("World!");
    const hash = hasher.final();
    const expected = keccak256("Hello, World!");
    try std.testing.expectEqualSlices(u8, &expected, &hash);
}

test "toHexString" {
    const hash = keccak256("hello");
    var buffer: [66]u8 = undefined;
    const hex = toHexString(&hash, &buffer);
    try std.testing.expectEqualStrings("0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8", hex);
}

test "fromHexString with 0x prefix" {
    const hex = "0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8";
    const hash = fromHexString(hex).?;
    const expected = keccak256("hello");
    try std.testing.expectEqualSlices(u8, &expected, &hash);
}

test "fromHexString without prefix" {
    const hex = "1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8";
    const hash = fromHexString(hex).?;
    const expected = keccak256("hello");
    try std.testing.expectEqualSlices(u8, &expected, &hash);
}

test "fromHexString invalid length" {
    const result = fromHexString("1234");
    try std.testing.expectEqual(@as(?Hash, null), result);
}

test "fromHexString invalid characters" {
    const result = fromHexString("zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz");
    try std.testing.expectEqual(@as(?Hash, null), result);
}

test "keccak256 EIP-712 domain separator example" {
    // EIP-712 类型哈希示例
    // keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
    const type_hash = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    var buffer: [66]u8 = undefined;
    const hex = toHexString(&type_hash, &buffer);
    // 这是一个已知的类型哈希
    try std.testing.expectEqualStrings("0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f", hex);
}
