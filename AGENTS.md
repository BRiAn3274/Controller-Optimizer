# Controller Optimizer 维护说明

## 1. 功能与范围

Controller Optimizer 是《以撒的结合：忏悔+》的 Lua 创意工坊 Mod，用于改善
手柄右摇杆控制硫磺火时的输入体验。它只在游戏读取输入时返回经过处理的值，
不生成攻击实体、不改变伤害，也不直接修改激光生命周期。

当前功能：

- 普通阿撒泻勒和硫磺火的方向稳定与短暂掉采样保护；
- 里阿撒泻勒的原生触发、按住、释放、重新武装输入时序；
- 持有 Analog Stick 时保留完整的 360 度瞄准；
- 持有玄秘魔眼、豆奶、十字准星时完整放行射击输入；
- 可选的 Mars 左摇杆误触保护；
- 可选的 Schoolbag 双主动道具快速切换；
- 仅针对原版小硫磺火和小蒙斯特的跟班释放兼容。

## 2. 作用原理与维护边界

运行入口是 `main.lua` 中的 `MC_INPUT_ACTION` 回调。普通硫磺火只处理
`GET_ACTION_VALUE`，`pressed` 与 `triggered` 保持原生，保证玩家松开摇杆时
游戏立即收到释放输入。

里阿撒泻勒是唯一会重建输入时序的路径：每次稳定的摇杆手势只给出一次原生
触发，之后持续读取实时方向完成蓄力。玄秘魔眼、豆奶、十字准星会接管瞄准
或射击节奏，因此必须对全部射击 Hook 返回 `nil`，把完整原生输入还给游戏。

玩家状态必须使用稳定的引擎身份作为键。不要以临时 Lua userdata wrapper
本身作为跨帧状态键。

## 3. GitHub 与创意工坊

- GitHub 仓库：<https://github.com/BRiAn3274/Controller-Optimizer>
- Steam Workshop 条目：`3731198516`
- Steam App ID：`250900`
- 当前开发版本：`1.7.2`

## 4. 仓库文件

| 路径 | 用途 |
|---|---|
| `AGENTS.md` | 本维护说明。 |
| `README.md` | GitHub 仓库公开说明。 |
| `PROJECT.md` | 本地项目记录与常用检查命令。 |
| `main.lua` | Mod 运行时逻辑和全部输入处理。 |
| `metadata.xml` | 创意工坊 ID、版本和元数据。 |
| `tests/test_controller_optimizer.lua` | 可重复执行的输入回归测试。 |
| `CHANGELOG.md` | 版本行为变更。 |
| `release-notes/` | 面向创意工坊的历史发布说明。 |
| `docs/背景信息.md` | 项目背景。 |
| `docs/兼容性审计.md` | 输入所有权和兼容性边界。 |
| `tools/upload_workshop.sh` | 创意工坊检查、打包与上传脚本。 |
| `tools/README.md` | 上传脚本说明。 |
| `ControllerOptimizer_cover.png` | Mod 内使用的封面图。 |
| `ControllerOptimizer_preview.jpg` | 创意工坊上传预览图。 |

上传脚本只会打包 `main.lua`、`metadata.xml`、
`ControllerOptimizer_cover.png`。测试、工具、文档与 Git 文件不会进入创意工坊
包。

## 5. 本机与 Steam Deck 路径

| 位置 | 用途 |
|---|---|
| `/Users/a1/Documents/Codex 2/Controller-Optimizer` | 当前本机仓库。 |
| `/Users/a1/Vibe/Projects/Personal/isaac-controller-mod/.steam-workshop.env` | Steam 用户名配置；不得提交。 |
| `/Users/a1/steamcmd/steamcmd.sh` | 创意工坊上传使用的 SteamCMD。 |
| `/Users/a1/.ssh/controller_optimizer_deck_ed25519` | 个人 Steam Deck SSH 私钥；不得公开或替换。 |
| `/home/deck/.local/share/Steam/steamapps/workshop/content/250900/3731198516` | Steam Deck 上订阅到的 Mod 目录。 |

直接修改 Deck 的创意工坊目录仅用于临时验证，Steam 同步可能将其覆盖。正式发布
必须通过 SteamCMD 上传。

## 6. 如何连接 Steam Deck

前提：Steam Deck 已启用 SSH、与本机在同一网络，并使用当前密钥与 IP。

```bash
ssh -i "/Users/a1/.ssh/controller_optimizer_deck_ed25519" \
  deck@192.168.1.235
```

检查连接和 Isaac 是否正在运行：

```bash
ssh -i "/Users/a1/.ssh/controller_optimizer_deck_ed25519" \
  deck@192.168.1.235 \
  'if pgrep -f "[i]saac-ng.exe" >/dev/null; then echo running; else echo stopped; fi'
```

查看 Deck 上当前 Mod 的版本：

```bash
ssh -i "/Users/a1/.ssh/controller_optimizer_deck_ed25519" \
  deck@192.168.1.235 \
  'rg -n "local VERSION|<version>" \
  "$HOME/.local/share/Steam/steamapps/workshop/content/250900/3731198516/main.lua" \
  "$HOME/.local/share/Steam/steamapps/workshop/content/250900/3731198516/metadata.xml"'
```

涉及替换 Deck 上 Mod 文件时，必须先确认 Isaac 已关闭，并在替换前建立远端备份。
不要把 SSH 私钥、Steam 密码或 Steam Guard 验证码写入命令、文件或聊天。

## 7. 发布与个人上传流程

1. 同步更新 `main.lua`、`metadata.xml`、`CHANGELOG.md` 中的版本与说明。
2. 发布前执行：

   ```bash
   luac -p main.lua
   lua tests/test_controller_optimizer.lua
   xmllint --noout metadata.xml
   git status --short
   ```

3. 提交发布内容并推送 `main` 到 GitHub。
4. 从仅保存用户名的配置中加载 Steam 用户名，运行上传脚本：

   ```bash
   cd "/Users/a1/Documents/Codex 2/Controller-Optimizer"
   set -a
   source "/Users/a1/Vibe/Projects/Personal/isaac-controller-mod/.steam-workshop.env"
   set +a
   STEAMCMD="/Users/a1/steamcmd/steamcmd.sh" \
     ./tools/upload_workshop.sh \
     --user "$STEAM_USERNAME" \
     --note "Version X.Y.Z: 简短的更新说明"
   ```

5. SteamCMD 会要求输入 Steam 账号密码；启用手机令牌时，还需在 Steam 手机
   App 中确认登录。密码、验证码不应存入配置文件或发送到聊天。
6. 上传成功后脚本才会创建注释标签 `vX.Y.Z`，再推送该标签：

   ```bash
   git push origin "vX.Y.Z"
   ```

默认上传会保留创意工坊页面已有的标题与描述。只有明确要用 `metadata.xml`
覆盖公开页面时，才添加 `--sync-page-metadata`。使用 `--dry-run` 可只验证打包
而不登录 Steam；不要使用 `--allow-dirty`。只有缺少可用 Lua 解释器时才使用
`--skip-tests`。
