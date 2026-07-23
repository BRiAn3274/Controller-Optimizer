# Controller Optimizer

《以撒的结合：忏悔+》手柄输入修复项目。仓库同时维护两个**独立**实现：Lua 创意工坊 Mod 与原生 Windows 自动加载实验。两者用途、部署方式和联机结论不同，不能混用。

## 项目结构

| 目录 | 内容 | 面向场景 |
|---|---|---|
| 根目录 | `Controller Optimizer` Lua Mod | 创意工坊、本地 Mod 游戏 |
| [`native-input-fix/`](native-input-fix/README.md) | C++ Win32 原生输入过滤与自动加载安装器 | Lua Mod 无法启用时的本地输入实验 |

## Lua 创意工坊 Mod

根目录中的 `main.lua` 是已发布的 Workshop Mod（当前稳定版 `1.7.0`）。它处理普通阿撒泻勒的硫磺火方向、里阿撒泻勒的触发/蓄力时序，以及可选的 Mars、Schoolbag 与部分跟班兼容。

运行时边界：只在 `MC_INPUT_ACTION` 返回过滤后的输入；不生成攻击、不修改攻击实体、伤害、激光生命周期或网络数据。

本地检查：

```bash
luac -p main.lua
lua tests/test_controller_optimizer.lua
xmllint --noout metadata.xml
```

Workshop 上传说明见 [`tools/README.md`](tools/README.md)，兼容性边界见 [`docs/兼容性审计.md`](docs/兼容性审计.md)。

## 原生自动加载实验

[`native-input-fix/`](native-input-fix/README.md) 是独立 C++ 项目，不加载 Lua Mod。它的目标是安装一次后仍从 Steam 正常启动游戏：`IsaacInputPatcher.exe` 修改 Isaac 的 WinMM 导入名，让私有 `cofix.dll` 在游戏启动时转发原 WinMM 函数并加载输入过滤 DLL。

这个自动加载链不会覆盖汉化补丁已有的 `bootstp.dll`、`inject.dll` 或 `language_unlocker.dll`。它仍是实验项目，只支持已验证的游戏版本，尚未完成受控的联机房主/客户端验证。完整部署与技术说明在子目录内。

## 维护规则

- Lua Mod 的发布文件只在仓库根目录维护；不要把 C++ DLL、构建目录或 CI 二进制提交到根目录。
- 原生项目的源代码、CMake、测试和文档只放在 `native-input-fix/`。
- 两个项目改动分别测试、分别发布；不要把任一项目的“可用”结论推广到另一个项目。
- 不提交 Steam 密码、Steam Guard、Deck 密码、SSH 私钥、Deck 日志或发布产物。
