# Windows 自动加载安装说明

## 包含内容

| 文件 | 用途 |
|---|---|
| `IsaacInputPatcher.exe` | 一次性安装自动加载链 |
| `IsaacInputUnpatcher.exe` | 一次性还原自动加载链 |
| `cofix.dll` | WinMM 转发 bootstrap，由游戏启动时加载 |
| `azazel_input_hook.dll` | 原生输入过滤 payload |
| `config/` | 诊断与角色测试配置模板 |

所有 EXE/DLL 均为 32 位。不要只复制其中一个文件，也不要把它们放到游戏目录后直接双击 DLL。

## 安装

1. 在 Steam 中退出 Isaac，并确认任务管理器中没有 `isaac-ng.exe`。
2. 解压发布包到任意临时目录。
3. 运行 `IsaacInputPatcher.exe`，在文件选择框中选游戏根目录的 `isaac-ng.exe`。
4. 等待“Automatic loader installed”成功提示。
5. 从 Steam 正常启动游戏。

安装器会在 EXE 同目录创建 `isaac-ng.exe.cofix-original`，然后只把 PE 导入表中的 `WINMM.dll` 改为同长度的 `cofix.dll`。它不修改 `.text` 代码，不替换汉化补丁的加载链，不需要常驻启动器。

## 卸载与恢复

1. 完全退出游戏。
2. 运行 `IsaacInputUnpatcher.exe` 并选择同一个 `isaac-ng.exe`。
3. 它会恢复 `cofix.dll -> WINMM.dll` 并删除本项目的 loader DLL。

如遇异常，可在 Steam 中使用“验证游戏文件完整性”。不要手动删除汉化补丁的 `bootstp.dll`、`inject.dll` 或 `language_unlocker.dll`。

## 当前验证范围

自动加载架构已通过 Win32 CI 构建和打包。普通阿撒泻勒与里阿撒泻勒的输入滤波曾在 Steam Deck + Proton 的手动注入路径下完成初测；自动加载路径和真实联机 host/client 矩阵仍待实机验证。因此发布时必须标记为预发布或实验版。
