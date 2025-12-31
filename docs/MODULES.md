# 模块设计文档

本文档详细描述 Polymarket Zig CLOB Client SDK 各模块的设计和实现细节。

## 目录

- [1. 模块概览](#1-模块概览)
- [2. Root 模块](#2-root-模块)
- [3. CLOB 模块](#3-clob-模块)
- [4. Auth 模块](#4-auth-模块)
- [5. Crypto 模块](#5-crypto-模块)
- [6. Types 模块](#6-types-模块)
- [7. Error 模块](#7-error-模块)
- [8. 可选模块](#8-可选模块)

---

## 1. 模块概览

### 1.1 目录结构

```
src/
├── root.zig                 # 库入口，公开 API
├── clob/                    # CLOB 客户端核心模块
│   ├── mod.zig             # 模块入口
│   ├── client.zig          # Client 实现
│   ├── order_builder.zig   # 订单构建器
│   ├── types/              # CLOB 类型定义
│   │   ├── mod.zig
│   │   ├── request.zig     # 请求类型
│   │   └── response.zig    # 响应类型
│   └── ws/                 # WebSocket 支持（可选）
│       ├── mod.zig
│       ├── client.zig
│       └── messages.zig
├── auth/                   # 认证模块
│   ├── mod.zig
│   ├── l1.zig              # L1 认证
│   ├── l2.zig              # L2 认证
│   ├── builder.zig         # Builder 认证
│   └── credentials.zig     # 凭证管理
├── crypto/                 # 加密模块
│   ├── mod.zig
│   ├── signer.zig          # 签名器接口
│   ├── local_signer.zig    # 本地签名器
│   ├── eip712.zig          # EIP-712 支持
│   ├── hmac.zig            # HMAC 签名
│   └── secp256k1.zig       # secp256k1 曲线
├── types/                  # 公共类型
│   ├── mod.zig
│   ├── decimal.zig         # 高精度十进制
│   ├── address.zig         # 以太坊地址
│   └── uuid.zig            # UUID
├── http/                   # HTTP 客户端封装
│   ├── mod.zig
│   ├── client.zig
│   └── request.zig
├── error.zig               # 错误定义
├── constants.zig           # 常量定义
└── utils.zig               # 工具函数
```

### 1.2 模块依赖图

```
                         root.zig
                            │
           ┌────────────────┼────────────────┐
           │                │                │
           ▼                ▼                ▼
       ┌──────┐        ┌──────┐        ┌──────┐
       │ clob │        │ auth │        │crypto│
       └──┬───┘        └──┬───┘        └──┬───┘
          │               │               │
          │   ┌───────────┴───────────┐   │
          │   │                       │   │
          │   ▼                       ▼   │
          │ ┌────┐               ┌────┐   │
          │ │ l1 │               │ l2 │   │
          │ └────┘               └────┘   │
          │                               │
          └───────────┬───────────────────┘
                      │
                      ▼
                 ┌─────────┐
                 │  types  │
                 └────┬────┘
                      │
                      ▼
                 ┌─────────┐
                 │  error  │
                 └─────────┘
```

---

## 2. Root 模块

### 2.1 职责

- 作为库的唯一公共入口点
- 重新导出所有公共 API
- 提供版本信息

### 2.2 实现

```zig
// src/root.zig

//! Polymarket Zig CLOB Client SDK
//!
//! 一个高性能、类型安全的 Polymarket CLOB API 客户端。
//!
//! ## 快速开始
//!
//! ```zig
//! const poly = @import("poly_sdk");
//!
//! var client = try poly.Client.init(allocator, .{});
//! defer client.deinit();
//!
//! const ok = try client.ok();
//! ```

const std = @import("std");

// 公共导出
pub const clob = @import("clob/mod.zig");
pub const auth = @import("auth/mod.zig");
pub const crypto = @import("crypto/mod.zig");
pub const types = @import("types/mod.zig");

// 便捷别名
pub const Client = clob.Client;
pub const Config = clob.Config;
pub const OrderBuilder = clob.OrderBuilder;

pub const Signer = crypto.Signer;
pub const LocalSigner = crypto.LocalSigner;

pub const Credentials = auth.Credentials;

pub const Decimal = types.Decimal;
pub const Address = types.Address;
pub const Amount = clob.types.Amount;
pub const Side = clob.types.Side;
pub const OrderType = clob.types.OrderType;

// 常量
pub const POLYGON: u64 = 137;
pub const AMOY: u64 = 80002;
pub const PRIVATE_KEY_VAR = "POLYMARKET_PRIVATE_KEY";

// 版本信息
pub const version = "0.1.0";
pub const version_major = 0;
pub const version_minor = 1;
pub const version_patch = 0;

// 测试
test {
    std.testing.refAllDeclsRecursive(@This());
}
```

---

## 3. CLOB 模块

### 3.1 职责

- 实现 CLOB API 客户端
- 管理客户端状态（未认证/已认证/Builder）
- 提供订单构建器
- 处理 HTTP 请求/响应

### 3.2 子模块

#### 3.2.1 client.zig

```zig
// src/clob/client.zig

const std = @import("std");
const http = @import("../http/mod.zig");
const auth = @import("../auth/mod.zig");
const crypto = @import("../crypto/mod.zig");
const types = @import("types/mod.zig");

/// 客户端状态枚举
pub const ClientState = enum {
    unauthenticated,
    authenticated,
    builder_authenticated,
};

/// 客户端配置
pub const Config = struct {
    host: []const u8 = "https://clob.polymarket.com",
    geoblock_host: []const u8 = "https://polymarket.com",
    use_server_time: bool = false,
    timeout_ms: u32 = 30000,
    max_retries: u8 = 3,
    user_agent: []const u8 = "poly-sdk-zig/0.1.0",
};

/// 泛型客户端类型
pub fn Client(comptime state: ClientState) type {
    return struct {
        const Self = @This();

        // 基础字段
        allocator: std.mem.Allocator,
        config: Config,
        http_client: http.Client,

        // 缓存
        tick_size_cache: std.StringHashMap(types.TickSize),
        neg_risk_cache: std.StringHashMap(bool),
        fee_rate_cache: std.StringHashMap(u32),

        // 认证状态字段（条件编译）
        credentials: if (state != .unauthenticated) auth.Credentials else void = 
            if (state != .unauthenticated) undefined else {},
        address: if (state != .unauthenticated) types.Address else void = 
            if (state != .unauthenticated) undefined else {},
        signature_type: if (state != .unauthenticated) types.SignatureType else void = 
            if (state != .unauthenticated) undefined else {},
        funder: if (state != .unauthenticated) ?types.Address else void = 
            if (state != .unauthenticated) null else {},

        // Builder 状态字段
        builder_config: if (state == .builder_authenticated) auth.BuilderConfig else void = 
            if (state == .builder_authenticated) undefined else {},

        /// 初始化客户端
        pub fn init(allocator: std.mem.Allocator, config: Config) !Self {
            var self = Self{
                .allocator = allocator,
                .config = config,
                .http_client = try http.Client.init(allocator, .{
                    .timeout_ms = config.timeout_ms,
                }),
                .tick_size_cache = std.StringHashMap(types.TickSize).init(allocator),
                .neg_risk_cache = std.StringHashMap(bool).init(allocator),
                .fee_rate_cache = std.StringHashMap(u32).init(allocator),
            };
            return self;
        }

        /// 释放资源
        pub fn deinit(self: *Self) void {
            self.tick_size_cache.deinit();
            self.neg_risk_cache.deinit();
            self.fee_rate_cache.deinit();
            self.http_client.deinit();
        }

        /// 清除内部缓存
        pub fn invalidateCaches(self: *Self) void {
            self.tick_size_cache.clearRetainingCapacity();
            self.neg_risk_cache.clearRetainingCapacity();
            self.fee_rate_cache.clearRetainingCapacity();
        }

        // === 公共方法（所有状态可用）===

        pub fn ok(self: *Self) ![]const u8 {
            return self.get("/", .{});
        }

        pub fn serverTime(self: *Self) !i64 {
            const response = try self.get("/time", .{});
            return response;
        }

        pub fn midpoint(self: *Self, request: types.MidpointRequest) !types.MidpointResponse {
            const path = try std.fmt.allocPrint(
                self.allocator, 
                "/midpoint?token_id={s}", 
                .{request.token_id}
            );
            defer self.allocator.free(path);
            return self.get(path, types.MidpointResponse);
        }

        // ... 其他公共方法

        // === 认证方法（仅未认证状态）===
        pub usingnamespace if (state == .unauthenticated) struct {
            pub fn authenticate(
                self: *Self,
                signer: anytype,
                options: AuthenticateOptions,
            ) !Client(.authenticated) {
                // 验证链 ID
                const chain_id = signer.chainId() orelse 
                    return error.ChainIdNotSet;
                
                if (chain_id != @import("../constants.zig").POLYGON and 
                    chain_id != @import("../constants.zig").AMOY) {
                    return error.UnsupportedChain;
                }

                // 验证 funder 和 signature_type 的组合
                if (options.funder != null and options.signature_type == .eoa) {
                    return error.InvalidFunderWithEoa;
                }
                if (options.funder == null and 
                    (options.signature_type == .proxy or options.signature_type == .gnosis_safe)) {
                    return error.MissingFunderForProxy;
                }

                // 获取或创建凭证
                const credentials = options.credentials orelse 
                    try self.createOrDeriveApiKey(signer, options.nonce);

                // 创建认证后的客户端
                var auth_client = Client(.authenticated){
                    .allocator = self.allocator,
                    .config = self.config,
                    .http_client = self.http_client,
                    .tick_size_cache = self.tick_size_cache,
                    .neg_risk_cache = self.neg_risk_cache,
                    .fee_rate_cache = self.fee_rate_cache,
                    .credentials = credentials,
                    .address = signer.address(),
                    .signature_type = options.signature_type,
                    .funder = options.funder,
                };

                return auth_client;
            }

            pub fn createApiKey(self: *Self, signer: anytype, nonce: ?u32) !auth.Credentials {
                const headers = try auth.l1.createHeaders(
                    self.allocator, 
                    signer, 
                    signer.chainId().?, 
                    std.time.timestamp(),
                    nonce
                );
                defer headers.deinit(self.allocator);

                return self.postWithHeaders("/auth/api-key", headers, auth.Credentials);
            }

            pub fn deriveApiKey(self: *Self, signer: anytype, nonce: ?u32) !auth.Credentials {
                const headers = try auth.l1.createHeaders(
                    self.allocator,
                    signer,
                    signer.chainId().?,
                    std.time.timestamp(),
                    nonce
                );
                defer headers.deinit(self.allocator);

                return self.getWithHeaders("/auth/derive-api-key", headers, auth.Credentials);
            }

            pub fn createOrDeriveApiKey(self: *Self, signer: anytype, nonce: ?u32) !auth.Credentials {
                return self.createApiKey(signer, nonce) catch 
                    self.deriveApiKey(signer, nonce);
            }
        } else struct {};

        // === 认证后方法 ===
        pub usingnamespace if (state == .authenticated or state == .builder_authenticated) struct {
            pub fn apiKeys(self: *Self) !types.ApiKeysResponse {
                return self.authenticatedGet("/auth/api-keys", types.ApiKeysResponse);
            }

            pub fn limitOrder(self: *Self) OrderBuilder(.limit, state) {
                return OrderBuilder(.limit, state).init(self);
            }

            pub fn marketOrder(self: *Self) OrderBuilder(.market, state) {
                return OrderBuilder(.market, state).init(self);
            }

            pub fn sign(self: *Self, signer: anytype, order: types.SignableOrder) !types.SignedOrder {
                const token_id = std.fmt.allocPrint(
                    self.allocator, 
                    "{d}", 
                    .{order.order.token_id}
                ) catch return error.OutOfMemory;
                defer self.allocator.free(token_id);

                const neg_risk = (try self.negRisk(token_id)).neg_risk;
                const chain_id = signer.chainId() orelse return error.ChainIdNotSet;

                const contract_config = @import("../constants.zig").contractConfig(chain_id, neg_risk) 
                    orelse return error.MissingContractConfig;

                const domain = crypto.Eip712Domain{
                    .name = "Polymarket CTF Exchange",
                    .version = "1",
                    .chain_id = chain_id,
                    .verifying_contract = contract_config.exchange,
                };

                const hash = order.order.eip712SigningHash(domain);
                const signature = try signer.signHash(hash);

                return types.SignedOrder{
                    .order = order.order,
                    .signature = signature,
                    .order_type = order.order_type,
                    .owner = self.credentials.key,
                };
            }

            pub fn postOrder(self: *Self, order: types.SignedOrder) ![]types.PostOrderResponse {
                return self.postOrders(&[_]types.SignedOrder{order});
            }

            pub fn postOrders(self: *Self, orders: []const types.SignedOrder) ![]types.PostOrderResponse {
                return self.authenticatedPost("/orders", orders, []types.PostOrderResponse);
            }

            pub fn cancelOrder(self: *Self, order_id: []const u8) !types.CancelOrdersResponse {
                const body = .{ .orderId = order_id };
                return self.authenticatedDelete("/order", body, types.CancelOrdersResponse);
            }

            pub fn cancelAllOrders(self: *Self) !types.CancelOrdersResponse {
                return self.authenticatedDelete("/cancel-all", null, types.CancelOrdersResponse);
            }

            // ... 其他认证后方法

            fn authenticatedGet(self: *Self, path: []const u8, comptime T: type) !T {
                const timestamp = if (self.config.use_server_time) 
                    try self.serverTime() 
                else 
                    std.time.timestamp();

                const headers = try auth.l2.createHeaders(
                    self.allocator,
                    self.credentials,
                    self.address,
                    .{ .method = "GET", .path = path, .body = null },
                    timestamp
                );
                defer headers.deinit(self.allocator);

                return self.getWithHeaders(path, headers, T);
            }

            fn authenticatedPost(self: *Self, path: []const u8, body: anytype, comptime T: type) !T {
                const timestamp = if (self.config.use_server_time)
                    try self.serverTime()
                else
                    std.time.timestamp();

                const json_body = try std.json.stringifyAlloc(self.allocator, body, .{});
                defer self.allocator.free(json_body);

                const headers = try auth.l2.createHeaders(
                    self.allocator,
                    self.credentials,
                    self.address,
                    .{ .method = "POST", .path = path, .body = json_body },
                    timestamp
                );
                defer headers.deinit(self.allocator);

                return self.postWithHeaders(path, headers, body, T);
            }
        } else struct {};

        // === Builder 专用方法 ===
        pub usingnamespace if (state == .builder_authenticated) struct {
            pub fn builderTrades(
                self: *Self,
                request: types.TradesRequest,
                next_cursor: ?[]const u8,
            ) !types.Page(types.BuilderTradeResponse) {
                const path = try buildPath(self.allocator, "/builder/trades", request, next_cursor);
                defer self.allocator.free(path);
                return self.builderAuthenticatedGet(path, types.Page(types.BuilderTradeResponse));
            }

            fn builderAuthenticatedGet(self: *Self, path: []const u8, comptime T: type) !T {
                const timestamp = if (self.config.use_server_time)
                    try self.serverTime()
                else
                    std.time.timestamp();

                // L2 headers
                const l2_headers = try auth.l2.createHeaders(
                    self.allocator,
                    self.credentials,
                    self.address,
                    .{ .method = "GET", .path = path, .body = null },
                    timestamp
                );
                defer l2_headers.deinit(self.allocator);

                // Builder headers
                const builder_headers = try auth.builder.createHeaders(
                    self.allocator,
                    self.builder_config,
                    .{ .method = "GET", .path = path, .body = null },
                    timestamp
                );
                defer builder_headers.deinit(self.allocator);

                // 合并 headers
                const merged = try mergeHeaders(self.allocator, l2_headers, builder_headers);
                defer merged.deinit(self.allocator);

                return self.getWithHeaders(path, merged, T);
            }
        } else struct {};

        // === 内部辅助方法 ===

        fn get(self: *Self, path: []const u8, comptime T: type) !T {
            const url = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ self.config.host, path });
            defer self.allocator.free(url);

            const response = try self.http_client.get(url);
            defer response.deinit();

            return std.json.parseFromSlice(T, self.allocator, response.body, .{});
        }

        fn getWithHeaders(self: *Self, path: []const u8, headers: anytype, comptime T: type) !T {
            const url = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ self.config.host, path });
            defer self.allocator.free(url);

            const response = try self.http_client.getWithHeaders(url, headers);
            defer response.deinit();

            return std.json.parseFromSlice(T, self.allocator, response.body, .{});
        }
    };
}

/// 认证选项
pub const AuthenticateOptions = struct {
    credentials: ?auth.Credentials = null,
    nonce: ?u32 = null,
    funder: ?types.Address = null,
    signature_type: types.SignatureType = .eoa,
};
```

#### 3.2.2 order_builder.zig

```zig
// src/clob/order_builder.zig

const std = @import("std");
const types = @import("types/mod.zig");
const crypto = @import("../crypto/mod.zig");
const Client = @import("client.zig").Client;
const ClientState = @import("client.zig").ClientState;

pub const OrderKind = enum {
    limit,
    market,
};

pub const USDC_DECIMALS: u32 = 6;
pub const LOT_SIZE_SCALE: u32 = 2;

/// 订单构建器
pub fn OrderBuilder(comptime kind: OrderKind, comptime state: ClientState) type {
    return struct {
        const Self = @This();

        client: *Client(state),
        token_id: ?[]const u8 = null,
        price: ?types.Decimal = null,
        size: ?types.Decimal = null,
        amount: ?types.Amount = null,
        side: ?types.Side = null,
        nonce: ?u64 = null,
        expiration: ?i64 = null,
        taker: ?types.Address = null,
        order_type: ?types.OrderType = null,

        pub fn init(client: *Client(state)) Self {
            return Self{ .client = client };
        }

        // 通用设置方法
        pub fn tokenId(self: Self, id: []const u8) Self {
            var new = self;
            new.token_id = id;
            return new;
        }

        pub fn side(self: Self, s: types.Side) Self {
            var new = self;
            new.side = s;
            return new;
        }

        pub fn nonce(self: Self, n: u64) Self {
            var new = self;
            new.nonce = n;
            return new;
        }

        pub fn expiration(self: Self, exp: i64) Self {
            var new = self;
            new.expiration = exp;
            return new;
        }

        pub fn taker(self: Self, addr: types.Address) Self {
            var new = self;
            new.taker = addr;
            return new;
        }

        pub fn orderType(self: Self, ot: types.OrderType) Self {
            var new = self;
            new.order_type = ot;
            return new;
        }

        // 限价单专用方法
        pub usingnamespace if (kind == .limit) struct {
            pub fn price(self: Self, p: types.Decimal) Self {
                var new = self;
                new.price = p;
                return new;
            }

            pub fn size(self: Self, s: types.Decimal) Self {
                var new = self;
                new.size = s;
                return new;
            }
        } else struct {};

        // 市价单专用方法
        pub usingnamespace if (kind == .market) struct {
            pub fn amount(self: Self, a: types.Amount) Self {
                var new = self;
                new.amount = a;
                return new;
            }
        } else struct {};

        /// 构建订单
        pub fn build(self: Self) !types.SignableOrder {
            // 验证必填字段
            const token_id = self.token_id orelse return error.MissingTokenId;
            const side_val = self.side orelse return error.MissingSide;

            // 获取市场信息
            const tick_size_resp = try self.client.tickSize(token_id);
            const fee_rate_resp = try self.client.feeRateBps(token_id);
            const minimum_tick_size = tick_size_resp.minimum_tick_size.asDecimal();

            if (kind == .limit) {
                return self.buildLimitOrder(
                    token_id, 
                    side_val, 
                    minimum_tick_size, 
                    fee_rate_resp.base_fee
                );
            } else {
                return self.buildMarketOrder(
                    token_id, 
                    side_val, 
                    minimum_tick_size, 
                    fee_rate_resp.base_fee
                );
            }
        }

        fn buildLimitOrder(
            self: Self,
            token_id: []const u8,
            side_val: types.Side,
            minimum_tick_size: types.Decimal,
            fee_rate: u32,
        ) !types.SignableOrder {
            const price_val = self.price orelse return error.MissingPrice;
            const size_val = self.size orelse return error.MissingSize;

            // 验证价格
            if (price_val.isNegative()) {
                return error.InvalidPrice;
            }
            if (price_val.scale() > minimum_tick_size.scale()) {
                return error.InvalidTickSize;
            }
            if (price_val.lessThan(minimum_tick_size) or 
                price_val.greaterThan(types.Decimal.ONE.sub(minimum_tick_size))) {
                return error.InvalidPrice;
            }

            // 验证数量
            if (size_val.scale() > LOT_SIZE_SCALE) {
                return error.InvalidSize;
            }
            if (size_val.isZero() or size_val.isNegative()) {
                return error.InvalidSize;
            }

            // 计算 maker/taker amounts
            const decimals = minimum_tick_size.scale();
            const taker_amount, const maker_amount = switch (side_val) {
                .buy => .{
                    size_val,
                    size_val.mul(price_val).truncWithScale(decimals + LOT_SIZE_SCALE),
                },
                .sell => .{
                    size_val.mul(price_val).truncWithScale(decimals + LOT_SIZE_SCALE),
                    size_val,
                },
                else => return error.InvalidSide,
            };

            const salt = generateSalt();
            const order_type = self.order_type orelse .gtc;

            // 验证 expiration
            if (order_type != .gtd and self.expiration != null and self.expiration.? > 0) {
                return error.ExpirationOnlyForGtd;
            }

            const order = types.Order{
                .salt = salt,
                .maker = self.client.funder orelse self.client.address,
                .signer = self.client.address,
                .taker = self.taker orelse types.Address.zero(),
                .token_id = try std.fmt.parseInt(u256, token_id, 10),
                .maker_amount = toFixedU128(maker_amount),
                .taker_amount = toFixedU128(taker_amount),
                .expiration = @intCast(self.expiration orelse 0),
                .nonce = self.nonce orelse 0,
                .fee_rate_bps = fee_rate,
                .side = @intFromEnum(side_val),
                .signature_type = @intFromEnum(self.client.signature_type),
            };

            return types.SignableOrder{
                .order = order,
                .order_type = order_type,
            };
        }

        fn buildMarketOrder(
            self: Self,
            token_id: []const u8,
            side_val: types.Side,
            minimum_tick_size: types.Decimal,
            fee_rate: u32,
        ) !types.SignableOrder {
            const amount_val = self.amount orelse return error.MissingAmount;
            const order_type = self.order_type orelse .fak;

            // 市价单只允许 FAK/FOK
            if (order_type != .fak and order_type != .fok) {
                return error.InvalidOrderTypeForMarket;
            }

            // 获取价格
            const price_val = self.price orelse 
                try self.calculateMarketPrice(token_id, side_val, amount_val, order_type);

            // 验证卖单必须用 shares
            if (side_val == .sell and amount_val.isUsdc()) {
                return error.SellOrderMustUseShares;
            }

            // 计算 amounts
            const decimals = minimum_tick_size.scale();
            const raw_amount = amount_val.asInner();

            const taker_amount, const maker_amount = switch (side_val) {
                .buy => if (amount_val.isUsdc()) .{
                    raw_amount.div(price_val).truncWithScale(decimals + LOT_SIZE_SCALE),
                    raw_amount,
                } else .{
                    raw_amount,
                    raw_amount.mul(price_val).truncWithScale(decimals + LOT_SIZE_SCALE),
                },
                .sell => .{
                    raw_amount.mul(price_val).truncWithScale(decimals + LOT_SIZE_SCALE),
                    raw_amount,
                },
                else => return error.InvalidSide,
            };

            const salt = generateSalt();

            const order = types.Order{
                .salt = salt,
                .maker = self.client.funder orelse self.client.address,
                .signer = self.client.address,
                .taker = self.taker orelse types.Address.zero(),
                .token_id = try std.fmt.parseInt(u256, token_id, 10),
                .maker_amount = toFixedU128(maker_amount),
                .taker_amount = toFixedU128(taker_amount),
                .expiration = 0,
                .nonce = self.nonce orelse 0,
                .fee_rate_bps = fee_rate,
                .side = @intFromEnum(side_val),
                .signature_type = @intFromEnum(self.client.signature_type),
            };

            return types.SignableOrder{
                .order = order,
                .order_type = order_type,
            };
        }

        fn calculateMarketPrice(
            self: Self,
            token_id: []const u8,
            side_val: types.Side,
            amount_val: types.Amount,
            order_type: types.OrderType,
        ) !types.Decimal {
            const book = try self.client.orderBook(.{ .token_id = token_id });

            const levels = switch (side_val) {
                .buy => book.asks,
                .sell => book.bids,
                else => return error.InvalidSide,
            };

            if (levels.len == 0) {
                return error.NoMarketPrice;
            }

            // 查找截止价格
            var sum = types.Decimal.ZERO;
            for (levels) |level| {
                sum = sum.add(if (amount_val.isUsdc())
                    level.size.mul(level.price)
                else
                    level.size);

                if (sum.greaterThanOrEqual(amount_val.asInner())) {
                    return level.price;
                }
            }

            if (order_type == .fok) {
                return error.InsufficientLiquidity;
            }

            return levels[0].price;
        }
    };
}

fn generateSalt() u64 {
    const now = std.time.timestamp();
    var rng = std.Random.DefaultPrng.init(@intCast(now));
    const rand = rng.random().float(f64);
    return @intFromFloat(@as(f64, @floatFromInt(now)) * rand);
}

fn toFixedU128(d: types.Decimal) u128 {
    return d.normalize().truncWithScale(USDC_DECIMALS).mantissa();
}
```

---

## 4. Auth 模块

### 4.1 职责

- 实现 L1/L2 认证流程
- 管理 API 凭证
- 生成认证头
- Builder 认证支持

### 4.2 子模块

详细设计参见 [AUTHENTICATION.md](./AUTHENTICATION.md)。

---

## 5. Crypto 模块

### 5.1 职责

- 提供签名器接口
- 实现 EIP-712 签名
- HMAC-SHA256 签名
- secp256k1 椭圆曲线操作

### 5.2 子模块

```zig
// src/crypto/mod.zig

pub const Signer = @import("signer.zig").Signer;
pub const LocalSigner = @import("local_signer.zig").LocalSigner;
pub const Eip712Domain = @import("eip712.zig").Eip712Domain;
pub const Eip712Struct = @import("eip712.zig").Eip712Struct;
pub const hmacSign = @import("hmac.zig").sign;
```

---

## 6. Types 模块

### 6.1 职责

- 定义公共类型
- 高精度十进制数
- 以太坊地址
- UUID

详细设计参见 [TYPES.md](./TYPES.md)。

---

## 7. Error 模块

### 7.1 职责

- 定义所有错误类型
- 提供错误详情

详细设计参见 [ERROR_HANDLING.md](./ERROR_HANDLING.md)。

---

## 8. 可选模块

### 8.1 WebSocket 模块

```zig
// src/clob/ws/mod.zig

pub const WsClient = @import("client.zig").WsClient;
pub const Channel = @import("messages.zig").Channel;
pub const Message = @import("messages.zig").Message;
```

### 8.2 Data API 模块

```zig
// src/data/mod.zig (可选功能)

pub const DataClient = @import("client.zig").DataClient;
```

### 8.3 Gamma API 模块

```zig
// src/gamma/mod.zig (可选功能)

pub const GammaClient = @import("client.zig").GammaClient;
```

### 8.4 Bridge API 模块

```zig
// src/bridge/mod.zig (可选功能)

pub const BridgeClient = @import("client.zig").BridgeClient;
```
