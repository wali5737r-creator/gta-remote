# AB GTA v5 — Improvements & QA Review

Scope (approved by Muhammad, premium mockup `mockup/v5-cheats-premium.png`):
**CHEATS screen** (3 game tabs, tap a card and the remote types the
code), **MISSIONS GUIDE screen**, **HORN** in all four driving modes,
**MISSION** button (vehicle side-missions), **TAB** button (on foot).
Version 5.0.0+2 (was 1.0.0+1 through v1–v4).

**Everything in v5 is Dart.** Nothing under `android/` changed — see
the descriptor proof at the end. **No re-pair needed.**

---

## What was built

### Cheat typer — `HidService.typeCheatCode` (lib/services/hid_service.dart)

- Refuses to run when not connected or when a code is already being
  typed (`isTypingCheat` flag, exposed for the UI).
- `releaseAllKeys()` first, so a held key (e.g. RACE) can never bleed
  into the typed word.
- Raw `sendReport` calls bypass the `_lastSentSignature` dedup —
  repeated letters (the two O's in BOOOOOORING, the double letters in
  FULLCLIP) are real separate presses, never merged.
- Per letter: report `[keycode]` for 55 ms, empty report, 40 ms gap
  (≈10.5 chars/s — fast human typing; slow enough for the games'
  per-frame keyboard polling, fast enough for SA's cheat window).
- GTA 5 (`useConsole: true`): grave key (0x35) down 60 ms → empty →
  300 ms console-open wait → letters → Enter (0x28) down 60 ms →
  empty.
- Every letter iteration re-checks the connection; a drop mid-type
  aborts the rest (a half-typed word does nothing in the games —
  cheats only fire on the complete word).
- `finally`: flag cleared, `_lastSentSignature` reset, current
  (empty) snapshot re-sent; on an aborted run one extra raw empty
  report guarantees no letter can stay down on the PC.

### CHEATS screen (lib/screens/cheats_screen.dart + lib/data/cheats.dart)

- Premium design per the approved mockup: dark blue-grey gradient,
  soft glow in the active game's colour, "★ CHEATS" header +
  subtitle + round ✕, three tabs (SAN ANDREAS orange #F7931E,
  VICE CITY pink #FF71CE, GTA 5 green #9CCC4F) — active tab glows,
  inactive tabs keep their game colour as text, exactly like the
  mockup. Category headers with accent bar + fading rule; cards
  show CODE (bold) + hint, in a 3-column grid; the whole list
  scrolls.
- Tab sublabels show the **real** counts from the data file —
  SA 36, VC 32, GTA 5 27 (the mockup's 42/38/34 were illustrative).
- While typing: all cards disabled (dimmed), the typing card gets
  the accent border + glow, status line shows "Typing HESOYAM…"
  with a spinner; success → "Sent — check your game" (green);
  not connected → "Not connected — connect to your laptop first.";
  mid-type drop → "Connection lost — the code was not fully
  typed."
- A 400 ms sync timer mirrors `hid.isTypingCheat` so re-entering
  the screen mid-type can never show live buttons over a busy
  typer (and the typer itself refuses a second code regardless).
- Footer notes: VC — "Classic PC codes. Most also work in the
  Definitive Edition; a few may not." GTA 5 — "The remote opens
  the console, types the code and presses Enter for you. Cheats
  pause achievements until you reload your save." (SA has no
  footer, as specified.)

### GUIDE screen (lib/screens/guide_screen.dart)

PremiumBackground + the app's card style; numbered "ALL GAMES —
HOW MISSIONS WORK" card (radar letter → go there → glowing marker
→ follow the radar marker), then SA (orange), VC (pink) and GTA 5
(green) sections with the approved content, including the MISSION
button's role for vehicle missions. The remote cannot see inside
the game — the guide teaches the (always identical) steps instead
of pretending to find missions automatically.

### New keys + profiles

- `GameKey`: `h` (0x0B), `e` (0x08), `tab` (0x2B), `capsLock`
  (0x39) — appended into `hidKeyOrder` after `c`. For any key set
  that does not contain a new key, the emitted keycode list is
  byte-identical to v4 (the order loop skips absent keys).
- `GameProfile.hornKey`: GTA V → E; SA Original → H; SA
  Definitive → H. `submissionKey`: GTA V → E; SA (both) →
  CapsLock.

### Layout integration

- **TopBar Row 2 (CHEATS / GUIDE pills).** Deviation from the
  literal spec, same reasoning as v4's HORN omission: Row 1 is
  provably full at 640 dp while driving (status pill min ~54 +
  4-segment switch ~305 + mode pill ~230 + gaps ≈ 613 > 608
  usable), so the pills live in a second row (26 dp) aligned to
  the **action-cluster side** (right, or left when flipped) —
  the side whose controls start lower (82 dp) — and the bar's
  top moved 8 → 6 to pay for it. Cluster-side clearance below
  Row 2 ≈ 2–6 dp painted at exactly 360 dp height, no overlap,
  no shared touch area; more at taller heights. On the
  steering-control side Row 2 would have collided with the
  on-foot weapon row (top 64).
- **MISSION pill** (108×32, `_PillButton`, blue) — in the
  controller's main Stack (not inside a mode layer, so it can
  never drift between modes): `top: 82`, margin 32 on the
  **steering-control side** (follows Flip controls), driving
  only. Tap → `_momentaryKeyPress('mission', submissionKey)` —
  the v3 clean-press helper (150 ms + 250 ms lockout +
  generation guard).
- **TAB pill** (72×48, `_PillButton`) — appended to the on-foot
  weapon-switch row after a 12 dp gap (same height as the WPN
  buttons, same row, joystick side). Tap →
  `_momentaryKeyPress('tab', GameKey.tab)`.
- **HORN**:
  - STEERING — the wheel **hub** (painted radius = size × 0.185):
    a pointer starting inside the hub becomes a horn hold
    (separate `_hornPointer`, never claims steering; steering
    and horn work simultaneously with two fingers). A
    non-rotating "HORN" label sits over the hub centre and
    lights up while held. The wheel's 24 dp centre-ignore meant
    hub touches never steered anyway, so steering feel is
    unchanged. Dispose while held fires `false` — horn can't
    stick.
  - TILT — no wheel exists, so a round HORN button (58) above
    the BRAKE pedal: `bottom: 176`, brake-side margin 53
    (12 dp above the pedal's top edge, 12 dp below Row 2).
  - CONTROLLER — round HORN button (58) in a new bottom row of
    the cluster column, centred under the action row (column
    188 → 258 dp tall; top edge 86 dp at 360 dp height).
  - ARROWS — round HORN button (50) above the arrows pair:
    `top: 126`, steering-side margin 97 (12 dp below the
    MISSION pill, 12 dp above the pair).
  - All horn controls feed source `'horn'` with
    `profile.hornKey` — the union design means horn composes
    with any held key and clears on every safety path.
- Opening CHEATS or GUIDE mirrors `_openSettings` exactly:
  `setState(_clearAllKeys())`, `_stopTilt()`, push, then
  `_applyLandscape()` + `_updateTiltSubscription()` on return.
  No key can stay held while browsing.
- Settings help gained three lines teaching TAB, CHEATS/GUIDE,
  HORN and MISSION (the codebase convention since v3).

---

## Per-button traces (every NEW control)

### HORN — STEERING mode
Finger lands within hub radius → `SteeringWheel._handlePointerDown`
claims it as `_hornPointer` (steering pointer untouched) →
`onHornHeldChanged(true)` → `_setSourceKeys('horn', {H})` (SA
profile) → union → HID report `[…, 0x0B, …]` → horn sounds.
Finger lifts → `_handlePointerUp` horn branch → callback(false) →
source cleared → report without 0x0B → horn stops. Wheel rotated
with the other hand the whole time: unaffected (separate pointer,
separate source 'pwm').

### HORN — TILT mode
RoundButton down → `onHeldChanged(true)` → source 'horn' {H} →
horn. Up/cancel/dispose → RoundButton's own dispose-release →
source cleared. (Tilt steering is the 'tilt'→'pwm' path; horn
never touches it.)

### HORN — CONTROLLER mode
Same RoundButton path as TILT, source 'horn' {E} on the GTA V
profile. Held together with RACE trigger: union {W, E} — both
work (in GTA V, E while driving is the horn; the game decides).

### HORN — ARROWS mode
Same RoundButton path (diameter 50). Held together with ▶:
union {D, H} — steering continues while the horn sounds.

### MISSION (all driving modes)
Tap → `_PillButton` fires on pointer-down →
`_momentaryKeyPress('mission', capsLock)` (SA) → lockout set,
source 'tap_mission' {CapsLock} → report keycodes […, 0x39] for
150 ms → generation-checked release → SA toggles submission
mode (taxi/vigilante/ambulance) — a second tap 250 ms+ later
toggles it off, exactly like a real keyboard's Caps Lock (the
host's Caps Lock state toggles too — inherent to the key, same
as any physical keyboard). GTA V profile: key is E — tap =
150 ms E press (interact/submission).

### TAB (on foot)
Tap → `_momentaryKeyPress('tab', GameKey.tab)` → source
'tap_tab' {0x2B} for 150 ms → release. In SA this answers the
game's "Press TAB to buy the property" prompt and opens the
stats screen — the two moments Muhammad personally hit in v4
testing.

### CHEATS — sample trace, SA "HESOYAM" (useConsole: false)
Tap card → connected check passes → status "Typing HESOYAM…",
cards disabled → `typeCheatCode('HESOYAM', useConsole: false)` →
`releaseAllKeys()` → raw reports: [0x0B] 55 ms → [] 40 ms →
[0x08] (E) → [] → [0x16] (S) → [] → [0x12] (O) → [] → [0x1C] (Y)
→ [] → [0x04] (A) → [] → [0x10] (M) → [] → finally: signature
reset + empty snapshot → status "Sent — check your game". Total
≈ 0.67 s. In SA the word registers as typed on a real keyboard
(DirectInput scancodes — layout-independent).

### CHEATS — sample trace, GTA 5 "TURTLE" (useConsole: true)
Tap card → `typeCheatCode('TURTLE', useConsole: true)` →
`releaseAllKeys()` → [0x35] (grave) 60 ms → [] → 300 ms wait
(console opens) → T-U-R-T-L-E at 55/40 ms → [0x28] (Enter)
60 ms → [] → finally reset → "Sent — check your game". Total
≈ 1.4 s. Footer on this tab warns about achievements pausing.

### CHEATS — VC tab
Same direct-typing path as SA (no console). Sample: "PANZER" →
[0x13] [0x04] [0x11] [0x1D] [0x08] [0x15] with 55/40 ms spacing.
Tab also carries the Definitive-Edition footer note.

### CHEATS / GUIDE pills (TopBar Row 2)
Tap → `_openCheats()` / `_openGuide()` → all keys cleared, tilt
stopped → screen pushes → browse → ✕ back → landscape re-applied,
tilt subscription refreshed. No report is sent by the navigation
itself beyond the clear-all empty snapshot.

---

## Layout budgets at 640×360 (all verified ≥ v4 pad widths)

Camera pad widths — **unchanged in every layout** (the pad code
and side insets were not touched): STEERING 142, TILT 261,
CONTROLLER 210, ARROWS 170, ON FOOT 136.

| New element | Space taken | Clearances |
|---|---|---|
| TopBar Row 2 (CHEATS 84 + 8 + GUIDE 68 = 160×26) | cluster side, y 48–74 | cluster top (82) ≈ 8 below; pad top corners start x ≤ 404 / ≥ 236 — no x-overlap with the pills (464–624 / 16–176) |
| MISSION pill 108×32 @ top 82, margin 32 (steering side) | y 82–114 | wheel painted top ≈ 128 (STEERING, 14 clear); arrows pair top 188; stick top ≈ 196; TILT brake top 196; banner is transient + centred (x ≈ 220–420), no overlap |
| TAB pill 72×48 in weapon row | row x 44–232 (non-flip) | pad left edge 246 → 14 gap; flip: row 408–596, pad right edge 382 → 26 gap |
| HORN hub (STEERING) | inside existing wheel | zero new space |
| HORN 58 (TILT) @ bottom 176, margin 53 | y 126–184, brake side | 12 below MISSION (114, same side), 12 above BRAKE top (196) |
| HORN 58 (CONTROLLER) | cluster column 188→258 tall | top edge 86 at 360 h; stick unchanged; pad unchanged |
| HORN 50 (ARROWS) @ top 126, margin 97 | y 126–176, x 97–147 | 12 below MISSION (114), 12 above arrows pair (188) |

At heights > 360 every vertical clearance grows (wheel/pedal
positions are bottom-anchored; the top-anchored additions stay).
At heights < 360 the existing `clusterScale` 0.86 shrink applies
to clusters as before; MISSION/TAB/horn positions are
top-anchored and unaffected.

Row 1 width at 640 (driving, unchanged): status (flexible,
ellipsises) + 12 + switch + 12 + mode pill — fits because the
status pill is the flexible element, as in v4.

---

## Three-lens review

### User lens (Muhammad, beginner, plays SA Original mostly)
- ✅ One tap per cheat, hint under every code in plain English —
  no code list to memorise, no laptop keyboard needed.
- ✅ HORN is where a player expects it: middle of the wheel.
  TILT players get a real button (there is no wheel to tap).
- ✅ MISSION + GUIDE answer his actual 2026-11-20/22 questions
  ("mission kaise start hota hai", "Press TAB to buy").
- ✅ Nothing he knows moved: every v1–v4 control is in its exact
  place; CHEATS/GUIDE are additions in a new row.
- ⚠️ Cheat typing needs the game in the world, not in a menu —
  taught in Settings help ("Stand in the game world first").
- ⚠️ SA's submission key is Caps Lock: the laptop's Caps Lock
  light will toggle too. That is what a real keyboard does;
  noted here so it isn't mistaken for a bug.

### Tester lens
- ✅ Double-tap a cheat card: second tap lands while `_busy` —
  ignored; the typer's own re-entry guard is a second lock.
- ✅ Disconnect mid-type: per-letter check aborts; finally-block
  sends an extra raw empty report; status shows the honest
  "not fully typed" message. A half word does nothing in-game.
- ✅ Repeated letters (BOOOOOORING ×6 O's, GETTHEREVERYFASTINDEED):
  raw sends bypass dedup — every letter is a full down/up.
- ✅ Hold HORN + steer + RACE simultaneously: three independent
  sources/pointers; union report carries all; releasing any one
  removes only its key.
- ✅ HORN (GTA V profile) and MISSION both use E: union semantics
  — MISSION's 150 ms release removes only its own source; a held
  horn keeps E down. Correct.
- ✅ Open CHEATS while RACE held by a second finger: clear-all
  fires first (the `_openSettings` path) — nothing sticks.
- ✅ Flip controls: Row 2, MISSION, TILT horn and ARROWS horn all
  follow the flip; arrows themselves never mirror (v4 rule kept).
- ⚠️ **Keyboard-layout caveat (GTA 5 console):** the typer sends
  US HID keycodes. SA/VC read DirectInput scancodes (position =
  letter, layout-independent). GTA V's console reads Windows
  text input — if the laptop's Windows input language were
  Hungarian (QWERTZ, Y/Z swapped), console letters Y/Z would
  swap. Muhammad's Windows UI is English; if a GTA 5 code ever
  "does nothing", switch the Windows input language to ENG and
  retry. Not fixable in the remote without knowing the layout.
- ⚠️ GTA 5 console timing (300 ms open wait, 60 ms Enter) is
  generous for a local machine but — like all v1–v4 in-game
  behaviour — only device-verifiable by the owner.

### Expert lens
- ✅ Zero Kotlin/`android/` changes; descriptor proof below.
  The typer is pure Dart over the existing `sendReport` channel
  (modifier 0, single keycode) — the keyboard report format is
  untouched, so Windows sees ordinary typing.
- ✅ New enum keycodes sit after `c` in `hidKeyOrder`; every
  pre-existing key set emits byte-identical reports to v4.
- ✅ Typer state hygiene: flag + signature reset + snapshot
  re-send in `finally`; abort path adds a belt-and-braces raw
  empty report (same philosophy as the v3 zero-report backstop).
- ✅ No new dependencies, no new permissions, no network.
  `pubspec` change is the version only: **5.0.0+2**.
- ✅ English UI: every new user-facing string is English
  (grep sweep over the new screens/data: zero Roman Urdu hits;
  code comments follow the codebase convention, as in v4).
- ℹ️ Deviations from the literal spec text, all forced by the
  640×360 geometry and documented above: TopBar pills in a
  second row (Row 1 is full); TILT horn as a button above BRAKE
  (TILT has no wheel hub); ARROWS horn above the pair instead of
  inside the pedal cluster (the cluster side has no free slot
  that keeps the pad at 170); real cheat counts on the tabs
  (36/32/27) instead of the mockup's illustrative 42/38/34.

### Findings fixed before commit
1. **Guide screen referenced a non-existent `PremiumBackground.base`**
   — caught in self-review; Scaffold background now uses the
   gradient's mid colour (0xFF0B0E13). Would have failed compile.
2. **Cheats screen sync timer rebuilt the whole screen every
   400 ms** — now rebuilds only when `isTypingCheat` actually
   changes.
3. **Steering-wheel hub touch vs steering claim ordering** — the
   horn check runs before the steering claim and before the
   spring-stop, so a hub tap during spring-return still horns
   and never disturbs the wheel angle.

---

## Descriptor-unchanged proof (v4 method)

- `git diff HEAD -- android/` → **empty**. Zero files changed
  under `android/` (also zero changes to `MainActivity.kt`, the
  manifest, and gradle files).
- Descriptor + SDP + QOS block extracted from
  `HidKeyboardManager.kt` (lines 59–142, `REPORT_DESCRIPTOR`
  through `QOS_SETTINGS`):
  - v5 tree: md5 `ba778a379ab87a7f50ec5d2810479153`
  - v4 (HEAD): md5 `ba778a379ab87a7f50ec5d2810479153`
  - **Identical → the v3 pairing stays valid; NO re-pair.**

## Not verified (no device / no local Flutter SDK)

- `flutter analyze` / tests: no Flutter/Dart SDK on this machine
  (same as v1–v4) — the GitHub Actions release build is the first
  compile proof; there is no `test/` directory in the repo.
- In-game behaviour of the typer (SA/VC/GTA 5), horn feel in all
  modes, and the GTA 5 console sequence are owner's-device
  checks, listed for Muhammad in the delivery note.
