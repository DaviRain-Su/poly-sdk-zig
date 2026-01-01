//! High-precision decimal type for financial calculations.
//!
//! This type uses fixed-point representation internally: mantissa * 10^(-scale)
//! Never use floating-point numbers for financial calculations.

const std = @import("std");

/// High-precision decimal number.
/// Internal representation: mantissa * 10^(-scale)
pub const Decimal = struct {
    mantissa: i128,
    scale: u8,

    // Constants
    pub const ZERO = Decimal{ .mantissa = 0, .scale = 0 };
    pub const ONE = Decimal{ .mantissa = 1, .scale = 0 };
    pub const ONE_HUNDRED = Decimal{ .mantissa = 100, .scale = 0 };

    /// Maximum supported scale (decimal places)
    pub const MAX_SCALE: u8 = 18;

    /// Create from integer
    pub fn fromInt(value: i64) Decimal {
        return Decimal{
            .mantissa = @as(i128, value),
            .scale = 0,
        };
    }

    /// Create from mantissa and scale directly
    pub fn fromParts(mantissa: i128, scale: u8) Decimal {
        return Decimal{
            .mantissa = mantissa,
            .scale = scale,
        };
    }

    /// Parse from string (e.g., "123.456", "-0.001")
    pub fn fromString(str: []const u8) !Decimal {
        if (str.len == 0) {
            return error.InvalidDecimalString;
        }

        var mantissa: i128 = 0;
        var scale: u8 = 0;
        var negative = false;
        var seen_dot = false;
        var has_digits = false;

        for (str) |c| {
            switch (c) {
                '-' => {
                    if (has_digits or negative) {
                        return error.InvalidDecimalString;
                    }
                    negative = true;
                },
                '+' => {
                    if (has_digits or negative) {
                        return error.InvalidDecimalString;
                    }
                },
                '.' => {
                    if (seen_dot) {
                        return error.InvalidDecimalString;
                    }
                    seen_dot = true;
                },
                '0'...'9' => {
                    has_digits = true;
                    // Check for overflow
                    const digit = @as(i128, c - '0');
                    if (mantissa > @divTrunc(std.math.maxInt(i128) - digit, 10)) {
                        return error.DecimalOverflow;
                    }
                    mantissa = mantissa * 10 + digit;
                    if (seen_dot) {
                        if (scale >= MAX_SCALE) {
                            return error.ScaleTooLarge;
                        }
                        scale += 1;
                    }
                },
                else => return error.InvalidDecimalString,
            }
        }

        if (!has_digits) {
            return error.InvalidDecimalString;
        }

        if (negative) {
            mantissa = -mantissa;
        }

        return Decimal{ .mantissa = mantissa, .scale = scale };
    }

    /// Create from floating point number.
    /// Note: Due to floating point representation, this may not be perfectly precise.
    /// For critical financial calculations, prefer fromString.
    pub fn fromFloat(value: f64) !Decimal {
        // Handle special cases
        if (std.math.isNan(value) or std.math.isInf(value)) {
            return error.InvalidDecimalString;
        }

        // Convert to string with sufficient precision
        var buf: [64]u8 = undefined;
        const str = std.fmt.bufPrint(&buf, "{d:.8}", .{value}) catch {
            return error.InvalidDecimalString;
        };

        // Trim trailing zeros after decimal point
        var end = str.len;
        var has_dot = false;
        for (str) |c| {
            if (c == '.') {
                has_dot = true;
                break;
            }
        }
        if (has_dot) {
            while (end > 0 and str[end - 1] == '0') {
                end -= 1;
            }
            if (end > 0 and str[end - 1] == '.') {
                end -= 1;
            }
        }

        return fromString(str[0..end]);
    }

    /// Get the scale (number of decimal places)
    pub fn getScale(self: Decimal) u8 {
        return self.scale;
    }

    /// Get the mantissa
    pub fn getMantissa(self: Decimal) i128 {
        return self.mantissa;
    }

    /// Check if zero
    pub fn isZero(self: Decimal) bool {
        return self.mantissa == 0;
    }

    /// Check if negative
    pub fn isNegative(self: Decimal) bool {
        return self.mantissa < 0;
    }

    /// Check if positive
    pub fn isPositive(self: Decimal) bool {
        return self.mantissa > 0;
    }

    /// Get absolute value
    pub fn abs(self: Decimal) Decimal {
        return Decimal{
            .mantissa = if (self.mantissa < 0) -self.mantissa else self.mantissa,
            .scale = self.scale,
        };
    }

    /// Negate
    pub fn negate(self: Decimal) Decimal {
        return Decimal{
            .mantissa = -self.mantissa,
            .scale = self.scale,
        };
    }

    /// Rescale to a new scale (may truncate)
    pub fn rescale(self: Decimal, new_scale: u8) Decimal {
        if (new_scale == self.scale) {
            return self;
        } else if (new_scale > self.scale) {
            // Increase precision
            const diff = new_scale - self.scale;
            var multiplier: i128 = 1;
            for (0..diff) |_| {
                multiplier *= 10;
            }
            return Decimal{
                .mantissa = self.mantissa * multiplier,
                .scale = new_scale,
            };
        } else {
            // Decrease precision (truncate)
            const diff = self.scale - new_scale;
            var divisor: i128 = 1;
            for (0..diff) |_| {
                divisor *= 10;
            }
            return Decimal{
                .mantissa = @divTrunc(self.mantissa, divisor),
                .scale = new_scale,
            };
        }
    }

    /// Truncate to specified scale
    pub fn truncWithScale(self: Decimal, new_scale: u8) Decimal {
        return self.rescale(new_scale);
    }

    /// Round to specified scale
    pub fn roundWithScale(self: Decimal, new_scale: u8) Decimal {
        if (new_scale >= self.scale) {
            return self.rescale(new_scale);
        }

        const diff = self.scale - new_scale;
        var divisor: i128 = 1;
        for (0..diff) |_| {
            divisor *= 10;
        }

        const half = @divTrunc(divisor, 2);
        const abs_mantissa = if (self.mantissa < 0) -self.mantissa else self.mantissa;
        const remainder = @mod(abs_mantissa, divisor);

        var result = @divTrunc(self.mantissa, divisor);
        if (remainder >= half) {
            if (self.mantissa >= 0) {
                result += 1;
            } else {
                result -= 1;
            }
        }

        return Decimal{
            .mantissa = result,
            .scale = new_scale,
        };
    }

    /// Normalize (remove trailing zeros)
    pub fn normalize(self: Decimal) Decimal {
        if (self.mantissa == 0) {
            return ZERO;
        }

        var mantissa = self.mantissa;
        var scale = self.scale;

        while (scale > 0 and @mod(mantissa, 10) == 0) {
            mantissa = @divExact(mantissa, 10);
            scale -= 1;
        }

        return Decimal{ .mantissa = mantissa, .scale = scale };
    }

    /// Addition
    pub fn add(self: Decimal, other: Decimal) Decimal {
        const max_scale = @max(self.scale, other.scale);
        const a = self.rescale(max_scale);
        const b = other.rescale(max_scale);
        return Decimal{
            .mantissa = a.mantissa + b.mantissa,
            .scale = max_scale,
        };
    }

    /// Subtraction
    pub fn sub(self: Decimal, other: Decimal) Decimal {
        const max_scale = @max(self.scale, other.scale);
        const a = self.rescale(max_scale);
        const b = other.rescale(max_scale);
        return Decimal{
            .mantissa = a.mantissa - b.mantissa,
            .scale = max_scale,
        };
    }

    /// Multiplication
    pub fn mul(self: Decimal, other: Decimal) Decimal {
        return Decimal{
            .mantissa = self.mantissa * other.mantissa,
            .scale = self.scale + other.scale,
        };
    }

    /// Division with extra precision
    pub fn div(self: Decimal, other: Decimal) !Decimal {
        if (other.mantissa == 0) {
            return error.DivisionByZero;
        }

        // Add extra precision for division
        const extra_precision: u8 = 18;
        const scaled_self = self.rescale(self.scale + extra_precision);

        return Decimal{
            .mantissa = @divTrunc(scaled_self.mantissa, other.mantissa),
            .scale = scaled_self.scale - other.scale,
        };
    }

    /// Less than comparison
    pub fn lessThan(self: Decimal, other: Decimal) bool {
        const max_scale = @max(self.scale, other.scale);
        const a = self.rescale(max_scale);
        const b = other.rescale(max_scale);
        return a.mantissa < b.mantissa;
    }

    /// Greater than comparison
    pub fn greaterThan(self: Decimal, other: Decimal) bool {
        return other.lessThan(self);
    }

    /// Equality comparison
    pub fn equal(self: Decimal, other: Decimal) bool {
        const a = self.normalize();
        const b = other.normalize();
        return a.mantissa == b.mantissa and a.scale == b.scale;
    }

    /// Less than or equal comparison
    pub fn lessThanOrEqual(self: Decimal, other: Decimal) bool {
        return self.lessThan(other) or self.equal(other);
    }

    /// Greater than or equal comparison
    pub fn greaterThanOrEqual(self: Decimal, other: Decimal) bool {
        return self.greaterThan(other) or self.equal(other);
    }

    /// Compare two decimals
    /// Returns: -1 if self < other, 0 if equal, 1 if self > other
    pub fn compare(self: Decimal, other: Decimal) i2 {
        if (self.lessThan(other)) return -1;
        if (self.greaterThan(other)) return 1;
        return 0;
    }

    /// Format for output
    pub fn format(
        self: Decimal,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        const abs_mantissa: u128 = if (self.mantissa < 0)
            @intCast(-self.mantissa)
        else
            @intCast(self.mantissa);

        if (self.mantissa < 0) {
            try writer.writeByte('-');
        }

        if (self.scale == 0) {
            try writer.print("{d}", .{abs_mantissa});
        } else {
            var divisor: u128 = 1;
            for (0..self.scale) |_| {
                divisor *= 10;
            }
            const int_part = abs_mantissa / divisor;
            const frac_part = abs_mantissa % divisor;

            try writer.print("{d}", .{int_part});
            try writer.writeByte('.');

            // Pad with leading zeros if necessary
            var temp = divisor / 10;
            while (temp > frac_part and temp > 0) {
                try writer.writeByte('0');
                temp /= 10;
            }
            if (frac_part > 0) {
                // Remove trailing zeros for cleaner output
                var frac = frac_part;
                while (frac % 10 == 0 and frac > 0) {
                    frac /= 10;
                }
                try writer.print("{d}", .{frac});
            }
        }
    }

    /// Convert to string (allocates)
    pub fn toString(self: Decimal, allocator: std.mem.Allocator) ![]u8 {
        // Estimate max size: sign + digits + '.' + scale digits
        const max_size: usize = 1 + 39 + 1 + self.scale; // i128 has up to 39 digits
        var buffer = try std.ArrayList(u8).initCapacity(allocator, max_size);
        errdefer buffer.deinit(allocator);

        // 使用 fixedBufferStream 作为中间缓冲
        var temp_buf: [64]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&temp_buf);
        self.format("{}", .{}, fbs.writer()) catch return error.BufferTooSmall;

        // 复制到 ArrayList
        try buffer.appendSlice(allocator, fbs.getWritten());
        return try buffer.toOwnedSlice(allocator);
    }

    /// JSON serialization (as quoted string)
    pub fn jsonStringify(self: Decimal, options: std.json.Stringify.Options, jw: *std.json.Stringify) !void {
        _ = options;
        // 使用临时缓冲区
        var temp_buf: [64]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&temp_buf);
        self.format("{}", .{}, fbs.writer()) catch return error.BufferTooSmall;
        try jw.write(fbs.getWritten());
    }

    /// JSON deserialization
    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !Decimal {
        _ = allocator;
        _ = options;
        const str = try source.nextString();
        return fromString(str);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "decimal from string" {
    const d1 = try Decimal.fromString("123.456");
    try std.testing.expectEqual(@as(i128, 123456), d1.mantissa);
    try std.testing.expectEqual(@as(u8, 3), d1.scale);

    const d2 = try Decimal.fromString("-0.001");
    try std.testing.expectEqual(@as(i128, -1), d2.mantissa);
    try std.testing.expectEqual(@as(u8, 3), d2.scale);

    const d3 = try Decimal.fromString("100");
    try std.testing.expectEqual(@as(i128, 100), d3.mantissa);
    try std.testing.expectEqual(@as(u8, 0), d3.scale);

    const d4 = try Decimal.fromString("0.5");
    try std.testing.expectEqual(@as(i128, 5), d4.mantissa);
    try std.testing.expectEqual(@as(u8, 1), d4.scale);
}

test "decimal invalid string" {
    try std.testing.expectError(error.InvalidDecimalString, Decimal.fromString(""));
    try std.testing.expectError(error.InvalidDecimalString, Decimal.fromString("abc"));
    try std.testing.expectError(error.InvalidDecimalString, Decimal.fromString("1.2.3"));
    try std.testing.expectError(error.InvalidDecimalString, Decimal.fromString("--1"));
}

test "decimal addition" {
    const a = try Decimal.fromString("1.5");
    const b = try Decimal.fromString("0.5");
    const sum = a.add(b);

    try std.testing.expectEqual(@as(i128, 20), sum.mantissa);
    try std.testing.expectEqual(@as(u8, 1), sum.scale);
}

test "decimal subtraction" {
    const a = try Decimal.fromString("1.5");
    const b = try Decimal.fromString("0.5");
    const diff = a.sub(b);

    try std.testing.expectEqual(@as(i128, 10), diff.mantissa);
    try std.testing.expectEqual(@as(u8, 1), diff.scale);
}

test "decimal multiplication" {
    const a = try Decimal.fromString("1.5");
    const b = try Decimal.fromString("0.5");
    const product = a.mul(b);

    // 1.5 * 0.5 = 0.75
    // 15 * 5 = 75, scale = 1 + 1 = 2
    try std.testing.expectEqual(@as(i128, 75), product.mantissa);
    try std.testing.expectEqual(@as(u8, 2), product.scale);
}

test "decimal comparison" {
    const a = try Decimal.fromString("1.5");
    const b = try Decimal.fromString("0.5");
    const c = try Decimal.fromString("1.50");

    try std.testing.expect(a.greaterThan(b));
    try std.testing.expect(b.lessThan(a));
    try std.testing.expect(a.equal(c));
}

test "decimal normalize" {
    const d = try Decimal.fromString("1.500");
    const normalized = d.normalize();

    try std.testing.expectEqual(@as(i128, 15), normalized.mantissa);
    try std.testing.expectEqual(@as(u8, 1), normalized.scale);
}

test "decimal rescale" {
    const d = try Decimal.fromString("1.5");

    // Increase scale
    const d2 = d.rescale(3);
    try std.testing.expectEqual(@as(i128, 1500), d2.mantissa);
    try std.testing.expectEqual(@as(u8, 3), d2.scale);

    // Decrease scale (truncate)
    const d3 = d2.rescale(1);
    try std.testing.expectEqual(@as(i128, 15), d3.mantissa);
    try std.testing.expectEqual(@as(u8, 1), d3.scale);
}

test "decimal zero and one" {
    try std.testing.expect(Decimal.ZERO.isZero());
    try std.testing.expect(!Decimal.ONE.isZero());
    try std.testing.expect(Decimal.ONE.equal(Decimal.fromInt(1)));
}

test "decimal negative" {
    const d = try Decimal.fromString("-1.5");
    try std.testing.expect(d.isNegative());
    try std.testing.expect(!d.isPositive());

    const abs_d = d.abs();
    try std.testing.expect(abs_d.isPositive());
}
