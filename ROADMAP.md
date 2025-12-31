# ROADMAP - 唯一真相来源

这是项目规划的唯一真相来源。所有工作都从这里派生。

**参考实现**:
- [py-clob-client](https://github.com/Polymarket/py-clob-client) - Python 客户端
- [clob-client](https://github.com/Polymarket/clob-client) - TypeScript 客户端

**API 覆盖分析**: [docs/design/api-coverage.md](./docs/design/api-coverage.md)

## 当前状态

**版本**: v0.0.0 (预发布)  
**阶段**: v0.1 - 核心基础

---

## v0.1 - 核心基础

> **目标**: 基础类型、HTTP 客户端和只读公共 API (L0)。
> **交付物**: 无需认证即可查询市场数据。

```zig
var client = try poly.Client.init(allocator, .{});
const markets = try client.getMarkets(.{});
const book = try client.getOrderBook(token_id);
```

### Stories

| Story | 状态 | 依赖 |
|-------|------|------|
| [v0.1-types](./stories/v0.1-types.md) | 🔨 进行中 | - |
| [v0.1-error](./stories/v0.1-error.md) | ⏳ 待开始 | - |
| [v0.1-http](./stories/v0.1-http.md) | ⏳ 待开始 | v0.1-error |
| [v0.1-public-api](./stories/v0.1-public-api.md) | ⏳ 待开始 | v0.1-http, v0.1-types |

### 公共端点 (L0)

| 端点 | 方法 | 状态 |
|------|------|------|
| `GET /` | `getOk()` | ⏳ |
| `GET /time` | `getServerTime()` | ⏳ |
| `GET /markets` | `getMarkets()` | ⏳ |
| `GET /simplified-markets` | `getSimplifiedMarkets()` | ⏳ |
| `GET /markets/{id}` | `getMarket()` | ⏳ |
| `GET /book` | `getOrderBook()` | ⏳ |
| `POST /books` | `getOrderBooks()` | ⏳ |
| `GET /midpoint` | `getMidpoint()` | ⏳ |
| `POST /midpoints` | `getMidpoints()` | ⏳ |
| `GET /price` | `getPrice()` | ⏳ |
| `POST /prices` | `getPrices()` | ⏳ |
| `GET /spread` | `getSpread()` | ⏳ |
| `POST /spreads` | `getSpreads()` | ⏳ |
| `GET /tick-size` | `getTickSize()` | ⏳ |
| `GET /neg-risk` | `getNegRisk()` | ⏳ |
| `GET /fee-rate` | `getFeeRateBps()` | ⏳ |
| `GET /last-trade-price` | `getLastTradePrice()` | ⏳ |
| `POST /last-trades-prices` | `getLastTradesPrices()` | ⏳ |

### 进度

- [x] 项目设置 (build.zig, 结构)
- [x] Decimal 类型实现
- [x] Secret 类型实现
- [ ] Address, UUID 类型
- [ ] 错误类型
- [ ] HTTP 客户端
- [ ] 公共 API 端点

---

## v0.2 - 认证与订单

> **目标**: L1/L2 认证和订单管理。
> **交付物**: 创建、发布和管理订单。

```zig
// L1: 创建 API 凭证
const creds = try client.createOrDeriveApiKey();
client.setApiCreds(creds);

// L2: 下单
const order = try client.createOrder(.{
    .token_id = "...",
    .price = try Decimal.fromString("0.65"),
    .size = try Decimal.fromString("100"),
    .side = .buy,
});
try client.postOrder(order, .gtc);
```

### Stories (计划中)

| Story | 状态 | 描述 |
|-------|------|------|
| v0.2-crypto | ⏳ 待开始 | secp256k1, keccak256, HMAC-SHA256 |
| v0.2-signer | ⏳ 待开始 | 钱包签名器 |
| v0.2-l1-auth | ⏳ 待开始 | EIP-712 签名, L1 headers |
| v0.2-l2-auth | ⏳ 待开始 | HMAC 请求签名, L2 headers |
| v0.2-order-builder | ⏳ 待开始 | 订单构建器 |
| v0.2-orders | ⏳ 待开始 | 订单 CRUD 操作 |

### L1 认证端点

| 端点 | 方法 | 状态 |
|------|------|------|
| `POST /auth/api-key` | `createApiKey()` | ⏳ |
| `GET /auth/derive-api-key` | `deriveApiKey()` | ⏳ |
| - | `createOrDeriveApiKey()` | ⏳ |

### L2 认证端点

| 端点 | 方法 | 状态 |
|------|------|------|
| `GET /auth/api-keys` | `getApiKeys()` | ⏳ |
| `DELETE /auth/api-key` | `deleteApiKey()` | ⏳ |
| `POST /order` | `postOrder()` | ⏳ |
| `POST /orders` | `postOrders()` | ⏳ |
| `GET /orders` | `getOpenOrders()` | ⏳ |
| `GET /order/{id}` | `getOrder()` | ⏳ |
| `DELETE /order` | `cancelOrder()` | ⏳ |
| `DELETE /orders` | `cancelOrders()` | ⏳ |
| `DELETE /cancel-all` | `cancelAll()` | ⏳ |
| `DELETE /cancel-market-orders` | `cancelMarketOrders()` | ⏳ |
| `GET /trades` | `getTrades()` | ⏳ |
| `GET /balance-allowance` | `getBalanceAllowance()` | ⏳ |
| `GET /update-balance-allowance` | `updateBalanceAllowance()` | ⏳ |
| `GET /notifications` | `getNotifications()` | ⏳ |
| `DELETE /notifications` | `dropNotifications()` | ⏳ |

### 订单类型

| 类型 | 描述 | 状态 |
|------|------|------|
| 限价单 (GTC) | Good Till Cancelled | ⏳ |
| 限价单 (GTD) | Good Till Date | ⏳ |
| 市价单 (FOK) | Fill Or Kill | ⏳ |
| 市价单 (FAK) | Fill And Kill | ⏳ |

### 便捷方法

| 方法 | 描述 | 状态 |
|------|------|------|
| `createOrder()` | 创建限价单 | ⏳ |
| `createMarketOrder()` | 创建市价单 | ⏳ |
| `createAndPostOrder()` | 创建并发布限价单 | ⏳ |
| `createAndPostMarketOrder()` | 创建并发布市价单 | ⏳ |
| `calculateMarketPrice()` | 计算市价 | ⏳ |

---

## v0.3 - Builder 与扩展

> **目标**: Builder 程序、RFQ 和高级功能。
> **交付物**: 做市商支持。

```zig
var client = try poly.Client.init(allocator, .{
    .builder_config = builder_config,
});
const trades = try client.getBuilderTrades(.{});
```

### Builder 端点

| 端点 | 方法 | 状态 |
|------|------|------|
| `GET /builder-trades` | `getBuilderTrades()` | ⏳ |
| `POST /auth/builder-api-key` | `createBuilderApiKey()` | ⏳ |
| `GET /auth/builder-api-keys` | `getBuilderApiKeys()` | ⏳ |
| `DELETE /auth/builder-api-key` | `revokeBuilderApiKey()` | ⏳ |

### Readonly API Key

| 端点 | 方法 | 状态 |
|------|------|------|
| `POST /auth/readonly-api-key` | `createReadonlyApiKey()` | ⏳ |
| `GET /auth/readonly-api-keys` | `getReadonlyApiKeys()` | ⏳ |
| `DELETE /auth/readonly-api-key` | `deleteReadonlyApiKey()` | ⏳ |
| `GET /readonly-api-key/validate` | `validateReadonlyApiKey()` | ⏳ |

### 其他功能

| 功能 | 描述 | 状态 |
|------|------|------|
| RFQ 客户端 | Request for Quote | ⏳ |
| Heartbeat | 保持订单有效性 | ⏳ |
| 订单评分 | 订单质量评估 | ⏳ |

---

## v0.4 - WebSocket

> **目标**: 实时数据订阅。
> **交付物**: 实时价格和订单更新。

```zig
var ws = try poly.WebSocket.connect(allocator, .{});
try ws.subscribeOrderBook(token_id, onUpdate);
```

---

## v0.5 - 奖励与分析

> **目标**: 流动性奖励和市场分析。

### 奖励端点

| 端点 | 方法 | 状态 |
|------|------|------|
| 用户收益 | `getEarningsForUserForDay()` | ⏳ |
| 总收益 | `getTotalEarningsForUserForDay()` | ⏳ |
| 奖励百分比 | `getRewardPercentages()` | ⏳ |
| 当前奖励 | `getCurrentRewards()` | ⏳ |
| 市场奖励 | `getRawRewardsForMarket()` | ⏳ |

### 市场分析

| 端点 | 方法 | 状态 |
|------|------|------|
| 价格历史 | `getPricesHistory()` | ⏳ |
| 市场交易事件 | `getMarketTradesEvents()` | ⏳ |
| 采样市场 | `getSamplingMarkets()` | ⏳ |

---

## v1.0 - 稳定版发布

> **目标**: 生产就绪，完整测试。

- [ ] 100% API 覆盖
- [ ] 完整文档
- [ ] 性能基准测试
- [ ] 安全审计
- [ ] 示例应用

---

## 状态图例

| 图标 | 含义 |
|------|------|
| ⏳ | 待开始 |
| 🔨 | 进行中 |
| ✅ | 已完成 |
| ❌ | 被阻塞 |

---

## 变更日志

| 日期 | 变更 |
|------|------|
| 2024-12-31 | 初始 ROADMAP，创建 v0.1 stories |
| 2024-12-31 | Secret 类型实现完成 |
| 2024-12-31 | 根据官方客户端分析扩展 ROADMAP，覆盖完整 API |
