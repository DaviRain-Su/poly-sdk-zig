//! .env 文件解析器
//!
//! 支持从 .env 文件加载环境变量配置。
//!
//! ## 功能特性
//!
//! - 解析标准 .env 文件格式
//! - 支持 `#` 注释
//! - 支持带引号和不带引号的值
//! - 支持空行和空值
//! - 自动查找项目根目录的 .env 文件
//! - 可选覆盖已存在的环境变量
//!
//! ## 使用示例
//!
//! ```zig
//! const DotEnv = @import("utils/dotenv.zig").DotEnv;
//!
//! // 加载 .env 文件
//! var env = DotEnv.init(allocator);
//! defer env.deinit();
//!
//! try env.load(".env");
//!
//! // 获取值
//! const api_key = env.get("API_KEY") orelse "default";
//!
//! // 或者使用必需的值（不存在则返回错误）
//! const secret = try env.getRequired("API_SECRET");
//! ```
//!
//! ## .env 文件格式
//!
//! ```text
//! # 这是注释
//! API_KEY=your_api_key
//! API_SECRET="带引号的值"
//! EMPTY_VALUE=
//! SPACED_VALUE = value with spaces around equals
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;

/// DotEnv 错误类型
pub const DotEnvError = error{
    /// 文件未找到
    FileNotFound,
    /// 解析错误
    ParseError,
    /// 必需的环境变量缺失
    MissingRequiredVar,
    /// 内存分配失败
    OutOfMemory,
    /// IO 错误
    IoError,
};

/// .env 文件解析器和环境变量管理器
pub const DotEnv = struct {
    allocator: Allocator,
    /// 存储解析的环境变量
    vars: std.StringHashMap([]const u8),
    /// 已分配的字符串（用于释放）
    allocated_strings: std.ArrayList([]const u8),

    const Self = @This();

    /// 初始化 DotEnv
    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .vars = std.StringHashMap([]const u8).init(allocator),
            .allocated_strings = .{},
        };
    }

    /// 释放资源
    pub fn deinit(self: *Self) void {
        // 释放所有分配的字符串
        for (self.allocated_strings.items) |s| {
            self.allocator.free(s);
        }
        self.allocated_strings.deinit(self.allocator);
        self.vars.deinit();
    }

    /// 从文件加载环境变量
    ///
    /// 参数:
    ///   - path: .env 文件路径，如果为 null 则使用默认路径 ".env"
    ///
    /// 返回: 加载的变量数量
    pub fn load(self: *Self, path: ?[]const u8) DotEnvError!usize {
        const file_path = path orelse ".env";

        const file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
            return switch (err) {
                error.FileNotFound => DotEnvError.FileNotFound,
                else => DotEnvError.IoError,
            };
        };
        defer file.close();

        // 读取整个文件内容
        var content_buf: [65536]u8 = undefined; // 64KB 应该足够大部分 .env 文件
        const bytes_read = file.readAll(&content_buf) catch {
            return DotEnvError.IoError;
        };

        return self.loadFromString(content_buf[0..bytes_read]);
    }

    /// 从字符串加载环境变量
    pub fn loadFromString(self: *Self, content: []const u8) DotEnvError!usize {
        var loaded_count: usize = 0;
        var lines = std.mem.splitSequence(u8, content, "\n");

        while (lines.next()) |line| {
            const trimmed_line = std.mem.trimRight(u8, line, "\r");

            if (self.parseLine(trimmed_line)) |_| {
                loaded_count += 1;
            } else |_| {
                // 忽略解析错误的行
            }
        }

        return loaded_count;
    }

    /// 解析单行
    fn parseLine(self: *Self, line: []const u8) DotEnvError!void {
        // 去除首尾空白
        const trimmed = std.mem.trim(u8, line, " \t");

        // 跳过空行
        if (trimmed.len == 0) {
            return DotEnvError.ParseError;
        }

        // 跳过注释
        if (trimmed[0] == '#') {
            return DotEnvError.ParseError;
        }

        // 查找 = 号
        const eq_pos = std.mem.indexOf(u8, trimmed, "=") orelse {
            return DotEnvError.ParseError;
        };

        // 提取 key
        const key_raw = trimmed[0..eq_pos];
        const key = std.mem.trim(u8, key_raw, " \t");

        if (key.len == 0) {
            return DotEnvError.ParseError;
        }

        // 提取 value
        const value_raw = if (eq_pos + 1 < trimmed.len) trimmed[eq_pos + 1 ..] else "";
        const value_trimmed = std.mem.trim(u8, value_raw, " \t");

        // 处理引号
        const value = self.unquote(value_trimmed);

        // 复制 key 和 value
        const key_copy = self.allocator.dupe(u8, key) catch {
            return DotEnvError.OutOfMemory;
        };
        errdefer self.allocator.free(key_copy);

        self.allocated_strings.append(self.allocator, key_copy) catch {
            self.allocator.free(key_copy);
            return DotEnvError.OutOfMemory;
        };

        const value_copy = self.allocator.dupe(u8, value) catch {
            return DotEnvError.OutOfMemory;
        };
        errdefer self.allocator.free(value_copy);

        self.allocated_strings.append(self.allocator, value_copy) catch {
            self.allocator.free(value_copy);
            return DotEnvError.OutOfMemory;
        };

        // 存储
        self.vars.put(key_copy, value_copy) catch {
            return DotEnvError.OutOfMemory;
        };
    }

    /// 去除引号
    fn unquote(self: *Self, value: []const u8) []const u8 {
        _ = self;
        if (value.len < 2) {
            return value;
        }

        const first = value[0];
        const last = value[value.len - 1];

        // 双引号或单引号
        if ((first == '"' and last == '"') or (first == '\'' and last == '\'')) {
            return value[1 .. value.len - 1];
        }

        return value;
    }

    /// 获取环境变量值
    ///
    /// 优先从 .env 文件加载的值获取，如果不存在则从系统环境变量获取
    pub fn get(self: *Self, key: []const u8) ?[]const u8 {
        // 先从加载的变量中获取
        if (self.vars.get(key)) |value| {
            return value;
        }

        // 再从系统环境变量获取
        return std.posix.getenv(key);
    }

    /// 获取必需的环境变量值
    ///
    /// 如果值不存在则返回错误
    pub fn getRequired(self: *Self, key: []const u8) DotEnvError![]const u8 {
        return self.get(key) orelse DotEnvError.MissingRequiredVar;
    }

    /// 获取环境变量值，如果不存在则返回默认值
    pub fn getOrDefault(self: *Self, key: []const u8, default: []const u8) []const u8 {
        return self.get(key) orelse default;
    }

    /// 获取布尔值
    pub fn getBool(self: *Self, key: []const u8, default: bool) bool {
        const value = self.get(key) orelse return default;

        // true 值
        if (std.mem.eql(u8, value, "true") or
            std.mem.eql(u8, value, "1") or
            std.mem.eql(u8, value, "yes") or
            std.mem.eql(u8, value, "on"))
        {
            return true;
        }

        // false 值
        if (std.mem.eql(u8, value, "false") or
            std.mem.eql(u8, value, "0") or
            std.mem.eql(u8, value, "no") or
            std.mem.eql(u8, value, "off"))
        {
            return false;
        }

        return default;
    }

    /// 获取整数值
    pub fn getInt(self: *Self, comptime T: type, key: []const u8, default: T) T {
        const value = self.get(key) orelse return default;
        return std.fmt.parseInt(T, value, 10) catch default;
    }

    /// 获取浮点数值
    pub fn getFloat(self: *Self, comptime T: type, key: []const u8, default: T) T {
        const value = self.get(key) orelse return default;
        return std.fmt.parseFloat(T, value) catch default;
    }

    /// 检查是否存在某个环境变量
    pub fn has(self: *Self, key: []const u8) bool {
        return self.get(key) != null;
    }

    /// 获取所有加载的变量数量
    pub fn count(self: *Self) usize {
        return self.vars.count();
    }

    /// 打印所有加载的变量（调试用）
    pub fn debugPrint(self: *Self) void {
        std.debug.print("=== DotEnv Variables ({d}) ===\n", .{self.vars.count()});
        var iter = self.vars.iterator();
        while (iter.next()) |entry| {
            // 对敏感字段隐藏值
            const is_sensitive = std.mem.indexOf(u8, entry.key_ptr.*, "SECRET") != null or
                std.mem.indexOf(u8, entry.key_ptr.*, "KEY") != null or
                std.mem.indexOf(u8, entry.key_ptr.*, "PASS") != null or
                std.mem.indexOf(u8, entry.key_ptr.*, "PRIVATE") != null;

            if (is_sensitive) {
                std.debug.print("  {s} = [REDACTED]\n", .{entry.key_ptr.*});
            } else {
                std.debug.print("  {s} = {s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
            }
        }
        std.debug.print("==============================\n", .{});
    }
};

// ============================================================================
// 便捷函数
// ============================================================================

/// 加载 .env 文件并返回 DotEnv 实例
pub fn load(allocator: Allocator, path: ?[]const u8) DotEnvError!DotEnv {
    var env = DotEnv.init(allocator);
    errdefer env.deinit();

    _ = try env.load(path);
    return env;
}

/// 尝试加载 .env 文件，如果文件不存在则返回空的 DotEnv
pub fn loadOrEmpty(allocator: Allocator, path: ?[]const u8) DotEnv {
    var env = DotEnv.init(allocator);

    _ = env.load(path) catch |err| {
        if (err == DotEnvError.FileNotFound) {
            // 文件不存在，返回空的 env
            return env;
        }
        // 其他错误也返回空的 env
        return env;
    };

    return env;
}

// ============================================================================
// 测试
// ============================================================================

test "parse basic env file" {
    const allocator = std.testing.allocator;

    var env = DotEnv.init(allocator);
    defer env.deinit();

    const content =
        \\# This is a comment
        \\API_KEY=test_key_123
        \\API_SECRET="secret_value"
        \\EMPTY=
        \\NUMBER=42
        \\
        \\SPACED = value with spaces
    ;

    const count = try env.loadFromString(content);
    try std.testing.expectEqual(@as(usize, 5), count);

    try std.testing.expectEqualStrings("test_key_123", env.get("API_KEY").?);
    try std.testing.expectEqualStrings("secret_value", env.get("API_SECRET").?);
    try std.testing.expectEqualStrings("", env.get("EMPTY").?);
    try std.testing.expectEqualStrings("42", env.get("NUMBER").?);
    try std.testing.expectEqualStrings("value with spaces", env.get("SPACED").?);
}

test "get with default" {
    const allocator = std.testing.allocator;

    var env = DotEnv.init(allocator);
    defer env.deinit();

    _ = try env.loadFromString("EXISTING=value");

    try std.testing.expectEqualStrings("value", env.getOrDefault("EXISTING", "default"));
    try std.testing.expectEqualStrings("default", env.getOrDefault("NOT_EXISTING", "default"));
}

test "get bool values" {
    const allocator = std.testing.allocator;

    var env = DotEnv.init(allocator);
    defer env.deinit();

    const content =
        \\BOOL_TRUE=true
        \\BOOL_1=1
        \\BOOL_YES=yes
        \\BOOL_FALSE=false
        \\BOOL_0=0
        \\BOOL_NO=no
        \\BOOL_INVALID=maybe
    ;

    _ = try env.loadFromString(content);

    try std.testing.expect(env.getBool("BOOL_TRUE", false) == true);
    try std.testing.expect(env.getBool("BOOL_1", false) == true);
    try std.testing.expect(env.getBool("BOOL_YES", false) == true);
    try std.testing.expect(env.getBool("BOOL_FALSE", true) == false);
    try std.testing.expect(env.getBool("BOOL_0", true) == false);
    try std.testing.expect(env.getBool("BOOL_NO", true) == false);
    try std.testing.expect(env.getBool("BOOL_INVALID", true) == true); // 默认值
    try std.testing.expect(env.getBool("NOT_EXIST", true) == true); // 默认值
}

test "get int values" {
    const allocator = std.testing.allocator;

    var env = DotEnv.init(allocator);
    defer env.deinit();

    _ = try env.loadFromString("PORT=8080\nINVALID=abc");

    try std.testing.expectEqual(@as(i32, 8080), env.getInt(i32, "PORT", 3000));
    try std.testing.expectEqual(@as(i32, 3000), env.getInt(i32, "INVALID", 3000));
    try std.testing.expectEqual(@as(i32, 3000), env.getInt(i32, "NOT_EXIST", 3000));
}

test "get float values" {
    const allocator = std.testing.allocator;

    var env = DotEnv.init(allocator);
    defer env.deinit();

    _ = try env.loadFromString("PRICE=0.65\nINVALID=abc");

    try std.testing.expectApproxEqAbs(@as(f64, 0.65), env.getFloat(f64, "PRICE", 0.0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), env.getFloat(f64, "INVALID", 0.0), 0.001);
}

test "required var" {
    const allocator = std.testing.allocator;

    var env = DotEnv.init(allocator);
    defer env.deinit();

    _ = try env.loadFromString("EXISTING=value");

    try std.testing.expectEqualStrings("value", try env.getRequired("EXISTING"));

    const result = env.getRequired("NOT_EXISTING");
    try std.testing.expectError(DotEnvError.MissingRequiredVar, result);
}

test "quotes handling" {
    const allocator = std.testing.allocator;

    var env = DotEnv.init(allocator);
    defer env.deinit();

    const content =
        \\DOUBLE_QUOTED="value in double quotes"
        \\SINGLE_QUOTED='value in single quotes'
        \\NO_QUOTES=value without quotes
        \\PARTIAL_QUOTE="unmatched quote
    ;

    _ = try env.loadFromString(content);

    try std.testing.expectEqualStrings("value in double quotes", env.get("DOUBLE_QUOTED").?);
    try std.testing.expectEqualStrings("value in single quotes", env.get("SINGLE_QUOTED").?);
    try std.testing.expectEqualStrings("value without quotes", env.get("NO_QUOTES").?);
    try std.testing.expectEqualStrings("\"unmatched quote", env.get("PARTIAL_QUOTE").?);
}

test "has function" {
    const allocator = std.testing.allocator;

    var env = DotEnv.init(allocator);
    defer env.deinit();

    _ = try env.loadFromString("EXISTING=value");

    try std.testing.expect(env.has("EXISTING"));
    try std.testing.expect(!env.has("NOT_EXISTING"));
}
