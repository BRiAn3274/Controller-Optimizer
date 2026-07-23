# Windows automatic installation

## Install once

1. Extract the complete package to a folder you control. Keep
   `IsaacInputPatcher.exe`, `cofix.dll`, and `azazel_input_hook.dll` together.
2. Keep Lua mods disabled for testing and close Isaac completely.
3. Double-click `IsaacInputPatcher.exe` and select the game's `isaac-ng.exe`.
4. The installer creates `isaac-ng.exe.cofix-original`, changes the WinMM import
   to `cofix.dll`, and places the two loader DLLs beside the game executable.
5. From then on, start Isaac normally through Steam. The loader runs with the
   game; there is no per-session injector step.

The installer deliberately uses its own `cofix.dll` name. It does not overwrite
the Chinese patch's `bootstp.dll`, `inject.dll`, or `language_unlocker.dll`.

## Troubleshooting

- Patcher cannot write: close Isaac and run the patcher with the permissions
  required by the chosen game directory.
- Game update: the update may restore `WINMM.dll`; run the patcher again after
  confirming the project supports the updated game build.
- No active hook: inspect `%LOCALAPPDATA%\IsaacNativeInputFix\diagnostics.json`.
  The matching `hook_status` must be `generic-test-active` or `tainted-test-active`.
- After a game update: stop. The payload intentionally refuses unapproved
  executable hashes; a new compatible build is required.

This is a local-input experiment. It does not install a Lua mod or modify game
network traffic, but controlled online host/client testing is still required.
