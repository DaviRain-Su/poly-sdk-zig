# poly-sdk-zig

**使用 Zig 在 Polymarket 上交易。** Polymarket CLOB API 的原生 Zig 客户端。

---

## 新闻稿

*即时发布*

**Polymarket 交易现已支持 Zig 开发者**

开发者现在可以使用 Zig 为 Polymarket 构建高性能交易机器人和应用程序。poly-sdk-zig 库提供类型安全的 Polymarket 预测市场访问，具有零成本抽象和编译时安全保证。

"我们构建这个是因为现有客户端只有 Python 和 Rust 版本。Zig 给我们 Rust 的性能，但工具更简单，没有隐藏的内存分配，"开发团队说。

核心优势：
- **类型安全**: 无效 API 使用会产生编译时错误
- **精确**: Decimal 类型用于精确的金融计算（无浮点误差）
- **显式**: 无隐藏分配，清晰的所有权语义
- **快速**: 零成本抽象，无运行时开销

---

## 常见问题

### 这是什么？

一个用于与 [Polymarket](https://polymarket.com)（世界最大的预测市场）交互的 Zig 库。你可以：
- 查询市场数据（价格、订单簿）
- 下单和管理订单
- 订阅实时更新（计划中）

### 为什么用 Zig 而不是 Python/Rust？

| 关注点 | Python | Rust | Zig |
|--------|--------|------|-----|
| 性能 | 慢 | 快 | 快 |
| 内存安全 | GC | 借用检查器 | 手动 + 工具 |
| 构建时间 | N/A | 慢 | 快 |
| 依赖 | 多 | 多 | 少 |
| 学习曲线 | 简单 | 陡峭 | 适中 |

Zig 是一个平衡点：像 Rust 一样快，但工具更简单，构建更快。

### 当前状态是什么？

🚧 **开发中** - 尚未准备好用于生产。

查看 [ROADMAP.md](./ROADMAP.md) 了解当前进度。

### 如何安装？

```zig
// build.zig.zon
.dependencies = .{
    .poly_sdk_zig = .{
        .url = "https://github.com/anthropics/poly-sdk-zig/archive/main.tar.gz",
        .hash = "...",
    },
},
```

### 如何使用？

```zig
const poly = @import("poly");

// 查询市场（无需认证）
var client = try poly.Client.init(allocator, .{});
defer client.deinit();

const markets = try client.markets(.{});
for (markets) |m| {
    std.debug.print("{s}\n", .{m.question});
}

// 下单（需要认证）
var auth = try client.authenticate(&signer);
try auth.postOrder(.{
    .token_id = "0x...",
    .side = .buy,
    .price = try poly.Decimal.fromString("0.65"),
    .size = try poly.Decimal.fromString("100"),
});
```

### 需要什么 Zig 版本？

Zig >= 0.15.2

### 哪里可以了解更多？

- [ROADMAP.md](./ROADMAP.md) - 开发计划
- [docs/](./docs/) - 文档
- [Polymarket API 文档](https://docs.polymarket.com)

---

## 快速链接

| 资源 | 描述 |
|------|------|
| [ROADMAP.md](./ROADMAP.md) | 唯一真相来源 - 版本规划 |
| [CHANGELOG.dev.md](./CHANGELOG.dev.md) | 开发日志 - 会话记录、进度追踪 |
| [stories/](./stories/) | 工作单元（Stories） |
| [AGENTS.md](./AGENTS.md) | AI 编码规范 |
| [docs/](./docs/) | 模块文档和设计决策 |

---

## 许可证

MIT
