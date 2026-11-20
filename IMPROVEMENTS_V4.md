# AB GTA — v4 Review: User / Tester / Expert (CONTROLLER + ARROWS modes, on-foot controls, English UI)

**Date:** 2026-11-20
**Scope:** (1) Two NEW driving modes approved from mockups
(`mockup/v4-3-controller.png`, `mockup/v4-4-arrows.png`, approved
"Han theek") — CONTROLLER (gamepad stick + triggers) and ARROWS
(tap steering buttons) — added as pure additions; STEERING, TILT
and ON FOOT behaviour/layout untouched. (2) Owner's scope
expansion: a full audit of the controller experience for actually
playing GTA (esp. SA), adding the controls a player genuinely
needs (AIM / weapon switch / crouch / horn evaluated). (3) ALL
in-app Roman Urdu strings converted to plain English.
**Method:** Static review of the full v4 diff + the pre-delivery
verification pass below (no SDK/device on this machine — same
limit as previous audits; CI build + the owner's device session
are the proofs).

**Result: 0 critical, 0 major. 2 minor found in review — both
fixed before build. HORN evaluated and deliberately omitted
(geometry proof below).**

---

## What v4 changes (summary)

- **DriveMode enum** (`settings_service.dart`): STEERING / TILT /
  CONTROLLER / ARROWS, persisted as `drive_mode`. Migration: a
  v2/v3 user with `tilt_steering = true` lands on TILT, everyone
  else on STEERING; `setDriveMode` also keeps the legacy bool in
  sync. The top-bar switch renders all four segments; switching
  runs the existing `_clearAllKeys()` path first (keys + mouse
  buttons + PWM engine + arrow state), and the tilt sensor starts
  only in TILT — exactly as before.
- **CONTROLLER mode** (new layer, mockup v4-3): subtle gamepad
  silhouette (static `CustomPainter`, non-interactive), analog
  stick on the left (`analog_stick.dart` — knob follows the
  finger, springs back on release; steer = dx/travel clamped
  ±1), the same CAMERA pad in the centre (smaller), RACE/BRAKE as
  wide trigger-style hold buttons on the right with the familiar
  EXIT CAR • MAP • HANDBRAKE round row beneath them. The stick
  feeds the **same v3 PWM engine** as a new `'stick'` source:
  fixed dead zone 0.12 (release 0.08), Settings **sensitivity
  applies**, Settings range/dead-zone stay wheel-only.
- **ARROWS mode** (new layer, mockup v4-4): two large ◀ ▶
  buttons on the left (`steer_arrows.dart`, raw Listener,
  multi-touch), CAMERA pad centre, and the **identical** steering
  -mode cluster on the right (action row + BRAKE/RACE pedals).
  Buttons drive A/D directly as a `'buttons'` key source:
  press = key down, release = key up, **but** a press shorter
  than **90 ms** is extended to a full 90 ms pulse ("one tap =
  slight move" — a 20–30 ms tap can be lost entirely by the
  game's input polling). Holding = continuous steer. Both arrows
  active at once = cancel (neither key); when one side's pulse
  ends, the other side applies.
- **On-foot additions** (see audit below): **AIM** (hold = HID
  mouse RIGHT), **CROUCH** (C tap — SA's crouch is a toggle),
  **weapon switch** (two compact ◀ ▶ WPN buttons sending mouse
  **wheel ticks**, tap = one tick, hold = repeat after 400 ms
  every 200 ms). ATTACK now sets only its own mouse bit
  (`HidService.setMouseButton`), so AIM and ATTACK can be held
  together; `releaseAllKeys()` still zeroes all bits on every
  safety path.
- **English UI**: every user-facing Roman Urdu string in Dart
  and Kotlin converted to plain English (areas listed below).
  Code comments remain Roman Urdu — they are developer notes,
  not app language.
- **HID/Kotlin: functionally untouched.** The only Kotlin change
  is the text of 17 user-facing error strings in
  `HidKeyboardManager.kt`. Descriptor, SDP, QOS, channel and
  `MainActivity.kt` are byte-identical to v3 (proof in the
  verification checklist) — **v4 needs NO re-pair.**

---

## Full controller audit — candidate controls (owner's expansion A)

### AIM (on foot) — ADDED
SA gunplay is hold-RMB to aim, LMB to fire; without it ATTACK
could only hip-fire. Placement: on-foot cluster gains a compact
third (secondary) row — AIM pill (96×48, hold) + CROUCH pill
(92×48). Row width 200 ≤ row 1's 220, so the CAMERA pad's
geometry is unchanged; cluster top edge at 640×360 is 112 dp,
clear of the top bar. Release safety is ATTACK's: the button bit
lives in `HidService._mouseButtons` and is zeroed by
`releaseAllKeys()` (mode/layout switch, steer switch, Settings
change, disconnect, app pause, controller dispose) + the Kotlin
zero-mouse backstop + the pill widget's own dispose release.
Ergonomics note (honest): AIM and ATTACK sit in different rows
of the same right-hand cluster — hold AIM with the right thumb
and tap/hold ATTACK with the same thumb slid up, or a second
finger; both buttons are independent Listeners, so simultaneous
holds register.

### Weapon switch (on foot) — ADDED (wheel ticks, not Q/E)
SA cycles weapons with the mouse wheel (and Q/E). Chosen:
**wheel ticks** via the existing mouse report's wheel field —
one input path (no new keycodes in the 6-key report budget),
works in GTA V too, and matches how a PC player does it. Q/E
would also have worked but spends keyboard slots and duplicates
a mouse-native function. Placement: the free band above the
joystick (joystick side; mirrors with flip) — two 48×48 buttons,
◀ = previous (wheel −1), ▶ = next (wheel +1), 8 dp apart
(pair-internal spacing; the ≥12 dp rule governs the main control
clusters — this pair is one combined control, like the two
arrows' 16 dp and the pedal pair). Tap = one tick; hold repeats
(400 ms delay, then every 200 ms) so a long weapon list cycles
fast. Ticks carry the current mouse-button state and mutate
nothing — there is no held state to stick.

### CROUCH (on foot) — ADDED (tap, not hold)
SA's C key **toggles** crouch, so the correct remote behaviour
is one clean press per toggle: CROUCH uses the v3 momentary
helper (150 ms press + 250 ms lockout, generation-guarded),
same as JUMP/MAP. `GameKey.c` (0x06) added to the enum and to
`hidKeyOrder` (inserted after F; reports for key sets without C
are byte-identical to v3). Note: in GTA V, C is look-behind —
still a useful, harmless press; the owner's game is SA, where
the CROUCH label is exact.

### HORN (driving) — OMITTED (deliberate, with the numbers)
H (hold) is the only candidate that does not fit. The driving
action row is 198 dp wide (3 × 58 + 2 × 12); a fourth round
button makes it 268 dp, which pushes the CAMERA pad's right
inset from 236 to 306 and shrinks the steering-mode pad at
640×360 from 142 dp to **72 dp wide** — unusable, and the brief
forbids shrinking main controls below v3 sizes. In TILT the pad
would drop 261 → 191 dp and in CONTROLLER the trigger column
(198) would no longer align with the row. The remaining free
space (bottom-centre) already holds Settings/Disconnect — a
horn next to the disconnect button invites the worst possible
mis-tap. In SA the horn is near-cosmetic (no mission requires
it). **Left out; can be revisited if the owner trades pad width
for it.**

### Also audited, no action needed
- **Look behind / camera centre**: the CAMERA pad covers it.
- **Sprint on foot**: RUN toggle already holds the sprint key in
  every report (v3 D1) — unchanged.
- **Enter/Exit, handbrake, map, jump**: present since v2/v3.
- **Pause (Esc)**: the MAP button is an Esc tap — same key.
- **Phone-answer / radio keys (SA)**: cosmetic, no space, skip.

---

## Language conversion (owner's expansion B) — areas converted

- **Connect screen**: permission explanation dialog + button,
  permission-from-Settings dialog, pairing guide (title, all 4
  steps, discoverable button), troubleshooting card (title + all
  5 points), permission card, section titles ("Which game will
  you play?", "Your laptop"), refresh tooltip, no-laptop info
  card, select-laptop hint, "Last laptop" chip, all status/error
  lines ("Getting ready…", discoverable status, Bluetooth-state
  error).
- **HID service (Dart)**: connection progress ("Turning
  Bluetooth on…", "Registering…", "Connecting…") and every
  plain-language error returned to the UI.
- **Controller screen**: Android Back dialog ("Disconnect?" +
  body), all mode banners (STEERING/TILT/CONTROLLER/ARROWS +
  tilt-sensor fallback), disconnect overlay body + reconnect
  button + back link.
- **Settings screen**: steering labels (wheel range, sensitivity,
  dead zone), flip-controls subtitle, default-game note, and all
  Help lines — rewritten to also teach the v4 modes and the
  AIM/CROUCH/weapon controls.
- **Kotlin** (`HidKeyboardManager.kt`, strings only): all 17
  user-facing error messages (registration, pairing, permission,
  Bluetooth-off, settings, connect failures).
- Already English and unchanged: all button labels, status pill,
  mode pill, Settings titles, CONNECT flow labels.

---

## MINOR (found in review, fixed before build)

### m1 — Weapon pair could touch the joystick's box on very short screens
**Lens:** Tester. **File:** `controller_screen.dart` →
`_buildOnFootLayer`

**Evidence:** The weapon pair sat at top 70 (bottom edge 118).
The joystick's top edge rises as screen height falls (its size
is height-driven): at 300 dp height the joystick box top is
≈116 — a ~2 dp bounding-box touch (no painted overlap — the
joystick is a circle — and no hit conflict in practice, but the
margin was thinner than this codebase accepts).

**Fix:** Pair moved to top 64 (bottom edge 112): ≥13 dp clear
of the top bar's bottom (≈51), ≥4 dp clear of the joystick box
even at 300 dp height, 26 dp at 360. Re-verified in the layout
table below.

### m2 — Dead parameter on the CROUCH builder
**Lens:** Expert. `_crouchButton(profile)` took a profile it
never used (CROUCH is `GameKey.c` in every profile). Parameter
removed so the next reader doesn't hunt for profile logic that
doesn't exist.

---

## Verified correct — no change needed

**Mode switching (Tester + Expert):**
- `_switchDriveMode` runs `_clearAllKeys()` before `setState` —
  keys, mouse buttons, PWM engine and arrow state all die before
  the new layer exists; outgoing-layer feeds during the 250 ms
  AnimatedSwitcher fade are blocked by per-source mode guards
  (`_feedWheelSteer` requires STEERING, `_feedTiltSteer` TILT,
  `_feedStickSteer` CONTROLLER, `_onArrowHeldChanged`/`_applyArrows`
  require ARROWS) — the QA m2 / IMPROVEMENTS_V3 T1 guard class,
  extended to both new sources.
- STEERING→TILT→CONTROLLER hopping: tilt subscription starts
  only on (driving ∧ TILT ∧ connected); leaving TILT cancels it
  via `_updateTiltSubscription`; the engine is reset by
  `_clearAllKeys` regardless of source, so no stale PWM key can
  survive into CONTROLLER. The new modes never touch the sensor.
- Persisted choice: switch → `setDriveMode` (writes `drive_mode`
  + legacy bool); cold start restores via `SettingsService.load`
  with bool migration. On-foot never shows the switch.
- Flip controls: both new layers mirror with the same
  Positioned/Transform pattern as the existing ones; the stick
  and cluster swap sides, the silhouette is symmetric, and the
  arrows pair keeps ◀ on the pair's left (direction semantics
  never mirror — same rule as the pedals keeping BRAKE left of
  RACE inside a flipped cluster).

**Stick (Expert):**
- Steer normalisation divides by knob travel (base radius −
  knob radius − 4), so full deflection = ±1 = full lock; the
  widget reports 0 the instant the finger lifts (the spring
  animation is visual only) and on dispose — the engine can
  never be left holding a stale value. Dead zone 0.12 /
  release 0.08 are fed as the engine's engage/release, so the
  stick gets the same hysteresis + PWM proportionality as the
  wheel; sensitivity multiplies before the dead zone, matching
  the wheel's treatment.
- The stick reports on down/move only; holding it still sends
  nothing new — the engine's 20 ms tick keeps pulsing from the
  last value, exactly like the wheel.

**Arrows (Tester):**
- Minimum pulse: release at t < 90 ms arms a one-shot timer for
  the remainder; `_arrowEffective` = physically held ∨ tail
  active. Re-press during a tail cancels the tail first (no
  premature cut). Both-sides-effective → empty source; when a
  tail expires, `_applyArrows` re-runs and the surviving side
  applies — the cancel rule and the pulse rule compose.
- All arrow timers are cancelled in `_resetArrows()`, which
  `_clearAllKeys()` calls — so mode switch, layout switch,
  steer switch, settings change, disconnect and pause all kill
  pending pulses; screen dispose cancels them directly too.
  A timer that somehow fired late would still hit the ARROWS
  guard in `_applyArrows` and no-op.
- Widget dispose fires `onHeldChanged(false)` (RoundButton
  pattern); post-switch calls are stopped by the mode guard.

**Mouse buttons (Expert):**
- `setMouseButton(bit, down)` composes bits and defers to the
  change-guarded `setMouseButtons` (mask 0x07). ATTACK release
  can no longer clear a held AIM and vice versa — the one real
  composition bug the AIM addition could have introduced,
  designed out at the service layer.
- `wheelTick` sends (0, 0, currentButtons, ±1) — a pure
  transient; the Kotlin side already clamps wheel to ±127 and
  masks buttons to 0x07 (v3 code, untouched).

**Regression pass (v3 behaviour):**
- STEERING and TILT layers: not one line of their layout or
  input code changed (the diff touches them only via the shared
  mode dispatch). ON FOOT rows 1–2 unchanged; row 3 and the
  weapon pair are additive, in previously empty space.
- Registration lifecycle, connect flow, pairing guide logic,
  auto-release paths, multi-touch capture, text-scale clamp,
  compact scaling: untouched files/behaviour.
- `hidKeyOrder` gained C after F; for every key set not
  containing C the emitted report bytes are identical to v3.

---

## Pre-delivery verification checklist (owner-required)

### 1. HID descriptor + Kotlin channel vs v3 (b3ca393) — ✅ PASS
- `git diff b3ca393 -- android/`: exactly **17 changed lines**,
  every one the text of a user-facing error string in
  `HidKeyboardManager.kt`. No code, constant or descriptor line
  appears in the diff.
- Descriptor + SDP + QOS block (extracted from
  `REPORT_DESCRIPTOR` through `QOS_SETTINGS`): md5
  `ba778a379ab87a7f50ec5d2810479153` at b3ca393 **and** in the
  v4 tree — identical.
- Channel method-name set: md5 identical at both revisions.
- `MainActivity.kt`: md5 `109b3397779a26562a47de571fbe87df`
  at both revisions — untouched.
- **Conclusion: no re-pair needed for v4.** Windows' cached SDP
  record (from the v3 pairing) stays valid.

### 2. Roman Urdu sweep — ✅ PASS (zero user-facing hits)
Grepped all of `lib/` and both Kotlin files for: `ho raha`,
`karun`, `Masla`, `aa raha`, `dabao`, `kholo`, `chahiye`,
`bhej`, `wala hai`, plus the wider net (`nahi`, `dobara`,
`koshish`, `warna`, `taake`, `ke liye`, `jayeg`, `chhut`,
`atak`, `ungli`, `simt`, `band karo`, `Samajh`, …).
- **String literals: zero hits.** Every user-facing string is
  English (areas listed above).
- Remaining hits are exclusively in `//` and `/** */` code
  comments (developer documentation, never rendered) — e.g.
  `hold_surface.dart`, `camera_pad.dart`, `steering_wheel.dart`
  inline comments and the Kotlin class docs. Classified, not
  user-facing.

### 3. Built-APK string check — executed post-build, pre-delivery
Procedure: unzip the CI artifact, run `strings` over
`lib/*/libapp.so`, require STEERING, TILT, CONTROLLER, ARROWS,
AIM, CROUCH and WPN present, plus "AB GTA" in the manifest and
the package id unchanged. **Result is recorded in the v4
delivery report; delivery is blocked unless this passes.**
(Same method that verified CAMERA/ATTACK in the v3 APK.)

### 4. Numeric layout verification at 640×360 — ✅ PASS
Common: top-bar chrome ends ≈51; CAMERA pad spans top 64 /
bottom 72 (height 224) in every layout; ghost buttons occupy
bottom 12..60 at centre; clusterScale = 1.0 at exactly 360
height (0.86 below). All gaps between controls ≥12 dp.

| Layout | Left control (x-range) | Pad (x-range, width) | Right cluster (x-range) | Cluster top edge | Gaps |
|---|---|---|---|---|---|
| STEERING (v3, unchanged) | wheel 34..250 | 262..404 (142) | 416..614 | 82 | 12 / 12 |
| TILT (v3, unchanged) | BRAKE 34..131 | 143..404 (261) | 416..614 | 82 | 12 / 12 |
| CONTROLLER (new) | stick 34..182 | 194..404 (210) | 416..614 | 156 | 12 / 12 |
| ARROWS (new) | arrows 30..222 | 234..404 (170) | 416..614 | 82 | 12 / 12 |
| ON FOOT (v4 rows added) | joystick 44..234 | 246..382 (136) | 394..614 | 112 | 12 / 12 |

Details:
- CONTROLLER cluster: RACE 198×54, gap 10, BRAKE 198×54,
  gap 12, action row 198×58 → height 188, top edge 156.
  Stick block: 148 wide, 168 tall (incl. STEER caption),
  top edge 176. Silhouette is decorative behind all controls
  (first in stack, painter never hit-tests) — visual only.
- ARROWS pair: 88 + 16 + 88 = 192 wide at left 30, bottom 84
  (y-band 84..172 from bottom) — clear of the centred ghost
  buttons (bottom ≤60) by 24 dp vertically and of the pad by
  12 dp horizontally.
- ON FOOT additions: row 3 = AIM 96 + 12 + CROUCH 92 = 200
  wide × 48 → cluster height 80+12+80+12+48 = 232, top edge
  112 (61 clear of the top bar); max row width stays 220, so
  the pad is exactly v3's. Weapon pair: 48+8+48 = 104 wide at
  left 44, top 64..112 — 26 dp above the joystick's top edge
  (144) at 360 height, ≥13 dp below the top bar, 98 dp left of
  the pad. On flip it follows the joystick side; the cluster
  side is never involved.
- Top bar at 640: 4-segment switch ≈ 312 dp + mode pill ≈ 216
  + gaps 24 → the Flexible status pill gets ≈88 dp and its
  text ellipsizes (pre-existing v3 mechanism — no overflow, no
  overlap; at the owner's ~880 dp wide screen the full laptop
  name shows). Cosmetic only, accepted.

### 5. Control-by-control trace (press → report → release) — ✅ PASS
Release paths for every row: **mode switch** (Driving↔On Foot),
**layout/mode switch** (drive-mode pill), **Settings round-trip**
(`_openSettings` clears + stops tilt first), **disconnect**
(HID event → `_clearAllKeys` + service state reset; Kotlin
sends zero reports), **app pause** (Dart lifecycle clear +
`releaseAllKeys`; Kotlin `onHostPause` zero reports),
**dispose** (screen dispose → `releaseAllKeys`; widget dispose
releases; Kotlin dispose zero reports). `_clearAllKeys()` =
sources cleared + RUN reset + arrow state reset + PWM engine
reset + `HidService.releaseAllKeys()` (keys snapshot + mouse
buttons zeroed).

| Control | Press → HID report | Release |
|---|---|---|
| RACE pedal / trigger (W) | HoldSurface down → source `race` → snapshot report ID 1 | Up/cancel → source cleared; HoldSurface dispose fires false; all clear paths |
| BRAKE pedal / trigger (S) | Same, source `brake` | Same |
| HANDBRAKE (Space) | RoundButton hold → source `handbrake` | Up/cancel/dispose → source cleared; all clear paths |
| ENTER/EXIT (F) | Tap → source `ftap`, 150 ms, target layout captured first, 250 ms lockout | Automatic at 150 ms; mid-tap clear leaves a no-op release + the intended mode switch; dispose backstopped by `releaseAllKeys` |
| MAP (Esc) | `_momentaryKeyPress('map')` → source `tap_map`, 150 ms + generation guard | Automatic; stale generations no-op |
| JUMP (profile key) | `_momentaryKeyPress('jump')` | Same |
| CROUCH (C) — new | `_momentaryKeyPress('crouch')` → source `tap_crouch` | Same (SA toggles crouch per press — no held state exists to stick) |
| RUN (sprint key) | Tap toggles source `run`; key present in every report while on | Second tap, or any clear path (also resets the toggle + light) |
| Wheel (STEERING) | Angle → engine → source `pwm` (A/D pulses) | Spring return feeds 0 → engine nulls; unmount paths clear engine |
| Tilt (TILT) | Sensor → engine → source `pwm` | `_stopTilt` (switch/pause/disconnect/settings); flat-phone + flip-invalidation engine resets; sensor error → STEERING fallback + clear |
| Stick (CONTROLLER) — new | Drag → engine (source `stick`) → source `pwm` | Finger lift reports 0 immediately; widget dispose reports 0; mode guard blocks fade-out feeds; clear paths reset engine |
| Arrows ◀ ▶ (ARROWS) — new | Listener down → source `buttons` (A or D) | Up/cancel → release, extended to 90 ms total if shorter (timer, cancelled by clear paths + dispose); both-held = empty source; widget dispose fires false (mode-guarded) |
| Joystick (WASD) | Sectors → source `joystick` | Centre/release → empty; widget dispose fires empty |
| ATTACK (mouse L) | RoundButton hold → `setMouseButton(0x01, true)` → mouse report ID 2 | Up/cancel/dispose → bit cleared (AIM bit preserved); `releaseAllKeys` zeroes all bits; Kotlin zero-mouse backstops |
| AIM (mouse R) — new | Pill hold → `setMouseButton(0x02, true)` → mouse report ID 2 | Same as ATTACK, mirrored bit |
| CAMERA pad | Drag → relative move reports (no state) | Nothing to release; flush timer cancelled on lift/dispose |
| Weapon ◀ ▶ (wheel) — new | Tap/hold-repeat → wheel tick report (transient, carries current button state) | Nothing held; repeat timers cancelled on up/cancel/dispose |
| Mode pill / drive-mode switch / ghost buttons | Send no keys by design | Switching itself runs the clear paths above |

**Verdict: no path leaves a stuck key or mouse button.** Every
stateful input is owned by exactly one of: a key source (cleared
by `_clearAllKeys`), the PWM engine (reset by `_clearAllKeys` /
dispose), `HidService` mouse state (zeroed by
`releaseAllKeys`), or a named timer (cancelled in
`_resetArrows` / widget dispose / screen dispose) — with the
unchanged Kotlin zero-report backstops beneath all of them.

---

## Must verify — CI build & owner's device test

1. **CI compile** — first proof of the Dart switch expressions,
   the new widgets and the enum refactor. (No local SDK, as in
   v1–v3.)
2. **No re-pair needed** — descriptor unchanged (checklist #1);
   v4 installs over v3 and the v3 pairing just works.
3. **Device — CONTROLLER feel:** stick travel vs car response,
   PWM proportionality from the stick, trigger hold comfort.
4. **Device — ARROWS feel:** 90 ms tap = a visible small nudge;
   hold = smooth continuous steer; both-thumb press cancels.
5. **Device — gunplay:** hold AIM + hold ATTACK together (both
   mouse bits in one report), fire, release — nothing sticks.
6. **Device — weapon/CROUCH:** WPN taps cycle one weapon per
   tap in SA; hold cycles fast; CROUCH tap crouches, second
   tap stands.
7. **Device — English pass:** pairing guide, errors and help
   read naturally in English; banners show the right mode name.
