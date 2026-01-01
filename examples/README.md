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
| `find_btc_markets.zig` | BTC 市场搜索工具 | 否 |
| `btc_15m_monitor.zig` | BTC 15分钟市场实时监控 | 否 |
| `btc_auto_trader.zig` | BTC 15分钟自动交易系统 v1 | 是（实盘）/否（模拟）|
| `btc_orderbook_monitor.zig` | BTC 15分钟订单簿监控 | 否 |
| `btc_smart_trader.zig` | BTC 15分钟智能交易系统 v2 | 是（实盘）/否（模拟）|

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

### find_btc_markets.zig

BTC 市场搜索工具：
- 连接 Polymarket API
- 搜索所有 BTC/Bitcoin 相关市场
- 显示市场详情、Token ID、价格
- 输出可直接用于策略配置的信息

**用途**：找到 BTC 相关市场的 Token ID 和 Condition ID，配置到 `.env` 文件中。

### btc_15m_monitor.zig

BTC 15 分钟市场实时监控工具（对冲策略专用）：
- 持续轮询 Polymarket API
- 自动检测 `btc-updown-15m-*` 格式的市场
- **策略适用性评估**：根据剩余时间评估是否适合对冲策略
- 发现市场时显示 Token ID 和价格
- 计算下一个预期市场的时间
- 可选自动更新 `.env` 配置文件

**策略适用性评级**：
- ✅ 最佳：剩余 >10分钟，有充足时间执行两步对冲
- ⚠️ 可以：剩余 7-10分钟，时间较紧需快速决策
- 🔶 危险：剩余 4-7分钟，可能没时间完成对冲
- ❌ 不建议：剩余 <4分钟，风险太高

**命令行选项**：
- `--strategy, -s` - 只显示适合策略的市场（剩余 >=7分钟）
- `--once` - 只扫描一次然后退出
- `--all` - 显示所有市场（包括不活跃的）
- `--auto-env` - 发现市场时自动更新 .env 文件
- `--help` - 显示帮助信息

**用途**：BTC 15 分钟涨跌预测市场每 15 分钟创建一次，生命周期很短。此工具帮助实时发现适合对冲策略的短期市场。

### btc_auto_trader.zig

BTC 15 分钟市场自动交易系统（监控 + 策略一体化）：
- 自动监控并发现 BTC 15 分钟涨跌市场
- 评估市场适用性（剩余时间分析）
- 自动配置并执行对冲策略
- 市场结束后自动切换到下一个市场
- 支持模拟模式和实盘模式

**工作流程**：
```
┌─────────────────────────────────────────────────────────────┐
│  阶段 1: 监控                                                │
│  └── 扫描 API 寻找 btc-updown-15m-* 市场                    │
│  └── 评估剩余时间（需要 >=7 分钟）                          │
├─────────────────────────────────────────────────────────────┤
│  阶段 2: 策略执行                                            │
│  └── 检测价格暴跌 → 买入 YES                                │
│  └── 检测价格反弹 → 卖出 NO 对冲                            │
├─────────────────────────────────────────────────────────────┤
│  阶段 3: 等待                                                │
│  └── 等待市场结束                                           │
│  └── 重置状态，返回阶段 1                                   │
└─────────────────────────────────────────────────────────────┘
```

**配置（.env 文件）**：
```bash
# 模式控制
AUTO_TRADER_DRY_RUN=true              # true=模拟模式, false=实盘

# 最小剩余时间（分钟）
AUTO_TRADER_MIN_REMAINING_MINUTES=7

# 实盘模式 - 只需要私钥！
# API 凭证会通过 L1 认证自动获取
POLY_PRIVATE_KEY=your_private_key_without_0x_prefix

# 可选：手动指定 API 凭证（如果不指定会自动获取）
# POLY_API_KEY=your_api_key
# POLY_API_SECRET=your_secret
# POLY_API_PASSPHRASE=your_passphrase

# 策略参数（与 btc_hedge_strategy 相同）
STRATEGY_SUM_TARGET=0.3
STRATEGY_MOVE_THRESHOLD=0.01
STRATEGY_MIN_BUY_PRICE=0.15
STRATEGY_HEDGE_SPREAD=0.05
```

**重要**: 实盘模式只需要配置 `POLY_PRIVATE_KEY`！系统会自动通过 L1 认证获取 API 凭证。

**命令**：
```bash
# 模拟模式运行（默认，不需要凭证）
zig build run-btc_auto_trader

# 实盘模式（需要在 .env 中设置 AUTO_TRADER_DRY_RUN=false）
zig build run-btc_auto_trader
```

**用途**：将监控和策略结合，实现全自动交易。无需手动配置 Token ID，系统会自动发现市场并执行策略。

### btc_orderbook_monitor.zig

BTC 15分钟市场订单簿实时监控：
- 显示 UP 和 DOWN 两边的订单簿
- 最佳买卖价、价差、中间价
- 买卖盘深度分析
- 套利机会检测（UP + DOWN != 1.0）
- 自动切换到下一个市场

**命令**：
```bash
zig build run-btc_orderbook_monitor
```

### btc_smart_trader.zig

BTC 15分钟市场智能交易系统 v2（改进版）：

**核心改进**：
- **真实价差分析**：忽略边缘订单（0.01-0.20, 0.80-0.99），找到真正的买卖价差
- **多策略模式**：支持做市、套利、趋势跟随、混合模式
- **动量指标**：基于价格历史计算动量和波动率
- **风险管理**：根据波动率调整策略行为

**策略模式**：
| 模式 | 描述 |
|------|------|
| `market_maker` | 做市商策略：在价差两侧挂单赚取价差 |
| `arbitrage` | 套利策略：当 UP + DOWN != 1.0 时套利 |
| `trend_follower` | 趋势跟随：跟随价格动量方向交易 |
| `hybrid` | 混合模式：综合使用多种策略（默认） |

**配置（.env 文件）**：
```bash
# 策略模式
SMART_TRADER_MODE=hybrid           # hybrid/market_maker/arbitrage/trend

# 模式控制
SMART_TRADER_DRY_RUN=true          # true=模拟模式, false=实盘

# 策略参数
SMART_TRADER_EDGE_THRESHOLD=0.20   # 边缘价格阈值
SMART_TRADER_MM_SPREAD=0.02        # 做市最小价差
SMART_TRADER_ARB_THRESHOLD=0.02    # 套利阈值
SMART_TRADER_TREND_THRESHOLD=0.05  # 趋势阈值
SMART_TRADER_ORDER_SIZE=50.0       # 单次订单金额
SMART_TRADER_MAX_POSITION=200.0    # 最大仓位

# 实盘模式 - 只需要私钥！
POLY_PRIVATE_KEY=your_private_key_without_0x_prefix
```

**运行**：
```bash
# 模拟模式（默认）
zig build run-btc_smart_trader

# 实盘模式（需要配置 SMART_TRADER_DRY_RUN=false）
zig build run-btc_smart_trader
```

**关键洞察**：

之前的问题是看到 0.01 买价 / 0.99 卖价（98% 价差），认为市场流动性很差。但实际上这只是边缘做市商的订单。真正的中间价格区域（0.40-0.60）有活跃的订单簿：
- 真实买价: ~0.51
- 真实卖价: ~0.52
- 真实价差: ~0.01 (1%)

这个版本通过过滤边缘订单，找到真实的市场价格，使策略能够正常运作。

## 运行示例

示例可通过 build.zig 构建和运行：

```bash
# 构建所有示例
zig build examples

# 运行特定示例
zig build run-basic_types           # 基础类型演示
zig build run-public_api            # 公共 API 演示
zig build run-authentication        # 认证流程演示
zig build run-order_management      # 订单管理演示
zig build run-websocket             # WebSocket 演示
zig build run-btc_hedge_strategy    # BTC 对冲策略
zig build run-find_btc_markets      # BTC 市场搜索
zig build run-btc_15m_monitor       # BTC 15分钟市场监控
zig build run-btc_15m_monitor -- --once  # 单次扫描
zig build run-btc_auto_trader       # BTC 自动交易系统 v1
zig build run-btc_orderbook_monitor # BTC 订单簿监控
zig build run-btc_smart_trader      # BTC 智能交易系统 v2

# 查看所有可用命令
zig build --help | grep run-
```

示例文件也是教学文档，包含详细的代码说明和注释：

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
