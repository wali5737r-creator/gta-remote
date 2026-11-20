# AB GTA — v3 Review: User / Tester / Expert (HID mouse + PWM steering)

**Date:** 2026-11-20
**Scope:** The v3 changes, driven by Muhammad's first real play session
with v2 on GTA San Andreas Original — (1) camera fixed / no mouse,
(2) swimming straight-only with uneven speed, (3) ENTER/EXIT feeling
reversed, (4) steering oversensitive (small move = full turn),
(5) no fight button, (6) no map button, (7) buttons too big and
touching — plus a regression pass over v2 behaviour (registration
lifecycle, connect flow, auto-release, multi-touch wheel+pedals).
**Method:** Static review of the full v3 diff (no SDK/device on this
machine — same limit as the previous audits; CI build + the owner's
device session are the proofs).

**Result: 1 major, 3 minor found in review — all fixed before build.**
Everything else verified correct or recorded as a deliberate decision
below. No QA_REPORT / IMPROVEMENTS / IMPROVEMENTS_V2 fix is regressed
(verified list at the end).

---

## What v3 changes (summary)

- **HID mouse (Report ID 2):** the descriptor gains a standard mouse
  collection (3 buttons + 5-bit padding, relative X/Y ±127, wheel);
  the keyboard collection's bytes are **untouched**. SDP subclass is
  now `SUBCLASS1_COMBO`. Kotlin gains `sendMouse(dx, dy, buttons,
  wheel)`; a zero-mouse report joins the existing safety paths
  (host pause, disconnect, dispose).
- **CAMERA pad** (new widget): raw-Listener drag pad in all three
  layouts (driving-steering centre, driving-tilt centre, on-foot
  centre), sensitivity ×2.2, deltas accumulated with fractional
  carry and flushed every ~12 ms, split into ±127 chunks, final
  flush on finger-lift.
- **PWM steering:** wheel and tilt now feed a normalised steer
  (−1..+1) into one engine in the controller. 20 ms tick; per
  100 ms window the key-down time is 25 ms + 75 ms × duty, duty =
  clamp((|s| − dz)/(1 − dz)); duty ≥ 0.98 = continuous hold. The
  window is realised by error diffusion across ticks, so the
  long-run duty matches the formula exactly at 20 ms granularity.
  Direction hysteresis reuses each source's existing thresholds
  (wheel: dead-zone°/range with the v2 release rule; tilt: 12°/45°
  engage, 8°/45° release; tilt full lock = 45° of delta).
- **Momentary presses:** ENTER/EXIT (F), JUMP and MAP (Esc) are now
  one clean 150 ms press with a 250 ms double-fire lockout. JUMP
  changed from hold to tap. ENTER/EXIT stays ONE toggle button.
- **ATTACK (on foot):** hold = HID mouse LEFT held, release = up.
  Button state lives in `HidService` and is zeroed by
  `releaseAllKeys()` — i.e. on mode switch, steer switch, settings
  change, disconnect, app pause and controller dispose — plus the
  Kotlin zero-mouse backstop on pause/disconnect/dispose, plus the
  widget's own dispose release. A stuck click is impossible by the
  same construction that makes stuck keys impossible.
- **MAP (both layouts):** Esc tap, second slot of the action row —
  the slot that was an invisible spacer on foot in v2.
- **Layout pass:** round buttons 68→58 (ENTER/EXIT, HANDBRAKE, MAP),
  JUMP 94→80, ATTACK 80 (new), RUN 118×74→100×63, pedal pads
  RACE 78×148→66×126 and BRAKE 114×96→97×82, pedal arm 30→26.
  Every inter-control gap is now ≥12 dp (two v2 gaps of 10 dp —
  action-row-to-pedals in both driving clusters — raised to 12;
  top-bar gaps 10→12). Geometry verified numerically at 640×360
  (see Tester section); pedals keep BRAKE first/left, RACE
  second/right; tilt keeps BRAKE alone left, RACE alone right,
  action row above RACE. Game profiles and Settings semantics
  unchanged.

---

## MAJOR (fixed)

### T1 — `_stopTilt()` reset the whole steering engine, including the wheel's
**Lens:** Tester. **File:** `controller_screen.dart` → `_stopTilt`

**Evidence:** The first v3 draft put an unconditional
`_resetSteerEngine()` in `_stopTilt()`. But `_stopTilt()` is also
reached from `_updateTiltSubscription()`, which the HID listener
calls on **every connected event**. In STEERING mode a duplicate
connected event mid-drive (the QA M3 scenario — explicitly
anticipated by this codebase) would have cancelled the PWM timer
and dropped wheel steering until the wheel angle changed by another
degree: a silent, confusing mid-corner steering cut.

**Fix:** `_stopTilt()` now resets the engine only when the active
steer source is actually `'tilt'`. Every other path that must clear
steering (mode switch, steer switch, settings, pause, disconnect,
dispose) already goes through `_clearAllKeys()` / dispose, which
reset the engine unconditionally. Verified path by path.

---

## MINOR (fixed)

### E1 — Camera pad's top gap to the top bar was ~9 dp, not ≥12
**Lens:** Expert. **File:** `controller_screen.dart` → `_buildCameraPad`

**Evidence:** The tallest top-bar chrome (mode pill) ends at
≈51 dp from the top; the pad's first draft started at 60. The v3
layout rule is ≥12 dp between controls.

**Fix:** Pad top inset 60→64 (13 dp clear of the pill). The bottom
gap was already exactly 12 (pad bottom inset 72 vs ghost buttons'
top edge at H−60).

### U1 — Controller doc comment still named a 'wheel' key source
**Lens:** User (maintainer). The class comment listed sources
"(wheel, race, joystick…)"; the wheel no longer owns a source —
steering arrives via 'pwm'. Comment corrected so the next reader
isn't sent looking for code that no longer exists.

### U2 — Settings never mentioned the camera pad / MAP / ATTACK
**Lens:** User. **File:** `settings_screen.dart` (Help card)

**Evidence:** Same gap as IMPROVEMENTS_V2 U3: the new controls live
only on the controller; a user who never drags the centre pad would
not know the camera can move at all, nor that swimming direction
follows it.

**Fix:** One Help line in the card's existing Roman Urdu style:
CAMERA pad = mouse (camera + swim direction; RUN on = fast swim),
MAP opens the map/pause menu, ATTACK (on foot) is the mouse click —
hold for fighting. No new Settings controls; semantics unchanged.

---

## Deliberate decisions (not bugs)

### D1 — RUN stays a toggle; that IS the held sprint key (issue 2)
The task asked to *confirm* RUN is hold-to-sprint. In v2/v3 RUN is
the SRS FR-16 toggle: while it shows RUNNING, the profile's sprint
key is present in **every** HID report, continuously — the exact
signal a physically held sprint key produces, and what makes CJ
swim fast. Nothing about the toggle weakens that. The "sometimes
fast, sometimes slow" report is explained by two real causes, both
now addressed or documented: (a) swimming *direction* was bound to
the fixed camera — the CAMERA pad fixes it; (b) FR-22 resets RUN on
every mode switch, so entering water right after exiting a car
silently drops sprint until RUN is tapped again — pre-existing,
documented behaviour, now also stated in the Settings help line.
No swim-specific code was added, per the task. If the owner later
wants literal press-and-hold RUN, it is a one-widget change — but
it would contradict the approved FR-16 design, so it was not made
unilaterally.

### D2 — No ATTACK button in the driving layouts
The task allows ATTACK in driving only "if space allows without
crowding". At the verified small size (640×360) the driving centre
is fully committed to the CAMERA pad (142 dp wide there); a fourth
action-row button would cut the pad to ~72 dp — unusable — or push
the cluster into the wheel. Driving keeps ENTER/EXIT • MAP •
HANDBRAKE. Fighting is an on-foot activity and ATTACK is there;
for pause-menu clicks while driving, the mode pill (layout-only,
sends no key) switches to the on-foot layout where ATTACK clicks —
noted here so the limitation is explicit, not discovered.

### D3 — PWM window realised by error diffusion, not a phase timer
A strict 100 ms phase window at 20 ms ticks can only produce
down-times in 20 ms steps (25 ms → 20 or 40). Error diffusion
distributes the same total down-time across ticks so the long-run
duty equals 25 + 75·duty ms per 100 ms within one tick. Same
formula, finer grain, smoother car. Direction changes still engage
on the very next tick (accumulator primed to 1.0 on a direction
change), so responsiveness is not traded away.

---

## Verified correct — no change needed

**HID / Kotlin (Expert):**
- Keyboard descriptor bytes are byte-identical to v2 — the mouse
  collection is appended after the keyboard's End Collection.
  Mouse payload (1 button byte + X + Y + wheel = 4 bytes) matches
  the declared sizes/counts; logical ranges re-declared before each
  Input item; Report ID 2 sits inside its own application
  collection. `sendReport(device, 2, 4-byte data)` matches the API
  convention verified in QA (payload excludes the ID).
- `SUBCLASS1_COMBO` is the correct SDP subclass for a keyboard +
  mouse composite; name/provider strings unchanged ("AB GTA").
- `sendMouse` mirrors `sendReport`'s guards (registered +
  connected, SecurityException → false) and clamps/masks its inputs
  natively as a second line of defence behind the Dart chunking.
- Registration lifecycle, waiter list, bond check, fast-fail
  connect — untouched. The CI workflow restores this exact Kotlin
  file around `flutter create`, so no workflow change is needed.

**PWM engine (Expert + Tester):**
- No division by zero is reachable: engage is deadZone/range
  (max 15/90 ≈ 0.167) or 12/45 ≈ 0.267 — never 1. Dead zone 0
  gives duty = |s|, matching v2's dz=0 immediate-steer semantics.
- Hysteresis band behaviour: with release < |s| ≤ engage the
  direction is held and duty clamps to 0 → the formula's 25 ms
  minimum pulse — the spec's own arithmetic, not an accident.
- Timer lifecycle: created only by `_setSteerInput` (`??=` —
  never doubled), cancelled by `_resetSteerEngine` and dispose.
  A tick that races a cancel no-ops (`_setPwmKey(null)` against an
  already-null applied key).
- Source discipline: wheel feeds are ignored unless driving +
  STEERING; tilt feeds unless driving + TILT — so the outgoing
  layer during AnimatedSwitcher's 250 ms fade cannot resurrect
  steering (same guard class as QA m2).
- Tilt's flat-phone release and |delta| > 100° baseline
  invalidation (IMPROVEMENTS_V2 T3/T5) now release via the engine
  and re-feed on the next valid sample — behaviour preserved.
- The wheel's spring return still reports every rounded degree,
  so PWM duty eases off as the wheel centres — no separate
  "release" path needed. Wheel widget dispose no longer releases a
  key it no longer owns; every unmount path (mode switch, steer
  switch, screen dispose) clears the engine first — verified
  against each call site.

**Momentary presses (Tester):**
- Lockout (250 ms) starts at press-down; the key is up at 150 ms,
  so a deliberate re-press is possible 100 ms after release —
  responsive, but a bounce/double-tap inside the window is dead.
- Generation guard: a mode switch mid-press clears the source;
  the stale 150 ms release then no-ops against a newer press of
  the same id. ENTER/EXIT keeps the QA m2 target-capture fix.
- SA Definitive's shared Space (RUN toggle + JUMP tap) composes
  correctly through the source union — the tap's release removes
  only its own source; Space stays while RUN is on.

**Camera pad (Tester + User):**
- Single-pointer ownership, no gesture arena — simultaneous
  RACE-hold + camera drag works (the FR-14 pattern, extended).
  A finger that starts on a button and slides onto the pad is
  ignored by the pad, and vice versa.
- Fractional accumulation means slow precise drags (menu pointer)
  are not lost below the 1-unit threshold; fast flicks chunk
  losslessly at ±127 per report.
- Pad geometry (640×360): driving 142×224, tilt 261×224,
  on-foot 136×224; at the C67's ~880 dp width: 382 / 501 / 376
  wide. All gaps to neighbouring controls ≥12 dp; pad is first in
  each layer's Stack, so any residual overlap would still favour
  the buttons. Ghost buttons clear the pad's bottom by 12 dp;
  the disconnect overlay covers the pad like every control.
- The centred angle readout now floats over the pad (IgnorePointer
  text, translucent) — readable, never blocks a drag.

**Regression pass (v2 behaviour):**
- Connect flow, early registration, device list, pairing guide,
  troubleshooting card — untouched files, untouched behaviour.
- Auto-release: keyboard paths unchanged; mouse buttons join the
  same paths (Dart `releaseAllKeys` + Kotlin zero-mouse on
  pause/disconnect/dispose + widget dispose). Disconnect event
  resets Dart's button state without sending (link already dead;
  the host releases buttons on link loss itself).
- Multi-touch wheel + pedals: wheel input handling is unchanged
  except the removed key callback; pedals/buttons untouched.
- Flip-controls mirrors the pad insets with the clusters (pad
  insets are computed from the same side constants).
- Text-scale clamp and compact scaling (0.86 under 360 dp height)
  cover the new rows: worst-case cluster heights after shrink —
  driving/tilt 262 dp (top edge ≈82 at 360 dp height, clear of
  the top bar), on-foot 172 dp.

---

## Must verify — CI build & owner's device test

1. **CI compile** — first proof of the Kotlin descriptor/subclass
   edit and the Dart engine. Expected risk area, as flagged before
   the build: HID descriptor / `SUBCLASS1_COMBO` surface.
2. **⚠ Re-pair required (descriptor change):** Windows caches the
   old SDP record (keyboard-only). The owner must **Remove device**
   on the laptop and pair again once, or the mouse will not exist
   as far as Windows is concerned. The app cannot detect the stale
   record — keyboard will keep working, camera will not.
3. **Device — camera feel:** pad sensitivity 2.2 in SA (free-look
   speed), menu-pointer precision in the pause menu, and that SA
   Original accepts combo-device mouse input at all (standard
   DirectInput — expected yes).
4. **Device — PWM feel:** gentle lane changes at ~15° wheel /
   ~20° tilt should nudge, not swing; full lock must feel
   continuous. Dead-zone/sensitivity settings now shape the PWM
   curve as well as the wheel graphic — one drive in each steer
   mode settles it.
5. **Device — ENTER/EXIT:** repeated deliberate taps near a car;
   the 250 ms lockout must not eat a genuine second press.
6. **Device — ATTACK:** hold-to-fight on foot; confirm the click
   releases on mode switch / disconnect (punch must not continue).
7. **Device — swimming:** enter water, RUN on, joystick forward +
   pad to turn — direction must follow the camera and speed must
   stay fast while RUNNING shows.
