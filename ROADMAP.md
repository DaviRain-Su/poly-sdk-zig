# ROADMAP - 唯一真相来源

这是项目规划的唯一真相来源。所有工作都从这里派生。

## 当前状态

**版本**: v0.0.0 (预发布)  
**阶段**: v0.1 - 核心基础

---

## v0.1 - 核心基础

> **目标**: 基础类型、HTTP 客户端和只读公共 API。
> **交付物**: 无需认证即可查询市场数据。

```zig
var client = try poly.Client.init(allocator, .{});
const markets = try client.markets(.{});
```

### Stories

| Story | 状态 | 依赖 |
|-------|------|------|
| [v0.1-types](./stories/v0.1-types.md) | 🔨 进行中 | - |
| [v0.1-error](./stories/v0.1-error.md) | ⏳ 待开始 | - |
| [v0.1-http](./stories/v0.1-http.md) | ⏳ 待开始 | v0.1-error |
| [v0.1-public-api](./stories/v0.1-public-api.md) | ⏳ 待开始 | v0.1-http, v0.1-types |

### 进度

- [x] 项目设置 (build.zig, 结构)
- [x] Decimal 类型实现
- [x] Secret 类型实现
- [ ] Address, UUID 类型
- [ ] 错误类型
- [ ] HTTP 客户端
- [ ] 公共 API 端点

---

## v0.2 - 认证与订单

> **目标**: 完整的认证和订单管理。
> **交付物**: 下单和管理订单。

```zig
var auth = try client.authenticate(&signer);
try auth.postOrder(order);
```

### Stories (计划中)

| Story | 状态 | 描述 |
|-------|------|------|
| v0.2-crypto | ⏳ 待开始 | secp256k1, keccak256, HMAC |
| v0.2-l1-auth | ⏳ 待开始 | EIP-712 签名 |
| v0.2-l2-auth | ⏳ 待开始 | HMAC 请求签名 |
| v0.2-orders | ⏳ 待开始 | 订单构建器, 下单/取消 |

---

## v0.3 - Builder 与扩展

> **目标**: Builder 程序和其他功能。

---

## v0.4 - WebSocket

> **目标**: 实时数据订阅。

---

## v1.0 - 稳定版发布

> **目标**: 生产就绪，完整测试。

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
