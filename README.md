# poly-sdk-zig

[![Zig](https://img.shields.io/badge/Zig-0.15.2+-orange)](https://ziglang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Polymarket CLOB API 的原生 Zig 客户端。

## 功能特性

- **类型安全**: 编译时检查，无效 API 使用会产生编译错误
- **精确计算**: Decimal 类型用于金融计算（无浮点误差）
- **显式分配**: 无隐藏内存分配，清晰的所有权语义
- **零成本抽象**: 无运行时开销
- **最小依赖**: 仅使用 Zig 标准库

## 安装

```zig
// build.zig.zon
.dependencies = .{
    .poly_sdk_zig = .{
        .url = "https://github.com/anthropics/poly-sdk-zig/archive/main.tar.gz",
        .hash = "...",
    },
},
```

**要求**: Zig >= 0.15.2

## 快速开始

### 只读（无需认证）

```zig
const poly = @import("poly");

pub fn main() !void {
    var client = try poly.Client.init(allocator, .{});
    defer client.deinit();

    // 服务器状态
    const ok = try client.ok();
    
    // 获取市场列表
    const markets = try client.markets(.{});
    
    // 获取价格
    const price = try client.price(.{ .token_id = "..." });
    
    // 获取订单簿
    const book = try client.orderBook(.{ .token_id = "..." });
}
```

### 交易（需要认证）

```zig
const poly = @import("poly");

pub fn main() !void {
    // 初始化认证客户端
    var client = try poly.Client.init(allocator, .{
        .private_key = private_key,
        .chain_id = 137,  // Polygon 主网
        .signature_type = .eoa,  // 或 .magic, .proxy
        .funder = funder_address,  // 可选：代理钱包地址
    });
    defer client.deinit();

    // 下限价单
    try client.postOrder(.{
        .token_id = "0x...",
        .side = .buy,
        .price = try poly.Decimal.fromString("0.65"),
        .size = try poly.Decimal.fromString("100"),
    });

    // 查看订单
    const orders = try client.getOrders(.{});

    // 取消订单
    try client.cancelOrder(order_id);
    
    // 取消所有订单
    try client.cancelAll();
}
```

## 核心类型

### Decimal - 精确金融计算

```zig
const Decimal = poly.Decimal;

// 永远不要用 f64 处理金钱！
const price = try Decimal.fromString("0.65");
const size = try Decimal.fromString("100");
const total = price.mul(size);  // 精确的 65.00

// 比较
if (price.lessThan(Decimal.ONE)) {
    // price < 1.0
}
```

### Secret - 保护敏感数据

```zig
const Secret = poly.Secret;

const api_key = Secret([]const u8).init("sk_live_xxx");

// 安全：日志输出 "[REDACTED]"
std.log.info("key: {f}", .{api_key});

// 需要时显式获取
const key = api_key.reveal();
```

## 配置

复制 `.env.example` 为 `.env` 并配置：

```bash
# 必需
POLYGON_WALLET_PRIVATE_KEY=你的私钥

# 可选
CLOB_API_URL=https://clob.polymarket.com
POLYGON_CHAIN_ID=137
FUNDER_ADDRESS=代理钱包地址
SIGNATURE_TYPE=0  # 0=EOA, 1=Magic, 2=Proxy
```

## 签名类型

| 类型 | 值 | 说明 |
|------|-----|------|
| EOA | 0 | MetaMask、硬件钱包等直接控制私钥的钱包 |
| Magic | 1 | Email/Magic 钱包（委托签名） |
| Proxy | 2 | 浏览器钱包代理（使用代理合约） |

## 示例

查看 [examples/](./examples/) 目录获取更多示例：

```bash
# 运行基础类型示例
zig run examples/basic_types.zig
```

## 当前状态

🚧 **开发中** - 尚未准备好用于生产。

查看 [ROADMAP.md](./ROADMAP.md) 了解开发进度。

### 已实现

- [x] Decimal 类型（精确金融计算）
- [x] Secret 类型（保护敏感数据）
- [ ] Address 类型（EIP-55 校验和）
- [ ] UUID 类型
- [ ] HTTP 客户端
- [ ] 公共 API
- [ ] 认证
- [ ] 订单管理

## 文档

| 文档 | 描述 |
|------|------|
| [ROADMAP.md](./ROADMAP.md) | 版本规划 |
| [CHANGELOG.dev.md](./CHANGELOG.dev.md) | 开发日志 |
| [AGENTS.md](./AGENTS.md) | AI 编码规范 |
| [docs/](./docs/) | 详细文档 |
| [examples/](./examples/) | 示例代码 |

## 相关项目

- [clob-client](https://github.com/Polymarket/clob-client) - TypeScript 客户端
- [py-clob-client](https://github.com/Polymarket/py-clob-client) - Python 客户端
- [agents](https://github.com/Polymarket/agents) - AI 交易代理
- [Polymarket API 文档](https://docs.polymarket.com)

## 贡献

欢迎贡献！请查看 [CONTRIBUTING.md](./CONTRIBUTING.md)。

安全问题请参阅 [SECURITY.md](./SECURITY.md)。

## 服务条款

⚠️ [Polymarket 服务条款](https://polymarket.com/tos) 禁止美国居民和某些其他司法管辖区的人员在 Polymarket 上交易（包括通过 UI、API 和代理）。

## 许可证

[MIT License](./LICENSE)
