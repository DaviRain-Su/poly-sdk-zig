# Wallet

> 以太坊钱包类型，封装私钥、公钥和地址。

## 概述

`Wallet` 类型是对以太坊账户的完整封装，包含：

- 私钥（使用 `Secret` 保护，防止意外日志泄露）
- 公钥（secp256k1 曲线）
- 以太坊地址（20 字节，Keccak256 哈希的后 20 字节）

## 类型定义

```zig
pub const Wallet = struct {
    /// 私钥（使用 Secret 包装保护）
    private_key: Secret(PrivateKey),
    
    /// 公钥
    public_key: PublicKey,
    
    /// 以太坊地址（20 字节）
    address_bytes: [20]u8,
};
```

## 创建钱包

### 从私钥十六进制字符串

```zig
const wallet = try Wallet.fromPrivateKeyHex("0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318");
// 或不带 0x 前缀
const wallet2 = try Wallet.fromPrivateKeyHex("4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318");
```

### 从私钥对象

```zig
const pk = try PrivateKey.fromHex("0x...");
const wallet = Wallet.fromPrivateKey(pk);
```

### 生成随机钱包

```zig
const wallet = try Wallet.generate();
```

## 获取地址

### EIP-55 校验和格式（推荐）

```zig
const hex = wallet.getAddressChecksumHex();  // [42]u8
// 例如: "0x2C7536E3605D9C16a7a3D7b1898e529396a65c23"
```

### 小写格式

```zig
var buffer: [42]u8 = undefined;
const hex = wallet.getAddressLowerHex(&buffer);
// 例如: "0x2c7536e3605d9c16a7a3d7b1898e529396a65c23"
```

### Address 类型

```zig
const address = wallet.getAddress();  // Address 类型
```

## 签名

### 签名消息哈希（32 字节）

```zig
const message_hash = keccak256("Hello, World!");
const signature = try wallet.sign(&message_hash);
```

### 签名任意消息（EIP-191）

EIP-191 会自动添加以太坊签名前缀：`"\x19Ethereum Signed Message:\n" + len(message)`

```zig
const signature = try wallet.signMessage("Hello, Polymarket!");
```

### 验证签名

```zig
const is_valid = wallet.verify(&message_hash, &signature);
```

## 完整示例

```zig
const poly = @import("poly-sdk-zig");
const Wallet = poly.Wallet;
const keccak256 = poly.keccak256;

// 创建钱包
const wallet = try Wallet.fromPrivateKeyHex(
    "0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318"
);

// 获取地址
const address = wallet.getAddressChecksumHex();
std.debug.print("Address: {s}\n", .{&address});

// 签名消息
const message = "Hello, Polymarket!";
const signature = try wallet.signMessage(message);

// 手动验证（计算 EIP-191 哈希）
var hasher = poly.crypto.Hasher.init();
hasher.update("\x19Ethereum Signed Message:\n");
hasher.update("18");  // message.len
hasher.update(message);
const expected_hash = hasher.final();

// 验证签名
const is_valid = wallet.verify(&expected_hash, &signature);
std.debug.print("Signature valid: {}\n", .{is_valid});
```

## 错误类型

```zig
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
```

## 安全注意事项

1. **私钥保护**: `private_key` 使用 `Secret` 包装，格式化时输出 `[REDACTED]`
2. **不要日志记录私钥**: 即使通过 `reveal()` 获取私钥，也不要将其写入日志
3. **安全存储**: 在生产环境中，私钥应存储在安全的密钥管理系统中

## 测试覆盖

- `Wallet.fromPrivateKeyHex` - 有效/无效输入
- `Wallet.generate` - 随机生成
- `Wallet.getAddress` - 地址格式
- `Wallet.sign` / `verify` - 签名和验证
- `Wallet.signMessage` - EIP-191 签名
- Secret 保护 - 格式化输出 `[REDACTED]`
