# 文档

文档结构镜像源代码结构。每个已实现的模块都有对应的文档。

## 快速导航

| 文档 | 用途 |
|------|------|
| [ROADMAP.md](../ROADMAP.md) | 唯一真相来源 - 版本规划 |
| [CHANGELOG.dev.md](../CHANGELOG.dev.md) | 开发日志 - 会话记录、进度追踪 |
| [AGENTS.md](../AGENTS.md) | AI 编码规范 |
| [stories/](../stories/) | 工作单元（Stories） |

## 结构

```
docs/
├── README.md             # 本文件
├── error.md              # 错误类型
├── design/
│   ├── api-coverage.md   # API 功能覆盖分析（完整）
│   ├── contracts.md      # Polygon 合约配置
│   ├── types.md          # 详细类型定义
│   └── rfc/              # 设计决策（Why）
│       ├── 001-decimal-type.md
│       ├── 002-arraylist-allocator.md
│       └── 003-secret-type.md
├── types/                # 镜像 src/types/
│   ├── decimal.md        # 对应 src/types/decimal.zig
│   ├── secret.md         # 对应 src/types/secret.zig
│   ├── address.md        # 对应 src/types/address.zig
│   └── uuid.md           # 对应 src/types/uuid.zig
├── http/                 # 镜像 src/http/
│   └── README.md         # HTTP 客户端
├── crypto/               # 镜像 src/crypto/
│   ├── README.md         # 模块概述
│   ├── keccak.md         # Keccak256 哈希
│   ├── ecdsa.md          # secp256k1 ECDSA 签名
│   └── hmac.md           # HMAC-SHA256 认证
├── signer/               # 镜像 src/signer/
│   ├── README.md         # 模块概述
│   ├── wallet.md         # Wallet 类型
│   └── eip712.md         # EIP-712 签名
├── auth/                 # 镜像 src/auth/
│   ├── README.md         # 模块概述
│   ├── l1-auth.md        # L1 认证 (EIP-712)
│   └── l2-auth.md        # L2 认证 (HMAC-SHA256)
├── order/                # 镜像 src/order/
│   ├── README.md         # 模块概述
│   └── builder.md        # 订单构建器
└── clob/                 # 镜像 src/clob/
    ├── README.md         # 模块概述
    └── orders.md         # 订单管理 API
```

## 设计文档

### 核心设计

| 文档 | 描述 | 状态 |
|------|------|------|
| [api-coverage.md](./design/api-coverage.md) | API 功能覆盖分析 - 完整对比官方客户端 | ✅ 完成 |
| [contracts.md](./design/contracts.md) | Polygon 合约配置 - 地址、ABI、Allowances | ✅ 完成 |
| [types.md](./design/types.md) | 详细类型定义 - 枚举、结构体、参数 | ✅ 完成 |

### RFCs

设计决策文档，包含问题、方案和备选方案。

| RFC | 标题 | 状态 |
|-----|------|------|
| [001](./design/rfc/001-decimal-type.md) | Decimal 类型 | 已采纳 |
| [002](./design/rfc/002-arraylist-allocator.md) | ArrayList Allocator (Zig 0.15) | 已采纳 |
| [003](./design/rfc/003-secret-type.md) | Secret 类型 | 已采纳 |

## 已实现的模块

### types/ - 核心类型

| 源文件 | 文档 | 状态 |
|--------|------|------|
| `src/types/decimal.zig` | [types/decimal.md](./types/decimal.md) | ✅ |
| `src/types/secret.zig` | [types/secret.md](./types/secret.md) | ✅ |
| `src/types/address.zig` | [types/address.md](./types/address.md) | ✅ |
| `src/types/uuid.zig` | [types/uuid.md](./types/uuid.md) | ✅ |
| `src/types/mod.zig` | - | ✅ |
| `src/types/contracts.zig` | [design/contracts.md](./design/contracts.md) | ⏳ 未实现 |

### crypto/ - 加密模块

| 源文件 | 文档 | 状态 |
|--------|------|------|
| `src/crypto/mod.zig` | [crypto/README.md](./crypto/README.md) | ✅ |
| `src/crypto/keccak.zig` | [crypto/keccak.md](./crypto/keccak.md) | ✅ |
| `src/crypto/ecdsa.zig` | [crypto/ecdsa.md](./crypto/ecdsa.md) | ✅ |
| `src/crypto/hmac.zig` | [crypto/hmac.md](./crypto/hmac.md) | ✅ |

### signer/ - 签名模块

| 源文件 | 文档 | 状态 |
|--------|------|------|
| `src/signer/mod.zig` | [signer/README.md](./signer/README.md) | ✅ |
| `src/signer/wallet.zig` | [signer/wallet.md](./signer/wallet.md) | ✅ |
| `src/signer/eip712.zig` | [signer/eip712.md](./signer/eip712.md) | ✅ |

### auth/ - 认证模块

| 源文件 | 文档 | 状态 |
|--------|------|------|
| `src/auth/mod.zig` | - | ✅ |
| `src/auth/l1.zig` | [auth/l1-auth.md](./auth/l1-auth.md) | ✅ |
| `src/auth/l2.zig` | [auth/l2-auth.md](./auth/l2-auth.md) | ✅ |
| `src/auth/api_creds.zig` | [auth/l1-auth.md](./auth/l1-auth.md) | ✅ |
| `src/auth/headers.zig` | [auth/l1-auth.md](./auth/l1-auth.md) | ✅ |

### order/ - 订单模块

| 源文件 | 文档 | 状态 |
|--------|------|------|
| `src/order/mod.zig` | [order/README.md](./order/README.md) | ✅ |
| `src/order/types.zig` | [order/builder.md](./order/builder.md) | ✅ |
| `src/order/calculator.zig` | [order/builder.md](./order/builder.md) | ✅ |
| `src/order/builder.zig` | [order/builder.md](./order/builder.md) | ✅ |

### clob/ - CLOB 客户端模块

| 源文件 | 文档 | 状态 |
|--------|------|------|
| `src/clob/mod.zig` | - | ✅ |
| `src/clob/client.zig` | [clob/orders.md](./clob/orders.md) | ✅ |
| `src/clob/types/mod.zig` | - | ✅ |
| `src/clob/types/enums.zig` | - | ✅ |
| `src/clob/types/market.zig` | - | ✅ |
| `src/clob/types/book.zig` | - | ✅ |
| `src/clob/types/order.zig` | [clob/orders.md](./clob/orders.md) | ✅ |
| `src/clob/types/trade.zig` | [clob/orders.md](./clob/orders.md) | ✅ |
| `src/clob/types/account.zig` | [clob/orders.md](./clob/orders.md) | ✅ |

## API 覆盖统计

基于 [api-coverage.md](./design/api-coverage.md) 的分析：

| 版本 | 功能 | 端点数量 |
|------|------|----------|
| v0.1 | 公共 API (L0) | ~20 |
| v0.2 | 认证与订单 (L1/L2) | ~25 |
| v0.3 | Builder + RFQ | ~25 |
| v0.4 | WebSocket | ~4 |
| v0.5 | 奖励 + 分析 | ~10 |
| **总计** | | **~84** |

## 原则

> **文档跟随代码，而非相反。**

- 只为 `src/` 中存在的内容编写文档
- 每个 `.zig` 文件可以有对应的 `.md` 文件
- RFC 解释 **为什么**，模块文档解释 **是什么** 和 **怎么用**
- 设计文档（`design/`）记录跨模块的设计决策

## 参考链接

### 官方仓库
- [py-clob-client](https://github.com/Polymarket/py-clob-client) - Python 客户端
- [clob-client](https://github.com/Polymarket/clob-client) - TypeScript 客户端
- [agents](https://github.com/Polymarket/agents) - AI 交易代理

### 官方文档
- [Polymarket API 文档](https://docs.polymarket.com/)
- [CLOB API 规范](https://docs.polymarket.com/developers/clob-api)
- [Gamma Markets API](https://docs.polymarket.com/developers/gamma-markets-api)
