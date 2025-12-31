# 类型系统设计文档

本文档详细描述 Polymarket Zig CLOB Client SDK 的类型系统设计。

## 目录

- [1. 设计原则](#1-设计原则)
- [2. 基础类型](#2-基础类型)
- [3. CLOB 业务类型](#3-clob-业务类型)
- [4. 请求类型](#4-请求类型)
- [5. 响应类型](#5-响应类型)
- [6. 序列化](#6-序列化)
- [7. 类型转换](#7-类型转换)

---

## 1. 设计原则

### 1.1 类型安全

- 使用编译时类型检查防止运行时错误
- 利用 Zig 的 `comptime` 功能实现零成本抽象
- 枚举类型表示有限状态集

### 1.2 内存安全

- 明确所有权语义
- 使用 `Allocator` 显式管理内存
- 避免悬空指针

### 1.3 与 Rust 版本的映射

| Rust 类型 | Zig 类型 |
|-----------|----------|
| `String` | `[]const u8` |
| `Vec<T>` | `[]T` |
| `Option<T>` | `?T` |
| `Result<T, E>` | `!T` 或 `Error!T` |
| `HashMap<K, V>` | `std.HashMap(K, V, ...)` |
| `Decimal` | 自定义 `Decimal` |
| `Address` | `[20]u8` |
| `U256` | `u256` |
| `Uuid` | `[16]u8` + 辅助函数 |

---

## 2. 基础类型

### 2.1 Decimal

高精度十进制数类型，用于表示价格和数量。

```zig
// src/types/decimal.zig

/// 高精度十进制数
/// 内部使用定点表示：mantissa * 10^(-scale)
pub const Decimal = struct {
    mantissa: i128,
    scale: u8,

    // 常量
    pub const ZERO = Decimal{ .mantissa = 0, .scale = 0 };
    pub const ONE = Decimal{ .mantissa = 1, .scale = 0 };
    pub const ONE_HUNDRED = Decimal{ .mantissa = 100, .scale = 0 };

    /// 从浮点数创建
    pub fn fromFloat(value: f64) Decimal {
        // 自动检测精度
        var scale: u8 = 0;
        var temp = value;
        while (temp != @trunc(temp) and scale < 18) {
            temp *= 10;
            scale += 1;
        }
        const mantissa: i128 = @intFromFloat(temp);
        return Decimal{ .mantissa = mantissa, .scale = scale };
    }

    /// 从整数创建
    pub fn fromInt(value: i64) Decimal {
        return Decimal{
            .mantissa = @as(i128, value),
            .scale = 0,
        };
    }

    /// 从字符串解析
    pub fn fromString(str: []const u8) !Decimal {
        var mantissa: i128 = 0;
        var scale: u8 = 0;
        var negative = false;
        var seen_dot = false;

        for (str) |c| {
            switch (c) {
                '-' => negative = true,
                '.' => seen_dot = true,
                '0'...'9' => {
                    mantissa = mantissa * 10 + @as(i128, c - '0');
                    if (seen_dot) scale += 1;
                },
                else => return error.InvalidDecimalString,
            }
        }

        if (negative) mantissa = -mantissa;
        return Decimal{ .mantissa = mantissa, .scale = scale };
    }

    /// 转换为浮点数
    pub fn toFloat(self: Decimal) f64 {
        const base: f64 = @floatFromInt(self.mantissa);
        var divisor: f64 = 1;
        var i: u8 = 0;
        while (i < self.scale) : (i += 1) {
            divisor *= 10;
        }
        return base / divisor;
    }

    /// 获取精度（小数位数）
    pub fn getScale(self: Decimal) u8 {
        return self.scale;
    }

    /// 截断到指定精度
    pub fn truncWithScale(self: Decimal, new_scale: u8) Decimal {
        if (new_scale >= self.scale) {
            // 增加精度，乘以 10 的幂
            const diff = new_scale - self.scale;
            var multiplier: i128 = 1;
            var i: u8 = 0;
            while (i < diff) : (i += 1) {
                multiplier *= 10;
            }
            return Decimal{
                .mantissa = self.mantissa * multiplier,
                .scale = new_scale,
            };
        } else {
            // 减少精度，除以 10 的幂（截断）
            const diff = self.scale - new_scale;
            var divisor: i128 = 1;
            var i: u8 = 0;
            while (i < diff) : (i += 1) {
                divisor *= 10;
            }
            return Decimal{
                .mantissa = @divTrunc(self.mantissa, divisor),
                .scale = new_scale,
            };
        }
    }

    /// 标准化（移除尾随零）
    pub fn normalize(self: Decimal) Decimal {
        var mantissa = self.mantissa;
        var scale = self.scale;

        while (scale > 0 and @mod(mantissa, 10) == 0) {
            mantissa = @divExact(mantissa, 10);
            scale -= 1;
        }

        return Decimal{ .mantissa = mantissa, .scale = scale };
    }

    /// 加法
    pub fn add(self: Decimal, other: Decimal) Decimal {
        const max_scale = @max(self.scale, other.scale);
        const a = self.truncWithScale(max_scale);
        const b = other.truncWithScale(max_scale);
        return Decimal{
            .mantissa = a.mantissa + b.mantissa,
            .scale = max_scale,
        };
    }

    /// 减法
    pub fn sub(self: Decimal, other: Decimal) Decimal {
        const max_scale = @max(self.scale, other.scale);
        const a = self.truncWithScale(max_scale);
        const b = other.truncWithScale(max_scale);
        return Decimal{
            .mantissa = a.mantissa - b.mantissa,
            .scale = max_scale,
        };
    }

    /// 乘法
    pub fn mul(self: Decimal, other: Decimal) Decimal {
        return Decimal{
            .mantissa = self.mantissa * other.mantissa,
            .scale = self.scale + other.scale,
        };
    }

    /// 除法
    pub fn div(self: Decimal, other: Decimal) Decimal {
        // 增加精度以保持精确性
        const extra_precision: u8 = 18;
        const scaled_self = self.truncWithScale(self.scale + extra_precision);
        return Decimal{
            .mantissa = @divTrunc(scaled_self.mantissa, other.mantissa),
            .scale = scaled_self.scale - other.scale,
        };
    }

    /// 比较
    pub fn lessThan(self: Decimal, other: Decimal) bool {
        const max_scale = @max(self.scale, other.scale);
        const a = self.truncWithScale(max_scale);
        const b = other.truncWithScale(max_scale);
        return a.mantissa < b.mantissa;
    }

    pub fn greaterThan(self: Decimal, other: Decimal) bool {
        return other.lessThan(self);
    }

    pub fn equal(self: Decimal, other: Decimal) bool {
        const a = self.normalize();
        const b = other.normalize();
        return a.mantissa == b.mantissa and a.scale == b.scale;
    }

    pub fn lessThanOrEqual(self: Decimal, other: Decimal) bool {
        return self.lessThan(other) or self.equal(other);
    }

    pub fn greaterThanOrEqual(self: Decimal, other: Decimal) bool {
        return self.greaterThan(other) or self.equal(other);
    }

    /// 检查是否为零
    pub fn isZero(self: Decimal) bool {
        return self.mantissa == 0;
    }

    /// 检查是否为负数
    pub fn isNegative(self: Decimal) bool {
        return self.mantissa < 0;
    }

    /// 格式化输出
    pub fn format(
        self: Decimal,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        const abs_mantissa = if (self.mantissa < 0) -self.mantissa else self.mantissa;
        
        if (self.mantissa < 0) {
            try writer.writeByte('-');
        }

        if (self.scale == 0) {
            try writer.print("{d}", .{abs_mantissa});
        } else {
            var divisor: i128 = 1;
            var i: u8 = 0;
            while (i < self.scale) : (i += 1) {
                divisor *= 10;
            }
            const int_part = @divTrunc(abs_mantissa, divisor);
            const frac_part = @mod(abs_mantissa, divisor);
            try writer.print("{d}.{d:0>[1]}", .{ int_part, frac_part, self.scale });
        }
    }

    /// JSON 序列化
    pub fn jsonStringify(self: Decimal, options: std.json.StringifyOptions, writer: anytype) !void {
        _ = options;
        try writer.writeByte('"');
        try self.format("{}", .{}, writer);
        try writer.writeByte('"');
    }

    /// JSON 反序列化
    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !Decimal {
        _ = allocator;
        _ = options;
        const str = try source.nextString();
        return fromString(str);
    }
};

test "decimal basic operations" {
    const a = Decimal.fromFloat(1.5);
    const b = Decimal.fromFloat(0.5);
    
    const sum = a.add(b);
    try std.testing.expectEqual(@as(f64, 2.0), sum.toFloat());
    
    const diff = a.sub(b);
    try std.testing.expectEqual(@as(f64, 1.0), diff.toFloat());
    
    const product = a.mul(b);
    try std.testing.expectEqual(@as(f64, 0.75), product.toFloat());
}

test "decimal from string" {
    const d = try Decimal.fromString("123.456");
    try std.testing.expectEqual(@as(i128, 123456), d.mantissa);
    try std.testing.expectEqual(@as(u8, 3), d.scale);
}
```

### 2.2 Address

以太坊地址类型。

```zig
// src/types/address.zig

const std = @import("std");

/// 以太坊地址 (20 字节)
pub const Address = [20]u8;

/// 零地址
pub const ZERO_ADDRESS: Address = [_]u8{0} ** 20;

/// 从十六进制字符串解析地址
pub fn fromHex(hex: []const u8) !Address {
    var result: Address = undefined;
    
    const start: usize = if (hex.len >= 2 and hex[0] == '0' and (hex[1] == 'x' or hex[1] == 'X'))
        2
    else
        0;

    if (hex.len - start != 40) {
        return error.InvalidAddressLength;
    }

    for (0..20) |i| {
        const high = try hexCharToNibble(hex[start + i * 2]);
        const low = try hexCharToNibble(hex[start + i * 2 + 1]);
        result[i] = (high << 4) | low;
    }

    return result;
}

/// 将地址转换为十六进制字符串
pub fn toHex(address: Address, allocator: std.mem.Allocator) ![]u8 {
    const hex_chars = "0123456789abcdef";
    var result = try allocator.alloc(u8, 42);  // "0x" + 40 hex chars
    
    result[0] = '0';
    result[1] = 'x';
    
    for (address, 0..) |byte, i| {
        result[2 + i * 2] = hex_chars[byte >> 4];
        result[2 + i * 2 + 1] = hex_chars[byte & 0x0F];
    }
    
    return result;
}

/// 将地址转换为带校验和的十六进制字符串 (EIP-55)
pub fn toChecksumHex(address: Address, allocator: std.mem.Allocator) ![]u8 {
    const lowercase = try toHex(address, allocator);
    defer allocator.free(lowercase);
    
    // 计算地址的 keccak256 哈希
    var hasher = std.crypto.hash.sha3.Keccak256.init(.{});
    hasher.update(lowercase[2..]);  // 不包含 "0x"
    const hash = hasher.finalResult();
    
    var result = try allocator.alloc(u8, 42);
    result[0] = '0';
    result[1] = 'x';
    
    for (0..40) |i| {
        const char = lowercase[2 + i];
        const hash_nibble = if (i % 2 == 0) hash[i / 2] >> 4 else hash[i / 2] & 0x0F;
        
        result[2 + i] = if (char >= 'a' and char <= 'f' and hash_nibble >= 8)
            char - 32  // 转大写
        else
            char;
    }
    
    return result;
}

fn hexCharToNibble(c: u8) !u4 {
    return switch (c) {
        '0'...'9' => @intCast(c - '0'),
        'a'...'f' => @intCast(c - 'a' + 10),
        'A'...'F' => @intCast(c - 'A' + 10),
        else => error.InvalidHexCharacter,
    };
}

/// JSON 序列化
pub fn jsonStringifyAddress(address: Address, options: std.json.StringifyOptions, writer: anytype) !void {
    _ = options;
    try writer.writeAll("\"0x");
    for (address) |byte| {
        try writer.print("{x:0>2}", .{byte});
    }
    try writer.writeByte('"');
}

test "address from hex" {
    const addr = try fromHex("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
    try std.testing.expectEqual(@as(u8, 0xf3), addr[0]);
    try std.testing.expectEqual(@as(u8, 0x66), addr[19]);
}

test "address to hex" {
    var allocator = std.testing.allocator;
    const addr = try fromHex("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
    const hex = try toHex(addr, allocator);
    defer allocator.free(hex);
    try std.testing.expectEqualStrings("0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266", hex);
}
```

### 2.3 UUID

UUID 类型。

```zig
// src/types/uuid.zig

const std = @import("std");

/// UUID (RFC 4122)
pub const Uuid = struct {
    bytes: [16]u8,

    pub const nil = Uuid{ .bytes = [_]u8{0} ** 16 };

    /// 生成 v4 随机 UUID
    pub fn v4() Uuid {
        var bytes: [16]u8 = undefined;
        std.crypto.random.bytes(&bytes);
        
        // 设置版本 (v4)
        bytes[6] = (bytes[6] & 0x0F) | 0x40;
        // 设置变体 (RFC 4122)
        bytes[8] = (bytes[8] & 0x3F) | 0x80;
        
        return Uuid{ .bytes = bytes };
    }

    /// 从字符串解析
    pub fn fromString(str: []const u8) !Uuid {
        if (str.len != 36) {
            return error.InvalidUuidLength;
        }

        var bytes: [16]u8 = undefined;
        var byte_idx: usize = 0;
        var str_idx: usize = 0;

        while (str_idx < 36) : (str_idx += 1) {
            if (str[str_idx] == '-') continue;

            const high = try hexCharToNibble(str[str_idx]);
            str_idx += 1;
            const low = try hexCharToNibble(str[str_idx]);
            
            bytes[byte_idx] = (high << 4) | low;
            byte_idx += 1;
        }

        return Uuid{ .bytes = bytes };
    }

    /// 转换为字符串
    pub fn toString(self: Uuid, allocator: std.mem.Allocator) ![]u8 {
        var result = try allocator.alloc(u8, 36);
        const hex = "0123456789abcdef";
        
        var out_idx: usize = 0;
        for (self.bytes, 0..) |byte, i| {
            if (i == 4 or i == 6 or i == 8 or i == 10) {
                result[out_idx] = '-';
                out_idx += 1;
            }
            result[out_idx] = hex[byte >> 4];
            result[out_idx + 1] = hex[byte & 0x0F];
            out_idx += 2;
        }
        
        return result;
    }

    /// 格式化输出
    pub fn format(
        self: Uuid,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        
        const hex = "0123456789abcdef";
        for (self.bytes, 0..) |byte, i| {
            if (i == 4 or i == 6 or i == 8 or i == 10) {
                try writer.writeByte('-');
            }
            try writer.writeByte(hex[byte >> 4]);
            try writer.writeByte(hex[byte & 0x0F]);
        }
    }

    /// JSON 序列化
    pub fn jsonStringify(self: Uuid, options: std.json.StringifyOptions, writer: anytype) !void {
        _ = options;
        try writer.writeByte('"');
        try self.format("{}", .{}, writer);
        try writer.writeByte('"');
    }
};

fn hexCharToNibble(c: u8) !u4 {
    return switch (c) {
        '0'...'9' => @intCast(c - '0'),
        'a'...'f' => @intCast(c - 'a' + 10),
        'A'...'F' => @intCast(c - 'A' + 10),
        else => error.InvalidHexCharacter,
    };
}
```

### 2.4 Secret

安全包装类型，防止敏感数据泄露。

```zig
// src/types/secret.zig

const std = @import("std");

/// 安全包装类型，防止意外日志输出敏感数据
pub fn Secret(comptime T: type) type {
    return struct {
        const Self = @This();
        
        value: T,

        pub fn init(value: T) Self {
            return Self{ .value = value };
        }

        /// 显式获取内部值
        pub fn reveal(self: Self) T {
            return self.value;
        }

        /// 格式化时显示 [REDACTED]
        pub fn format(
            self: Self,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = self;
            _ = fmt;
            _ = options;
            try writer.writeAll("[REDACTED]");
        }

        /// 清零内存
        pub fn zeroize(self: *Self) void {
            if (@TypeOf(T) == []u8 or @TypeOf(T) == []const u8) {
                @memset(self.value, 0);
            } else if (@typeInfo(T) == .array) {
                @memset(&self.value, 0);
            }
        }
    };
}
```

---

## 3. CLOB 业务类型

### 3.1 订单类型

```zig
// src/clob/types/mod.zig

const std = @import("std");
const Decimal = @import("../../types/decimal.zig").Decimal;
const Address = @import("../../types/address.zig").Address;
const Uuid = @import("../../types/uuid.zig").Uuid;

/// 订单类型
pub const OrderType = enum {
    /// Good 'til Cancelled - 直到取消前有效
    gtc,
    /// Fill or Kill - 全部成交或取消
    fok,
    /// Good 'til Date - 直到指定日期有效
    gtd,
    /// Fill and Kill - 尽可能成交，剩余取消
    fak,
    /// 未知类型
    unknown,

    pub fn jsonStringify(self: OrderType, options: std.json.StringifyOptions, writer: anytype) !void {
        _ = options;
        const str = switch (self) {
            .gtc => "GTC",
            .fok => "FOK",
            .gtd => "GTD",
            .fak => "FAK",
            .unknown => "UNKNOWN",
        };
        try writer.print("\"{s}\"", .{str});
    }

    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !OrderType {
        _ = allocator;
        _ = options;
        const str = try source.nextString();
        if (std.mem.eql(u8, str, "GTC") or std.mem.eql(u8, str, "gtc")) return .gtc;
        if (std.mem.eql(u8, str, "FOK") or std.mem.eql(u8, str, "fok")) return .fok;
        if (std.mem.eql(u8, str, "GTD") or std.mem.eql(u8, str, "gtd")) return .gtd;
        if (std.mem.eql(u8, str, "FAK") or std.mem.eql(u8, str, "fak")) return .fak;
        return .unknown;
    }
};

/// 交易方向
pub const Side = enum(u8) {
    buy = 0,
    sell = 1,
    unknown = 255,

    pub fn jsonStringify(self: Side, options: std.json.StringifyOptions, writer: anytype) !void {
        _ = options;
        const str = switch (self) {
            .buy => "BUY",
            .sell => "SELL",
            .unknown => "UNKNOWN",
        };
        try writer.print("\"{s}\"", .{str});
    }

    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !Side {
        _ = allocator;
        _ = options;
        const str = try source.nextString();
        if (std.mem.eql(u8, str, "BUY") or std.mem.eql(u8, str, "buy")) return .buy;
        if (std.mem.eql(u8, str, "SELL") or std.mem.eql(u8, str, "sell")) return .sell;
        return .unknown;
    }
};

/// 签名类型
pub const SignatureType = enum(u8) {
    /// 标准 EOA 钱包
    eoa = 0,
    /// Proxy 钱包 (Magic/Email)
    proxy = 1,
    /// Gnosis Safe 多签钱包
    gnosis_safe = 2,
};

/// 订单状态
pub const OrderStatusType = enum {
    live,
    matched,
    canceled,
    delayed,
    unmatched,
    unknown,
};

/// 资产类型
pub const AssetType = enum {
    collateral,
    conditional,
    unknown,
};

/// 交易者角色
pub const TraderSide = enum {
    taker,
    maker,
    unknown,
};

/// 价格精度
pub const TickSize = enum {
    /// 0.1
    tenth,
    /// 0.01
    hundredth,
    /// 0.001
    thousandth,
    /// 0.0001
    ten_thousandth,

    pub fn asDecimal(self: TickSize) Decimal {
        return switch (self) {
            .tenth => Decimal{ .mantissa = 1, .scale = 1 },
            .hundredth => Decimal{ .mantissa = 1, .scale = 2 },
            .thousandth => Decimal{ .mantissa = 1, .scale = 3 },
            .ten_thousandth => Decimal{ .mantissa = 1, .scale = 4 },
        };
    }

    pub fn scale(self: TickSize) u8 {
        return switch (self) {
            .tenth => 1,
            .hundredth => 2,
            .thousandth => 3,
            .ten_thousandth => 4,
        };
    }

    pub fn fromDecimal(d: Decimal) !TickSize {
        const normalized = d.normalize();
        if (normalized.mantissa == 1) {
            return switch (normalized.scale) {
                1 => .tenth,
                2 => .hundredth,
                3 => .thousandth,
                4 => .ten_thousandth,
                else => error.InvalidTickSize,
            };
        }
        return error.InvalidTickSize;
    }
};

/// 金额类型
pub const Amount = struct {
    value: Decimal,
    kind: AmountKind,

    pub const AmountKind = enum {
        usdc,
        shares,
    };

    pub fn usdc(value: Decimal) !Amount {
        const normalized = value.normalize();
        if (normalized.scale > 6) {
            return error.TooManyDecimalPlaces;
        }
        return Amount{ .value = normalized, .kind = .usdc };
    }

    pub fn shares(value: Decimal) !Amount {
        const normalized = value.normalize();
        if (normalized.scale > 2) {
            return error.TooManyDecimalPlaces;
        }
        return Amount{ .value = normalized, .kind = .shares };
    }

    pub fn asInner(self: Amount) Decimal {
        return self.value;
    }

    pub fn isUsdc(self: Amount) bool {
        return self.kind == .usdc;
    }

    pub fn isShares(self: Amount) bool {
        return self.kind == .shares;
    }
};

/// 订单结构（对应链上 Order 结构）
pub const Order = struct {
    salt: u256,
    maker: Address,
    signer: Address,
    taker: Address,
    token_id: u256,
    maker_amount: u256,
    taker_amount: u256,
    expiration: u256,
    nonce: u256,
    fee_rate_bps: u256,
    side: u8,
    signature_type: u8,

    /// EIP-712 类型哈希
    pub fn typeHash() [32]u8 {
        const type_string = "Order(uint256 salt,address maker,address signer,address taker,uint256 tokenId,uint256 makerAmount,uint256 takerAmount,uint256 expiration,uint256 nonce,uint256 feeRateBps,uint8 side,uint8 signatureType)";
        var hasher = std.crypto.hash.sha3.Keccak256.init(.{});
        hasher.update(type_string);
        return hasher.finalResult();
    }

    /// 计算结构哈希
    pub fn structHash(self: Order) [32]u8 {
        var hasher = std.crypto.hash.sha3.Keccak256.init(.{});
        
        // 添加类型哈希
        hasher.update(&typeHash());
        
        // 添加各字段（按顺序 ABI 编码）
        hasher.update(&encodeU256(self.salt));
        hasher.update(&encodeAddress(self.maker));
        hasher.update(&encodeAddress(self.signer));
        hasher.update(&encodeAddress(self.taker));
        hasher.update(&encodeU256(self.token_id));
        hasher.update(&encodeU256(self.maker_amount));
        hasher.update(&encodeU256(self.taker_amount));
        hasher.update(&encodeU256(self.expiration));
        hasher.update(&encodeU256(self.nonce));
        hasher.update(&encodeU256(self.fee_rate_bps));
        hasher.update(&encodeU8(self.side));
        hasher.update(&encodeU8(self.signature_type));
        
        return hasher.finalResult();
    }

    /// 计算 EIP-712 签名哈希
    pub fn eip712SigningHash(self: Order, domain: anytype) [32]u8 {
        var hasher = std.crypto.hash.sha3.Keccak256.init(.{});
        hasher.update(&[_]u8{ 0x19, 0x01 });
        hasher.update(&domain.structHash());
        hasher.update(&self.structHash());
        return hasher.finalResult();
    }
};

fn encodeU256(value: u256) [32]u8 {
    var result: [32]u8 = undefined;
    std.mem.writeInt(u256, &result, value, .big);
    return result;
}

fn encodeAddress(addr: Address) [32]u8 {
    var result: [32]u8 = [_]u8{0} ** 32;
    @memcpy(result[12..32], &addr);
    return result;
}

fn encodeU8(value: u8) [32]u8 {
    var result: [32]u8 = [_]u8{0} ** 32;
    result[31] = value;
    return result;
}

/// 可签名订单
pub const SignableOrder = struct {
    order: Order,
    order_type: OrderType,
};

/// 已签名订单
pub const SignedOrder = struct {
    order: Order,
    signature: [65]u8,
    order_type: OrderType,
    owner: Uuid,

    /// JSON 序列化（特殊格式，signature 合并到 order 中）
    pub fn jsonStringify(self: SignedOrder, options: std.json.StringifyOptions, writer: anytype) !void {
        _ = options;
        try writer.writeAll("{\"order\":{");
        // ... 序列化 order 字段和 signature
        try writer.writeAll("},\"orderType\":");
        try self.order_type.jsonStringify(.{}, writer);
        try writer.writeAll(",\"owner\":\"");
        try self.owner.format("{}", .{}, writer);
        try writer.writeAll("\"}");
    }
};
```

---

## 4. 请求类型

```zig
// src/clob/types/request.zig

const Decimal = @import("../../types/decimal.zig").Decimal;
const mod = @import("mod.zig");

pub const MidpointRequest = struct {
    token_id: []const u8,
};

pub const PriceRequest = struct {
    token_id: []const u8,
    side: mod.Side,
};

pub const SpreadRequest = struct {
    token_id: []const u8,
};

pub const OrderBookSummaryRequest = struct {
    token_id: []const u8,
};

pub const LastTradePriceRequest = struct {
    token_id: []const u8,
};

pub const OrdersRequest = struct {
    market: ?[]const u8 = null,
    asset_id: ?[]const u8 = null,
    state: ?mod.OrderStatusType = null,
};

pub const TradesRequest = struct {
    market: ?[]const u8 = null,
    asset_id: ?[]const u8 = null,
    maker_address: ?[]const u8 = null,
    before: ?i64 = null,
    after: ?i64 = null,
    id: ?[]const u8 = null,
};

pub const CancelMarketOrderRequest = struct {
    market: ?[]const u8 = null,
    asset_id: ?[]const u8 = null,
};

pub const BalanceAllowanceRequest = struct {
    asset_type: ?mod.AssetType = null,
    token_id: ?[]const u8 = null,
    signature_type: ?mod.SignatureType = null,
};

pub const UpdateBalanceAllowanceRequest = struct {
    asset_type: ?mod.AssetType = null,
    token_id: ?[]const u8 = null,
    signature_type: ?mod.SignatureType = null,
};

pub const DeleteNotificationsRequest = struct {
    ids: []const []const u8,
};

pub const UserRewardsEarningRequest = struct {
    start_date: ?[]const u8 = null,
    end_date: ?[]const u8 = null,
};
```

---

## 5. 响应类型

```zig
// src/clob/types/response.zig

const std = @import("std");
const Decimal = @import("../../types/decimal.zig").Decimal;
const Uuid = @import("../../types/uuid.zig").Uuid;
const mod = @import("mod.zig");

/// 分页响应包装
pub fn Page(comptime T: type) type {
    return struct {
        data: []T,
        next_cursor: []const u8,
        limit: u32 = 0,
        count: u32 = 0,
    };
}

pub const MidpointResponse = struct {
    mid: Decimal,
};

pub const MidpointsResponse = struct {
    // token_id -> mid
    // 使用 std.json.Value 处理动态键
};

pub const PriceResponse = struct {
    price: Decimal,
};

pub const PricesResponse = struct {
    // token_id -> price map
};

pub const SpreadResponse = struct {
    spread: Decimal,
};

pub const SpreadsResponse = struct {
    // token_id -> spread map
};

pub const TickSizeResponse = struct {
    minimum_tick_size: mod.TickSize,
};

pub const NegRiskResponse = struct {
    neg_risk: bool,
};

pub const FeeRateResponse = struct {
    base_fee: u32,
};

pub const GeoblockResponse = struct {
    blocked: bool,
    ip: []const u8,
    country: []const u8,
    region: []const u8,
};

pub const PriceLevel = struct {
    price: Decimal,
    size: Decimal,
};

pub const OrderBookSummaryResponse = struct {
    market: []const u8,
    asset_id: []const u8,
    bids: []PriceLevel,
    asks: []PriceLevel,
    hash: []const u8,
    timestamp: i64,
};

pub const LastTradePriceResponse = struct {
    price: Decimal,
};

pub const TokenInfo = struct {
    token_id: []const u8,
    outcome: []const u8,
    winner: bool,
};

pub const RewardsInfo = struct {
    rates: []const struct {
        asset_address: []const u8,
        rewards_daily_rate: Decimal,
    },
    min_size: Decimal,
    max_spread: Decimal,
};

pub const MarketResponse = struct {
    condition_id: []const u8,
    question_id: []const u8,
    tokens: []TokenInfo,
    rewards: RewardsInfo,
    minimum_order_size: Decimal,
    minimum_tick_size: mod.TickSize,
    description: []const u8,
    category: []const u8,
    end_date_iso: []const u8,
    game_start_time: ?[]const u8,
    question: []const u8,
    market_slug: []const u8,
    min_incentive_size: Decimal,
    max_incentive_spread: Decimal,
    active: bool,
    closed: bool,
    seconds_delay: i32,
    icon: []const u8,
    fpmm: []const u8,
    neg_risk: bool,
    neg_risk_market_id: ?[]const u8,
    neg_risk_request_id: ?[]const u8,
    is_50_50_outcome: bool,
    accepting_orders: bool,
    accepting_order_timestamp: ?[]const u8,
};

pub const SimplifiedMarketResponse = struct {
    condition_id: []const u8,
    tokens: []struct {
        token_id: []const u8,
        outcome: []const u8,
    },
    neg_risk: bool,
};

pub const ApiKeysResponse = struct {
    api_keys: []struct {
        api_key: Uuid,
        created_at: []const u8,
    },
};

pub const PostOrderResponse = struct {
    order_id: []const u8,
    status: []const u8,
    error_msg: ?[]const u8 = null,
};

pub const OpenOrderResponse = struct {
    id: []const u8,
    status: mod.OrderStatusType,
    owner: []const u8,
    market: []const u8,
    asset_id: []const u8,
    side: mod.Side,
    original_size: Decimal,
    size_matched: Decimal,
    price: Decimal,
    outcome: []const u8,
    order_type: mod.OrderType,
    created_at: []const u8,
    expiration: []const u8,
    associate_trades: []TradeResponse,
};

pub const CancelOrdersResponse = struct {
    canceled: []const []const u8,
    not_canceled: ?struct {
        id: []const u8,
        reason: []const u8,
    } = null,
};

pub const TradeResponse = struct {
    id: []const u8,
    taker_order_id: []const u8,
    market: []const u8,
    asset_id: []const u8,
    side: mod.Side,
    size: Decimal,
    fee_rate_bps: u32,
    price: Decimal,
    status: []const u8,
    match_time: []const u8,
    last_update: []const u8,
    outcome: []const u8,
    bucket_index: u32,
    owner: []const u8,
    maker_address: []const u8,
    transaction_hash: ?[]const u8,
    trader_side: mod.TraderSide,
    type: []const u8,
};

pub const BalanceAllowanceResponse = struct {
    balance: Decimal,
    allowance: Decimal,
};

pub const NotificationResponse = struct {
    id: []const u8,
    type: []const u8,
    message: []const u8,
    created_at: []const u8,
};

pub const BanStatusResponse = struct {
    banned: bool,
};

pub const OrderScoringResponse = struct {
    scoring: bool,
};

pub const OrdersScoringResponse = struct {
    // order_id -> scoring map
};

pub const CurrentRewardResponse = struct {
    condition_id: []const u8,
    daily_rate: Decimal,
    min_size: Decimal,
    max_spread: Decimal,
};

pub const UserEarningResponse = struct {
    date: []const u8,
    earnings: Decimal,
    market: []const u8,
};

pub const TotalUserEarningResponse = struct {
    date: []const u8,
    total_earnings: Decimal,
};

pub const UserRewardsEarningResponse = struct {
    // 复杂响应结构
};

pub const RewardsPercentagesResponse = struct {
    maker_percentage: Decimal,
    taker_percentage: Decimal,
};

pub const MarketRewardResponse = struct {
    condition_id: []const u8,
    date: []const u8,
    amount: Decimal,
};

pub const BuilderApiKeyResponse = struct {
    api_key: Uuid,
    created_at: []const u8,
};

pub const BuilderTradeResponse = struct {
    // 继承 TradeResponse 并添加 builder 特定字段
    base: TradeResponse,
    builder_fee: Decimal,
};
```

---

## 6. 序列化

### 6.1 JSON 序列化策略

- 使用 `std.json` 进行序列化/反序列化
- 自定义类型实现 `jsonStringify` 和 `jsonParse` 方法
- 字段名转换：Zig 使用 snake_case，JSON 使用 camelCase

### 6.2 自定义序列化示例

```zig
/// 驼峰命名转换
pub fn toCamelCase(allocator: std.mem.Allocator, snake: []const u8) ![]u8 {
    // 预分配容量，snake_case 转 camelCase 长度不会超过原长度
    var result = try std.ArrayList(u8).initCapacity(allocator, snake.len);
    errdefer result.deinit();  // 错误时释放，成功时由 toOwnedSlice 转移所有权
    var capitalize_next = false;
    
    for (snake) |c| {
        if (c == '_') {
            capitalize_next = true;
        } else if (capitalize_next) {
            // Zig 0.15: append 需要传入 allocator
            try result.append(allocator, std.ascii.toUpper(c));
            capitalize_next = false;
        } else {
            try result.append(allocator, c);
        }
    }
    
    // Zig 0.15: toOwnedSlice 需要传入 allocator
    return try result.toOwnedSlice(allocator);
}
```

---

## 7. 类型转换

### 7.1 Rust -> Zig 类型映射详细说明

```zig
// Rust: rust_decimal::Decimal
// Zig: 自定义 Decimal 结构

// Rust: alloy::primitives::Address
// Zig: [20]u8 别名

// Rust: alloy::primitives::U256
// Zig: u256 (Zig 原生支持)

// Rust: uuid::Uuid
// Zig: [16]u8 + 辅助方法

// Rust: chrono::DateTime<Utc>
// Zig: i64 (Unix timestamp) 或 []const u8 (ISO 8601)

// Rust: serde_json::Value
// Zig: std.json.Value

// Rust: HashMap<K, V>
// Zig: std.HashMap 或 std.StringHashMap
```

### 7.2 错误类型转换

```zig
// Rust: thiserror 定义的错误枚举
// Zig: error 集合

pub const Error = error{
    // 网络
    ConnectionFailed,
    Timeout,
    // 认证
    InvalidSignature,
    InvalidCredentials,
    // 验证
    ValidationFailed,
    InvalidTickSize,
    // ...
};
```
