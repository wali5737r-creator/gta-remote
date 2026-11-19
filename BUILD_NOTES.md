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
  background/pause (both Dart lifecycle *and* native `onPause` → zero report
  + unregister), leaving the controller, and mode switch; on reconnect the
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
