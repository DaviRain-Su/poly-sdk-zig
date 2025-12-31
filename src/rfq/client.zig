//! RFQ (Request for Quote) 客户端
//!
//! RFQ 客户端是 ClobClient 的子客户端，用于处理大宗交易询价。
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
//! // 获取报价
//! const quotes = try client.rfq().getRfqQuotes(.{ .request_id = request.request_id });
//!
//! // 接受最佳报价
//! const best = try client.rfq().getRfqBestQuote(request.request_id);
//! try client.rfq().acceptRfqQuote(.{
//!     .request_id = request.request_id,
//!     .quote_id = best.quote_id,
//!     .expiration = std.time.timestamp() + 60,
//! });
//! ```

const std = @import("std");
const types = @import("types.zig");

/// RFQ API 端点
pub const Endpoints = struct {
    pub const RFQ_REQUEST = "/rfq/request";
    pub const RFQ_QUOTE = "/rfq/quote";
    pub const RFQ_DATA_REQUESTS = "/rfq/data/requests";
    pub const RFQ_DATA_QUOTES = "/rfq/data/quotes";
    pub const RFQ_DATA_BEST_QUOTE = "/rfq/data/best-quote";
    pub const RFQ_REQUEST_ACCEPT = "/rfq/request/accept";
    pub const RFQ_QUOTE_APPROVE = "/rfq/quote/approve";
    pub const RFQ_CONFIG = "/rfq/config";
};

/// RFQ 客户端错误
pub const RfqError = error{
    /// 未认证
    Unauthorized,
    /// 请求失败
    RequestFailed,
    /// JSON 解析失败
    InvalidJson,
    /// 内存不足
    OutOfMemory,
    /// 请求无效
    BadRequest,
    /// 未找到
    NotFound,
    /// 请求被限制
    RateLimited,
    /// 服务器错误
    ServerError,
};

/// RFQ 客户端
///
/// 通过 ClobClient.rfq() 方法获取实例。
/// 与主客户端共享认证和 HTTP 连接。
pub const RfqClient = struct {
    /// 分配器
    allocator: std.mem.Allocator,

    /// HTTP 客户端
    http_client: *std.http.Client,

    /// 基础 URL
    base_url: []const u8,

    /// L2 认证信息
    api_creds: ?*const @import("../auth/api_creds.zig").ApiCreds,

    const Self = @This();

    /// 初始化 RFQ 客户端
    ///
    /// 通常由 ClobClient 内部调用。
    pub fn init(
        allocator: std.mem.Allocator,
        http_client: *std.http.Client,
        base_url: []const u8,
        api_creds: ?*const @import("../auth/api_creds.zig").ApiCreds,
    ) Self {
        return Self{
            .allocator = allocator,
            .http_client = http_client,
            .base_url = base_url,
            .api_creds = api_creds,
        };
    }

    // =========================================================================
    // RFQ 请求端点
    // =========================================================================

    /// 创建 RFQ 请求 - POST /rfq/request
    ///
    /// 创建一个新的大宗交易询价请求。
    pub fn createRfqRequest(self: *Self, params: types.CreateRfqRequestParams) RfqError!types.RfqRequest {
        const json_body = std.json.stringifyAlloc(self.allocator, params, .{}) catch return RfqError.OutOfMemory;
        defer self.allocator.free(json_body);

        const response_body = self.doAuthPost(Endpoints.RFQ_REQUEST, json_body) catch return RfqError.RequestFailed;
        defer self.allocator.free(response_body);

        const parsed = std.json.parseFromSlice(types.RfqRequest, self.allocator, response_body, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        }) catch return RfqError.InvalidJson;
        defer parsed.deinit();

        return parsed.value;
    }

    /// 取消 RFQ 请求 - DELETE /rfq/request
    ///
    /// 取消一个待处理的询价请求。
    pub fn cancelRfqRequest(self: *Self, request_id: []const u8) RfqError!types.CancelRfqResponse {
        const request_body = .{ .requestId = request_id };

        const json_body = std.json.stringifyAlloc(self.allocator, request_body, .{}) catch return RfqError.OutOfMemory;
        defer self.allocator.free(json_body);

        const response_body = self.doAuthDelete(Endpoints.RFQ_REQUEST, json_body) catch return RfqError.RequestFailed;
        defer self.allocator.free(response_body);

        const parsed = std.json.parseFromSlice(types.CancelRfqResponse, self.allocator, response_body, .{
            .ignore_unknown_fields = true,
        }) catch return RfqError.InvalidJson;
        defer parsed.deinit();

        return parsed.value;
    }

    /// 获取 RFQ 请求列表 - GET /rfq/data/requests
    ///
    /// 获取当前用户的询价请求列表。
    pub fn getRfqRequests(self: *Self, params: types.GetRfqRequestsParams) RfqError!std.json.Parsed(types.PaginatedRfqRequests) {
        var path_buf: [512]u8 = undefined;
        var path_len: usize = 0;

        const base = Endpoints.RFQ_DATA_REQUESTS;
        @memcpy(path_buf[0..base.len], base);
        path_len = base.len;

        var has_params = false;

        if (params.market) |market| {
            path_buf[path_len] = if (has_params) '&' else '?';
            path_len += 1;
            const param = std.fmt.bufPrint(path_buf[path_len..], "market={s}", .{market}) catch return RfqError.BadRequest;
            path_len += param.len;
            has_params = true;
        }

        if (params.state) |state| {
            path_buf[path_len] = if (has_params) '&' else '?';
            path_len += 1;
            const param = std.fmt.bufPrint(path_buf[path_len..], "state={s}", .{state}) catch return RfqError.BadRequest;
            path_len += param.len;
            has_params = true;
        }

        if (params.limit) |limit| {
            path_buf[path_len] = if (has_params) '&' else '?';
            path_len += 1;
            const param = std.fmt.bufPrint(path_buf[path_len..], "limit={d}", .{limit}) catch return RfqError.BadRequest;
            path_len += param.len;
            has_params = true;
        }

        if (params.next_cursor) |cursor| {
            path_buf[path_len] = if (has_params) '&' else '?';
            path_len += 1;
            const param = std.fmt.bufPrint(path_buf[path_len..], "next_cursor={s}", .{cursor}) catch return RfqError.BadRequest;
            path_len += param.len;
        }

        const path = path_buf[0..path_len];
        const response_body = self.doAuthGet(path) catch return RfqError.RequestFailed;
        defer self.allocator.free(response_body);

        return std.json.parseFromSlice(types.PaginatedRfqRequests, self.allocator, response_body, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        }) catch RfqError.InvalidJson;
    }

    // =========================================================================
    // RFQ 报价端点
    // =========================================================================

    /// 创建 RFQ 报价 - POST /rfq/quote（做市商用）
    ///
    /// 做市商为询价请求创建报价。
    pub fn createRfqQuote(self: *Self, params: types.CreateRfqQuoteParams) RfqError!types.RfqQuote {
        const json_body = std.json.stringifyAlloc(self.allocator, params, .{}) catch return RfqError.OutOfMemory;
        defer self.allocator.free(json_body);

        const response_body = self.doAuthPost(Endpoints.RFQ_QUOTE, json_body) catch return RfqError.RequestFailed;
        defer self.allocator.free(response_body);

        const parsed = std.json.parseFromSlice(types.RfqQuote, self.allocator, response_body, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        }) catch return RfqError.InvalidJson;
        defer parsed.deinit();

        return parsed.value;
    }

    /// 取消 RFQ 报价 - DELETE /rfq/quote
    ///
    /// 取消一个待处理的报价。
    pub fn cancelRfqQuote(self: *Self, quote_id: []const u8) RfqError!types.CancelRfqResponse {
        const request_body = .{ .quoteId = quote_id };

        const json_body = std.json.stringifyAlloc(self.allocator, request_body, .{}) catch return RfqError.OutOfMemory;
        defer self.allocator.free(json_body);

        const response_body = self.doAuthDelete(Endpoints.RFQ_QUOTE, json_body) catch return RfqError.RequestFailed;
        defer self.allocator.free(response_body);

        const parsed = std.json.parseFromSlice(types.CancelRfqResponse, self.allocator, response_body, .{
            .ignore_unknown_fields = true,
        }) catch return RfqError.InvalidJson;
        defer parsed.deinit();

        return parsed.value;
    }

    /// 获取 RFQ 报价列表 - GET /rfq/data/quotes
    ///
    /// 获取询价请求的报价列表。
    pub fn getRfqQuotes(self: *Self, params: types.GetRfqQuotesParams) RfqError!std.json.Parsed(types.PaginatedRfqQuotes) {
        var path_buf: [512]u8 = undefined;
        var path_len: usize = 0;

        const base = Endpoints.RFQ_DATA_QUOTES;
        @memcpy(path_buf[0..base.len], base);
        path_len = base.len;

        var has_params = false;

        if (params.request_id) |request_id| {
            path_buf[path_len] = if (has_params) '&' else '?';
            path_len += 1;
            const param = std.fmt.bufPrint(path_buf[path_len..], "request_id={s}", .{request_id}) catch return RfqError.BadRequest;
            path_len += param.len;
            has_params = true;
        }

        if (params.market) |market| {
            path_buf[path_len] = if (has_params) '&' else '?';
            path_len += 1;
            const param = std.fmt.bufPrint(path_buf[path_len..], "market={s}", .{market}) catch return RfqError.BadRequest;
            path_len += param.len;
            has_params = true;
        }

        if (params.state) |state| {
            path_buf[path_len] = if (has_params) '&' else '?';
            path_len += 1;
            const param = std.fmt.bufPrint(path_buf[path_len..], "state={s}", .{state}) catch return RfqError.BadRequest;
            path_len += param.len;
            has_params = true;
        }

        if (params.limit) |limit| {
            path_buf[path_len] = if (has_params) '&' else '?';
            path_len += 1;
            const param = std.fmt.bufPrint(path_buf[path_len..], "limit={d}", .{limit}) catch return RfqError.BadRequest;
            path_len += param.len;
            has_params = true;
        }

        if (params.next_cursor) |cursor| {
            path_buf[path_len] = if (has_params) '&' else '?';
            path_len += 1;
            const param = std.fmt.bufPrint(path_buf[path_len..], "next_cursor={s}", .{cursor}) catch return RfqError.BadRequest;
            path_len += param.len;
        }

        const path = path_buf[0..path_len];
        const response_body = self.doAuthGet(path) catch return RfqError.RequestFailed;
        defer self.allocator.free(response_body);

        return std.json.parseFromSlice(types.PaginatedRfqQuotes, self.allocator, response_body, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        }) catch RfqError.InvalidJson;
    }

    /// 获取最佳报价 - GET /rfq/data/best-quote
    ///
    /// 获取指定请求的最佳报价。
    pub fn getRfqBestQuote(self: *Self, request_id: []const u8) RfqError!types.RfqQuote {
        var path_buf: [512]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "{s}?request_id={s}", .{ Endpoints.RFQ_DATA_BEST_QUOTE, request_id }) catch return RfqError.BadRequest;

        const response_body = self.doAuthGet(path) catch return RfqError.RequestFailed;
        defer self.allocator.free(response_body);

        const parsed = std.json.parseFromSlice(types.RfqQuote, self.allocator, response_body, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        }) catch return RfqError.InvalidJson;
        defer parsed.deinit();

        return parsed.value;
    }

    // =========================================================================
    // RFQ 交易端点
    // =========================================================================

    /// 接受 RFQ 报价 - POST /rfq/request/accept
    ///
    /// 用户接受做市商的报价。
    pub fn acceptRfqQuote(self: *Self, params: types.AcceptRfqQuoteParams) RfqError!types.AcceptRfqQuoteResponse {
        const json_body = std.json.stringifyAlloc(self.allocator, params, .{}) catch return RfqError.OutOfMemory;
        defer self.allocator.free(json_body);

        const response_body = self.doAuthPost(Endpoints.RFQ_REQUEST_ACCEPT, json_body) catch return RfqError.RequestFailed;
        defer self.allocator.free(response_body);

        const parsed = std.json.parseFromSlice(types.AcceptRfqQuoteResponse, self.allocator, response_body, .{
            .ignore_unknown_fields = true,
        }) catch return RfqError.InvalidJson;
        defer parsed.deinit();

        return parsed.value;
    }

    /// 批准 RFQ 订单 - POST /rfq/quote/approve（做市商用）
    ///
    /// 做市商批准已接受的订单。
    pub fn approveRfqOrder(self: *Self, quote_id: []const u8) RfqError!types.ApproveRfqOrderResponse {
        const request_body = .{ .quoteId = quote_id };

        const json_body = std.json.stringifyAlloc(self.allocator, request_body, .{}) catch return RfqError.OutOfMemory;
        defer self.allocator.free(json_body);

        const response_body = self.doAuthPost(Endpoints.RFQ_QUOTE_APPROVE, json_body) catch return RfqError.RequestFailed;
        defer self.allocator.free(response_body);

        const parsed = std.json.parseFromSlice(types.ApproveRfqOrderResponse, self.allocator, response_body, .{
            .ignore_unknown_fields = true,
        }) catch return RfqError.InvalidJson;
        defer parsed.deinit();

        return parsed.value;
    }

    // =========================================================================
    // RFQ 配置端点
    // =========================================================================

    /// 获取 RFQ 配置 - GET /rfq/config
    ///
    /// 获取 RFQ 系统的配置信息。
    pub fn getRfqConfig(self: *Self) RfqError!types.RfqConfig {
        const response_body = self.doAuthGet(Endpoints.RFQ_CONFIG) catch return RfqError.RequestFailed;
        defer self.allocator.free(response_body);

        const parsed = std.json.parseFromSlice(types.RfqConfig, self.allocator, response_body, .{
            .ignore_unknown_fields = true,
        }) catch return RfqError.InvalidJson;
        defer parsed.deinit();

        return parsed.value;
    }

    // =========================================================================
    // HTTP 辅助方法
    // =========================================================================

    /// 构建完整 URL
    fn buildUrl(self: *Self, path: []const u8) ![]u8 {
        return std.fmt.allocPrint(self.allocator, "{s}{s}", .{ self.base_url, path });
    }

    /// 执行认证 GET 请求
    fn doAuthGet(self: *Self, path: []const u8) ![]u8 {
        const creds = self.api_creds orelse return RfqError.Unauthorized;

        const url = try self.buildUrl(path);
        defer self.allocator.free(url);

        // 生成 L2 auth header
        const L2Auth = @import("../auth/l2.zig").L2Auth;
        const l2 = L2Auth.init(creds);
        const auth_header = l2.generateHeader(.{
            .method = "GET",
            .path = path,
            .body = null,
        }) catch return RfqError.Unauthorized;

        const poly_headers = auth_header.toHttpHeaders();

        const uri = std.Uri.parse(url) catch return RfqError.BadRequest;

        var req = self.http_client.request(.GET, uri, .{
            .extra_headers = &[_]std.http.Header{
                .{ .name = "Accept", .value = "application/json" },
                .{ .name = "User-Agent", .value = "poly-sdk-zig/0.1.0" },
                .{ .name = "Content-Type", .value = "application/json" },
                poly_headers[0],
                poly_headers[1],
                poly_headers[2],
                poly_headers[3],
            },
        }) catch return RfqError.RequestFailed;
        defer req.deinit();

        req.sendBodiless() catch return RfqError.RequestFailed;
        var response = req.receiveHead(&.{}) catch return RfqError.RequestFailed;

        const status_code = @intFromEnum(response.head.status);
        if (status_code >= 400) {
            if (status_code == 401) return RfqError.Unauthorized;
            if (status_code == 404) return RfqError.NotFound;
            if (status_code == 429) return RfqError.RateLimited;
            if (status_code >= 500) return RfqError.ServerError;
            return RfqError.RequestFailed;
        }

        var reader = response.reader(&.{});
        return reader.allocRemaining(self.allocator, std.Io.Limit.limited(10 * 1024 * 1024)) catch return RfqError.RequestFailed;
    }

    /// 执行认证 POST 请求
    fn doAuthPost(self: *Self, path: []const u8, body: []const u8) ![]u8 {
        const creds = self.api_creds orelse return RfqError.Unauthorized;

        const url = try self.buildUrl(path);
        defer self.allocator.free(url);

        const L2Auth = @import("../auth/l2.zig").L2Auth;
        const l2 = L2Auth.init(creds);
        const auth_header = l2.generateHeader(.{
            .method = "POST",
            .path = path,
            .body = body,
        }) catch return RfqError.Unauthorized;

        const poly_headers = auth_header.toHttpHeaders();

        const uri = std.Uri.parse(url) catch return RfqError.BadRequest;

        var req = self.http_client.request(.POST, uri, .{
            .extra_headers = &[_]std.http.Header{
                .{ .name = "Accept", .value = "application/json" },
                .{ .name = "User-Agent", .value = "poly-sdk-zig/0.1.0" },
                .{ .name = "Content-Type", .value = "application/json" },
                poly_headers[0],
                poly_headers[1],
                poly_headers[2],
                poly_headers[3],
            },
        }) catch return RfqError.RequestFailed;
        defer req.deinit();

        req.transfer_encoding = .{ .content_length = body.len };
        var body_writer = req.sendBodyUnflushed(&.{}) catch return RfqError.RequestFailed;
        body_writer.writer.writeAll(body) catch return RfqError.RequestFailed;
        body_writer.end() catch return RfqError.RequestFailed;
        if (req.connection) |conn| {
            conn.flush() catch return RfqError.RequestFailed;
        }

        var response = req.receiveHead(&.{}) catch return RfqError.RequestFailed;

        const status_code = @intFromEnum(response.head.status);
        if (status_code >= 400) {
            if (status_code == 401) return RfqError.Unauthorized;
            if (status_code == 404) return RfqError.NotFound;
            if (status_code == 429) return RfqError.RateLimited;
            if (status_code >= 500) return RfqError.ServerError;
            return RfqError.RequestFailed;
        }

        var reader = response.reader(&.{});
        return reader.allocRemaining(self.allocator, std.Io.Limit.limited(10 * 1024 * 1024)) catch return RfqError.RequestFailed;
    }

    /// 执行认证 DELETE 请求
    fn doAuthDelete(self: *Self, path: []const u8, body: []const u8) ![]u8 {
        const creds = self.api_creds orelse return RfqError.Unauthorized;

        const url = try self.buildUrl(path);
        defer self.allocator.free(url);

        const L2Auth = @import("../auth/l2.zig").L2Auth;
        const l2 = L2Auth.init(creds);
        const auth_header = l2.generateHeader(.{
            .method = "DELETE",
            .path = path,
            .body = body,
        }) catch return RfqError.Unauthorized;

        const poly_headers = auth_header.toHttpHeaders();

        const uri = std.Uri.parse(url) catch return RfqError.BadRequest;

        var req = self.http_client.request(.DELETE, uri, .{
            .extra_headers = &[_]std.http.Header{
                .{ .name = "Accept", .value = "application/json" },
                .{ .name = "User-Agent", .value = "poly-sdk-zig/0.1.0" },
                .{ .name = "Content-Type", .value = "application/json" },
                poly_headers[0],
                poly_headers[1],
                poly_headers[2],
                poly_headers[3],
            },
        }) catch return RfqError.RequestFailed;
        defer req.deinit();

        req.transfer_encoding = .{ .content_length = body.len };
        var body_writer = req.sendBodyUnflushed(&.{}) catch return RfqError.RequestFailed;
        body_writer.writer.writeAll(body) catch return RfqError.RequestFailed;
        body_writer.end() catch return RfqError.RequestFailed;
        if (req.connection) |conn| {
            conn.flush() catch return RfqError.RequestFailed;
        }

        var response = req.receiveHead(&.{}) catch return RfqError.RequestFailed;

        const status_code = @intFromEnum(response.head.status);
        if (status_code >= 400) {
            if (status_code == 401) return RfqError.Unauthorized;
            if (status_code == 404) return RfqError.NotFound;
            if (status_code == 429) return RfqError.RateLimited;
            if (status_code >= 500) return RfqError.ServerError;
            return RfqError.RequestFailed;
        }

        var reader = response.reader(&.{});
        return reader.allocRemaining(self.allocator, std.Io.Limit.limited(10 * 1024 * 1024)) catch return RfqError.RequestFailed;
    }
};

// ============================================================================
// 测试
// ============================================================================

test "Endpoints constants" {
    try std.testing.expectEqualStrings("/rfq/request", Endpoints.RFQ_REQUEST);
    try std.testing.expectEqualStrings("/rfq/quote", Endpoints.RFQ_QUOTE);
    try std.testing.expectEqualStrings("/rfq/data/requests", Endpoints.RFQ_DATA_REQUESTS);
    try std.testing.expectEqualStrings("/rfq/data/quotes", Endpoints.RFQ_DATA_QUOTES);
    try std.testing.expectEqualStrings("/rfq/data/best-quote", Endpoints.RFQ_DATA_BEST_QUOTE);
    try std.testing.expectEqualStrings("/rfq/request/accept", Endpoints.RFQ_REQUEST_ACCEPT);
    try std.testing.expectEqualStrings("/rfq/quote/approve", Endpoints.RFQ_QUOTE_APPROVE);
    try std.testing.expectEqualStrings("/rfq/config", Endpoints.RFQ_CONFIG);
}

test "RfqClient init" {
    var http_client: std.http.Client = .{ .allocator = std.testing.allocator };
    defer http_client.deinit();

    const rfq = RfqClient.init(
        std.testing.allocator,
        &http_client,
        "https://clob.polymarket.com",
        null,
    );

    try std.testing.expectEqualStrings("https://clob.polymarket.com", rfq.base_url);
    try std.testing.expectEqual(@as(?*const @import("../auth/api_creds.zig").ApiCreds, null), rfq.api_creds);
}
