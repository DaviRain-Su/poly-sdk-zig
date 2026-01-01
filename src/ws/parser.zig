// WebSocket 消息解析器
//
// 解析 Polymarket WebSocket API 返回的 JSON 消息
// 支持所有 Market Channel 和 User Channel 消息类型

const std = @import("std");
const types = @import("types.zig");

const Allocator = std.mem.Allocator;

/// 解析错误
pub const ParseError = error{
    InvalidJson,
    MissingEventType,
    UnknownEventType,
    MissingRequiredField,
    OutOfMemory,
};

/// 解析结果
pub const ParseResult = union(enum) {
    book: types.BookMessage,
    price_change: types.PriceChangeMessage,
    last_trade_price: types.LastTradePriceMessage,
    best_bid_ask: types.BestBidAskMessage,
    tick_size_change: types.TickSizeChangeMessage,
    order: types.OrderMessage,
    trade: types.TradeMessage,
    pong: void,
    unknown: []const u8,
};

/// 带资源管理的解析结果
/// 调用者必须调用 deinit() 释放内存
pub const ParsedMessage = struct {
    result: ParseResult,
    /// 内部 JSON 解析句柄，用于释放内存
    _parsed: ?std.json.Parsed(std.json.Value),
    allocator: Allocator,

    const Self = @This();

    /// 释放解析结果占用的内存
    pub fn deinit(self: *Self) void {
        if (self._parsed) |*p| {
            p.deinit();
        }
    }

    /// 获取解析结果
    pub fn get(self: *const Self) ParseResult {
        return self.result;
    }
};

/// 消息解析器
pub const MessageParser = struct {
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return .{ .allocator = allocator };
    }

    /// 解析原始消息（返回带资源管理的结果）
    ///
    /// 调用者必须调用返回值的 deinit() 方法释放内存
    pub fn parseOwned(self: *Self, raw_message: []const u8) ParseError!ParsedMessage {
        // 检查 PONG 响应
        if (std.mem.eql(u8, raw_message, "PONG")) {
            return ParsedMessage{
                .result = .{ .pong = {} },
                ._parsed = null,
                .allocator = self.allocator,
            };
        }

        // 尝试解析 JSON
        const parsed = std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            raw_message,
            .{},
        ) catch return ParseError.InvalidJson;
        // 不要 defer deinit，让调用者负责

        const root = parsed.value;

        // 获取事件类型
        const event_type_value = root.object.get("event_type") orelse {
            return ParsedMessage{
                .result = .{ .unknown = raw_message },
                ._parsed = parsed,
                .allocator = self.allocator,
            };
        };

        const event_type_str = switch (event_type_value) {
            .string => |s| s,
            else => {
                var p = parsed;
                p.deinit();
                return ParseError.MissingEventType;
            },
        };

        // 根据事件类型解析
        const event_type = types.EventType.fromString(event_type_str) orelse {
            return ParsedMessage{
                .result = .{ .unknown = raw_message },
                ._parsed = parsed,
                .allocator = self.allocator,
            };
        };

        const result = switch (event_type) {
            .book => self.parseBookMessage(root),
            .price_change => self.parsePriceChangeMessage(root),
            .last_trade_price => self.parseLastTradePriceMessage(root),
            .best_bid_ask => self.parseBestBidAskMessage(root),
            .tick_size_change => self.parseTickSizeChangeMessage(root),
            .order => self.parseOrderMessage(root),
            .trade => self.parseTradeMessage(root),
            .new_market, .market_resolved => ParseResult{ .unknown = raw_message },
        } catch |err| {
            var p = parsed;
            p.deinit();
            return err;
        };

        return ParsedMessage{
            .result = result,
            ._parsed = parsed,
            .allocator = self.allocator,
        };
    }

    /// 解析原始消息（旧 API，用于简单场景）
    /// 警告：返回的字符串指针可能在解析器内部内存释放后失效
    /// 推荐使用 parseOwned() 代替
    pub fn parse(self: *Self, raw_message: []const u8) ParseError!ParseResult {
        const owned = try self.parseOwned(raw_message);
        // 注意：这里不调用 deinit()，因为我们要返回结果
        // 这意味着内存会泄漏，但这是旧 API 的行为
        // 新代码应该使用 parseOwned()
        return owned.result;
    }

    /// 解析 Book 消息
    fn parseBookMessage(_: *Self, root: std.json.Value) ParseError!ParseResult {
        const obj = root.object;

        const asset_id = getStringField(obj, "asset_id") orelse return ParseError.MissingRequiredField;
        const market = getStringField(obj, "market") orelse return ParseError.MissingRequiredField;
        const timestamp = getStringField(obj, "timestamp") orelse return ParseError.MissingRequiredField;

        // 解析 bids 和 asks
        // 注意：这里返回空切片，完整解析需要分配内存
        // 实际使用时建议使用 JSON 直接反序列化到具体类型
        const bids: []const types.BookLevel = &.{};
        const asks: []const types.BookLevel = &.{};

        _ = obj.get("bids"); // 标记为已使用
        _ = obj.get("asks"); // 标记为已使用

        return .{
            .book = .{
                .asset_id = asset_id,
                .market = market,
                .bids = bids,
                .asks = asks,
                .timestamp = timestamp,
                .hash = getStringField(obj, "hash"),
            },
        };
    }

    /// 解析 Price Change 消息
    fn parsePriceChangeMessage(_: *Self, root: std.json.Value) ParseError!ParseResult {
        const obj = root.object;

        const market = getStringField(obj, "market") orelse return ParseError.MissingRequiredField;
        const timestamp = getStringField(obj, "timestamp") orelse return ParseError.MissingRequiredField;

        return .{
            .price_change = .{
                .market = market,
                .price_changes = &.{}, // 需要实际解析 price_changes 数组
                .timestamp = timestamp,
            },
        };
    }

    /// 解析 Last Trade Price 消息
    fn parseLastTradePriceMessage(_: *Self, root: std.json.Value) ParseError!ParseResult {
        const obj = root.object;

        const asset_id = getStringField(obj, "asset_id") orelse return ParseError.MissingRequiredField;
        const market = getStringField(obj, "market") orelse return ParseError.MissingRequiredField;
        const price = getStringField(obj, "price") orelse return ParseError.MissingRequiredField;
        const size = getStringField(obj, "size") orelse return ParseError.MissingRequiredField;
        const side = getStringField(obj, "side") orelse return ParseError.MissingRequiredField;
        const timestamp = getStringField(obj, "timestamp") orelse return ParseError.MissingRequiredField;

        return .{
            .last_trade_price = .{
                .asset_id = asset_id,
                .market = market,
                .price = price,
                .size = size,
                .side = side,
                .fee_rate_bps = getStringField(obj, "fee_rate_bps"),
                .timestamp = timestamp,
            },
        };
    }

    /// 解析 Best Bid Ask 消息
    fn parseBestBidAskMessage(_: *Self, root: std.json.Value) ParseError!ParseResult {
        const obj = root.object;

        const asset_id = getStringField(obj, "asset_id") orelse return ParseError.MissingRequiredField;
        const market = getStringField(obj, "market") orelse return ParseError.MissingRequiredField;
        const best_bid = getStringField(obj, "best_bid") orelse return ParseError.MissingRequiredField;
        const best_ask = getStringField(obj, "best_ask") orelse return ParseError.MissingRequiredField;
        const timestamp = getStringField(obj, "timestamp") orelse return ParseError.MissingRequiredField;

        return .{
            .best_bid_ask = .{
                .asset_id = asset_id,
                .market = market,
                .best_bid = best_bid,
                .best_ask = best_ask,
                .spread = getStringField(obj, "spread"),
                .timestamp = timestamp,
            },
        };
    }

    /// 解析 Tick Size Change 消息
    fn parseTickSizeChangeMessage(_: *Self, root: std.json.Value) ParseError!ParseResult {
        const obj = root.object;

        const asset_id = getStringField(obj, "asset_id") orelse return ParseError.MissingRequiredField;
        const market = getStringField(obj, "market") orelse return ParseError.MissingRequiredField;
        const old_tick_size = getStringField(obj, "old_tick_size") orelse return ParseError.MissingRequiredField;
        const new_tick_size = getStringField(obj, "new_tick_size") orelse return ParseError.MissingRequiredField;
        const timestamp = getStringField(obj, "timestamp") orelse return ParseError.MissingRequiredField;

        return .{
            .tick_size_change = .{
                .asset_id = asset_id,
                .market = market,
                .old_tick_size = old_tick_size,
                .new_tick_size = new_tick_size,
                .timestamp = timestamp,
            },
        };
    }

    /// 解析 Order 消息
    fn parseOrderMessage(_: *Self, root: std.json.Value) ParseError!ParseResult {
        const obj = root.object;

        const id = getStringField(obj, "id") orelse return ParseError.MissingRequiredField;
        const asset_id = getStringField(obj, "asset_id") orelse return ParseError.MissingRequiredField;
        const market = getStringField(obj, "market") orelse return ParseError.MissingRequiredField;
        const order_type = getStringField(obj, "type") orelse return ParseError.MissingRequiredField;
        const side = getStringField(obj, "side") orelse return ParseError.MissingRequiredField;
        const price = getStringField(obj, "price") orelse return ParseError.MissingRequiredField;
        const original_size = getStringField(obj, "original_size") orelse return ParseError.MissingRequiredField;
        const size_matched = getStringField(obj, "size_matched") orelse return ParseError.MissingRequiredField;
        const timestamp = getStringField(obj, "timestamp") orelse return ParseError.MissingRequiredField;

        return .{
            .order = .{
                .id = id,
                .asset_id = asset_id,
                .market = market,
                .type = order_type,
                .side = side,
                .price = price,
                .original_size = original_size,
                .size_matched = size_matched,
                .outcome = getStringField(obj, "outcome"),
                .owner = getStringField(obj, "owner"),
                .order_owner = getStringField(obj, "order_owner"),
                .timestamp = timestamp,
                .associate_trades = getStringField(obj, "associate_trades"),
            },
        };
    }

    /// 解析 Trade 消息
    fn parseTradeMessage(_: *Self, root: std.json.Value) ParseError!ParseResult {
        const obj = root.object;

        const id = getStringField(obj, "id") orelse return ParseError.MissingRequiredField;
        const asset_id = getStringField(obj, "asset_id") orelse return ParseError.MissingRequiredField;
        const market = getStringField(obj, "market") orelse return ParseError.MissingRequiredField;
        const status = getStringField(obj, "status") orelse return ParseError.MissingRequiredField;
        const side = getStringField(obj, "side") orelse return ParseError.MissingRequiredField;
        const price = getStringField(obj, "price") orelse return ParseError.MissingRequiredField;
        const size = getStringField(obj, "size") orelse return ParseError.MissingRequiredField;
        const timestamp = getStringField(obj, "timestamp") orelse return ParseError.MissingRequiredField;

        return .{
            .trade = .{
                .id = id,
                .asset_id = asset_id,
                .market = market,
                .status = status,
                .side = side,
                .price = price,
                .size = size,
                .outcome = getStringField(obj, "outcome"),
                .owner = getStringField(obj, "owner"),
                .trade_owner = getStringField(obj, "trade_owner"),
                .taker_order_id = getStringField(obj, "taker_order_id"),
                .maker_orders = null,
                .matchtime = getStringField(obj, "matchtime"),
                .last_update = getStringField(obj, "last_update"),
                .timestamp = timestamp,
                .type = getStringField(obj, "type"),
            },
        };
    }
};

/// 从对象获取字符串字段
fn getStringField(obj: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const value = obj.get(key) orelse return null;
    return switch (value) {
        .string => |s| s,
        else => null,
    };
}

// ============================================================================
// 便捷函数
// ============================================================================

/// 快速检测消息类型
pub fn detectEventType(raw_message: []const u8) ?types.EventType {
    if (std.mem.eql(u8, raw_message, "PONG")) {
        return null; // PONG 不是事件类型
    }

    // 查找 "event_type" 字段
    const event_type_key = "\"event_type\":\"";
    const start = std.mem.indexOf(u8, raw_message, event_type_key) orelse return null;
    const value_start = start + event_type_key.len;

    const end = std.mem.indexOfPos(u8, raw_message, value_start, "\"") orelse return null;
    const event_type_str = raw_message[value_start..end];

    return types.EventType.fromString(event_type_str);
}

/// 检查是否是 PONG 响应
pub fn isPong(raw_message: []const u8) bool {
    return std.mem.eql(u8, raw_message, "PONG");
}

/// 提取 asset_id 字段（快速方式，不完整解析）
pub fn extractAssetId(raw_message: []const u8) ?[]const u8 {
    const key = "\"asset_id\":\"";
    const start = std.mem.indexOf(u8, raw_message, key) orelse return null;
    const value_start = start + key.len;

    const end = std.mem.indexOfPos(u8, raw_message, value_start, "\"") orelse return null;
    return raw_message[value_start..end];
}

/// 提取 market 字段（快速方式，不完整解析）
pub fn extractMarket(raw_message: []const u8) ?[]const u8 {
    const key = "\"market\":\"";
    const start = std.mem.indexOf(u8, raw_message, key) orelse return null;
    const value_start = start + key.len;

    const end = std.mem.indexOfPos(u8, raw_message, value_start, "\"") orelse return null;
    return raw_message[value_start..end];
}

// ============================================================================
// 测试
// ============================================================================

test "isPong" {
    try std.testing.expect(isPong("PONG"));
    try std.testing.expect(!isPong("PING"));
    try std.testing.expect(!isPong("{\"event_type\":\"book\"}"));
}

test "detectEventType" {
    try std.testing.expectEqual(
        types.EventType.book,
        detectEventType("{\"event_type\":\"book\",\"asset_id\":\"123\"}").?,
    );
    try std.testing.expectEqual(
        types.EventType.price_change,
        detectEventType("{\"event_type\":\"price_change\",\"market\":\"0x123\"}").?,
    );
    try std.testing.expectEqual(
        types.EventType.order,
        detectEventType("{\"event_type\":\"order\",\"id\":\"abc\"}").?,
    );
    try std.testing.expectEqual(
        types.EventType.trade,
        detectEventType("{\"event_type\":\"trade\",\"status\":\"MATCHED\"}").?,
    );
    try std.testing.expect(detectEventType("PONG") == null);
    try std.testing.expect(detectEventType("invalid") == null);
}

test "extractAssetId" {
    const msg = "{\"event_type\":\"book\",\"asset_id\":\"123456789\",\"market\":\"0xabc\"}";
    try std.testing.expectEqualStrings("123456789", extractAssetId(msg).?);
}

test "extractMarket" {
    const msg = "{\"event_type\":\"book\",\"asset_id\":\"123\",\"market\":\"0xabcdef\"}";
    try std.testing.expectEqualStrings("0xabcdef", extractMarket(msg).?);
}

test "MessageParser.parseOwned PONG" {
    var parser = MessageParser.init(std.testing.allocator);
    var result = try parser.parseOwned("PONG");
    defer result.deinit();
    try std.testing.expect(result.result == .pong);
}

test "MessageParser.parseOwned book message" {
    var msg_parser = MessageParser.init(std.testing.allocator);

    const json =
        \\{"event_type":"book","asset_id":"123","market":"0xabc","bids":[],"asks":[],"timestamp":"1234567890"}
    ;

    var result = try msg_parser.parseOwned(json);
    defer result.deinit();

    try std.testing.expect(result.result == .book);
    const book = result.result.book;
    try std.testing.expectEqualStrings("123", book.asset_id);
    try std.testing.expectEqualStrings("0xabc", book.market);
    try std.testing.expectEqualStrings("1234567890", book.timestamp);
}

test "MessageParser.parseOwned last_trade_price message" {
    var msg_parser = MessageParser.init(std.testing.allocator);

    const json =
        \\{"event_type":"last_trade_price","asset_id":"123","market":"0xabc","price":"0.5","size":"100","side":"BUY","timestamp":"1234567890"}
    ;

    var result = try msg_parser.parseOwned(json);
    defer result.deinit();

    try std.testing.expect(result.result == .last_trade_price);
    const ltp = result.result.last_trade_price;
    try std.testing.expectEqualStrings("123", ltp.asset_id);
    try std.testing.expectEqualStrings("0.5", ltp.price);
}

test "MessageParser.parseOwned order message" {
    var msg_parser = MessageParser.init(std.testing.allocator);

    const json =
        \\{"event_type":"order","id":"order-123","asset_id":"asset-456","market":"0xmarket","type":"PLACEMENT","side":"SELL","price":"0.65","original_size":"50","size_matched":"0","timestamp":"1234567890"}
    ;

    var result = try msg_parser.parseOwned(json);
    defer result.deinit();

    try std.testing.expect(result.result == .order);
    const order = result.result.order;
    try std.testing.expectEqualStrings("order-123", order.id);
}

test "MessageParser.parseOwned trade message" {
    var msg_parser = MessageParser.init(std.testing.allocator);

    const json =
        \\{"event_type":"trade","id":"trade-789","asset_id":"asset-456","market":"0xmarket","status":"MATCHED","side":"BUY","price":"0.55","size":"25","timestamp":"1234567890"}
    ;

    var result = try msg_parser.parseOwned(json);
    defer result.deinit();

    try std.testing.expect(result.result == .trade);
    const trade = result.result.trade;
    try std.testing.expectEqualStrings("trade-789", trade.id);
}

test "MessageParser.parseOwned unknown event type" {
    var msg_parser = MessageParser.init(std.testing.allocator);

    const json =
        \\{"event_type":"unknown_type","data":"test"}
    ;

    var result = try msg_parser.parseOwned(json);
    defer result.deinit();

    try std.testing.expect(result.result == .unknown);
}

test "MessageParser.parseOwned invalid json" {
    var msg_parser = MessageParser.init(std.testing.allocator);
    const result = msg_parser.parseOwned("not valid json {");
    try std.testing.expectError(ParseError.InvalidJson, result);
}

test "MessageParser.parseOwned best_bid_ask message" {
    var msg_parser = MessageParser.init(std.testing.allocator);

    const json =
        \\{"event_type":"best_bid_ask","asset_id":"123","market":"0xabc","best_bid":"0.48","best_ask":"0.52","spread":"0.04","timestamp":"1234567890"}
    ;

    var result = try msg_parser.parseOwned(json);
    defer result.deinit();

    try std.testing.expect(result.result == .best_bid_ask);
    const bba = result.result.best_bid_ask;
    try std.testing.expectEqualStrings("0.48", bba.best_bid);
    try std.testing.expectEqualStrings("0.52", bba.best_ask);
}
