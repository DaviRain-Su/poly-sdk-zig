# API 功能覆盖分析

本文档对比官方 Python/TypeScript 客户端的功能，确保我们的 Zig 实现覆盖所有 API。

**参考仓库**:
- [py-clob-client](https://github.com/Polymarket/py-clob-client)
- [clob-client](https://github.com/Polymarket/clob-client)

---

## 认证级别

官方客户端支持三个认证级别：

| 级别 | 描述 | 需要 |
|------|------|------|
| L0 | 只读公共 API | 仅 host URL |
| L1 | L1 认证端点 | host + chain_id + private_key |
| L2 | 完整访问 | host + chain_id + private_key + API credentials |

另外还有 **Builder 认证** 用于做市商程序。

---

## 公共端点 (L0 - 无需认证)

### 服务器状态

| 端点 | 方法 | Python | TypeScript | Zig ROADMAP |
|------|------|--------|------------|-------------|
| `/` | GET | `get_ok()` | `getOk()` | v0.1 ✅ |
| `/time` | GET | `get_server_time()` | `getServerTime()` | v0.1 ✅ |

### 市场数据

| 端点 | 方法 | Python | TypeScript | Zig ROADMAP |
|------|------|--------|------------|-------------|
| `/markets` | GET | `get_markets()` | `getMarkets()` | v0.1 ✅ |
| `/simplified-markets` | GET | `get_simplified_markets()` | `getSimplifiedMarkets()` | v0.1 ⚠️ 缺失 |
| `/sampling-markets` | GET | `get_sampling_markets()` | `getSamplingMarkets()` | ❌ 缺失 |
| `/sampling-simplified-markets` | GET | `get_sampling_simplified_markets()` | `getSamplingSimplifiedMarkets()` | ❌ 缺失 |
| `/markets/{id}` | GET | `get_market()` | `getMarket()` | v0.1 ✅ |
| `/markets/{id}/trades-events` | GET | `get_market_trades_events()` | `getMarketTradesEvents()` | ❌ 缺失 |

### 价格和订单簿

| 端点 | 方法 | Python | TypeScript | Zig ROADMAP |
|------|------|--------|------------|-------------|
| `/book` | GET | `get_order_book()` | `getOrderBook()` | v0.1 ✅ |
| `/books` | POST | `get_order_books()` | `getOrderBooks()` | ❌ 缺失 |
| `/midpoint` | GET | `get_midpoint()` | `getMidpoint()` | v0.1 ✅ |
| `/midpoints` | POST | `get_midpoints()` | `getMidpoints()` | ❌ 缺失 |
| `/price` | GET | `get_price()` | `getPrice()` | v0.1 ✅ |
| `/prices` | POST | `get_prices()` | `getPrices()` | ❌ 缺失 |
| `/spread` | GET | `get_spread()` | `getSpread()` | v0.1 ✅ |
| `/spreads` | POST | `get_spreads()` | `getSpreads()` | ❌ 缺失 |
| `/last-trade-price` | GET | `get_last_trade_price()` | `getLastTradePrice()` | ❌ 缺失 |
| `/last-trades-prices` | POST | `get_last_trades_prices()` | `getLastTradesPrices()` | ❌ 缺失 |
| `/tick-size` | GET | `get_tick_size()` | `getTickSize()` | v0.1 ✅ |
| `/neg-risk` | GET | `get_neg_risk()` | `getNegRisk()` | ❌ 缺失 |
| `/fee-rate` | GET | `get_fee_rate_bps()` | `getFeeRateBps()` | ❌ 缺失 |
| `/prices-history` | GET | - | `getPricesHistory()` | ❌ 缺失 |

### Readonly API Key

| 端点 | 方法 | Python | TypeScript | Zig ROADMAP |
|------|------|--------|------------|-------------|
| `/readonly-api-key/validate` | GET | `validate_readonly_api_key()` | `validateReadonlyApiKey()` | ❌ 缺失 |

---

## L1 认证端点

### API Key 管理

| 端点 | 方法 | Python | TypeScript | Zig ROADMAP |
|------|------|--------|------------|-------------|
| `/auth/api-key` | POST | `create_api_key()` | `createApiKey()` | v0.2 ✅ |
| `/auth/derive-api-key` | GET | `derive_api_key()` | `deriveApiKey()` | v0.2 ✅ |
| - | - | `create_or_derive_api_creds()` | `createOrDeriveApiKey()` | v0.2 ✅ |

### 订单创建（签名）

| 功能 | Python | TypeScript | Zig ROADMAP |
|------|--------|------------|-------------|
| 创建限价单 | `create_order()` | `createOrder()` | v0.2 ✅ |
| 创建市价单 | `create_market_order()` | `createMarketOrder()` | v0.2 ⚠️ 缺失 |
| 计算市价 | `calculate_market_price()` | `calculateMarketPrice()` | ❌ 缺失 |

---

## L2 认证端点

### API Key 管理

| 端点 | 方法 | Python | TypeScript | Zig ROADMAP |
|------|------|--------|------------|-------------|
| `/auth/api-keys` | GET | `get_api_keys()` | `getApiKeys()` | ❌ 缺失 |
| `/auth/api-key` | DELETE | `delete_api_key()` | `deleteApiKey()` | ❌ 缺失 |
| `/closed-only` | GET | `get_closed_only_mode()` | `getClosedOnlyMode()` | ❌ 缺失 |

### Readonly API Key

| 端点 | 方法 | Python | TypeScript | Zig ROADMAP |
|------|------|--------|------------|-------------|
| `/auth/readonly-api-key` | POST | `create_readonly_api_key()` | `createReadonlyApiKey()` | ❌ 缺失 |
| `/auth/readonly-api-keys` | GET | `get_readonly_api_keys()` | `getReadonlyApiKeys()` | ❌ 缺失 |
| `/auth/readonly-api-key` | DELETE | `delete_readonly_api_key()` | `deleteReadonlyApiKey()` | ❌ 缺失 |

### 订单管理

| 端点 | 方法 | Python | TypeScript | Zig ROADMAP |
|------|------|--------|------------|-------------|
| `/order` | POST | `post_order()` | `postOrder()` | v0.2 ✅ |
| `/orders` | POST | `post_orders()` | `postOrders()` | ❌ 缺失 |
| `/orders` | GET | `get_orders()` | `getOpenOrders()` | v0.2 ✅ |
| `/order/{id}` | GET | `get_order()` | `getOrder()` | ❌ 缺失 |
| `/order` | DELETE | `cancel()` | `cancelOrder()` | v0.2 ✅ |
| `/orders` | DELETE | `cancel_orders()` | `cancelOrders()` | ❌ 缺失 |
| `/cancel-all` | DELETE | `cancel_all()` | `cancelAll()` | v0.2 ✅ |
| `/cancel-market-orders` | DELETE | `cancel_market_orders()` | `cancelMarketOrders()` | ❌ 缺失 |

### 交易和便捷方法

| 功能 | Python | TypeScript | Zig ROADMAP |
|------|--------|------------|-------------|
| 创建并发布订单 | `create_and_post_order()` | `createAndPostOrder()` | v0.2 ⚠️ 缺失 |
| 创建并发布市价单 | - | `createAndPostMarketOrder()` | ❌ 缺失 |
| 获取交易历史 | `get_trades()` | `getTrades()` | ❌ 缺失 |

### 账户和余额

| 端点 | 方法 | Python | TypeScript | Zig ROADMAP |
|------|------|--------|------------|-------------|
| `/balance-allowance` | GET | `get_balance_allowance()` | `getBalanceAllowance()` | ❌ 缺失 |
| `/update-balance-allowance` | GET | `update_balance_allowance()` | `updateBalanceAllowance()` | ❌ 缺失 |

### 通知

| 端点 | 方法 | Python | TypeScript | Zig ROADMAP |
|------|------|--------|------------|-------------|
| `/notifications` | GET | `get_notifications()` | `getNotifications()` | ❌ 缺失 |
| `/notifications` | DELETE | `drop_notifications()` | `dropNotifications()` | ❌ 缺失 |

### 订单评分

| 端点 | 方法 | Python | TypeScript | Zig ROADMAP |
|------|------|--------|------------|-------------|
| `/order-scoring` | GET | `is_order_scoring()` | `isOrderScoring()` | ❌ 缺失 |
| `/orders-scoring` | POST | `are_orders_scoring()` | `areOrdersScoring()` | ❌ 缺失 |

### 奖励系统

| 端点 | Python | TypeScript | Zig ROADMAP |
|------|--------|------------|-------------|
| 用户收益 | - | `getEarningsForUserForDay()` | ❌ 缺失 |
| 总收益 | - | `getTotalEarningsForUserForDay()` | ❌ 缺失 |
| 奖励百分比 | - | `getRewardPercentages()` | ❌ 缺失 |
| 当前奖励 | - | `getCurrentRewards()` | ❌ 缺失 |
| 市场奖励 | - | `getRawRewardsForMarket()` | ❌ 缺失 |

### Heartbeat

| 端点 | 方法 | Python | TypeScript | Zig ROADMAP |
|------|------|--------|------------|-------------|
| `/heartbeat` | POST | `post_heartbeat()` | - | ❌ 缺失 |

---

## Builder 认证

| 功能 | Python | TypeScript | Zig ROADMAP |
|------|--------|------------|-------------|
| Builder 配置 | `builder_config` | `builderConfig` | v0.3 ⚠️ |
| 获取 Builder 交易 | `get_builder_trades()` | `getBuilderTrades()` | v0.3 ⚠️ |
| 创建 Builder API Key | - | `createBuilderApiKey()` | ❌ 缺失 |
| 获取 Builder API Keys | - | `getBuilderApiKeys()` | ❌ 缺失 |
| 撤销 Builder API Key | - | `revokeBuilderApiKey()` | ❌ 缺失 |

---

## RFQ (Request for Quote)

两个官方客户端都有 `RfqClient`，我们的 ROADMAP 没有提及。

---

## 核心类型

| 类型 | Python | TypeScript | Zig ROADMAP |
|------|--------|------------|-------------|
| Decimal/价格 | 内置 float | 内置 number | v0.1 ✅ Decimal |
| Address | 字符串 | 字符串 | v0.1 ⚠️ |
| UUID | 字符串 | 字符串 | v0.1 ⚠️ |
| Secret | 无 | 无 | v0.1 ✅ Secret |
| OrderBuilder | `OrderBuilder` | `OrderBuilder` | v0.2 ✅ |
| Signer | `Signer` | - | v0.2 ✅ |

---

## 签名和加密

| 功能 | 描述 | Zig ROADMAP |
|------|------|-------------|
| secp256k1 | 椭圆曲线签名 | v0.2 ✅ |
| keccak256 | 哈希函数 | v0.2 ✅ |
| HMAC-SHA256 | L2 认证签名 | v0.2 ✅ |
| EIP-712 | 结构化数据签名 | v0.2 ✅ |

---

## 缺失功能总结

### 高优先级（核心交易功能）

1. **市价单** - `create_market_order()`, `createAndPostMarketOrder()`
2. **批量订单** - `post_orders()`, `cancel_orders()`
3. **交易历史** - `get_trades()`
4. **账户余额** - `get_balance_allowance()`
5. **批量价格查询** - `get_order_books()`, `get_midpoints()`, `get_prices()`

### 中优先级（完整 API 覆盖）

6. **简化市场** - `get_simplified_markets()`
7. **最后成交价** - `get_last_trade_price()`
8. **费率查询** - `get_fee_rate_bps()`, `get_neg_risk()`
9. **通知系统** - `get_notifications()`, `drop_notifications()`
10. **Heartbeat** - 保持订单有效性

### 低优先级（高级功能）

11. **RFQ 客户端** - Request for Quote
12. **Builder 程序** - 做市商专用
13. **奖励系统** - 流动性奖励
14. **订单评分** - 订单质量评估

---

## 建议的 ROADMAP 更新

### v0.1 补充

- 添加简化市场端点
- 添加批量查询端点
- 添加最后成交价
- 添加费率和风险查询

### v0.2 补充

- 添加市价单支持
- 添加批量订单操作
- 添加交易历史
- 添加账户余额查询
- 添加通知系统

### v0.3 补充

- 完整 Builder 支持
- RFQ 客户端
- Heartbeat 机制

### v0.4 补充

- 奖励系统
- 订单评分
