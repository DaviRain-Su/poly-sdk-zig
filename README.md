# poly-sdk-zig

[![Zig](https://img.shields.io/badge/Zig-0.15.2+-orange)](https://ziglang.org/)
[![CI](https://github.com/anthropics/poly-sdk-zig/actions/workflows/ci.yml/badge.svg)](https://github.com/anthropics/poly-sdk-zig/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Tests](https://img.shields.io/badge/tests-371%20passing-brightgreen)](https://github.com/anthropics/poly-sdk-zig)

Polymarket CLOB API 的原生 Zig 客户端。

## 功能特性

- **完整 API 覆盖**: 支持所有 Polymarket CLOB API 端点（~80+ 端点）
- **类型安全**: 编译时检查，无效 API 使用会产生编译错误
- **精确计算**: Decimal 类型用于金融计算（无浮点误差）
- **显式分配**: 无隐藏内存分配，清晰的所有权语义
- **零成本抽象**: 无运行时开销
- **最小依赖**: 仅使用 Zig 标准库

### 支持的功能

| 模块 | 功能 | 状态 |
|------|------|------|
| **公共 API (L0)** | 市场数据、订单簿、价格 | ✅ |
| **L1 认证** | API Key 创建/派生 | ✅ |
| **L2 认证** | HMAC 签名、订单管理 | ✅ |
| **订单管理** | 限价单、市价单、取消 | ✅ |
| **Builder** | 做市商 API Key 管理 | ✅ |
| **RFQ** | 大宗交易询价系统 | ✅ |
| **WebSocket** | 实时市场/用户数据 | ✅ |
| **奖励/分析** | 订单评分、交易事件 | ✅ |

## 安装

在 `build.zig.zon` 中添加依赖：

```zig
.dependencies = .{
    .poly_sdk_zig = .{
        .url = "https://github.com/anthropics/poly-sdk-zig/archive/main.tar.gz",
        .hash = "...",
    },
},
```

**要求**: Zig >= 0.15.2

## 快速开始

### 1. 公共 API（无需认证）

```zig
const poly = @import("poly_sdk_zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建客户端
    var client = poly.clob.ClobClient.init(allocator, .{});
    defer client.deinit();

    // 获取市场列表
    const markets = try client.getMarkets(.{});
    defer markets.deinit();

    // 获取订单簿
    const book = try client.getOrderBook("token_id_here");
    defer book.deinit();

    // 获取价格
    const price = try client.getPrice("token_id", .buy);
}
```

### 2. 获取 API 凭证（L1 认证）

```zig
// 从私钥创建钱包
const wallet = try poly.signer.Wallet.fromPrivateKeyHex("0x...");

// 设置钱包
client.setWallet(&wallet);

// 创建或派生 API Key
var creds = try client.createOrDeriveApiKey();
defer creds.deinit();

// 设置凭证用于后续请求
client.setApiCreds(&creds);
```

### 3. 订单管理（L2 认证）

```zig
// 创建限价单
const order = try client.createOrder(.{
    .token_id = "0x...",
    .price = try poly.types.Decimal.fromString("0.65"),
    .size = try poly.types.Decimal.fromString("100"),
    .side = .buy,
});

// 发布订单
const response = try client.postOrder(&order, .GTC);

// 查看订单
const orders = try client.getOpenOrders(.{});
defer orders.deinit();

// 取消订单
_ = try client.cancelOrder(order_id);

// 取消所有订单
_ = try client.cancelAll();
```

### 4. RFQ（大宗交易）

```zig
// 获取 RFQ 子客户端
var rfq = client.rfqClient();

// 创建询价请求
const request = try rfq.createRfqRequest(.{
    .asset_in = "USDC",
    .asset_out = token_id,
    .amount_in = "10000",
});

// 获取最佳报价
const best = try rfq.getRfqBestQuote(request.request_id);
```

## 核心类型

### Decimal - 精确金融计算

```zig
const Decimal = poly.types.Decimal;

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
const SecretString = poly.types.SecretString;

const api_key = SecretString.init("sk_live_xxx");

// 安全：日志输出 "[REDACTED]"
std.debug.print("key: {f}", .{api_key});

// 需要时显式获取
const key = api_key.reveal();
```

### ContractConfig - 合约配置

```zig
const contracts = poly.types.contracts;

// 获取主网配置
const config = contracts.getConfig(.polygon, false);

// 获取 Neg Risk 配置
const neg_risk_config = contracts.getConfig(.polygon, true);
```

## 配置

### 环境变量

```bash
# 必需（用于交易）
POLYGON_WALLET_PRIVATE_KEY=你的私钥

# 可选
CLOB_API_URL=https://clob.polymarket.com
POLYGON_CHAIN_ID=137
```

### 签名类型

| 类型 | 值 | 说明 |
|------|-----|------|
| EOA | 0 | MetaMask、硬件钱包等直接控制私钥的钱包 |
| Magic | 1 | Email/Magic 钱包（委托签名） |
| Proxy | 2 | 浏览器钱包代理（使用代理合约） |

## 示例

查看 [examples/](./examples/) 目录获取更多示例：

| 示例 | 描述 |
|------|------|
| [basic_types.zig](./examples/basic_types.zig) | Decimal 和 Secret 类型使用 |
| [public_api.zig](./examples/public_api.zig) | 公共 API 端点使用 |
| [authentication.zig](./examples/authentication.zig) | L1/L2 认证流程 |
| [order_management.zig](./examples/order_management.zig) | 订单创建和管理 |

## 测试

```bash
# 运行所有测试
zig test src/root.zig

# 当前: 365 tests passing
```

## 当前状态

**版本**: v0.6.0 (准备发布 v1.0)

✅ **生产就绪** - API 100% 覆盖，365 个测试通过。

### 模块状态

| 模块 | 文件 | 测试 | 状态 |
|------|------|------|------|
| 核心类型 | `src/types/` | ~60 | ✅ |
| HTTP 客户端 | `src/http/` | ~15 | ✅ |
| CLOB 客户端 | `src/clob/` | ~50 | ✅ |
| 加密 | `src/crypto/` | ~40 | ✅ |
| 签名 | `src/signer/` | ~30 | ✅ |
| 认证 | `src/auth/` | ~40 | ✅ |
| 订单 | `src/order/` | ~30 | ✅ |
| RFQ | `src/rfq/` | ~20 | ✅ |
| WebSocket | `src/ws/` | ~25 | ✅ |

查看 [ROADMAP.md](./ROADMAP.md) 了解详细开发进度。

## 文档

| 文档 | 描述 |
|------|------|
| [ROADMAP.md](./ROADMAP.md) | 版本规划和 API 覆盖 |
| [AGENTS.md](./AGENTS.md) | AI 编码规范 |
| [docs/](./docs/) | 详细 API 文档 |
| [examples/](./examples/) | 示例代码 |
| [stories/](./stories/) | 开发 Stories |

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
