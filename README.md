# Controller Optimizer

Controller-focused input fixes for *The Binding of Isaac: Repentance+*.

The mod stabilizes Brimstone aiming, preserves 360-degree aiming with Analog
Stick, provides a native input sequence for Tainted Azazel, guards Mars against
analog-stick misfires, and adds an optional Schoolbag quick swap.

## Development

Runtime files uploaded to Steam Workshop:

- `main.lua`
- `metadata.xml`
- `ControllerOptimizer_cover.png`

Run the local input simulation before a release:

```bash
lua tests/test_controller_optimizer.lua
```

Upload instructions are in [`tools/README.md`](tools/README.md).

## Versioning

`main.lua` and `metadata.xml` must contain the same version. Stable Workshop
releases are marked with annotated Git tags such as `v1.5.0`.
