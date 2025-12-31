# secp256k1 ECDSA 签名

> 以太坊兼容的椭圆曲线数字签名

## 概述

本模块提供 secp256k1 椭圆曲线上的 ECDSA 签名功能，用于：
- 以太坊交易签名
- EIP-712 结构化数据签名
- L1 认证签名

## 类型

### PrivateKey

私钥类型，封装 32 字节密钥。

```zig
pub const PrivateKey = struct {
    bytes: [32]u8,
    
    pub fn fromBytes(bytes: *const [32]u8) !PrivateKey;
    pub fn fromHex(hex: []const u8) !PrivateKey;
    pub fn generate() !PrivateKey;
    pub fn publicKey(self: *const PrivateKey) PublicKey;
    pub fn sign(self: *const PrivateKey, message_hash: *const [32]u8) !Signature;
    pub fn toHex(self: *const PrivateKey, buffer: *[66]u8) []const u8;
};
```

### PublicKey

公钥类型，封装椭圆曲线点。

```zig
pub const PublicKey = struct {
    pub fn fromUncompressedBytes(bytes: *const [65]u8) !PublicKey;
    pub fn fromCompressedBytes(bytes: *const [33]u8) !PublicKey;
    pub fn toUncompressedBytes(self: *const PublicKey) [65]u8;
    pub fn toCompressedBytes(self: *const PublicKey) [33]u8;
    pub fn toAddress(self: *const PublicKey) [20]u8;
    pub fn addressToHex(address: *const [20]u8, buffer: *[42]u8) []const u8;
    pub fn verify(self: *const PublicKey, message_hash: *const [32]u8, signature: *const Signature) !void;
};
```

### Signature

签名类型，包含 r, s, v 分量。

```zig
pub const Signature = struct {
    r: [32]u8,
    s: [32]u8,
    v: u8,
    
    pub fn fromBytes(bytes: *const [65]u8) Signature;
    pub fn toBytes(self: *const Signature) [65]u8;
    pub fn fromHex(hex: []const u8) ?Signature;
    pub fn toHex(self: *const Signature, buffer: *[132]u8) []const u8;
    pub fn getEthereumV(self: *const Signature) u8;
    pub fn setEthereumV(self: *Signature, eth_v: u8) void;
};
```

### 错误类型

```zig
pub const SignError = error{
    InvalidPrivateKey,
    SigningFailed,
    InvalidHexCharacter,
    InvalidPrivateKeyLength,
    IdentityElement,
    NonCanonical,
};

pub const VerifyError = error{
    InvalidPublicKey,
    InvalidSignature,
    VerificationFailed,
    IdentityElement,
    NonCanonical,
};
```

## 常量

| 常量 | 值 | 描述 |
|------|---|------|
| `PRIVATE_KEY_LENGTH` | 32 | 私钥长度（字节） |
| `PUBLIC_KEY_UNCOMPRESSED_LENGTH` | 65 | 未压缩公钥长度 |
| `PUBLIC_KEY_COMPRESSED_LENGTH` | 33 | 压缩公钥长度 |
| `SIGNATURE_LENGTH` | 65 | 签名长度 (r + s + v) |
| `ADDRESS_LENGTH` | 20 | 以太坊地址长度 |

## 使用示例

### 创建/加载私钥

```zig
const crypto = @import("poly-sdk-zig").crypto;

// 从十六进制字符串加载
const pk = try crypto.PrivateKey.fromHex("0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318");

// 从字节数组加载
var bytes: [32]u8 = ...;
const pk2 = try crypto.PrivateKey.fromBytes(&bytes);

// 生成随机私钥
const pk3 = try crypto.PrivateKey.generate();
```

### 获取公钥和地址

```zig
const private_key = try crypto.PrivateKey.fromHex("0x...");
const public_key = private_key.publicKey();

// 获取以太坊地址
const address = public_key.toAddress();

// 格式化为十六进制
var buffer: [42]u8 = undefined;
const hex_address = crypto.PublicKey.addressToHex(&address, &buffer);
// => "0x2c7536e3605d9c16a7a3d7b1898e529396a65c23"
```

### 签名和验证

```zig
// 计算消息哈希
const message_hash = crypto.keccak256("Hello, Polymarket!");

// 签名
const signature = try private_key.sign(&message_hash);

// 验证
try public_key.verify(&message_hash, &signature);
```

### 签名序列化

```zig
// 转换为字节
const bytes = signature.toBytes();  // [65]u8

// 转换为十六进制
var buffer: [132]u8 = undefined;
const hex = signature.toHex(&buffer);  // "0x..."

// 从十六进制解析
const sig = crypto.Signature.fromHex(hex).?;
```

### 以太坊 v 值

```zig
// 获取以太坊格式的 v (27 或 28)
const eth_v = signature.getEthereumV();

// 设置以太坊格式的 v
signature.setEthereumV(27);
```

## 地址计算

以太坊地址从公钥计算：

```
address = keccak256(public_key[1:65])[12:32]
```

1. 取未压缩公钥（65 字节），去掉第一个字节（0x04 前缀）
2. 计算剩余 64 字节的 Keccak256 哈希
3. 取哈希的后 20 字节作为地址

## 已知测试向量

| 私钥 | 地址 |
|------|------|
| `0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318` | `0x2c7536e3605d9c16a7a3d7b1898e529396a65c23` |

## 安全注意事项

1. **私钥保护**: 永远不要在日志或错误消息中暴露私钥
2. **随机性**: 签名需要随机数，使用不安全的随机数会导致私钥泄露
3. **验证**: 总是验证签名后再使用
4. **内存清理**: 使用完私钥后应该清零内存

## 技术实现

本模块使用 Zig 0.15 的 `std.crypto.sign.ecdsa.Ecdsa` 结合 `Secp256k1` 曲线和 `Keccak256` 哈希：

```zig
const EcdsaSecp256k1Keccak256 = std.crypto.sign.ecdsa.Ecdsa(
    std.crypto.ecc.Secp256k1,
    std.crypto.hash.sha3.Keccak256,
);
```
