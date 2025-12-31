# 订单模块 (order)

> Polymarket 订单创建和管理

## 概述

订单模块提供创建、签名和管理 Polymarket CLOB 订单的功能。

## 模块结构

```
src/order/
├── mod.zig         # 模块入口和导出
├── types.zig       # 订单类型定义
├── calculator.zig  # 金额和价格计算
└── builder.zig     # 订单构建器
```

## 主要组件

| 组件 | 描述 | 文档 |
|------|------|------|
| OrderBuilder | 订单构建器 | [builder.md](builder.md) |
| Side | 交易方向 (BUY/SELL) | [builder.md](builder.md#side) |
| SignedOrder | 签名后的订单 | [builder.md](builder.md#signedorder) |
| TickSize | 价格精度 | [builder.md](builder.md#ticksize) |

## 快速开始

```zig
const poly = @import("poly-sdk-zig");

// 创建钱包和构建器
const wallet = try poly.Wallet.fromPrivateKeyHex("0x...");
const builder = poly.OrderBuilder.init(&wallet, .{ .chain_id = 137 });

// 创建限价单
const order = try builder.createOrder(.{
    .token_id = "12345",
    .price = try poly.Decimal.fromString("0.65"),
    .size = try poly.Decimal.fromString("100"),
    .side = .BUY,
}, .{
    .tick_size = .@"0.01",
});
```

## 金额计算公式

| 方向 | Maker 支付 | Taker 获得 |
|------|-----------|-----------|
| BUY  | price × size (USDC) | size (代币) |
| SELL | size (代币) | price × size (USDC) |

## 测试

```bash
# 运行订单模块测试
zig test src/order/mod.zig

# 运行所有测试
zig build test
```

## 相关文档

- [订单构建器](builder.md) - 详细 API 文档
- [签名模块](../signer/README.md) - 钱包和签名
- [类型模块](../types/README.md) - Decimal 等核心类型
