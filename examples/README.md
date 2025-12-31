# 示例代码

本目录包含 poly-sdk-zig 的使用示例。

## 示例列表

| 文件 | 描述 | 需要认证 |
|------|------|----------|
| `basic_types.zig` | 基础类型使用（Decimal, Secret） | 否 |
| `read_only.zig` | 只读 API（市场、价格、订单簿） | 否 |
| `trading.zig` | 下单和管理订单 | 是 |

## 运行示例

```bash
# 编译并运行示例
zig build-exe examples/basic_types.zig -I src
./basic_types

# 或使用 zig run
zig run examples/basic_types.zig -I src
```

## 配置

需要认证的示例需要设置环境变量：

```bash
# 复制环境变量模板
cp .env.example .env

# 编辑 .env 填入你的配置
# POLYGON_WALLET_PRIVATE_KEY=你的私钥
```

## 注意事项

⚠️ **重要**：这些示例仅供学习使用。在生产环境中：

- 永远不要硬编码私钥
- 使用安全的密钥管理
- 从小额交易开始测试
- 了解 [Polymarket 服务条款](https://polymarket.com/tos)
