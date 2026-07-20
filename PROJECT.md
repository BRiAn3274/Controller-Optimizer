---
name: isaac-controller-mod
status: active
category: Personal
stack: lua
created: unknown
last-reviewed: 2026-07-20
remote: https://github.com/BRiAn3274/Controller-Optimizer.git
---

# Controller Optimizer

## 用途

为《The Binding of Isaac: Repentance+》提供手柄输入修复和优化。原项目目录已于 2026-07-19 从桌面迁入 Vibe。

当前测试版本为 1.7.0。后续维护以“只修正游戏读取到的输入，不生成攻击、不修改攻击实体”为边界。

## 检查命令

```bash
luac -p main.lua
lua tests/test_controller_optimizer.lua
```

Steam Workshop 上传步骤见 `tools/README.md`。

## 环境与数据

- 技术栈：Lua。
- Git 远端：`origin`。
- 项目背景资料：`docs/背景信息.md`。
- 兼容性边界与审计：`docs/兼容性审计.md`。
- 本地 Steam 账户配置：`.steam-workshop.env`，已被 Git 忽略，不得提交。

## 安全清理

可以删除：日志、`*.luac`、临时生成的 `workshop_build_item.vdf` 和工具生成的临时构建目录。

不可删除：`main.lua`、`metadata.xml`、测试、发布说明、封面图、Git 历史和 `.steam-workshop.env` 的唯一副本。
