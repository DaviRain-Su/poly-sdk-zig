# BTC 二元期权对冲套利策略

> 使用 Polymarket SDK 实现的自动化交易策略

## 概述

本策略针对 Polymarket 上的 "BTC 价格在下一个 15 分钟内是否上涨" 类型的二元期权市场，实现两步对冲套利。

### 核心逻辑

1. **第一步 - 捕捉暴跌买入 YES**: 当检测到价格快速大幅下跌时，买入 YES 股份
2. **第二步 - 反弹后对冲锁定**: 价格反弹后，卖出等量 NO 股份，锁定利润

### 利润来源

- YES + NO = 1 美元 (完全对冲)
- 若 YES 买入均价 0.20，对冲时涨到 0.35，则锁定 0.15 利润/份

## 快速开始

### 1. 准备工作

```bash
# 克隆项目
git clone https://github.com/your-repo/poly-sdk-zig.git
cd poly-sdk-zig

# 构建项目
zig build
```

### 2. 配置环境变量

#### 方法一: 使用 .env 文件 (推荐)

```bash
# 复制示例配置文件
cp .env.example .env

# 编辑配置文件
vim .env  # 或使用你喜欢的编辑器
```

#### 方法二: 使用环境变量

```bash
# 设置必需的环境变量
export POLY_PRIVATE_KEY=your_private_key_without_0x
export POLY_API_KEY=your_api_key
export POLY_API_SECRET=your_api_secret
export POLY_API_PASSPHRASE=your_passphrase

# 设置市场配置
export POLY_YES_TOKEN=123456...
export POLY_NO_TOKEN=789012...
export POLY_CONDITION_ID=abcdef...
```

### 3. 运行策略

```bash
# 直接运行示例
zig build run-btc-hedge

# 或手动编译运行
zig build-exe examples/btc_hedge_strategy.zig -lc
./btc_hedge_strategy
```

## 配置参数详解

### 必需配置

| 参数 | 说明 | 示例 |
|------|------|------|
| `POLY_PRIVATE_KEY` | 钱包私钥 (不带 0x 前缀) | `4c0883a69102937d...` |
| `POLY_API_KEY` | Polymarket API Key | `pk_live_xxxxx` |
| `POLY_API_SECRET` | Polymarket API Secret | `sk_live_xxxxx` |
| `POLY_API_PASSPHRASE` | Polymarket API Passphrase | `your_passphrase` |
| `POLY_YES_TOKEN` | YES Token ID | `123456...` |
| `POLY_NO_TOKEN` | NO Token ID | `789012...` |
| `POLY_CONDITION_ID` | 市场 Condition ID | `0xabcdef...` |

### 网络配置

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `POLY_USE_TESTNET` | 是否使用测试网 | `false` |
| `CLOB_API_URL` | API 端点 | `https://clob.polymarket.com` |

### 策略参数

| 参数 | 说明 | 默认值 | 推荐范围 |
|------|------|--------|----------|
| `STRATEGY_SUM_TARGET` | 累计买入目标 | `0.3` | 0.2 - 0.6 |
| `STRATEGY_MOVE_THRESHOLD` | 下跌触发阈值 | `0.01` (1%) | 0.005 - 0.02 |
| `STRATEGY_MIN_BUY_PRICE` | 最低买入价格 | `0.15` | 0.10 - 0.25 |
| `STRATEGY_HEDGE_SPREAD` | 对冲触发价差 | `0.05` | 0.03 - 0.10 |
| `STRATEGY_MAX_POSITION` | 最大仓位 (USDC) | `100.0` | 根据资金调整 |
| `STRATEGY_POLL_INTERVAL` | 监控间隔 (毫秒) | `500` | 200 - 1000 |

## 策略参数说明

### 累计买入目标 (sum_target)

控制总体仓位大小。值越小越保守。

- **0.3 (保守)**: 只用 30% 的最大仓位
- **0.5 (中等)**: 用 50% 的最大仓位
- **0.8 (激进)**: 用 80% 的最大仓位

### 下跌触发阈值 (move_threshold)

价格从高点下跌多少开始监控。

- **0.005 (敏感)**: 0.5% 下跌就开始关注
- **0.01 (标准)**: 1% 下跌开始关注
- **0.02 (保守)**: 2% 下跌才开始关注

### 最低买入价格 (min_buy_price)

只有价格低于此值才考虑买入。

- **0.10**: 极端保守，只在价格很低时买入
- **0.15**: 标准设置
- **0.25**: 更激进，价格较高时也会买入

### 对冲触发价差 (hedge_spread)

当前价格与买入均价的差值达到多少时触发对冲。

- **0.03**: 3% 的价差就对冲 (更快锁定小利润)
- **0.05**: 5% 的价差对冲 (标准)
- **0.10**: 10% 的价差对冲 (追求更大利润但风险更高)

## 如何获取 Token ID

### 方法一: 使用 Polymarket API

```bash
# 获取所有市场
curl https://gamma-api.polymarket.com/markets | jq '.[] | {
  question: .question,
  condition_id: .condition_id,
  tokens: .tokens
}'
```

### 方法二: 使用浏览器开发者工具

1. 访问 Polymarket 市场页面
2. 打开浏览器开发者工具 (F12)
3. 切换到 Network 标签
4. 刷新页面，查找包含 `token_id` 的响应

### 方法三: 使用 SDK 公共 API

```zig
const poly = @import("poly-sdk-zig");

var client = poly.ClobClient.init(allocator, .{});
defer client.deinit();

const markets = try client.getMarkets(.{});
defer markets.deinit();

for (markets.value) |market| {
    std.debug.print("Market: {s}\n", .{market.question});
    std.debug.print("Condition ID: {s}\n", .{market.condition_id});
    // tokens 包含 YES 和 NO 的 token_id
}
```

## 运行示例

### 成功运行输出

```
╔══════════════════════════════════════════════════════════════╗
║     BTC 二元期权对冲套利策略 - Polymarket Trading Bot        ║
╠══════════════════════════════════════════════════════════════╣
║  策略: 抄底 YES + 反弹对冲 NO                                 ║
║  目标: 捕捉短期暴跌,锁定无风险利润                           ║
╚══════════════════════════════════════════════════════════════╝

1. 加载配置...
   从 .env 文件加载了 15 个配置项
   网络: 主网 (Polygon)

2. 初始化钱包...
   钱包地址: 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045

3. 初始化 API 凭证...
   API 凭证初始化完成

4. 初始化 CLOB 客户端...
   客户端初始化完成

5. 检查账户余额...
   USDC 余额: 1000.00

6. 配置策略参数...
   累计目标: 30%
   下跌阈值: 1.0%
   最低买价: 0.15
   对冲价差: 0.05
   最大仓位: $100

7. 启动策略...
   按 Ctrl+C 停止

=== BTC 对冲策略启动 ===
[1735689600] YES价格: 0.4500 (均价: 0.0000, 持仓: 0.00)
[1735689601] 检测到暴跌! 当前价格: 0.1200
[1735689601] 准备买入 YES: 数量=100.00, 价格=0.1200
[1735689601] YES 买入成功! 订单ID: abc123...
[1735689610] YES价格: 0.2500 (均价: 0.1200, 持仓: 100.00)
[1735689610] 触发对冲! 当前价格: 0.2500, 买入均价: 0.1200
[1735689610] 对冲成功! 锁定利润: $13.00

=== 交易总结 ===
YES 持仓: 100.00 份
YES 成本: $12.00
YES 均价: 0.1200
是否对冲: true
锁定利润: $13.00
投资回报率: 108.3%
```

## 风险提示

1. **资金风险**: 这是真实交易代码，会涉及实际资金
2. **市场风险**: 二元期权市场波动剧烈，可能导致亏损
3. **技术风险**: 网络延迟、API 故障等可能影响交易执行
4. **策略风险**: 市场可能持续下跌，对冲时机可能错失

### 建议

- 先在测试网验证策略
- 从小额资金开始
- 设置合理的止损
- 监控策略运行状态
- 不要投入超过你能承受损失的资金

## 常见问题

### Q: 如何获取 API Key?

A: 可以通过以下方式获取:
1. 使用 SDK 的 L1 认证功能派生 API Key
2. 使用 Polymarket 官方客户端
3. 参考 `examples/authentication.zig` 示例

### Q: 测试网和主网有什么区别?

A: 
- **测试网 (Amoy)**: 使用测试代币，无真实资金风险，适合开发测试
- **主网 (Polygon)**: 使用真实 USDC，有资金风险，用于实际交易

### Q: 策略会自动平仓吗?

A: 
- 完成对冲后，你持有等量的 YES 和 NO 股份
- 期权到期时会自动结算
- 你也可以在到期前手动平仓

### Q: 如何修改策略参数?

A: 
1. 编辑 `.env` 文件中的 `STRATEGY_*` 参数
2. 或在代码中直接修改 `StrategyConfig` 结构

## 相关文档

- [SDK 快速开始](../README.md)
- [认证指南](../auth/README.md)
- [CLOB 客户端文档](../clob/client.md)
- [订单构建器文档](../order/builder.md)
