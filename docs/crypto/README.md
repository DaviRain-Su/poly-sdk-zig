# 加密模块 (crypto)

> 提供 Polymarket API 认证所需的加密原语

## 概述

`crypto` 模块封装了 Zig 标准库的加密功能，为 Polymarket API 提供：

- **Keccak256** - 以太坊兼容的哈希算法，用于 EIP-712 签名
- **secp256k1 ECDSA** - 椭圆曲线数字签名，用于交易签名
- **HMAC-SHA256** - 消息认证码，用于 L2 API 请求签名

## 模块结构

```
src/crypto/
├── mod.zig           # 模块导出
├── keccak.zig        # Keccak256 哈希
├── ecdsa.zig         # secp256k1 ECDSA 签名
└── hmac.zig          # HMAC-SHA256 认证
```

## 快速开始

```zig
const crypto = @import("poly-sdk-zig").crypto;

// Keccak256 哈希
const hash = crypto.keccak256("hello");
// => 0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8

// ECDSA 签名
const private_key = try crypto.PrivateKey.fromHex("0x...");
const public_key = private_key.publicKey();
const address = public_key.toAddress();

const message_hash = crypto.keccak256("message");
const signature = try private_key.sign(&message_hash);
try public_key.verify(&message_hash, &signature);

// HMAC-SHA256 (用于 L2 认证)
const mac = crypto.hmacSha256("api_secret", "message");
var buffer: [44]u8 = undefined;
const base64_mac = crypto.macToBase64(&mac, &buffer);
```

## 子模块

| 文件 | 文档 | 描述 |
|------|------|------|
| keccak.zig | [keccak.md](./keccak.md) | Keccak256 哈希 |
| ecdsa.zig | [ecdsa.md](./ecdsa.md) | secp256k1 ECDSA 签名 |
| hmac.zig | [hmac.md](./hmac.md) | HMAC-SHA256 认证 |

## 类型导出

### 从 keccak.zig

| 类型/函数 | 描述 |
|----------|------|
| `Hash` | 32 字节哈希类型 |
| `Hasher` | 流式哈希器 |
| `keccak256(data)` | 计算 Keccak256 哈希 |
| `keccak256Multi(parts)` | 多块哈希 |

### 从 ecdsa.zig

| 类型/函数 | 描述 |
|----------|------|
| `PrivateKey` | 私钥类型 |
| `PublicKey` | 公钥类型 |
| `Signature` | 签名类型 (r, s, v) |
| `SignError` | 签名错误 |
| `VerifyError` | 验证错误 |

### 从 hmac.zig

| 类型/函数 | 描述 |
|----------|------|
| `Mac` | 32 字节 MAC 类型 |
| `Hmac` | 流式 HMAC 计算器 |
| `hmacSha256(key, message)` | 计算 HMAC |
| `macToBase64(mac, buffer)` | Base64 编码 |
| `hmacVerify(key, message, expected)` | 验证 MAC |

## 使用场景

### 1. EIP-712 签名（用于 L1 认证和订单签名）

```zig
// 1. 计算类型哈希
const type_hash = crypto.keccak256(
    "Order(uint256 salt,address maker,address signer,...)"
);

// 2. 计算结构体哈希
var hasher = crypto.Hasher.init();
hasher.update(&type_hash);
hasher.update(&encoded_data);
const struct_hash = hasher.final();

// 3. 计算最终摘要
const domain_separator = crypto.keccak256(...);
const digest = crypto.keccak256Multi(&.{
    "\x19\x01",
    &domain_separator,
    &struct_hash,
});

// 4. 签名
const signature = try private_key.sign(&digest);
```

### 2. L2 API 认证

```zig
// 构建签名消息: timestamp + method + path + body
var hmac = crypto.Hmac.init(api_secret);
hmac.update(timestamp);
hmac.update("POST");
hmac.update("/order");
hmac.update(body_json);
const mac = hmac.final();

// Base64 编码作为 POLY-SIGNATURE header
var buffer: [44]u8 = undefined;
const signature = crypto.macToBase64(&mac, &buffer);
```

### 3. 地址计算

```zig
const private_key = try crypto.PrivateKey.fromHex("0x...");
const public_key = private_key.publicKey();
const address = public_key.toAddress();

var buffer: [42]u8 = undefined;
const hex_address = crypto.PublicKey.addressToHex(&address, &buffer);
// => "0x2c7536e3605d9c16a7a3d7b1898e529396a65c23"
```

## 安全注意事项

1. **私钥保护**: 私钥应该使用 `Secret` 类型包装，防止意外日志泄露
2. **常量时间比较**: 使用 `hmacVerify` 进行 MAC 验证，它使用常量时间比较防止时序攻击
3. **随机数生成**: `PrivateKey.generate()` 使用系统安全随机数生成器
4. **内存清理**: 敏感数据使用后应该清零（Zig 的 `@memset` 可能被优化掉，考虑使用 `std.crypto.utils.secureZero`）

## 技术实现

本模块使用 Zig 0.15 标准库的加密原语：

```zig
// Keccak256
const Keccak256 = std.crypto.hash.sha3.Keccak256;

// HMAC-SHA256
const HmacSha256 = std.crypto.auth.hmac.sha2.HmacSha256;

// secp256k1 ECDSA with Keccak256
const EcdsaSecp256k1Keccak256 = std.crypto.sign.ecdsa.Ecdsa(
    std.crypto.ecc.Secp256k1,
    std.crypto.hash.sha3.Keccak256,
);
```

## 测试

```bash
# 测试整个 crypto 模块
zig test src/crypto/mod.zig

# 测试单个子模块
zig test src/crypto/keccak.zig
zig test src/crypto/ecdsa.zig
zig test src/crypto/hmac.zig
```

## 参考资料

- [EIP-712: Typed structured data hashing and signing](https://eips.ethereum.org/EIPS/eip-712)
- [Ethereum Yellow Paper - Appendix F](https://ethereum.github.io/yellowpaper/paper.pdf)
- [Keccak256 规范](https://keccak.team/keccak.html)
- [secp256k1 曲线参数](https://www.secg.org/sec2-v2.pdf)
