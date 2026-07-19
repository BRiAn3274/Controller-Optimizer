# Controller Optimizer

Controller-focused input fixes for *The Binding of Isaac: Repentance+*.

The mod stabilizes controller Brimstone aiming, guards Mars against analog-stick
misfires, and adds an optional Schoolbag quick swap.

Version 1.5.1 republishes the stable 1.3.2 runtime behavior with a newer version
number so installations that received 1.5.0 can update normally.

## Development

Runtime files uploaded to Steam Workshop:

- `main.lua`
- `metadata.xml`
- `ControllerOptimizer_cover.png`

Check Lua syntax before a release:

```bash
luac -p main.lua
```

Upload instructions are in [`tools/README.md`](tools/README.md).

## Versioning

`main.lua` and `metadata.xml` must contain the same version. Stable Workshop
releases are marked with annotated Git tags such as `v1.5.1`.
