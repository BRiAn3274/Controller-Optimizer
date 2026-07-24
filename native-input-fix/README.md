# Isaac Native Input Fix

《以撒的结合：忏悔+》的原生手柄输入过滤实验。它独立于根目录的 Lua Workshop Mod，目标是在联机不能启用 Lua Mod 时，仍然只在本机过滤游戏读取到的射击输入。

> 当前为预发布实验构建。自动加载安装器已完成 Windows x86 构建；Steam Deck 自动启动实机验证尚未完成，受控联机房主/客户端验证也尚未完成。

## Windows 用户：安装一次，之后正常从 Steam 启动

发布包已包含静态链接的 Windows x86 程序，不需要额外安装 Visual C++ 运行库。

1. 解压完整 zip，保持 `IsaacInputPatcher.exe`、`bootstp.dll` 和 `azazel_input_hook.dll` 在同一目录。
2. 在 Steam 中完全关闭 Isaac。
3. 双击 `IsaacInputPatcher.exe`，选择游戏目录中的 `isaac-ng.exe`。
4. 若 EXE 仍导入 `userenv`，安装器创建 `isaac-ng.exe.cofix-original` 并把该导入改为同长度的 `bootstp`；若汉化补丁已经安装，则不再修改 EXE，而是保存并链式调用其现有 `bootstp.dll`。
5. 此后直接从 Steam 启动游戏。兼容桥会先调用原有汉化 bootstrap（如有），否则转发系统 `userenv.dll`，再加载输入过滤 DLL。

安装器不分发汉化补丁代码或二进制。检测到其 `bootstp.dll` 时，会在本机保存为 `cofix_bootstrap_chain.dll` 并保持原有调用顺序；`inject.dll` 和 `language_unlocker.dll` 不会被修改。

## 卸载

完全关闭 Isaac 后运行 `IsaacInputUnpatcher.exe`，选择同一个 `isaac-ng.exe`。若安装前存在汉化 bootstrap，它会原样恢复；否则还原 `bootstp -> userenv`。随后只删除本项目的 payload 和所有权标记。Steam 的“验证游戏文件完整性”也可以恢复 EXE。

## 输入范围与安全边界

- 仅处理捕获到的本地输入对象和射击 action `4..7`。
- 不修改网络包、联机协议、远端状态、XInput、攻击实体、伤害、激光生命周期或存档。
- 只在已验证的 PE32/i386、输入 bridge 指纹和方法序言均匹配时安装主动 hook；输入对象只通过游戏自然调用被动捕获，不在启动期主动调用内部游戏函数。
- 当前已实测的目标：Repentance+ `1.9.7.17.J460`，Steam build `22878971`，Proton `9.0-203`。

## 配置与诊断

配置和诊断位于：`%LOCALAPPDATA%\IsaacNativeInputFix\`。

- `config/generic-test.ini`：普通阿撒泻勒方向值测试。
- `config/tainted-test.ini`：里阿撒泻勒触发/按住/方向测试。
- `config/diagnostic.ini`：只收集兼容性诊断，不修改输入。

当前正在将两种角色逻辑收敛为 DLL 内部的自动判断；在完成该验证前，不应把任意测试配置称为通用联机正式版。

`diagnostics.json` 中只有 `hook_status` 为 `generic-test-active` 或 `tainted-test-active`，且对应 hook 字段为 `true` 时，才表示运行时路径已实际启用。

## 开发

Windows x86 目标必须使用 MSVC：

```powershell
cmake -S . -B build -A Win32
cmake --build build --config Release
ctest --test-dir build -C Release --output-on-failure
cmake --build build --config Release --target package
```

技术记录见 [`docs/reverse-engineering.md`](docs/reverse-engineering.md)，Windows 安装细节见 [`docs/deployment-windows.md`](docs/deployment-windows.md)。
