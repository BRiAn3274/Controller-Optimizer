# Steam Workshop uploader

`upload_workshop.sh` updates Workshop item `3731198516` for app `250900`.
It stages only the three runtime files, so Git metadata, tests, and tools are
never included in the Workshop package.

## One-time setup

SteamCMD is discovered from `PATH`, `$HOME/steamcmd/steamcmd.sh`, or the path in
the `STEAMCMD` environment variable.

Optionally create an ignored `.steam-workshop.env` file in the repository root:

```bash
STEAM_USERNAME=your_steam_account_name
```

Store only the account name there. Never store a password or Steam Guard code.
SteamCMD requests them interactively when required.

## Validate without uploading

```bash
./tools/upload_workshop.sh --dry-run
```

## Upload a release

Commit the release first, make sure `main.lua` and `metadata.xml` have the same
version, then run:

```bash
./tools/upload_workshop.sh --user your_account_name --note "Version 1.5.0"
```

The uploader:

1. requires a clean Git worktree;
2. validates the Workshop ID and version strings;
3. checks Lua syntax and runs the simulation tests;
4. stages only runtime files in a temporary directory;
5. generates the SteamCMD VDF automatically;
6. uploads to the existing Workshop item;
7. creates the annotated `v<version>` tag after a successful upload if needed.

Use `--allow-dirty` only for deliberate test uploads. Use `--skip-tests` only
when no compatible Lua interpreter is available.
