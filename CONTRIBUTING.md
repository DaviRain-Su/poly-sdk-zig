# 贡献指南

感谢你帮助改进 `poly-sdk-zig`！

## 如何贡献

1. **Fork 仓库**并创建功能分支
2. **编写代码**，遵循 [AGENTS.md](./AGENTS.md) 中的编码规范
3. **添加测试**（如适用）
4. **运行测试**确保通过：`zig build test`
5. **提交 PR**，包含清晰的变更描述和动机

## 开发流程

```bash
# 克隆你的 fork
git clone https://github.com/<你的用户名>/poly-sdk-zig.git
cd poly-sdk-zig

# 创建功能分支
git checkout -b feature/你的功能名

# 运行测试
zig build test

# 提交变更
git add .
git commit -m "feat: 添加xxx功能"
git push origin feature/你的功能名
```

## 代码规范

- **Zig 版本**: >= 0.15.2
- **文档语言**: 中文
- **代码注释**: 英文（遵循 Zig 惯例）
- 详见 [AGENTS.md](./AGENTS.md)

## 文档规范

- 所有 `.md` 文件使用中文
- 代码已实现后再写文档（不预设计）
- 文档结构镜像代码结构

## 报告问题

- 使用 GitHub Issues 报告 bug
- 包含复现步骤和 Zig 版本
- 安全漏洞请参阅 [SECURITY.md](./SECURITY.md)

## 相关文档

- [ROADMAP.md](./ROADMAP.md) - 版本规划
- [AGENTS.md](./AGENTS.md) - 编码规范
- [CHANGELOG.dev.md](./CHANGELOG.dev.md) - 开发日志
