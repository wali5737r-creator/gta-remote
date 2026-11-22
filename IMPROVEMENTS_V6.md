# IMPROVEMENTS_V6 — v5.1 QA (cheat typer reliability + FLY mode + rename)

Three-lens review (user / tester / expert) of the v5.1 changes, with full
traces. Written before the build; the GitHub Actions release build is the
compile proof (no local Flutter/Dart SDK), and Muhammad's device is the
final judge for feel.

---

## 1. What changed

1. **Cheat typer reliability fix** (`lib/services/hid_service.dart`,
   `lib/screens/cheats_screen.dart`) — owner-device bug: tapped cheats did
   nothing in-game while laptop-keyboard typing worked.
2. **FLY driving mode** — Muhammad's corrected design: ONE handle for turn
   + pitch (he rejected the earlier TURN/NOSE button-cluster draft),
   RACE + DOWN pedals, camera pad + EXIT/MAP. Files:
   `lib/widgets/fly_stick.dart` (new), `lib/models/game_key.dart`,
   `lib/services/settings_service.dart`, `lib/screens/controller_screen.dart`,
   `lib/widgets/steer_mode_switch.dart`, `lib/screens/settings_screen.dart`,
   mockup `mockup/v6-fly-mode.html` (rewritten for the handle design).
3. **Rename to "Gaming Remote"** — found ALREADY applied as v5.0.1
   (commit `b9cca6f`) before this task ran; verified complete (see §6).

Zero changes under `android/` for items 1–2 (and none needed for 3).

---

## 2. The Kotlin boolean — what `sendReport` really returns

Read directly from `HidKeyboardManager.kt` (lines 671–695, read-only —
Kotlin not modified):

- If the HID proxy is null, no device is connected, or the state is not
  `STATE_CONNECTED` → `result.success(false)`.
- Otherwise it builds the 8-byte report and calls
  `proxy.sendReport(device, REPORT_ID, data)` — the Android
  `BluetoothHidDevice.sendReport(...)` API — inside a try/catch
  (`SecurityException` → `false`), and returns `result.success(sent)`.

**Conclusion: the returned boolean genuinely is the Android HID stack's
own accept/reject answer for that exact report.** A `false` means the
report was refused before/at queueing — it is a real dropped report, not
a "maybe".

**The v5 bug, precisely:** the Dart typer awaited the channel call but
discarded the boolean (only `PlatformException` was caught). At 55 ms
down / 40 ms gap, any single refused report silently deleted one letter,
the typed word was corrupted, and GTA's cheat system (which needs the
exact word) did nothing — matching the owner report exactly, including
why ordinary remote keys (state snapshots, resent on every change) were
unaffected.

## 3. Typer fix — design and traces

- `_sendRawReportReliable(keycode)`: awaits `sendReport`, reads the
  boolean. On `false` (or `PlatformException`): wait 40 ms, retry — up to
  2 retries (3 attempts total per report). Returns whether the report was
  accepted.
- Timings: key-down held **90 ms**, inter-letter gap **70 ms** (was
  55/40). GTA V console: grave (0x35) down 90 ms → up → **300 ms** settle
  → letters → Enter (0x28) down 90 ms → up. All through the same helper.
- If any report still fails after retries, typing **aborts immediately**
  and returns `CheatSendResult.sendFailed` — no pretending.
- Return type is now `CheatSendResult { success, notConnected,
  sendFailed }`. CHEATS screen mapping:
  - success → "Sent — check your game"
  - sendFailed → "Could not send — check the connection and try again."
  - notConnected (link dropped mid-type) → "Connection lost — the code
    was not fully typed."
  - Pre-tap disconnected check unchanged: "Not connected — connect to
    your laptop first."
- Safety semantics kept from v5, re-verified line by line: refuse when
  disconnected or already typing; `releaseAllKeys()` first; per-letter
  connection check; raw sends bypass `_lastSentSignature` dedup (so
  repeated letters — e.g. the six O's of BOOOOOORING — are real separate
  presses, never merged); `finally` clears the typing flag, resets the
  signature, re-sends the current snapshot, and on the abort path sends
  an extra reliable raw empty report so no letter can stay down on the PC.
- **Retry double-press risk — considered and accepted:** per §2, `false`
  means the stack refused the report, so a retry cannot double-type in
  the normal case. Worst case (a hypothetical stack that queued yet
  reported false) one letter doubles, that one cheat fails, and the user
  re-taps — strictly better than v5, where a dropped letter failed every
  affected cheat silently.
- **Duration:** typical ≈ 160 ms per letter (a 10-letter code ≈ 1.6 s,
  vs ≈ 1 s in v5); worst case with full retries ≈ 320 ms per letter. The
  CHEATS screen shows "Typing CODE…" for the whole duration (it polls
  `isTypingCheat`), so the longer time is visible, not a hang.

## 4. FLY mode — traces (read these before "fixing" anything)

### 4.1 Handle axes → keys (`_feedFlyStick`, source `'flystick'`)

The `FlyStick` widget reports raw axes (x: −1 left … +1 right;
y: −1 up … +1 down), AnalogStick mechanics (single-pointer capture,
radial clamp, spring return; release and dispose both report (0, 0)
immediately). The controller applies a dead zone with hysteresis —
**engage 0.25, release 0.18** — per axis, independently:

| Handle position | Key held | Effect in GTA SA |
|---|---|---|
| left (x ≤ −0.25) | profile steer-left (**A**) | turn / bank left |
| right (x ≥ +0.25) | profile steer-right (**D**) | turn / bank right |
| **up (y ≤ −0.25)** | **`GameKey.arrowDown` (0x51)** | **NOSE UP (climb)** |
| **down (y ≥ +0.25)** | **`GameKey.arrowUp` (0x52)** | **NOSE DOWN (descend)** |
| diagonal (both axes past dead zone) | both keys at once | turn + climb/descend together |
| released / centred | none | all four keys release |

> **⚠ THE PITCH INVERSION IS INTENTIONAL.** Handle UP sends ArrowDown
> and handle DOWN sends ArrowUp. This is the flight-stick convention and
> it matches the game: in GTA SA, **ArrowDown pitches the nose UP** and
> ArrowUp pitches it DOWN. "Correcting" this table would invert flight
> controls and break the mode. The same warning lives in
> `game_key.dart`, `_feedFlyStick`, `BUILD_NOTES.md`, and the Settings
> help text ("push it up to climb (nose up), pull it down to descend").

- No PWM and no sensitivity multiplier in FLY: keys are plain holds while
  an axis is beyond the dead zone (per the design brief).
- Both axes feed ONE source set, so a diagonal is a single snapshot with
  two keycodes — the key-set architecture sends them in one report.
- Release behaviour: widget release → (0, 0) → both dirs 0 → source set
  emptied → snapshot without those keys. Mode switch / ON FOOT switch /
  opening CHEATS, GUIDE or Settings / disconnect all run
  `_clearAllKeys()`, which now also calls `_resetFlyStick()`; the
  widget's own dispose-report is a second, independent safety (its feed
  is mode-guarded, so a late (0, 0) after a switch is a no-op against
  already-cleared state).
- The pitch keys only reach the laptop because `arrowUp`/`arrowDown`
  were **appended to `hidKeyOrder`** — the snapshot sender iterates that
  list. They were appended at the END so every pre-existing key set
  produces byte-identical reports to v5 (existing modes provably
  unchanged at the wire level).

### 4.2 Pedals, camera, EXIT/MAP

| Control | Path | Key |
|---|---|---|
| RACE pedal | `HoldSurface` → `_setSourceKeys('race', …)` | profile accelerate (**W**) |
| DOWN pedal | `HoldSurface` → `_setSourceKeys('brake', …)` | profile brake (**S**) — brake on ground, descend/slow in air |
| CAMERA pad | `CameraPad.onMove` → `_hid.moveMouse` (same component & path as all modes) | HID mouse |
| EXIT button | `_enterExitButton()` → `_onEnterExitTap` (v3 clean press: 150 ms + lockout) | profile enter/exit (**F**) |
| MAP button | `_mapButton()` → `_momentaryKeyPress('map', …)` (same v3 pattern) | **Esc** |

- No HORN in FLY (no horn control exists in the layer) and no MISSION:
  the MISSION pill condition in `build()` is now
  `_driving && _driveMode != DriveMode.fly`. Other modes' pill behaviour
  is byte-for-byte the old condition plus this one exclusion.
- Cosmetic note (accepted): the shared EXIT button's driving label reads
  "EXIT CAR" in every driving mode, FLY included — same wording as
  STEERING/TILT/etc.; not changed, to avoid touching shared controls.

### 4.3 Persistence & migration

- `DriveMode.fly('FLY')` appended to the enum; stored via the existing
  `setDriveMode` (`drive_mode` key + legacy `tilt_steering` bool sync).
- `DriveMode.byName` already falls back to STEERING for unknown names:
  v5 stored values (`steering/tilt/controller/arrows`) all still parse;
  a hypothetical corrupt value cannot crash; even a downgrade to the v5
  app with `fly` stored degrades to STEERING, not a crash.

## 5. Layout budget — FLY at 640×360, and the 5-mode pill

### 5.1 FLY columns (heights from the top of the screen)

| Column | x (non-flip) | Width | Vertical | Contents |
|---|---|---|---|---|
| HANDLE | 16 … 212 | 196 | top 84, bottom 16 (260 tall, centred) | FlyStick 176 (+ HANDLE caption ≈ 199 total) |
| CAMERA | 224 … 494 | **270** | top 84, bottom 72 (204 tall) | caption 17 + 6 + pad ≈ 115 (flex) + 8 + EXIT/MAP row 58 |
| THROTTLE | 506 … 624 | 118 | top 84, bottom 16 (bottom-anchored) | caption 17 + 6 + RACE 118 + 10 + DOWN 84 = 235 |

- Width check: 16 + 196 + 12 + 270 + 12 + 118 + 16 = **640** ✓.
  Camera pad **270 ≥ 170** ✓; inter-column gaps **12** ✓ (brief minimum).
- Flip: HANDLE ↔ THROTTLE swap sides (16…134 pedals, 428…624 handle);
  CAMERA stays central (146…416) — pitch is central under flip, per spec.
- Ghost-button clearance: the EXIT/MAP row's bottom edge is at
  y = 360 − 72 = **288**; the centre ghost buttons occupy y ≈ 300…348 →
  12 dp clear, the same bottom-72 protection the other modes' camera pad
  uses. Side columns end at x ≤ 212 / x ≥ 506, far from the ghost zone
  (x ≈ 266…374).
- Top clearance: columns start at y = 84; Row-2 pills (CHEATS/GUIDE, on
  the pedals side) end at y ≈ 74 → 10 dp clear.
- Short screens: the existing `clusterScale` (0.86 below 360 dp height)
  scales the stick (→ ≈151) and the pedal column (→ ≈202) — the handle
  column total ≈ 171 and pedals ≈ 202 both fit a 224-tall stage.
- Narrower screens: camera width = W − 370 → 200 at W=570, still ≥ 170;
  below that it shrinks like every other mode's pad does.
- **Deviation, forced by geometry:** the brief asked for the existing
  pedal widgets stacked (RACE over DOWN). A full `CarPedal` is
  arm 26 + gap 1 + pad + label block ≈ **192 (RACE) / 148 (BRAKE)** tall;
  stacked = **340 > 260** available — impossible at 360 dp height. FLY
  therefore uses `_FlyPedal`: compact pads in the exact CarPedal/trigger
  colours (green RACE, red DOWN) on the same `HoldSurface` capture
  semantics, RACE still the taller pedal (118 vs 84), labelled
  "RACE — W — speed / climb" and "DOWN — S — brake / descend".

### 5.2 Five-segment mode pill

Baseline (v5 QA arithmetic): 4 segments ≈ 279 dp + border
(STEERING 77, TILT 48, CONTROLLER 92, ARROWS 62 at padding 9 / font 11 /
spacing 0.8). For v6 the segment padding went 9 → 7, font 11 → 10.5,
letter spacing 0.8 → 0.5 (char ≈ 6.9 dp):

| Segment | Est. width |
|---|---|
| STEERING | ≈ 69 |
| TILT | ≈ 42 |
| CONTROLLER | ≈ 83 |
| ARROWS | ≈ 55 |
| FLY | ≈ 35 |
| **Total** | **≈ 284** |

The 5-segment switch is ≈ the same width as v5's 4-segment switch, so
TopBar Row 1 behaves exactly as in v5 (the status pill is the flexible
element and ellipsises first). All five labels remain fully readable —
none is truncated, since the switch sizes to its content. (Estimates
from the v5 baseline arithmetic; the release build + owner device are
the final proof.)

## 6. Rename verification ("Gaming Remote")

Found already committed before this task ran — commit `b9cca6f`
"v5.0.1: rename app label to Gaming Remote" (manifest label, MaterialApp
title, connect/settings strings, pubspec 5.0.1+3). Re-verified for v5.1:

- `grep "AB GTA" lib/` → **zero matches** (no visible string — and no
  comment — still carries the old name under `lib/`).
- `AndroidManifest.xml`: `android:label="Gaming Remote"` ✓ (committed in
  `b9cca6f`; untouched by v5.1).
- Deliberately unchanged, as before: the Kotlin SDP name/description
  stays "AB GTA" — that is the cached Bluetooth HID record on the
  laptop; changing it risks a re-pair. Package id
  `com.muhammad.gtaremote` unchanged; no class names changed.

## 7. Three-lens review

### User lens (Muhammad, beginner, Roman Urdu speaker)
- FLY is one tap on the top switch while driving; the banner announces
  "✈ FLY — one handle for planes & helicopters"; Settings help explains
  the handle, the pedals, and the absence of HORN/MISSION in one short
  English paragraph (app UI is English-only, as he set in v5).
- The handle matches his own words: one stick, corners do two things at
  once. Arrows drawn on the stick base show the four directions without
  reading anything.
- CHEATS failures now say what actually happened and what to do, instead
  of v5's misleading silence.
- The jetpack case he hit (RACE alone doesn't lift) is covered by the
  DOWN/RACE sub-labels ("speed / climb", "brake / descend") plus the
  help line.

### Tester lens (edge cases traced in code)
- Typer: repeated letters (dedup bypass ✓); abort mid-code (finally →
  reliable empty report ✓); GTA V console path uses the same helper and
  timings ✓; screen's `_busy` guard + service's `isTypingCheat` guard
  both intact ✓; result switch in the screen is exhaustive over the
  3-value enum ✓.
- FLY: stick release, pointer-cancel, and widget dispose all report
  (0, 0) ✓; mode switch mid-hold → `_clearAllKeys` + `_resetFlyStick`
  ✓; opening CHEATS/GUIDE/Settings from FLY follows the same clear-all
  path as other modes ✓; tilt subscription never starts in FLY ✓; PWM
  engine never fed in FLY and is reset on the switch into FLY ✓;
  MISSION pill absent only in FLY ✓; angle readout still STEERING-only
  ✓; stored-mode migration both directions ✓ (§4.3).
- Exhaustiveness: all three `DriveMode` switch expressions in
  `controller_screen.dart` (mode banner, switch banner, layer switch)
  gained `fly` cases — Dart would refuse to compile otherwise; TopBar
  and SteerModeSwitch iterate/pass values without switching ✓.
- No other callers of `typeCheatCode` exist besides the CHEATS screen ✓.

### Expert lens
- The reliability fix is built on the platform's own contract (§2), not
  on timing superstition: sends are awaited, the accept boolean is read,
  retries are bounded (2), and failure is surfaced honestly.
- Wire-compatibility: arrows appended at the end of `hidKeyOrder` →
  byte-identical reports for all pre-existing key sets; the HID
  descriptor/SDP/QOS block is untouched (proof in §8); the snapshot
  architecture (union of per-source sets) is reused, not paralleled —
  FLY adds one source (`'flystick'`) and reuses `race`/`brake`.
- `FlyStick` duplicates ~40 lines of AnalogStick pointer mechanics
  rather than generalising the older widget — deliberate: CONTROLLER
  mode's feel is owner-verified and must not change; a shared refactor
  would risk it for zero user benefit.
- Bounded worst cases: typer retries add ≤ ~160 ms per letter; the
  abort path's final empty report is itself reliable but bounded
  (3 attempts).

## 8. Descriptor proof & change inventory

- Descriptor + SDP + QOS block (`HidKeyboardManager.kt` lines 59–142),
  extracted with the v4/v5 method:
  `sed -n '59,142p' … | md5sum` → **`ba778a379ab87a7f50ec5d2810479153`**
  — identical to v4/v5. **No re-pair needed** (same reasoning as v4/v5:
  descriptor, SDP and QOS all unchanged; the only `android/` difference
  vs v5.0.0 is the manifest label from the already-committed rename).
- `git diff HEAD -- android/` before the v5.1 commit: **empty**.
- Files changed in v5.1: `lib/services/hid_service.dart`,
  `lib/screens/cheats_screen.dart`, `lib/models/game_key.dart`,
  `lib/services/settings_service.dart`, `lib/screens/controller_screen.dart`,
  `lib/widgets/fly_stick.dart` (new), `lib/widgets/steer_mode_switch.dart`,
  `lib/screens/settings_screen.dart`, `mockup/v6-fly-mode.html`
  (rewritten), `pubspec.yaml` (5.1.0+3), `BUILD_NOTES.md`,
  `IMPROVEMENTS_V6.md` (this file). The stale-design
  `mockup/v6-fly-mode.png` is NOT committed — the parent re-renders it
  from the updated HTML.

## 9. Findings & fixes during implementation

1. **Design superseded mid-task:** the brief's TURN/NOSE button clusters
   were replaced by Muhammad's one-handle correction (parent follow-up).
   Implemented the handle; the cluster draft (and its geometry notes)
   was discarded, and this doc traces the handle instead.
2. **CarPedal stacking impossible** (340 > 260) → compact `_FlyPedal`
   pads (§5.1). RACE remains the tall pedal; behaviour identical.
3. **Rename already done:** v5.0.1 (commit `b9cca6f`) had already applied
   "Gaming Remote" before this task started. Verified rather than
   redone (§6) — no duplicate rename diff in v5.1.
4. **Version-code note:** pubspec set to **5.1.0+3** as instructed, but
   version code 3 was already used by 5.0.1+3. Android accepts an
   equal-versionCode install over the same signature (versionName is
   higher), so the APK installs over both v5 and v5.0.1; flagged here
   and in BUILD_NOTES in case a monotonic +4 is preferred later.
5. **`_buildCameraPad` does not bundle EXIT/MAP** (in other modes those
   live in the action cluster) — FLY builds its own camera column with
   the EXIT/MAP row under the pad, reusing the same two clean-press
   button builders, so press behaviour is identical everywhere.
6. **Status-pill squeeze:** adding a 5th segment without shrinking would
   have pushed Row 1 ≈ 50 dp wider than v5's already-full row; the
   minimal shrink in §5.2 keeps the total at the v5 level.

## 10. Not verified here (honest limits)

- No local Flutter/Dart SDK: compile proof is the GitHub Actions release
  build; layout numbers are arithmetic from the codebase's own constants
  (the same method as v4/v5 QA), not screenshots.
- Owner-device checks still decide: cheat typing in all three games
  after the fix; FLY handle feel in a real plane/helicopter (including
  whether the pitch inversion feels right in practice); DOWN pedal in
  the air; five-segment pill readability on the real phone at its real
  width.
