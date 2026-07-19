# Controller Optimizer

Controller-focused input fixes for *The Binding of Isaac: Repentance+*.

The mod stabilizes controller Brimstone aiming, preserves live 360-degree aiming
with Analog Stick, repairs Tainted Azazel's Repentance+ trigger/charge sequence,
guards Mars against analog-stick misfires, and adds an optional Schoolbag quick
swap.

Version 1.6.0 keeps ordinary Azazel's pressed/released state native, limits stick
dropout filtering to two frames, and allows Tainted Azazel to turn while charging
without generating another sneeze trigger. Smooth turns remain immediate, while
sudden near-opposite spikes require brief confirmation to reject stick snapback.

## Development

Runtime files uploaded to Steam Workshop:

- `main.lua`
- `metadata.xml`
- `ControllerOptimizer_cover.png`

Run syntax and controller-input simulation checks before a release:

```bash
luac -p main.lua
lua tests/test_controller_optimizer.lua
```

Upload instructions are in [`tools/README.md`](tools/README.md).

## Versioning

`main.lua` and `metadata.xml` must contain the same version. Stable Workshop
releases are marked with annotated Git tags such as `v1.6.0`.
