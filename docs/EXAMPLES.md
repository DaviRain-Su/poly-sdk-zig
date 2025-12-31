# 示例和使用指南

本文档提供 Polymarket Zig CLOB Client SDK 的详细使用示例。

## 目录

- [1. 快速开始](#1-快速开始)
- [2. 基础示例](#2-基础示例)
- [3. 认证示例](#3-认证示例)
- [4. 订单操作](#4-订单操作)
- [5. 市场数据](#5-市场数据)
- [6. 高级用法](#6-高级用法)

---

## 1. 快速开始

### 1.1 安装

在 `build.zig.zon` 中添加依赖：

```zig
.{
    .name = "my-trading-bot",
    .version = "0.1.0",
    .dependencies = .{
        .poly_sdk = .{
            .url = "https://github.com/yourusername/poly-sdk-zig/archive/v0.1.0.tar.gz",
            .hash = "...",
        },
    },
}
```

在 `build.zig` 中配置：

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const poly_sdk = b.dependency("poly_sdk", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "trading-bot",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("poly", poly_sdk.module("poly_sdk"));

    b.installArtifact(exe);
}
```

### 1.2 Hello World

```zig
const std = @import("std");
const poly = @import("poly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建客户端
    var client = try poly.Client.init(allocator, .{});
    defer client.deinit();

    // 检查服务状态
    const status = try client.ok();
    std.debug.print("Server status: {s}\n", .{status});

    // 获取服务器时间
    const time = try client.serverTime();
    std.debug.print("Server time: {d}\n", .{time});
}
```

---

## 2. 基础示例

### 2.1 获取市场列表

```zig
const std = @import("std");
const poly = @import("poly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = try poly.Client.init(allocator, .{});
    defer client.deinit();

    // 获取第一页市场
    var markets = try client.markets(null);
    
    std.debug.print("Found {d} markets\n", .{markets.count});
    
    for (markets.data) |market| {
        std.debug.print("Market: {s}\n", .{market.question});
        std.debug.print("  Condition ID: {s}\n", .{market.condition_id});
        std.debug.print("  Active: {}\n", .{market.active});
        std.debug.print("  Tokens:\n", .{});
        
        for (market.tokens) |token| {
            std.debug.print("    - {s}: {s}\n", .{token.outcome, token.token_id});
        }
        std.debug.print("\n", .{});
    }

    // 获取下一页
    if (!std.mem.eql(u8, markets.next_cursor, "LTE=")) {
        const next_markets = try client.markets(markets.next_cursor);
        std.debug.print("Next page has {d} markets\n", .{next_markets.count});
    }
}
```

### 2.2 获取价格信息

```zig
const std = @import("std");
const poly = @import("poly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = try poly.Client.init(allocator, .{});
    defer client.deinit();

    const token_id = "your-token-id-here";

    // 获取中间价
    const midpoint = try client.midpoint(.{ .token_id = token_id });
    std.debug.print("Midpoint: {}\n", .{midpoint.mid.toFloat()});

    // 获取买卖价格
    const buy_price = try client.price(.{
        .token_id = token_id,
        .side = .buy,
    });
    const sell_price = try client.price(.{
        .token_id = token_id,
        .side = .sell,
    });
    std.debug.print("Buy price: {}\n", .{buy_price.price.toFloat()});
    std.debug.print("Sell price: {}\n", .{sell_price.price.toFloat()});

    // 获取价差
    const spread = try client.spread(.{ .token_id = token_id });
    std.debug.print("Spread: {}\n", .{spread.spread.toFloat()});
}
```

### 2.3 获取订单簿

```zig
const std = @import("std");
const poly = @import("poly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = try poly.Client.init(allocator, .{});
    defer client.deinit();

    const token_id = "your-token-id-here";

    const book = try client.orderBook(.{ .token_id = token_id });

    std.debug.print("Order Book for {s}\n", .{book.asset_id});
    std.debug.print("Timestamp: {d}\n\n", .{book.timestamp});

    std.debug.print("=== ASKS (Sell Orders) ===\n", .{});
    std.debug.print("{s:>10} | {s:>12}\n", .{ "Price", "Size" });
    std.debug.print("{s:-<10}-+-{s:-<12}\n", .{ "", "" });
    
    // 显示前 10 个卖单（从低到高）
    const asks_to_show = @min(book.asks.len, 10);
    var i: usize = 0;
    while (i < asks_to_show) : (i += 1) {
        const ask = book.asks[book.asks.len - 1 - i];
        std.debug.print("{d:>10.4} | {d:>12.2}\n", .{
            ask.price.toFloat(),
            ask.size.toFloat(),
        });
    }

    std.debug.print("\n=== BIDS (Buy Orders) ===\n", .{});
    std.debug.print("{s:>10} | {s:>12}\n", .{ "Price", "Size" });
    std.debug.print("{s:-<10}-+-{s:-<12}\n", .{ "", "" });
    
    // 显示前 10 个买单（从高到低）
    const bids_to_show = @min(book.bids.len, 10);
    i = 0;
    while (i < bids_to_show) : (i += 1) {
        const bid = book.bids[i];
        std.debug.print("{d:>10.4} | {d:>12.2}\n", .{
            bid.price.toFloat(),
            bid.size.toFloat(),
        });
    }
}
```

---

## 3. 认证示例

### 3.1 基础认证

```zig
const std = @import("std");
const poly = @import("poly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 从环境变量获取私钥
    const private_key = std.posix.getenv("POLYMARKET_PRIVATE_KEY") orelse {
        std.log.err("POLYMARKET_PRIVATE_KEY environment variable not set", .{});
        return error.MissingPrivateKey;
    };

    // 创建签名器
    var signer = try poly.LocalSigner.fromHex(private_key);
    signer = signer.withChainId(poly.POLYGON);  // Polygon 主网

    // 创建并认证客户端
    var client = try poly.Client.init(allocator, .{});
    defer client.deinit();

    var auth_client = try client.authenticate(&signer, .{});
    defer auth_client.deinit();

    // 现在可以访问认证 API
    const api_keys = try auth_client.apiKeys();
    std.debug.print("API Keys:\n", .{});
    for (api_keys.api_keys) |key| {
        std.debug.print("  - {s} (created: {s})\n", .{ key.api_key, key.created_at });
    }
}
```

### 3.2 使用 Proxy 钱包

```zig
const std = @import("std");
const poly = @import("poly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const private_key = std.posix.getenv("POLYMARKET_PRIVATE_KEY") orelse 
        return error.MissingPrivateKey;
    const funder_address = std.posix.getenv("POLYMARKET_FUNDER_ADDRESS") orelse 
        return error.MissingFunderAddress;

    var signer = try poly.LocalSigner.fromHex(private_key);
    signer = signer.withChainId(poly.POLYGON);

    const funder = try poly.Address.fromHex(funder_address);

    var client = try poly.Client.init(allocator, .{});
    defer client.deinit();

    // 使用 Proxy 签名类型认证
    var auth_client = try client.authenticate(&signer, .{
        .funder = funder,
        .signature_type = .proxy,
    });
    defer auth_client.deinit();

    std.debug.print("Authenticated with proxy wallet\n", .{});
    std.debug.print("Signer: {s}\n", .{try poly.Address.toHex(signer.address(), allocator)});
    std.debug.print("Funder: {s}\n", .{funder_address});
}
```

### 3.3 使用现有凭证

```zig
const std = @import("std");
const poly = @import("poly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 从存储加载凭证
    const credentials = poly.Credentials{
        .key = try poly.Uuid.fromString("your-api-key-uuid"),
        .secret = poly.Secret([]const u8).init("your-secret-base64"),
        .passphrase = poly.Secret([]const u8).init("your-passphrase"),
    };

    const private_key = std.posix.getenv("POLYMARKET_PRIVATE_KEY") orelse 
        return error.MissingPrivateKey;

    var signer = try poly.LocalSigner.fromHex(private_key);
    signer = signer.withChainId(poly.POLYGON);

    var client = try poly.Client.init(allocator, .{});
    defer client.deinit();

    // 使用现有凭证认证
    var auth_client = try client.authenticate(&signer, .{
        .credentials = credentials,
    });
    defer auth_client.deinit();

    std.debug.print("Authenticated with existing credentials\n", .{});
}
```

---

## 4. 订单操作

### 4.1 创建限价单

```zig
const std = @import("std");
const poly = @import("poly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 认证设置（省略）
    var signer = // ...
    var auth_client = // ...

    const token_id = "your-token-id";

    // 创建限价买单
    const order = try auth_client.limitOrder()
        .tokenId(token_id)
        .price(poly.Decimal.fromFloat(0.65))   // 价格 $0.65
        .size(poly.Decimal.fromFloat(100.0))   // 数量 100 份
        .side(.buy)
        .orderType(.gtc)  // Good 'til Cancelled
        .build();

    std.debug.print("Order built:\n", .{});
    std.debug.print("  Token ID: {d}\n", .{order.order.token_id});
    std.debug.print("  Maker Amount: {d}\n", .{order.order.maker_amount});
    std.debug.print("  Taker Amount: {d}\n", .{order.order.taker_amount});

    // 签名订单
    const signed_order = try auth_client.sign(&signer, order);

    // 提交订单
    const response = try auth_client.postOrder(signed_order);

    for (response) |r| {
        std.debug.print("Order response:\n", .{});
        std.debug.print("  Order ID: {s}\n", .{r.order_id});
        std.debug.print("  Status: {s}\n", .{r.status});
        if (r.error_msg) |msg| {
            std.debug.print("  Error: {s}\n", .{msg});
        }
    }
}
```

### 4.2 创建市价单

```zig
const std = @import("std");
const poly = @import("poly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 认证设置（省略）
    var signer = // ...
    var auth_client = // ...

    const token_id = "your-token-id";

    // 创建市价买单 - 花费 $100 USDC 购买
    const buy_order = try auth_client.marketOrder()
        .tokenId(token_id)
        .amount(try poly.Amount.usdc(poly.Decimal.fromFloat(100.0)))
        .side(.buy)
        .orderType(.fok)  // Fill or Kill
        .build();

    // 创建市价卖单 - 卖出 50 份
    const sell_order = try auth_client.marketOrder()
        .tokenId(token_id)
        .amount(try poly.Amount.shares(poly.Decimal.fromFloat(50.0)))
        .side(.sell)
        .orderType(.fak)  // Fill and Kill (允许部分成交)
        .build();

    // 签名并提交
    const signed_buy = try auth_client.sign(&signer, buy_order);
    const buy_response = try auth_client.postOrder(signed_buy);

    std.debug.print("Buy order submitted: {s}\n", .{buy_response[0].order_id});
}
```

### 4.3 批量下单

```zig
const std = @import("std");
const poly = @import("poly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 认证设置（省略）
    var signer = // ...
    var auth_client = // ...

    const token_id = "your-token-id";

    // 创建多个订单（预分配容量）
    const buy_prices = [_]f64{ 0.60, 0.61, 0.62, 0.63, 0.64 };
    var orders = try std.ArrayList(poly.SignedOrder).initCapacity(allocator, buy_prices.len);
    defer orders.deinit();

    // 买单梯队
    for (buy_prices) |price| {
        const order = try auth_client.limitOrder()
            .tokenId(token_id)
            .price(poly.Decimal.fromFloat(price))
            .size(poly.Decimal.fromFloat(20.0))
            .side(.buy)
            .orderType(.gtc)
            .build();

        const signed = try auth_client.sign(&signer, order);
        // Zig 0.15: append 需要传入 allocator
        try orders.append(allocator, signed);
    }

    // 批量提交
    const responses = try auth_client.postOrders(orders.items);

    std.debug.print("Submitted {d} orders:\n", .{responses.len});
    for (responses) |r| {
        std.debug.print("  {s}: {s}\n", .{ r.order_id, r.status });
    }
}
```

### 4.4 取消订单

```zig
const std = @import("std");
const poly = @import("poly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 认证设置（省略）
    var auth_client = // ...

    // 取消单个订单
    const order_id = "your-order-id";
    const cancel_result = try auth_client.cancelOrder(order_id);
    std.debug.print("Canceled: {d} orders\n", .{cancel_result.canceled.len});

    // 取消多个订单
    const order_ids = [_][]const u8{
        "order-id-1",
        "order-id-2",
        "order-id-3",
    };
    const batch_result = try auth_client.cancelOrders(&order_ids);
    std.debug.print("Batch canceled: {d} orders\n", .{batch_result.canceled.len});

    // 取消所有订单
    const all_result = try auth_client.cancelAllOrders();
    std.debug.print("Canceled all: {d} orders\n", .{all_result.canceled.len});

    // 取消特定市场的订单
    const market_result = try auth_client.cancelMarketOrders(.{
        .market = "your-condition-id",
    });
    std.debug.print("Market orders canceled: {d}\n", .{market_result.canceled.len});
}
```

### 4.5 查询订单

```zig
const std = @import("std");
const poly = @import("poly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 认证设置（省略）
    var auth_client = // ...

    // 查询单个订单
    const order_id = "your-order-id";
    const order = try auth_client.order(order_id);
    std.debug.print("Order {s}:\n", .{order.id});
    std.debug.print("  Status: {}\n", .{order.status});
    std.debug.print("  Side: {}\n", .{order.side});
    std.debug.print("  Price: {}\n", .{order.price.toFloat()});
    std.debug.print("  Original Size: {}\n", .{order.original_size.toFloat()});
    std.debug.print("  Size Matched: {}\n", .{order.size_matched.toFloat()});

    // 查询所有活跃订单
    const orders = try auth_client.orders(.{
        .state = .live,
    }, null);
    std.debug.print("\nActive orders: {d}\n", .{orders.count});

    for (orders.data) |o| {
        std.debug.print("  {s}: {s} {} @ {}\n", .{
            o.id,
            o.outcome,
            o.side,
            o.price.toFloat(),
        });
    }
}
```

---

## 5. 市场数据

### 5.1 获取交易历史

```zig
const std = @import("std");
const poly = @import("poly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 认证设置（省略）
    var auth_client = // ...

    // 获取最近交易
    const trades = try auth_client.trades(.{}, null);

    std.debug.print("Recent trades: {d}\n", .{trades.count});
    for (trades.data) |trade| {
        std.debug.print("Trade {s}:\n", .{trade.id});
        std.debug.print("  Market: {s}\n", .{trade.market});
        std.debug.print("  Side: {}\n", .{trade.side});
        std.debug.print("  Price: {}\n", .{trade.price.toFloat()});
        std.debug.print("  Size: {}\n", .{trade.size.toFloat()});
        std.debug.print("  Time: {s}\n", .{trade.match_time});
        std.debug.print("  Role: {}\n", .{trade.trader_side});
        std.debug.print("\n", .{});
    }

    // 获取特定市场的交易
    const market_trades = try auth_client.trades(.{
        .market = "your-condition-id",
    }, null);
    std.debug.print("Market trades: {d}\n", .{market_trades.count});
}
```

### 5.2 检查地理限制

```zig
const std = @import("std");
const poly = @import("poly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = try poly.Client.init(allocator, .{});
    defer client.deinit();

    const geoblock = try client.checkGeoblock();

    if (geoblock.blocked) {
        std.debug.print("Access BLOCKED\n", .{});
        std.debug.print("  IP: {s}\n", .{geoblock.ip});
        std.debug.print("  Country: {s}\n", .{geoblock.country});
        std.debug.print("  Region: {s}\n", .{geoblock.region});
    } else {
        std.debug.print("Access allowed from {s}, {s}\n", .{
            geoblock.region,
            geoblock.country,
        });
    }
}
```

### 5.3 查询余额

```zig
const std = @import("std");
const poly = @import("poly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 认证设置（省略）
    var auth_client = // ...

    // 查询 USDC 余额
    const collateral = try auth_client.balanceAllowance(.{
        .asset_type = .collateral,
    });
    std.debug.print("USDC Balance: {}\n", .{collateral.balance.toFloat()});
    std.debug.print("USDC Allowance: {}\n", .{collateral.allowance.toFloat()});

    // 查询特定代币余额
    const token_id = "your-token-id";
    const conditional = try auth_client.balanceAllowance(.{
        .asset_type = .conditional,
        .token_id = token_id,
    });
    std.debug.print("Token Balance: {}\n", .{conditional.balance.toFloat()});
    std.debug.print("Token Allowance: {}\n", .{conditional.allowance.toFloat()});
}
```

---

## 6. 高级用法

### 6.1 流式获取数据

```zig
const std = @import("std");
const poly = @import("poly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = try poly.Client.init(allocator, .{});
    defer client.deinit();

    // 流式获取所有市场
    std.debug.print("Streaming all markets...\n", .{});
    
    var count: u32 = 0;
    var cursor: ?[]const u8 = null;
    
    while (true) {
        const page = try client.markets(cursor);
        
        for (page.data) |market| {
            count += 1;
            std.debug.print("[{d}] {s}\n", .{ count, market.question });
        }
        
        if (std.mem.eql(u8, page.next_cursor, "LTE=")) {
            break;
        }
        cursor = page.next_cursor;
    }
    
    std.debug.print("\nTotal markets: {d}\n", .{count});
}
```

### 6.2 做市策略示例

```zig
const std = @import("std");
const poly = @import("poly");

const MarketMaker = struct {
    allocator: std.mem.Allocator,
    client: *poly.Client(.authenticated),
    signer: *poly.LocalSigner,
    token_id: []const u8,
    spread: f64,
    size: f64,
    active_orders: std.ArrayList([]const u8),

    pub fn init(
        allocator: std.mem.Allocator,
        client: *poly.Client(.authenticated),
        signer: *poly.LocalSigner,
        token_id: []const u8,
        spread: f64,
        size: f64,
    ) !MarketMaker {
        // 做市商通常只有 2 个活跃订单（买单 + 卖单）
        var active_orders = try std.ArrayList([]const u8).initCapacity(allocator, 2);
        
        return .{
            .allocator = allocator,
            .client = client,
            .signer = signer,
            .token_id = token_id,
            .spread = spread,
            .size = size,
            .active_orders = active_orders,
        };
    }

    pub fn deinit(self: *MarketMaker) void {
        self.active_orders.deinit();
    }

    pub fn updateQuotes(self: *MarketMaker) !void {
        // 取消现有订单
        if (self.active_orders.items.len > 0) {
            _ = try self.client.cancelOrders(self.active_orders.items);
            self.active_orders.clearRetainingCapacity();
        }

        // 获取中间价
        const midpoint = try self.client.midpoint(.{ .token_id = self.token_id });
        const mid = midpoint.mid.toFloat();

        // 计算买卖价
        const half_spread = self.spread / 2.0;
        const bid_price = mid - half_spread;
        const ask_price = mid + half_spread;

        // 下买单
        if (bid_price > 0.0) {
            const bid_order = try self.client.limitOrder()
                .tokenId(self.token_id)
                .price(poly.Decimal.fromFloat(bid_price))
                .size(poly.Decimal.fromFloat(self.size))
                .side(.buy)
                .orderType(.gtc)
                .build();

            const signed_bid = try self.client.sign(self.signer, bid_order);
            const bid_response = try self.client.postOrder(signed_bid);
            // Zig 0.15: append 需要传入 allocator
            try self.active_orders.append(self.allocator, bid_response[0].order_id);
        }

        // 下卖单
        if (ask_price < 1.0) {
            const ask_order = try self.client.limitOrder()
                .tokenId(self.token_id)
                .price(poly.Decimal.fromFloat(ask_price))
                .size(poly.Decimal.fromFloat(self.size))
                .side(.sell)
                .orderType(.gtc)
                .build();

            const signed_ask = try self.client.sign(self.signer, ask_order);
            const ask_response = try self.client.postOrder(signed_ask);
            // Zig 0.15: append 需要传入 allocator
            try self.active_orders.append(self.allocator, ask_response[0].order_id);
        }

        std.debug.print("Updated quotes: bid={d:.4}, ask={d:.4}\n", .{ bid_price, ask_price });
    }

    pub fn run(self: *MarketMaker, interval_ms: u64) !void {
        std.debug.print("Starting market maker for {s}\n", .{self.token_id});
        std.debug.print("Spread: {d:.4}, Size: {d:.2}\n", .{ self.spread, self.size });

        while (true) {
            self.updateQuotes() catch |err| {
                std.log.err("Failed to update quotes: {}", .{err});
            };
            std.time.sleep(interval_ms * std.time.ns_per_ms);
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 设置认证...
    var signer = // ...
    var auth_client = // ...

    var mm = try MarketMaker.init(
        allocator,
        &auth_client,
        &signer,
        "your-token-id",
        0.02,   // 2% spread
        100.0,  // 100 shares per side
    );
    defer mm.deinit();

    try mm.run(5000);  // 每 5 秒更新一次
}
```

### 6.3 Builder 认证

```zig
const std = @import("std");
const poly = @import("poly");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 普通认证
    var signer = // ...
    var client = try poly.Client.init(allocator, .{});
    defer client.deinit();

    var auth_client = try client.authenticate(&signer, .{});
    defer auth_client.deinit();

    // 创建 Builder API 密钥
    const builder_credentials = try auth_client.createBuilderApiKey();
    std.debug.print("Builder API Key: {s}\n", .{builder_credentials.key});

    // 升级到 Builder 客户端
    var builder_client = try auth_client.promoteToBuilder(.{
        .local = builder_credentials,
    });
    defer builder_client.deinit();

    // 使用 Builder API
    const builder_trades = try builder_client.builderTrades(.{}, null);
    std.debug.print("Builder trades: {d}\n", .{builder_trades.count});
}
```
