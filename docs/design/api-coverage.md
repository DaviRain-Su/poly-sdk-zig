# API 功能覆盖分析

本文档对比官方 Python/TypeScript 客户端的功能，确保我们的 Zig 实现覆盖所有 API。

**参考仓库**:
- [py-clob-client](https://github.com/Polymarket/py-clob-client) - Python 客户端 (v0.34.1)
- [clob-client](https://github.com/Polymarket/clob-client) - TypeScript 客户端 (v5.1.3)
- [agents](https://github.com/Polymarket/agents) - AI 交易代理框架

**相关文档**:
- [合约配置](./contracts.md) - Polygon 合约地址
- [类型定义](./types.md) - 详细类型定义

---

## 目录

1. [认证级别](#认证级别)
2. [签名类型](#签名类型)
3. [公共端点 (L0)](#公共端点-l0---无需认证)
4. [L1 认证端点](#l1-认证端点)
5. [L2 认证端点](#l2-认证端点)
6. [Builder 认证](#builder-认证)
7. [RFQ 系统](#rfq-request-for-quote)
8. [奖励系统](#奖励系统)
9. [Gamma API](#gamma-api-市场元数据)
10. [核心类型](#核心类型)
11. [Header 类型](#header-类型)
12. [缺失功能总结](#缺失功能总结)

---

## 认证级别

官方客户端支持三个认证级别：

| 级别 | 描述 | 需要 | 访问权限 |
|------|------|------|----------|
| L0 | 只读公共 API | 仅 host URL | 市场数据、订单簿、价格 |
| L1 | L1 认证端点 | host + chain_id + private_key | 创建/派生 API Key、签名订单 |
| L2 | 完整访问 | host + chain_id + private_key + API credentials | 所有端点 |
| Builder | 做市商程序 | L2 + BuilderConfig | Builder 专用端点 |

---

## 签名类型

`signature_type` 参数告诉系统如何验证签名：

| 值 | 名称 | 描述 | 使用场景 |
|----|------|------|----------|
| `0` | EOA | 标准外部账户签名 | MetaMask、硬件钱包、直接控制私钥 |
| `1` | Email/Magic | 委托签名 | Email 登录、Magic 钱包 |
| `2` | Proxy | 浏览器钱包代理签名 | 代理合约（非直接钱包连接） |

**注意**: 使用代理钱包时需要设置 `funder` 参数，指向实际持有资金的地址。

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
| `/simplified-markets` | GET | `get_simplified_markets()` | `getSimplifiedMarkets()` | v0.1 ✅ |
| `/sampling-markets` | GET | `get_sampling_markets()` | `getSamplingMarkets()` | v0.1 ✅ |
| `/sampling-simplified-markets` | GET | `get_sampling_simplified_markets()` | `getSamplingSimplifiedMarkets()` | v0.1 ✅ |
| `/markets/{condition_id}` | GET | `get_market()` | `getMarket()` | v0.1 ✅ |
| `/live-activity/events/{condition_id}` | GET | `get_market_trades_events()` | `getMarketTradesEvents()` | v0.5 ⏳ |

### 价格和订单簿

| 端点 | 方法 | Python | TypeScript | Zig ROADMAP |
|------|------|--------|------------|-------------|
| `/book` | GET | `get_order_book()` | `getOrderBook()` | v0.1 ✅ |
| `/books` | POST | `get_order_books()` | `getOrderBooks()` | v0.1 ✅ |
| `/midpoint` | GET | `get_midpoint()` | `getMidpoint()` | v0.1 ✅ |
| `/midpoints` | POST | `get_midpoints()` | `getMidpoints()` | v0.1 ✅ |
| `/price` | GET | `get_price()` | `getPrice()` | v0.1 ✅ |
| `/prices` | POST | `get_prices()` | `getPrices()` | v0.1 ✅ |
| `/spread` | GET | `get_spread()` | `getSpread()` | v0.1 ✅ |
| `/spreads` | POST | `get_spreads()` | `getSpreads()` | v0.1 ✅ |
| `/last-trade-price` | GET | `get_last_trade_price()` | `getLastTradePrice()` | v0.1 ✅ |
| `/last-trades-prices` | POST | `get_last_trades_prices()` | `getLastTradesPrices()` | v0.1 ✅ |
| `/tick-size` | GET | `get_tick_size()` | `getTickSize()` | v0.1 ✅ |
| `/neg-risk` | GET | `get_neg_risk()` | `getNegRisk()` | v0.1 ✅ |
| `/fee-rate` | GET | `get_fee_rate_bps()` | `getFeeRateBps()` | v0.1 ✅ |
| `/prices-history` | GET | - | `getPricesHistory()` | v0.5 ⏳ |

### Readonly API Key 验证

| 端点 | 方法 | Python | TypeScript | Zig ROADMAP |
|------|------|--------|------------|-------------|
| `/auth/validate-readonly-api-key` | GET | `validate_readonly_api_key()` | `validateReadonlyApiKey()` | v0.3 ⏳ |

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
| 创建市价单 | `create_market_order()` | `createMarketOrder()` | v0.2 ✅ |
| 计算市价 | `calculate_market_price()` | `calculateMarketPrice()` | v0.2 ✅ |

---

## L2 认证端点

### API Key 管理

| 端点 | 方法 | Python | TypeScript | Zig ROADMAP |
|------|------|--------|------------|-------------|
| `/auth/api-keys` | GET | `get_api_keys()` | `getApiKeys()` | v0.2 ✅ |
| `/auth/api-key` | DELETE | `delete_api_key()` | `deleteApiKey()` | v0.2 ✅ |
| `/auth/ban-status/closed-only` | GET | `get_closed_only_mode()` | `getClosedOnlyMode()` | v0.2 ✅ |

### Readonly API Key 管理

| 端点 | 方法 | Python | TypeScript | Zig ROADMAP |
|------|------|--------|------------|-------------|
| `/auth/readonly-api-key` | POST | `create_readonly_api_key()` | `createReadonlyApiKey()` | v0.3 ⏳ |
| `/auth/readonly-api-keys` | GET | `get_readonly_api_keys()` | `getReadonlyApiKeys()` | v0.3 ⏳ |
| `/auth/readonly-api-key` | DELETE | `delete_readonly_api_key()` | `deleteReadonlyApiKey()` | v0.3 ⏳ |

### 订单管理

| 端点 | 方法 | Python | TypeScript | Zig ROADMAP |
|------|------|--------|------------|-------------|
| `/order` | POST | `post_order()` | `postOrder()` | v0.2 ✅ |
| `/orders` | POST | `post_orders()` | `postOrders()` | v0.2 ✅ |
| `/data/orders` | GET | `get_orders()` | `getOpenOrders()` | v0.2 ✅ |
| `/data/order/{id}` | GET | `get_order()` | `getOrder()` | v0.2 ✅ |
| `/order` | DELETE | `cancel()` | `cancelOrder()` | v0.2 ✅ |
| `/orders` | DELETE | `cancel_orders()` | `cancelOrders()` | v0.2 ✅ |
| `/cancel-all` | DELETE | `cancel_all()` | `cancelAll()` | v0.2 ✅ |
| `/cancel-market-orders` | DELETE | `cancel_market_orders()` | `cancelMarketOrders()` | v0.2 ✅ |

### 交易和便捷方法

| 功能 | Python | TypeScript | Zig ROADMAP |
|------|--------|------------|-------------|
| 创建并发布订单 | `create_and_post_order()` | `createAndPostOrder()` | v0.2 ✅ |
| 创建并发布市价单 | - | `createAndPostMarketOrder()` | v0.2 ✅ |
| 获取交易历史 | `get_trades()` | `getTrades()` | v0.2 ✅ |
| 分页获取交易 | - | `getTradesPaginated()` | v0.2 ✅ |

### 账户和余额

| 端点 | 方法 | Python | TypeScript | Zig ROADMAP |
|------|------|--------|------------|-------------|
| `/balance-allowance` | GET | `get_balance_allowance()` | `getBalanceAllowance()` | v0.2 ✅ |
| `/balance-allowance/update` | GET | `update_balance_allowance()` | `updateBalanceAllowance()` | v0.2 ✅ |

### 通知

| 端点 | 方法 | Python | TypeScript | Zig ROADMAP |
|------|------|--------|------------|-------------|
| `/notifications` | GET | `get_notifications()` | `getNotifications()` | v0.2 ✅ |
| `/notifications` | DELETE | `drop_notifications()` | `dropNotifications()` | v0.2 ✅ |

### 订单评分

| 端点 | 方法 | Python | TypeScript | Zig ROADMAP |
|------|------|--------|------------|-------------|
| `/order-scoring` | GET | `is_order_scoring()` | `isOrderScoring()` | v0.5 ⏳ |
| `/orders-scoring` | POST | `are_orders_scoring()` | `areOrdersScoring()` | v0.5 ⏳ |

### Heartbeat

| 端点 | 方法 | Python | TypeScript | Zig ROADMAP | 说明 |
|------|------|--------|------------|-------------|------|
| `/v1/heartbeats` | POST | `post_heartbeat()` | - | v0.3 ⏳ | 10秒内不发送会取消所有订单 |

---

## Builder 认证

Builder 是用于做市商程序的独立认证流程。

### Builder API Key 管理

| 端点 | 方法 | Python | TypeScript | Zig ROADMAP |
|------|------|--------|------------|-------------|
| `/auth/builder-api-key` | POST | - | `createBuilderApiKey()` | v0.3 ⏳ |
| `/auth/builder-api-key` | GET | - | `getBuilderApiKeys()` | v0.3 ⏳ |
| `/auth/builder-api-key` | DELETE | - | `revokeBuilderApiKey()` | v0.3 ⏳ |

### Builder 交易

| 端点 | 方法 | Python | TypeScript | Zig ROADMAP |
|------|------|--------|------------|-------------|
| `/builder/trades` | GET | `get_builder_trades()` | `getBuilderTrades()` | v0.3 ⏳ |

### Builder 配置

```typescript
// BuilderConfig 接口
interface BuilderConfig {
    apiKey: string;
    apiSecret: string;
    passphrase: string;
    
    isValid(): boolean;
    generateBuilderHeaders(method: string, path: string, body?: string): BuilderHeaderPayload;
}
```

---

## RFQ (Request for Quote)

RFQ 是一个独立的子客户端，用于大宗交易的询价系统。

### RFQ 端点

| 端点 | 方法 | Python | TypeScript | Zig ROADMAP |
|------|------|--------|------------|-------------|
| `/rfq/request` | POST | `rfq.create_rfq_request()` | `rfq.createRfqRequest()` | v0.3 ⏳ |
| `/rfq/request` | DELETE | `rfq.cancel_rfq_request()` | `rfq.cancelRfqRequest()` | v0.3 ⏳ |
| `/rfq/data/requests` | GET | `rfq.get_rfq_requests()` | `rfq.getRfqRequests()` | v0.3 ⏳ |
| `/rfq/quote` | POST | `rfq.create_rfq_quote()` | `rfq.createRfqQuote()` | v0.3 ⏳ |
| `/rfq/quote` | DELETE | `rfq.cancel_rfq_quote()` | `rfq.cancelRfqQuote()` | v0.3 ⏳ |
| `/rfq/data/quotes` | GET | `rfq.get_rfq_quotes()` | `rfq.getRfqQuotes()` | v0.3 ⏳ |
| `/rfq/data/best-quote` | GET | `rfq.get_rfq_best_quote()` | `rfq.getRfqBestQuote()` | v0.3 ⏳ |
| `/rfq/request/accept` | POST | `rfq.accept_rfq_quote()` | `rfq.acceptRfqQuote()` | v0.3 ⏳ |
| `/rfq/quote/approve` | POST | `rfq.approve_rfq_order()` | `rfq.approveRfqOrder()` | v0.3 ⏳ |
| `/rfq/config` | GET | `rfq.rfq_config()` | `rfq.rfqConfig()` | v0.3 ⏳ |

### RFQ 匹配类型

```typescript
enum RfqMatchType {
    COMPLEMENTARY = "COMPLEMENTARY",  // BUY <> SELL, SELL <> BUY
    MERGE = "MERGE",                  // BUY <> BUY, SELL <> SELL (合并)
    MINT = "MINT"                     // BUY <> BUY, SELL <> SELL (铸造)
}
```

### RFQ 类型定义

```typescript
// RFQ 请求
interface RfqRequest {
    requestId: string;
    userAddress: string;
    proxyAddress: string;
    token: string;
    complement: string;
    condition: string;
    side: string;
    sizeIn: string;
    sizeOut: string;
    price: number;
    acceptedQuoteId: string;
    state: string;
    expiry: Date;
    createdAt: Date;
    updatedAt: Date;
}

// RFQ 报价
interface RfqQuote {
    quoteId: string;
    requestId: string;
    userAddress: string;
    proxyAddress: string;
    token: string;
    complement: string;
    condition: string;
    side: string;
    sizeIn: string;
    sizeOut: string;
    price: number;
    state: string;
    matchType: string;
    expiry: Date;
    createdAt: Date;
    updatedAt: Date;
}

// 创建 RFQ 请求参数
interface CreateRfqRequestParams {
    assetIn: string;
    assetOut: string;
    amountIn: string;
    amountOut: string;
    userType: number;
}

// 接受报价参数
interface AcceptQuoteParams {
    requestId: string;
    quoteId: string;
    expiration: number;
}
```

---

## 奖励系统

流动性奖励相关端点（仅 TypeScript 客户端）。

| 端点 | 方法 | TypeScript | Zig ROADMAP |
|------|------|------------|-------------|
| `/rewards/user` | GET | `getEarningsForUserForDay()` | v0.5 ⏳ |
| `/rewards/user/total` | GET | `getTotalEarningsForUserForDay()` | v0.5 ⏳ |
| `/rewards/user/percentages` | GET | `getRewardPercentages()` | v0.5 ⏳ |
| `/rewards/markets/current` | GET | `getCurrentRewards()` | v0.5 ⏳ |
| `/rewards/markets/{conditionId}` | GET | `getRawRewardsForMarket()` | v0.5 ⏳ |
| `/rewards/user/markets` | GET | `getUserEarningsAndMarketsConfig()` | v0.5 ⏳ |

### 奖励类型定义

```typescript
interface UserEarning {
    date: string;
    condition_id: string;
    asset_address: string;
    maker_address: string;
    earnings: number;
    asset_rate: number;
}

interface MarketReward {
    condition_id: string;
    question: string;
    market_slug: string;
    event_slug: string;
    image: string;
    rewards_max_spread: number;
    rewards_min_size: number;
    tokens: Token[];
    rewards_config: RewardsConfig[];
}

interface RewardsConfig {
    asset_address: string;
    start_date: string;
    end_date: string;
    rate_per_day: number;
    total_rewards: number;
}
```

---

## Gamma API (市场元数据)

Gamma API 是 Polymarket 的市场元数据 API，与 CLOB API 分离。

**Base URL**: `https://gamma-api.polymarket.com`

### Gamma 端点

| 端点 | 方法 | 功能 | Zig ROADMAP |
|------|------|------|-------------|
| `/markets` | GET | 获取所有市场 | v0.1 ⏳ |
| `/markets/{id}` | GET | 获取单个市场 | v0.1 ⏳ |
| `/events` | GET | 获取所有事件 | v0.1 ⏳ |

### Gamma 查询参数

| 参数 | 类型 | 说明 |
|------|------|------|
| `active` | bool | 筛选活跃市场 |
| `closed` | bool | 筛选已关闭市场 |
| `archived` | bool | 筛选已归档市场 |
| `limit` | int | 返回数量限制 |
| `offset` | int | 分页偏移 |
| `enableOrderBook` | bool | 筛选有订单簿的市场 |
| `clob_token_ids` | string | 按 token ID 查询 |

### Gamma 类型定义

```typescript
interface Market {
    id: string;
    question: string;
    description: string;
    active: boolean;
    closed: boolean;
    archived: boolean;
    funded: boolean;
    endDate: string;
    outcomes: string[];
    outcomePrices: string[];  // JSON 字符串数组
    clobTokenIds: string[];   // JSON 字符串数组
    volume: number;
    spread: number;
    rewardsMinSize: number;
    rewardsMaxSpread: number;
}

interface PolymarketEvent {
    id: string;
    ticker: string;
    slug: string;
    title: string;
    description: string;
    active: boolean;
    closed: boolean;
    archived: boolean;
    new: boolean;
    featured: boolean;
    restricted: boolean;
    endDate: string;
    markets: Market[];
    tags: Tag[];
}
```

---

## 核心类型

### 订单类型枚举

```typescript
enum OrderType {
    GTC = "GTC",  // Good Till Cancelled - 直到取消
    GTD = "GTD",  // Good Till Date - 直到指定日期
    FOK = "FOK",  // Fill Or Kill - 全部成交或取消
    FAK = "FAK"   // Fill And Kill - 部分成交，剩余取消
}

enum Side {
    BUY = "BUY",
    SELL = "SELL"
}
```

### 订单参数

```typescript
// 限价单参数
interface OrderArgs {
    token_id: string;      // Conditional token ID
    price: number;         // 价格 (0 < price < 1)
    size: number;          // 数量（以 token 计）
    side: Side;            // 买/卖
    fee_rate_bps?: number; // 费率（基点）
    nonce?: number;        // 用于链上取消
    expiration?: number;   // 过期时间戳
    taker?: string;        // 指定接单地址（零地址 = 公开订单）
}

// 市价单参数
interface MarketOrderArgs {
    token_id: string;
    amount: number;        // BUY: 美元金额, SELL: token 数量
    side: Side;
    price?: number;        // 不提供则自动计算
    fee_rate_bps?: number;
    nonce?: number;
    taker?: string;
    order_type?: OrderType.FOK | OrderType.FAK;
}
```

### 订单簿类型

```typescript
interface OrderBookSummary {
    market: string;        // 市场 condition ID
    asset_id: string;      // Token ID
    timestamp: string;
    bids: OrderSummary[];  // 买单列表
    asks: OrderSummary[];  // 卖单列表
    min_order_size: string;
    tick_size: string;     // "0.1" | "0.01" | "0.001" | "0.0001"
    neg_risk: boolean;
    hash: string;          // 订单簿哈希
}

interface OrderSummary {
    price: string;
    size: string;
}
```

### 交易类型

```typescript
interface Trade {
    id: string;
    taker_order_id: string;
    market: string;
    asset_id: string;
    side: Side;
    size: string;
    fee_rate_bps: string;
    price: string;
    status: string;
    match_time: string;
    last_update: string;
    outcome: string;
    bucket_index: number;
    owner: string;
    maker_address: string;
    maker_orders: MakerOrder[];
    transaction_hash: string;
    trader_side: "TAKER" | "MAKER";
}
```

### API 凭证

```typescript
interface ApiCreds {
    api_key: string;
    api_secret: string;
    api_passphrase: string;
}
```

### 查询参数类型

```typescript
interface TradeParams {
    id?: string;
    maker_address?: string;
    market?: string;
    asset_id?: string;
    before?: string;
    after?: string;
}

interface OpenOrderParams {
    id?: string;
    market?: string;
    asset_id?: string;
}

interface BookParams {
    token_id: string;
    side?: Side;
}

interface BalanceAllowanceParams {
    asset_type: "COLLATERAL" | "CONDITIONAL";
    token_id?: string;
    signature_type?: number;
}

interface PriceHistoryFilterParams {
    market?: string;
    startTs?: number;
    endTs?: number;
    fidelity?: number;
    interval?: "max" | "1w" | "1d" | "6h" | "1h";
}
```

---

## Header 类型

### L1 认证 Header (EIP-712 签名验证)

```typescript
interface L1PolyHeader {
    POLY_ADDRESS: string;      // 钱包地址
    POLY_SIGNATURE: string;    // EIP-712 签名
    POLY_TIMESTAMP: string;    // 时间戳
    POLY_NONCE: string;        // Nonce
}
```

### L2 认证 Header (API Key 验证)

```typescript
interface L2PolyHeader {
    POLY_ADDRESS: string;      // 钱包地址
    POLY_SIGNATURE: string;    // HMAC-SHA256 签名
    POLY_TIMESTAMP: string;    // 时间戳
    POLY_API_KEY: string;      // API Key
    POLY_PASSPHRASE: string;   // Passphrase
}
```

### Builder Header

```typescript
interface L2WithBuilderHeader extends L2PolyHeader {
    POLY_BUILDER_API_KEY: string;
    POLY_BUILDER_TIMESTAMP: string;
    POLY_BUILDER_PASSPHRASE: string;
    POLY_BUILDER_SIGNATURE: string;
}
```

---

## 签名和加密

| 功能 | 描述 | 使用场景 | Zig ROADMAP |
|------|------|----------|-------------|
| secp256k1 | 椭圆曲线签名 | 订单签名、L1 认证 | v0.2 ✅ |
| keccak256 | Keccak-256 哈希 | 地址计算、消息哈希 | v0.2 ✅ |
| HMAC-SHA256 | 消息认证码 | L2 API 请求签名 | v0.2 ✅ |
| EIP-712 | 结构化数据签名 | 订单签名、L1 认证 | v0.2 ✅ |
| EIP-55 | 地址校验和 | 地址格式化 | v0.1 ✅ |

---

## 缺失功能总结

### 已计划覆盖 (v0.1 - v0.3)

所有核心功能已在 ROADMAP 中计划：

- **v0.1**: 所有公共端点 (L0)
- **v0.2**: 认证、订单管理、交易历史
- **v0.3**: Builder、RFQ、Heartbeat、Readonly API Key

### 低优先级 (v0.5)

以下功能计划在 v0.5 实现：

1. **奖励系统** - 流动性奖励查询
2. **订单评分** - 订单质量评估
3. **价格历史** - 历史价格查询
4. **市场交易事件** - 实时交易活动

### 不计划实现

以下功能不在当前路线图中：

1. **Gamma API** - 可单独实现或作为可选模块
2. **WebSocket** - 计划在 v0.4 作为独立模块

---

## ROADMAP 对照表

| 版本 | 功能 | 端点数量 |
|------|------|----------|
| v0.1 | 公共 API (L0) | ~20 |
| v0.2 | 认证与订单 (L1/L2) | ~25 |
| v0.3 | Builder + RFQ | ~15 |
| v0.4 | WebSocket | - |
| v0.5 | 奖励 + 分析 | ~10 |
| v1.0 | 稳定版 | 全部 |

---

## 更新日志

| 日期 | 变更 |
|------|------|
| 2024-12-31 | 初始版本，基础 API 覆盖分析 |
| 2024-12-31 | 添加 RFQ 端点详情、合约配置、类型定义、Header 类型、Gamma API |
