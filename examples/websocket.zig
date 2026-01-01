//! WebSocket 实时数据示例
//!
//! 演示如何使用 WebSocket 模块订阅实时市场数据和用户订单更新。
//!
//! 支持两种频道:
//! - Market Channel: 公开市场数据（无需认证）
//! - User Channel: 用户私有数据（需要 API 凭证）
//!
//! 注意: 此示例需要网络连接到 Polymarket WebSocket 服务器。
//!
//! 运行: zig build run-websocket

const std = @import("std");
const poly = @import("poly_sdk_zig");

// 导入模块
const ws = poly.ws;

// ============================================================================
// 回调函数定义
// ============================================================================

/// 处理订单簿快照
fn onBookUpdate(book: ws.BookMessage) void {
    std.debug.print("[BOOK] Asset: {s}\n", .{book.asset_id});
    std.debug.print("  Bids: {d} levels, Asks: {d} levels\n", .{ book.bids.len, book.asks.len });

    // 显示最优买卖价
    if (book.bids.len > 0) {
        std.debug.print("  Best Bid: {s} @ {s}\n", .{ book.bids[0].size, book.bids[0].price });
    }
    if (book.asks.len > 0) {
        std.debug.print("  Best Ask: {s} @ {s}\n", .{ book.asks[0].size, book.asks[0].price });
    }
    std.debug.print("\n", .{});
}

/// 处理价格变化
fn onPriceChange(change: ws.PriceChangeMessage) void {
    std.debug.print("[PRICE_CHANGE] Market: {s}\n", .{change.market});
    std.debug.print("  Changes: {d}\n\n", .{change.changes.len});
}

/// 处理最新成交价
fn onLastTradePrice(msg: ws.LastTradePriceMessage) void {
    std.debug.print("[LAST_TRADE] Asset: {s}, Price: {s}\n\n", .{ msg.asset_id, msg.price });
}

/// 处理最佳买卖价
fn onBestBidAsk(msg: ws.BestBidAskMessage) void {
    std.debug.print("[BEST_BID_ASK] Market: {s}\n", .{msg.market});
    if (msg.best_bid) |bid| {
        std.debug.print("  Best Bid: {s} @ {s}\n", .{ bid.size, bid.price });
    }
    if (msg.best_ask) |ask| {
        std.debug.print("  Best Ask: {s} @ {s}\n", .{ ask.size, ask.price });
    }
    std.debug.print("\n", .{});
}

/// 处理订单更新 (User Channel)
fn onOrderUpdate(order: ws.OrderMessage) void {
    std.debug.print("[ORDER] ID: {s}\n", .{order.id});
    std.debug.print("  Type: {s}, Side: {s}\n", .{ order.type, order.side });
    std.debug.print("  Price: {s}, Size: {s}\n", .{ order.price, order.original_size });
    std.debug.print("  Matched: {s}\n\n", .{order.size_matched});
}

/// 处理交易更新 (User Channel)
fn onTradeUpdate(trade: ws.TradeMessage) void {
    std.debug.print("[TRADE] ID: {s}\n", .{trade.id});
    std.debug.print("  Status: {s}, Side: {s}\n", .{ trade.status, trade.side });
    std.debug.print("  Price: {s}, Size: {s}\n\n", .{ trade.price, trade.size });
}

/// 处理错误
fn onError(err: anyerror) void {
    std.debug.print("[ERROR] {}\n\n", .{err});
}

/// 处理连接状态变化
fn onConnection(connected: bool) void {
    if (connected) {
        std.debug.print("[CONNECTION] Connected to WebSocket\n\n", .{});
    } else {
        std.debug.print("[CONNECTION] Disconnected from WebSocket\n\n", .{});
    }
}

// ============================================================================
// 示例入口
// ============================================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Polymarket WebSocket 示例 ===\n\n", .{});

    // ========================================================================
    // 1. WebSocket 端点信息
    // ========================================================================

    std.debug.print("1. WebSocket 端点\n", .{});
    std.debug.print("   Market Channel: {s}\n", .{ws.Endpoints.marketUrl()});
    std.debug.print("   User Channel:   {s}\n\n", .{ws.Endpoints.userUrl()});

    // ========================================================================
    // 2. Market Channel 示例（公开数据，无需认证）
    // ========================================================================

    std.debug.print("2. Market Channel (公开市场数据)\n", .{});
    std.debug.print("   用途: 订阅订单簿、价格变化、成交等公开数据\n", .{});
    std.debug.print("   认证: 无需\n\n", .{});

    std.debug.print("   示例代码:\n", .{});
    std.debug.print("   ```zig\n", .{});
    std.debug.print("   var market = try ws.MarketChannel.init(allocator, .{{\n", .{});
    std.debug.print("       .on_book = onBookUpdate,\n", .{});
    std.debug.print("       .on_price_change = onPriceChange,\n", .{});
    std.debug.print("       .on_last_trade_price = onLastTradePrice,\n", .{});
    std.debug.print("       .on_best_bid_ask = onBestBidAsk,\n", .{});
    std.debug.print("       .on_error = onError,\n", .{});
    std.debug.print("       .on_connection = onConnection,\n", .{});
    std.debug.print("       .custom_feature_enabled = true,  // 启用 best_bid_ask\n", .{});
    std.debug.print("   }});\n", .{});
    std.debug.print("   defer market.deinit();\n", .{});
    std.debug.print("   \n", .{});
    std.debug.print("   try market.connect();\n", .{});
    std.debug.print("   try market.subscribe(&.{{ \"token_id_1\", \"token_id_2\" }});\n", .{});
    std.debug.print("   try market.run();  // 阻塞，处理消息\n", .{});
    std.debug.print("   ```\n\n", .{});

    // ========================================================================
    // 3. User Channel 示例（私有数据，需要认证）
    // ========================================================================

    std.debug.print("3. User Channel (用户私有数据)\n", .{});
    std.debug.print("   用途: 订阅用户的订单状态和交易更新\n", .{});
    std.debug.print("   认证: 需要 API Key, Secret, Passphrase\n\n", .{});

    std.debug.print("   示例代码:\n", .{});
    std.debug.print("   ```zig\n", .{});
    std.debug.print("   var user = try ws.UserChannel.init(allocator, .{{\n", .{});
    std.debug.print("       .api_key = \"your-api-key\",\n", .{});
    std.debug.print("       .api_secret = \"your-api-secret\",\n", .{});
    std.debug.print("       .api_passphrase = \"your-passphrase\",\n", .{});
    std.debug.print("       .on_order = onOrderUpdate,\n", .{});
    std.debug.print("       .on_trade = onTradeUpdate,\n", .{});
    std.debug.print("       .on_error = onError,\n", .{});
    std.debug.print("       .on_connection = onConnection,\n", .{});
    std.debug.print("   }});\n", .{});
    std.debug.print("   defer user.deinit();\n", .{});
    std.debug.print("   \n", .{});
    std.debug.print("   // 传入 condition_id (市场 ID)\n", .{});
    std.debug.print("   try user.connect(&.{{ \"condition_id_1\" }});\n", .{});
    std.debug.print("   try user.run();  // 阻塞，处理消息\n", .{});
    std.debug.print("   ```\n\n", .{});

    // ========================================================================
    // 4. 低级 API 示例
    // ========================================================================

    std.debug.print("4. 低级 WebSocket API\n", .{});
    std.debug.print("   用途: 更细粒度的控制，手动处理消息\n\n", .{});

    std.debug.print("   示例代码:\n", .{});
    std.debug.print("   ```zig\n", .{});
    std.debug.print("   var client = try ws.WebSocketClient.init(allocator, ws.Endpoints.marketUrl());\n", .{});
    std.debug.print("   defer client.deinit();\n", .{});
    std.debug.print("   \n", .{});
    std.debug.print("   try client.connect();\n", .{});
    std.debug.print("   \n", .{});
    std.debug.print("   // 手动构建订阅消息\n", .{});
    std.debug.print("   const msg = try ws.serializeMarketSubscribe(allocator, &.{{\"token_id\"}}, false);\n", .{});
    std.debug.print("   defer allocator.free(msg);\n", .{});
    std.debug.print("   try client.send(msg);\n", .{});
    std.debug.print("   \n", .{});
    std.debug.print("   // 手动接收和解析消息\n", .{});
    std.debug.print("   while (true) {{\n", .{});
    std.debug.print("       if (try client.receive()) |raw_msg| {{\n", .{});
    std.debug.print("           defer allocator.free(raw_msg);\n", .{});
    std.debug.print("           \n", .{});
    std.debug.print("           // 检查消息类型\n", .{});
    std.debug.print("           if (ws.isPong(raw_msg)) {{\n", .{});
    std.debug.print("               continue;  // 忽略心跳响应\n", .{});
    std.debug.print("           }}\n", .{});
    std.debug.print("           \n", .{});
    std.debug.print("           // 解析消息\n", .{});
    std.debug.print("           if (ws.detectEventType(raw_msg)) |event_type| {{\n", .{});
    std.debug.print("               switch (event_type) {{\n", .{});
    std.debug.print("                   .book => std.debug.print(\"Book update\\n\", .{{}}),\n", .{});
    std.debug.print("                   .price_change => std.debug.print(\"Price change\\n\", .{{}}),\n", .{});
    std.debug.print("                   else => {{}},\n", .{});
    std.debug.print("               }}\n", .{});
    std.debug.print("           }}\n", .{});
    std.debug.print("       }}\n", .{});
    std.debug.print("   }}\n", .{});
    std.debug.print("   ```\n\n", .{});

    // ========================================================================
    // 5. 消息解析示例
    // ========================================================================

    std.debug.print("5. 消息解析\n", .{});
    std.debug.print("   使用 MessageParser 完整解析消息\n\n", .{});

    std.debug.print("   示例代码:\n", .{});
    std.debug.print("   ```zig\n", .{});
    std.debug.print("   var parser = ws.MessageParser.init(allocator);\n", .{});
    std.debug.print("   \n", .{});
    std.debug.print("   const result = try parser.parse(raw_message);\n", .{});
    std.debug.print("   switch (result) {{\n", .{});
    std.debug.print("       .book => |msg| {{\n", .{});
    std.debug.print("           std.debug.print(\"Book: {{s}}\\n\", .{{msg.asset_id}});\n", .{});
    std.debug.print("       }},\n", .{});
    std.debug.print("       .price_change => |msg| {{\n", .{});
    std.debug.print("           std.debug.print(\"Price change: {{s}}\\n\", .{{msg.market}});\n", .{});
    std.debug.print("       }},\n", .{});
    std.debug.print("       .order => |msg| {{\n", .{});
    std.debug.print("           std.debug.print(\"Order: {{s}}\\n\", .{{msg.id}});\n", .{});
    std.debug.print("       }},\n", .{});
    std.debug.print("       .trade => |msg| {{\n", .{});
    std.debug.print("           std.debug.print(\"Trade: {{s}}\\n\", .{{msg.id}});\n", .{});
    std.debug.print("       }},\n", .{});
    std.debug.print("       .pong => {{}},\n", .{});
    std.debug.print("       .unknown => |raw| {{\n", .{});
    std.debug.print("           std.debug.print(\"Unknown: {{s}}\\n\", .{{raw}});\n", .{});
    std.debug.print("       }},\n", .{});
    std.debug.print("   }}\n", .{});
    std.debug.print("   ```\n\n", .{});

    // ========================================================================
    // 6. 消息类型汇总
    // ========================================================================

    std.debug.print("=== 消息类型汇总 ===\n\n", .{});

    std.debug.print("Market Channel 消息:\n", .{});
    std.debug.print("  - book            订单簿快照 (首次订阅、成交后)\n", .{});
    std.debug.print("  - price_change    价格层级变化 (下单、取消)\n", .{});
    std.debug.print("  - last_trade_price 最新成交价\n", .{});
    std.debug.print("  - best_bid_ask    最佳买卖价 (需启用 custom_feature)\n", .{});
    std.debug.print("  - tick_size_change 最小价格间隔变化\n\n", .{});

    std.debug.print("User Channel 消息:\n", .{});
    std.debug.print("  - order           订单状态 (PLACEMENT/UPDATE/CANCELLATION)\n", .{});
    std.debug.print("  - trade           交易状态 (MATCHED/MINED/CONFIRMED/FAILED)\n\n", .{});

    // ========================================================================
    // 7. 配置选项
    // ========================================================================

    std.debug.print("=== 配置选项 ===\n\n", .{});

    std.debug.print("MarketChannelOptions:\n", .{});
    std.debug.print("  .custom_feature_enabled  启用 best_bid_ask (默认 false)\n", .{});
    std.debug.print("  .auto_reconnect          自动重连 (默认 true)\n", .{});
    std.debug.print("  .max_reconnect_attempts  最大重试次数 (默认 5)\n", .{});
    std.debug.print("  .reconnect_delay_ms      重连延迟 (默认 1000ms)\n", .{});
    std.debug.print("  .heartbeat_interval_ms   心跳间隔 (默认 10000ms)\n\n", .{});

    std.debug.print("UserChannelOptions:\n", .{});
    std.debug.print("  .api_key                 API Key (必填)\n", .{});
    std.debug.print("  .api_secret              API Secret (必填)\n", .{});
    std.debug.print("  .api_passphrase          API Passphrase (必填)\n", .{});
    std.debug.print("  .auto_reconnect          自动重连 (默认 true)\n", .{});
    std.debug.print("  .heartbeat_interval_ms   心跳间隔 (默认 10000ms)\n\n", .{});

    // ========================================================================
    // 8. 注意事项
    // ========================================================================

    std.debug.print("=== 注意事项 ===\n\n", .{});
    std.debug.print("1. 心跳: 必须每 10 秒发送 PING，否则连接会被关闭\n", .{});
    std.debug.print("   高级 API (MarketChannel/UserChannel) 自动处理心跳\n\n", .{});
    std.debug.print("2. 重连: 建议启用 auto_reconnect 处理网络问题\n\n", .{});
    std.debug.print("3. 内存: 低级 API 接收的消息需要调用者释放\n\n", .{});
    std.debug.print("4. 安全: User Channel 的 API 凭证不要硬编码在代码中\n\n", .{});
    std.debug.print("5. Token ID vs Condition ID:\n", .{});
    std.debug.print("   - Market Channel 订阅使用 token_id (资产 ID)\n", .{});
    std.debug.print("   - User Channel 订阅使用 condition_id (市场 ID)\n\n", .{});

    // 演示消息解析（使用模拟数据）
    std.debug.print("=== 演示: 解析模拟消息 ===\n\n", .{});

    // 模拟 book 消息
    const book_json =
        \\{"event_type":"book","asset_id":"12345","market":"0xabc","bids":[{"price":"0.50","size":"100"}],"asks":[{"price":"0.55","size":"50"}],"timestamp":"1234567890","hash":"0xdef"}
    ;

    std.debug.print("输入 (book):\n{s}\n\n", .{book_json});

    // 使用快速检测
    if (ws.detectEventType(book_json)) |event_type| {
        std.debug.print("检测到事件类型: {s}\n", .{@tagName(event_type)});
    }

    if (ws.extractAssetId(book_json)) |asset_id| {
        std.debug.print("提取的 asset_id: {s}\n", .{asset_id});
    }

    if (ws.extractMarket(book_json)) |market_id| {
        std.debug.print("提取的 market: {s}\n\n", .{market_id});
    }

    // 使用完整解析器
    var parser = ws.MessageParser.init(allocator);
    const result = parser.parse(book_json) catch |err| {
        std.debug.print("解析错误: {}\n", .{err});
        return;
    };

    switch (result) {
        .book => |book| {
            std.debug.print("完整解析结果:\n", .{});
            std.debug.print("  event_type: {s}\n", .{book.event_type});
            std.debug.print("  asset_id: {s}\n", .{book.asset_id});
            std.debug.print("  bids: {d} levels\n", .{book.bids.len});
            std.debug.print("  asks: {d} levels\n", .{book.asks.len});
        },
        else => {},
    }

    std.debug.print("\n=== 完成 ===\n", .{});
}
