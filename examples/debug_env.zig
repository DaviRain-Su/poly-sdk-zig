//! 调试 .env 文件加载

const std = @import("std");
const poly = @import("poly_sdk_zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("========================================\n", .{});
    std.debug.print("调试 .env 文件加载\n", .{});
    std.debug.print("========================================\n\n", .{});

    std.debug.print("加载 .env 文件...\n", .{});

    var env = poly.loadEnvOrEmpty(allocator, ".env");
    defer env.deinit();

    std.debug.print("\n检查 SMART_TRADER_DRY_RUN:\n", .{});

    const raw_value = env.get("SMART_TRADER_DRY_RUN");
    if (raw_value) |v| {
        std.debug.print("  原始值: '{s}'\n", .{v});
        std.debug.print("  长度: {d}\n", .{v.len});
        std.debug.print("  字节: ", .{});
        for (v) |b| {
            std.debug.print("{x:0>2} ", .{b});
        }
        std.debug.print("\n", .{});
    } else {
        std.debug.print("  未找到!\n", .{});
    }

    const dry_run = env.getBool("SMART_TRADER_DRY_RUN", true);
    std.debug.print("  getBool 结果: {}\n", .{dry_run});

    std.debug.print("\n检查 AUTO_TRADER_DRY_RUN:\n", .{});
    const auto_raw = env.get("AUTO_TRADER_DRY_RUN");
    if (auto_raw) |v| {
        std.debug.print("  原始值: '{s}'\n", .{v});
    } else {
        std.debug.print("  未找到!\n", .{});
    }

    std.debug.print("\n检查 POLY_PRIVATE_KEY:\n", .{});
    const pk = env.get("POLY_PRIVATE_KEY");
    if (pk) |v| {
        std.debug.print("  找到, 长度: {d}\n", .{v.len});
        if (v.len > 0) {
            std.debug.print("  前4个字符: {s}...\n", .{v[0..@min(4, v.len)]});
        }
    } else {
        std.debug.print("  未找到!\n", .{});
    }

    std.debug.print("\n检查 SMART_TRADER_MODE:\n", .{});
    const mode = env.get("SMART_TRADER_MODE");
    if (mode) |v| {
        std.debug.print("  原始值: '{s}'\n", .{v});
    } else {
        std.debug.print("  未找到!\n", .{});
    }

    std.debug.print("\n========================================\n", .{});
    std.debug.print("调试完成\n", .{});
    std.debug.print("========================================\n", .{});
}
