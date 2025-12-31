# 订单构建器 (OrderBuilder)

> 创建和签名 Polymarket CLOB 订单

## 概述

`OrderBuilder` 提供了创建 Polymarket 限价单的功能。它封装了：

- 价格和数量验证
- 金额计算（maker/taker amounts）
- EIP-712 签名生成

## 快速开始

```zig
const poly = @import("poly-sdk-zig");

// 1. 创建钱包
const wallet = try poly.Wallet.fromPrivateKeyHex("0x...");

// 2. 创建订单构建器
const builder = poly.OrderBuilder.init(&wallet, .{ 
    .chain_id = 137,  // Polygon mainnet
});

// 3. 创建限价单
const order = try builder.createOrder(.{
    .token_id = "123456789012345678901234567890123456789",
    .price = try poly.Decimal.fromString("0.65"),
    .size = try poly.Decimal.fromString("100"),
    .side = .BUY,
}, .{
    .tick_size = .@"0.01",
    .neg_risk = false,
});

// 4. 获取签名 hex
var sig_buf: [132]u8 = undefined;
const signature_hex = order.getSignatureHex(&sig_buf);
```

## 类型

### OrderBuilder

订单构建器结构体。

```zig
pub const OrderBuilder = struct {
    wallet: *const Wallet,
    chain_id: u64,
};
```

**字段**:
- `wallet`: 钱包引用，用于签名
- `chain_id`: 链 ID（137 = Polygon mainnet，80002 = Amoy testnet）

### OrderBuilderOptions

构建器初始化选项。

```zig
pub const OrderBuilderOptions = struct {
    chain_id: u64 = 137,
};
```

### OrderArgs

限价单参数。

```zig
pub const OrderArgs = struct {
    token_id: []const u8,      // Token ID（市场条件代币）
    price: Decimal,            // 价格 (0 < price < 1)
    size: Decimal,             // 数量
    side: Side,                // 交易方向 (BUY/SELL)
    fee_rate_bps: u16 = 0,     // 费率（基点）
    expiration: u64 = 0,       // 过期时间戳（0 = 永不过期）
    nonce: u64 = 0,            // Nonce
    taker: ?[20]u8 = null,     // 指定接单者（null = 公开订单）
};
```

### CreateOrderOptions

创建订单选项。

```zig
pub const CreateOrderOptions = struct {
    tick_size: TickSize = .@"0.01",      // 价格精度
    neg_risk: bool = false,               // 是否为 Neg Risk 市场
    signature_type: SignatureType = .EOA, // 签名类型
};
```

### SignedOrder

签名后的订单。

```zig
pub const SignedOrder = struct {
    salt: u256,
    maker: [20]u8,
    signer: [20]u8,
    taker: [20]u8,
    token_id: u256,
    maker_amount: u256,
    taker_amount: u256,
    expiration: u256,
    nonce: u256,
    fee_rate_bps: u256,
    side: Side,
    signature_type: SignatureType,
    signature: Signature,
};
```

### Side

交易方向。

```zig
pub const Side = enum(u8) {
    BUY = 0,   // 买入（支付 USDC，获得代币）
    SELL = 1,  // 卖出（支付代币，获得 USDC）
};
```

### TickSize

价格精度。

```zig
pub const TickSize = enum {
    @"0.1",    // 10% 精度
    @"0.01",   // 1% 精度（最常用）
    @"0.001",  // 0.1% 精度
    @"0.0001", // 0.01% 精度
};
```

### SignatureType

签名类型。

```zig
pub const SignatureType = enum(u8) {
    EOA = 0,            // 外部账户（MetaMask、硬件钱包等）
    POLY_PROXY = 1,     // Polymarket 代理钱包
    POLY_GNOSIS_SAFE = 2, // Polymarket Gnosis Safe
};
```

## 函数

### OrderBuilder.init

```zig
pub fn init(wallet: *const Wallet, options: OrderBuilderOptions) OrderBuilder
```

创建订单构建器实例。

**参数**:
- `wallet`: 钱包引用
- `options`: 构建器选项

**返回**: `OrderBuilder` 实例

**示例**:
```zig
const builder = OrderBuilder.init(&wallet, .{ .chain_id = 137 });
```

### OrderBuilder.createOrder

```zig
pub fn createOrder(
    self: *const Self,
    args: OrderArgs,
    options: CreateOrderOptions,
) OrderBuilderError!SignedOrder
```

创建并签名限价单。

**参数**:
- `args`: 订单参数
- `options`: 创建选项

**返回**: 签名后的订单

**错误**:
- `InvalidPrice`: 价格无效（<= 0 或 >= 1）
- `InvalidSize`: 数量无效（<= 0）
- `InvalidTokenId`: Token ID 无效
- `SigningFailed`: 签名失败
- `Overflow`: 数值溢出

**示例**:
```zig
// 创建买单
const buy_order = try builder.createOrder(.{
    .token_id = "12345",
    .price = try Decimal.fromString("0.65"),
    .size = try Decimal.fromString("100"),
    .side = .BUY,
}, .{
    .tick_size = .@"0.01",
});

// 创建卖单
const sell_order = try builder.createOrder(.{
    .token_id = "12345",
    .price = try Decimal.fromString("0.70"),
    .size = try Decimal.fromString("50"),
    .side = .SELL,
}, .{
    .tick_size = .@"0.01",
});
```

### SignedOrder.getOrderHash

```zig
pub fn getOrderHash(self: *const Self, chain_id: u64, neg_risk: bool) [32]u8
```

获取订单的 EIP-712 哈希。

### SignedOrder.getSignatureHex

```zig
pub fn getSignatureHex(self: *const Self, buffer: *[132]u8) []const u8
```

获取签名的十六进制字符串（0x 前缀）。

## 金额计算

订单金额根据交易方向计算：

| 方向 | maker_amount | taker_amount |
|------|--------------|--------------|
| BUY  | price × size (USDC) | size (代币) |
| SELL | size (代币) | price × size (USDC) |

**单位**: USDC 和条件代币都使用 6 位小数。

**示例**:
```
买入 100 个代币，价格 0.65:
- maker_amount = 0.65 × 100 = 65 USDC = 65,000,000（最小单位）
- taker_amount = 100 代币 = 100,000,000（最小单位）

卖出 200 个代币，价格 0.35:
- maker_amount = 200 代币 = 200,000,000（最小单位）
- taker_amount = 0.35 × 200 = 70 USDC = 70,000,000（最小单位）
```

## 价格验证

- 价格必须 > 0 且 < 1（概率市场）
- 价格会自动舍入到指定的 `tick_size`

## 链 ID

| 网络 | Chain ID |
|------|----------|
| Polygon Mainnet | 137 |
| Polygon Amoy Testnet | 80002 |

不同链 ID 会产生不同的 EIP-712 签名。

## 完整示例

```zig
const std = @import("std");
const poly = @import("poly-sdk-zig");

pub fn main() !void {
    // 创建钱包
    const wallet = try poly.Wallet.fromPrivateKeyHex(
        "0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318",
    );

    // 创建构建器
    const builder = poly.OrderBuilder.init(&wallet, .{ .chain_id = 137 });

    // 创建限价买单
    const order = try builder.createOrder(.{
        .token_id = "48331043336612883890938759509493159234755048973500640148014422747788308965732",
        .price = try poly.Decimal.fromString("0.65"),
        .size = try poly.Decimal.fromString("100"),
        .side = .BUY,
        .fee_rate_bps = 0,
        .expiration = 0, // 永不过期
    }, .{
        .tick_size = .@"0.01",
        .neg_risk = false,
        .signature_type = .EOA,
    });

    // 输出订单信息
    std.debug.print("Order created:\n", .{});
    std.debug.print("  salt: {d}\n", .{order.salt});
    std.debug.print("  token_id: {d}\n", .{order.token_id});
    std.debug.print("  maker_amount: {d}\n", .{order.maker_amount});
    std.debug.print("  taker_amount: {d}\n", .{order.taker_amount});
    std.debug.print("  side: {s}\n", .{order.side.toString()});

    // 获取签名 hex
    var sig_buf: [132]u8 = undefined;
    const sig_hex = order.getSignatureHex(&sig_buf);
    std.debug.print("  signature: {s}\n", .{sig_hex});
}
```

## 注意事项

1. **钱包生命周期**: `OrderBuilder` 持有钱包的引用，确保钱包在使用期间有效
2. **价格范围**: Polymarket 概率市场价格必须在 (0, 1) 范围内
3. **Token ID**: 来自 Polymarket API 的市场条件代币 ID
4. **Neg Risk 市场**: 某些市场使用不同的合约地址，需要设置 `neg_risk = true`
5. **测试网络**: 使用 Amoy testnet (chain_id = 80002) 进行测试

## 相关模块

- [Wallet](../signer/wallet.md) - 钱包和密钥管理
- [EIP-712](../signer/eip712.md) - EIP-712 签名
- [Decimal](../types/decimal.md) - 高精度十进制数
