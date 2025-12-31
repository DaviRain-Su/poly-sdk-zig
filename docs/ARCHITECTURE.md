# 架构设计文档

## 1. 概述

本文档描述 Polymarket Zig CLOB Client SDK 的整体架构设计。该 SDK 是 Rust 版本 `rs-clob-client` 的 Zig 语言移植，旨在提供高性能、类型安全的 Polymarket CLOB API 客户端。

### 1.1 设计目标

1. **类型安全**：利用 Zig 的编译时类型系统防止运行时错误
2. **零成本抽象**：热路径中避免动态分发和不必要的内存分配
3. **状态机模式**：编译时强制正确的 API 使用顺序
4. **模块化设计**：清晰的模块边界，便于测试和维护
5. **Zig 惯用设计**：遵循 Zig 语言的最佳实践和惯例

### 1.2 与 Rust 版本的对比

| 方面 | Rust 版本 | Zig 版本 |
|------|-----------|----------|
| 类型状态机 | `PhantomData` + 泛型 | Comptime 类型参数 |
| 异步运行时 | `tokio` | 同步阻塞 / libxev (可选) |
| HTTP 客户端 | `reqwest` | `std.http.Client` |
| JSON 处理 | `serde` | `std.json` |
| 密码学 | `alloy` | 自定义实现 + zig-crypto |
| 错误处理 | `thiserror` | Zig Error Union |

> **注意**: Zig 的 async/await 功能在 0.11 版本后被移除，目前处于重新设计阶段。
> 本 SDK 默认使用同步阻塞 I/O，可选集成 [libxev](https://github.com/Cloudef/libxev) 
> 或 [zig-aio](https://github.com/Cloudef/zig-aio) 实现异步操作。

## 2. 系统架构

### 2.1 整体架构图

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           用户应用程序                                    │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         Public API Layer                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │
│  │   Client    │  │OrderBuilder │  │   Types     │  │   Errors    │    │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘    │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         Core Services Layer                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │
│  │    Auth     │  │   Signer    │  │  HTTP Core  │  │   Cache     │    │
│  │   Module    │  │   Module    │  │   Module    │  │   Module    │    │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘    │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        Infrastructure Layer                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │
│  │ std.http    │  │ std.crypto  │  │  std.json   │  │  std.mem    │    │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         External Services                                │
│  ┌──────────────────────────┐  ┌──────────────────────────┐            │
│  │   Polymarket CLOB API    │  │   Polygon Blockchain     │            │
│  │   https://clob.polymarket.com                          │            │
│  └──────────────────────────┘  └──────────────────────────┘            │
└─────────────────────────────────────────────────────────────────────────┘
```

### 2.2 模块依赖关系

```
                    ┌──────────┐
                    │  root    │
                    └────┬─────┘
          ┌──────────────┼──────────────┐
          ▼              ▼              ▼
    ┌──────────┐   ┌──────────┐   ┌──────────┐
    │   clob   │   │   auth   │   │  crypto  │
    └────┬─────┘   └────┬─────┘   └────┬─────┘
         │              │              │
         │    ┌─────────┴─────────┐    │
         │    ▼                   ▼    │
         │ ┌──────┐          ┌──────┐  │
         │ │  l1  │          │  l2  │  │
         │ └──────┘          └──────┘  │
         │                             │
         └──────────┬──────────────────┘
                    ▼
              ┌──────────┐
              │  types   │
              └────┬─────┘
                   ▼
              ┌──────────┐
              │  error   │
              └──────────┘
```

## 3. 核心模块设计

### 3.1 Client 模块 (`src/clob/client.zig`)

Client 是 SDK 的核心入口点，使用类型状态机模式实现认证状态管理。

#### 3.1.1 状态类型定义

```zig
/// 客户端状态类型
pub const ClientState = enum {
    unauthenticated,
    authenticated,
    builder_authenticated,
};

/// 认证类型
pub const AuthKind = enum {
    normal,
    builder,
};

/// 签名类型
pub const SignatureType = enum(u8) {
    eoa = 0,           // 标准 EOA 钱包
    proxy = 1,         // Magic/Email 钱包
    gnosis_safe = 2,   // Gnosis Safe 多签
};
```

#### 3.1.2 Client 结构

```zig
/// 泛型客户端，S 为状态类型参数
pub fn Client(comptime S: ClientState) type {
    return struct {
        const Self = @This();

        // 内部状态
        allocator: std.mem.Allocator,
        http_client: std.http.Client,
        host: []const u8,
        config: Config,
        
        // 缓存
        tick_sizes: std.StringHashMap(TickSize),
        neg_risk: std.StringHashMap(bool),
        fee_rate_bps: std.StringHashMap(u32),
        
        // 认证状态（仅在认证后可用）
        credentials: if (S != .unauthenticated) Credentials else void,
        address: if (S != .unauthenticated) Address else void,
        signature_type: if (S != .unauthenticated) SignatureType else void,
        funder: if (S != .unauthenticated) ?Address else void,

        /// 初始化
        pub fn init(allocator: std.mem.Allocator, config: Config) !Self { ... }

        /// 释放资源
        pub fn deinit(self: *Self) void { ... }

        // 公共方法（所有状态可用）
        pub fn ok(self: *Self) ![]const u8 { ... }
        pub fn serverTime(self: *Self) !i64 { ... }
        pub fn markets(self: *Self, cursor: ?[]const u8) !Page(MarketResponse) { ... }
        // ...

        // 认证方法（仅未认证状态可用）
        pub usingnamespace if (S == .unauthenticated) struct {
            pub fn authenticate(
                self: *Self, 
                signer: anytype
            ) !Client(.authenticated) { ... }
        } else struct {};

        // 认证后方法（仅认证状态可用）
        pub usingnamespace if (S == .authenticated or S == .builder_authenticated) struct {
            pub fn apiKeys(self: *Self) !ApiKeysResponse { ... }
            pub fn postOrder(self: *Self, order: SignedOrder) !PostOrderResponse { ... }
            pub fn cancelOrder(self: *Self, order_id: []const u8) !CancelOrdersResponse { ... }
            // ...
        } else struct {};

        // Builder 专用方法
        pub usingnamespace if (S == .builder_authenticated) struct {
            pub fn builderTrades(self: *Self, request: TradesRequest) !Page(BuilderTradeResponse) { ... }
        } else struct {};
    };
}
```

#### 3.1.3 配置结构

```zig
pub const Config = struct {
    /// CLOB API 主机地址
    host: []const u8 = "https://clob.polymarket.com",
    
    /// 是否使用服务器时间（会增加额外网络请求）
    use_server_time: bool = false,
    
    /// 地理封锁检测 API 地址
    geoblock_host: []const u8 = "https://polymarket.com",
    
    /// HTTP 超时时间（毫秒）
    timeout_ms: u32 = 30000,
    
    /// 最大重试次数
    max_retries: u8 = 3,
};
```

### 3.2 Auth 模块 (`src/auth/`)

认证模块处理 L1 和 L2 认证流程。

#### 3.2.1 凭证结构

```zig
/// API 凭证
pub const Credentials = struct {
    key: Uuid,
    secret: Secret([]const u8),
    passphrase: Secret([]const u8),

    pub fn init(key: Uuid, secret: []const u8, passphrase: []const u8) Credentials { ... }
};

/// 安全包装类型，防止意外泄露
pub fn Secret(comptime T: type) type {
    return struct {
        value: T,
        
        pub fn reveal(self: @This()) T {
            return self.value;
        }
        
        pub fn format(
            self: @This(),
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = self;
            _ = fmt;
            _ = options;
            try writer.writeAll("[REDACTED]");
        }
    };
}
```

#### 3.2.2 L1 认证

```zig
// src/auth/l1.zig

pub const L1Headers = struct {
    poly_address: []const u8,
    poly_signature: []const u8,
    poly_timestamp: []const u8,
    poly_nonce: []const u8,
};

/// 创建 L1 认证头
pub fn createHeaders(
    allocator: std.mem.Allocator,
    signer: anytype,
    chain_id: u64,
    timestamp: i64,
    nonce: ?u32,
) !L1Headers {
    const naive_nonce = nonce orelse 0;
    
    // 构建 EIP-712 结构
    const auth = ClobAuth{
        .address = signer.address(),
        .timestamp = timestamp,
        .nonce = naive_nonce,
        .message = "This message attests that I control the given wallet",
    };
    
    const domain = Eip712Domain{
        .name = "ClobAuthDomain",
        .version = "1",
        .chain_id = chain_id,
    };
    
    // 签名
    const hash = auth.eip712SigningHash(domain);
    const signature = try signer.signHash(hash);
    
    return L1Headers{
        .poly_address = try std.fmt.allocPrint(allocator, "0x{x}", .{signer.address()}),
        .poly_signature = try std.fmt.allocPrint(allocator, "0x{x}", .{signature}),
        .poly_timestamp = try std.fmt.allocPrint(allocator, "{d}", .{timestamp}),
        .poly_nonce = try std.fmt.allocPrint(allocator, "{d}", .{naive_nonce}),
    };
}
```

#### 3.2.3 L2 认证

```zig
// src/auth/l2.zig

pub const L2Headers = struct {
    poly_address: []const u8,
    poly_api_key: []const u8,
    poly_passphrase: []const u8,
    poly_signature: []const u8,
    poly_timestamp: []const u8,
};

/// 创建 L2 认证头
pub fn createHeaders(
    allocator: std.mem.Allocator,
    credentials: Credentials,
    address: Address,
    request: Request,
    timestamp: i64,
) !L2Headers {
    const message = try buildMessage(allocator, request, timestamp);
    const signature = try hmacSign(credentials.secret.reveal(), message);
    
    return L2Headers{
        .poly_address = try std.fmt.allocPrint(allocator, "0x{x}", .{address}),
        .poly_api_key = try std.fmt.allocPrint(allocator, "{s}", .{credentials.key}),
        .poly_passphrase = credentials.passphrase.reveal(),
        .poly_signature = signature,
        .poly_timestamp = try std.fmt.allocPrint(allocator, "{d}", .{timestamp}),
    };
}

fn buildMessage(allocator: std.mem.Allocator, request: Request, timestamp: i64) ![]const u8 {
    return try std.fmt.allocPrint(
        allocator, 
        "{d}{s}{s}{s}", 
        .{ timestamp, request.method, request.path, request.body orelse "" }
    );
}
```

### 3.3 Crypto 模块 (`src/crypto/`)

加密模块提供签名、哈希和 EIP-712 支持。

#### 3.3.1 Signer 接口

```zig
// src/crypto/signer.zig

/// 签名器接口
pub const Signer = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        address: *const fn (*anyopaque) Address,
        signHash: *const fn (*anyopaque, [32]u8) anyerror![65]u8,
        chainId: *const fn (*anyopaque) ?u64,
    };

    pub fn address(self: Signer) Address {
        return self.vtable.address(self.ptr);
    }

    pub fn signHash(self: Signer, hash: [32]u8) ![65]u8 {
        return self.vtable.signHash(self.ptr, hash);
    }

    pub fn chainId(self: Signer) ?u64 {
        return self.vtable.chainId(self.ptr);
    }
};

/// 本地签名器（私钥签名）
pub const LocalSigner = struct {
    private_key: [32]u8,
    chain_id: ?u64,

    pub fn fromHex(hex: []const u8) !LocalSigner { ... }
    
    pub fn withChainId(self: LocalSigner, chain_id: u64) LocalSigner { ... }
    
    pub fn address(self: *const LocalSigner) Address { ... }
    
    pub fn signHash(self: *const LocalSigner, hash: [32]u8) ![65]u8 { ... }
    
    pub fn asSigner(self: *LocalSigner) Signer { ... }
};
```

#### 3.3.2 EIP-712 支持

```zig
// src/crypto/eip712.zig

pub const Eip712Domain = struct {
    name: ?[]const u8 = null,
    version: ?[]const u8 = null,
    chain_id: ?u256 = null,
    verifying_contract: ?Address = null,
    salt: ?[32]u8 = null,
    
    pub fn structHash(self: Eip712Domain) [32]u8 { ... }
};

/// EIP-712 可签名类型接口
pub fn Eip712Struct(comptime T: type) type {
    return struct {
        pub fn typeHash() [32]u8 { ... }
        pub fn structHash(data: T) [32]u8 { ... }
        pub fn eip712SigningHash(data: T, domain: Eip712Domain) [32]u8 {
            var hasher = std.crypto.hash.sha3.Keccak256.init(.{});
            hasher.update(&[_]u8{0x19, 0x01});
            hasher.update(&domain.structHash());
            hasher.update(&structHash(data));
            return hasher.finalResult();
        }
    };
}
```

### 3.4 Types 模块 (`src/clob/types/`)

类型模块定义所有请求和响应类型。

#### 3.4.1 核心类型

```zig
// src/clob/types/mod.zig

/// 订单类型
pub const OrderType = enum {
    gtc,  // Good 'til Cancelled
    fok,  // Fill or Kill
    gtd,  // Good 'til Date
    fak,  // Fill and Kill
    unknown,
};

/// 交易方向
pub const Side = enum(u8) {
    buy = 0,
    sell = 1,
    unknown = 255,
};

/// 价格精度
pub const TickSize = enum {
    tenth,           // 0.1
    hundredth,       // 0.01
    thousandth,      // 0.001
    ten_thousandth,  // 0.0001

    pub fn asDecimal(self: TickSize) Decimal { ... }
    pub fn scale(self: TickSize) u8 { ... }
};

/// 订单状态
pub const OrderStatusType = enum {
    live,
    matched,
    canceled,
    delayed,
    unmatched,
    unknown,
};

/// 资产类型
pub const AssetType = enum {
    collateral,
    conditional,
    unknown,
};
```

#### 3.4.2 订单结构

```zig
/// 订单（对应 Solidity Order 结构）
pub const Order = struct {
    salt: u256,
    maker: Address,
    signer: Address,
    taker: Address,
    token_id: u256,
    maker_amount: u256,
    taker_amount: u256,
    expiration: u256,
    nonce: u256,
    fee_rate_bps: u256,
    side: u8,
    signature_type: u8,
};

/// 可签名订单
pub const SignableOrder = struct {
    order: Order,
    order_type: OrderType,
};

/// 已签名订单
pub const SignedOrder = struct {
    order: Order,
    signature: [65]u8,
    order_type: OrderType,
    owner: Uuid,
};
```

### 3.5 OrderBuilder 模块 (`src/clob/order_builder.zig`)

订单构建器使用 Builder 模式创建订单。

```zig
/// 订单构建器
pub fn OrderBuilder(comptime Kind: OrderKind, comptime K: AuthKind) type {
    return struct {
        const Self = @This();

        client: *Client(.authenticated),
        signer: Address,
        signature_type: SignatureType,
        funder: ?Address,
        token_id: ?[]const u8,
        price: ?Decimal,
        size: ?Decimal,
        amount: ?Amount,
        side: ?Side,
        nonce: ?u64,
        expiration: ?i64,
        taker: ?Address,
        order_type: ?OrderType,

        // 通用设置方法
        pub fn tokenId(self: Self, id: []const u8) Self { ... }
        pub fn side(self: Self, s: Side) Self { ... }
        pub fn nonce(self: Self, n: u64) Self { ... }
        pub fn expiration(self: Self, exp: i64) Self { ... }
        pub fn taker(self: Self, addr: Address) Self { ... }
        pub fn orderType(self: Self, ot: OrderType) Self { ... }

        // 限价单特定方法
        pub usingnamespace if (Kind == .limit) struct {
            pub fn price(self: Self, p: Decimal) Self { ... }
            pub fn size(self: Self, s: Decimal) Self { ... }
        } else struct {};

        // 市价单特定方法
        pub usingnamespace if (Kind == .market) struct {
            pub fn amount(self: Self, a: Amount) Self { ... }
        } else struct {};

        /// 构建订单
        pub fn build(self: Self) !SignableOrder {
            // 验证必填字段
            const token_id = self.token_id orelse 
                return error.MissingTokenId;
            const side = self.side orelse 
                return error.MissingSide;
            
            // 根据订单类型进行构建
            if (Kind == .limit) {
                return self.buildLimitOrder(token_id, side);
            } else {
                return self.buildMarketOrder(token_id, side);
            }
        }
    };
}

pub const OrderKind = enum {
    limit,
    market,
};
```

## 4. 数据流

### 4.1 认证流程

```
┌─────────────────────────────────────────────────────────────────────┐
│                          L1 认证流程                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   ┌────────┐    ┌──────────┐    ┌──────────┐    ┌────────────┐     │
│   │ 用户   │───▶│ 私钥签名 │───▶│ EIP-712  │───▶│ POST /auth │     │
│   │ 私钥   │    │ ClobAuth │    │  消息    │    │ /api-key   │     │
│   └────────┘    └──────────┘    └──────────┘    └─────┬──────┘     │
│                                                        │            │
│                                                        ▼            │
│                                                 ┌────────────┐     │
│                                                 │ Credentials│     │
│                                                 │ (key,      │     │
│                                                 │  secret,   │     │
│                                                 │  passphrase│     │
│                                                 └────────────┘     │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                          L2 认证流程                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   ┌────────────┐    ┌──────────┐    ┌────────────┐                  │
│   │ Credentials│───▶│ HMAC-    │───▶│ API 请求   │                  │
│   │            │    │ SHA256   │    │ + Headers  │                  │
│   └────────────┘    └──────────┘    └─────┬──────┘                  │
│                                           │                         │
│        消息格式: {timestamp}{method}{path}{body}                    │
│                                           │                         │
│                                           ▼                         │
│                                    ┌────────────┐                   │
│                                    │ CLOB API   │                   │
│                                    └────────────┘                   │
└─────────────────────────────────────────────────────────────────────┘
```

### 4.2 订单创建流程

```
┌─────────────────────────────────────────────────────────────────────┐
│                        订单创建流程                                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   用户                                                               │
│    │                                                                │
│    ▼                                                                │
│   ┌────────────────────┐                                           │
│   │ OrderBuilder       │                                           │
│   │  .tokenId(...)     │                                           │
│   │  .price(...)       │                                           │
│   │  .size(...)        │                                           │
│   │  .side(...)        │                                           │
│   └─────────┬──────────┘                                           │
│             │                                                       │
│             ▼                                                       │
│   ┌────────────────────┐     ┌────────────────────┐               │
│   │ .build()           │────▶│ 获取 tick_size     │               │
│   │                    │     │ 获取 fee_rate      │               │
│   │                    │     │ 获取 neg_risk      │               │
│   └─────────┬──────────┘     └────────────────────┘               │
│             │                                                       │
│             ▼                                                       │
│   ┌────────────────────┐                                           │
│   │ SignableOrder      │                                           │
│   └─────────┬──────────┘                                           │
│             │                                                       │
│             ▼                                                       │
│   ┌────────────────────┐     ┌────────────────────┐               │
│   │ client.sign()      │────▶│ EIP-712 签名       │               │
│   │                    │     │ Order 结构         │               │
│   └─────────┬──────────┘     └────────────────────┘               │
│             │                                                       │
│             ▼                                                       │
│   ┌────────────────────┐                                           │
│   │ SignedOrder        │                                           │
│   └─────────┬──────────┘                                           │
│             │                                                       │
│             ▼                                                       │
│   ┌────────────────────┐     ┌────────────────────┐               │
│   │ client.postOrder() │────▶│ POST /orders       │               │
│   └────────────────────┘     └────────────────────┘               │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## 5. 错误处理

### 5.1 错误类型设计

```zig
// src/error.zig

pub const Error = error{
    // 网络错误
    ConnectionFailed,
    Timeout,
    
    // 认证错误
    InvalidSignature,
    InvalidCredentials,
    Unauthorized,
    NonceAlreadyUsed,
    
    // 验证错误
    ValidationFailed,
    InvalidTickSize,
    InvalidPrice,
    InvalidSize,
    InsufficientLiquidity,
    
    // API 错误
    ApiError,
    NotFound,
    RateLimited,
    Geoblocked,
    
    // 内部错误
    InternalError,
    ParseError,
    
    // 合约配置错误
    MissingContractConfig,
};

/// 详细错误信息
pub const ErrorDetails = struct {
    code: Error,
    message: []const u8,
    http_status: ?u16 = null,
    path: ?[]const u8 = null,
};
```

### 5.2 错误处理模式

```zig
/// Result 类型别名
pub fn Result(comptime T: type) type {
    return union(enum) {
        ok: T,
        err: ErrorDetails,
        
        pub fn unwrap(self: @This()) !T {
            return switch (self) {
                .ok => |v| v,
                .err => |e| {
                    std.log.err("{s}", .{e.message});
                    return e.code;
                },
            };
        }
    };
}
```

## 6. 性能考虑

### 6.1 内存管理

- 使用 Arena Allocator 处理临时分配
- 复用 HTTP 连接
- 缓存 tick_size、neg_risk、fee_rate 避免重复请求

### 6.2 并发

- **默认模式**: 同步阻塞 I/O，简单可靠
- **可选异步**: 通过 libxev 或 zig-aio 集成实现非阻塞 I/O
- 支持多线程并行请求处理
- 注意：Zig 原生 async/await 在 0.11+ 版本已移除，待重新设计

### 6.3 零拷贝

- 尽可能使用切片而非复制
- JSON 解析时就地解析

## 7. 安全考虑

### 7.1 私钥保护

- 私钥永不日志输出
- 使用 `Secret` 类型包装敏感数据
- 内存清零处理

### 7.2 网络安全

- 强制 HTTPS
- 验证 TLS 证书
- 请求签名防篡改

## 8. 扩展性

### 8.1 自定义签名器

支持实现自定义 Signer 接口以支持：
- 硬件钱包
- 远程签名服务（AWS KMS）
- 多签钱包

### 8.2 可选功能模块

- WebSocket 支持
- Data API
- Gamma API
- Bridge API

## 9. 测试策略

### 9.1 单元测试

- 类型序列化/反序列化
- 签名生成
- 订单构建逻辑

### 9.2 集成测试

- Mock HTTP 服务器
- 端到端流程测试

### 9.3 测试覆盖率目标

- 核心模块 > 90%
- 整体 > 80%
