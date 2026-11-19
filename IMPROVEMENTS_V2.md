# AB GTA — v2 Review: User / Tester / Expert (Racing Cockpit + TILT + rename)

**Date:** 2026-11-19
**Scope:** The v2 changes only — Racing Cockpit theme, BRAKE-first pedal
order, TILT steering mode (`sensors_plus`), STEERING|TILT switch, rename
to "AB GTA", custom launcher icons — reviewed through the same three
lenses as QA_REPORT.md and IMPROVEMENTS.md, against the v2 section of
BUILD_NOTES.md.
**Method:** Static review of every v2-touched file (no SDK/device on this
machine — same limit as the previous audits). Tilt sign and sampling
behaviour were re-derived from the Android sensor model, not taken from
the build notes' claims. Everything marked FIXED is implemented in code,
uncommitted — the main agent owns git/CI.

**Result: 1 critical, 4 major, 5 minor — all fixed.**
**No QA_REPORT / IMPROVEMENTS fix is regressed** (verified list at the
end): early HID registration, no-unregister-on-pause, registration waiter
list, class-aware auto-refreshing device list, fast-fail connect wait,
permission Settings path, wheel as raw `Listener`, wheel hysteresis,
text-scale clamp 0.85–1.15, compact scaling — all untouched in behaviour.
Kotlin was not modified at all this round.

---

## CRITICAL

### E1 — Tilt steering was INVERTED (right tilt → car steers left)
**Lens:** Expert. **File:** `lib/screens/controller_screen.dart` → `_onTiltEvent`

**Evidence:** The v2 code computed `delta = baseline − current` and the
build notes claim this "yields clockwise-positive = steer-right in both
landscape orientations — verified by worked examples". The worked
examples do not survive re-derivation. The accelerometer reports the
**up** vector (specific force) in the device frame. Writing α for
`atan2(gy, gx)` and φ for the phone's rotation from portrait, the
reported vector gives α = 90° − φ — so when the user rotates the phone
**clockwise** (steer right) by δ, α **increases** by δ, in *both*
landscape orientations:

- *Landscape-left:* held straight, event ≈ (+9.81, 0) → α = 0°.
  Steer right 20° → event ≈ (+9.22, +3.35) → α = +20°.
  Code's delta = 0 − 20 = **−20° → LEFT key.**
- *Landscape-right:* held straight, event ≈ (−9.81, 0) → α = 180°.
  Steer right 20° → event ≈ (−9.22, −3.35) → α = −160°.
  Code's delta = 180 − (−160) = 340 → wrapped **−20° → LEFT key.**

The notes' intuition ("device-frame gravity counter-rotates") applies
to the angle *increasing* under clockwise rotation — the subtraction
was the wrong way round. As shipped, TILT mode would have steered the
car opposite to the phone, 100% of the time, in both orientations —
the new feature's core interaction, broken.

**Fix:** `delta = angleDeg − _tiltBaselineDeg!` (clockwise-positive in
both orientations, consistent with the touch wheel's own sign
convention: positive angle → D). The code comment now carries the
correct worked example and records that the v1 formula was inverted.
The BUILD_NOTES v2 section still contains the wrong derivation — left
for the main agent to correct, per the QA m5 precedent. If the owner's
device test somehow disagrees with the derivation, this remains a
one-line flip — but the derivation was checked three ways (formula +
explicit vectors in both orientations).

---

## MAJOR

### E2 — Tilt sampled at the 200 ms default — ~0.7 s of steering lag
**Lens:** Expert. **File:** `controller_screen.dart` → `_startTilt`

**Evidence:** `accelerometerEventStream()` was called with no
`samplingPeriod`, so sensors_plus uses `SensorInterval.normalInterval`
= 200 ms (Android `SENSOR_DELAY_NORMAL`, 5 Hz — a rate meant for
screen-orientation changes). Stacked with the α = 0.25 low-pass
(effective lag ≈ 3 samples), a steering input took roughly
200 ms (sampling) + ~600 ms (filter) ≈ **0.7 s** to register — the car
would feel drunk. The build notes never mention the rate.

**Fix:** `accelerometerEventStream(samplingPeriod:
SensorInterval.gameInterval)` (20 ms / 50 Hz, `SENSOR_DELAY_GAME`).
Filter lag drops to ~60 ms; α = 0.25 is then well-judged and was left
alone. No `HIGH_SAMPLING_RATE_SENSORS` permission is needed (that is
only for >200 Hz on Android 12+). Android treats the period as a hint,
so the device test should confirm the delivered rate feels live.

### T1 — Opening Settings in TILT held a false steering key for the whole visit
**Lens:** Tester. **File:** `controller_screen.dart` → `_openSettings`

**Evidence:** Pushing a route does not pause the app, and
`_openSettings` only cleared keys once at open. The tilt subscription
kept running under the Settings screen — which forces **portrait**.
Rotating the phone to portrait swings the in-plane gravity angle ~90°
from the landscape baseline, so `_evaluateTilt` engaged A or D and
*held it the entire time the user was in Settings*, re-adding the
source after every settings change cleared it. The car steers itself
while the user reads a settings list.

**Fix:** `_openSettings` now calls `_stopTilt()` before the push and
`_updateTiltSubscription()` after the pop (next to the existing
`_applyLandscape()`), so tilt restarts afterwards with a fresh
baseline. Same reasoning already applied to app-pause; the route push
was the one lifecycle hole left.

### T2 — Baseline was a single noisy sample captured mid-jolt
**Lens:** Tester. **File:** `controller_screen.dart` → `_onTiltEvent`

**Evidence:** The baseline was literally the first accelerometer
sample after `_startTilt`. That sample is also the low-pass seed
(unfiltered), and tilt is usually entered by tapping the STEERING|TILT
switch — a tap that physically jolts the phone. A baseline off by
3–5° shifts both engage thresholds asymmetrically (e.g. right engages
at 8°, left at 16°) and makes a centred car creep one way until the
user re-enters TILT. The build notes' "phone jis haalat me pakra hai,
wahi seedha hai" only holds if the phone is *still* at that instant.

**Fix:** The baseline is now the **vector average of the first
~300 ms of valid samples** (`atan2` of the summed smoothed vectors —
wrap-safe by construction). No key is evaluated until the baseline
locks. A new `_resetTiltBaseline()` keeps the accumulator, the
smoothing seed state and the flat-timer consistent across every
start/stop path.

### T3 — Laying the phone flat held the steering key forever
**Lens:** Tester. **File:** `controller_screen.dart` → `_onTiltEvent`

**Evidence:** The flat-phone guard (`magnitude < 2.5`) returned early
and deliberately "kept the current key" — indefinitely. Put the phone
down on a table mid-drive with a steer key engaged and the key stays
down until the phone is picked up, the mode changes, or the app
pauses: precisely the stuck-key failure class every other part of
this app is engineered to make impossible (and the car circles in-game
meanwhile).

**Fix:** Short dips still keep the key (hand shake shouldn't stutter
steering), but after **250 ms** of continuously invalid samples the
tilt key is released. The baseline is *kept* — picking the phone back
up in the same hold resumes steering immediately.

---

## MINOR

### T4 — Tilt subscription wasn't gated on the connection
**Lens:** Tester. **File:** `controller_screen.dart` → `_updateTiltSubscription`

**Evidence:** The guard was `_driving && _tiltMode`; the disconnect
case was covered only because the HID listener calls `_stopTilt()`
directly. A lifecycle `resumed` (or a Settings return) while
disconnected restarted the sensor, and a tilt key engaged at the
moment of reconnect would ride QA M3's clean-state snapshot into the
game. Tilt is the app's first *hands-free* key source — the wheel and
joystick can't do this, because they need a finger down.

**Fix:** The guard is now `_driving && _tiltMode && _connected`. On
reconnect the HID listener restarts tilt with a fresh baseline, as
already documented. The function's doc comment (which already claimed
"disconnect me band") is now actually true on every path.

### T5 — Phone flipped to the other landscape side wedged a permanent steer
**Lens:** Tester. **File:** `controller_screen.dart` → `_onTiltEvent`

**Evidence:** Baseline is relative to one landscape side. Rotating the
phone 180° in-plane to the other side (cable on the wrong side — a
real mid-session move) leaves delta ≈ ±180°, which the hysteresis
reads as a permanently held steer in one direction until TILT is
re-entered.

**Fix:** `|delta| > 100°` is treated as an invalid orientation: the
tilt key is released and the baseline is invalidated, so a fresh
~300 ms baseline is captured at the new hold. Legitimate tilt play
never approaches 100° from the user's own centre, so this cannot fire
during real steering.

### U1 — A dead/missing accelerometer left the switch lying
**Lens:** User (+ Expert). **File:** `controller_screen.dart` → `_startTilt` onError

**Evidence:** On a sensor-stream error the old code stopped tilt
"silently" — the switch kept showing TILT active, the wheel stayed
gone, and steering was simply dead with no explanation. A first-time
user cannot distinguish that from "tilt doesn't work".

**Fix:** On error, this session falls back to STEERING (wheel
returns), and a banner says why: *"⚠ Tilt sensor nahi mila — STEERING
on hai"*. The *saved* preference is deliberately not overwritten — a
transient stream error shouldn't rewrite the user's setting; next
session TILT is tried again. Pedals and buttons were never affected.

### U2 — Switching steer mode gave no feedback; restored TILT was a surprise
**Lens:** User. **File:** `controller_screen.dart` → `_switchSteerMode`, `_modeBannerText`

**Evidence:** Tapping the switch made the wheel vanish/appear with no
explanation of what changed or what to do next — and because the
choice persists, a user returning days later with TILT saved entered
Driving to find no wheel and only a plain "🚗 DRIVING" banner.

**Fix:** The switch now shows the standard mode banner —
*"📱 TILT — phone hilao"* / *"🎡 STEERING — ungli se ghumao"* — and
the driving-entry/mode banner reads *"🚗 DRIVING • TILT"* whenever
tilt is active, via a shared `_modeBannerText`. No new UI elements;
the existing banner channel does the teaching.

### U3 — Settings never mentioned TILT existed
**Lens:** User. **File:** `lib/screens/settings_screen.dart` (Help card)

**Evidence:** The switch lives only on the controller's top bar, and
the Settings "Steering" section (range / sensitivity / dead zone)
reads as if it governs *all* steering — a tilt user could reasonably
expect the dead-zone slider to change tilt's fixed 12°/8° (it doesn't;
BUILD_NOTES documents "no new Settings-screen entries" as a design
choice, so no control was added).

**Fix:** One Help line, in the card's existing Roman Urdu style,
saying where the STEERING|TILT switch lives, what TILT does, and that
the steering settings above it apply to the touch wheel only.

### E3 — Round launcher icon existed but was never referenced
**Lens:** Expert. **File:** `android/app/src/main/AndroidManifest.xml`

**Evidence:** v2 shipped `ic_launcher_round.png` at all five
densities, but the manifest declared only `android:icon`. Launchers
that request the round variant (Pixel-style) silently fell back to
the square icon.

**Fix:** Added `android:roundIcon="@mipmap/ic_launcher_round"`.
Verified the artwork survives the circular mask: the wheel fits
inside the inscribed circle, so the mask trims only dark carbon
corners. (The round PNGs are byte-identical to the square ones —
acceptable, since the launcher applies the mask itself.)
**CI dependency:** the manifest now *requires* `ic_launcher_round` to
exist after the `flutter create` merge — see "Must verify" below.

---

## Verified correct — no change needed

**Tilt core (Expert):**
- **Hysteresis logic** (`_evaluateTilt`): engage >12°, release ≤8°,
  direct left↔right crossings switch immediately, boundary values
  behave symmetrically. Correct as shipped.
- **Flip-controls does *not* need to invert tilt**, and doesn't: flip
  is a layout mirror; the phone's physical rotation for "right" is
  the same whichever side the pedals sit on. Inverting would *create*
  the E1 bug for flipped users only.
- **sensors_plus ^7.0.0 usage**: `accelerometerEventStream()` +
  `samplingPeriod` + `SensorInterval` are the current 7.x API
  (confirmed against the package docs); stream errors surface as
  async stream errors (handled — U1); a missing accelerometer
  degrades through that same path, never a crash.
- **Low-pass α = 0.25** at the new 50 Hz rate: ~60 ms time constant —
  the right side of responsive-vs-jittery. Only wrong *because of*
  the old 200 ms rate (E2), not in itself.

**Tilt lifecycle (Tester):**
- **No subscription leak or double-subscribe path exists**:
  `_startTilt` is guarded by `_tiltSubscription != null`, every stop
  cancels the referenced subscription before nulling it, and the
  error path funnels through `_stopTilt`. Rapid STEERING↔TILT
  toggling can at worst double-deliver a sample or two during the
  async cancel — harmless to a state machine that only acts on
  threshold crossings, and self-correcting on the next event.
- Switch is **not rendered on foot** (`top_bar.dart`: `if (driving &&
  …)`), tilt cannot start on foot (`_driving` in the guard), and
  entering Driving in TILT starts it via `_switchMode` — all correct.
- Disconnect / pause / inactive / dispose all stop tilt and release
  its key; reconnect restarts with a fresh baseline. Correct.
- Switching steer mode mid-drive clears all keys first (pedals must
  be re-pressed afterwards) — the *same* semantics as the pre-existing
  mode switch and settings change (QA m3), and the layer is rebuilt
  by the AnimatedSwitcher either way. Consistent, not a bug.
- **Pedal multi-touch in the tilt layout** uses the identical
  `HoldSurface` per-pointer widgets as steering mode (BRAKE left
  thumb + RACE right thumb + HANDBRAKE third finger verified by code
  path) — arena-free, unchanged.
- **Text-scale clamp and compact scaling cover the new UI**: the
  clamp wraps the whole controller (switch included); the tilt
  layer's BRAKE and RACE cluster both take `clusterScale`. The top
  bar fits three elements because the status pill is `Flexible` with
  a 200 dp name cap (IMPROVEMENTS T4) — the switch (~196 dp) and mode
  pill (~212 dp) always keep their place.

**User surface:**
- **BRAKE alone on the left in TILT reads as intentional** — it sits
  at the wheel's exact anchored spot (left: 34, bottom: 16) with the
  same scale treatment, and EXIT CAR + HANDBRAKE keep their steering-
  mode position above RACE. Nothing about the layout looks like a
  missing wheel once the U2 banner has explained the mode.
- **Switch state is obvious**: active segment is a filled orange
  gradient with white bold text; inactive is muted blue-grey text on
  near-black. No ambiguity at arm's length.
- **Theme readability**: Racing Cockpit keeps body text at
  #CBD5E1 / #94A3B8 on #0B0E13 (comfortable contrast); orange is
  reserved for accents, borders and CTAs with white text. No teal
  hex from v1 survives anywhere in `lib/`.
- **Rename is complete**: zero user-visible "GTA Remote" remains in
  `lib/`, `android/` or `pubspec.yaml` — manifest label, MaterialApp
  title, connect header, permission dialog, Kotlin SDP
  name/description/provider and the Settings-path error string all
  say **AB GTA**. Package id unchanged, so v2 installs over v1.
- **Icons**: exact sizes at all densities (48/72/96/144/192) for both
  variants; no `mipmap-anydpi-v26` exists, so no adaptive-XML
  conflict is possible; corners are carbon-filled (visually
  confirmed at xxxhdpi — no white triangles).

**Not regressed (spot-checked against both prior reports):** Kotlin
untouched (waiter list, no-unregister-on-pause, SDP, bond check all
as QA left them); connect screen's early registration, 4 s
auto-refresh, class-aware sorting and "Aakhri laptop" chip untouched;
wheel file changed only in paint colours since IMPROVEMENTS T1/T2;
hid_service untouched this round.

---

## Must verify — CI build & owner's device test

1. **CI compile** is the first proof of this round's edits —
   specifically the `SensorInterval` import surface of sensors_plus
   ^7.0.0 and the new tilt fields. (Static balance checks pass;
   there is no SDK here.)
2. **CI workflow must preserve `res/mipmap-*`**: the manifest now
   references `@mipmap/ic_launcher_round`; if the workflow ever
   replaces `res/` wholesale instead of merging, AAPT linking fails
   on the missing round resource. (BUILD_NOTES already flags the
   merge requirement — it is now load-bearing.)
3. **Device — tilt direction, both landscape sides** (E1): hold the
   phone each way, tilt right, car must go right. The derivation is
   solid, but this is the one-line-flip check the build notes
   anticipated — just with the opposite expected outcome.
4. **Device — tilt feel** (E2/T2): delivered sample rate on realme UI
   (Android may not honour 50 Hz exactly), 12°/8° thresholds, and
   whether the ~300 ms baseline window is unnoticeable at mode entry.
5. **Device — Settings round-trip in TILT** (T1): open Settings
   mid-drive; the car must not steer while Settings is open, and tilt
   must resume (fresh baseline) on return.
6. **Device — flat test** (T3): engage a tilt steer, lay the phone
   flat; the key must release within ~a second (250 ms + one HID
   report), and steering must resume on pick-up without re-entering
   TILT.
