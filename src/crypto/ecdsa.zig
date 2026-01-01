//! secp256k1 ECDSA 签名
//!
//! 提供以太坊兼容的 ECDSA 签名功能，用于：
//! - EIP-712 结构化数据签名
//! - 订单签名
//! - L1 认证签名
//!
//! 示例:
//! ```zig
//! const private_key = try PrivateKey.fromHex("0x...");
//! const public_key = private_key.publicKey();
//! const address = public_key.toAddress();
//!
//! const signature = try private_key.sign(message_hash);
//! ```

const std = @import("std");
const keccak = @import("keccak.zig");

/// 私钥长度（32 字节）
pub const PRIVATE_KEY_LENGTH: usize = 32;

/// 公钥长度（未压缩格式，65 字节：0x04 + 64 字节）
pub const PUBLIC_KEY_UNCOMPRESSED_LENGTH: usize = 65;

/// 公钥长度（压缩格式，33 字节）
pub const PUBLIC_KEY_COMPRESSED_LENGTH: usize = 33;

/// 签名长度（65 字节：r + s + v）
pub const SIGNATURE_LENGTH: usize = 65;

/// 以太坊地址长度（20 字节）
pub const ADDRESS_LENGTH: usize = 20;

/// 底层曲线和 ECDSA 实现
const Secp256k1 = std.crypto.ecc.Secp256k1;
const Keccak256 = std.crypto.hash.sha3.Keccak256;
const EcdsaImpl = std.crypto.sign.ecdsa.Ecdsa(Secp256k1, Keccak256);

/// 签名错误
pub const SignError = error{
    /// 无效的私钥
    InvalidPrivateKey,
    /// 签名失败
    SigningFailed,
    /// 无效的十六进制字符
    InvalidHexCharacter,
    /// 无效的私钥长度
    InvalidPrivateKeyLength,
    /// 身份元素错误
    IdentityElement,
    /// 非规范错误
    NonCanonical,
};

/// 验证错误
pub const VerifyError = error{
    /// 无效的公钥
    InvalidPublicKey,
    /// 无效的签名
    InvalidSignature,
    /// 验证失败
    VerificationFailed,
    /// 身份元素错误
    IdentityElement,
    /// 非规范错误
    NonCanonical,
};

/// 以太坊签名（65 字节：r[32] + s[32] + v[1]）
pub const Signature = struct {
    /// r 分量（32 字节）
    r: [32]u8,
    /// s 分量（32 字节）
    s: [32]u8,
    /// 恢复 ID（0, 1, 27, 28）
    v: u8,

    const Self = @This();

    /// 从字节数组创建
    pub fn fromBytes(bytes: *const [SIGNATURE_LENGTH]u8) Self {
        return .{
            .r = bytes[0..32].*,
            .s = bytes[32..64].*,
            .v = bytes[64],
        };
    }

    /// 转换为字节数组
    pub fn toBytes(self: *const Self) [SIGNATURE_LENGTH]u8 {
        var bytes: [SIGNATURE_LENGTH]u8 = undefined;
        @memcpy(bytes[0..32], &self.r);
        @memcpy(bytes[32..64], &self.s);
        bytes[64] = self.v;
        return bytes;
    }

    /// 转换为十六进制字符串（带 0x 前缀）
    pub fn toHex(self: *const Self, buffer: *[132]u8) []const u8 {
        buffer[0] = '0';
        buffer[1] = 'x';
        const bytes = self.toBytes();
        _ = std.fmt.bufPrint(buffer[2..], "{x}", .{bytes}) catch unreachable;
        return buffer[0..132];
    }

    /// 从十六进制字符串解析
    pub fn fromHex(hex: []const u8) ?Self {
        const data = if (hex.len >= 2 and hex[0] == '0' and (hex[1] == 'x' or hex[1] == 'X'))
            hex[2..]
        else
            hex;

        if (data.len != 130) return null;

        var bytes: [SIGNATURE_LENGTH]u8 = undefined;
        for (0..65) |i| {
            const high = hexCharToNibble(data[i * 2]) orelse return null;
            const low = hexCharToNibble(data[i * 2 + 1]) orelse return null;
            bytes[i] = (@as(u8, high) << 4) | @as(u8, low);
        }
        return fromBytes(&bytes);
    }

    /// 获取以太坊格式的 v 值（27 或 28）
    pub fn getEthereumV(self: *const Self) u8 {
        if (self.v < 27) {
            return self.v + 27;
        }
        return self.v;
    }

    /// 设置以太坊格式的 v 值
    pub fn setEthereumV(self: *Self, eth_v: u8) void {
        if (eth_v >= 27) {
            self.v = eth_v - 27;
        } else {
            self.v = eth_v;
        }
    }
};

/// 私钥
pub const PrivateKey = struct {
    /// 内部密钥对
    keypair: EcdsaImpl.KeyPair,
    /// 原始私钥字节
    bytes: [PRIVATE_KEY_LENGTH]u8,

    const Self = @This();

    /// 从字节数组创建
    pub fn fromBytes(bytes: *const [PRIVATE_KEY_LENGTH]u8) SignError!Self {
        const keypair = EcdsaImpl.KeyPair.fromSecretKey(.{ .bytes = bytes.* }) catch {
            return SignError.InvalidPrivateKey;
        };
        return .{
            .keypair = keypair,
            .bytes = bytes.*,
        };
    }

    /// 从十六进制字符串创建
    pub fn fromHex(hex: []const u8) SignError!Self {
        const data = if (hex.len >= 2 and hex[0] == '0' and (hex[1] == 'x' or hex[1] == 'X'))
            hex[2..]
        else
            hex;

        if (data.len != 64) return SignError.InvalidPrivateKeyLength;

        var bytes: [PRIVATE_KEY_LENGTH]u8 = undefined;
        for (0..32) |i| {
            const high = hexCharToNibble(data[i * 2]) orelse return SignError.InvalidHexCharacter;
            const low = hexCharToNibble(data[i * 2 + 1]) orelse return SignError.InvalidHexCharacter;
            bytes[i] = (@as(u8, high) << 4) | @as(u8, low);
        }
        return fromBytes(&bytes);
    }

    /// 生成随机私钥
    pub fn generate() SignError!Self {
        var seed: [32]u8 = undefined;
        std.crypto.random.bytes(&seed);
        return fromBytes(&seed);
    }

    /// 获取公钥
    pub fn publicKey(self: *const Self) PublicKey {
        return PublicKey{ .inner = self.keypair.public_key };
    }

    /// 签名消息哈希（32 字节）
    ///
    /// 注意：这个方法签名预哈希的消息。对于 EIP-712，
    /// 应该先计算结构化数据的哈希，然后调用此方法。
    pub fn sign(self: *const Self, message_hash: *const [32]u8) SignError!Signature {
        const sig = self.keypair.signPrehashed(message_hash.*, null) catch |err| switch (err) {
            error.IdentityElement => return SignError.IdentityElement,
            error.NonCanonical => return SignError.NonCanonical,
        };

        // 计算恢复 ID (v)
        const v = self.computeRecoveryId(message_hash, &sig);

        return Signature{
            .r = sig.r,
            .s = sig.s,
            .v = v,
        };
    }

    /// 计算恢复 ID
    ///
    /// 尝试使用 recovery_id = 0 和 1 恢复公钥，找到与原始公钥匹配的那个。
    fn computeRecoveryId(self: *const Self, message_hash: *const [32]u8, sig: *const EcdsaImpl.Signature) u8 {
        const pub_key = self.keypair.public_key;
        const original_bytes = pub_key.toUncompressedSec1();

        // 尝试恢复 ID 0 和 1
        for ([_]u8{ 0, 1 }) |recovery_id| {
            if (recoverPublicKeyImpl(message_hash, sig, recovery_id)) |recovered| {
                // 比较恢复的公钥与原始公钥
                const recovered_bytes = recovered.toUncompressedSec1();
                if (std.mem.eql(u8, &recovered_bytes, &original_bytes)) {
                    return recovery_id;
                }
            } else |_| {
                // 恢复失败，尝试下一个 recovery_id
                continue;
            }
        }
        // 默认返回 0（不应该发生）
        return 0;
    }

    /// 转换为十六进制字符串（带 0x 前缀）
    pub fn toHex(self: *const Self, buffer: *[66]u8) []const u8 {
        buffer[0] = '0';
        buffer[1] = 'x';
        _ = std.fmt.bufPrint(buffer[2..], "{x}", .{self.bytes}) catch unreachable;
        return buffer[0..66];
    }
};

/// 公钥
pub const PublicKey = struct {
    inner: EcdsaImpl.PublicKey,

    const Self = @This();

    /// 从未压缩格式（65 字节）创建
    pub fn fromUncompressedBytes(bytes: *const [PUBLIC_KEY_UNCOMPRESSED_LENGTH]u8) VerifyError!Self {
        const inner = EcdsaImpl.PublicKey.fromSec1(bytes) catch |err| switch (err) {
            error.IdentityElement => return VerifyError.IdentityElement,
            error.NonCanonical => return VerifyError.NonCanonical,
            else => return VerifyError.InvalidPublicKey,
        };
        return .{ .inner = inner };
    }

    /// 从压缩格式（33 字节）创建
    pub fn fromCompressedBytes(bytes: *const [PUBLIC_KEY_COMPRESSED_LENGTH]u8) VerifyError!Self {
        const inner = EcdsaImpl.PublicKey.fromSec1(bytes) catch |err| switch (err) {
            error.IdentityElement => return VerifyError.IdentityElement,
            error.NonCanonical => return VerifyError.NonCanonical,
            else => return VerifyError.InvalidPublicKey,
        };
        return .{ .inner = inner };
    }

    /// 转换为未压缩格式（65 字节）
    pub fn toUncompressedBytes(self: *const Self) [PUBLIC_KEY_UNCOMPRESSED_LENGTH]u8 {
        return self.inner.toUncompressedSec1();
    }

    /// 转换为压缩格式（33 字节）
    pub fn toCompressedBytes(self: *const Self) [PUBLIC_KEY_COMPRESSED_LENGTH]u8 {
        return self.inner.toCompressedSec1();
    }

    /// 计算以太坊地址
    ///
    /// 地址 = keccak256(public_key[1:65])[12:32]
    /// 其中 public_key 是未压缩格式（去掉 0x04 前缀）
    pub fn toAddress(self: *const Self) [ADDRESS_LENGTH]u8 {
        const uncompressed = self.toUncompressedBytes();
        // 跳过 0x04 前缀，取后 64 字节
        const pub_key_bytes = uncompressed[1..65];
        const hash = keccak.keccak256(pub_key_bytes);
        // 取哈希的后 20 字节
        return hash[12..32].*;
    }

    /// 将地址格式化为十六进制字符串（带 0x 前缀）
    pub fn addressToHex(address: *const [ADDRESS_LENGTH]u8, buffer: *[42]u8) []const u8 {
        buffer[0] = '0';
        buffer[1] = 'x';
        _ = std.fmt.bufPrint(buffer[2..], "{x}", .{address.*}) catch unreachable;
        return buffer[0..42];
    }

    /// 验证签名
    pub fn verify(self: *const Self, message_hash: *const [32]u8, signature: *const Signature) VerifyError!void {
        const sig = EcdsaImpl.Signature{
            .r = signature.r,
            .s = signature.s,
        };
        sig.verifyPrehashed(message_hash.*, self.inner) catch {
            return VerifyError.VerificationFailed;
        };
    }
};

/// 从签名和消息哈希恢复公钥（公开版本，返回 optional）
pub fn recoverPublicKey(
    message_hash: *const [32]u8,
    signature: *const EcdsaImpl.Signature,
    recovery_id: u8,
) ?EcdsaImpl.PublicKey {
    return recoverPublicKeyImpl(message_hash, signature, recovery_id) catch null;
}

/// 从签名和消息哈希恢复公钥
///
/// 实现 ECDSA 公钥恢复算法：
/// 1. 从 r 值和 recovery_id 恢复点 R
/// 2. 计算 u1 = -z * r^-1 mod n
/// 3. 计算 u2 = s * r^-1 mod n
/// 4. 公钥 Q = u1 * G + u2 * R
fn recoverPublicKeyImpl(
    message_hash: *const [32]u8,
    signature: *const EcdsaImpl.Signature,
    recovery_id: u8,
) !EcdsaImpl.PublicKey {
    const Curve = Secp256k1;
    const Scalar = Curve.scalar.Scalar;

    // 只支持 recovery_id 0 和 1
    if (recovery_id > 1) return error.InvalidRecoveryId;

    // 解析 r 和 s 为标量
    const r_scalar = Scalar.fromBytes(signature.r, .big) catch return error.InvalidSignature;
    const s_scalar = Scalar.fromBytes(signature.s, .big) catch return error.InvalidSignature;

    if (r_scalar.isZero() or s_scalar.isZero()) return error.InvalidSignature;

    // 解析消息哈希为标量
    const z = Scalar.fromBytes(message_hash.*, .big) catch return error.InvalidMessageHash;

    // 从 r 值恢复点 R
    // R.x = r, R.y 根据 recovery_id 的奇偶性确定
    const r_fe = Curve.Fe.fromBytes(signature.r, .big) catch return error.InvalidSignature;

    // 尝试根据 x 坐标找到曲线上的点
    // y^2 = x^3 + 7 (secp256k1 曲线方程)
    const R = recoverPointFromX(r_fe, recovery_id) catch return error.PointNotOnCurve;

    // 计算 r^-1 mod n
    const r_inv = r_scalar.invert();

    // 计算 coeff1 = -z * r^-1 mod n
    const neg_z = z.neg();
    const coeff1 = neg_z.mul(r_inv);

    // 计算 coeff2 = s * r^-1 mod n
    const coeff2 = s_scalar.mul(r_inv);

    // Q = coeff1 * G + coeff2 * R
    const G = Curve.basePoint;
    const coeff1_bytes = coeff1.toBytes(.big);
    const coeff2_bytes = coeff2.toBytes(.big);

    // coeff1 * G
    const c1G = G.mul(coeff1_bytes, .big) catch return error.InvalidPoint;

    // coeff2 * R
    const c2R = R.mul(coeff2_bytes, .big) catch return error.InvalidPoint;

    // Q = c1G + c2R
    const Q = c1G.add(c2R);

    // 将点转换为未压缩的 SEC1 格式，然后创建 PublicKey
    const Q_affine = Q.affineCoordinates();
    var sec1: [65]u8 = undefined;
    sec1[0] = 0x04; // 未压缩格式前缀
    @memcpy(sec1[1..33], &Q_affine.x.toBytes(.big));
    @memcpy(sec1[33..65], &Q_affine.y.toBytes(.big));

    return EcdsaImpl.PublicKey.fromSec1(&sec1) catch return error.InvalidPublicKey;
}

/// 从 x 坐标恢复曲线上的点
fn recoverPointFromX(x: Secp256k1.Fe, recovery_id: u8) !Secp256k1 {
    const Curve = Secp256k1;
    const Fe = Curve.Fe;

    // y^2 = x^3 + 7
    const x_cubed = x.mul(x).mul(x);
    const b = Fe.fromInt(7) catch unreachable;
    const y_squared = x_cubed.add(b);

    // 计算 y = sqrt(y^2)
    const y = y_squared.sqrt() catch return error.PointNotOnCurve;

    // 根据 recovery_id 选择 y 的正负
    // recovery_id 的最低位表示 y 的奇偶性
    const y_is_odd = y.isOdd();
    const should_be_odd = (recovery_id & 1) == 1;

    const final_y = if (y_is_odd != should_be_odd) y.neg() else y;

    // 从仿射坐标创建点
    return Curve.fromAffineCoordinates(.{ .x = x, .y = final_y }) catch return error.PointNotOnCurve;
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

test "PrivateKey.fromHex valid" {
    // 测试私钥（仅用于测试，不要在生产中使用！）
    const hex = "0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    const pk = try PrivateKey.fromHex(hex);
    _ = pk;
}

test "PrivateKey.fromHex without 0x prefix" {
    const hex = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    const pk = try PrivateKey.fromHex(hex);
    _ = pk;
}

test "PrivateKey.fromHex invalid length" {
    const hex = "0x1234";
    const result = PrivateKey.fromHex(hex);
    try std.testing.expectError(SignError.InvalidPrivateKeyLength, result);
}

test "PrivateKey.fromHex invalid character" {
    const hex = "0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdez";
    const result = PrivateKey.fromHex(hex);
    try std.testing.expectError(SignError.InvalidHexCharacter, result);
}

test "PrivateKey.publicKey" {
    const hex = "0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    const pk = try PrivateKey.fromHex(hex);
    const pub_key = pk.publicKey();
    const uncompressed = pub_key.toUncompressedBytes();
    // 第一个字节应该是 0x04（未压缩公钥前缀）
    try std.testing.expectEqual(@as(u8, 0x04), uncompressed[0]);
}

test "PrivateKey.toHex" {
    const hex = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    const pk = try PrivateKey.fromHex(hex);
    var buffer: [66]u8 = undefined;
    const result = pk.toHex(&buffer);
    try std.testing.expectEqualStrings("0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef", result);
}

test "PublicKey.toAddress" {
    // 已知的测试向量
    // 私钥: 0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
    // 对应的地址需要验证
    const pk = try PrivateKey.fromHex("0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef");
    const pub_key = pk.publicKey();
    const address = pub_key.toAddress();
    var buffer: [42]u8 = undefined;
    const hex_address = PublicKey.addressToHex(&address, &buffer);
    // 地址应该是 20 字节的十六进制
    try std.testing.expect(hex_address.len == 42);
    try std.testing.expect(hex_address[0] == '0');
    try std.testing.expect(hex_address[1] == 'x');
}

test "PrivateKey.sign and PublicKey.verify" {
    const pk = try PrivateKey.fromHex("0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef");
    const pub_key = pk.publicKey();

    // 创建消息哈希
    const message_hash = keccak.keccak256("Hello, Polymarket!");

    // 签名
    const signature = try pk.sign(&message_hash);

    // 验证
    try pub_key.verify(&message_hash, &signature);
}

test "Signature.toBytes and fromBytes" {
    var sig = Signature{
        .r = [_]u8{0x01} ** 32,
        .s = [_]u8{0x02} ** 32,
        .v = 27,
    };
    const bytes = sig.toBytes();
    const recovered = Signature.fromBytes(&bytes);
    try std.testing.expectEqualSlices(u8, &sig.r, &recovered.r);
    try std.testing.expectEqualSlices(u8, &sig.s, &recovered.s);
    try std.testing.expectEqual(sig.v, recovered.v);
}

test "Signature.toHex and fromHex" {
    const pk = try PrivateKey.fromHex("0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef");
    const message_hash = keccak.keccak256("test");
    const signature = try pk.sign(&message_hash);

    var buffer: [132]u8 = undefined;
    const hex = signature.toHex(&buffer);

    const recovered = Signature.fromHex(hex).?;
    try std.testing.expectEqualSlices(u8, &signature.r, &recovered.r);
    try std.testing.expectEqualSlices(u8, &signature.s, &recovered.s);
}

test "Signature.getEthereumV" {
    var sig = Signature{
        .r = [_]u8{0} ** 32,
        .s = [_]u8{0} ** 32,
        .v = 0,
    };
    try std.testing.expectEqual(@as(u8, 27), sig.getEthereumV());

    sig.v = 1;
    try std.testing.expectEqual(@as(u8, 28), sig.getEthereumV());

    sig.v = 27;
    try std.testing.expectEqual(@as(u8, 27), sig.getEthereumV());
}

test "known test vector - vitalik's address" {
    // 著名的测试私钥 (不要在生产中使用!)
    // 私钥: 0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318
    // 地址: 0x2c7536E3605D9C16a7a3D7b1898e529396a65c23
    const pk = try PrivateKey.fromHex("0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318");
    const pub_key = pk.publicKey();
    const address = pub_key.toAddress();
    var buffer: [42]u8 = undefined;
    const hex_address = PublicKey.addressToHex(&address, &buffer);

    // 转换为小写进行比较
    try std.testing.expectEqualStrings("0x2c7536e3605d9c16a7a3d7b1898e529396a65c23", hex_address);
}

test "PrivateKey.generate" {
    const pk1 = try PrivateKey.generate();
    const pk2 = try PrivateKey.generate();

    // 两个随机私钥应该不同
    try std.testing.expect(!std.mem.eql(u8, &pk1.bytes, &pk2.bytes));
}
