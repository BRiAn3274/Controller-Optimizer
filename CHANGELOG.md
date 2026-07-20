# Changelog

## 1.7.0 - 2026-07-20

- Remove all player-laser entity inspection and lifetime mutation. Familiar
  compatibility now changes release input only.
- Restrict the charge-familiar release path to the original Lil Brimstone and
  Lil Monstro variants instead of every familiar owned by the player.
- Isolate shooting state by player so characters sharing one controller cannot
  reset or retrigger each other's input profile.
- Use a stable engine player identity instead of a transient Lua userdata
  wrapper so direction, release and snapback history survive every input hook.
- Leave Mars `IS_ACTION_PRESSED` native and suppress only confirmed analog
  `IS_ACTION_TRIGGERED` edges.
- Keep Schoolbag quick swap enabled by default, but require the actual
  Schoolbag collectible, two occupied slots, and an unambiguous controller
  target. Use Isaac physical button 13 for right-stick press; button 11 is the
  right bumper and must not trigger a swap.
- Treat movement, physical-button polling, familiar scanning, and lifecycle
  callbacks as optional APIs so their absence cannot disable core shoot filtering.
- Validate raw input values and internal thresholds, rate-limit input-read errors,
  and normalize `main.lua` to UTF-8 without BOM using LF line endings.
- Add conflict-boundary, shared-controller, Mars, Schoolbag, familiar-scope, and
  optional-API regression tests.

## 1.6.0

- Remove the 45-frame virtual Brimstone hold that delayed ordinary Azazel's
  attack after the player returned the stick to center.
- Leave ordinary Brimstone `triggered` and `pressed` states to the base game;
  filter only direction values and a two-frame input dropout.
- Update Tainted Azazel's held direction every frame while keeping exactly one
  initial sneeze trigger.
- Preserve live Analog Stick 360-degree turning during Tainted Azazel charge.
- Confirm abrupt near-180-degree direction jumps before accepting them, preventing
  no-center stick snapback from reversing the final beam direction.
- Replace tests that encoded delayed release and locked aim with release,
  turning, snapback, and no-retrigger regression tests.

## 1.5.1

- Republish the stable 1.3.2 runtime behavior as a forward update so Steam and
  Isaac replace installations that received 1.5.0.
- No gameplay behavior changes from 1.3.2.

## 1.5.0

- Restore a native trigger/hold/release input sequence for Tainted Azazel in
  Repentance+ without spawning attacks from Lua.
- Preserve Analog Stick 360-degree aiming.
- Keep shooting value and pressed-state outputs synchronized.
- Add release debounce, rearming, snapback rejection, and direction confirmation.
- Remove unused hold settings, a redundant wrapper, and unread state fields.
- Add repeatable controller-input tests and a reusable SteamCMD uploader.

## 1.3.2

- Workshop baseline imported from published item `3731198516`.
