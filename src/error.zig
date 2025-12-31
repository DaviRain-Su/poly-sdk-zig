//! Error types for the Polymarket CLOB client.
//!
//! This module defines all error types used throughout the SDK, organized by category:
//!
//! - **Network errors**: Connection failures, timeouts
//! - **HTTP errors**: Status code based errors (4xx, 5xx)
//! - **Parse errors**: JSON parsing, type conversion
//! - **Validation errors**: Invalid parameters, business logic
//! - **Auth errors**: Authentication and authorization failures
//!
//! ## Error Context
//!
//! For detailed error information, use `ErrorContext`:
//!
//! ```zig
//! const result = client.getMarkets() catch |err| {
//!     if (client.getLastErrorContext()) |ctx| {
//!         std.log.err("Error: {s} (HTTP {?})", .{ctx.message, ctx.http_status});
//!     }
//!     return err;
//! };
//! ```

const std = @import("std");

/// All possible errors in the Polymarket CLOB client.
///
/// Errors are grouped by category for easier handling.
pub const Error = error{
    // =========================================================================
    // Network Errors
    // =========================================================================

    /// Failed to establish connection to the server
    ConnectionFailed,

    /// Connection was refused by the server
    ConnectionRefused,

    /// Request timed out waiting for response
    Timeout,

    /// DNS resolution failed
    DnsResolutionFailed,

    /// TLS/SSL handshake failed
    TlsHandshakeFailed,

    /// Connection was reset by peer
    ConnectionReset,

    // =========================================================================
    // HTTP Errors (4xx Client Errors)
    // =========================================================================

    /// 400 Bad Request - Invalid request syntax or parameters
    BadRequest,

    /// 401 Unauthorized - Missing or invalid authentication
    Unauthorized,

    /// 403 Forbidden - Valid auth but insufficient permissions
    Forbidden,

    /// 404 Not Found - Resource does not exist
    NotFound,

    /// 405 Method Not Allowed
    MethodNotAllowed,

    /// 409 Conflict - Resource conflict (e.g., duplicate order)
    Conflict,

    /// 422 Unprocessable Entity - Validation failed
    UnprocessableEntity,

    /// 429 Too Many Requests - Rate limit exceeded
    RateLimited,

    // =========================================================================
    // HTTP Errors (5xx Server Errors)
    // =========================================================================

    /// 500 Internal Server Error
    InternalServerError,

    /// 502 Bad Gateway
    BadGateway,

    /// 503 Service Unavailable
    ServiceUnavailable,

    /// 504 Gateway Timeout
    GatewayTimeout,

    /// Unknown HTTP error (status code not mapped)
    UnknownHttpError,

    // =========================================================================
    // Parse Errors
    // =========================================================================

    /// Failed to parse JSON response
    InvalidJson,

    /// JSON field is missing or has wrong type
    MissingField,

    /// Failed to parse decimal number
    InvalidDecimal,

    /// Failed to parse Ethereum address
    InvalidAddress,

    /// Failed to parse UUID
    InvalidUuid,

    /// Invalid hex string
    InvalidHex,

    /// Response body is empty when content was expected
    EmptyResponse,

    // =========================================================================
    // Validation Errors
    // =========================================================================

    /// Price must be > 0 and < 1
    InvalidPrice,

    /// Size must be positive and meet minimum requirements
    InvalidSize,

    /// Invalid token ID format
    InvalidTokenId,

    /// Invalid condition ID format
    InvalidConditionId,

    /// Invalid order type
    InvalidOrderType,

    /// Invalid side (must be BUY or SELL)
    InvalidSide,

    /// Expiration time is in the past
    ExpiredTimestamp,

    /// Amount exceeds available balance
    InsufficientBalance,

    /// Order would exceed position limits
    PositionLimitExceeded,

    // =========================================================================
    // Authentication Errors
    // =========================================================================

    /// API credentials are not configured
    MissingCredentials,

    /// API key is invalid or revoked
    InvalidApiKey,

    /// Signature verification failed
    InvalidSignature,

    /// API credentials have expired
    ExpiredCredentials,

    /// Nonce is invalid or already used
    InvalidNonce,

    /// Timestamp is too far from server time
    TimestampOutOfRange,

    /// Account is banned or in closed-only mode
    AccountRestricted,

    // =========================================================================
    // Order Errors
    // =========================================================================

    /// Order not found
    OrderNotFound,

    /// Order has already been filled
    OrderAlreadyFilled,

    /// Order has already been cancelled
    OrderAlreadyCancelled,

    /// Market is closed or not accepting orders
    MarketClosed,

    /// Self-trade prevention triggered
    SelfTradePrevention,

    // =========================================================================
    // System Errors
    // =========================================================================

    /// Memory allocation failed
    OutOfMemory,

    /// Operation was cancelled
    Cancelled,

    /// Maximum retry attempts exceeded
    MaxRetriesExceeded,
};

/// HTTP status code type
pub const HttpStatus = u16;

/// Map HTTP status code to appropriate error.
///
/// Returns null for success status codes (2xx).
pub fn fromHttpStatus(status: HttpStatus) ?Error {
    return switch (status) {
        200...299 => null, // Success
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

/// Check if an HTTP status code indicates success.
pub fn isSuccessStatus(status: HttpStatus) bool {
    return status >= 200 and status < 300;
}

/// Check if an error is retryable.
///
/// Retryable errors are typically transient and may succeed on retry:
/// - Network errors (timeout, connection issues)
/// - Server errors (5xx)
/// - Rate limiting (with backoff)
pub fn isRetryable(err: Error) bool {
    return switch (err) {
        // Network errors - usually transient
        Error.ConnectionFailed,
        Error.ConnectionRefused,
        Error.Timeout,
        Error.DnsResolutionFailed,
        Error.TlsHandshakeFailed,
        Error.ConnectionReset,
        => true,

        // Server errors - may be transient
        Error.InternalServerError,
        Error.BadGateway,
        Error.ServiceUnavailable,
        Error.GatewayTimeout,
        => true,

        // Rate limiting - retry with backoff
        Error.RateLimited => true,

        // All other errors are not retryable
        else => false,
    };
}

/// Get a human-readable description of an error.
pub fn describe(err: Error) []const u8 {
    return switch (err) {
        // Network
        Error.ConnectionFailed => "Failed to connect to server",
        Error.ConnectionRefused => "Connection refused by server",
        Error.Timeout => "Request timed out",
        Error.DnsResolutionFailed => "DNS resolution failed",
        Error.TlsHandshakeFailed => "TLS handshake failed",
        Error.ConnectionReset => "Connection reset by peer",

        // HTTP 4xx
        Error.BadRequest => "Bad request - check parameters",
        Error.Unauthorized => "Unauthorized - check API credentials",
        Error.Forbidden => "Forbidden - insufficient permissions",
        Error.NotFound => "Resource not found",
        Error.MethodNotAllowed => "HTTP method not allowed",
        Error.Conflict => "Resource conflict",
        Error.UnprocessableEntity => "Validation failed",
        Error.RateLimited => "Rate limit exceeded - retry later",

        // HTTP 5xx
        Error.InternalServerError => "Internal server error",
        Error.BadGateway => "Bad gateway",
        Error.ServiceUnavailable => "Service unavailable",
        Error.GatewayTimeout => "Gateway timeout",
        Error.UnknownHttpError => "Unknown HTTP error",

        // Parse
        Error.InvalidJson => "Failed to parse JSON response",
        Error.MissingField => "Required field missing in response",
        Error.InvalidDecimal => "Invalid decimal number format",
        Error.InvalidAddress => "Invalid Ethereum address",
        Error.InvalidUuid => "Invalid UUID format",
        Error.InvalidHex => "Invalid hexadecimal string",
        Error.EmptyResponse => "Empty response from server",

        // Validation
        Error.InvalidPrice => "Price must be between 0 and 1",
        Error.InvalidSize => "Invalid order size",
        Error.InvalidTokenId => "Invalid token ID",
        Error.InvalidConditionId => "Invalid condition ID",
        Error.InvalidOrderType => "Invalid order type",
        Error.InvalidSide => "Side must be BUY or SELL",
        Error.ExpiredTimestamp => "Timestamp has expired",
        Error.InsufficientBalance => "Insufficient balance",
        Error.PositionLimitExceeded => "Position limit exceeded",

        // Auth
        Error.MissingCredentials => "API credentials not configured",
        Error.InvalidApiKey => "Invalid or revoked API key",
        Error.InvalidSignature => "Signature verification failed",
        Error.ExpiredCredentials => "API credentials have expired",
        Error.InvalidNonce => "Invalid or reused nonce",
        Error.TimestampOutOfRange => "Timestamp too far from server time",
        Error.AccountRestricted => "Account is restricted",

        // Order
        Error.OrderNotFound => "Order not found",
        Error.OrderAlreadyFilled => "Order has already been filled",
        Error.OrderAlreadyCancelled => "Order has already been cancelled",
        Error.MarketClosed => "Market is closed",
        Error.SelfTradePrevention => "Self-trade prevention triggered",

        // System
        Error.OutOfMemory => "Memory allocation failed",
        Error.Cancelled => "Operation was cancelled",
        Error.MaxRetriesExceeded => "Maximum retry attempts exceeded",
    };
}

/// Extended error context with additional information.
///
/// This structure provides more details about an error, including
/// the original HTTP response and retry information.
pub const ErrorContext = struct {
    /// The error code
    code: Error,

    /// Human-readable error message
    message: []const u8,

    /// HTTP status code (if from HTTP response)
    http_status: ?HttpStatus = null,

    /// Retry-After header value in seconds (for rate limiting)
    retry_after: ?u64 = null,

    /// Request ID for debugging (if provided by server)
    request_id: ?[]const u8 = null,

    /// Raw error response body (for debugging)
    raw_response: ?[]const u8 = null,

    /// Create error context from an error code
    pub fn fromError(err: Error) ErrorContext {
        return .{
            .code = err,
            .message = describe(err),
        };
    }

    /// Create error context from HTTP status and optional body
    pub fn fromHttp(status: HttpStatus, body: ?[]const u8) ErrorContext {
        const err = fromHttpStatus(status) orelse Error.UnknownHttpError;
        return .{
            .code = err,
            .message = describe(err),
            .http_status = status,
            .raw_response = body,
        };
    }

    /// Check if this error is retryable
    pub fn canRetry(self: ErrorContext) bool {
        return isRetryable(self.code);
    }

    /// Format for logging
    pub fn format(self: ErrorContext, writer: anytype) !void {
        try writer.print("{s}", .{self.message});
        if (self.http_status) |status| {
            try writer.print(" (HTTP {})", .{status});
        }
        if (self.request_id) |id| {
            try writer.print(" [request_id: {s}]", .{id});
        }
    }
};

/// Result type that includes error context on failure.
///
/// This allows returning detailed error information without
/// using out parameters or global state.
pub fn ResultWithContext(comptime T: type) type {
    return union(enum) {
        ok: T,
        err: ErrorContext,

        const Self = @This();

        pub fn unwrap(self: Self) !T {
            return switch (self) {
                .ok => |value| value,
                .err => |ctx| ctx.code,
            };
        }

        pub fn getContext(self: Self) ?ErrorContext {
            return switch (self) {
                .ok => null,
                .err => |ctx| ctx,
            };
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

test "fromHttpStatus success codes" {
    try std.testing.expectEqual(@as(?Error, null), fromHttpStatus(200));
    try std.testing.expectEqual(@as(?Error, null), fromHttpStatus(201));
    try std.testing.expectEqual(@as(?Error, null), fromHttpStatus(204));
    try std.testing.expectEqual(@as(?Error, null), fromHttpStatus(299));
}

test "fromHttpStatus client errors" {
    try std.testing.expectEqual(Error.BadRequest, fromHttpStatus(400).?);
    try std.testing.expectEqual(Error.Unauthorized, fromHttpStatus(401).?);
    try std.testing.expectEqual(Error.Forbidden, fromHttpStatus(403).?);
    try std.testing.expectEqual(Error.NotFound, fromHttpStatus(404).?);
    try std.testing.expectEqual(Error.RateLimited, fromHttpStatus(429).?);
}

test "fromHttpStatus server errors" {
    try std.testing.expectEqual(Error.InternalServerError, fromHttpStatus(500).?);
    try std.testing.expectEqual(Error.BadGateway, fromHttpStatus(502).?);
    try std.testing.expectEqual(Error.ServiceUnavailable, fromHttpStatus(503).?);
    try std.testing.expectEqual(Error.GatewayTimeout, fromHttpStatus(504).?);
}

test "fromHttpStatus unknown" {
    try std.testing.expectEqual(Error.UnknownHttpError, fromHttpStatus(418).?); // I'm a teapot
    try std.testing.expectEqual(Error.UnknownHttpError, fromHttpStatus(599).?);
}

test "isSuccessStatus" {
    try std.testing.expect(isSuccessStatus(200));
    try std.testing.expect(isSuccessStatus(201));
    try std.testing.expect(isSuccessStatus(204));
    try std.testing.expect(!isSuccessStatus(400));
    try std.testing.expect(!isSuccessStatus(500));
}

test "isRetryable network errors" {
    try std.testing.expect(isRetryable(Error.ConnectionFailed));
    try std.testing.expect(isRetryable(Error.Timeout));
    try std.testing.expect(isRetryable(Error.ConnectionReset));
}

test "isRetryable server errors" {
    try std.testing.expect(isRetryable(Error.InternalServerError));
    try std.testing.expect(isRetryable(Error.ServiceUnavailable));
    try std.testing.expect(isRetryable(Error.RateLimited));
}

test "isRetryable non-retryable errors" {
    try std.testing.expect(!isRetryable(Error.BadRequest));
    try std.testing.expect(!isRetryable(Error.Unauthorized));
    try std.testing.expect(!isRetryable(Error.InvalidPrice));
    try std.testing.expect(!isRetryable(Error.MissingCredentials));
}

test "describe returns non-empty string" {
    // Test a few representative errors
    try std.testing.expect(describe(Error.ConnectionFailed).len > 0);
    try std.testing.expect(describe(Error.BadRequest).len > 0);
    try std.testing.expect(describe(Error.InvalidPrice).len > 0);
    try std.testing.expect(describe(Error.MissingCredentials).len > 0);
}

test "ErrorContext fromError" {
    const ctx = ErrorContext.fromError(Error.Unauthorized);
    try std.testing.expectEqual(Error.Unauthorized, ctx.code);
    try std.testing.expect(ctx.message.len > 0);
    try std.testing.expectEqual(@as(?HttpStatus, null), ctx.http_status);
}

test "ErrorContext fromHttp" {
    const ctx = ErrorContext.fromHttp(429, "Rate limit exceeded");
    try std.testing.expectEqual(Error.RateLimited, ctx.code);
    try std.testing.expectEqual(@as(?HttpStatus, 429), ctx.http_status);
    try std.testing.expectEqualStrings("Rate limit exceeded", ctx.raw_response.?);
}

test "ErrorContext canRetry" {
    const retryable_ctx = ErrorContext.fromHttp(503, null);
    try std.testing.expect(retryable_ctx.canRetry());

    const non_retryable_ctx = ErrorContext.fromHttp(400, null);
    try std.testing.expect(!non_retryable_ctx.canRetry());
}

test "ResultWithContext ok" {
    const Result = ResultWithContext(u32);
    const result = Result{ .ok = 42 };

    try std.testing.expectEqual(@as(u32, 42), try result.unwrap());
    try std.testing.expectEqual(@as(?ErrorContext, null), result.getContext());
}

test "ResultWithContext err" {
    const Result = ResultWithContext(u32);
    const ctx = ErrorContext.fromError(Error.NotFound);
    const result = Result{ .err = ctx };

    try std.testing.expectError(Error.NotFound, result.unwrap());
    try std.testing.expect(result.getContext() != null);
}
