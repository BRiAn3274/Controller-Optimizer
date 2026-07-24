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

1. Add `IsaacInputPatcher.exe` to Steam as a non-Steam game.
2. Force the same Proton compatibility tool used by Isaac.
3. Start the patcher from Steam and select `isaac-ng.exe` in the file picker.
4. Confirm installation once, then remove the patcher shortcut if desired.
5. Start Isaac normally from its original Steam library entry thereafter.

If Isaac still names `userenv` at its dynamic loader point, the patcher creates
`isaac-ng.exe.cofix-original` and changes that unique string to `bootstp`. If another
patch already installed `bootstp.dll`, the executable is left untouched and
that DLL is preserved as `cofix_bootstrap_chain.dll`. The bridge invokes it
before attaching the independent input payload.
No launcher or per-session injector is needed. Re-run the patcher after Steam
replaces `isaac-ng.exe` during a game update or reinstall.

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

## Test scope

This is an experimental local-input build. Keep all Lua mods disabled for the
test. It has passed local Steam Deck tests for ordinary and Tainted Azazel, but
has not passed a controlled online host/client compatibility matrix.
