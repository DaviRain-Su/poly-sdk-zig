# 示例代码

本目录包含 poly-sdk-zig 的使用示例。

## 示例列表

| 文件 | 描述 | 需要认证 |
|------|------|----------|
| `basic_types.zig` | 基础类型使用（Decimal, Secret, Address, UUID） | 否 |
| `public_api.zig` | 公共 API（市场、价格、订单簿） | 否 |
| `authentication.zig` | L1/L2 认证流程 | 是 |
| `order_management.zig` | 订单创建、发布和管理 | 是 |
| `websocket.zig` | WebSocket 实时数据订阅 | 部分 |
| `btc_hedge_strategy.zig` | BTC 二元期权对冲套利策略 | 是 |

## 示例说明

### basic_types.zig

演示核心类型的使用：
- `Decimal` - 高精度十进制数字
- `Secret` - 敏感数据包装器
- `Address` - 以太坊地址（EIP-55 校验和）
- `UUID` - v4 UUID 生成

### public_api.zig

演示无需认证的公共端点：
- 服务器状态检查
- 市场列表查询
- 订单簿获取
- 价格、中间价、价差查询
- 批量端点使用

### authentication.zig

演示认证流程：
- L1 认证（钱包签名）
- API Key 创建和派生
- L2 认证（HMAC 签名）
- 认证请求示例

### order_management.zig

演示订单管理：
- 创建限价单和市价单
- 发布订单
- 查询订单状态
- 取消订单
- 批量订单操作

### websocket.zig

演示 WebSocket 实时数据：
- Market Channel（公开市场数据）
- User Channel（用户私有数据）
- 消息解析和处理
- 回调函数配置

### btc_hedge_strategy.zig

完整的 BTC 二元期权对冲套利策略：
- 针对 "BTC 15分钟内是否上涨" 市场
- 两步对冲：抄底 YES + 反弹卖 NO
- 自动检测暴跌和反弹时机
- 动态仓位管理
- 利润锁定计算

**策略原理**：
1. 监控 YES 价格，检测快速下跌
2. 价格跌到低位时买入 YES
3. 价格反弹后卖出等量 NO 对冲
4. YES + NO = 1，锁定无风险利润

**风险提示**：这是真实交易策略，涉及资金风险，仅供教育参考。

## 运行示例

示例文件是独立的教学文档，主要用于展示 API 用法。它们包含详细的代码说明和注释。

```bash
# 查看示例代码了解 API 使用方法
cat examples/public_api.zig
cat examples/websocket.zig
```

## 配置

需要认证的示例需要设置环境变量：

```bash
# 基础认证配置
export POLY_PRIVATE_KEY=0x...          # 钱包私钥
export POLY_API_KEY=your-api-key       # API Key
export POLY_API_SECRET=your-secret     # API Secret  
export POLY_API_PASSPHRASE=your-pass   # API Passphrase

# BTC 对冲策略额外配置
export POLY_YES_TOKEN=...              # YES Token ID
export POLY_NO_TOKEN=...               # NO Token ID
export POLY_CONDITION_ID=...           # 市场 Condition ID
```

Token ID 和 Condition ID 可从 Polymarket 市场页面获取。

## 注意事项

1. **安全**: 永远不要硬编码私钥或 API 凭证
2. **测试网**: 建议先在测试网验证逻辑
3. **小额测试**: 正式交易前先用小额测试
4. **服务条款**: 了解 [Polymarket 服务条款](https://polymarket.com/tos)

## 更多资源

- [API 文档](../docs/README.md)
- [类型定义](../docs/design/types.md)
- [WebSocket 文档](../docs/ws/README.md)
