# API 参考文档

本文档详细描述 Polymarket Zig CLOB Client SDK 的所有公共 API。

## 目录

- [1. Client API](#1-client-api)
  - [1.1 初始化](#11-初始化)
  - [1.2 公共方法](#12-公共方法)
  - [1.3 认证方法](#13-认证方法)
  - [1.4 订单管理](#14-订单管理)
  - [1.5 交易查询](#15-交易查询)
- [2. OrderBuilder API](#2-orderbuilder-api)
- [3. Signer API](#3-signer-api)
- [4. Types API](#4-types-api)
- [5. REST API 端点映射](#5-rest-api-端点映射)

---

## 1. Client API

### 1.1 初始化

#### `Client.init`

创建新的客户端实例。

```zig
pub fn init(allocator: std.mem.Allocator, config: Config) !Client(.unauthenticated)
```

**参数:**
| 参数 | 类型 | 描述 |
|------|------|------|
| `allocator` | `std.mem.Allocator` | 内存分配器 |
| `config` | `Config` | 客户端配置 |

**返回:** `!Client(.unauthenticated)` - 未认证状态的客户端

**示例:**
```zig
var client = try Client.init(allocator, .{
    .host = "https://clob.polymarket.com",
    .timeout_ms = 30000,
});
defer client.deinit();
```

#### `Client.default`

使用默认配置创建客户端。

```zig
pub fn default(allocator: std.mem.Allocator) !Client(.unauthenticated)
```

**示例:**
```zig
var client = try Client.default(allocator);
defer client.deinit();
```

#### `Client.deinit`

释放客户端资源。

```zig
pub fn deinit(self: *Client) void
```

---

### 1.2 公共方法

以下方法在所有客户端状态下可用（未认证、已认证、Builder 认证）。

#### `ok`

检查 CLOB API 服务状态。

```zig
pub fn ok(self: *Client) ![]const u8
```

**返回:** `![]const u8` - 服务状态字符串 "OK"

**对应 API:** `GET /`

---

#### `serverTime`

获取服务器时间戳。

```zig
pub fn serverTime(self: *Client) !i64
```

**返回:** `!i64` - Unix 时间戳（秒）

**对应 API:** `GET /time`

---

#### `midpoint`

获取特定代币的中间价格。

```zig
pub fn midpoint(self: *Client, request: MidpointRequest) !MidpointResponse
```

**参数:**
| 参数 | 类型 | 描述 |
|------|------|------|
| `request.token_id` | `[]const u8` | 代币 ID |

**返回:**
```zig
pub const MidpointResponse = struct {
    mid: Decimal,
};
```

**对应 API:** `GET /midpoint?token_id={token_id}`

---

#### `midpoints`

批量获取多个代币的中间价格。

```zig
pub fn midpoints(self: *Client, requests: []const MidpointRequest) !MidpointsResponse
```

**对应 API:** `POST /midpoints`

---

#### `price`

获取特定代币和方向的价格。

```zig
pub fn price(self: *Client, request: PriceRequest) !PriceResponse
```

**参数:**
```zig
pub const PriceRequest = struct {
    token_id: []const u8,
    side: Side,
};
```

**返回:**
```zig
pub const PriceResponse = struct {
    price: Decimal,
};
```

**对应 API:** `GET /price?token_id={token_id}&side={side}`

---

#### `prices`

批量获取价格。

```zig
pub fn prices(self: *Client, requests: []const PriceRequest) !PricesResponse
```

**对应 API:** `POST /prices`

---

#### `spread`

获取特定代币的买卖价差。

```zig
pub fn spread(self: *Client, request: SpreadRequest) !SpreadResponse
```

**返回:**
```zig
pub const SpreadResponse = struct {
    spread: Decimal,
};
```

**对应 API:** `GET /spread?token_id={token_id}`

---

#### `tickSize`

获取代币的最小价格精度。

```zig
pub fn tickSize(self: *Client, token_id: []const u8) !TickSizeResponse
```

**返回:**
```zig
pub const TickSizeResponse = struct {
    minimum_tick_size: TickSize,
};
```

**对应 API:** `GET /tick-size?token_id={token_id}`

**注意:** 结果会被缓存以减少 API 调用。

---

#### `negRisk`

检查代币是否属于负风险市场。

```zig
pub fn negRisk(self: *Client, token_id: []const u8) !NegRiskResponse
```

**返回:**
```zig
pub const NegRiskResponse = struct {
    neg_risk: bool,
};
```

**对应 API:** `GET /neg-risk?token_id={token_id}`

---

#### `feeRateBps`

获取代币的手续费率（基点）。

```zig
pub fn feeRateBps(self: *Client, token_id: []const u8) !FeeRateResponse
```

**返回:**
```zig
pub const FeeRateResponse = struct {
    base_fee: u32,
};
```

**对应 API:** `GET /fee-rate?token_id={token_id}`

---

#### `checkGeoblock`

检查当前 IP 是否被地理封锁。

```zig
pub fn checkGeoblock(self: *Client) !GeoblockResponse
```

**返回:**
```zig
pub const GeoblockResponse = struct {
    blocked: bool,
    ip: []const u8,
    country: []const u8,
    region: []const u8,
};
```

**对应 API:** `GET {geoblock_host}/api/geoblock`

---

#### `orderBook`

获取订单簿摘要。

```zig
pub fn orderBook(self: *Client, request: OrderBookSummaryRequest) !OrderBookSummaryResponse
```

**返回:**
```zig
pub const OrderBookSummaryResponse = struct {
    market: []const u8,
    asset_id: []const u8,
    bids: []PriceLevel,
    asks: []PriceLevel,
    hash: []const u8,
    timestamp: i64,
};

pub const PriceLevel = struct {
    price: Decimal,
    size: Decimal,
};
```

**对应 API:** `GET /book?token_id={token_id}`

---

#### `orderBooks`

批量获取订单簿。

```zig
pub fn orderBooks(self: *Client, requests: []const OrderBookSummaryRequest) ![]OrderBookSummaryResponse
```

**对应 API:** `POST /books`

---

#### `lastTradePrice`

获取最新成交价。

```zig
pub fn lastTradePrice(self: *Client, request: LastTradePriceRequest) !LastTradePriceResponse
```

**返回:**
```zig
pub const LastTradePriceResponse = struct {
    price: Decimal,
};
```

**对应 API:** `GET /last-trade-price?token_id={token_id}`

---

#### `market`

获取特定市场信息。

```zig
pub fn market(self: *Client, condition_id: []const u8) !MarketResponse
```

**返回:**
```zig
pub const MarketResponse = struct {
    condition_id: []const u8,
    question_id: []const u8,
    tokens: []TokenInfo,
    rewards: RewardsInfo,
    minimum_order_size: Decimal,
    minimum_tick_size: TickSize,
    description: []const u8,
    category: []const u8,
    end_date_iso: []const u8,
    game_start_time: ?[]const u8,
    question: []const u8,
    market_slug: []const u8,
    min_incentive_size: Decimal,
    max_incentive_spread: Decimal,
    active: bool,
    closed: bool,
    seconds_delay: i32,
    icon: []const u8,
    fpmm: []const u8,
    neg_risk: bool,
    neg_risk_market_id: ?[]const u8,
    neg_risk_request_id: ?[]const u8,
    is_50_50_outcome: bool,
    accepting_orders: bool,
    accepting_order_timestamp: ?[]const u8,
};
```

**对应 API:** `GET /markets/{condition_id}`

---

#### `markets`

获取市场列表（分页）。

```zig
pub fn markets(self: *Client, next_cursor: ?[]const u8) !Page(MarketResponse)
```

**返回:**
```zig
pub fn Page(comptime T: type) type {
    return struct {
        data: []T,
        next_cursor: []const u8,
        limit: u32,
        count: u32,
    };
}
```

**对应 API:** `GET /markets?next_cursor={cursor}`

---

#### `samplingMarkets`

获取抽样市场列表。

```zig
pub fn samplingMarkets(self: *Client, next_cursor: ?[]const u8) !Page(MarketResponse)
```

**对应 API:** `GET /sampling-markets?next_cursor={cursor}`

---

#### `simplifiedMarkets`

获取简化市场列表。

```zig
pub fn simplifiedMarkets(self: *Client, next_cursor: ?[]const u8) !Page(SimplifiedMarketResponse)
```

**对应 API:** `GET /simplified-markets?next_cursor={cursor}`

---

### 1.3 认证方法

#### `authenticate`

将未认证客户端升级为已认证客户端。

```zig
pub fn authenticate(
    self: *Client(.unauthenticated), 
    signer: *Signer,
    options: AuthenticateOptions,
) !Client(.authenticated)
```

**参数:**
```zig
pub const AuthenticateOptions = struct {
    credentials: ?Credentials = null,  // 可选：使用现有凭证
    nonce: ?u32 = null,                // 可选：指定 nonce
    funder: ?Address = null,           // 可选：资金地址
    signature_type: SignatureType = .eoa,
};
```

**示例:**
```zig
// 自动创建/派生 API 凭证
var auth_client = try client.authenticate(&signer, .{});

// 使用 Proxy 钱包
var auth_client = try client.authenticate(&signer, .{
    .funder = funder_address,
    .signature_type = .proxy,
});
```

---

#### `createApiKey`

创建新的 API 凭证（L1 认证）。

```zig
pub fn createApiKey(
    self: *Client(.unauthenticated),
    signer: *Signer,
    nonce: ?u32,
) !Credentials
```

**对应 API:** `POST /auth/api-key` (L1 Headers)

---

#### `deriveApiKey`

派生现有 API 凭证（L1 认证）。

```zig
pub fn deriveApiKey(
    self: *Client(.unauthenticated),
    signer: *Signer,
    nonce: ?u32,
) !Credentials
```

**对应 API:** `GET /auth/derive-api-key` (L1 Headers)

---

#### `createOrDeriveApiKey`

创建或派生 API 凭证（幂等操作）。

```zig
pub fn createOrDeriveApiKey(
    self: *Client(.unauthenticated),
    signer: *Signer,
    nonce: ?u32,
) !Credentials
```

---

#### `apiKeys`

获取当前地址的所有 API 密钥。

```zig
pub fn apiKeys(self: *Client(.authenticated)) !ApiKeysResponse
```

**对应 API:** `GET /auth/api-keys` (L2 Headers)

---

#### `deleteApiKey`

删除当前 API 密钥。

```zig
pub fn deleteApiKey(self: *Client(.authenticated)) !void
```

**对应 API:** `DELETE /auth/api-key` (L2 Headers)

---

#### `promoteToBuilder`

将已认证客户端升级为 Builder 认证客户端。

```zig
pub fn promoteToBuilder(
    self: *Client(.authenticated),
    config: BuilderConfig,
) !Client(.builder_authenticated)
```

**参数:**
```zig
pub const BuilderConfig = union(enum) {
    local: Credentials,
    remote: struct {
        host: []const u8,
        token: ?[]const u8,
    },
};
```

---

### 1.4 订单管理

#### `limitOrder`

创建限价单构建器。

```zig
pub fn limitOrder(self: *Client(.authenticated)) OrderBuilder(.limit)
```

**示例:**
```zig
const order = try client.limitOrder()
    .tokenId("token-id")
    .price(Decimal.fromFloat(0.65))
    .size(Decimal.fromFloat(100.0))
    .side(.buy)
    .orderType(.gtc)
    .build();
```

---

#### `marketOrder`

创建市价单构建器。

```zig
pub fn marketOrder(self: *Client(.authenticated)) OrderBuilder(.market)
```

**示例:**
```zig
const order = try client.marketOrder()
    .tokenId("token-id")
    .amount(Amount.usdc(Decimal.fromFloat(100.0)))
    .side(.buy)
    .orderType(.fok)
    .build();
```

---

#### `sign`

签名可签名订单。

```zig
pub fn sign(
    self: *Client(.authenticated),
    signer: *Signer,
    order: SignableOrder,
) !SignedOrder
```

---

#### `postOrder`

提交单个订单。

```zig
pub fn postOrder(self: *Client(.authenticated), order: SignedOrder) ![]PostOrderResponse
```

**返回:**
```zig
pub const PostOrderResponse = struct {
    order_id: []const u8,
    status: []const u8,
    error_msg: ?[]const u8,
};
```

**对应 API:** `POST /orders` (L2 Headers)

---

#### `postOrders`

批量提交订单。

```zig
pub fn postOrders(self: *Client(.authenticated), orders: []const SignedOrder) ![]PostOrderResponse
```

**对应 API:** `POST /orders` (L2 Headers)

---

#### `order`

获取特定订单信息。

```zig
pub fn order(self: *Client(.authenticated), order_id: []const u8) !OpenOrderResponse
```

**返回:**
```zig
pub const OpenOrderResponse = struct {
    id: []const u8,
    status: OrderStatusType,
    owner: []const u8,
    market: []const u8,
    asset_id: []const u8,
    side: Side,
    original_size: Decimal,
    size_matched: Decimal,
    price: Decimal,
    outcome: []const u8,
    order_type: OrderType,
    created_at: []const u8,
    expiration: []const u8,
    associate_trades: []TradeResponse,
};
```

**对应 API:** `GET /data/order/{order_id}` (L2 Headers)

---

#### `orders`

获取订单列表。

```zig
pub fn orders(
    self: *Client(.authenticated),
    request: OrdersRequest,
    next_cursor: ?[]const u8,
) !Page(OpenOrderResponse)
```

**参数:**
```zig
pub const OrdersRequest = struct {
    market: ?[]const u8 = null,
    asset_id: ?[]const u8 = null,
    state: ?OrderStatusType = null,
};
```

**对应 API:** `GET /data/orders` (L2 Headers)

---

#### `cancelOrder`

取消单个订单。

```zig
pub fn cancelOrder(self: *Client(.authenticated), order_id: []const u8) !CancelOrdersResponse
```

**返回:**
```zig
pub const CancelOrdersResponse = struct {
    canceled: []const u8,  // 已取消的订单 ID 列表
    not_canceled: struct {
        id: []const u8,
        reason: []const u8,
    },
};
```

**对应 API:** `DELETE /order` (L2 Headers)

---

#### `cancelOrders`

批量取消订单。

```zig
pub fn cancelOrders(self: *Client(.authenticated), order_ids: []const []const u8) !CancelOrdersResponse
```

**对应 API:** `DELETE /orders` (L2 Headers)

---

#### `cancelAllOrders`

取消所有订单。

```zig
pub fn cancelAllOrders(self: *Client(.authenticated)) !CancelOrdersResponse
```

**对应 API:** `DELETE /cancel-all` (L2 Headers)

---

#### `cancelMarketOrders`

取消特定市场的所有订单。

```zig
pub fn cancelMarketOrders(self: *Client(.authenticated), request: CancelMarketOrderRequest) !CancelOrdersResponse
```

**参数:**
```zig
pub const CancelMarketOrderRequest = struct {
    market: ?[]const u8 = null,
    asset_id: ?[]const u8 = null,
};
```

**对应 API:** `DELETE /cancel-market-orders` (L2 Headers)

---

### 1.5 交易查询

#### `trades`

获取交易历史。

```zig
pub fn trades(
    self: *Client(.authenticated),
    request: TradesRequest,
    next_cursor: ?[]const u8,
) !Page(TradeResponse)
```

**参数:**
```zig
pub const TradesRequest = struct {
    market: ?[]const u8 = null,
    asset_id: ?[]const u8 = null,
    maker_address: ?[]const u8 = null,
    before: ?i64 = null,
    after: ?i64 = null,
    id: ?[]const u8 = null,
};
```

**返回:**
```zig
pub const TradeResponse = struct {
    id: []const u8,
    taker_order_id: []const u8,
    market: []const u8,
    asset_id: []const u8,
    side: Side,
    size: Decimal,
    fee_rate_bps: u32,
    price: Decimal,
    status: []const u8,
    match_time: []const u8,
    last_update: []const u8,
    outcome: []const u8,
    bucket_index: u32,
    owner: []const u8,
    maker_address: []const u8,
    transaction_hash: ?[]const u8,
    trader_side: TraderSide,
    type: []const u8,
};
```

**对应 API:** `GET /data/trades` (L2 Headers)

---

### 1.6 余额和授权

#### `balanceAllowance`

获取余额和授权信息。

```zig
pub fn balanceAllowance(
    self: *Client(.authenticated),
    request: BalanceAllowanceRequest,
) !BalanceAllowanceResponse
```

**参数:**
```zig
pub const BalanceAllowanceRequest = struct {
    asset_type: ?AssetType = null,
    token_id: ?[]const u8 = null,
    signature_type: ?SignatureType = null,
};
```

**返回:**
```zig
pub const BalanceAllowanceResponse = struct {
    balance: Decimal,
    allowance: Decimal,
};
```

**对应 API:** `GET /balance-allowance` (L2 Headers)

---

### 1.7 通知

#### `notifications`

获取通知列表。

```zig
pub fn notifications(self: *Client(.authenticated)) ![]NotificationResponse
```

**对应 API:** `GET /notifications` (L2 Headers)

---

#### `deleteNotifications`

删除通知。

```zig
pub fn deleteNotifications(self: *Client(.authenticated), request: DeleteNotificationsRequest) !void
```

**对应 API:** `DELETE /notifications` (L2 Headers)

---

### 1.8 奖励

#### `currentRewards`

获取当前奖励信息。

```zig
pub fn currentRewards(self: *Client(.authenticated), next_cursor: ?[]const u8) !Page(CurrentRewardResponse)
```

**对应 API:** `GET /rewards/markets/current` (L2 Headers)

---

#### `earningsForUserForDay`

获取用户特定日期的收益。

```zig
pub fn earningsForUserForDay(
    self: *Client(.authenticated),
    date: Date,
    next_cursor: ?[]const u8,
) !Page(UserEarningResponse)
```

**对应 API:** `GET /rewards/user` (L2 Headers)

---

### 1.9 Builder 专用方法

以下方法仅在 Builder 认证状态下可用。

#### `builderApiKeys`

获取 Builder API 密钥。

```zig
pub fn builderApiKeys(self: *Client(.builder_authenticated)) ![]BuilderApiKeyResponse
```

**对应 API:** `GET /auth/builder-api-key` (L2 + Builder Headers)

---

#### `createBuilderApiKey`

创建 Builder API 密钥。

```zig
pub fn createBuilderApiKey(self: *Client(.authenticated)) !Credentials
```

**对应 API:** `POST /auth/builder-api-key` (L2 Headers)

---

#### `revokeBuilderApiKey`

撤销 Builder API 密钥。

```zig
pub fn revokeBuilderApiKey(self: *Client(.builder_authenticated)) !void
```

**对应 API:** `DELETE /auth/builder-api-key` (L2 + Builder Headers)

---

#### `builderTrades`

获取 Builder 交易历史。

```zig
pub fn builderTrades(
    self: *Client(.builder_authenticated),
    request: TradesRequest,
    next_cursor: ?[]const u8,
) !Page(BuilderTradeResponse)
```

**对应 API:** `GET /builder/trades` (L2 + Builder Headers)

---

## 2. OrderBuilder API

### 2.1 通用方法

#### `tokenId`

设置代币 ID（必填）。

```zig
pub fn tokenId(self: Self, id: []const u8) Self
```

---

#### `side`

设置交易方向（必填）。

```zig
pub fn side(self: Self, s: Side) Self
```

---

#### `nonce`

设置 nonce 值。

```zig
pub fn nonce(self: Self, n: u64) Self
```

---

#### `expiration`

设置过期时间（仅 GTD 订单）。

```zig
pub fn expiration(self: Self, exp: i64) Self
```

---

#### `taker`

设置指定接单方地址。

```zig
pub fn taker(self: Self, addr: Address) Self
```

---

#### `orderType`

设置订单类型。

```zig
pub fn orderType(self: Self, ot: OrderType) Self
```

---

### 2.2 限价单方法

#### `price`

设置价格（必填）。

```zig
pub fn price(self: Self, p: Decimal) Self
```

---

#### `size`

设置数量（必填）。

```zig
pub fn size(self: Self, s: Decimal) Self
```

---

### 2.3 市价单方法

#### `amount`

设置金额（必填）。

```zig
pub fn amount(self: Self, a: Amount) Self
```

---

### 2.4 构建

#### `build`

验证并构建订单。

```zig
pub fn build(self: Self) !SignableOrder
```

**可能的错误:**
- `error.MissingTokenId` - 缺少代币 ID
- `error.MissingSide` - 缺少交易方向
- `error.MissingPrice` - 缺少价格（限价单）
- `error.MissingSize` - 缺少数量（限价单）
- `error.MissingAmount` - 缺少金额（市价单）
- `error.InvalidPrice` - 价格无效
- `error.InvalidSize` - 数量无效
- `error.InvalidTickSize` - 价格精度超出限制

---

## 3. Signer API

### 3.1 Signer 接口

```zig
pub const Signer = struct {
    pub fn address(self: *Signer) Address
    pub fn signHash(self: *Signer, hash: [32]u8) ![65]u8
    pub fn chainId(self: *Signer) ?u64
};
```

---

### 3.2 LocalSigner

#### `fromHex`

从十六进制私钥创建签名器。

```zig
pub fn fromHex(hex: []const u8) !LocalSigner
```

**示例:**
```zig
const signer = try LocalSigner.fromHex("0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");
```

---

#### `fromBytes`

从字节数组创建签名器。

```zig
pub fn fromBytes(bytes: [32]u8) LocalSigner
```

---

#### `withChainId`

设置链 ID。

```zig
pub fn withChainId(self: LocalSigner, chain_id: u64) LocalSigner
```

**示例:**
```zig
const signer = try LocalSigner.fromHex(private_key);
const polygon_signer = signer.withChainId(137);  // Polygon mainnet
```

---

#### `asSigner`

转换为通用 Signer 接口。

```zig
pub fn asSigner(self: *LocalSigner) Signer
```

---

## 4. Types API

### 4.1 Decimal

高精度十进制数类型。

```zig
pub const Decimal = struct {
    pub fn fromFloat(value: f64) Decimal
    pub fn fromInt(value: i64) Decimal
    pub fn fromString(str: []const u8) !Decimal
    pub fn toFloat(self: Decimal) f64
    pub fn scale(self: Decimal) u8
    pub fn truncWithScale(self: Decimal, new_scale: u8) Decimal
    pub fn normalize(self: Decimal) Decimal
    
    // 常量
    pub const ZERO: Decimal;
    pub const ONE: Decimal;
    pub const ONE_HUNDRED: Decimal;
};
```

---

### 4.2 Amount

金额类型，区分 USDC 和 Shares。

```zig
pub const Amount = struct {
    pub fn usdc(value: Decimal) !Amount
    pub fn shares(value: Decimal) !Amount
    pub fn asInner(self: Amount) Decimal
    pub fn isUsdc(self: Amount) bool
    pub fn isShares(self: Amount) bool
};
```

---

### 4.3 Address

以太坊地址类型。

```zig
pub const Address = [20]u8;

pub fn addressFromHex(hex: []const u8) !Address
pub fn addressToHex(address: Address, allocator: std.mem.Allocator) ![]const u8
```

---

### 4.4 常量

```zig
/// Polygon 主网链 ID
pub const POLYGON: u64 = 137;

/// Polygon 测试网链 ID (Amoy)
pub const AMOY: u64 = 80002;

/// 私钥环境变量名
pub const PRIVATE_KEY_VAR: []const u8 = "POLYMARKET_PRIVATE_KEY";
```

---

## 5. REST API 端点映射

| SDK 方法 | HTTP 方法 | 端点 | 认证级别 |
|---------|----------|------|---------|
| `ok` | GET | `/` | 无 |
| `serverTime` | GET | `/time` | 无 |
| `midpoint` | GET | `/midpoint` | 无 |
| `midpoints` | POST | `/midpoints` | 无 |
| `price` | GET | `/price` | 无 |
| `prices` | POST | `/prices` | 无 |
| `spread` | GET | `/spread` | 无 |
| `spreads` | POST | `/spreads` | 无 |
| `tickSize` | GET | `/tick-size` | 无 |
| `negRisk` | GET | `/neg-risk` | 无 |
| `feeRateBps` | GET | `/fee-rate` | 无 |
| `orderBook` | GET | `/book` | 无 |
| `orderBooks` | POST | `/books` | 无 |
| `lastTradePrice` | GET | `/last-trade-price` | 无 |
| `market` | GET | `/markets/{id}` | 无 |
| `markets` | GET | `/markets` | 无 |
| `samplingMarkets` | GET | `/sampling-markets` | 无 |
| `simplifiedMarkets` | GET | `/simplified-markets` | 无 |
| `checkGeoblock` | GET | `/api/geoblock` | 无 |
| `createApiKey` | POST | `/auth/api-key` | L1 |
| `deriveApiKey` | GET | `/auth/derive-api-key` | L1 |
| `apiKeys` | GET | `/auth/api-keys` | L2 |
| `deleteApiKey` | DELETE | `/auth/api-key` | L2 |
| `closedOnlyMode` | GET | `/auth/ban-status/closed-only` | L2 |
| `postOrder` | POST | `/orders` | L2 |
| `postOrders` | POST | `/orders` | L2 |
| `order` | GET | `/data/order/{id}` | L2 |
| `orders` | GET | `/data/orders` | L2 |
| `cancelOrder` | DELETE | `/order` | L2 |
| `cancelOrders` | DELETE | `/orders` | L2 |
| `cancelAllOrders` | DELETE | `/cancel-all` | L2 |
| `cancelMarketOrders` | DELETE | `/cancel-market-orders` | L2 |
| `trades` | GET | `/data/trades` | L2 |
| `notifications` | GET | `/notifications` | L2 |
| `deleteNotifications` | DELETE | `/notifications` | L2 |
| `balanceAllowance` | GET | `/balance-allowance` | L2 |
| `updateBalanceAllowance` | GET | `/balance-allowance/update` | L2 |
| `isOrderScoring` | GET | `/order-scoring` | L2 |
| `areOrdersScoring` | GET | `/orders-scoring` | L2 |
| `currentRewards` | GET | `/rewards/markets/current` | L2 |
| `earningsForUserForDay` | GET | `/rewards/user` | L2 |
| `totalEarningsForUserForDay` | GET | `/rewards/user/total` | L2 |
| `rewardPercentages` | GET | `/rewards/user/percentages` | L2 |
| `rawRewardsForMarket` | GET | `/rewards/markets/{id}` | L2 |
| `createBuilderApiKey` | POST | `/auth/builder-api-key` | L2 |
| `builderApiKeys` | GET | `/auth/builder-api-key` | Builder |
| `revokeBuilderApiKey` | DELETE | `/auth/builder-api-key` | Builder |
| `builderTrades` | GET | `/builder/trades` | Builder |

---

## 6. 错误码参考

| 错误码 | 描述 |
|--------|------|
| `ConnectionFailed` | 网络连接失败 |
| `Timeout` | 请求超时 |
| `InvalidSignature` | 签名无效 |
| `InvalidCredentials` | 凭证无效 |
| `Unauthorized` | 未授权 |
| `NonceAlreadyUsed` | Nonce 已被使用 |
| `ValidationFailed` | 验证失败 |
| `InvalidTickSize` | 价格精度无效 |
| `InvalidPrice` | 价格无效 |
| `InvalidSize` | 数量无效 |
| `InsufficientLiquidity` | 流动性不足 |
| `ApiError` | API 错误 |
| `NotFound` | 资源未找到 |
| `RateLimited` | 请求频率限制 |
| `Geoblocked` | 地理位置限制 |
| `MissingContractConfig` | 缺少合约配置 |
