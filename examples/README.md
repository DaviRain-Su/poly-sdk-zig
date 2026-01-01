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
| `btc_ws_trader.zig` | BTC 15分钟 WebSocket 实时交易系统 | 是（实盘）/否（模拟）|
| `btc_orderbook_monitor.zig` | BTC 15分钟订单簿实时监控 | 否 |

## 运行示例

```bash
# 构建所有示例
zig build examples

# 运行特定示例
zig build run-basic_types           # 基础类型演示
zig build run-public_api            # 公共 API 演示
zig build run-authentication        # 认证流程演示
zig build run-order_management      # 订单管理演示
zig build run-websocket             # WebSocket 演示
zig build run-btc_ws_trader         # BTC 实时交易系统
zig build run-btc_orderbook_monitor # BTC 订单簿监控
```

## 配置

需要认证的示例需要在 `.env` 文件中配置：

```bash
# 基础认证配置
POLY_PRIVATE_KEY=your_private_key_without_0x_prefix

# 签名类型 (0=EOA, 1=POLY_PROXY, 2=POLY_GNOSIS_SAFE)
WS_TRADER_SIGNATURE_TYPE=2

# Proxy/Funder 地址（用于 POLY_PROXY 或 POLY_GNOSIS_SAFE）
POLY_ADDRESS=0x...

# 交易配置
WS_TRADER_DRY_RUN=true              # true=模拟模式, false=实盘
WS_TRADER_ORDER_SIZE=10             # 每单金额（美元）
```

## 注意事项

1. **安全**: 永远不要硬编码私钥或 API 凭证
2. **测试网**: 建议先在测试网验证逻辑
3. **小额测试**: 正式交易前先用小额测试
4. **Allowance**: 使用 Proxy 钱包时需要先在 Polymarket 网站授权 USDC
