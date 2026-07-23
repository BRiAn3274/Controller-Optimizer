---
name: isaac-native-input-fix
type: personal
status: active
remote: https://github.com/BRiAn3274/Isaac-Native-Input-Fix.git
---

# Isaac Native Input Fix

Win32 native input-filter framework for The Binding of Isaac: Repentance+.

## Commands

```powershell
cmake -S . -B build -A Win32
cmake --build build --config Release
ctest --test-dir build -C Release --output-on-failure
cmake --build build --config Release --target package
```

The runtime is fail-closed. Until a game-version-specific native input hook is
validated, the payload runs in diagnostics-only mode.
