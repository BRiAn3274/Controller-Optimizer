# Controller Optimizer

Controller-focused input fixes for *The Binding of Isaac: Repentance+*.

The mod stabilizes controller Brimstone aiming and repairs Tainted Azazel's
Repentance+ trigger/charge input sequence. Mars protection and Schoolbag quick
swap are isolated optional controller utilities.

Version 1.7.0 keeps ordinary Azazel's pressed/released state native, limits stick
dropout filtering to two frames, and allows Tainted Azazel to turn while charging
without generating another sneeze trigger. Smooth turns remain immediate, while
sudden near-opposite spikes require brief confirmation to reject stick snapback.
It also removes all attack-entity manipulation and narrows optional compatibility
paths to reduce conflicts with other mods.

## Compatibility contract

- The runtime only returns filtered values from `MC_INPUT_ACTION`.
- Ordinary Brimstone overrides direction values only; pressed and triggered
  states remain native.
- Tainted Azazel input reconstruction runs only for that player type in
  Repentance+ and creates one input trigger per stick gesture.
- The mod never spawns attacks, calls player fire methods, or modifies laser
  entities, damage, charge, or lifetime.
- Non-player entities, keyboard controller index 0, unrelated actions,
  non-Brimstone weapons, and Eye of the Occult are passed through with `nil`.
- Charge-familiar release handling is input-only and limited to the original Lil
  Brimstone and Lil Monstro variants.
- Schoolbag quick swap is enabled by default, requires the actual Schoolbag
  collectible and two occupied slots, and refuses to guess between players
  sharing one controller. It can still be disabled in Mod Config Menu.

Multiple mods can still return values for the same `MC_INPUT_ACTION` call. Load
order conflicts cannot be eliminated completely, so this mod deliberately
returns `nil` outside the narrow cases above.

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
The design boundary and remaining compatibility risks are documented in
[`docs/兼容性审计.md`](docs/兼容性审计.md).

## Versioning

`main.lua` and `metadata.xml` must contain the same version. Stable Workshop
releases are marked with annotated Git tags such as `v1.7.0`.
