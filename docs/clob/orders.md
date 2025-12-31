# 订单管理 API

> ClobClient 的订单管理功能

## 概述

ClobClient 提供完整的订单管理功能，包括：

- 订单发布（单个/批量）
- 订单查询
- 订单取消
- 交易历史
- 余额查询

所有订单管理 API 需要 L2 认证。

## 快速开始

```zig
const poly = @import("poly-sdk-zig");

// 创建钱包
const wallet = try poly.Wallet.fromPrivateKeyHex("0x...");

// 创建 API 凭证
var creds = try poly.ApiCreds.init(allocator, "api_key", "api_secret", "passphrase");
defer creds.deinit();

// 创建认证客户端
var client = poly.ClobClient.initWithAuth(allocator, .{
    .chain_id = 137,
}, &wallet, &creds);
defer client.deinit();

// 创建并发布订单
const response = try client.createAndPostOrder(.{
    .token_id = "12345",
    .price = try poly.Decimal.fromString("0.65"),
    .size = try poly.Decimal.fromString("100"),
    .side = .BUY,
}, .{
    .tick_size = .@"0.01",
}, .GTC);

if (response.success) {
    std.debug.print("Order ID: {s}\n", .{response.orderID.?});
}
```

## API

### postOrder

发布单个订单。

```zig
pub fn postOrder(
    self: *ClobClient,
    order: *const SignedOrder,
    order_type: types.OrderType,
) !types.PostOrderResponse
```

**参数**:
- `order`: 已签名的订单
- `order_type`: 订单类型 (GTC, GTD, FOK, FAK)

**返回**: `PostOrderResponse`

### getOpenOrders

查询开放订单。

```zig
pub fn getOpenOrders(
    self: *ClobClient, 
    params: types.OpenOrdersParams
) !std.json.Parsed(types.PaginatedOrders)
```

**参数**:
- `id`: 按订单 ID 过滤
- `market`: 按市场 ID 过滤
- `asset_id`: 按资产 ID 过滤
- `next_cursor`: 分页游标

### getOrder

获取单个订单详情。

```zig
pub fn getOrder(
    self: *ClobClient, 
    order_id: []const u8
) !std.json.Parsed(types.OpenOrder)
```

### cancelOrder

取消单个订单。

```zig
pub fn cancelOrder(
    self: *ClobClient, 
    order_id: []const u8
) !types.CancelOrderResponse
```

### cancelOrders

批量取消订单。

```zig
pub fn cancelOrders(
    self: *ClobClient, 
    order_ids: []const []const u8
) !types.CancelOrderResponse
```

### cancelAll

取消所有开放订单。

```zig
pub fn cancelAll(self: *ClobClient) !types.CancelOrderResponse
```

### getTrades

查询交易历史。

```zig
pub fn getTrades(
    self: *ClobClient, 
    params: types.TradesParams
) !std.json.Parsed(types.PaginatedTrades)
```

### getBalanceAllowance

查询余额和授权额度。

```zig
pub fn getBalanceAllowance(
    self: *ClobClient, 
    params: types.BalanceAllowanceParams
) !types.BalanceAllowanceResponse
```

### createOrder

创建订单（不发布）。

```zig
pub fn createOrder(
    self: *ClobClient,
    args: OrderArgs,
    options: CreateOrderOptions,
) !SignedOrder
```

### createAndPostOrder

创建并发布订单（便捷方法）。

```zig
pub fn createAndPostOrder(
    self: *ClobClient,
    args: OrderArgs,
    options: CreateOrderOptions,
    order_type: types.OrderType,
) !types.PostOrderResponse
```

## 类型

### OrderType

```zig
pub const OrderType = enum {
    GTC,  // Good Till Cancelled
    GTD,  // Good Till Date
    FOK,  // Fill Or Kill
    FAK,  // Fill And Kill
};
```

### PostOrderResponse

```zig
pub const PostOrderResponse = struct {
    success: bool,
    errorMsg: ?[]const u8,
    orderID: ?[]const u8,
    transactionsHashes: ?[]const []const u8,
};
```

### OpenOrder

```zig
pub const OpenOrder = struct {
    id: []const u8,
    status: ?[]const u8,
    owner: ?[]const u8,
    market: ?[]const u8,
    asset_id: ?[]const u8,
    side: ?[]const u8,
    original_size: ?[]const u8,
    size_matched: ?[]const u8,
    price: ?[]const u8,
    // ...
};
```

## 分页

使用游标分页获取大量数据：

```zig
var cursor: ?[]const u8 = null;

while (true) {
    const result = try client.getOpenOrders(.{ .next_cursor = cursor });
    defer result.deinit();
    
    for (result.value.data) |order| {
        // 处理订单
    }
    
    cursor = result.value.next_cursor;
    if (cursor == null or std.mem.eql(u8, cursor.?, types.END_CURSOR)) {
        break;
    }
}
```

## 错误处理

```zig
const response = client.postOrder(&order, .GTC) catch |err| {
    switch (err) {
        Error.Unauthorized => std.debug.print("需要认证\n", .{}),
        Error.BadRequest => std.debug.print("无效订单\n", .{}),
        Error.RateLimited => std.debug.print("请求过多\n", .{}),
        else => std.debug.print("错误: {}\n", .{err}),
    }
    return err;
};

if (!response.success) {
    std.debug.print("订单失败: {s}\n", .{response.errorMsg orelse "未知错误"});
}
```

## 注意事项

1. **认证**: 所有订单管理 API 需要 L2 认证
2. **签名**: 订单需要 EIP-712 签名
3. **链 ID**: 确保 chain_id 与网络匹配 (137=主网, 80002=测试网)
4. **费率**: 检查市场费率设置
5. **余额**: 发布订单前确保有足够余额

## 相关文档

- [OrderBuilder](../order/builder.md) - 订单构建
- [认证](../auth/README.md) - L2 认证
- [类型](../design/types.md) - 完整类型定义
