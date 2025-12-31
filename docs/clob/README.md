# CLOB 客户端模块

> Polymarket Central Limit Order Book (CLOB) API 客户端。

## 概述

`clob` 模块提供了 Polymarket CLOB API 的完整客户端实现，支持：

- **公共端点 (L0)** - 无需认证的市场数据查询
- **认证端点 (L2)** - 需要 API Key 的订单管理

## 模块结构

```
src/clob/
├── mod.zig           # 模块导出
├── client.zig        # CLOB 客户端
└── types/
    ├── mod.zig       # 类型导出
    ├── enums.zig     # 枚举类型
    ├── market.zig    # 市场类型
    ├── book.zig      # 订单簿类型
    ├── order.zig     # 订单类型
    ├── trade.zig     # 交易类型
    └── account.zig   # 账户类型
```

## 子模块

| 文件 | 文档 | 描述 |
|------|------|------|
| client.zig | [orders.md](./orders.md) | CLOB 客户端实现 |
| types/*.zig | [orders.md](./orders.md) | API 响应类型 |

## 快速开始

### 公共 API (无需认证)

```zig
const clob = @import("poly-sdk-zig").clob;

var client = clob.ClobClient.init(allocator, .{});
defer client.deinit();

// 检查服务器状态
const ok = try client.getOk();

// 获取市场列表
const markets = try client.getMarkets(.{});
defer markets.deinit();

// 获取订单簿
const book = try client.getOrderBook("token_id");
defer book.deinit();

// 获取价格
const price = try client.getPrice("token_id", .BUY);
```

### 认证 API (需要 API Key)

```zig
const clob = @import("poly-sdk-zig").clob;

// 初始化认证客户端
var client = clob.ClobClient.initWithAuth(
    allocator,
    .{},
    &wallet,
    &api_creds,
);
defer client.deinit();

// 创建订单
const order = try client.createOrder(.{
    .token_id = "123456789",
    .price = try Decimal.fromString("0.65"),
    .size = try Decimal.fromString("100"),
    .side = .BUY,
}, .{ .tick_size = .@"0.01" });

// 发布订单
const result = try client.postOrder(&order, .GTC);

// 查询订单
const orders = try client.getOpenOrders(.{});
defer orders.deinit();

// 取消订单
try client.cancelOrder("order_id");
```

## 端点覆盖

### 公共端点 (L0)

| 端点 | 方法 | 状态 |
|------|------|------|
| `GET /` | `getOk()` | ✅ |
| `GET /time` | `getServerTime()` | ✅ |
| `GET /markets` | `getMarkets()` | ✅ |
| `GET /simplified-markets` | `getSimplifiedMarkets()` | ✅ |
| `GET /markets/{id}` | `getMarket()` | ✅ |
| `GET /book` | `getOrderBook()` | ✅ |
| `GET /price` | `getPrice()` | ✅ |
| `GET /midpoint` | `getMidpoint()` | ✅ |
| `GET /spread` | `getSpread()` | ✅ |
| `GET /tick-size` | `getTickSize()` | ✅ |
| `GET /neg-risk` | `getNegRisk()` | ✅ |
| `GET /last-trade-price` | `getLastTradePrice()` | ✅ |

### 认证端点 (L2)

| 端点 | 方法 | 状态 |
|------|------|------|
| `POST /order` | `postOrder()` | ✅ |
| `GET /data/orders` | `getOpenOrders()` | ✅ |
| `GET /data/order/{id}` | `getOrder()` | ✅ |
| `DELETE /order` | `cancelOrder()` | ✅ |
| `DELETE /orders` | `cancelOrders()` | ✅ |
| `DELETE /cancel-all` | `cancelAll()` | ✅ |
| `DELETE /cancel-market-orders` | `cancelMarketOrders()` | ✅ |
| `GET /data/trades` | `getTrades()` | ✅ |
| `GET /balance-allowance` | `getBalanceAllowance()` | ✅ |
| `GET /notifications` | `getNotifications()` | ✅ |
| `DELETE /notifications` | `dropNotifications()` | ✅ |

## 便捷方法

| 方法 | 描述 |
|------|------|
| `createOrder()` | 使用 OrderBuilder 创建订单 |
| `createAndPostOrder()` | 创建并发布订单 |

## 配置选项

```zig
const Config = struct {
    /// API 基础 URL
    base_url: []const u8 = "https://clob.polymarket.com",
    /// 请求超时（纳秒）
    timeout_ns: u64 = 30 * std.time.ns_per_s,
    /// 链 ID (137 = Polygon mainnet)
    chain_id: u64 = 137,
};
```

## 错误处理

所有方法都返回错误联合类型，需要处理以下错误：

- `Unauthorized` - 未认证或认证失败
- `BadRequest` - 请求参数错误
- `NotFound` - 资源不存在
- `RateLimited` - 请求过于频繁
- `InvalidJson` - 响应解析失败

## 测试

```bash
# 测试整个 clob 模块
zig test src/clob/mod.zig

# 测试客户端
zig test src/clob/client.zig
```
