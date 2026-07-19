# Changelog

## 1.6.0

- Remove the 45-frame virtual Brimstone hold that delayed ordinary Azazel's
  attack after the player returned the stick to center.
- Leave ordinary Brimstone `triggered` and `pressed` states to the base game;
  filter only direction values and a two-frame input dropout.
- Update Tainted Azazel's held direction every frame while keeping exactly one
  initial sneeze trigger.
- Preserve live Analog Stick 360-degree turning during Tainted Azazel charge.
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
