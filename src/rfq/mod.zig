//! RFQ (Request for Quote) 模块
//!
//! 提供大宗交易询价功能。用户可以发起询价请求，
//! 做市商提供报价，用户选择最优报价执行交易。
//!
//! ## 使用示例
//!
//! ```zig
//! const poly = @import("poly-sdk-zig");
//!
//! // 通过 ClobClient 访问 RFQ
//! var client = poly.ClobClient.initWithAuth(allocator, .{}, &wallet, &creds);
//! defer client.deinit();
//!
//! // 创建 RFQ 请求
//! const request = try client.rfq().createRfqRequest(.{
//!     .asset_in = "USDC",
//!     .asset_out = token_id,
//!     .amount_in = "10000",
//! });
//!
//! // 获取最佳报价并接受
//! const best = try client.rfq().getRfqBestQuote(request.request_id);
//! try client.rfq().acceptRfqQuote(.{
//!     .request_id = request.request_id,
//!     .quote_id = best.quote_id,
//!     .expiration = std.time.timestamp() + 60,
//! });
//! ```
//!
//! ## 工作流程
//!
//! 1. 用户创建 RFQ 请求 (`createRfqRequest`)
//! 2. 做市商看到请求并创建报价 (`createRfqQuote`)
//! 3. 用户获取报价列表 (`getRfqQuotes`) 或最佳报价 (`getRfqBestQuote`)
//! 4. 用户接受报价 (`acceptRfqQuote`)
//! 5. 做市商批准订单 (`approveRfqOrder`)

const std = @import("std");

/// RFQ 类型定义
pub const types = @import("types.zig");

/// RFQ 客户端
pub const client = @import("client.zig");

// ============================================================================
// 类型导出
// ============================================================================

// 枚举类型
pub const RfqMatchType = types.RfqMatchType;
pub const RfqRequestState = types.RfqRequestState;
pub const RfqQuoteState = types.RfqQuoteState;

// 请求/报价类型
pub const RfqRequest = types.RfqRequest;
pub const RfqQuote = types.RfqQuote;

// 参数类型
pub const CreateRfqRequestParams = types.CreateRfqRequestParams;
pub const CreateRfqQuoteParams = types.CreateRfqQuoteParams;
pub const AcceptRfqQuoteParams = types.AcceptRfqQuoteParams;
pub const ApproveRfqOrderParams = types.ApproveRfqOrderParams;
pub const GetRfqRequestsParams = types.GetRfqRequestsParams;
pub const GetRfqQuotesParams = types.GetRfqQuotesParams;
pub const CancelRfqRequestParams = types.CancelRfqRequestParams;
pub const CancelRfqQuoteParams = types.CancelRfqQuoteParams;

// 响应类型
pub const RfqRequestResponse = types.RfqRequestResponse;
pub const RfqQuoteResponse = types.RfqQuoteResponse;
pub const PaginatedRfqRequests = types.PaginatedRfqRequests;
pub const PaginatedRfqQuotes = types.PaginatedRfqQuotes;
pub const AcceptRfqQuoteResponse = types.AcceptRfqQuoteResponse;
pub const ApproveRfqOrderResponse = types.ApproveRfqOrderResponse;
pub const CancelRfqResponse = types.CancelRfqResponse;
pub const RfqConfig = types.RfqConfig;

// 客户端类型
pub const RfqClient = client.RfqClient;
pub const RfqError = client.RfqError;
pub const Endpoints = client.Endpoints;

// ============================================================================
// 测试
// ============================================================================

test "rfq module exports" {
    // 测试枚举类型
    try std.testing.expectEqual(RfqMatchType.COMPLEMENTARY, RfqMatchType.fromString("COMPLEMENTARY").?);
    try std.testing.expectEqual(RfqRequestState.PENDING, RfqRequestState.fromString("PENDING").?);
    try std.testing.expectEqual(RfqQuoteState.ACCEPTED, RfqQuoteState.fromString("ACCEPTED").?);

    // 测试结构体类型
    const request = RfqRequest{
        .request_id = "req-123",
        .state = "PENDING",
    };
    try std.testing.expectEqualStrings("req-123", request.request_id);

    const quote = RfqQuote{
        .quote_id = "quote-456",
        .match_type = "COMPLEMENTARY",
    };
    try std.testing.expectEqualStrings("quote-456", quote.quote_id);
}

test "rfq parameter types" {
    const create_params = CreateRfqRequestParams{
        .asset_in = "USDC",
        .asset_out = "token-123",
        .amount_in = "10000",
    };
    try std.testing.expectEqualStrings("USDC", create_params.asset_in);

    const accept_params = AcceptRfqQuoteParams{
        .request_id = "req-123",
        .quote_id = "quote-456",
        .expiration = 1704067200,
    };
    try std.testing.expectEqual(@as(i64, 1704067200), accept_params.expiration);
}

test "rfq response types" {
    const response = AcceptRfqQuoteResponse{
        .success = true,
        .order_id = "order-789",
    };
    try std.testing.expect(response.success);
    try std.testing.expectEqualStrings("order-789", response.order_id.?);

    const config = RfqConfig{
        .min_request_amount = "1000",
        .enabled = true,
    };
    try std.testing.expect(config.enabled);
}

test "rfq endpoints" {
    try std.testing.expectEqualStrings("/rfq/request", Endpoints.RFQ_REQUEST);
    try std.testing.expectEqualStrings("/rfq/data/best-quote", Endpoints.RFQ_DATA_BEST_QUOTE);
}

test "all submodules" {
    _ = types;
    _ = client;
}
