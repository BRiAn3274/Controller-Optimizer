# Steam Deck deployment

This package injects a native Windows DLL into the running Proton game process.
It does not install a Lua mod, replace a game DLL, or modify network traffic.

## Prerequisites

- Steam Deck Desktop Mode with SSH access;
- Proton 9.0 (Beta) installed at the default Steam path;
- Repentance+ closed while installing;
- the observed target build: `1.9.7.17.J460`, Steam build `22878971`.

The scripts assume `deck@192.168.1.235` and the SSH key at
`~/.ssh/controller_optimizer_deck_ed25519`. Override with `DECK_HOST` and
`DECK_KEY` if necessary.

## Persistent automatic-loader install

The end-user flow mirrors other one-time Proton patch installers:

There are two supported installation paths:

### From Desktop Mode with the patcher

1. Add `IsaacInputPatcher.exe` to Steam as a non-Steam game.
2. Force the same Proton compatibility tool used by Isaac.
3. Start the patcher from Steam and select `isaac-ng.exe` in the file picker.
4. Confirm installation once, then remove the patcher shortcut if desired.
5. Start Isaac normally from its original Steam library entry thereafter.

### From another computer over SSH

The package also contains `tools/deck-persistent-install.sh` and
`tools/deck-persistent-uninstall.sh`. They copy the bridge and payload to the
Deck, run the Win32 patcher inside Isaac's Proton prefix, and leave the
installation in place for ordinary Steam launches:

```bash
bash tools/deck-persistent-install.sh /path/to/IsaacNativeInputFix diagnostic
```

Use `generic-test` or `tainted-test` only for the corresponding test profile.
The defaults assume `deck@192.168.1.235`, Proton 9.0 (Beta), and the default
Steam library. Override `DECK_HOST`, `DECK_KEY`, `DECK_GAME_WIN`,
`DECK_ISAAC_REL`, `DECK_COMPATDATA_REL`, and `DECK_PROTON_REL` when the Deck
uses another account, library, or Proton version. Remove the loader with:

```bash
bash tools/deck-persistent-uninstall.sh /path/to/IsaacNativeInputFix
```

If Isaac still names `userenv` at its dynamic loader point, the patcher creates
`isaac-ng.exe.cofix-original` and changes that unique string to `bootstp`. If another
patch already installed `bootstp.dll`, the executable is left untouched and
that DLL is preserved as `cofix_bootstrap_chain.dll`. The bridge invokes it
before attaching the independent input payload.
No launcher or per-session injector is needed. This is persistent across
reboots and normal Steam launches, but not across a Steam update that replaces
`isaac-ng.exe`; rerun the installer after an update. The patcher must refuse to
touch an unknown executable build rather than attempting a best-effort patch.

## Developer injection test

From macOS or Linux, with the package directory as the argument:

```bash
bash tools/deck-install.sh /path/to/IsaacNativeInputFix tainted-test
```

Start Isaac normally through Steam. Once the title screen is visible, inject:

```bash
bash tools/deck-inject.sh
bash tools/deck-collect.sh
```

Confirm `diagnostics.json` reports `"hook_status": "tainted-test-active"`
and all three hook fields are `true` before testing Tainted Azazel. The generic
profile is installed with `generic-test` and must only be tested with ordinary
Azazel.

The injected module is unloaded by closing the game. To remove staged binaries
after the game has closed:

```bash
bash tools/deck-uninstall.sh
```

Configuration and diagnostic logs are intentionally retained in the Proton
prefix. The legacy developer-injection scripts do not change the persistent
bootstrap chain.

## What “persistent” means

The installation does not keep a DLL injected after the game exits. It changes
one verified loader-name string in the game executable from `userenv` to
`bootstp`. On every later launch, the game's normal Windows loader loads the
local `bootstp.dll`; that bridge forwards the original `userenv` call and then
loads `azazel_input_hook.dll` into the same game process. Closing Isaac unloads
both modules, and the next launch repeats the normal loading sequence.

This is the same broad pattern used by loader-style translation patches, but it
is not a Lua/Workshop mod and it is not a Decky plugin. It is a local Proton
runtime patch and should be treated as an experimental binary modification.

## Test scope

This is an experimental local-input build. Keep all Lua mods disabled for the
test. It has passed local Steam Deck tests for ordinary and Tainted Azazel, but
has not passed a controlled online host/client compatibility matrix.
