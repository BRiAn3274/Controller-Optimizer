# Windows 自动加载安装说明

## 包含内容

| 文件 | 用途 |
|---|---|
| `IsaacInputPatcher.exe` | 一次性安装自动加载链 |
| `IsaacInputUnpatcher.exe` | 一次性还原自动加载链 |
| `bootstp.dll` | `userenv` 兼容桥，由游戏已有初始化调用点加载 |
| `azazel_input_hook.dll` | 原生输入过滤 payload |
| `config/` | 诊断与角色测试配置模板 |

所有 EXE/DLL 均为 32 位。不要只复制其中一个文件，也不要把它们放到游戏目录后直接双击 DLL。

## 安装

1. 在 Steam 中退出 Isaac，并确认任务管理器中没有 `isaac-ng.exe`。
2. 解压发布包到任意临时目录。
3. 运行 `IsaacInputPatcher.exe`，在文件选择框中选游戏根目录的 `isaac-ng.exe`。
4. 等待“Automatic loader installed”成功提示。
5. 从 Steam 正常启动游戏。

未安装其他 bootstrap 时，安装器会创建 `isaac-ng.exe.cofix-original`，只把经 PE32/i386 校验且全文件唯一的动态库名 `userenv\0` 等长改为 `bootstp\0`。若汉化补丁已经完成同一改动，则 EXE 不再变化；现有 `bootstp.dll` 会保存为 `cofix_bootstrap_chain.dll`，由本项目桥接后继续原样调用。安装器不修改 `.text`，也不需要常驻启动器。

## 卸载与恢复

1. 完全退出游戏。
2. 运行 `IsaacInputUnpatcher.exe` 并选择同一个 `isaac-ng.exe`。
3. 它会恢复安装前的汉化 `bootstp.dll`；若安装前没有 bootstrap，则恢复 `bootstp -> userenv`。

如遇异常，可在 Steam 中使用“验证游戏文件完整性”。不要手动删除汉化补丁的 `inject.dll` 或 `language_unlocker.dll`。

## 当前验证范围

旧的 WinMM 自动加载试验已撤销。新的 `userenv/bootstp` 兼容链必须先通过 Win32 CI、安装/卸载事务测试和 Steam Deck 实机验证；真实联机 host/client 矩阵也仍待验证。因此发布时必须标记为预发布或实验版。
