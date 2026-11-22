# IMPROVEMENTS_V7 — v5.3 QA (CRICKET mode for EA Sports Cricket 07)

Three-lens review (gamer / tester / expert) of the v5.3 changes, with
full traces. Written before the build; the GitHub Actions release
build is the compile proof (no local Flutter/Dart SDK), and
Muhammad's device is the final judge for feel.

---

## 1. What changed

**CRICKET mode** — a new `DriveMode.cricket` (sixth segment of the
top-bar switch: STEERING | TILT | CONTROLLER | ARROWS | FLY |
CRICKET). When active it replaces the driving stage with a
Cricket 07 stage (approved mockups `mockup/v7-cricket-mode-4.png`
BATTING + `mockup/v7-cricket-bowling.png` BOWLING):

- **BATTING tab:** full-area swipe = shot (8-way direction from
  the swipe vector, selected shot key, Shift if LOFT is held,
  one 120 ms snapshot); tap (< 40 dp) = no shot (leave the
  ball, exactly like the game). Shot selector FRONT FOOT /
  BACK FOOT / ADVANCE, LOFT hold, RUN, CANCEL, PAUSE, MENU,
  CAMERA ULTA — all small round 76 dp buttons in one cluster.
- **BOWLING tab:** drag = bowling marker (arrow keys held per
  drag vector, 10 dp dead zone); delivery buttons SEEDHI BALL /
  VARIATION 1 / 2 / 3 / SLOWER, plus PAUSE / MENU / CAMERA ULTA.
- No CAMERA pad in this mode — Cricket 07 is keyboard-only, and
  the app's HID mouse has nothing to do there.

Files: `lib/widgets/cricket_gesture_area.dart` (new — both
gesture surfaces), `lib/screens/controller_screen.dart` (state,
feeds, layer, clusters, tab switch), `lib/models/game_key.dart`
(arrowLeft/arrowRight — see §2), `lib/services/settings_service.dart`
(enum value + CAMERA ULTA pref), `lib/widgets/steer_mode_switch.dart`
(segment shrink), `lib/screens/settings_screen.dart` (help),
`pubspec.yaml` (5.3.0+5). **Zero changes under `android/`** (§9).

## 2. Cricket 07 key facts used — and one brief correction

Keys are the game's own documented controls; nothing was
invented: batting **S** front foot, **W** back foot, **D**
advance / take a run, **A** cancel run, **Shift** lofted,
**arrows** shot direction, **Esc** pause, **S** menu select;
bowling **S** stock, **A/D/W** variations, **Shift** slower,
**arrows held** move the marker.

**Correction to the build brief:** it assumed all four arrow
`GameKey`s already existed ("arrows from v5.1"). Only
`arrowUp`/`arrowDown` did (FLY pitch). `arrowLeft` (0x50) and
`arrowRight` (0x4F) were added in `game_key.dart`, **appended at
the very end of `hidKeyOrder`** (after the v5.2 numpad keys), so
every pre-existing key set still produces byte-identical reports
— the same argument as v5.1/v5.2. This is a Dart-only addition of
two standard HID usages; the descriptor is untouched (§9), so
still **no re-pair**.

## 3. Per-button key trace (UI → GameKey → HID usage)

### BATTING tab

| UI control | Path | GameKey | HID usage |
|---|---|---|---|
| Swipe (≥ 40 dp) | `CricketBattingArea.onSwipe` → `_onCricketSwipe` → `_fireCricketShot` (source `cricket_shot`, 120 ms) | sector arrows (table §4) + selected shot key (+ Shift if LOFT held) | arrows 0x4F/0x50/0x51/0x52, shot 0x16/0x1A/0x07, Shift = modifier bit 0x02 |
| Tap (< 40 dp) | same path, distance check | — (nothing sent) | — |
| FRONT FOOT (selector) | `_selectCricketShot` — state only, no key sent | selects **S** for the next swipe | 0x16 when the swipe fires |
| BACK FOOT (selector) | same | selects **W** | 0x1A |
| ADVANCE (selector) | same | selects **D** | 0x07 |
| LOFT (hold) | RoundButton `onHeldChanged` → `_cricketLoftHeld` flag — **no key sent by itself** | **Shift** joins the swipe snapshot only while held | modifier bit 0x02 |
| RUN (tap) | `_momentaryKeyPress('cricket_run', …)` — v3 clean press, 150 ms + 250 ms lockout | **D** | 0x07 |
| CANCEL (tap) | `_momentaryKeyPress('cricket_cancel', …)` | **A** | 0x04 |
| PAUSE (tap) | `_momentaryKeyPress('cricket_pause', …)` | **Esc** | 0x29 |
| MENU (tap) | `_momentaryKeyPress('cricket_menu', …)` | **S** | 0x16 |
| CAMERA ULTA (toggle) | `_toggleCricketCameraFlip` → `SettingsService.setCricketCameraFlip` (persisted) | no key — inverts both swipe axes in `_onCricketSwipe` | — |

### BOWLING tab

| UI control | Path | GameKey | HID usage |
|---|---|---|---|
| Drag on pitch | `CricketBowlingArea.onDragChanged` → `_onCricketMarkerDrag` (source `cricket_marker`) | arrow(s) per drag vector (§5) | 0x4F/0x50/0x51/0x52 |
| Drag end | `onDragEnd` → `_onCricketMarkerEnd` | source cleared | — |
| SEEDHI BALL (tap) | `_momentaryKeyPress('cricket_bowl_stock', …)` | **S** | 0x16 |
| VARIATION 1 (tap) | `_momentaryKeyPress('cricket_bowl_var1', …)` | **A** | 0x04 |
| VARIATION 2 (tap) | `_momentaryKeyPress('cricket_bowl_var2', …)` | **D** | 0x07 |
| VARIATION 3 (tap) | `_momentaryKeyPress('cricket_bowl_var3', …)` | **W** | 0x1A |
| SLOWER (tap) | `_momentaryKeyPress('cricket_bowl_slower', …)` | **Shift alone** (snapshot with only the modifier bit, 150 ms) | modifier bit 0x02 |
| PAUSE / MENU / CAMERA ULTA | same as batting tab | Esc / S / toggle | 0x29 / 0x16 / — |

> **Variation labels are generic on purpose.** Which delivery
> each variation key (A/D/W, Shift) actually produces depends on
> the bowler (a fast bowler's swing/cutter set is not a spinner's)
> and the game itself shows the delivery name on screen. Printing
> a fixed name on the button would be wrong for half the bowlers,
> so the buttons carry the number + the real key letter only.
> (Same note lives above `_bowlingClusterRows` in code.)

Worst-case report size: a lofted diagonal swipe = 2 arrows +
1 shot key = 3 keycodes + modifier — well under the 6-key cap.

## 4. The 8-way swipe sector table

Sector = `round(atan2(dy, dx) / 45°)` in screen coordinates
(0° = right, 90° = down), normalised to 0–7. **The arrow combo
equals the swipe's screen direction** (broadcast camera, the
game's default view). CAMERA ULTA negates the vector first
(= sector + 4).

| Swipe | Sector | Arrows sent | Shot (game's name for it) |
|---|---|---|---|
| → | 0 | {arrowRight} | leg side |
| ↘ | 1 | {arrowDown, arrowRight} | on-drive |
| ↓ | 2 | {arrowDown} | straight (SEEDHA) |
| ↙ | 3 | {arrowDown, arrowLeft} | cover |
| ← | 4 | {arrowLeft} | point |
| ↖ | 5 | {arrowUp, arrowLeft} | third man |
| ↑ | 6 | {arrowUp} | behind (PEECHE) |
| ↗ | 7 | {arrowUp, arrowRight} | fine leg |

The gesture area's painted labels sit at exactly these edges, so
the picture on the phone and the table above cannot drift apart.

## 5. Bowling marker trace

- Drag vector is measured from the **drag anchor** (where the
  finger landed), not from the pitch centre — the player can
  start the drag anywhere on the pitch area.
- Per axis, dead zone 10 dp: dx ≤ −10 → arrowLeft, dx ≥ +10 →
  arrowRight; dy likewise for arrowUp/arrowDown. Both axes are
  evaluated independently, so a diagonal drag holds two arrows
  in one snapshot — the game's marker moves diagonally, exactly
  like holding two arrow keys on a real keyboard.
- The held set is recomputed on **every** move event; crossing
  back inside the dead zone releases that axis immediately.
- Pointer up/cancel → source cleared. Widget dispose mid-drag
  also calls `onDragEnd` (and every clear-all clears the source
  anyway — two independent safeties).
- The on-screen marker dot is **visual only** (follows the
  finger, rests at good length when idle). The game's own marker
  is the one that matters; the dot just shows the drag is alive.
- CAMERA ULTA does **not** apply here (brief: batting swipes
  only) — the toggle stays visible on this tab because the state
  is shared, and flipping it here takes effect on the next
  batting swipe.

## 6. Layout budget — 640×360 and the 6-segment pill

### Cricket stage (from the top of the screen)

| Element | Geometry | Check |
|---|---|---|
| Top bar | Row 1 ≈ 40 + Row 2 (CHEATS/GUIDE) 32 → ends ≈ y 78 | stage starts top 84 (FLY's clearance) ✓ |
| Gesture column | left 16 (flip: right 16), right offset 293 → **width 331** | **≥ 330 required ✓** |
| Tabs row | ≈ 29 tall + 8 gap, inside the gesture column | — |
| Gesture surface | top 84 + 37 → bottom 72: height ≈ 167 at 360 | a 40 dp swipe fits easily ✓ |
| Divider | x = 359 (flip: mirrored), 1 dp, gaps 12 both sides | ✓ |
| Button cluster | x 372…624 (width **252** = 3 × 76 + 2 × 12), top 84…bottom 16 (260) for **252** of buttons (3 × 76 + 2 × 12) | fits with 4 dp slack top/bottom ✓ |
| Ghost buttons (Settings/Disconnect) | centre, x ≈ 266…374, y ≈ 300…348 | gesture surface ends at y = 288 (bottom 72) ✓; cluster starts x = 372, ghost *visual* ends x = 371 ✓ no overlap |
| MISSION pill | suppressed in CRICKET (and FLY) | ✓ |
| Short screens (< 360 tall) | `clusterScale` 0.86 → cluster ≈ 217 tall in a ≈ 220 stage | ✓ (same mechanism as all modes) |
| Wider screens | cluster fixed 252; gesture column absorbs all extra width | ✓ |

**Deviation forced by geometry:** the mockups show a "BUTTONS" /
"DELIVERY BUTTONS" caption above the grid. The grid alone is
252 dp tall in a 260 dp stage — there is no room for a caption
line at 640×360, so the caption is dropped in the app (the mockup
frame was 520 tall). Everything else follows the mockups.

### Six-segment mode pill

Segment style shrunk again (padding 7 → 5, font 10.5 → 10,
spacing 0.5 → 0.3; char ≈ 6.1 dp):

| Segment | Est. width |
|---|---|
| STEERING | ≈ 59 |
| TILT | ≈ 34 |
| CONTROLLER | ≈ 71 |
| ARROWS | ≈ 47 |
| FLY | ≈ 28 |
| CRICKET | ≈ 53 |
| **Total** | **≈ 292 + border ≈ 294** |

Row 1 at 640 dp: 294 (switch) + ≈ 208 (mode pill) + 24 (gaps) =
526 ≤ 608 available — no overflow; the status pill is the
Flexible element and ellipsises first (the v5 behaviour, slightly
more pronounced). All six labels stay fully readable. On the
owner's real phone (much wider than 640 dp) the status text fits
in full.

## 7. Edge cases traced in code

- **Swipe during a LOFT hold:** LOFT is a `RoundButton` with its
  own raw-pointer capture; the swipe area is a separate
  `Listener` tracking a different pointer id. One finger holds
  LOFT, another swipes — the flag is read at fire time, so the
  snapshot carries Shift. Releasing LOFT *during* the 120 ms
  window does not alter the in-flight snapshot (the set was
  already committed to the source). ✓
- **LOFT held with no swipe:** nothing is sent — faithful to
  the game (Shift alone does nothing). ✓
- **Tab switch mid-hold / mid-drag:** `_switchCricketTab` runs
  `_clearAllKeys()` first (sources cleared, shot timer
  cancelled, generation bumped, LOFT flag reset, shot selection
  back to FRONT FOOT), then swaps the tab. The outgoing gesture
  widget's dispose is a second safety (bowling area calls
  `onDragEnd`; RoundButton dispose releases its hold). ✓
- **Disconnect mid-swipe:** a shot only fires on pointer *up*;
  if the link drops mid-gesture, the HID state listener runs
  `_clearAllKeys()` and the eventual `_fireCricketShot` snapshot
  goes to a dead link as a no-op send (the service's own state
  was reset by the disconnect event). No key can stick: the
  120 ms timer still clears the source, and the service sends
  the clean state on reconnect (FR-28). ✓
- **Mode exit mid-drag (bowling):** mode switch → clear-all
  clears `cricket_marker`; the widget dispose also fires
  `onDragEnd`. The controller feed is mode-guarded
  (`_driveMode != DriveMode.cricket` returns early), so a late
  move event after the switch is a no-op. ✓
- **Second swipe inside the 120 ms window:** the new set
  replaces the old in the same source and the timer restarts
  (generation guard) — a quick second shot is never eaten by a
  lockout, and the first timer cannot cut the second shot. ✓
- **Shot selector tapped mid-window:** changes only the *next*
  swipe's key; the in-flight snapshot is untouched. ✓
- **RUN (D) vs ADVANCE (D):** same physical key, two buttons —
  that is the game's own design (D advances before the shot and
  runs after it). The lockout ids differ (`cricket_run` vs the
  selector, which sends nothing), so they cannot block each
  other. ✓
- **CAMERA ULTA toggle:** goes through `SettingsService`, whose
  change notification runs the controller's standard
  clear-all + rebuild — no key can survive the flip, and the
  toggle's lit state re-reads the persisted value. ✓
- **Stored-mode migration:** `DriveMode.cricket` is appended to
  the enum; `byName` still falls back to STEERING for unknown
  names, so v5.2 stored values parse unchanged, and a downgrade
  with `cricket` stored degrades to STEERING, not a crash. ✓
- **Exhaustiveness:** all three `DriveMode` switch expressions
  (mode banner, switch banner, layer switch) gained `cricket`
  cases — Dart would refuse to compile otherwise. ✓

## 8. Three-lens review

### Gamer lens (Muhammad, playing Cricket 07 on the laptop)
- One tap on the top switch → CRICKET; the banner announces
  "🏏 CRICKET — swipe to bat, drag to bowl". BATTING is the
  default tab, FRONT FOOT the default shot — a first-time user
  can play a shot with zero setup: wait for the ball, swipe
  towards cover.
- The swipe is the whole left side of the phone, not a small
  pad — like the mobile cricket games he knows, but the buttons
  are Cricket 07's own (he corrected two earlier mockups on
  exactly this point; the final layout is his: buttons on one
  side, small and round, swipe on the other).
- Leaving a ball needs no button: just don't swipe. The hint
  line on the field says so.
- CAMERA ULTA is on the stage itself (both tabs) — if he flips
  the in-game camera, one tap fixes the remote, no Settings
  trip.

### Tester lens
- Every button traced to a key in §3; every sector in §4;
  marker axes in §5. Report-size worst case 3 keycodes +
  modifier ≤ 6 cap. ✓
- All release paths converge on `_clearAllKeys()` →
  `_resetCricketState()` (shot timer, generation, LOFT flag,
  shot default) + source clearing + `releaseAllKeys()`. ✓
- The two gesture widgets own **no** key state; killing them
  mid-gesture cannot strand a key (batting fires only on
  pointer-up; bowling's keys live in a controller source that
  clear-all owns). ✓
- Flip controls: mirrored by swapping the Positioned offsets
  only (cluster ↔ gesture) — the gesture logic is untouched,
  and the swipe→arrow mapping does **not** mirror (screen
  directions stay screen directions; CAMERA ULTA is the
  separate, deliberate inversion). ✓

### Expert lens
- The mode reuses the app's three load-bearing patterns
  verbatim: per-source key union (one new source per gesture:
  `cricket_shot`, `cricket_marker`), the v3 clean-press helper
  for every tap button (no new press machinery), and
  clear-all-on-every-transition. The only new timer is the
  shot window, generation-guarded like the momentary helper.
- The shot is a *snapshot*, not a sequence of sends — one
  report carries direction + shot + Shift together, which is
  exactly how a real keyboard chord reaches the game; there is
  no inter-key timing to go wrong (the cheat-typer lesson).
- Wire compatibility is argued, not assumed: two usages
  appended at the end of `hidKeyOrder`; descriptor/SDP/QOS
  untouched (§9). All other modes emit byte-identical reports
  to v5.2.
- `CricketBattingArea`/`CricketBowlingArea` duplicate the
  field decoration (one shared `BoxDecoration` + `_PitchStrip`)
  instead of a class hierarchy — two small widgets, no
  abstraction debt, same call as FlyStick vs AnalogStick in v5.1.

## 9. Descriptor proof & change inventory

- Descriptor + SDP + QOS block (`HidKeyboardManager.kt` lines
  59–142), same extraction as v4–v5.2:
  `sed -n '59,142p' … | md5sum` → **`ba778a379ab87a7f50ec5d2810479153`**
  — identical to v4/v5/v5.1/v5.2. **No re-pair needed.**
- `git diff HEAD -- android/` before the v5.3 commit: **empty**.
- Files changed in v5.3: `lib/models/game_key.dart`,
  `lib/services/settings_service.dart`,
  `lib/widgets/steer_mode_switch.dart`,
  `lib/widgets/cricket_gesture_area.dart` (new),
  `lib/screens/controller_screen.dart`,
  `lib/screens/settings_screen.dart`, `pubspec.yaml`
  (5.3.0+5), `mockup/v7-cricket-mode-4.html/png`,
  `mockup/v7-cricket-bowling.html/png`, `BUILD_NOTES.md`,
  `IMPROVEMENTS_V7.md` (this file).

## 10. Decisions made where the brief left room

1. **arrowLeft/arrowRight added** (§2) — the brief's premise
   that all arrows existed was wrong for Left/Right; appended
   at the end of `hidKeyOrder`, byte-identity preserved.
2. **Cluster captions dropped** (§6) — geometry, not taste.
3. **Flip mirroring implemented** (brief: do it if cheap) —
   it was: the layer is three `Positioned`s whose left/right
   values swap. Noted in §8.
4. **Shot selection resets on every clear-all** (entering the
   mode, tab switches, Settings trips, disconnects) — the
   brief's "reset transient cricket state" applied uniformly;
   FRONT FOOT is always the predictable starting shot.
   CAMERA ULTA is *not* reset — it is a persisted preference.
5. **Shot window is its own 120 ms timer**, not the 150 ms
   clean-press helper: the helper takes a single key and has a
   250 ms lockout; a shot is a *set* of keys and the next ball
   may need an immediate second shot. The generation-guard
   pattern is shared; the lockout is deliberately absent.
6. **MENU/PAUSE/RUN/CANCEL/deliveries use the existing helper**
   with cricket-specific lockout ids, so a cricket PAUSE can
   never be eaten by a driving MAP tap's lockout or vice versa.

## 11. Not verified here (honest limits)

- No local Flutter/Dart SDK: compile proof is the GitHub
  Actions release build; layout numbers are arithmetic from
  the codebase's own constants (the same method as v4–v6 QA),
  not screenshots.
- Owner-device checks still decide: swipe timing feel against
  real bowling speeds in Cricket 07; whether 120 ms is the
  right shot window for the game's input polling; marker drag
  speed (one drag = one hold — long drags move the marker
  further, like a real keyboard); CAMERA ULTA against the
  in-game flipped camera; six-segment pill readability on the
  real phone.
