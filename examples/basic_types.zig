//! 基础类型使用示例
//!
//! 演示 Decimal 和 Secret 类型的基本用法。
//! 运行: zig build run-basic_types

const std = @import("std");
const poly = @import("poly_sdk_zig");

// 导入类型
const Decimal = poly.Decimal;
const Secret = poly.Secret;
const SecretString = poly.SecretString;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Decimal 类型示例 ===\n\n", .{});

    // 从字符串创建 Decimal
    const price = try Decimal.fromString("0.65");
    const size = try Decimal.fromString("100");

    const price_str = try price.toString(allocator);
    defer allocator.free(price_str);
    const size_str = try size.toString(allocator);
    defer allocator.free(size_str);

    std.debug.print("价格: {s}\n", .{price_str});
    std.debug.print("数量: {s}\n", .{size_str});

    // 算术运算
    const total = price.mul(size);
    const total_str = try total.toString(allocator);
    defer allocator.free(total_str);
    std.debug.print("总额: {s} (精确计算，无浮点误差)\n\n", .{total_str});

    // 比较
    const threshold = try Decimal.fromString("0.5");
    if (price.greaterThan(threshold)) {
        std.debug.print("价格 > 0.5\n", .{});
    }

    // 常量
    const zero_str = try Decimal.ZERO.toString(allocator);
    defer allocator.free(zero_str);
    const one_str = try Decimal.ONE.toString(allocator);
    defer allocator.free(one_str);
    std.debug.print("Decimal.ZERO = {s}\n", .{zero_str});
    std.debug.print("Decimal.ONE = {s}\n\n", .{one_str});

    std.debug.print("=== Secret 类型示例 ===\n\n", .{});

    // 创建 Secret
    const api_key = SecretString.init("sk_live_xxxxxxxxxxxxx");

    // Secret 输出被保护
    std.debug.print("API Key: [REDACTED] (Secret 类型保护敏感数据)\n", .{});

    // 需要时可以 reveal
    const revealed = api_key.reveal();
    std.debug.print("Revealed: {s}\n", .{revealed});
    std.debug.print("（使用 reveal() 获取原始值）\n\n", .{});

    // 在结构体中使用
    const Credentials = struct {
        api_key: SecretString,
        passphrase: SecretString,
    };

    const creds = Credentials{
        .api_key = SecretString.init("my_api_key"),
        .passphrase = SecretString.init("my_passphrase"),
    };

    std.debug.print("凭证结构体:\n", .{});
    std.debug.print("  api_key: [REDACTED]\n", .{});
    std.debug.print("  passphrase: [REDACTED]\n", .{});
    std.debug.print("  (实际值: {s}, {s})\n", .{ creds.api_key.reveal(), creds.passphrase.reveal() });

    std.debug.print("\n=== 完成 ===\n", .{});
}
