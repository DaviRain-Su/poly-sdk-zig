# Polymarket Zig CLOB Client

[![Zig](https://img.shields.io/badge/Zig-0.13.0-orange)](https://ziglang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

一个高性能、类型安全的 Zig 语言实现的 Polymarket Central Limit Order Book (CLOB) 客户端 SDK。

## 目录

- [概述](#概述)
- [特性](#特性)
- [快速开始](#快速开始)
- [安装](#安装)
- [使用示例](#使用示例)
- [架构设计](#架构设计)
- [API 参考](#api-参考)
- [开发指南](#开发指南)
- [贡献指南](#贡献指南)
- [关于 Polymarket](#关于-polymarket)

## 概述

本项目是 [Polymarket rs-clob-client](https://github.com/Polymarket/rs-clob-client) 的 Zig 语言移植版本。Polymarket 是全球最大的预测市场平台，允许用户通过对未来事件下注来获取信息和利润。

### 核心功能

- **类型化 CLOB 请求**：订单、交易、市场、余额等完整类型支持
- **双重认证流程**：
  - 标准认证流程 (L1/L2)
  - [Builder](https://docs.polymarket.com/developers/builders/builder-intro) 认证流程
- **编译时状态机**：
  - 防止在未认证状态下使用认证端点
  - 编译时强制正确的状态转换
- **签名器支持**：支持本地签名和远程签名（如 AWS KMS）
- **零成本抽象**：热路径中无动态分发
- **订单构建器**：便于构建和签名订单
- **完整序列化支持**：JSON 序列化/反序列化
- **灵活的 I/O 模式**：同步阻塞（默认）或异步（通过 libxev）

## 特性

| 特性 | 描述 | 状态 |
|------|------|------|
| 未认证客户端 | 只读访问市场数据 | 计划中 |
| L1 认证 | 私钥签名获取 API 凭证 | 计划中 |
| L2 认证 | API 凭证认证请求 | 计划中 |
| Builder 认证 | Builder 程序特殊认证 | 计划中 |
| 限价单 | 创建和提交限价订单 | 计划中 |
| 市价单 | 创建和提交市价订单 | 计划中 |
| WebSocket | 实时数据流 | 计划中 |
| 地理封锁检测 | 检测 IP 访问限制 | 计划中 |

## 快速开始

### 系统要求

- Zig >= 0.13.0
- 网络连接

### 安装

在 `build.zig.zon` 中添加依赖：

```zig
.dependencies = .{
    .poly_sdk_zig = .{
        .url = "https://github.com/yourusername/poly-sdk-zig/archive/refs/tags/v0.1.0.tar.gz",
        .hash = "...",
    },
},
```

在 `build.zig` 中配置：

```zig
const poly_sdk = b.dependency("poly_sdk_zig", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("poly_sdk", poly_sdk.module("poly_sdk"));
```

## 使用示例

### 未认证客户端（只读）

```zig
const std = @import("std");
const poly = @import("poly_sdk");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建未认证客户端
    var client = try poly.clob.Client.init(allocator, .{});
    defer client.deinit();

    // 检查服务状态
    const ok = try client.ok();
    std.debug.print("Server status: {s}\n", .{ok});

    // 获取市场数据
    const markets = try client.markets(null);
    for (markets.data) |market| {
        std.debug.print("Market: {s}\n", .{market.condition_id});
    }
}
```

### 认证客户端

```zig
const std = @import("std");
const poly = @import("poly_sdk");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 从环境变量获取私钥
    const private_key = std.posix.getenv("POLYMARKET_PRIVATE_KEY") orelse 
        return error.MissingPrivateKey;

    // 创建签名器
    const signer = try poly.crypto.LocalSigner.fromHex(private_key);

    // 创建认证客户端
    var client = try poly.clob.Client.init(allocator, .{});
    defer client.deinit();

    // 认证
    var auth_client = try client.authenticate(&signer);
    defer auth_client.deinit();

    // 获取 API 密钥
    const api_keys = try auth_client.apiKeys();
    std.debug.print("API Keys: {any}\n", .{api_keys});
}
```

### 下单示例

```zig
const std = @import("std");
const poly = @import("poly_sdk");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const private_key = std.posix.getenv("POLYMARKET_PRIVATE_KEY") orelse 
        return error.MissingPrivateKey;

    const signer = try poly.crypto.LocalSigner.fromHex(private_key);

    var client = try poly.clob.Client.init(allocator, .{});
    defer client.deinit();

    var auth_client = try client.authenticate(&signer);
    defer auth_client.deinit();

    // 创建限价单
    const order = try auth_client.limitOrder()
        .tokenId("your-token-id")
        .size(poly.Decimal.fromFloat(100.0))
        .price(poly.Decimal.fromFloat(0.65))
        .side(.buy)
        .build();

    // 签名并提交订单
    const signed_order = try auth_client.sign(&signer, order);
    const response = try auth_client.postOrder(signed_order);

    std.debug.print("Order response: {any}\n", .{response});
}
```

## 架构设计

详细架构设计请参阅 [ARCHITECTURE.md](./ARCHITECTURE.md)。

### 模块结构

```
poly-sdk-zig/
├── src/
│   ├── root.zig          # 库入口
│   ├── clob/             # CLOB 客户端模块
│   │   ├── client.zig    # 客户端实现
│   │   ├── types/        # 类型定义
│   │   │   ├── mod.zig
│   │   │   ├── request.zig
│   │   │   └── response.zig
│   │   ├── order_builder.zig
│   │   └── ws/           # WebSocket
│   ├── auth/             # 认证模块
│   │   ├── mod.zig
│   │   ├── l1.zig        # L1 认证
│   │   ├── l2.zig        # L2 认证
│   │   └── builder.zig   # Builder 认证
│   ├── crypto/           # 加密模块
│   │   ├── signer.zig
│   │   ├── eip712.zig
│   │   └── hmac.zig
│   ├── types/            # 公共类型
│   │   └── decimal.zig
│   └── error.zig         # 错误定义
├── examples/             # 示例代码
├── tests/                # 测试
└── docs/                 # 文档
```

## API 参考

详细 API 参考请参阅 [API_REFERENCE.md](./API_REFERENCE.md)。

## 开发指南

### 构建

```bash
zig build
```

### 运行测试

```bash
zig build test
```

### 运行示例

```bash
zig build run-example-unauthenticated
```

## 贡献指南

我们欢迎社区贡献！请查看 [CONTRIBUTING.md](./CONTRIBUTING.md) 了解如何参与。

## 许可证

MIT License - 详见 [LICENSE](../LICENSE)

## 关于 Polymarket

[Polymarket](https://docs.polymarket.com/polymarket-learn/get-started/what-is-polymarket) 是全球最大的预测市场，允许您通过对各种主题的未来事件下注来保持信息灵通并从您的知识中获利。研究表明，预测市场通常比专家更准确，因为它们将新闻、民意调查和专家意见组合成一个单一值，代表市场对事件几率的看法。

## 相关链接

- [Polymarket 官方网站](https://polymarket.com)
- [Polymarket 开发者文档](https://docs.polymarket.com)
- [原始 Rust 客户端](https://github.com/Polymarket/rs-clob-client)
- [Polymarket Discord](https://discord.gg/polymarket)
