//! 工具模块
//!
//! 提供各种实用工具函数和类型。

pub const dotenv = @import("dotenv.zig");

// 导出便捷类型和函数
pub const DotEnv = dotenv.DotEnv;
pub const DotEnvError = dotenv.DotEnvError;

/// 加载 .env 文件
pub const loadEnv = dotenv.load;

/// 尝试加载 .env 文件，如果不存在则返回空实例
pub const loadEnvOrEmpty = dotenv.loadOrEmpty;

test {
    _ = dotenv;
}
