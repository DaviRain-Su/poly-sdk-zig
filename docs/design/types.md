# 类型定义

本文档详细定义所有 Polymarket CLOB API 使用的类型。

**来源**:
- [py-clob-client/clob_types.py](https://github.com/Polymarket/py-clob-client/blob/main/py_clob_client/clob_types.py)
- [clob-client/src/types.ts](https://github.com/Polymarket/clob-client/blob/main/src/types.ts)

---

## 目录

1. [枚举类型](#枚举类型)
2. [API 凭证](#api-凭证)
3. [订单类型](#订单类型)
4. [订单簿类型](#订单簿类型)
5. [交易类型](#交易类型)
6. [查询参数](#查询参数)
7. [响应类型](#响应类型)
8. [RFQ 类型](#rfq-类型)
9. [奖励类型](#奖励类型)
10. [Zig 实现](#zig-实现)

---

## 枚举类型

### OrderType - 订单类型

```zig
pub const OrderType = enum {
    /// Good Till Cancelled - 直到取消
    GTC,
    /// Good Till Date - 直到指定日期
    GTD,
    /// Fill Or Kill - 全部成交或取消
    FOK,
    /// Fill And Kill - 部分成交，剩余取消
    FAK,
    
    pub fn toString(self: OrderType) []const u8 {
        return switch (self) {
            .GTC => "GTC",
            .GTD => "GTD",
            .FOK => "FOK",
            .FAK => "FAK",
        };
    }
};
```

### Side - 交易方向

```zig
pub const Side = enum {
    BUY,
    SELL,
    
    pub fn toString(self: Side) []const u8 {
        return switch (self) {
            .BUY => "BUY",
            .SELL => "SELL",
        };
    }
};
```

### AssetType - 资产类型

```zig
pub const AssetType = enum {
    /// USDC 抵押品
    COLLATERAL,
    /// 条件代币
    CONDITIONAL,
};
```

### SignatureType - 签名类型

```zig
pub const SignatureType = enum(u8) {
    /// 标准 EOA (MetaMask, 硬件钱包)
    EOA = 0,
    /// Email/Magic 钱包
    POLY_PROXY = 1,
    /// 浏览器钱包代理
    POLY_GNOSIS_SAFE = 2,
};
```

### TickSize - 价格精度

```zig
pub const TickSize = enum {
    @"0.1",
    @"0.01",
    @"0.001",
    @"0.0001",
    
    pub fn toFloat(self: TickSize) f64 {
        return switch (self) {
            .@"0.1" => 0.1,
            .@"0.01" => 0.01,
            .@"0.001" => 0.001,
            .@"0.0001" => 0.0001,
        };
    }
};
```

---

## API 凭证

### ApiCreds

```zig
/// API 凭证
pub const ApiCreds = struct {
    /// API Key
    api_key: []const u8,
    /// API Secret (用于 HMAC 签名)
    api_secret: Secret([]const u8),
    /// API Passphrase
    api_passphrase: Secret([]const u8),
};
```

### ReadonlyApiKeyResponse

```zig
/// 只读 API Key 响应
pub const ReadonlyApiKeyResponse = struct {
    api_key: []const u8,
};
```

### BuilderApiKey

```zig
/// Builder API Key
pub const BuilderApiKey = struct {
    key: []const u8,
    secret: Secret([]const u8),
    passphrase: Secret([]const u8),
};
```

---

## 订单类型

### OrderArgs - 限价单参数

```zig
/// 限价单参数
pub const OrderArgs = struct {
    /// Conditional token ID
    token_id: []const u8,
    
    /// 价格 (0 < price < 1)
    price: Decimal,
    
    /// 数量（以 token 计）
    size: Decimal,
    
    /// 买/卖方向
    side: Side,
    
    /// 费率（基点），默认 0
    fee_rate_bps: u16 = 0,
    
    /// 用于链上取消的 nonce
    nonce: u64 = 0,
    
    /// 过期时间戳（0 = 永不过期）
    expiration: u64 = 0,
    
    /// 指定接单地址（零地址 = 公开订单）
    taker: ?[42]u8 = null,
};
```

### MarketOrderArgs - 市价单参数

```zig
/// 市价单参数
pub const MarketOrderArgs = struct {
    /// Conditional token ID
    token_id: []const u8,
    
    /// 金额
    /// - BUY: 美元金额
    /// - SELL: token 数量
    amount: Decimal,
    
    /// 买/卖方向
    side: Side,
    
    /// 价格（不提供则自动计算）
    price: ?Decimal = null,
    
    /// 费率（基点）
    fee_rate_bps: u16 = 0,
    
    /// 用于链上取消的 nonce
    nonce: u64 = 0,
    
    /// 指定接单地址
    taker: ?[42]u8 = null,
    
    /// 订单类型 (FOK 或 FAK)
    order_type: OrderType = .FOK,
};
```

### SignedOrder - 已签名订单

```zig
/// 已签名订单
pub const SignedOrder = struct {
    /// 随机盐值
    salt: u256,
    /// 订单创建者地址
    maker: [42]u8,
    /// 签名者地址
    signer: [42]u8,
    /// 接单者地址
    taker: [42]u8,
    /// Token ID
    token_id: []const u8,
    /// Maker 金额
    maker_amount: u256,
    /// Taker 金额
    taker_amount: u256,
    /// 过期时间
    expiration: u64,
    /// Nonce
    nonce: u64,
    /// 费率（基点）
    fee_rate_bps: u16,
    /// 交易方向
    side: Side,
    /// 签名类型
    signature_type: SignatureType,
    /// 签名
    signature: [132]u8,
};
```

### CreateOrderOptions

```zig
/// 创建订单选项
pub const CreateOrderOptions = struct {
    /// 价格精度
    tick_size: TickSize,
    /// 是否为 neg risk 市场
    neg_risk: bool = false,
};
```

---

## 订单簿类型

### OrderBookSummary

```zig
/// 订单簿摘要
pub const OrderBookSummary = struct {
    /// 市场 condition ID
    market: []const u8,
    /// Token ID
    asset_id: []const u8,
    /// 时间戳
    timestamp: []const u8,
    /// 买单列表
    bids: []OrderSummary,
    /// 卖单列表
    asks: []OrderSummary,
    /// 最小订单大小
    min_order_size: Decimal,
    /// 价格精度
    tick_size: TickSize,
    /// 是否为 neg risk 市场
    neg_risk: bool,
    /// 订单簿哈希
    hash: []const u8,
};
```

### OrderSummary

```zig
/// 订单摘要（价格层级）
pub const OrderSummary = struct {
    /// 价格
    price: Decimal,
    /// 该价格的总数量
    size: Decimal,
};
```

---

## 交易类型

### Trade

```zig
/// 交易记录
pub const Trade = struct {
    /// 交易 ID
    id: []const u8,
    /// Taker 订单 ID
    taker_order_id: []const u8,
    /// 市场
    market: []const u8,
    /// Token ID
    asset_id: []const u8,
    /// 交易方向
    side: Side,
    /// 成交数量
    size: Decimal,
    /// 费率（基点）
    fee_rate_bps: u16,
    /// 成交价格
    price: Decimal,
    /// 状态
    status: []const u8,
    /// 匹配时间
    match_time: []const u8,
    /// 最后更新时间
    last_update: []const u8,
    /// 结果
    outcome: []const u8,
    /// Bucket 索引
    bucket_index: u32,
    /// 所有者地址
    owner: []const u8,
    /// Maker 地址
    maker_address: []const u8,
    /// Maker 订单列表
    maker_orders: []MakerOrder,
    /// 交易哈希
    transaction_hash: []const u8,
    /// 交易者角色
    trader_side: TraderSide,
};

pub const TraderSide = enum {
    TAKER,
    MAKER,
};
```

### MakerOrder

```zig
/// Maker 订单信息
pub const MakerOrder = struct {
    order_id: []const u8,
    owner: []const u8,
    maker_address: []const u8,
    matched_amount: Decimal,
    price: Decimal,
    fee_rate_bps: u16,
    asset_id: []const u8,
    outcome: []const u8,
    side: Side,
};
```

### OpenOrder

```zig
/// 开放订单
pub const OpenOrder = struct {
    id: []const u8,
    status: []const u8,
    owner: []const u8,
    maker_address: []const u8,
    market: []const u8,
    asset_id: []const u8,
    side: Side,
    original_size: Decimal,
    size_matched: Decimal,
    price: Decimal,
    associate_trades: [][]const u8,
    outcome: []const u8,
    created_at: u64,
    expiration: u64,
    order_type: OrderType,
};
```

---

## 查询参数

### TradeParams

```zig
/// 交易查询参数
pub const TradeParams = struct {
    id: ?[]const u8 = null,
    maker_address: ?[]const u8 = null,
    market: ?[]const u8 = null,
    asset_id: ?[]const u8 = null,
    before: ?[]const u8 = null,
    after: ?[]const u8 = null,
};
```

### OpenOrderParams

```zig
/// 订单查询参数
pub const OpenOrderParams = struct {
    id: ?[]const u8 = null,
    market: ?[]const u8 = null,
    asset_id: ?[]const u8 = null,
};
```

### BookParams

```zig
/// 订单簿查询参数
pub const BookParams = struct {
    token_id: []const u8,
    side: ?Side = null,
};
```

### BalanceAllowanceParams

```zig
/// 余额查询参数
pub const BalanceAllowanceParams = struct {
    asset_type: AssetType,
    token_id: ?[]const u8 = null,
    signature_type: ?SignatureType = null,
};
```

### OrderScoringParams

```zig
/// 订单评分查询参数
pub const OrderScoringParams = struct {
    order_id: []const u8,
};

pub const OrdersScoringParams = struct {
    order_ids: [][]const u8,
};
```

### DropNotificationParams

```zig
/// 删除通知参数
pub const DropNotificationParams = struct {
    ids: [][]const u8,
};
```

### PriceHistoryFilterParams

```zig
/// 价格历史查询参数
pub const PriceHistoryFilterParams = struct {
    market: ?[]const u8 = null,
    start_ts: ?u64 = null,
    end_ts: ?u64 = null,
    fidelity: ?u32 = null,
    interval: ?PriceHistoryInterval = null,
};

pub const PriceHistoryInterval = enum {
    max,
    @"1w",
    @"1d",
    @"6h",
    @"1h",
};
```

---

## 响应类型

### BalanceAllowanceResponse

```zig
/// 余额响应
pub const BalanceAllowanceResponse = struct {
    balance: Decimal,
    allowance: Decimal,
};
```

### OrderScoring

```zig
/// 订单评分响应
pub const OrderScoring = struct {
    scoring: bool,
};

/// 批量订单评分响应
pub const OrdersScoring = std.StringHashMap(bool);
```

### Notification

```zig
/// 通知
pub const Notification = struct {
    type: u32,
    owner: []const u8,
    payload: []const u8,  // JSON
};
```

### PaginationPayload

```zig
/// 分页响应
pub fn PaginationPayload(comptime T: type) type {
    return struct {
        limit: u32,
        count: u32,
        next_cursor: []const u8,
        data: []T,
    };
}
```

### MarketPrice

```zig
/// 市场价格（价格历史）
pub const MarketPrice = struct {
    /// 时间戳
    t: u64,
    /// 价格
    p: Decimal,
};
```

### MarketTradeEvent

```zig
/// 市场交易事件
pub const MarketTradeEvent = struct {
    event_type: []const u8,
    market: struct {
        condition_id: []const u8,
        asset_id: []const u8,
        question: []const u8,
        icon: []const u8,
        slug: []const u8,
    },
    user: struct {
        address: []const u8,
        username: []const u8,
        profile_picture: []const u8,
        optimized_profile_picture: []const u8,
        pseudonym: []const u8,
    },
    side: Side,
    size: Decimal,
    fee_rate_bps: u16,
    price: Decimal,
    outcome: []const u8,
    outcome_index: u32,
    transaction_hash: []const u8,
    timestamp: []const u8,
};
```

---

## RFQ 类型

### RfqMatchType

```zig
/// RFQ 匹配类型
pub const RfqMatchType = enum {
    /// BUY <> SELL, SELL <> BUY
    COMPLEMENTARY,
    /// BUY <> BUY, SELL <> SELL (合并)
    MERGE,
    /// BUY <> BUY, SELL <> SELL (铸造)
    MINT,
};
```

### RfqRequest

```zig
/// RFQ 请求
pub const RfqRequest = struct {
    request_id: []const u8,
    user_address: []const u8,
    proxy_address: []const u8,
    token: []const u8,
    complement: []const u8,
    condition: []const u8,
    side: Side,
    size_in: Decimal,
    size_out: Decimal,
    price: Decimal,
    accepted_quote_id: []const u8,
    state: []const u8,
    expiry: u64,
    created_at: u64,
    updated_at: u64,
};
```

### RfqQuote

```zig
/// RFQ 报价
pub const RfqQuote = struct {
    quote_id: []const u8,
    request_id: []const u8,
    user_address: []const u8,
    proxy_address: []const u8,
    token: []const u8,
    complement: []const u8,
    condition: []const u8,
    side: Side,
    size_in: Decimal,
    size_out: Decimal,
    price: Decimal,
    state: []const u8,
    match_type: RfqMatchType,
    expiry: u64,
    created_at: u64,
    updated_at: u64,
};
```

### CreateRfqRequestParams

```zig
/// 创建 RFQ 请求参数
pub const CreateRfqRequestParams = struct {
    asset_in: []const u8,
    asset_out: []const u8,
    amount_in: Decimal,
    amount_out: Decimal,
    user_type: SignatureType,
};
```

### AcceptQuoteParams

```zig
/// 接受报价参数
pub const AcceptQuoteParams = struct {
    request_id: []const u8,
    quote_id: []const u8,
    expiration: u64,
};
```

---

## 奖励类型

### UserEarning

```zig
/// 用户收益
pub const UserEarning = struct {
    date: []const u8,
    condition_id: []const u8,
    asset_address: []const u8,
    maker_address: []const u8,
    earnings: Decimal,
    asset_rate: Decimal,
};
```

### MarketReward

```zig
/// 市场奖励
pub const MarketReward = struct {
    condition_id: []const u8,
    question: []const u8,
    market_slug: []const u8,
    event_slug: []const u8,
    image: []const u8,
    rewards_max_spread: Decimal,
    rewards_min_size: Decimal,
    tokens: []Token,
    rewards_config: []RewardsConfig,
};

pub const Token = struct {
    token_id: []const u8,
    outcome: []const u8,
    price: Decimal,
};

pub const RewardsConfig = struct {
    asset_address: []const u8,
    start_date: []const u8,
    end_date: []const u8,
    rate_per_day: Decimal,
    total_rewards: Decimal,
};
```

---

## Zig 实现

### 常量

```zig
/// 零地址（用于公开订单）
pub const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

/// 初始游标（分页）
pub const INITIAL_CURSOR = "MA==";

/// 结束游标（分页）
pub const END_CURSOR = "LTE=";

/// USDC 精度
pub const COLLATERAL_TOKEN_DECIMALS: u8 = 6;
```

### 文件结构

```
src/types/
├── mod.zig           # ✅ 模块导出
├── decimal.zig       # ✅ 已实现
├── secret.zig        # ✅ 已实现
├── address.zig       # ✅ 已实现
└── uuid.zig          # ✅ 已实现

# 订单相关类型在 clob/types/ 中实现
src/clob/types/
├── mod.zig           # ✅ 模块导出
├── order.zig         # ✅ 订单类型
├── book.zig          # ✅ 订单簿类型
├── trade.zig         # ✅ 交易类型
├── market.zig        # ✅ 市场类型
├── account.zig       # ✅ 账户类型 (含 API 凭证)
├── builder.zig       # ✅ Builder 类型
└── common.zig        # ✅ 通用类型

# RFQ 类型在 rfq/types.zig 中实现
src/rfq/
├── mod.zig           # ✅ 模块导出
├── client.zig        # ✅ RFQ 客户端
└── types.zig         # ✅ RFQ 类型

# 注: contracts.zig (合约配置) 推迟到 v0.4
```

---

## 更新日志

| 日期 | 变更 |
|------|------|
| 2024-12-31 | 初始版本，从官方仓库提取类型定义 |
| 2024-12-31 | 更新文件结构图，反映 v0.3 完成后的实际状态 |
