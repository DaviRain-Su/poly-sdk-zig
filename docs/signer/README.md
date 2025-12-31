# 签名模块 (Signer)

> 以太坊签名相关功能，包括钱包管理和 EIP-712 类型化数据签名。

## 概述

签名模块提供以太坊交易和消息签名所需的核心功能：

- **钱包管理**: 私钥、公钥、地址封装
- **EIP-191 签名**: 个人消息签名
- **EIP-712 签名**: 类型化结构数据签名（Polymarket 订单签名）

## 模块结构

```
src/signer/
├── mod.zig       # 模块入口，导出所有公共 API
├── wallet.zig    # 钱包类型
└── eip712.zig    # EIP-712 类型化数据签名
```

## 快速开始

```zig
const poly = @import("poly-sdk-zig");
const signer = poly.signer;

// 1. 创建钱包
const wallet = try signer.Wallet.fromPrivateKeyHex("0x...");

// 2. 获取地址
const address = wallet.getAddressChecksumHex();  // "0x..."

// 3. 签名消息 (EIP-191)
const sig = try wallet.signMessage("Hello, Polymarket!");

// 4. 签名 Polymarket 订单 (EIP-712)
const order = signer.Order{
    .salt = 12345,
    .maker = wallet.address_bytes,
    .signer = wallet.address_bytes,
    .taker = [_]u8{0} ** 20,
    .token_id = 1,
    .maker_amount = 100,
    .taker_amount = 65,
    .expiration = 0,
    .nonce = 0,
    .fee_rate_bps = 0,
    .side = 0,  // BUY
    .signature_type = 0,  // EOA
};

const digest = signer.hashPolymarketOrder(&order, signer.POLYGON_CHAIN_ID, false);
const order_sig = try wallet.sign(&digest);
```

## 子模块

| 模块 | 描述 | 文档 |
|------|------|------|
| `wallet` | 钱包类型（私钥/公钥/地址管理） | [wallet.md](wallet.md) |
| `eip712` | EIP-712 类型化数据签名 | [eip712.md](eip712.md) |

## 主要类型

### Wallet

钱包类型，封装私钥、公钥和以太坊地址。

```zig
pub const Wallet = struct {
    private_key: Secret(PrivateKey),  // 使用 Secret 保护
    public_key: PublicKey,
    address_bytes: [20]u8,
};
```

详见 [wallet.md](wallet.md)。

### EIP-712 类型

用于 EIP-712 结构化数据签名的类型定义。

```zig
pub const Domain = struct {
    name: ?[]const u8,
    version: ?[]const u8,
    chain_id: ?u256,
    verifying_contract: ?[20]u8,
    salt: ?[32]u8,
};

pub const Order = struct {
    salt: u256,
    maker: [20]u8,
    // ... 更多字段
};
```

详见 [eip712.md](eip712.md)。

## 安全考虑

1. **私钥保护**: 使用 `Secret(PrivateKey)` 包装，防止意外日志泄露
2. **常量时间比较**: Secret 类型使用常量时间比较，防止时序攻击
3. **签名验证**: 提供签名验证功能，确保签名正确性

## 相关链接

- [EIP-191: Signed Data Standard](https://eips.ethereum.org/EIPS/eip-191)
- [EIP-712: Typed structured data hashing and signing](https://eips.ethereum.org/EIPS/eip-712)
- [Polymarket CLOB API 文档](https://docs.polymarket.com/)
