//! HTTP client for Polymarket CLOB API.
//!
//! Provides a simple wrapper around Zig's standard HTTP client with:
//! - Base URL configuration
//! - JSON request/response handling
//! - Error mapping (HTTP status → SDK errors)
//! - Timeout handling
//! - Custom header support
//!
//! ## Example
//!
//! ```zig
//! var client = try HttpClient.init(allocator, .{
//!     .base_url = "https://clob.polymarket.com",
//! });
//! defer client.deinit();
//!
//! // GET request
//! const response = try client.get("/markets", .{});
//! defer response.deinit();
//!
//! // POST request with JSON body
//! const order = Order{ ... };
//! const response = try client.postJson("/order", order, .{});
//! defer response.deinit();
//! ```

const std = @import("std");

// Error types for HTTP module
pub const Error = error{
    // Network
    ConnectionFailed,
    ConnectionRefused,
    Timeout,
    DnsResolutionFailed,
    TlsHandshakeFailed,
    ConnectionReset,
    // HTTP
    BadRequest,
    Unauthorized,
    Forbidden,
    NotFound,
    MethodNotAllowed,
    Conflict,
    UnprocessableEntity,
    RateLimited,
    InternalServerError,
    BadGateway,
    ServiceUnavailable,
    GatewayTimeout,
    UnknownHttpError,
    // Parse
    InvalidJson,
    // System
    OutOfMemory,
};

/// Map HTTP status code to appropriate error
pub fn errorFromHttpStatus(status: u16) ?Error {
    return switch (status) {
        200...299 => null,
        400 => Error.BadRequest,
        401 => Error.Unauthorized,
        403 => Error.Forbidden,
        404 => Error.NotFound,
        405 => Error.MethodNotAllowed,
        409 => Error.Conflict,
        422 => Error.UnprocessableEntity,
        429 => Error.RateLimited,
        500 => Error.InternalServerError,
        502 => Error.BadGateway,
        503 => Error.ServiceUnavailable,
        504 => Error.GatewayTimeout,
        else => Error.UnknownHttpError,
    };
}

/// Get error description
pub fn describeError(err: Error) []const u8 {
    return switch (err) {
        Error.ConnectionFailed => "Failed to connect to server",
        Error.ConnectionRefused => "Connection refused by server",
        Error.Timeout => "Request timed out",
        Error.DnsResolutionFailed => "DNS resolution failed",
        Error.TlsHandshakeFailed => "TLS handshake failed",
        Error.ConnectionReset => "Connection reset by peer",
        Error.BadRequest => "Bad request - check parameters",
        Error.Unauthorized => "Unauthorized - check API credentials",
        Error.Forbidden => "Forbidden - insufficient permissions",
        Error.NotFound => "Resource not found",
        Error.MethodNotAllowed => "HTTP method not allowed",
        Error.Conflict => "Resource conflict",
        Error.UnprocessableEntity => "Validation failed",
        Error.RateLimited => "Rate limit exceeded - retry later",
        Error.InternalServerError => "Internal server error",
        Error.BadGateway => "Bad gateway",
        Error.ServiceUnavailable => "Service unavailable",
        Error.GatewayTimeout => "Gateway timeout",
        Error.UnknownHttpError => "Unknown HTTP error",
        Error.InvalidJson => "Failed to parse JSON response",
        Error.OutOfMemory => "Memory allocation failed",
    };
}

/// Check if error is retryable
pub fn isRetryable(err: Error) bool {
    return switch (err) {
        Error.ConnectionFailed,
        Error.ConnectionRefused,
        Error.Timeout,
        Error.DnsResolutionFailed,
        Error.TlsHandshakeFailed,
        Error.ConnectionReset,
        Error.InternalServerError,
        Error.BadGateway,
        Error.ServiceUnavailable,
        Error.GatewayTimeout,
        Error.RateLimited,
        => true,
        else => false,
    };
}

/// Error context with additional information
pub const ErrorContext = struct {
    code: Error,
    message: []const u8,
    http_status: ?u16 = null,
    retry_after: ?u64 = null,
    raw_response: ?[]const u8 = null,

    pub fn fromError(err: Error) ErrorContext {
        return .{
            .code = err,
            .message = describeError(err),
        };
    }

    pub fn fromHttp(status: u16, body: ?[]const u8) ErrorContext {
        const err = errorFromHttpStatus(status) orelse Error.UnknownHttpError;
        return .{
            .code = err,
            .message = describeError(err),
            .http_status = status,
            .raw_response = body,
        };
    }

    pub fn canRetry(self: ErrorContext) bool {
        return isRetryable(self.code);
    }
};

/// Default timeout in nanoseconds (30 seconds)
const DEFAULT_TIMEOUT_NS: u64 = 30 * std.time.ns_per_s;

/// Default user agent
const DEFAULT_USER_AGENT = "poly-sdk-zig/0.1.0";

/// HTTP client configuration
pub const Config = struct {
    /// Base URL for all requests (e.g., "https://clob.polymarket.com")
    base_url: []const u8,

    /// Request timeout in nanoseconds
    timeout_ns: u64 = DEFAULT_TIMEOUT_NS,

    /// User agent string
    user_agent: []const u8 = DEFAULT_USER_AGENT,
};

/// HTTP response wrapper
pub const Response = struct {
    allocator: std.mem.Allocator,

    /// HTTP status code
    status: std.http.Status,

    /// Response body
    body: []const u8,

    /// Deinitialize and free resources
    pub fn deinit(self: *Response) void {
        self.allocator.free(self.body);
    }

    /// Check if response indicates success (2xx)
    pub fn isSuccess(self: Response) bool {
        return @intFromEnum(self.status) >= 200 and @intFromEnum(self.status) < 300;
    }

    /// Get error if response indicates failure
    pub fn getError(self: Response) ?Error {
        return errorFromHttpStatus(@intFromEnum(self.status));
    }

    /// Get error context if response indicates failure
    pub fn getErrorContext(self: Response) ?ErrorContext {
        const err = self.getError() orelse return null;
        return ErrorContext{
            .code = err,
            .message = describeError(err),
            .http_status = @intFromEnum(self.status),
            .raw_response = if (self.body.len > 0) self.body else null,
        };
    }

    /// Parse response body as JSON
    pub fn json(self: Response, comptime T: type) !T {
        const parsed = try std.json.parseFromSlice(T, self.allocator, self.body, .{
            .ignore_unknown_fields = true,
        });
        return parsed.value;
    }

    /// Parse response body as JSON with arena allocator (caller manages lifetime)
    pub fn jsonWithAllocator(self: Response, comptime T: type, allocator: std.mem.Allocator) !std.json.Parsed(T) {
        return std.json.parseFromSlice(T, allocator, self.body, .{
            .ignore_unknown_fields = true,
        });
    }
};

/// Request options for individual requests
pub const RequestOptions = struct {
    /// Additional headers
    headers: ?[]const std.http.Header = null,

    /// Request-specific timeout (overrides client default)
    timeout_ns: ?u64 = null,
};

/// HTTP client for API requests
pub const HttpClient = struct {
    allocator: std.mem.Allocator,
    config: Config,
    client: std.http.Client,

    /// Initialize HTTP client
    pub fn init(allocator: std.mem.Allocator, config: Config) HttpClient {
        return HttpClient{
            .allocator = allocator,
            .config = config,
            .client = .{ .allocator = allocator },
        };
    }

    /// Deinitialize and free resources
    pub fn deinit(self: *HttpClient) void {
        self.client.deinit();
    }

    /// Perform GET request
    pub fn get(self: *HttpClient, path: []const u8, options: RequestOptions) !Response {
        return self.doRequest(.GET, path, null, options);
    }

    /// Perform POST request with raw body
    pub fn post(self: *HttpClient, path: []const u8, body: ?[]const u8, options: RequestOptions) !Response {
        return self.doRequest(.POST, path, body, options);
    }

    /// Perform POST request with JSON body
    pub fn postJson(self: *HttpClient, path: []const u8, value: anytype, options: RequestOptions) !Response {
        const body = try std.json.Stringify.valueAlloc(self.allocator, value, .{});
        defer self.allocator.free(body);

        // Merge content-type header with existing headers
        var headers_list = try std.ArrayList(std.http.Header).initCapacity(self.allocator, 8);
        defer headers_list.deinit(self.allocator);

        try headers_list.append(self.allocator, .{
            .name = "Content-Type",
            .value = "application/json",
        });

        if (options.headers) |extra_headers| {
            for (extra_headers) |header| {
                try headers_list.append(self.allocator, header);
            }
        }

        const new_options = RequestOptions{
            .headers = headers_list.items,
            .timeout_ns = options.timeout_ns,
        };

        return self.doRequest(.POST, path, body, new_options);
    }

    /// Perform DELETE request
    pub fn delete(self: *HttpClient, path: []const u8, options: RequestOptions) !Response {
        return self.doRequest(.DELETE, path, null, options);
    }

    /// Perform DELETE request with JSON body
    pub fn deleteJson(self: *HttpClient, path: []const u8, value: anytype, options: RequestOptions) !Response {
        const body = try std.json.Stringify.valueAlloc(self.allocator, value, .{});
        defer self.allocator.free(body);

        var headers_list = try std.ArrayList(std.http.Header).initCapacity(self.allocator, 8);
        defer headers_list.deinit(self.allocator);

        try headers_list.append(self.allocator, .{
            .name = "Content-Type",
            .value = "application/json",
        });

        if (options.headers) |extra_headers| {
            for (extra_headers) |header| {
                try headers_list.append(self.allocator, header);
            }
        }

        const new_options = RequestOptions{
            .headers = headers_list.items,
            .timeout_ns = options.timeout_ns,
        };

        return self.doRequest(.DELETE, path, body, new_options);
    }

    /// Internal request implementation
    fn doRequest(
        self: *HttpClient,
        method: std.http.Method,
        path: []const u8,
        body: ?[]const u8,
        options: RequestOptions,
    ) !Response {
        // Build full URL
        const url = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ self.config.base_url, path });
        defer self.allocator.free(url);

        // Build headers
        var extra_headers = try std.ArrayList(std.http.Header).initCapacity(self.allocator, 16);
        defer extra_headers.deinit(self.allocator);

        try extra_headers.append(self.allocator, .{
            .name = "User-Agent",
            .value = self.config.user_agent,
        });

        try extra_headers.append(self.allocator, .{
            .name = "Accept",
            .value = "application/json",
        });

        if (options.headers) |hdrs| {
            for (hdrs) |header| {
                try extra_headers.append(self.allocator, header);
            }
        }

        // Prepare response buffer
        var response_buffer = try std.ArrayList(u8).initCapacity(self.allocator, 4096);
        errdefer response_buffer.deinit(self.allocator);

        // Make request using fetch API
        const result = self.client.fetch(.{
            .location = .{ .url = url },
            .method = method,
            .payload = body,
            .extra_headers = extra_headers.items,
            .response_storage = .{ .dynamic = &response_buffer },
        }) catch |err| {
            return mapFetchError(err);
        };

        return Response{
            .allocator = self.allocator,
            .status = result.status,
            .body = try response_buffer.toOwnedSlice(self.allocator),
        };
    }

    /// Map fetch errors to SDK errors
    fn mapFetchError(err: anyerror) Error!Response {
        return switch (err) {
            error.ConnectionRefused => Error.ConnectionRefused,
            error.ConnectionResetByPeer => Error.ConnectionReset,
            error.ConnectionTimedOut => Error.Timeout,
            error.NetworkUnreachable => Error.ConnectionFailed,
            error.HostUnreachable => Error.ConnectionFailed,
            error.UnknownHostName => Error.DnsResolutionFailed,
            error.TlsFailure => Error.TlsHandshakeFailed,
            error.OutOfMemory => Error.OutOfMemory,
            else => Error.ConnectionFailed,
        };
    }
};

/// Build query string from parameters
pub fn buildQueryString(allocator: std.mem.Allocator, params: anytype) ![]u8 {
    var result = try std.ArrayList(u8).initCapacity(allocator, 256);
    errdefer result.deinit(allocator);

    const fields = @typeInfo(@TypeOf(params)).@"struct".fields;
    var first = true;

    inline for (fields) |field| {
        const value = @field(params, field.name);

        // Handle optional fields - use comptime branch
        if (comptime @typeInfo(field.type) == .optional) {
            if (value) |actual_value| {
                try appendQueryParam(&result, allocator, field.name, actual_value, &first);
            }
            // Skip null optionals
        } else {
            try appendQueryParam(&result, allocator, field.name, value, &first);
        }
    }

    return result.toOwnedSlice(allocator);
}

fn appendQueryParam(result: *std.ArrayList(u8), allocator: std.mem.Allocator, name: []const u8, value: anytype, first: *bool) !void {
    if (!first.*) {
        try result.append(allocator, '&');
    } else {
        try result.append(allocator, '?');
        first.* = false;
    }

    // Write key
    try result.appendSlice(allocator, name);
    try result.append(allocator, '=');

    // Write value
    try writeUrlEncodedValue(result, allocator, value);
}

fn writeUrlEncodedValue(result: *std.ArrayList(u8), allocator: std.mem.Allocator, value: anytype) !void {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    // Handle strings (slices of u8) first
    if (comptime isStringType(T)) {
        // String - URL encode it
        for (value) |c| {
            if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.' or c == '~') {
                try result.append(allocator, c);
            } else {
                var buf: [3]u8 = undefined;
                _ = std.fmt.bufPrint(&buf, "%{X:0>2}", .{c}) catch unreachable;
                try result.appendSlice(allocator, &buf);
            }
        }
        return;
    }

    switch (info) {
        .int, .comptime_int => {
            var buf: [32]u8 = undefined;
            const str = try std.fmt.bufPrint(&buf, "{d}", .{value});
            try result.appendSlice(allocator, str);
        },
        .float, .comptime_float => {
            var buf: [64]u8 = undefined;
            const str = try std.fmt.bufPrint(&buf, "{d}", .{value});
            try result.appendSlice(allocator, str);
        },
        .bool => {
            try result.appendSlice(allocator, if (value) "true" else "false");
        },
        .@"enum" => {
            try result.appendSlice(allocator, @tagName(value));
        },
        else => {},
    }
}

fn isStringType(comptime T: type) bool {
    const info = @typeInfo(T);
    if (info == .pointer) {
        const ptr = info.pointer;
        if (ptr.size == .slice and ptr.child == u8) {
            return true;
        }
        // Check for *const [N]u8 (string literals)
        if (ptr.size == .one) {
            const child_info = @typeInfo(ptr.child);
            if (child_info == .array and child_info.array.child == u8) {
                return true;
            }
        }
    }
    return false;
}

// ============================================================================
// Tests
// ============================================================================

test "Config defaults" {
    const config = Config{
        .base_url = "https://example.com",
    };

    try std.testing.expectEqual(DEFAULT_TIMEOUT_NS, config.timeout_ns);
    try std.testing.expectEqualStrings(DEFAULT_USER_AGENT, config.user_agent);
}

test "Response.isSuccess" {
    var response = Response{
        .allocator = std.testing.allocator,
        .status = .ok,
        .body = "",
    };

    try std.testing.expect(response.isSuccess());

    response.status = .not_found;
    try std.testing.expect(!response.isSuccess());

    response.status = .internal_server_error;
    try std.testing.expect(!response.isSuccess());
}

test "Response.getError" {
    var response = Response{
        .allocator = std.testing.allocator,
        .status = .ok,
        .body = "",
    };

    try std.testing.expectEqual(@as(?Error, null), response.getError());

    response.status = .not_found;
    try std.testing.expectEqual(Error.NotFound, response.getError().?);

    response.status = .too_many_requests;
    try std.testing.expectEqual(Error.RateLimited, response.getError().?);
}

test "errorFromHttpStatus" {
    try std.testing.expectEqual(@as(?Error, null), errorFromHttpStatus(200));
    try std.testing.expectEqual(@as(?Error, null), errorFromHttpStatus(201));
    try std.testing.expectEqual(Error.BadRequest, errorFromHttpStatus(400).?);
    try std.testing.expectEqual(Error.Unauthorized, errorFromHttpStatus(401).?);
    try std.testing.expectEqual(Error.NotFound, errorFromHttpStatus(404).?);
    try std.testing.expectEqual(Error.RateLimited, errorFromHttpStatus(429).?);
    try std.testing.expectEqual(Error.InternalServerError, errorFromHttpStatus(500).?);
}

test "isRetryable" {
    try std.testing.expect(isRetryable(Error.ConnectionFailed));
    try std.testing.expect(isRetryable(Error.Timeout));
    try std.testing.expect(isRetryable(Error.RateLimited));
    try std.testing.expect(isRetryable(Error.ServiceUnavailable));
    try std.testing.expect(!isRetryable(Error.BadRequest));
    try std.testing.expect(!isRetryable(Error.Unauthorized));
}

test "ErrorContext" {
    const ctx = ErrorContext.fromError(Error.NotFound);
    try std.testing.expectEqual(Error.NotFound, ctx.code);
    try std.testing.expect(ctx.message.len > 0);

    const http_ctx = ErrorContext.fromHttp(429, "rate limited");
    try std.testing.expectEqual(Error.RateLimited, http_ctx.code);
    try std.testing.expectEqual(@as(?u16, 429), http_ctx.http_status);
    try std.testing.expect(http_ctx.canRetry());
}

test "buildQueryString empty" {
    const params = .{};
    const result = try buildQueryString(std.testing.allocator, params);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("", result);
}

test "buildQueryString simple" {
    const params = .{
        .limit = @as(u32, 100),
        .offset = @as(u32, 0),
    };
    const result = try buildQueryString(std.testing.allocator, params);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("?limit=100&offset=0", result);
}

test "buildQueryString with string" {
    const params = .{
        .market = "0x1234",
        .active = true,
    };
    const result = try buildQueryString(std.testing.allocator, params);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("?market=0x1234&active=true", result);
}

test "buildQueryString with optional" {
    const Params = struct {
        limit: u32,
        cursor: ?[]const u8,
    };
    const params = Params{
        .limit = 50,
        .cursor = null,
    };
    const result = try buildQueryString(std.testing.allocator, params);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("?limit=50", result);
}

test "buildQueryString url encoding" {
    const params = .{
        .query = "hello world",
    };
    const result = try buildQueryString(std.testing.allocator, params);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("?query=hello%20world", result);
}

test "HttpClient init" {
    var client = HttpClient.init(std.testing.allocator, .{
        .base_url = "https://example.com",
    });
    defer client.deinit();

    try std.testing.expectEqualStrings("https://example.com", client.config.base_url);
}
