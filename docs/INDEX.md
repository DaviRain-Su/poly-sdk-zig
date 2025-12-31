# Polymarket Zig CLOB Client SDK 文档索引

## 文档导航

本项目采用文档驱动开发模式，以下是所有设计文档的完整列表。

---

## 核心文档

| 文档 | 描述 | 重要程度 |
|------|------|----------|
| [README.md](./README.md) | 项目概述、快速开始指南 | 必读 |
| [ARCHITECTURE.md](./ARCHITECTURE.md) | 系统架构设计、模块依赖 | 必读 |
| [API_REFERENCE.md](./API_REFERENCE.md) | 完整 API 参考文档 | 必读 |

---

## 设计文档

| 文档 | 描述 | 相关模块 |
|------|------|----------|
| [MODULES.md](./MODULES.md) | 模块设计和实现细节 | 所有模块 |
| [TYPES.md](./TYPES.md) | 类型系统设计 | `types/`, `clob/types/` |
| [AUTHENTICATION.md](./AUTHENTICATION.md) | 认证流程设计 | `auth/` |
| [ERROR_HANDLING.md](./ERROR_HANDLING.md) | 错误处理机制 | `error.zig` |

---

## 使用文档

| 文档 | 描述 | 适用人群 |
|------|------|----------|
| [EXAMPLES.md](./EXAMPLES.md) | 示例代码和使用教程 | 开发者 |
| [ROADMAP.md](./ROADMAP.md) | 开发路线图和版本规划 | 贡献者 |

---

## 文档统计

| 项目 | 数量 |
|------|------|
| 总文档数 | 9 |
| 核心文档 | 3 |
| 设计文档 | 4 |
| 使用文档 | 2 |

---

## 阅读建议

### 新用户

1. 阅读 [README.md](./README.md) 了解项目概述
2. 参考 [EXAMPLES.md](./EXAMPLES.md) 快速上手
3. 查阅 [API_REFERENCE.md](./API_REFERENCE.md) 了解具体 API

### 贡献者

1. 阅读 [ARCHITECTURE.md](./ARCHITECTURE.md) 理解系统设计
2. 阅读 [MODULES.md](./MODULES.md) 了解模块实现
3. 阅读 [ROADMAP.md](./ROADMAP.md) 了解开发计划

### 深入理解

1. [TYPES.md](./TYPES.md) - 类型系统设计
2. [AUTHENTICATION.md](./AUTHENTICATION.md) - 认证机制
3. [ERROR_HANDLING.md](./ERROR_HANDLING.md) - 错误处理

---

## 文档版本

- 文档版本: 1.0.0
- 最后更新: 2024-12-31
- 对应代码版本: 开发中

---

## 文档结构图

```
docs/
├── INDEX.md              # 本文件 - 文档索引
├── README.md             # 项目概述
├── ARCHITECTURE.md       # 架构设计
├── API_REFERENCE.md      # API 参考
├── MODULES.md            # 模块设计
├── TYPES.md              # 类型系统
├── AUTHENTICATION.md     # 认证流程
├── ERROR_HANDLING.md     # 错误处理
├── EXAMPLES.md           # 示例代码
└── ROADMAP.md            # 开发路线图
```

---

## 相关资源

### 官方资源

- [Polymarket 官方网站](https://polymarket.com)
- [Polymarket 开发者文档](https://docs.polymarket.com)
- [原始 Rust 客户端](https://github.com/Polymarket/rs-clob-client)

### 技术资源

- [Zig 语言官网](https://ziglang.org)
- [Zig 标准库文档](https://ziglang.org/documentation/master/std/)

### 区块链资源

- [EIP-712 规范](https://eips.ethereum.org/EIPS/eip-712)
- [Polygon 网络](https://polygon.technology/)
