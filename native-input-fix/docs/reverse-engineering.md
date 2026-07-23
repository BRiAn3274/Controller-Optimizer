# J460 native input discovery

Target observed on Steam Deck:

- Steam build `22878971`;
- Repentance+ `1.9.7.17.J460`;
- PE32/i386 image base `0x00400000`;
- SHA-256 `7122AC28779925B24E23E2416F231322B1470388BD25E2C08665AD8D53B3EA4F`;
- PE timestamp `0x69E6E3A7`.

The executable is locally modified by an existing `bootstp/inject` loader, so
the full-file hash is not assumed to represent a stock Steam executable.

## Confirmed Lua binding chain

The unique API strings are registered with these native wrappers:

| API | registration wrapper | native bridge callback | input-object slot |
|---|---:|---:|---:|
| `IsActionPressed` | `0x0086FD40` | `0x00A20940` | vtable `+0x30` |
| `IsActionTriggered` | `0x0086FD10` | `0x00A209E0` | vtable `+0x34` |
| `GetActionValue` | `0x0086FD70` | `0x00A20AB0` | vtable `+0x38` |

The three registration string references occur at `0x0086E152`,
`0x0086E141`, and `0x0086E163` respectively.

This confirms that all three public action queries converge on adjacent virtual
methods of a native input object. The payload scans for the bridge sequences and
reports their unique RVAs.

The diagnostic capture build temporarily detours the value bridge, invokes the
approved image's `GetActionValue` wrapper for controller 1 and shoot actions
4–7, records the concrete input-object vtable, then restores the original five
bytes before writing diagnostics. It does not change the returned value.

## Remaining proof before an active hook

The Lua bridges are not themselves the final hook target because online mode
can run with Lua mods disabled. The next runtime trace must identify:

1. the concrete input-object vtable used by the local player;
2. the controller/player ownership data reachable from that object;
3. native gameplay call sites for slots `+0x30`, `+0x34`, and `+0x38`;
4. whether those queries occur before online input serialization;
5. a structural signature that remains unique on an unmodified stock J460 EXE.

No active detour should be enabled until all five conditions are verified.
