# Controller Optimizer Agent Guide

## 1. Purpose and Scope

Controller Optimizer is a Lua Steam Workshop mod for *The Binding of Isaac:
Repentance+*. It improves controller right-stick behavior for Brimstone-style
shooting without spawning attacks or modifying attack entities.

Current supported behavior includes:

- ordinary Azazel/Brimstone direction stabilization and short input-dropout
  protection;
- Tainted Azazel's native trigger, hold, release, and rearm input sequence;
- 360-degree preservation for Analog Stick;
- native-input pass-through for Eye of the Occult, Soy Milk, and The Marked;
- optional Mars analog-trigger guard and Schoolbag quick swap;
- limited release handling for the original Lil Brimstone and Lil Monstro.

The repository intentionally contains only the Lua Workshop mod. Do not add or
propose DLL injection, executable patching, Proton hooks, process injection,
native loaders, or external input-filter binaries. Online compatibility is not
a reason to expand the project outside this boundary.

## 2. Runtime Model

`main.lua` registers `MC_INPUT_ACTION` and returns filtered values only while
Isaac asks for controller input. It must never call attack APIs, spawn entities,
or modify laser lifetime, damage, network traffic, saves, or game executables.

The normal Brimstone path changes only `GET_ACTION_VALUE`; native
`pressed`/`triggered` state remains untouched. The Tainted Azazel path is the
only path that rebuilds a necessary input sequence. When a compatibility item
owns aim or firing cadence, return `nil` for every shooting hook so the game
receives the complete native input.

Keep per-player state keyed by the stable engine identity. Do not use a Lua
userdata wrapper itself as persistent state identity.

## 3. Repository and Files

GitHub: <https://github.com/BRiAn3274/Controller-Optimizer>

Workshop item: `3731198516` for Steam app `250900`.

Important repository files:

| Path | Purpose |
|---|---|
| `AGENTS.md` | This maintenance and release guide. |
| `README.md` | Public repository overview. |
| `PROJECT.md` | Local project record and routine checks. |
| `main.lua` | Runtime mod and all input filtering behavior. |
| `metadata.xml` | Mod ID, version, and Workshop metadata source. |
| `tests/test_controller_optimizer.lua` | Deterministic Lua input regression tests. |
| `CHANGELOG.md` | Release behavior changes. |
| `release-notes/` | Workshop-facing historical release notes. |
| `docs/背景信息.md` | Product and problem background. |
| `docs/兼容性审计.md` | Input ownership and compatibility boundary. |
| `tools/upload_workshop.sh` | Validates and uploads only runtime files. |
| `tools/README.md` | Workshop uploader details. |
| `ControllerOptimizer_cover.png` | In-mod cover image. |
| `ControllerOptimizer_preview.jpg` | Upload-only Workshop preview image. |

Do not upload tests, tools, Git metadata, or documentation to Workshop. The
uploader stages only `main.lua`, `metadata.xml`, and
`ControllerOptimizer_cover.png`.

## 4. Local and Deck Paths

| Location | Purpose |
|---|---|
| `/Users/a1/Documents/Codex 2/Controller-Optimizer` | Active local repository. |
| `/Users/a1/Vibe/Projects/Personal/isaac-controller-mod/.steam-workshop.env` | Local Steam account-name configuration. Never commit it. |
| `/Users/a1/steamcmd/steamcmd.sh` | SteamCMD executable used for Workshop uploads. |
| `/Users/a1/.ssh/controller_optimizer_deck_ed25519` | SSH key for the personal Steam Deck. Do not expose or replace it. |
| `/home/deck/.local/share/Steam/steamapps/workshop/content/250900/3731198516` | Steam Deck's locally subscribed Workshop copy. |

Direct edits to the Deck Workshop directory are temporary: Steam Workshop sync
can replace them. Publish through SteamCMD for a durable distribution update.

## 5. Release and Upload Procedure

1. Update the version consistently in `main.lua`, `metadata.xml`, and
   `CHANGELOG.md`.
2. Run the release checks:

   ```bash
   luac -p main.lua
   lua tests/test_controller_optimizer.lua
   xmllint --noout metadata.xml
   git status --short
   ```

3. Commit the release and push `main` to GitHub.
4. Load the account-name-only configuration and upload. SteamCMD prompts for
   the Steam account password and, when enabled, Steam Guard mobile approval.
   Never put either secret in a file, command line, or chat.

   ```bash
   cd "/Users/a1/Documents/Codex 2/Controller-Optimizer"
   set -a
   source "/Users/a1/Vibe/Projects/Personal/isaac-controller-mod/.steam-workshop.env"
   set +a
   STEAMCMD="/Users/a1/steamcmd/steamcmd.sh" \
     ./tools/upload_workshop.sh \
     --user "$STEAM_USERNAME" \
     --note "Version X.Y.Z: short release summary"
   ```

5. The script creates annotated tag `vX.Y.Z` only after SteamCMD reports a
   successful upload. Push it separately:

   ```bash
   git push origin "vX.Y.Z"
   ```

The uploader preserves the existing Workshop title and description by default.
Use `--sync-page-metadata` only when deliberately replacing the public page
with the contents of `metadata.xml`. Use `--dry-run` to validate packaging
without a Steam login. Do not use `--allow-dirty`; use `--skip-tests` only when
no compatible Lua interpreter is available.
