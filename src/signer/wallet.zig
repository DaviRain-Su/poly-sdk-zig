//! 钱包类型
//!
//! 封装私钥、公钥和地址，提供签名功能。
//!
//! 示例:
//! ```zig
//! const wallet = try Wallet.fromPrivateKeyHex("0x...");
//! const address = wallet.getAddressHex();
//!
//! const signature = try wallet.sign(&message_hash);
//! ```

const std = @import("std");
const root = @import("../root.zig");

const crypto = root.crypto;
const types = root.types;

const PrivateKey = crypto.PrivateKey;
const PublicKey = crypto.PublicKey;
const Signature = crypto.Signature;
const Hasher = crypto.Hasher;
const keccak256 = crypto.keccak256;
const Address = types.Address;
const Secret = types.Secret;

/// 钱包错误
pub const WalletError = error{
    /// 无效的私钥
    InvalidPrivateKey,
    /// 无效的十六进制字符
    InvalidHexCharacter,
    /// 无效的私钥长度
    InvalidPrivateKeyLength,
    /// 签名失败
    SigningFailed,
};

/// 钱包类型
///
/// 封装私钥、公钥和以太坊地址，提供签名功能。
/// 私钥使用 Secret 包装，防止意外日志泄露。
pub const Wallet = struct {
    /// 私钥（使用 Secret 包装保护）
    private_key: Secret(PrivateKey),
    /// 公钥
    public_key: PublicKey,
    /// 以太坊地址（20 字节）
    address_bytes: [20]u8,

    const Self = @This();

    /// 从私钥创建钱包
    ///
    /// 参数:
    ///   - private_key: 私钥
    ///
    /// 返回: 钱包实例
    pub fn fromPrivateKey(private_key: PrivateKey) Self {
        const public_key = private_key.publicKey();
        const address_bytes = public_key.toAddress();

        return .{
            .private_key = Secret(PrivateKey).init(private_key),
            .public_key = public_key,
            .address_bytes = address_bytes,
        };
    }

    /// 从十六进制私钥字符串创建钱包
    ///
    /// 参数:
    ///   - hex: 十六进制私钥字符串（可带 0x 前缀）
    ///
    /// 返回: 钱包实例，失败返回错误
    pub fn fromPrivateKeyHex(hex: []const u8) WalletError!Self {
        const pk = PrivateKey.fromHex(hex) catch |err| {
            return switch (err) {
                error.InvalidHexCharacter => WalletError.InvalidHexCharacter,
                error.InvalidPrivateKeyLength => WalletError.InvalidPrivateKeyLength,
                else => WalletError.InvalidPrivateKey,
            };
        };
        return fromPrivateKey(pk);
    }

    /// 生成随机钱包
    ///
    /// 使用系统安全随机数生成器生成新的私钥。
    pub fn generate() WalletError!Self {
        const pk = PrivateKey.generate() catch {
            return WalletError.InvalidPrivateKey;
        };
        return fromPrivateKey(pk);
    }

    /// 获取地址（Address 类型）
    pub fn getAddress(self: *const Self) Address {
        return Address.fromBytes(self.address_bytes);
    }

    /// 获取地址的十六进制字符串（带 0x 前缀，带 EIP-55 校验和）
    pub fn getAddressChecksumHex(self: *const Self) [42]u8 {
        const addr = self.getAddress();
        return addr.toChecksumHex();
    }

    /// 获取地址的小写十六进制字符串（带 0x 前缀）
    pub fn getAddressLowerHex(self: *const Self, buffer: *[42]u8) []const u8 {
        return PublicKey.addressToHex(&self.address_bytes, buffer);
    }

    /// 签名消息哈希（32 字节）
    ///
    /// 参数:
    ///   - message_hash: 32 字节的消息哈希
    ///
    /// 返回: 签名（r, s, v）
    pub fn sign(self: *const Self, message_hash: *const [32]u8) WalletError!Signature {
        const pk = self.private_key.reveal();
        return pk.sign(message_hash) catch {
            return WalletError.SigningFailed;
        };
    }

    /// 签名任意消息（EIP-191）
    ///
    /// 对消息添加以太坊签名前缀后签名。
    /// 前缀: "\x19Ethereum Signed Message:\n" + len(message)
    ///
    /// 参数:
    ///   - message: 任意消息
    ///
    /// 返回: 签名（r, s, v）
    pub fn signMessage(self: *const Self, message: []const u8) WalletError!Signature {
        // 构建 EIP-191 消息
        const prefix = "\x19Ethereum Signed Message:\n";

        // 计算消息长度的字符串表示
        var len_buf: [20]u8 = undefined;
        const len_str = std.fmt.bufPrint(&len_buf, "{d}", .{message.len}) catch unreachable;

        // 计算哈希
        var hasher = Hasher.init();
        hasher.update(prefix);
        hasher.update(len_str);
        hasher.update(message);
        const hash = hasher.final();

        return self.sign(&hash);
    }

    /// 验证签名是否来自此钱包
    ///
    /// 参数:
    ///   - message_hash: 32 字节的消息哈希
    ///   - signature: 签名
    ///
    /// 返回: 签名是否有效
    pub fn verify(self: *const Self, message_hash: *const [32]u8, signature: *const Signature) bool {
        self.public_key.verify(message_hash, signature) catch {
            return false;
        };
        return true;
    }
};

// ============================================================================
// 测试
// ============================================================================

test "Wallet.fromPrivateKeyHex valid" {
    const wallet = try Wallet.fromPrivateKeyHex("0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318");
    var buffer: [42]u8 = undefined;
    const address = wallet.getAddressLowerHex(&buffer);
    try std.testing.expectEqualStrings("0x2c7536e3605d9c16a7a3d7b1898e529396a65c23", address);
}

test "Wallet.fromPrivateKeyHex without 0x" {
    const wallet = try Wallet.fromPrivateKeyHex("4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318");
    var buffer: [42]u8 = undefined;
    const address = wallet.getAddressLowerHex(&buffer);
    try std.testing.expectEqualStrings("0x2c7536e3605d9c16a7a3d7b1898e529396a65c23", address);
}

test "Wallet.fromPrivateKeyHex invalid length" {
    const result = Wallet.fromPrivateKeyHex("0x1234");
    try std.testing.expectError(WalletError.InvalidPrivateKeyLength, result);
}

test "Wallet.fromPrivateKeyHex invalid character" {
    const result = Wallet.fromPrivateKeyHex("0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f36231z");
    try std.testing.expectError(WalletError.InvalidHexCharacter, result);
}

test "Wallet.generate" {
    const wallet1 = try Wallet.generate();
    const wallet2 = try Wallet.generate();

    // 两个随机钱包地址应该不同
    try std.testing.expect(!std.mem.eql(u8, &wallet1.address_bytes, &wallet2.address_bytes));
}

test "Wallet.getAddress" {
    const wallet = try Wallet.fromPrivateKeyHex("0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318");
    const address = wallet.getAddress();

    // 验证地址格式
    const hex = address.toChecksumHex();
    try std.testing.expect(hex.len == 42);
    try std.testing.expectEqualStrings("0x", hex[0..2]);
}

test "Wallet.sign and verify" {
    const wallet = try Wallet.fromPrivateKeyHex("0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318");

    // 创建消息哈希
    const message_hash = keccak256("Hello, Polymarket!");

    // 签名
    const signature = try wallet.sign(&message_hash);

    // 验证
    try std.testing.expect(wallet.verify(&message_hash, &signature));
}

test "Wallet.signMessage EIP-191" {
    const wallet = try Wallet.fromPrivateKeyHex("0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318");

    // 签名消息
    const signature = try wallet.signMessage("Hello, Polymarket!");

    // 手动计算 EIP-191 哈希验证
    const prefix = "\x19Ethereum Signed Message:\n";
    var hasher = Hasher.init();
    hasher.update(prefix);
    hasher.update("18"); // "Hello, Polymarket!".len = 18
    hasher.update("Hello, Polymarket!");
    const expected_hash = hasher.final();

    // 验证签名
    try std.testing.expect(wallet.verify(&expected_hash, &signature));
}

test "Wallet.verify with wrong message" {
    const wallet = try Wallet.fromPrivateKeyHex("0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318");

    const message_hash = keccak256("Hello");
    const signature = try wallet.sign(&message_hash);

    // 使用错误的消息验证
    const wrong_hash = keccak256("Wrong");
    try std.testing.expect(!wallet.verify(&wrong_hash, &signature));
}

test "Wallet private key is secret" {
    const wallet = try Wallet.fromPrivateKeyHex("0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318");

    // Secret 类型的 format 应该输出 [REDACTED]
    var buffer: [100]u8 = undefined;
    const formatted = std.fmt.bufPrint(&buffer, "{f}", .{wallet.private_key}) catch unreachable;
    try std.testing.expectEqualStrings("[REDACTED]", formatted);
}
