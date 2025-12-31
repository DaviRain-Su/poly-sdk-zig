# 开发路线图

本文档描述 Polymarket Zig CLOB Client SDK 的开发计划和里程碑。

## 版本规划

### v0.1.0 - 核心功能 (MVP)

**目标**: 实现基础 CLOB 客户端功能

**时间线**: 第 1-2 周

#### 待完成功能

- [ ] **项目基础设施**
  - [ ] 项目结构搭建
  - [ ] 构建系统配置
  - [ ] 测试框架设置
  - [ ] CI/CD 配置

- [ ] **类型系统**
  - [ ] Decimal 高精度类型
  - [ ] Address 类型
  - [ ] UUID 类型
  - [ ] Secret 包装类型
  - [ ] 所有 CLOB 业务类型

- [ ] **HTTP 客户端**
  - [ ] 基础 HTTP 请求
  - [ ] JSON 序列化/反序列化
  - [ ] 错误处理
  - [ ] 超时控制

- [ ] **公共 API**
  - [ ] `ok()` - 服务状态检查
  - [ ] `serverTime()` - 服务器时间
  - [ ] `midpoint()` / `midpoints()` - 中间价
  - [ ] `price()` / `prices()` - 价格
  - [ ] `spread()` / `spreads()` - 价差
  - [ ] `tickSize()` - 价格精度
  - [ ] `negRisk()` - 负风险检查
  - [ ] `feeRateBps()` - 手续费率
  - [ ] `orderBook()` / `orderBooks()` - 订单簿
  - [ ] `lastTradePrice()` - 最新成交价
  - [ ] `market()` / `markets()` - 市场信息
  - [ ] `checkGeoblock()` - 地理限制检查

---

### v0.2.0 - 认证与交易

**目标**: 实现完整认证流程和订单管理

**时间线**: 第 3-4 周

#### 待完成功能

- [ ] **加密模块**
  - [ ] secp256k1 签名
  - [ ] keccak256 哈希
  - [ ] EIP-712 结构化签名
  - [ ] HMAC-SHA256

- [ ] **L1 认证**
  - [ ] ClobAuth EIP-712 消息构建
  - [ ] L1 头生成
  - [ ] `createApiKey()`
  - [ ] `deriveApiKey()`
  - [ ] `createOrDeriveApiKey()`

- [ ] **L2 认证**
  - [ ] HMAC 签名
  - [ ] L2 头生成
  - [ ] 认证状态管理

- [ ] **订单构建器**
  - [ ] `limitOrder()` 限价单
  - [ ] `marketOrder()` 市价单
  - [ ] 价格/数量验证
  - [ ] 订单签名

- [ ] **订单管理**
  - [ ] `postOrder()` / `postOrders()`
  - [ ] `order()` / `orders()`
  - [ ] `cancelOrder()` / `cancelOrders()`
  - [ ] `cancelAllOrders()`
  - [ ] `cancelMarketOrders()`

- [ ] **交易查询**
  - [ ] `trades()`
  - [ ] `balanceAllowance()`

---

### v0.3.0 - 完整功能

**目标**: 实现所有 CLOB API 和 Builder 支持

**时间线**: 第 5-6 周

#### 待完成功能

- [ ] **Builder 认证**
  - [ ] Builder 头生成
  - [ ] 本地/远程配置
  - [ ] `promoteToBuilder()`
  - [ ] `createBuilderApiKey()`
  - [ ] `builderApiKeys()`
  - [ ] `revokeBuilderApiKey()`
  - [ ] `builderTrades()`

- [ ] **通知管理**
  - [ ] `notifications()`
  - [ ] `deleteNotifications()`

- [ ] **奖励查询**
  - [ ] `currentRewards()`
  - [ ] `earningsForUserForDay()`
  - [ ] `totalEarningsForUserForDay()`
  - [ ] `rewardPercentages()`
  - [ ] `rawRewardsForMarket()`

- [ ] **其他功能**
  - [ ] `closedOnlyMode()`
  - [ ] `updateBalanceAllowance()`
  - [ ] `isOrderScoring()` / `areOrdersScoring()`

- [ ] **分页支持**
  - [ ] `streamData()` 流式获取

---

### v0.4.0 - WebSocket 支持

**目标**: 实现实时数据订阅

**时间线**: 第 7-8 周

> **注意**: 由于 Zig 原生 async/await 在 0.11+ 版本已移除，WebSocket 支持将：
> - 默认使用同步阻塞模式（在独立线程中运行）
> - 可选集成 [libxev](https://github.com/Cloudef/libxev) 实现事件驱动的非阻塞 I/O

#### 待完成功能

- [ ] **WebSocket 客户端**
  - [ ] 连接管理
  - [ ] 自动重连
  - [ ] 心跳处理
  - [ ] 可选 libxev 集成

- [ ] **市场频道**
  - [ ] 订单簿订阅
  - [ ] 价格订阅
  - [ ] 交易订阅

- [ ] **用户频道**
  - [ ] 订单更新
  - [ ] 成交通知
  - [ ] 余额更新

- [ ] **认证**
  - [ ] WebSocket L2 认证

---

### v0.5.0 - 可选 API

**目标**: 实现可选的辅助 API

**时间线**: 第 9-10 周

#### 待完成功能

- [ ] **Data API**
  - [ ] 历史数据查询
  - [ ] 统计数据

- [ ] **Gamma API**
  - [ ] 市场元数据
  - [ ] 事件信息

- [ ] **Bridge API**
  - [ ] 跨链桥接

---

### v1.0.0 - 稳定版本

**目标**: 生产就绪的稳定版本

**时间线**: 第 11-12 周

#### 待完成功能

- [ ] **稳定性**
  - [ ] 完整测试覆盖
  - [ ] 性能优化
  - [ ] 内存优化

- [ ] **文档**
  - [ ] 完整 API 文档
  - [ ] 教程和示例
  - [ ] 变更日志

- [ ] **工具**
  - [ ] CLI 工具
  - [ ] 代码生成器

---

## 功能优先级

### P0 - 必须 (Must Have)

| 功能 | 描述 | 版本 |
|------|------|------|
| HTTP 客户端 | 基础请求能力 | v0.1.0 |
| 类型系统 | 核心数据类型 | v0.1.0 |
| 公共 API | 市场数据读取 | v0.1.0 |
| L1/L2 认证 | 完整认证流程 | v0.2.0 |
| 订单管理 | 下单/取消/查询 | v0.2.0 |

### P1 - 应该 (Should Have)

| 功能 | 描述 | 版本 |
|------|------|------|
| Builder 认证 | Builder 程序支持 | v0.3.0 |
| 奖励查询 | 流动性奖励 | v0.3.0 |
| WebSocket | 实时数据 | v0.4.0 |

### P2 - 可以 (Could Have)

| 功能 | 描述 | 版本 |
|------|------|------|
| Data API | 历史数据 | v0.5.0 |
| Gamma API | 市场元数据 | v0.5.0 |
| Bridge API | 跨链桥接 | v0.5.0 |
| CLI 工具 | 命令行界面 | v1.0.0 |

---

## 技术债务

### 已知问题

1. **内存管理**
   - 需要仔细审查所有分配/释放路径
   - 考虑使用 Arena Allocator 优化临时分配

2. **错误处理**
   - 需要更详细的错误上下文
   - 考虑添加错误追踪

3. **测试覆盖**
   - 需要添加集成测试
   - 需要 Mock 服务器

### 改进计划

1. **性能优化**
   - HTTP 连接池
   - JSON 解析优化
   - 减少内存分配

2. **可用性改进**
   - 更好的错误消息
   - 更多示例代码
   - IDE 支持

---

## 发布检查清单

### 发布前检查

- [ ] 所有测试通过
- [ ] 文档更新
- [ ] CHANGELOG 更新
- [ ] 版本号更新
- [ ] 示例代码测试
- [ ] 依赖更新

### 发布后检查

- [ ] GitHub Release 创建
- [ ] 文档网站更新
- [ ] 公告发布

---

## 贡献指南

### 如何贡献

1. Fork 仓库
2. 创建功能分支
3. 提交更改
4. 创建 Pull Request

### 代码规范

- 遵循 Zig 官方风格指南
- 所有公共 API 需要文档注释
- 新功能需要测试覆盖

### 问题报告

请在 GitHub Issues 中报告：
- Bug 报告
- 功能请求
- 文档改进

---

## 联系方式

- **GitHub Issues**: 技术问题和 Bug 报告
- **Discussions**: 一般讨论和问题
- **Discord**: 实时交流
