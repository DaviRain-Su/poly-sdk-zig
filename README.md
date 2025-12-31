# poly-sdk-zig

**Trade on Polymarket with Zig.** A native Zig client for the Polymarket CLOB API.

---

## Press Release

*FOR IMMEDIATE RELEASE*

**Polymarket Trading Now Available for Zig Developers**

Developers can now build high-performance trading bots and applications for Polymarket using Zig. The poly-sdk-zig library provides type-safe access to Polymarket's prediction markets with zero-cost abstractions and compile-time safety guarantees.

"We built this because existing clients are in Python and Rust. Zig gives us the performance of Rust with simpler tooling and no hidden allocations," said the development team.

Key benefits:
- **Type-safe**: Compile-time errors for invalid API usage
- **Precise**: Decimal type for exact financial calculations (no floating-point errors)
- **Explicit**: No hidden allocations, clear ownership semantics
- **Fast**: Zero-cost abstractions, no runtime overhead

---

## FAQ

### What is this?

A Zig library to interact with [Polymarket](https://polymarket.com), the world's largest prediction market. You can:
- Query market data (prices, order books)
- Place and manage orders
- Subscribe to real-time updates (planned)

### Why Zig instead of Python/Rust?

| Concern | Python | Rust | Zig |
|---------|--------|------|-----|
| Performance | Slow | Fast | Fast |
| Memory safety | GC | Borrow checker | Manual + tools |
| Build time | N/A | Slow | Fast |
| Dependencies | Many | Many | Minimal |
| Learning curve | Easy | Steep | Moderate |

Zig hits a sweet spot: fast like Rust, but simpler tooling and faster builds.

### What's the current status?

🚧 **Under Development** - Not ready for production.

See [ROADMAP.md](./ROADMAP.md) for current progress.

### How do I install it?

```zig
// build.zig.zon
.dependencies = .{
    .poly_sdk_zig = .{
        .url = "https://github.com/anthropics/poly-sdk-zig/archive/main.tar.gz",
        .hash = "...",
    },
},
```

### How do I use it?

```zig
const poly = @import("poly");

// Query markets (no auth required)
var client = try poly.Client.init(allocator, .{});
defer client.deinit();

const markets = try client.markets(.{});
for (markets) |m| {
    std.debug.print("{s}\n", .{m.question});
}

// Place orders (auth required)
var auth = try client.authenticate(&signer);
try auth.postOrder(.{
    .token_id = "0x...",
    .side = .buy,
    .price = try poly.Decimal.fromString("0.65"),
    .size = try poly.Decimal.fromString("100"),
});
```

### What Zig version do I need?

Zig >= 0.15.2

### Where can I learn more?

- [ROADMAP.md](./ROADMAP.md) - Development plan
- [docs/](./docs/) - Documentation
- [Polymarket API Docs](https://docs.polymarket.com)

---

## Quick Links

| Resource | Description |
|----------|-------------|
| [ROADMAP.md](./ROADMAP.md) | Source of Truth - what's planned |
| [stories/](./stories/) | Work units for contributors |
| [AGENTS.md](./AGENTS.md) | Coding guidelines |
| [docs/](./docs/) | Documentation |

---

## License

MIT
