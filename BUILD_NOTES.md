# GTA Remote — Build Notes

**Date:** 2026-11-19
**Built to:** `docs/SRS.md` (FR-1…FR-34, NFR-1…NFR-9) + `docs/research.md`, with
Muhammad's later design revisions applied (see Deviations).
**Status:** Code complete. **Not compiled and not device-tested yet** — this
machine has no Flutter/Android SDK; the first compile is the GitHub Actions
build, and the first pairing doubles as the SRS §9.1 HID gate test.

---

## What was implemented

A Flutter Android app that registers the phone as a **Bluetooth HID keyboard**
(Android `BluetoothHidDevice`, API 28+) via a hand-written Kotlin platform
channel. Windows pairs with the phone using its built-in HID driver — **no
software on the laptop, no internet, no WiFi**. Every key-state change sends
one 8-byte boot-keyboard report (modifier byte + up to 6 keycodes) — a state
snapshot, so a key can never stay stuck.

### Highlights per SRS area

- **Connection (FR-1…FR-7):** game profile selected before connecting and
  remembered; plain-language permission explanation *before* the system
  dialog; HID registration state always read from real callbacks, never
  assumed; bonded-device list (no scanning UI); register → connect sequence
  with live progress text (`Register ho raha hai… → Connect ho raha hai…`);
  first-time pairing guide with numbered steps + "make discoverable" button;
  one-tap Reconnect after a drop; plain-language errors (including the
  "another remote app holds the registration" case).
- **Driving (FR-8…FR-14):** touch steering wheel with **delta-angle**
  tracking (grab anywhere, never snaps), ±90° default range (±135° in
  Settings), 7° default dead zone, ~200 ms ease-out spring return to centre,
  fixed ▲ bezel marker; RACE and BRAKE hold-pedals with per-finger touch
  capture (sliding off does not release); HANDBRAKE hold button; all inputs
  combine into one report (per-control key "sources" are unioned).
- **On foot (FR-15…FR-18):** fixed-base 8-way WASD joystick in the wheel's
  position (~13 dp radial dead zone, knob travel clamped, smooth return);
  RUN is a **toggle** (lit + `RUNNING`); JUMP is momentary; labels and keys
  follow the game profile.
- **Mode switching (FR-19…FR-22):** ENTER/EXIT button sends an F tap
  (~130 ms) and swaps the layout; the mode pill in the top bar switches
  **layout only, sends no key** (desync recovery); every switch clears all
  keys first, resets RUN, shows a ~650 ms `🚗 DRIVING` / `🚶 ON FOOT` banner
  and fires a haptic double-tick.
- **Settings (FR-23…FR-27):** steering range ±90°/±135°, dead-zone slider
  0–15°, sensitivity Low/Medium/High (0.7×/1.0×/1.4×), flip-controls switch,
  default game profile, plain-language help notes. Everything persists
  (profile, settings, last laptop). Changing a setting mid-session first
  releases all keys.
- **Safety (FR-28…FR-34):** all keys release on disconnect, app
  background/pause (both Dart lifecycle *and* native `onPause` → zero report;
  registration intentionally survives pause since v1.1 — see QA_REPORT.md),
  leaving the controller, and mode switch; on reconnect the
  first report is the clean state; disconnected = blocking overlay with
  Reconnect; controller is landscape + immersive + wake-locked while
  connected; Android Back asks "Disconnect karun?" before leaving; every
  press has visual + haptic feedback; every control is icon + word + key
  sub-text with the SRS colour code.

### Game profiles (Muhammad's final change — ALL GTA versions)

| Profile | RUN (sprint) | JUMP |
|---|---|---|
| GTA V | Left Shift | Space |
| GTA San Andreas — Original | Space | Left Shift |
| GTA San Andreas — Definitive | Space | Space |

Driving keys (W/A/S/D, F, Space handbrake) are identical in all three.
Button labels always follow the selected profile.

---

## Muhammad's design revision (acknowledged — overrides SRS wireframes)

Applied on top of the SRS, per Muhammad's mockup feedback (2026-11-19):

1. **Pedal order swapped:** RACE is FIRST (left), BRAKE after it (right).
2. **ENTER/EXIT CAR moved out of the top bar:** it is a round glossy button
   **above the pedal cluster, next to HANDBRAKE**; in On-Foot mode it sits in
   the **exact same position** (an invisible spacer keeps its place where
   HANDBRAKE would be). Top bar keeps only the connection status pill (left)
   and the mode pill (right).
3. **Realistic styling:** pedals look like real car pedals (metal arm +
   rubber grip-ridge pads; accelerator tall/narrow, brake wider/shorter;
   subtle green/red coding kept); the wheel looks like a real car wheel
   (thick leather rim with stitching, metal spokes, large centre hub with
   teal horn ring).
4. **Premium direction:** rich dark theme with ambient glows and glassy
   panels, brushed-metal/rubber pedals, glossy round buttons, wide
   letter-spaced labels, smooth 60 fps animations (spring return, pedal
   press, ~250 ms mode cross-fade) — matched to `mockup/design.html`.
5. **No caption/instruction text under the steering wheel** (the small
   centre-screen steering-angle readout from SRS §7.2 is kept — it is not a
   caption under the wheel).

### Other deviations from the SRS text, and why

- **Three profiles instead of two** — Muhammad's explicit final change
  (SRS §3.2/§10 had GTA V + SA Original; SA Definitive added from
  research §6.4's verified table).
- **ENTER/EXIT is a 68 dp round button**, not the SRS's ≥120×64 dp
  top-centre rectangle — Muhammad's revision moved it; the F-tap behaviour
  (FR-19) is unchanged.
- **Settings/Disconnect icons** live as two small ghost buttons at the
  bottom-centre of the controller instead of the top bar (the revision
  reserves the top bar for status + mode pill). Disconnect is also on the
  Android Back dialog (FR-32) and the disconnected overlay.
- **Discoverable is a button in the pairing guide**, not automatic while
  the guide is open (FR-4) — Android requires a user-consent dialog for
  discoverability every time; auto-popping it on screen entry would be
  hostile. The guide's step 1 tells the user to tap it.
- **minSdk:** `build.gradle.kts` keeps the fixed template's
  `flutter.minSdkVersion`; the HID code guards Android < 9 with a
  plain-language error instead. Target device (realme C67) is Android
  13/14, so this is only a safety net.

---

## File map

### Dart (`lib/`)

| File | Role |
|---|---|
| `main.dart` | App entry; loads settings, premium dark teal theme, home = Connect screen |
| `models/game_key.dart` | `GameKey` enum — HID keycodes (W 0x1A, A 0x04, S 0x16, D 0x07, F 0x09, Space 0x2C, Enter, Esc) + Shift as modifier bit 0x02; fixed report ordering |
| `models/game_profile.dart` | The 3 game profiles (key mappings + selector notes) |
| `services/hid_service.dart` | Method/Event channel client; pressed-key set → snapshot reports (dedupe, 6-key cap); register→connect sequence with timeouts and plain-language errors; disconnect sequence |
| `services/settings_service.dart` | `shared_preferences` persistence (profile, steering range/dead zone/sensitivity, flip, last device); `ChangeNotifier` |
| `screens/connect_screen.dart` | S1 — game selector, permission card/flow, bonded laptop list, big CONNECT, pairing guide + discoverable button, status/errors |
| `screens/controller_screen.dart` | S2+S3 — both modes, key-source union manager, F-tap + mode logic, banner, disconnect overlay + reconnect, back-confirm, lifecycle/wakelock/orientation |
| `screens/settings_screen.dart` | S4 — steering feel, flip controls, default game, help notes |
| `widgets/steering_wheel.dart` | Delta-angle wheel, spring return, leather/stitch/metal/hub `CustomPainter`, fixed bezel ▲ |
| `widgets/joystick.dart` | Fixed-base 8-way WASD joystick with animated knob return |
| `widgets/car_pedal.dart` | Realistic pedal (metal arm + grip-ridge pad), press animation + glow |
| `widgets/round_button.dart` | Glossy round button — tap mode (ENTER/EXIT) or hold mode (HANDBRAKE/JUMP), lit state |
| `widgets/hold_surface.dart` | Single-pointer capture surface (press survives sliding off) |
| `widgets/top_bar.dart` | Status pill + mode pill (layout-only) |
| `widgets/premium_background.dart` | Dark gradient + ambient glow backdrop |

### Kotlin (`android/app/src/main/kotlin/com/muhammad/gtaremote/`)

| File | Role |
|---|---|
| `MainActivity.kt` | Creates the manager; forwards `onPause`, permission results, activity results; disposes on engine cleanup |
| `HidKeyboardManager.kt` | All Bluetooth HID work: profile proxy, `registerApp` with the standard boot-keyboard descriptor + SDP ("GTA Remote", keyboard subclass), connect/disconnect, 8-byte `sendReport`, bonded list, runtime permissions (CONNECT/ADVERTISE), enable-Bluetooth + discoverable intents, plain-language errors; on host pause → zero report + unregister |

Channels: MethodChannel `gta_remote/hid`, EventChannel `gta_remote/hid_events`.
Manifest: `BLUETOOTH`/`BLUETOOTH_ADMIN` (maxSdk 30), `BLUETOOTH_CONNECT`,
`BLUETOOTH_ADVERTISE`, `VIBRATE`; **no INTERNET permission** (NFR-2).
`pubspec.yaml`: tilt/WiFi draft removed — deps are only `wakelock_plus` +
`shared_preferences`. The superseded draft's `lib/` was replaced entirely;
the Android scaffolding follows the fixed AGP-9 template unchanged.

## How the HID channel works (one paragraph)

Dart keeps a set of pressed `GameKey`s. Every change rebuilds the report —
modifier byte (Shift → 0x02) + keycodes in a fixed order, max 6 — and calls
`sendReport` on the MethodChannel only if the snapshot changed. Kotlin
validates "registered + connected", packs the 8 bytes and calls
`BluetoothHidDevice.sendReport(device, reportId = 1, data)`. Registration
and connection truth flows the other way on the EventChannel from the real
`BluetoothHidDevice.Callback` (`onAppStatusChanged`,
`onConnectionStateChanged`); the Dart `registerApp()` future completes only
when Android's callback confirms registration. A pending register call is
queued if the HID profile proxy has not arrived yet.

---

## What could NOT be verified without a device

- **The gate question (SRS §9.1 / research R1):** whether realme UI on the
  C67 exposes the HID-device role at all. If pairing from Windows fails
  ("Incorrect PIN" / phone-only pairing), no app code can fix it — the
  SRS §6.3 SPP fallback would be the next step. The first real pairing of
  this app *is* the gate test.
- **Compilation:** no Flutter/Dart/Android SDK on this machine — the code
  was written and self-reviewed but never compiled. First proof is the
  GitHub Actions build.
- Pairing flow from Windows (passkey on both sides), SDP caching behaviour,
  and whether Windows shows the phone as a keyboard on first pair.
- 6KRO combos on the real phone+laptop (W+A+Space+Shift together), HID
  latency feel, and GTA's acceptance of the input in both games/profiles
  (esp. the SA Original Jump/Sprint swap — SRS §9.4 profile checks).
- Permission dialogs and the enable/discoverable intents on Android 13/14
  (realme UI), wake-lock behaviour, and OEM battery management during a
  long session (Settings help note covers the Unrestricted-battery tip).
- Touch feel: wheel spring timing, pedal sizes and the joystick dead zone
  on the real screen — tuned to the SRS/mockup numbers, adjustable in
  Settings if Muhammad finds them off.
- Edge case kept in mind: if the app is backgrounded mid-drive, Android
  unregisters the HID app by design; on return the controller shows the
  disconnected overlay with Reconnect (FR-29) — behaviour implemented, but
  the exact callback ordering on realme UI is unverified.

---

## v2 — Racing Cockpit theme, pedal swap, TILT mode, rename (2026-11-19)

Owner-approved changes on top of v1 + QA_REPORT + IMPROVEMENTS. None of
the earlier fixes regressed: early HID registration on connect-screen
load, no unregister on pause, registration waiter list, class-aware
auto-refreshing device list, fast-fail connect wait, permanently-denied
Settings path, wheel as raw `Listener`, steering hysteresis, text-scale
clamp 0.85–1.15 and compact scaling are all untouched in behaviour —
this round changed colours, pedal order, and added one input source.

### Theme — "Racing Cockpit" (Design 1)

Applied across connect screen, controller and settings, from
`mockup/design-options.html` `.v1` values:

- Background: near-black carbon — base `#0B0E13`, subtle ±45° diagonal
  weave painted by a `CustomPaint` inside a `RepaintBoundary`
  (`premium_background.dart`, no image assets), red glow bottom-right,
  faint orange glow top-left.
- Accent orange `#F97316`/`#EA580C`/`#FB923C`; secondary red
  `#EF4444`/`#B91C1C`; gunmetal surfaces `#171B21`/`#1F2937`, card
  borders `#262E3A`.
- Wheel repainted: gunmetal rim sweep (`#3A3F47`/`#14171C`/`#0A0C0F`/
  `#262B33`), spokes `#4B5563 → #1F2937 → #374151`, **orange dashed
  stitching**, **red top stripe** (`#EF4444 → #991B1B`, also the bezel
  marker), hub `#4B5563 → #111827 → #030712` with orange border and
  **orange hub ring**.
- Pedals are now gunmetal metal pads (gradient `#6B7280 → #374151 →
  #1F2937 → #4B5563`) with **vertical** grip stripes; arm `#9CA3AF →
  #4B5563`. Accent semantics unchanged: RACE label/border green,
  BRAKE red.
- ENTER/EXIT CAR = orange gradient, HANDBRAKE = red gradient,
  JUMP = gunmetal with orange border, RUN keeps its amber (cockpit
  warning-light) identity, joystick knob is now orange.
- CONNECT button, selection accents, chips, slider, guide steps —
  all orange; Material seed colour is orange, scaffold `#0B0E13`.

### Pedal order (final)

Driving (both steering sub-modes): **BRAKE first (left, wide+short
pad), RACE second (right, tall+narrow pad)** — this replaces the v1
"RACE first" revision. Pedal widgets are shared helpers in the
controller (`_brakePedal` / `_racePedal` / `_handbrakeButton`), so the
order cannot drift between sub-modes.

### TILT steering mode (new)

- The driving top bar gains a **STEERING | TILT** segmented switch
  (`widgets/steer_mode_switch.dart`, English labels per the approved
  mockup, orange active segment). It renders **only in driving mode**.
  The choice persists via `SettingsService.tiltSteering`
  (shared_preferences key `tilt_steering`) and is restored next
  session. No new Settings-screen entries.
- STEERING sub-mode: the existing touch wheel (unchanged behaviour).
- TILT sub-mode: **no wheel and no gauge** — BRAKE pedal bottom-left
  where the wheel was, RACE bottom-right, EXIT CAR + HANDBRAKE above
  RACE in the same relative spot as steering mode. Flip-controls
  mirrors both sides. The centre angle readout is hidden in TILT.
- Input: `sensors_plus` **^7.0.0**, `accelerometerEventStream()`.
  The steer angle is the phone's in-plane rotation of the gravity
  vector, `atan2(gy, gx)`, measured **relative to a baseline captured
  when tilt starts** (entering TILT, entering Driving in TILT,
  reconnect, or resume). Delta = current − baseline (the
  accelerometer reports the up vector, whose device-frame angle
  increases under clockwise rotation, so this yields
  clockwise-positive = steer-right in both landscape orientations —
  corrected in the v2 review, see IMPROVEMENTS_V2.md; the original
  build derivation had the sign inverted). A light low-pass
  (α = 0.25) kills hand jitter; samples with in-plane magnitude
  < 2.5 m/s² (phone nearly flat) are ignored rather than guessed.
- Thresholds mirror the wheel's hysteresis: **engage beyond 12°,
  release below 8°**, direct left↔right crossings switch immediately.
  Tilt feeds the key-source union as source `'tilt'` with the active
  profile's steer-left/steer-right keys (A/D in all profiles).
- Lifecycle: the subscription runs **only** while driving + TILT.
  It is cancelled and tilt keys released on switching to STEERING,
  switching on-foot, disconnect (HID state listener), app
  pause/inactive, and screen dispose. On resume/reconnect it restarts
  with a fresh baseline. A sensor-stream error stops tilt silently —
  pedals and buttons keep working.
- Not device-verified (no device here): the sign convention on the
  real phone in the user's usual landscape side, and the 12°/8°
  feel. If steering comes out inverted on hardware, the one-line fix
  is the sign of `delta` in `_onTiltEvent`.

### Rename — "AB GTA"

App label (manifest), MaterialApp title, connect-screen header,
permission/help strings, and the Bluetooth SDP name/description/
provider in `HidKeyboardManager.kt` now say **AB GTA**. The Android
package id (`com.muhammad.gtaremote`) and Dart package name are
unchanged, so this build installs as an update over v1. (Windows may
show the old name for the existing bond until the device is removed
and re-paired — same Remove-device step as before.)

### App icon

From the owner's logo (`imagine_media/…ab-gta-logo…webp`, 1600²):
centre-cropped to 90%, the remaining white corner triangles (outside
the logo's rounded square) flood-filled with near-black carbon from
the corners only, then written as `ic_launcher.png` +
`ic_launcher_round.png` at 48/72/96/144/192 px into
`res/mipmap-mdpi … mipmap-xxxhdpi`. The project had **no**
`mipmap-anydpi-v26` adaptive-icon XML (in fact no `res/` at all — it
came from `flutter create` in CI), so nothing had to be removed; the
new PNGs are the only launcher icons. **CI note:** the workflow must
preserve these `res/mipmap-*` folders (handled separately); if it
ever replaces `res/` wholesale instead of merging, the
`flutter create` styles (`@style/NormalTheme`) must still come from
the generated tree.

---

## v3 — HID mouse (camera), PWM steering, ATTACK + MAP, layout pass (2026-11-20)

Driven by Muhammad's first real play session with v2 (SA Original):
camera fixed, swimming straight-only/uneven, ENTER/EXIT feeling
reversed, steering all-or-nothing, no fight button, no map button,
buttons too big/touching. Full three-lens review: `IMPROVEMENTS_V3.md`
(1 major + 3 minor found in review, all fixed before build).

### HID mouse (the camera fix)

- The report descriptor gains a **mouse collection, Report ID 2**
  (3 buttons + 5-bit padding, relative X/Y ±127, wheel) appended
  after the keyboard collection — **keyboard bytes unchanged**.
  SDP subclass is now `SUBCLASS1_COMBO`; name/provider unchanged.
- Kotlin: `sendMouse(dx, dy, buttons, wheel)` on the same channel
  (guards mirror `sendReport`); `sendZeroMouseReport` added to
  `onHostPause`, `disconnectInternal` and `dispose`.
- Dart `HidService`: `_mouseButtons` state, `moveMouse`,
  `setMouseButtons` (change-guarded); `releaseAllKeys()` also
  zeroes the mouse buttons, so every existing safety path covers
  clicks too; the disconnect event resets the state without sending.
- **⚠ Owner action: Remove device + re-pair once on the laptop.**
  The descriptor changed, so Windows' cached SDP record for the
  existing bond is keyboard-only until re-paired.

### CAMERA pad (`lib/widgets/camera_pad.dart`, new)

Raw-Listener drag pad in all three layouts (centre, between the
side controls with ≥12 dp gaps, below the top bar, above the ghost
buttons). Deltas ×2.2 sensitivity, fractionally accumulated, flushed
every ~12 ms in ±127 chunks; final flush on lift; single-pointer
ownership like every other control. This one pad is SA's camera,
swim-direction control and pause-menu pointer.

### PWM steering (the oversensitivity fix)

The wheel and tilt no longer emit A/D directly. They feed a
normalised steer (−1..+1) into one engine in `controller_screen.dart`:
20 ms tick, direction chosen with each source's existing hysteresis
(wheel: dead-zone/range + the v2 release rule; tilt: 12° engage /
8° release over a 45° full-lock scale), duty =
clamp((|s| − dz)/(1 − dz)); per 100 ms the key is down
25 ms + 75 ms × duty (error diffusion across ticks — see
IMPROVEMENTS_V3 D3); duty ≥ 0.98 holds the key. `SteeringWheel`
now reports only its angle (its key callback and internal hysteresis
are gone — the engine owns thresholds); tilt feeds the same engine
instead of the old 'tilt' key source. The union source is 'pwm'.

### Momentary presses (the ENTER/EXIT fix)

ENTER/EXIT (F), JUMP and MAP are one clean **150 ms** press with a
**250 ms double-fire lockout** (`_momentaryKeyPress` +
generation guard; ENTER/EXIT keeps its target-capture + its own
lockout timestamp). JUMP changed from hold to tap. ENTER/EXIT stays
a single toggle button labelled ENTER/EXIT CAR.

### ATTACK + MAP

- **ATTACK** (on foot only, action-row third slot — where HANDBRAKE
  sits in driving): hold sends HID mouse LEFT, release sends up.
  Driving omits it deliberately (IMPROVEMENTS_V3 D2 — the pad owns
  the driving centre at small sizes).
- **MAP** (both layouts, action-row second slot — the v2 on-foot
  spacer's place): Esc tap; SA Original's map is in the pause menu,
  where the pad is the pointer.

### Swimming (issue closed without swim code)

Direction follows the camera → the pad. Speed: RUN remains the
FR-16 toggle, and while RUNNING the sprint key is held in every
report — the same signal as hold-to-sprint (IMPROVEMENTS_V3 D1).
A Settings help line now teaches pad + MAP + ATTACK + this.

### Layout pass

Round buttons 68→58 (ENTER/EXIT, HANDBRAKE, MAP), JUMP 94→80,
ATTACK 80, RUN 118×74→100×63, pedals RACE 78×148→66×126 /
BRAKE 114×96→97×82, arm 30→26. All gaps ≥12 dp (two 10 dp gaps
raised; top-bar gaps 10→12). Verified numerically at 640×360 and
~880 dp wide; compact scaling untouched. Pedal order and tilt
layout exactly as v2; profiles and Settings semantics unchanged.

### Not device-verified (owner's session decides)

Combo-device mouse acceptance in SA, camera sensitivity feel,
PWM feel in both steer modes, lockout feel on ENTER/EXIT, ATTACK
release on disconnect, swim turning with the pad. See
IMPROVEMENTS_V3 "Must verify".

---

## v4 — CONTROLLER + ARROWS modes, on-foot gunplay controls, English UI (2026-11-20)

Owner-approved mockups (`mockup/v4-modes.html`, screens v4-3 /
v4-4 — "Han theek") plus an owner-ordered scope expansion: a full
controller audit with any genuinely-needed controls added, and
ALL in-app Roman Urdu converted to English. Full three-lens
review + the owner-required pre-delivery verification checklist:
`IMPROVEMENTS_V4.md` (0 critical / 0 major; 2 minors fixed
pre-build; HORN evaluated and omitted with geometry proof).

### Two new driving modes (pure additions)

- **DriveMode enum** replaces the STEERING/TILT bool:
  STEERING | TILT | CONTROLLER | ARROWS in the top-bar switch,
  persisted as `drive_mode` (legacy `tilt_steering` bool migrated
  on load and kept in sync on write). Switching runs the existing
  clear-all path first; per-source mode guards block outgoing
  layer feeds during the switch fade. Tilt sensor logic is
  untouched and runs only in TILT. STEERING / TILT / ON FOOT
  layouts and behaviour are byte-for-byte the v3 ones.
- **CONTROLLER:** gamepad silhouette (static painter) behind a
  148 dp analog stick (left, STEER caption as approved), the
  CAMERA pad centre (210 dp wide at 640×360), and a right column
  of RACE (green) / BRAKE (red) trigger hold buttons (198×54)
  over the usual EXIT CAR • MAP • HANDBRAKE round row. The stick
  feeds the v3 PWM engine as source `'stick'` — fixed dead zone
  0.12 / release 0.08, Settings sensitivity applies, range and
  dead-zone settings stay wheel-only. New widget:
  `lib/widgets/analog_stick.dart`.
- **ARROWS:** two 88 dp ◀ ▶ buttons (left, 16 dp gap), CAMERA
  pad centre, the steering mode's exact cluster on the right.
  Buttons drive A/D as source `'buttons'` — no PWM; a press
  shorter than 90 ms is extended to a 90 ms minimum pulse (the
  mode's whole point: one tap = slight move), hold = continuous,
  both held = cancel. New widget: `lib/widgets/steer_arrows.dart`.
- Flip controls mirrors both new layouts exactly like the old
  ones (arrows keep ◀ on the pair's left — directions never
  mirror).

### On-foot audit additions

- **AIM** (hold = mouse RIGHT) and **CROUCH** (C tap — SA
  toggles crouch; momentary helper) as a compact third row in
  the on-foot cluster (AIM 96×48 + CROUCH 92×48; cluster width
  unchanged at 220, pad geometry untouched). ATTACK/AIM compose
  via the new `HidService.setMouseButton(bit, down)` — neither
  release clears the other; `releaseAllKeys` still zeroes both.
- **Weapon switch:** ◀ ▶ WPN pair (48×48) in the free band
  above the joystick (follows flip with the joystick), sending
  mouse **wheel ticks** (`HidService.wheelTick`) — tap = one
  weapon, hold = repeat after 400 ms every 200 ms. Wheel chosen
  over Q/E: mouse-native in SA + GTA V, spends no keyboard
  slots. `GameKey.c` (0x06) added; report bytes for sets
  without C are identical to v3.
- **HORN omitted deliberately:** a 4th action-row button (268
  dp row) would cut the steering-mode CAMERA pad at 640×360
  from 142 dp to 72 dp wide. Numbers in IMPROVEMENTS_V4.

### English UI

Every user-facing Roman Urdu string converted to plain English:
connect screen (permission dialogs, pairing guide,
troubleshooting card, status/errors), HID service progress +
errors, controller banners + disconnect dialog/overlay, Settings
labels + help (help also teaches the v4 modes/controls), and
17 error strings in `HidKeyboardManager.kt`. Code comments stay
Roman Urdu (developer notes, not UI). Verified by grep: zero
Roman Urdu hits in string literals.

### HID / re-pair

**No re-pair needed.** The Kotlin diff vs v3 (b3ca393) is
exactly 17 string-literal lines; the descriptor + SDP + QOS
block md5 is identical (`ba778a379ab87a7f50ec5d2810479153`),
channel method names identical, `MainActivity.kt` untouched.
Dart-side, the only HID changes are additive (`setMouseButton`,
`wheelTick`) over the v3 channel.

### Not device-verified (owner's session decides)

Stick feel + PWM proportionality from the stick, 90 ms arrow
tap feel, AIM+ATTACK simultaneous hold in SA, wheel-tick weapon
cycling, CROUCH toggle, English wording in the live pairing
flow. See IMPROVEMENTS_V4 "Must verify".

## v5 — CHEATS screen, MISSIONS GUIDE, HORN, MISSION + TAB buttons (2026-11-22)

Version 5.0.0+2. Approved scope + premium CHEATS design
(`mockup/v5-cheats-premium.html/png`). Full review:
`IMPROVEMENTS_V5.md`.

### What was added

- **Cheat typer** (`HidService.typeCheatCode`, Dart only): raw
  `sendReport` calls bypass the snapshot dedup; per letter
  55 ms down / 40 ms gap. SA + VC type directly in the game;
  GTA V goes through the ~ console (grave 0x35, 300 ms wait,
  letters, Enter). `releaseAllKeys()` first; per-letter
  connection check aborts a dropped type; `finally` clears the
  `isTypingCheat` flag, resets the dedup signature and re-sends
  the current snapshot (plus a raw empty report on abort).
- **CHEATS screen** (`lib/screens/cheats_screen.dart`, data in
  `lib/data/cheats.dart`): premium mockup design — per-game
  accent glow, tabs SAN ANDREAS (orange) / VICE CITY (pink) /
  GTA 5 (green) with real code counts (36 / 32 / 27), category
  headers, CODE + hint cards, status line (Typing… / Sent /
  Not connected / Connection lost), VC + GTA 5 footer notes.
- **GUIDE screen** (`lib/screens/guide_screen.dart`): how
  missions work (radar letter → marker), SA / VC / GTA 5
  sections, save points, airports, vehicle missions via the
  MISSION button.
- **New keys**: `GameKey.h` (0x0B), `e` (0x08), `tab` (0x2B),
  `capsLock` (0x39), appended to `hidKeyOrder` after `c` —
  pre-existing key sets emit byte-identical reports.
  `GameProfile.hornKey` (V: E, SA: H) and `submissionKey`
  (V: E, SA: CapsLock).
- **HORN**: STEERING = wheel hub hold (separate pointer in
  `SteeringWheel`, non-rotating HORN label, dispose releases);
  TILT = round button above BRAKE; CONTROLLER = round button
  under the action row; ARROWS = round button above the pair.
  All feed source `'horn'`.
- **MISSION pill** (driving, steering-control side, top 82):
  `_momentaryKeyPress('mission', submissionKey)` — the v3
  150 ms + lockout clean press.
- **TAB pill** (on foot): appended to the weapon-switch row;
  `_momentaryKeyPress('tab', GameKey.tab)`.
- **TopBar Row 2**: CHEATS + GUIDE pills on the action-cluster
  side (Row 1 is full at 640 dp while driving — see
  IMPROVEMENTS_V5); opening either screen mirrors
  `_openSettings` (clear-all + stop tilt first). Settings help
  teaches all five additions.

### HID / re-pair

**No re-pair needed.** `git diff HEAD -- android/` is empty;
the descriptor + SDP + QOS block md5 is identical to v4
(`ba778a379ab87a7f50ec5d2810479153`). All v5 work is Dart over
the existing `sendReport` channel.

### Not device-verified (owner's session decides)

Cheat typing in all three games (incl. the GTA 5 console
sequence and the Windows input-language caveat for Y/Z),
horn feel in the four modes, MISSION starting a taxi mission
in SA, TAB answering the property prompt.

## v5.0.1 rename (2026-11-22)
- App label renamed to "Gaming Remote" per Muhammad's words ("remote ki jga gaming Remote likho").
- Changed ONLY user-visible label/title strings: AndroidManifest android:label, MaterialApp title, connect/settings screens, pubspec description; version 5.0.1+3.
- Deliberately UNCHANGED: HidKeyboardManager SDP_SETTINGS name/description ("AB GTA") — that is the cached Bluetooth HID record; changing it risks a Windows re-pair, so the laptop-side Bluetooth name stays "AB GTA".

## v5.1 (2026-11-22) — cheat typer reliability + FLY mode

### 1. Cheat typer reliability fix (owner-device bug in v5)

Muhammad reported: cheat codes tapped in CHEATS do nothing in-game, while
typing the same codes on the laptop keyboard works; normal remote keys fine.

- **Kotlin finding (read-only, Kotlin NOT modified):** `HidKeyboardManager.kt`
  `sendReport` (lines 671–695) returns `result.success(sent)` where `sent` is
  the direct return value of `BluetoothHidDevice.sendReport(device,
  REPORT_ID, data)` — `false` when the proxy/device is null, when not
  `STATE_CONNECTED`, or on `SecurityException`. The boolean genuinely
  reflects the Android HID stack accepting the report.
- **The v5 bug:** Dart awaited the call but discarded the boolean, so a
  dropped report was a silently dropped letter → corrupted code → no effect.
- **v6 fix (`hid_service.dart`):** new `_sendRawReportReliable` — every send
  awaited, boolean read; on `false`, wait 40 ms and retry, up to 2 retries
  (3 attempts per report); still failing → typing aborts with a distinct
  result. Timings slowed: key held **90 ms**, gap **70 ms** (was 55/40).
  Same helper + timings for the GTA V console sequence (grave 0x35, 300 ms
  settle, letters, Enter 0x28).
- Return type is now `CheatSendResult { success, notConnected, sendFailed }`.
  CHEATS screen: success → "Sent — check your game"; sendFailed → "Could not
  send — check the connection and try again."; mid-type disconnect →
  "Connection lost — the code was not fully typed."; the pre-tap
  not-connected message is unchanged.
- All v5 safety semantics kept: refuse when disconnected or already typing,
  `releaseAllKeys()` first, per-letter connection check, raw sends bypass the
  `_lastSentSignature` dedup (repeated letters stay real presses), `finally`
  clears the flag, resets the signature, re-sends the current snapshot, plus
  a reliable raw empty report on the abort path.

### 2. FLY driving mode (planes & helicopters)

Muhammad's corrected design (he rejected separate TURN/NOSE button
clusters): **one handle** for turning AND pitch.

- `DriveMode.fly('FLY')` appended; persisted like the other modes;
  `DriveMode.byName` still falls back to STEERING for unknown names, so v5
  stored values migrate safely. Mode pill: segment padding 9→7, font
  11→10.5, letter spacing 0.8→0.5 so all five labels stay fully readable
  at 640 dp.
- New `FlyStick` widget (AnalogStick mechanics, two axes, four arrows
  ▲▼◀▶ drawn on the base, sky-blue accent, HANDLE caption).
  Controller feed `_feedFlyStick`, source `'flystick'`, dead zone engage
  0.25 / release 0.18 (hysteresis), no PWM, no sensitivity multiplier:
  - left → profile steer-left (A); right → steer-right (D)
  - **up → `GameKey.arrowDown` = NOSE UP; down → `GameKey.arrowUp` =
    NOSE DOWN** — intentional flight-stick inversion (GTA SA reads
    ArrowDown as nose-up). Do not "fix" this.
  - Diagonals work (both axes evaluated independently; the key-set
    architecture sends both keys in one report). Release reports (0, 0)
    → all four keys release. `_resetFlyStick()` runs inside
    `_clearAllKeys()`, so mode switches / screen opens / disconnects are
    safe exactly like other controls.
- `GameKey.arrowUp(0x52)` / `arrowDown(0x51)` added, appended at the END of
  `hidKeyOrder` — existing key-set report bytes are unchanged.
- Layout (640×360): handle column 196 (stick 176), THROTTLE column 118
  with compact `_FlyPedal` pads (RACE h118 "W — speed / climb", DOWN h84
  "S — brake / descend"; full CarPedals are 192+148=340 tall and cannot
  stack in the 260 stage), CAMERA column 270 wide with the pad plus
  EXIT (F) / MAP (Esc) clean-press buttons under it, bottom 72 so the row
  clears the centre ghost buttons. No HORN, no MISSION in FLY (pill
  suppressed). Flip swaps handle ↔ pedals; pitch stays central.
- Settings help gained one FLY line; the steering-modes help line now
  lists FLY too. Mockup updated: `mockup/v6-fly-mode.html` (handle design).

### 3. Rename

Already applied earlier today as v5.0.1 (commit `b9cca6f`): manifest
`android:label="Gaming Remote"`, MaterialApp title, connect/settings
strings. Verified for v5.1: no `AB GTA` string remains under `lib/`;
the Kotlin SDP name/description stays "AB GTA" on purpose (cached
Bluetooth record — changing it risks a re-pair).

### HID / re-pair

**No re-pair needed.** ZERO changes under `android/` in v5.1
(`git diff HEAD -- android/` empty before commit); descriptor + SDP + QOS
block (Kotlin lines 59–142) md5 still
`ba778a379ab87a7f50ec5d2810479153`, identical to v4/v5.

### Version note

pubspec is `5.1.0+3` as instructed. Version code 3 was already used by
v5.0.1+3; Android accepts an equal-versionCode install over the same
signature, and the versionName is higher. If a monotonic code is wanted
later, bump to +4.

### Not device-verified (owner's session decides)

Cheat typing after the reliability fix (all three games), FLY handle feel
in a plane/helicopter (incl. the pitch inversion in practice), DOWN pedal
behaviour in the air, five-segment pill readability on the real phone.

## v5.2 (2026-11-22) — FLY pitch fix: numpad keys

Owner-device bug in v5.1: in FLY mode the plane taxis (RACE/W works)
but the nose never lifts. Glint re-read `fly_stick.dart` and
`_feedFlyStick` directly — stick and feed were wired exactly as
designed (handle up → `GameKey.arrowDown`). The fault is the key
choice: **GTA SA (2005) does not pitch aircraft with the arrow keys
by default.** Pitch is the "Special Control" axis on the numpad —
**Numpad 2 = nose up, Numpad 8 = nose down** (the well-known SA
laptop problem; SA reads DirectInput scancodes, so NumLock state is
irrelevant). GTA V likewise: **Numpad 8 = nose down, Numpad 5 =
nose up**.

### Change (Dart only)

- `game_key.dart`: added `numpad2` (0x5A), `numpad5` (0x5D — HID
  keypad 5; 0x5C would be keypad 4), `numpad8` (0x60), appended at
  the END of `hidKeyOrder` after the arrow keys — every pre-existing
  key set stays byte-identical.
- `_feedFlyStick` only: handle UP (NOSE UP) now sends
  {arrowDown, numpad2, numpad5}; handle DOWN (NOSE DOWN) sends
  {arrowUp, numpad8}. Arrows kept for VC/other games. Left/right
  (A/D) unchanged. The comment above the function explains why the
  sets carry both arrow and numpad keys — do not "clean them up".
- Settings FLY help line unchanged (it never named the arrow keys).
- Full write-up: `IMPROVEMENTS_V6.md` §11.

### HID / re-pair

**No re-pair needed.** ZERO changes under `android/`; descriptor +
SDP + QOS block md5 still `ba778a379ab87a7f50ec5d2810479153`.

### Version

`5.2.0+4` — versionCode 4, monotonic again (v5.1's +3 had reused
5.0.1's code 3).

### Not device-verified (owner's session decides)

Pitch response in SA (plane + helicopter) and GTA V with the numpad
keys; VC unaffected-ness (numpad usages expected inert there).

## v5.3 (2026-11-22) — CRICKET mode for EA Sports Cricket 07

Version 5.3.0+5. Muhammad-approved design (mockups
`mockup/v7-cricket-mode-4.png` BATTING + `mockup/v7-cricket-bowling.png`
BOWLING — his layout after three correction rounds: buttons all on
ONE side, small and ROUND, none stretched; the swipe/drag area on
the other side). Full three-lens review + traces:
`IMPROVEMENTS_V7.md`.

### What was added

- **`DriveMode.cricket('CRICKET')`** — sixth pill segment (segment
  padding 7→5, font 10.5→10, spacing 0.5→0.3 so all six labels fit
  at 640 dp; the status pill ellipsises first, as since v5).
  Persisted like the other modes; `byName` fallback unchanged.
  When active, CRICKET **replaces the driving stage**; the
  MISSION pill is suppressed (FLY rule extended).
- **BATTING tab** (`CricketBattingArea`): the whole left area is
  the swipe surface. Swipe ≥ 40 dp fires ONE snapshot for 120 ms
  (generation-guarded timer, no lockout): the 8-way sector's
  arrow combo (screen direction = arrow direction, broadcast
  camera) + the selected shot key + Shift if **LOFT** is held.
  A tap (< 40 dp) sends nothing — leaving a ball, exactly like
  the game. Shot selectors: FRONT FOOT (S) default, BACK FOOT
  (W), ADVANCE (D) — state only, reset to FRONT FOOT on every
  clear-all. RUN = clean-press D, CANCEL = A, PAUSE = Esc,
  MENU = S (all via the v3 `_momentaryKeyPress` helper).
- **BOWLING tab** (`CricketBowlingArea`): drag holds the marker
  arrows matching the drag vector from its anchor (10 dp dead
  zone per axis, diagonals hold both) in source
  `cricket_marker`; release clears them. The on-screen marker
  dot is visual only. Deliveries (clean-press 150 ms): SEEDHI
  BALL = S, VARIATION 1 = A, VARIATION 2 = D, VARIATION 3 = W,
  SLOWER = Shift alone. **Variation labels stay generic on
  purpose** — which ball a variation key throws depends on the
  bowler and the game shows the name itself.
- **CAMERA ULTA** (both tabs): persisted toggle
  (`SettingsService.cricketCameraFlip`, pref
  `cricket_camera_flip`); inverts both axes of batting swipes
  only — never the bowling marker, never reset by clear-all.
- **Layout (640×360):** gesture column 331 dp wide (≥ 330),
  tabs on top of it, surface bottom at 72 (ghost-button
  clearance, same as the camera pad); divider at x 359; cluster
  252×252 (3 × 76 dp round buttons + 12 dp gaps) centred in the
  260 dp stage. The mockups' "BUTTONS" caption is dropped —
  the grid alone fills the stage height. Flip controls mirrors
  the layer (cluster ↔ gesture swap, offsets only).
- **New keys:** `GameKey.arrowLeft` (0x50) / `arrowRight`
  (0x4F) — the brief assumed all four arrows already existed;
  only Up/Down did (FLY). Appended at the END of `hidKeyOrder`,
  so all pre-existing key sets stay byte-identical.
- Entering CRICKET or switching its tabs runs the standard
  `_clearAllKeys()` first, which now also calls
  `_resetCricketState()` (shot timer cancelled, generation
  bumped, LOFT flag cleared, shot back to FRONT FOOT).
- Settings help: the steering-modes line now lists CRICKET, and
  one new help line teaches the mode (swipe to bat, drag to
  place the ball, CAMERA ULTA).

### HID / re-pair

**No re-pair needed.** ZERO changes under `android/`
(`git diff HEAD -- android/` empty); descriptor + SDP + QOS block
md5 still `ba778a379ab87a7f50ec5d2810479153`, identical to
v4/v5/v5.1/v5.2. All v5.3 work is Dart over the existing
`sendReport` channel.

### Not device-verified (owner's session decides)

Swipe timing against real bowling speeds; the 120 ms shot window
against the game's input polling; marker drag distance/feel;
CAMERA ULTA against the in-game flipped camera; six-segment pill
readability on the real phone; whether Cricket 07's variations
match the A/D/W/Shift keys for his bowlers (the game shows the
names — the buttons deliberately don't guess them).

## v5.4 — ATTACK auto-aim (aim + fire, aik button)

- **Darkhwast (2026-11-24):** AIM phir ATTACK — do alag buttons me
  waqt lagta hai. ATTACK ke andar hi nishana lagane wala function
  rakh do. Koi naya button nahi, layout waisa hi.
- **Tabdeeli (Dart-only, `controller_screen.dart`):**
  ATTACK dabate hi LEFT (fire) + RIGHT (aim) dono mouse bits lagte
  hain; sub-label `Mouse` → `Aim + Fire`. AIM button rehta hai
  (baghair fire ke nishana). Malik-gin helper `_setAimHeldBy`
  + field `_aimHolders`: right bit tabhi chhutta hai jab 'aim' aur
  'attack' dono malik chhor dein. `_clearAllKeys()` me
  `_aimHolders.clear()` (stale-holder band).
- **QA:** `IMPROVEMENTS_V8.md` — teen nazariye (user/tester/
  expert), traces T1–T6, 0 critical/major findings.
- **HID / re-pair:** ZERO changes under `android/`; descriptor +
  SDP + QOS md5 `ba778a379ab87a7f50ec5d2810479153` unchanged →
  **no re-pair, v5.3 ke upar install karo.**

### Not device-verified (owner's session decides)

ATTACK se aim+fire aik saath; AIM akela sirf nishana; AIM dabaye
rakh kar ATTACK chhorne par aim na toote; mode switch ke baad
koi atka hua aim nahi.
