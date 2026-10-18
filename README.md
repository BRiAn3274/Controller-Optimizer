# Controller Optimizer

《以撒的结合：忏悔+》手柄输入修复创意工坊 Mod。仓库只维护 Lua 实现。

## 项目结构

| 目录 | 内容 |
|---|---|
| 根目录 | `Controller Optimizer` Lua 创意工坊 Mod |

## Lua 创意工坊 Mod

根目录中的 `main.lua` 是创意工坊 Mod 的运行入口（当前版本 `1.7.3`）。它处理普通阿撒泻勒的硫磺火方向、里阿撒泻勒的触发/蓄力时序，以及可选的 Mars、Schoolbag 与部分跟班兼容。玄秘魔眼、豆奶、十字准星和鲁多维科技术会完整放行射击输入，保留这些攻击形态的原生 360° 瞄准。

1.7.3 在 Repentance+ 中统一普通硫磺火的方向、按住和触发状态，针对蓄满后缓慢收杆时的中间行程短喷中断进行修正。一次手势只在起始帧触发，持续收杆不重复触发；回中防抖默认两帧。自动输入回归已覆盖该契约，实际攻击表现仍需实机复测。普通 Repentance 保留原有处理方式。

运行时边界：只在 `MC_INPUT_ACTION` 返回过滤后的输入；不生成攻击、不修改攻击实体、伤害、激光生命周期或网络数据。

本地检查：

```bash
luac -p main.lua
lua tests/test_controller_optimizer.lua
xmllint --noout metadata.xml
```

Workshop 上传说明见 [`tools/README.md`](tools/README.md)，兼容性边界见 [`docs/兼容性审计.md`](docs/兼容性审计.md)。
