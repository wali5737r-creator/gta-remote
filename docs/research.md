# GTA Remote — Research Report

**Date:** 2026-11-19
**Project:** Free Android app (Flutter) that turns Muhammad's phone (realme C67, Android 13/14) into a steering-wheel controller for GTA V and GTA San Andreas on his Windows laptop.
**Requirements driving this research:** on-screen touch steering wheel (no tilt), RACE/BRAKE pedals, Enter/Exit-car button, separate on-foot controls, **Bluetooth only, no internet**, beginner-friendly.

---

## 1. Executive summary

- **Primary approach: Bluetooth Classic HID Device profile.** Android's `BluetoothHidDevice` API (Android 9+, API 28+) lets the phone register itself as a standard Bluetooth **keyboard**. Windows pairs with it using its built-in HID driver — **no software of any kind is installed on the PC**, and GTA cannot distinguish the phone from a real hardware keyboard.
- **No mature Flutter plugin exists for HID *device* (peripheral) mode** — almost all "HID" packages are host-mode (wrong direction). The plan is a hand-written **Kotlin platform channel** (~300–500 lines, engineering estimate) behind the Flutter UI, following proven open-source examples (Remote Numpad, the `virtual_gamepad` example app).
- **⚠️ One gate before building:** whether realme UI on the C67 exposes the HID-device role to apps is **unverified** — some OEMs disable it in firmware. A 30-minute free test with an existing HID app on the actual phone + laptop must pass before the full UI is built (§5).
- **Fallback: Bluetooth SPP/RFCOMM** — `flutter_bluetooth_serial_plus` on the phone + a small Python (pyserial) receiver on Windows pressing keys via SendInput scan codes. It works without HID firmware support, but needs PC software running every session, manual COM-port setup, and SendInput-injected keys can be ignored by games (DirectInput/UIPI/anti-cheat risk, especially GTA Online).
- **UI research surprise:** nearly all existing "phone steering wheel" apps steer by **tilting the phone**, not by dragging a wheel — Muhammad's requested drag-wheel is rarer and needs the specific mechanics in §6 (delta angle tracking, ±90° range, spring return-to-centre). A second key catch: **GTA San Andreas (original PC) swaps Jump and Sprint keys vs GTA V**, so the app needs a game-profile selector.

---

## 2. Option A — Bluetooth HID Device profile (PRIMARY)

### 2.1 How it works

1. The app gets the `BluetoothHidDevice` proxy via `BluetoothAdapter.getProfileProxy(..., BluetoothProfile.HID_DEVICE)` (profile constant 19).
2. It calls `registerApp()` with an SDP record describing a **keyboard** (`BluetoothHidDeviceAppSdpSettings`, subclass `SUBCLASS1_KEYBOARD` = 0x40) and the standard boot-keyboard report descriptor (~50–70 bytes, copied from a proven example project, not hand-derived).
3. First pairing is **initiated from Windows**: Settings → Bluetooth & devices → Add device → select the phone → confirm passkey on both sides. Windows then treats the phone as a keyboard (SDP record decides this, not the Bluetooth name).
4. In the app, the user picks the bonded laptop and the app calls `connect()`; when `onConnectionStateChanged → STATE_CONNECTED`, the app sends key state with `sendReport(device, reportId=1, data)`.
5. Later sessions: open app → it re-registers → tap Connect. No re-pairing.

**Hard constraints from the official API docs:**

- *Only one app can hold the HID-device registration at a time* — other HID apps on the phone will conflict; they must be closed.
- *The app is automatically unregistered when it is not in the foreground* — the app must stay open, screen on, while playing. This matches a controller use case (and the UI keeps the screen awake anyway).
- Registration/connection are **asynchronous** — state comes from `onAppStatusChanged` / `onConnectionStateChanged` callbacks; return values only mean "command sent".

**Permissions (Android 12+, mandatory on the C67):**

| Permission | Type | Why |
|---|---|---|
| `BLUETOOTH_CONNECT` | Runtime | Required by every `BluetoothHidDevice` method |
| `BLUETOOTH_ADVERTISE` | Runtime | Makes the phone discoverable for the first Windows-initiated pairing |
| `BLUETOOTH_SCAN` | Runtime (optional) | Only if the app scans; can be avoided (pairing is PC-initiated, PC is read from the bonded list). If declared, use `neverForLocation` so no location permission is involved |
| `BLUETOOTH` / `BLUETOOTH_ADMIN` | Manifest, `maxSdkVersion=30` | Legacy, for pre-Android-12 devices |

The user sees one system "Nearby devices" dialog. No location permission is needed.

### 2.2 The HID keyboard report — exact bytes for GTA

The phone sends an **8-byte boot-protocol keyboard report** on every state change:

| Byte | Meaning |
|---|---|
| 0 | Modifier bitmask — Left Shift = bit 1 = `0x02` (also L-Ctrl `0x01`, L-Alt `0x04`, etc.) |
| 1 | Reserved, always `0x00` |
| 2–7 | Up to **6 simultaneous keycodes** (USB HID Usage Page 0x07), `0x00` = empty |

**Keycodes needed:**

| Key | HID usage |
|---|---|
| A | `0x04` |
| D | `0x07` |
| F (letter — GTA enter/exit vehicle) | `0x09` |
| S | `0x16` |
| W | `0x1A` |
| Space | `0x2C` |
| Left Shift | *not a keycode* — modifier byte bit `0x02` |
| Enter (bonus) | `0x28` |
| Escape (bonus) | `0x29` |

> Note: GTA's enter/exit key is the **letter F = `0x09`**, not a function key (F1–F12 are `0x3A`–`0x45`).

**Press/release model is state, not events.** The app keeps a set of currently-pressed keys; on every touch change it rebuilds and sends the full snapshot:

- Press W: `00 00 1A 00 00 00 00 00`
- W + A together: `00 00 1A 04 00 00 00 00`
- W + A + Shift (sprint): `02 00 1A 04 00 00 00 00` (modifier does not consume a key slot)
- Release everything: all zeros.

**Simultaneous keys — 6KRO is enough.** Boot protocol allows 6 keycodes + modifiers. Worst realistic GTA combo — W + A/D + Space + F + Shift = 4 keycodes + 1 modifier — fits comfortably. An NKRO bitmap descriptor is possible but unnecessary and risks Windows compatibility; not for v1. (One thing to verify in the on-device prototype: W + A + Space held together must all register — see SRS test checklist.)

### 2.3 Flutter feasibility

| Package (pub.dev, checked 2026-11-19) | Verdict |
|---|---|
| `hid_tool` (0.1.x, updated 2026-10-06) | **Wrong direction** — HID *host* mode (app talks *to* a HID device). Do not use. |
| `bluetooth_hid`, `flutter_bluetooth_hid`, `hid_device` | **Not found** on pub.dev under these names despite targeted searches. Do not plan around them. |
| `universal_bluetooth_classic` (1.3.0, updated 2026-10-29; first published 2026-09-10) | **Only plausible HID-device plugin, but unproven.** Advertises SDP registration (`setupSdp` with an `AndroidSdpConfig` mirroring `BluetoothHidDeviceAppSdpSettings`) and `sendHidReport`. Cautions: much of its language is host-flavoured, its API already changed between 1.2.0/1.3.0, and it is ~2 months old. **Time-boxed spike only** — if it demonstrably registers the phone as a keyboard to Windows, it may replace part of the channel; otherwise discard. |
| `virtual_gamepad` (1.0.0, 2026-06-07) | Not a Bluetooth plugin — a gamepad **UI** widget. Its example app binds to `BluetoothHidDevice` via a hand-written Kotlin channel, confirming the platform-channel pattern is the norm. (Its report is a gamepad report, not the keyboard report GTA needs.) |

**Decision: own platform channel.** Flutter UI (wheel, pedals, buttons, multi-touch) → MethodChannel/EventChannel → one self-contained Kotlin component: proxy + service listener, report descriptor, SDP settings, HID callback, bonded-device list, `connect()/disconnect()`, pressed-state set → report builder → `sendReport()`, runtime permission requests.

**Open-source references (learn patterns from):**

- **Remote Numpad** (`guillaumevpayet/remote-numpad`, Kotlin, GPL-3.0 — study, don't copy code blindly): `HidConnectionInterface.kt`, `KeyboardReport.kt`, `HidPairingManager.kt` (CompanionDeviceManager pairing), `HidValidator.kt` (API 28 check).
- **`virtual_gamepad` example** (MIT): Flutter + Kotlin `BluetoothHidDevice` binding — closest to this project's exact stack.
- **Authorizer** (`tejado/authorizer`): pretends to be a Bluetooth HID keyboard; confirms API 28+ minimum and the one-registration exclusivity.

Shipping Play Store apps (Cordless, Remote Numpad, Dotori) confirm the user-facing claim: *"pairs like an ordinary Bluetooth keyboard — nothing to install on the other device."*

### 2.4 realme / Android 13–14 risks (the #1 project risk)

- The C67 comes in two variants — 5G (Dimensity 6100+, Bluetooth 5.2) and 4G (Snapdragon 685, Bluetooth 5.0, Android 13 → updated to 14) — both run realme UI 4.0 and support Bluetooth Classic HID in principle.
- **⚠️ UNVERIFIED: no source confirms or denies `BluetoothHidDevice` support on realme UI / the C67.** The API existing does not guarantee the OEM firmware exposes the HID peripheral role. Documented failure class: some OEMs (historically OnePlus, Nokia, Moto; per a shipping app's own listing, some Xiaomi/Redmi/POCO) disabled it. The failure signature is pairing from the PC failing with **"Incorrect PIN/passkey"**, or the phone pairing as a phone only, never opening a HID channel. No app can fix missing firmware support.
- **SDP caching:** if the name/subclass/descriptor changes during development, Windows keeps the cached pairing. Fix: Remove device in Windows **and** forget on the phone, then re-pair.
- **Battery savers:** OEM power management can kill a background connection. Mitigations: app stays foreground (required anyway), wake lock while connected, advise setting the app to "Unrestricted" battery.
- **Reconnect is not automatic** after the app is swiped away (registration died with it). The home screen is designed around one big "Connect" action that does register → connect in order and shows live connection state.

---

## 3. Option B — Bluetooth SPP / RFCOMM + Python receiver (FALLBACK)

### 3.1 Phone side (Flutter)

| Package | Status |
|---|---|
| `flutter_bluetooth_serial` (original) | **Unmaintained** — stuck at 0.3.1 (2021), pre-dates Android 12 permissions. Do not use. |
| `flutter_bluetooth_serial_plus` | **Maintained fork — the SPP choice.** v0.5.7 (published 2025-07-04, updated 2026-10-28). Same familiar API (`BluetoothConnection.toAddress`), handles Android 12+ permissions (`ensurePermissions()`). |
| `bluetooth_spp` (0.1.0, 2026-09-28) | Clean-room replacement, correct permissions, but **client-only (no RFCOMM server socket)** and author states a real SPP link is untested. Too young. |

Mainstream Flutter SPP plugins are **clients only** — the phone cannot host the service. Workable topology: **Windows is the SPP server** (it offers the "Incoming" serial service) and the phone connects out to it.

### 3.2 Windows side

1. Pair phone ↔ laptop in Windows Bluetooth settings.
2. Windows → "More Bluetooth options" → COM Ports tab → **Add → Incoming (device initiates the connection)** → note the COM number. Windows creates a virtual port shown in Device Manager as *"Standard Serial over Bluetooth link"* (SPP UUID `0x1101`).
3. Install Python 3 (tick "Add to PATH"), then the one dependency: `py -m pip install pyserial` (pyserial is not stdlib; everything else in the receiver is stdlib `ctypes`).
4. Receiver script: open the COM port (baud is ignored on Bluetooth virtual ports), read state frames from the phone (e.g. full touch-state per change, so a dropped packet self-heals), and inject keys with `ctypes` → `user32.SendInput` using `KEYEVENTF_SCANCODE (0x0008)` (+ `KEYEVENTF_KEYUP 0x0002` on release). PS/2 Set-1 scan codes: W `0x11`, A `0x1E`, S `0x1F`, D `0x20`, F `0x21`, Space `0x39`, L-Shift `0x2A`.
5. Script must run **before** the game, console left open, at the **same integrity level** as the game.

### 3.3 SPP problems

- **Two COM ports per pairing** (one Incoming, one Outgoing) with near-identical names — picking the wrong one is the #1 beginner failure: the script opens "successfully" and receives nothing forever.
- **COM numbers are not stable** — re-pairing or Windows updates can renumber them, breaking a hard-coded port.
- **Socket fragility** — the classic `read failed, socket might closed or timeout, read ret: -1` error; recovery is re-bond / toggle Bluetooth. No auto-reconnect in the plugin API.
- **⚠️ SendInput vs games:** SendInput events are *injected* input, subject to UIPI (can only inject into apps at equal/lesser integrity — run GTA as admin and the script as normal user, and input silently vanishes). Scan-code mode improves DirectInput/Raw Input compatibility but *"does not guarantee success"*; anti-cheat may ignore injected input. **SPP+SendInput might work in GTA SA / GTA V Story Mode and fail in GTA Online. HID has no such caveat.** (Inferred from DirectInput/SendInput evidence; no source tested GTA directly.)
- **User friction:** Python + pip + a console window + COM-port picking + "run this first, every time" is a developer setup, not a consumer setup.

---

## 4. Comparison

| Criterion | **HID Device (Classic BT HID)** | **SPP / RFCOMM + Python receiver** |
|---|---|---|
| PC software needed | **None.** Built-in Windows HID driver; phone *is* a keyboard | **Yes, mandatory:** Python + pyserial + receiver script running before every session, at matching integrity level |
| Setup difficulty (beginner) | Pair once **from Windows** (like any BT keyboard), then one-tap Connect in app | Pair, *plus* manually add an Incoming COM port, identify the right COM number among two similar ports, start script, then connect |
| Latency | BT HID report interval 8 ms (125 Hz); measured on a real BT keyboard: 8.5 ms avg, P95 14.3 ms; typical end-to-end 8–20 ms. Fine for GTA driving | No authoritative figure found (unverified). Same radio hop *plus* RFCOMM framing, COM layer, Python loop, SendInput — reasonably expected ≥ HID with more jitter |
| Reliability / reconnect | OS-level profile; reconnect = register + `connect()` in app. Risks are front-loaded (firmware support, first pairing) | COM renumbering, incoming/outgoing mix-ups, stale-socket errors, script-not-running, integrity mismatch. Reconnect logic entirely ours |
| Simultaneous keys | **6 keycodes + all modifiers (6KRO)** — GTA worst case (W+A+Space+F+Shift) = 4 + modifier. Fits | Unlimited by design (own protocol) — SPP's only outright win, and GTA doesn't need it |
| Works in GTA itself | **Yes by construction** — indistinguishable from a hardware keyboard to DirectInput/Raw Input/anti-cheat | **At risk** — injected input, UIPI, anti-cheat (esp. GTA Online) |
| Flutter effort | No mature plugin. Spike `universal_bluetooth_classic` (new, ambiguous) or write a ~300–500-line Kotlin platform channel (estimate) using documented APIs + copyable examples | Plugin-ready today (`flutter_bluetooth_serial_plus` 0.5.7). But total system effort is higher: Python receiver, setup guide, COM-port UX, support |
| Failure modes | (1) OEM firmware lacks HID-device role → total failure on that phone, detectable in 30 min before building; (2) "Incorrect PIN" pairing failure; (3) another HID app holds the single registration; (4) app backgrounded/screen off → unregistered; (5) stale SDP cache → forget & re-pair | (1) Wrong COM port → silent no-data; (2) COM number changes → script breaks; (3) Python/pyserial missing or script not running; (4) SendInput blocked/ignored by game; (5) RFCOMM socket drops; (6) phone-as-server assumption → never connects |
| Internet needed | None, ever | None after the one-time `pip install pyserial` (which itself needs internet once) |

### Recommendation

**PRIMARY — Bluetooth Classic HID Device profile** (`BluetoothHidDevice`, API 28+), Flutter UI + hand-written Kotlin platform channel. Reasons, in order of weight: (1) only option meeting the headline requirement — **no software on the PC**; (2) only option **guaranteed to be seen by GTA as a real keyboard**, immune to the SendInput failure class; (3) 6KRO + modifiers covers every GTA combination; (4) ~8–15 ms latency is proven-adequate for driving; (5) the Kotlin surface is small, documented by Google, with open-source precedents in the exact Flutter+Kotlin shape.

**FALLBACK — SPP/RFCOMM** via `flutter_bluetooth_serial_plus` (phone) + Python/pyserial receiver with scan-code SendInput (PC). Trigger only if the C67 fails the HID gate. Accept its costs explicitly: PC program every session, manual COM-port setup, and a real chance GTA (especially Online) ignores injected input — test in GTA SA and GTA V Story Mode before promising anything.

**Also considered and set aside:** BLE HID-over-GATT (HOGP) — also pairs with Windows with no PC software, but on Android it means hand-managing GATT services/advertising/bonding; more work than Classic HID. Research it only if the C67's Classic HID role turns out broken. WiFi/UDP (the superseded v1 draft) — excluded by Muhammad's requirement: Bluetooth, no internet/WiFi.

---

## 5. ⚠️ Mandatory pre-build gate (30 minutes, free)

Do **not** build the full app before this test:

1. On the actual **realme C67**, install an existing free HID-device app (e.g. Cordless free tier, Remote Numpad, or Authorizer) and enable its Bluetooth HID/keyboard mode. Close any other HID apps first (single registration).
2. On the actual **Windows laptop**: Settings → Bluetooth & devices → Add device → Bluetooth → select the phone → confirm passkey on both sides.
3. Open Notepad on the laptop and type from the phone app. Also hold two keys at once (e.g. W+A) and confirm both register.
4. **Pass** → Classic HID is proven on this exact phone/firmware; build with confidence.
   **Fail** (especially "Incorrect PIN", or pairs as phone-only) → firmware lacks the HID-device role; no app can fix it. Switch to the SPP fallback (and optionally research BLE HOGP).

---

## 6. UI/UX research

### 6.1 What existing apps teach us

| App | What it does | Lesson for GTA Remote |
|---|---|---|
| **Monect PC Remote** (10M+ downloads) | Multi-mode remote; Race mode steers by **G-sensor tilt**, on-screen accel/brake buttons; XInput emulation; layout store | Praise for versatility; **complaints: obnoxious half-screen ads, crashes, reconfig burden.** → No ads over controls, ever. One purpose, one screen — breadth is beginner-hostile. |
| **HandyGamePad** | Phone as gamepad (USB/Wi-Fi); gyro wheel = rotate the phone itself | **Free version limited to ~10 min/session** → session timers destroy a driving session. GTA Remote: none, ever. |
| **DroidJoy** | Real XInput gamepad emulation, Wi-Fi **or Bluetooth**, explicitly lists GTA V + GTA SA; joysticks, D-pad, 14 buttons | **Top complaint: could not connect at all** (even when paired) → connection UI is step 1, not buried in Settings. Occasional ~1 s input freeze on Wi-Fi. Users want per-button customisation, but ship a fixed good layout first for a beginner. |
| **RojX** | Drag-and-drop builder; **virtual wheel up to 900° + auto-centering**; per-axis linearity/sensitivity/deadzone | **Markets instant GTA template switching: On-Foot → Vehicle → Flight.** Validates Muhammad's driving/on-foot split — and that the switch must be instant, in-game, one tap. (Wi-Fi only; GTA Remote differs by design.) |
| **GamePad (BLE) / Gamepad Remote Controller** | Serverless **Bluetooth HID** gamepad apps; Steering mode = wheel + gas/brake pedals | Proves the no-PC-server HID model ships and works. Mode presets (Steering vs Classic) are how every successful app solves driving vs on-foot. |
| **Bluetooth Mouse & Keyboard apps** | Send **keyboard keys** via BT HID; best one has a gaming mode: **virtual thumbstick for WASD movement** + touchpad for mouse aim | Exactly the on-foot pattern recommended in §6.4. Keyboard-key control = GTA's keyboard bindings are the spec; there is no analog steering axis (see §6.2). |
| **Real Racing 3** ("Wheel" control) | "Wheel" is actually a **horizontal slide** disguised as a wheel; brake/accel = touch zones | Sliding is far easier to learn than rotating. Muhammad explicitly asked for rotate → ship rotate, but note slide as a possible v2 Settings alternative ("Steering style: Wheel / Slide") if rotate tests badly. |
| **Asphalt 8 / Legends (TouchDrive)** | Auto-steer/auto-accel options; player taps drift/boost | Beginners love **fewer simultaneous jobs**. GTA can't auto-steer, but v1 keeps pedals hold-only and drops gear/nitro clutter. |
| **Indie racing UX (Velocity Unleashed / Redline Riviera)** | Corner pedals under natural thumb rest; hold = throttle, tap = trail-brake; red glow on brake; widened touch radius so the thumb "won't slip off mid-corner"; short haptic tick | Directly adopted in §6.3. (Their tilt figures — full lock at 17–38° — show how sensitive humans want steering to feel.) |

**Headline:** almost every "phone steering wheel" app steers by **tilt**. The drag-wheel Muhammad asked for is the exception — its mechanics must be designed deliberately (§6.2), not copied.

### 6.2 Touch-wheel mechanics

- **Rotation tracking — absolute-angle *delta* method (recommended).** On touch-down, record the wheel centre; compute the finger's angle `atan2(y−Cy, x−Cx)`; on each move, add the *delta* (wrapped to −180°…+180°) to the wheel angle. This is the method in Nintendo's steering patent and VR wheel implementations. **Delta, not absolute:** if wheel angle = finger angle, grabbing the wheel at the bottom would snap it 180°. With deltas, wherever he grabs, that grip point follows his finger.
- **Grab area:** the whole disc, not a thin rim ring (beginners miss thin targets). Ignore touches within ~24 dp of the centre (angle is noisy there). **Finger ownership:** the first finger on the wheel owns it until it lifts; pedal fingers never steal it.
- **Max rotation: ±90° (180° lock-to-lock) default; ±135° option in Settings.** NOT 900°: that needs 1.25 turns each way = grab-drag-release-regrab 3–4 times per corner on glass (900° only makes sense for a phone in a physical rotating mount). **And the GTA-specific reason: GTA keyboard steering is binary A/D — a 900° wheel gives zero extra precision over 180°, only extra finger work.**
- **Spring return-to-centre: mandatory, not cosmetic.** On finger lift, animate back to 0° in ~180–250 ms (ease-out). For keyboard control this is a *safety* feature: a wheel stuck at −60° means `A` stays held and the car circles into a wall. Release A/D first as the wheel crosses the dead zone, then animate; ignore steering output while returning. Add a visible centre mark (top spoke/dot + fixed ▲ on the bezel).
- **Dead zone: 7° each side of centre** (Settings slider 0–15°). Absorbs finger tremor/resting drift. Forza guidance: keep the inner dead zone small unless straight-line travel is a problem.
- **Sensitivity:** default 1:1 finger-to-wheel; beginner-friendly **Low (0.7×) / Medium (1×) / High (1.4×)** buttons instead of a numeric slider. Gentle response curve near centre (e.g. output ∝ angle^1.3) reduces constant straight-line corrections. For binary A/D this maps to hold behaviour; an optional v2 refinement is pulse-width steering (small angle = tap-tap A/D, large angle = continuous hold) to fake analog feel.

### 6.3 Pedals

- **Hold-to-press buttons, never sliders** — W/S are binary; sliders need eyes-down and drift under the thumb.
- **Placement:** opposite side from the wheel, bottom corner, under the other thumb — steering + accelerating *simultaneously* requires two thumbs. Two tall vertical pedals like a car: **inner = BRAKE/REVERSE (S)** in red/orange, **outer = RACE/GAS (W)** in green, slightly taller/wider (it's held ~80% of driving time). In GTA, holding brake while stopped reverses automatically — the label teaches this (`BRAKE / REVERSE`); no separate reverse button.
- **Size:** ~84–96 dp wide × 130–150 dp tall each, 12–16 dp gap (prevents fat-finger both-pedals presses), touch area extending ~8 dp beyond the visible pedal.
- **Feedback (glass has no click — fake it three ways):** (1) instant visual — pedal fills bright, scales to ~96%, shifts down 2–3 dp; (2) haptic — one short 15–25 ms tick on press-down only (no continuous buzz); (3) persistent lit state while held, so a glance confirms "gas is ON".
- **Slide-off safety:** the pedal captures its touch — if the thumb slides off while held, the pedal stays active until the finger lifts.
- **Handbrake is essential in GTA driving (Space, both games):** a smaller round button above BRAKE. (Horn/camera keys differ between games — v1.1 at most, per-profile only.)

### 6.4 On-foot controls

**Verified key table — and a trap:**

| Action | GTA V (PC) | GTA SA — Original PC | GTA SA — Definitive Edition |
|---|---|---|---|
| Move | W A S D | W A S D | W A S D |
| Enter/Exit vehicle | F | F (also Enter) | F |
| Sprint / Run | **Left Shift (hold)** | **Space (hold/tap)** | Space |
| Jump / Climb | **Space** | **Left Shift** | Space |

SA Original swaps Sprint/Jump vs GTA V (verified against the original SA manual: Jump = Left Shift, Sprint = Space). **The app must have a game selector — [GTA V] [GTA SA] — on the Connect screen, and button labels must follow the profile.** Hard-coding one game's mapping is the single easiest bug to ship.

- **Movement: virtual joystick (recommended).** Four separate direction buttons are worst (no exclusivity, diagonals need two fingers, lift-and-replace to change direction); a pictured D-pad drifts on glass with no tactile pivot. A joystick gives one-thumb sliding movement with natural diagonals — quantised to **8 directions** (45° sectors → 1 or 2 WASD keys), radial dead zone ~12–15 dp.
- **Fixed base, not floating:** floating bases (stick spawns where the thumb lands) suit players watching the phone; Muhammad watches the **laptop**. A fixed base in the same spot as the wheel lets him learn one muscle position. Generous ~150 dp touch area around a 120–130 dp base; knob travels 55–60 dp then clamps.
- **RUN = toggle.** GTA V sprint is hold-Shift; holding a second button while steering a joystick is impractical. Tap RUN once → Shift held in software, button stays lit showing `RUNNING`; tap again → off. (Settings can offer "Hold to run" later.)
- **JUMP = big momentary button** (Space, or Shift in the SA-Original profile).
- **No combat/aim buttons in v1** — GTA aiming needs a mouse. A centre touchpad for mouse look is the natural v2 addition (as in Bluetooth keyboard gaming modes).

### 6.5 Mode switching (Driving ⇄ On-Foot)

**Automatic detection is impossible in this architecture — stated plainly so the SRS never promises it.** The phone is a one-way HID peripheral: it sends keys to Windows; GTA sends nothing back. The app cannot know the game actually seated him in a car (he may press F too far from a car, or entry may be interrupted).

Design — **F button is the switch trigger, plus a manual correction switch:**

1. **F button (primary):** one large button in the *same position in both modes* (top-centre). Tap → send `F` → **optimistically swap the layout**. Matches reality ~95% of the time and matches RojX's instant GTA template switching.
2. **Mode pill (correction):** segmented pill `[ 🚶 On Foot | 🚗 Driving ]` beside/under F, showing the current mode in words + colour. If layouts desync (pressed F, missed the car), he taps the correct side — **this changes layout ONLY, sends no key.** Without this escape hatch, one desync traps a beginner.
3. **Placement safety:** top-centre is the hard-to-reach zone in a two-hand landscape grip — a *feature* for Enter/Exit (deliberate, never spammed while steering), but not in a top corner (notch/gesture risk) and never at the bottom (accidental pedal-zone presses). Inset ≥28 dp from the top edge, ≥64 dp tall, icon + words (`ENTER CAR` / `EXIT CAR`, flipping with mode) — a beginner won't remember what a bare "F" means.
4. **Feedback:** brief full-screen edge flash / banner (~600 ms) — `🚗 DRIVING` / `🚶 ON FOOT` — plus a haptic double-tick; the mode word also stays large in the top bar (he glances at the phone, reads the game on the laptop).

### 6.6 General landscape-controller guidance

- **Grip model:** two hands, thumbs only. Easy zone = bottom-left + bottom-right quadrants; hard zone = top corners + centre-top. Continuous controls (wheel, joystick, pedals, jump) → bottom corners. Rare/deliberate (F, mode, disconnect) → top-centre strip. Centre screen mostly empty (status/mode) — the game is on the laptop.
- **Touch targets:** Material's 48 dp minimum is a *menu* floor, far too small for gameplay. Pedals ~90×140 dp, wheel 200–230 dp diameter, joystick base 120–130 dp, action buttons 72–88 dp, F button ~120×64 dp. ≥8 dp separation everywhere; 12–16 dp between opposing controls.
- **Edges & system gestures:** all controls ≥24 dp in from left/right/bottom edges (Android gesture-navigation zones); run the controller screen in immersive sticky full-screen; respect the camera-cutout inset; lock landscape; keep the screen awake while connected; Back button on the controller screen = confirm dialog, not instant disconnect.
- **Connection status always visible:** top bar — `● Connected — [Laptop name]` (green) / `● Disconnected` (red). Bluetooth HID can drop silently; if he presses pedals on a dead connection with no visible state, he'll think the app is broken (DroidJoy's top complaint pattern). When disconnected, show a **big centre overlay that blocks the controls** — never let him "drive" into nothing.
- **Beginner visuals:** every control = icon + plain-language word (`RACE`, `BRAKE`, `JUMP`, `RUN`, `ENTER CAR`), with the key letter as small sub-text (`W`, `S`, `Space`) for learning. Consistent colour code across both modes: green = go, red/orange = brake/stop, blue = movement, amber = enter/exit. Dark background, large type (≥16 sp on buttons).
- **Multi-touch is mandatory:** wheel + gas + handbrake = 3 simultaneous touches. Single-touch handling is a common Flutter controller bug — test explicitly.

---

## 7. Risks and open questions

| # | Risk / question | Impact | Mitigation |
|---|---|---|---|
| R1 | **realme C67 firmware may not expose the HID-device role** (unverified) | Total failure of the primary approach on this phone | §5 gate test with an existing free HID app *before* building; SPP fallback ready |
| R2 | HID registration is exclusive and foreground-only | App must stay open; other HID apps conflict | Design around it (foreground controller, wake lock); tell the user to close other remote apps |
| R3 | `universal_bluetooth_classic` HID-device role unproven; API churn | Wasted effort if trusted blindly | Time-boxed spike only; hand-written Kotlin channel is the committed plan |
| R4 | Simultaneous-key rollover on the actual laptop/phone combo (W+A+Space) | Dropped keys while driving | Prototype test in the gate phase (hold-combo test in Notepad / key tester) |
| R5 | SPP fallback: SendInput may be ignored by GTA (DirectInput/UIPI/anti-cheat) | Fallback may fail in GTA Online specifically | Test fallback in GTA SA + GTA V Story Mode before promising; HID remains primary |
| R6 | SPP end-to-end latency unmeasured | Fallback feel unknown | Measure on the target laptop if the fallback is ever built |
| R7 | Mode desync (F pressed, entry failed) | Wrong layout shown | Mode pill (layout-only correction) — §6.5 |
| R8 | GTA SA Definitive sprint binding varies by build | Wrong Run/Jump labels for some SA users | Game profiles + labels driven by profile; keep profile editable in Settings |
| R9 | Horn/camera keys differ between GTA V and SA | Wrong extra buttons | Excluded from v1; add per-profile only in v1.1 |

**Unverified items (honest list):** realme C67 HID-device support (R1 — the big one); `universal_bluetooth_classic` device-role behaviour and popularity; SPP latency figures; HID latency figures come from consumer BT *keyboard* tests (same profile/polling, directionally valid); platform-channel line counts are an engineering estimate; GTA-specific SendInput behaviour is inferred, not directly tested by any source; the SDP-cache forget/re-pair rule is standard Bluetooth behaviour attested in embedded-HID docs.

---

## 8. Sources

**Bluetooth HID / Android API**
- Android `BluetoothHidDevice` API reference — https://developer.android.com/reference/android/bluetooth/BluetoothHidDevice
- Android Bluetooth permissions guide — https://developer.android.com/develop/connectivity/bluetooth/bt-permissions
- Remote Numpad (GitHub + HID teardown) — https://github.com/guillaumevpayet/remote-numpad · https://deepwiki.com/guillaumevpayet/remote-numpad/5.3-bluetooth-hid-connection
- Authorizer (HID keyboard app) — https://github.com/tejado/authorizer
- Cordless Play listing (pair-from-PC; Xiaomi HID firmware failure) — https://play.google.com/store/apps/details?id=com.cordless.app
- Dotori BT Mouse HID troubleshooting (one registration, API 28) — https://dev.to/droidactor/fix-your-phones-mouse-connection-22hd
- "How Bluetooth HID turns an Android phone into a keyboard" — http://umatechnology.org/how-bluetooth-hid-turns-an-android-phone-into-a-keyboard-for-another-device/
- realme C67 5G official specs (BT 5.2, Android 13, realme UI 4.0) — https://www.realme.com/in/realme-c67-5g/specs

**HID report format**
- HID keyboard report format (8-byte, modifier byte, 6KRO) — https://duonghao.dev/notes/en/stm32/hid-keyboard-report-format/
- USB HID keycode list (A `0x04`, D `0x07`, F `0x09`, S `0x16`, W `0x1A`, Space `0x2C`) — https://gist.github.com/ekaitz-zarraga/2b25b94b711684ba4e969e5a5723969b
- Microsoft USB HID → PS/2 scan-code table — https://download.microsoft.com/download/1/6/1/161ba512-40e2-4cc9-843a-923143f3456c/translate.pdf
- Bluetooth keyboard latency test (125 Hz, 8.5 ms avg, P95 14.3 ms) — https://keyboard-test.cn/en/blog/20/

**Flutter packages**
- `universal_bluetooth_classic` — https://pub.dev/packages/universal_bluetooth_classic
- `hid_tool` (host mode) — https://pub.dev/packages/hid_tool
- `virtual_gamepad` (Kotlin HID example) — https://pub.dev/packages/virtual_gamepad
- `flutter_bluetooth_serial_plus` (v0.5.7) — https://pub.dev/packages/flutter_bluetooth_serial_plus
- `bluetooth_spp` (v0.1.0) — https://pub.dev/packages/bluetooth_spp

**SPP / Windows / SendInput**
- Microsoft `KEYBDINPUT` / `KEYEVENTF_SCANCODE` — https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-keybdinput
- Microsoft `SendInput` (UIPI) — https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-sendinput
- SPP virtual COM port lesson (two COM ports, baud ignored) — https://makeabilitylab.github.io/physcomp/esp32/bluetooth-serial.html
- Windows Incoming COM port setup — https://community.element14.com/technologies/internet-of-things/b/blog/posts/standard-serial-over-bluetooth-on-windows-10
- Python keystrokes to games (DirectInput, scan codes, no guarantee) — https://www.codestudy.net/blog/use-python-to-send-keystrokes-to-games-in-windows/

**UI/UX and competitor apps**
- Monect PC Remote — https://play.google.com/store/apps/details?id=com.monect.portable
- DroidJoy — https://play.google.com/store/apps/details?id=com.grill.droidjoy · https://www.appbrain.com/app/droidjoy-gamepad-joystick/com.grill.droidjoy
- RojX (900° wheel, auto-centre, GTA template switching) — https://rojx.io/
- GamePad (BLE) — https://play.google.com/store/apps/details?id=cc.codeskool.gamepadapp
- GamepadOS wheel guide (rotation ranges by vehicle) — https://www.gamepad.space/guides/wheel-mode-truck-bus-sims
- Real Racing (Wikipedia; control methods) — https://en.wikipedia.org/wiki/Real_Racing_(video_game)
- Nintendo steering patent US7625287B2 (delta-angle method, centre on lift) — https://patents.google.com/patent/US7625287B2/en
- Touch & tilt controls guide (pedal placement, haptics) — https://www.velocityunleashed.ca/blog/touch-and-tilt-controls-guide
- Forza wheel tuning (dead zones) — https://support.forza.net/hc/en-us/articles/51642814113427-Forza-Horizon-6-on-Wheel-Advanced-Wheel-Tuning
- GTA V PC controls — https://keymap.io/controls/gta-v/
- GTA SA Definitive controls guide — https://www.magicgameworld.com/gta-san-andreas-definitive-edition-controls-guide-pc-xbox/
- GTA San Andreas original manual (Jump = Left Shift, Sprint = Space) — https://archive.org/download/Macintosh_Garden_Manuals_2021_G-I/GTA_San_Andreas_Manual.pdf
- Mobile touch ergonomics / virtual joysticks — https://www.dianyingsir.com/posts/mobile-web-touch-ergonomics-and-virtual-joysticks/
