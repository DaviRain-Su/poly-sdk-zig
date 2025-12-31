# ROADMAP - 唯一真相来源

这是项目规划的唯一真相来源。所有工作都从这里派生。

**参考实现**:
- [py-clob-client](https://github.com/Polymarket/py-clob-client) - Python 客户端 (v0.34.1)
- [clob-client](https://github.com/Polymarket/clob-client) - TypeScript 客户端 (v5.1.3)
- [agents](https://github.com/Polymarket/agents) - AI 交易代理框架

**设计文档**:
- [API 覆盖分析](./docs/design/api-coverage.md) - 完整 API 对比
- [合约配置](./docs/design/contracts.md) - Polygon 合约地址
- [类型定义](./docs/design/types.md) - 详细类型定义

## 当前状态

**版本**: v0.3.0 (Builder、RFQ 与扩展)  
**阶段**: v0.3 - 🔨 进行中

---

## v0.1 - 核心基础

> **目标**: 基础类型、HTTP 客户端和只读公共 API (L0)。
> **交付物**: 无需认证即可查询市场数据。
> **端点数量**: ~20 个

```zig
var client = try poly.Client.init(allocator, .{});
const markets = try client.getMarkets(.{});
const book = try client.getOrderBook(token_id);
```

### Stories

| Story | 状态 | 依赖 |
|-------|------|------|
| [v0.1-types](./stories/v0.1-types.md) | ✅ 已完成 | - |
| [v0.1-error](./stories/v0.1-error.md) | ✅ 已完成 | - |
| [v0.1-http](./stories/v0.1-http.md) | ✅ 已完成 | v0.1-error |
| [v0.1-public-api](./stories/v0.1-public-api.md) | ✅ 已完成 | v0.1-http, v0.1-types |

### 核心类型

| 类型 | 文件 | 状态 | 测试 |
|------|------|------|------|
| Decimal | `src/types/decimal.zig` | ✅ 完成 | 10 tests |
| Secret | `src/types/secret.zig` | ✅ 完成 | 8 tests |
| Address | `src/types/address.zig` | ✅ 完成 | 15 tests |
| UUID | `src/types/uuid.zig` | ✅ 完成 | 15 tests |
| mod.zig | `src/types/mod.zig` | ✅ 完成 | 6 tests |
| ContractConfig | `src/types/contracts.zig` | ⏳ 待开始 | - |

### 公共端点 (L0 - 无需认证)

#### 服务器状态

| 端点 | 方法 | 状态 |
|------|------|------|
| `GET /` | `getOk()` | ✅ |
| `GET /time` | `getServerTime()` | ✅ |

#### 市场数据

| 端点 | 方法 | 状态 |
|------|------|------|
| `GET /markets` | `getMarkets()` | ✅ |
| `GET /simplified-markets` | `getSimplifiedMarkets()` | ✅ |
| `GET /sampling-markets` | `getSamplingMarkets()` | ⏳ |
| `GET /sampling-simplified-markets` | `getSamplingSimplifiedMarkets()` | ⏳ |
| `GET /markets/{condition_id}` | `getMarket()` | ✅ |

#### 价格和订单簿

| 端点 | 方法 | 状态 |
|------|------|------|
| `GET /book` | `getOrderBook()` | ✅ |
| `POST /books` | `getOrderBooks()` | ⏳ |
| `GET /midpoint` | `getMidpoint()` | ✅ |
| `POST /midpoints` | `getMidpoints()` | ⏳ |
| `GET /price` | `getPrice()` | ✅ |
| `POST /prices` | `getPrices()` | ⏳ |
| `GET /spread` | `getSpread()` | ✅ |
| `POST /spreads` | `getSpreads()` | ⏳ |
| `GET /tick-size` | `getTickSize()` | ✅ |
| `GET /neg-risk` | `getNegRisk()` | ✅ |
| `GET /fee-rate` | `getFeeRateBps()` | ⏳ |
| `GET /last-trade-price` | `getLastTradePrice()` | ✅ |
| `POST /last-trades-prices` | `getLastTradesPrices()` | ⏳ |

### 进度

- [x] 项目设置 (build.zig, 结构)
- [x] Decimal 类型实现
- [x] Secret 类型实现
- [x] 文档体系建立
- [x] API 覆盖分析完成
- [x] Address 类型实现（EIP-55 校验和）
- [x] UUID 类型实现（v4 随机生成）
- [x] types/mod.zig 模块导出
- [x] 错误类型实现（40+ 错误，14 tests）
- [x] HTTP 客户端实现（14 tests）
- [x] CLOB 客户端实现（12 个端点，18 tests）
- [x] **v0.1 完成！** 102 个测试通过

---

## v0.2 - 认证与订单

> **目标**: L1/L2 认证和订单管理。
> **交付物**: 创建、发布和管理订单。
> **端点数量**: ~25 个

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

### Stories

| Story | 状态 | 描述 | 依赖 |
|-------|------|------|------|
| [v0.2-crypto](./stories/v0.2-crypto.md) | ✅ 已完成 | Keccak256, secp256k1, HMAC-SHA256 | v0.1-types |
| [v0.2-signer](./stories/v0.2-signer.md) | ✅ 已完成 | Wallet, EIP-712 签名 | v0.2-crypto |
| [v0.2-l1-auth](./stories/v0.2-l1-auth.md) | ✅ 已完成 | L1 认证, API Key 创建/派生 | v0.2-signer |
| [v0.2-l2-auth](./stories/v0.2-l2-auth.md) | ✅ 已完成 | L2 认证, HMAC 请求签名 | v0.2-l1-auth |
| [v0.2-order-builder](./stories/v0.2-order-builder.md) | ✅ 已完成 | 订单构建器, 限价单/市价单 | v0.2-signer |
| [v0.2-orders](./stories/v0.2-orders.md) | ✅ 已完成 | 订单 CRUD, 交易历史, 余额查询 | v0.2-order-builder, v0.2-l2-auth |

### L1 认证端点

| 端点 | 方法 | 状态 |
|------|------|------|
| `POST /auth/api-key` | `createApiKey()` | ⏳ |
| `GET /auth/derive-api-key` | `deriveApiKey()` | ⏳ |
| - | `createOrDeriveApiKey()` | ⏳ |

### L2 认证端点

#### API Key 管理

| 端点 | 方法 | 状态 |
|------|------|------|
| `GET /auth/api-keys` | `getApiKeys()` | ⏳ |
| `DELETE /auth/api-key` | `deleteApiKey()` | ⏳ |
| `GET /auth/ban-status/closed-only` | `getClosedOnlyMode()` | ⏳ |

#### 订单管理

| 端点 | 方法 | 状态 |
|------|------|------|
| `POST /order` | `postOrder()` | ✅ |
| `POST /orders` | `postOrders()` | ✅ |
| `GET /data/orders` | `getOpenOrders()` | ✅ |
| `GET /data/order/{id}` | `getOrder()` | ✅ |
| `DELETE /order` | `cancelOrder()` | ✅ |
| `DELETE /orders` | `cancelOrders()` | ✅ |
| `DELETE /cancel-all` | `cancelAll()` | ✅ |
| `DELETE /cancel-market-orders` | `cancelMarketOrders()` | ✅ |

#### 交易和账户

| 端点 | 方法 | 状态 |
|------|------|------|
| `GET /data/trades` | `getTrades()` | ✅ |
| `GET /balance-allowance` | `getBalanceAllowance()` | ✅ |
| `GET /balance-allowance/update` | `updateBalanceAllowance()` | ⏳ |
| `GET /notifications` | `getNotifications()` | ✅ |
| `DELETE /notifications` | `dropNotifications()` | ✅ |

### 订单类型

| 类型 | 描述 | 状态 |
|------|------|------|
| 限价单 (GTC) | Good Till Cancelled | ✅ |
| 限价单 (GTD) | Good Till Date | ✅ |
| 市价单 (FOK) | Fill Or Kill | ✅ |
| 市价单 (FAK) | Fill And Kill | ✅ |

### 便捷方法

| 方法 | 描述 | 状态 |
|------|------|------|
| `createOrder()` | 创建限价单 | ✅ |
| `createMarketOrder()` | 创建市价单 | ✅ |
| `createAndPostOrder()` | 创建并发布限价单 | ✅ |
| `createAndPostMarketOrder()` | 创建并发布市价单 | ✅ |
| `calculateMarketPrice()` | 计算市价 | ✅ |
| `postOrders()` | 批量发布订单 | ✅ |

### 签名类型支持

| 类型 | 值 | 描述 | 状态 |
|------|---|------|------|
| EOA | 0 | MetaMask, 硬件钱包 | ✅ |
| POLY_PROXY | 1 | Email/Magic 钱包 | ⏳ |
| POLY_GNOSIS_SAFE | 2 | 浏览器钱包代理 | ⏳ |

---

## v0.3 - Builder、RFQ 与扩展

> **目标**: Builder 程序、RFQ 询价系统和高级功能。
> **交付物**: 做市商支持、大宗交易询价。
> **端点数量**: ~25 个

```zig
// Builder 模式
var client = try poly.Client.init(allocator, .{
    .builder_config = builder_config,
});
const trades = try client.getBuilderTrades(.{});

// RFQ 模式
const request = try client.rfq.createRfqRequest(order, .{});
const quotes = try client.rfq.getRfqQuotes(.{ .request_id = request.request_id });
```

### Builder 端点

| 端点 | 方法 | 状态 |
|------|------|------|
| `POST /auth/builder-api-key` | `createBuilderApiKey()` | ⏳ |
| `GET /auth/builder-api-key` | `getBuilderApiKeys()` | ⏳ |
| `DELETE /auth/builder-api-key` | `revokeBuilderApiKey()` | ⏳ |
| `GET /builder/trades` | `getBuilderTrades()` | ⏳ |

### Readonly API Key

| 端点 | 方法 | 状态 |
|------|------|------|
| `POST /auth/readonly-api-key` | `createReadonlyApiKey()` | ⏳ |
| `GET /auth/readonly-api-keys` | `getReadonlyApiKeys()` | ⏳ |
| `DELETE /auth/readonly-api-key` | `deleteReadonlyApiKey()` | ⏳ |
| `GET /auth/validate-readonly-api-key` | `validateReadonlyApiKey()` | ⏳ |

### RFQ (Request for Quote) 端点

| 端点 | 方法 | 状态 |
|------|------|------|
| `POST /rfq/request` | `rfq.createRfqRequest()` | ⏳ |
| `DELETE /rfq/request` | `rfq.cancelRfqRequest()` | ⏳ |
| `GET /rfq/data/requests` | `rfq.getRfqRequests()` | ⏳ |
| `POST /rfq/quote` | `rfq.createRfqQuote()` | ⏳ |
| `DELETE /rfq/quote` | `rfq.cancelRfqQuote()` | ⏳ |
| `GET /rfq/data/quotes` | `rfq.getRfqQuotes()` | ⏳ |
| `GET /rfq/data/best-quote` | `rfq.getRfqBestQuote()` | ⏳ |
| `POST /rfq/request/accept` | `rfq.acceptRfqQuote()` | ⏳ |
| `POST /rfq/quote/approve` | `rfq.approveRfqOrder()` | ⏳ |
| `GET /rfq/config` | `rfq.rfqConfig()` | ⏳ |

### Heartbeat

| 端点 | 方法 | 状态 | 说明 |
|------|------|------|------|
| `POST /v1/heartbeats` | `postHeartbeat()` | ✅ | 10秒内不发送会取消所有订单 |

---

## v0.4 - WebSocket

> **目标**: 实时数据订阅。
> **交付物**: 实时价格和订单更新。

```zig
var ws = try poly.WebSocket.connect(allocator, .{});
try ws.subscribeOrderBook(token_id, onUpdate);
try ws.subscribeTrades(token_id, onTrade);
```

### WebSocket 订阅

| 频道 | 描述 | 状态 |
|------|------|------|
| 订单簿 | 实时订单簿更新 | ⏳ |
| 交易 | 实时成交 | ⏳ |
| 用户订单 | 用户订单状态 | ⏳ |
| 用户交易 | 用户成交 | ⏳ |

---

## v0.5 - 奖励与分析

> **目标**: 流动性奖励和市场分析。
> **端点数量**: ~10 个

### 奖励端点

| 端点 | 方法 | 状态 |
|------|------|------|
| `GET /rewards/user` | `getEarningsForUserForDay()` | ⏳ |
| `GET /rewards/user/total` | `getTotalEarningsForUserForDay()` | ⏳ |
| `GET /rewards/user/percentages` | `getRewardPercentages()` | ⏳ |
| `GET /rewards/markets/current` | `getCurrentRewards()` | ⏳ |
| `GET /rewards/markets/{conditionId}` | `getRawRewardsForMarket()` | ⏳ |
| `GET /rewards/user/markets` | `getUserEarningsAndMarketsConfig()` | ⏳ |

### 市场分析

| 端点 | 方法 | 状态 |
|------|------|------|
| `GET /prices-history` | `getPricesHistory()` | ⏳ |
| `GET /live-activity/events/{condition_id}` | `getMarketTradesEvents()` | ⏳ |

### 订单评分

| 端点 | 方法 | 状态 |
|------|------|------|
| `GET /order-scoring` | `isOrderScoring()` | ⏳ |
| `POST /orders-scoring` | `areOrdersScoring()` | ⏳ |

---

## v1.0 - 稳定版发布

> **目标**: 生产就绪，完整测试。

### 发布检查清单

- [ ] 100% API 覆盖（约 70 个端点）
- [ ] 完整文档（中英双语）
- [ ] 性能基准测试
- [ ] 安全审计
- [ ] 示例应用
- [ ] CI/CD 配置
- [ ] 发布到 Zig 包管理器

### API 覆盖统计

| 版本 | 功能 | 端点数量 | 状态 |
|------|------|----------|------|
| v0.1 | 公共 API (L0) | ~20 | ✅ 完成 |
| v0.2 | 认证与订单 (L1/L2) | ~25 | ✅ 完成 |
| v0.3 | Builder + RFQ | ~25 | ⏳ 待开始 |
| v0.4 | WebSocket | ~4 | ⏳ 待开始 |
| v0.5 | 奖励 + 分析 | ~10 | ⏳ 待开始 |
| **总计** | | **~84** | |

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
| 2024-12-31 | 添加 RFQ 端点、合约配置、类型定义、Header 类型、签名类型说明 |
| 2024-12-31 | 完善 v0.3 RFQ 和 Builder 端点详情 |
| 2024-12-31 | Address 和 UUID 类型实现完成，v0.1-types Story 完成 |
| 2024-12-31 | v0.2-signer 完成：Wallet 类型、EIP-712 订单签名、Polymarket 合约地址 |
| 2024-12-31 | v0.2-l1-auth 完成：L1Auth、L1PolyHeader、ApiCreds、ClobAuth EIP-712 |
| 2024-12-31 | v0.2-l2-auth 完成：L2Auth、HMAC-SHA256 签名、Base64 编码 |
| 2024-12-31 | v0.2-order-builder 完成：OrderBuilder、限价单创建、金额计算、EIP-712 签名 |
| 2024-12-31 | v0.2-orders 完成：订单发布/查询/取消、交易历史、余额查询、L2 认证集成 |
| 2024-12-31 | v0.3 开始：市价单(FOK/FAK)、批量订单(postOrders)、Heartbeat 端点 |
