# Isaac Native Input Fix

Experimental Win32 input-filter framework for controller aiming in *The
Binding of Isaac: Repentance+*. The intended scope is ordinary Azazel and
Tainted Azazel in online play where Lua mods cannot be enabled.

The project does **not** patch network packets, create attacks, modify attack
entities, replace XInput, or overwrite game-root DLLs. It filters the local
player's native action-query results before the game serializes normal online
input.

## Current milestone

The experimental runtime has two narrowly scoped test profiles:

- `IsaacInputPatcher.exe` installs a one-time automatic loader; subsequent
  Steam launches load `azazel_input_hook.dll` without a separate injector;
- the payload validates the PE32 game image and writes executable/hash/runtime
  diagnostics;
- the cross-platform C++ aim state machine covers ordinary and Tainted Azazel;
- ordinary Azazel (`generic-test`) filters only native action values 4–7;
- Tainted Azazel (`tainted-test`) additionally filters native pressed and
  triggered action queries, emitting a single directional trigger after a
  stable aim direction is confirmed.

Both profiles are fail-closed: they patch only after matching the exact
approved executable hash, unique bridge signatures, captured controller object,
and expected method prologues. They do not identify player type at runtime, so
choose the profile only for its corresponding character and treat both as local
input experiments, not online-ready releases.

`WinmmProxyProbe.exe` is retained only as a Proton proxy compatibility probe;
the normal deployment path uses the injector and does not install `winmm.dll`.

Observed Steam Deck test target:

- Repentance+ `1.9.7.17.J460`, Steam build `22878971`;
- `isaac-ng.exe` PE32/i386;
- executable SHA-256
  `7122AC28779925B24E23E2416F231322B1470388BD25E2C08665AD8D53B3EA4F`;
- Proton `9.0-203`.

This executable already contains a third-party `bootstp/inject` loader chain.
The project treats those files as externally owned and never overwrites them.

## Windows automatic installation

Close Isaac, then run `IsaacInputPatcher.exe` from the complete package and
select `isaac-ng.exe`. The patcher creates a backup, changes only Isaac's
`WINMM.dll` import to the same-length private name `cofix.dll`, and copies
`cofix.dll` plus `azazel_input_hook.dll` into the game directory. `cofix.dll`
forwards the three WinMM APIs Isaac uses, then loads the payload on every normal
Steam launch. It does not replace the Chinese patch's `bootstp.dll`, `inject.dll`,
or `language_unlocker.dll`.

The automatic loader is intentionally experimental: the payload refuses
unsupported game builds at initialization and controlled online host/client
compatibility testing remains incomplete.

See `DEPLOYMENT_WINDOWS.md` in the package for troubleshooting.

## Build

Visual Studio 2022 with the Win32 MSVC toolchain and CMake:

```powershell
cmake -S . -B build -A Win32
cmake --build build --config Release
ctest --test-dir build -C Release --output-on-failure
cmake --build build --config Release --target package
```

Every push also builds and tests the Win32 package with GitHub Actions. Core
state-machine tests run on macOS/Linux without Windows headers.

## Steam Deck diagnostic deployment

Build/download the CI artifact, then from macOS run:

```bash
bash tools/deck-install.sh /path/to/IsaacNativeInputFix
```

The installer runs `WinmmProxyProbe.exe` inside the existing game Proton prefix
and stages all files under `IsaacNativeInputFix`. It does not overwrite a game
DLL. Start the game normally through Steam, then inject the diagnostic payload:

```bash
bash tools/deck-inject.sh
```

`config/generic-test.ini` enables the ordinary-Azazel value-only profile.
`config/tainted-test.ini` enables the experimental Tainted-Azazel profile;
it uses the same captured controller object and action IDs 4–7, while also
overriding pressed/triggered semantics. Do not use either profile for another
character, and do not use `tainted-test` as an online-ready build yet.

After starting and exiting the game, collect diagnostics:

```bash
bash tools/deck-collect.sh
```

Remove only this project's files with:

```bash
bash tools/deck-uninstall.sh
```

Do not publish a build as an active gameplay fix while diagnostics report a
diagnostic, `generic-test`, or `tainted-test` status.
