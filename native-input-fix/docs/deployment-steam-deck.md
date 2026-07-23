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

## Install and test

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
prefix. No script overwrites game-root DLLs or user-owned loader files.

## Test scope

This is an experimental local-input build. Keep all Lua mods disabled for the
test. It has passed local Steam Deck tests for ordinary and Tainted Azazel, but
has not passed a controlled online host/client compatibility matrix.
