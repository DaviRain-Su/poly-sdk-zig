//! 基础类型使用示例
//!
//! 演示 Decimal 和 Secret 类型的基本用法。
//! 运行: zig run examples/basic_types.zig

const std = @import("std");

// 导入类型（实际使用时从 poly 包导入）
const Decimal = @import("../src/types/decimal.zig").Decimal;
const Secret = @import("../src/types/secret.zig").Secret;
const SecretString = @import("../src/types/secret.zig").SecretString;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("=== Decimal 类型示例 ===\n\n", .{});

    // 从字符串创建 Decimal
    const price = try Decimal.fromString("0.65");
    const size = try Decimal.fromString("100");

    try stdout.print("价格: {f}\n", .{price});
    try stdout.print("数量: {f}\n", .{size});

    // 算术运算
    const total = price.mul(size);
    try stdout.print("总额: {f} (精确计算，无浮点误差)\n\n", .{total});

    // 比较
    const threshold = try Decimal.fromString("0.5");
    if (price.greaterThan(threshold)) {
        try stdout.print("价格 > 0.5\n", .{});
    }

    // 常量
    try stdout.print("Decimal.ZERO = {f}\n", .{Decimal.ZERO});
    try stdout.print("Decimal.ONE = {f}\n\n", .{Decimal.ONE});

    try stdout.print("=== Secret 类型示例 ===\n\n", .{});

    // 创建 Secret
    const api_key = SecretString.init("sk_live_xxxxxxxxxxxxx");

    // 格式化输出被保护
    try stdout.print("API Key: {f}\n", .{api_key});
    try stdout.print("（实际值被保护，输出 [REDACTED]）\n\n", .{});

    // 需要时可以 reveal
    const revealed = api_key.reveal();
    try stdout.print("Revealed: {s}\n", .{revealed});
    try stdout.print("（使用 reveal() 获取原始值）\n\n", .{});

    // 在结构体中使用
    const Credentials = struct {
        api_key: SecretString,
        passphrase: SecretString,
    };

    const creds = Credentials{
        .api_key = SecretString.init("my_api_key"),
        .passphrase = SecretString.init("my_passphrase"),
    };

    try stdout.print("凭证结构体:\n", .{});
    try stdout.print("  api_key: {f}\n", .{creds.api_key});
    try stdout.print("  passphrase: {f}\n", .{creds.passphrase});

    try stdout.print("\n=== 完成 ===\n", .{});
}
