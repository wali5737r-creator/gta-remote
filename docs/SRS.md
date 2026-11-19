# GTA Remote — Software Requirements Specification (SRS)

**Version:** 1.0 — 2026-11-19
**Status:** Draft for Muhammad's approval (build starts after the §9.1 hardware gate test passes)
**Companion document:** `research.md` (evidence, comparison, sources for every decision below)

---

## Khulasa (Roman Urdu Summary)

Ye app tumhare phone ko GTA ke liye **steering wheel** bana degi — laptop par GTA V ya GTA San Andreas chalega, aur tum phone se gari chalaoge.

- **Steering:** Screen ke aik side par bara steering wheel hoga. Ungli se **ghumaoge** to gari muregi. Koi tilt nahi — phone hilana nahi parega. Ungli uthate hi wheel khud seedha (centre) ho jayega, bilkul asli gari ki tarah.
- **Pedals:** Dusri side par do baray button honge — **RACE** (speed) aur **BRAKE**. Dabaye rakho to gari chalti rahegi, chhoro to rukegi. Aik chhota **HANDBRAKE** button bhi hoga tez mor ke liye.
- **Gari me bethna/utarna:** Upar aik bara button hoga — **ENTER CAR / EXIT CAR**. Dabane se banda gari me bethega ya utrega, aur screen khud badal jayegi.
- **Paidal (on foot):** Jab gari me na ho, screen badal jayegi — aik side **joystick** hoga chalne ke liye, dusri side **RUN** (bhagna) aur **JUMP** (chalang) ke button honge.
- **Connection: sirf Bluetooth.** Na internet chahiye, na WiFi, aur **laptop par koi program install nahi karna** — phone khud aik Bluetooth keyboard ban kar laptop se jur jayega, bilkul jaise asal Bluetooth keyboard jurta hai. Pehli dafa laptop ki Bluetooth settings se pair karna hoga (jaise koi bhi Bluetooth cheez pair karte hain), phir har dafa app me aik **Connect** button dabana hoga.
- **Game pehle select karna hoga** (GTA V ya GTA San Andreas) kyunke dono games me RUN aur JUMP ki keys ulta hain — app khud sahi keys laga degi aur button par sahi naam likha ayega.
- **Safety:** Agar Bluetooth beech me kat jaye, to saari keys khud chhut jayengi — gari apne aap aage nahi bhagegi. Screen par har waqt likha ayega ke connection hai ya nahi. Agar connection kat jaye to baray baray alfaaz me warning ayegi aur controls band ho jayenge, taake tumhe pata chal jaye.
- **Sab kuch free hai.** Koi ads nahi, koi paisay nahi, koi time limit nahi.
- **Aik zaroori test pehle hoga:** Kuch phones me ye Bluetooth keyboard wali sahulat company ki taraf se band hoti hai. Pehle hum aik maujooda free app se tumhare realme C67 par 30 minute ka test karenge ke ye sahulat hai ya nahi. Agar hui (umeed hai hogi), to app isi tareeqay se banegi. Agar na hui, to dusra tareeqa (Plan B) hai — us me laptop par aik chhota sa program chalana parega. Ye test app banane se **pehle** hoga taake waqt zaya na ho.

---

## 1. Introduction

### 1.1 Purpose

This document specifies **GTA Remote**: a free Android application that turns Muhammad's phone (realme C67, Android 13/14) into a touch game controller — steering wheel, pedals, and on-foot controls — for playing GTA V and GTA San Andreas on his Windows laptop. The phone connects to the laptop over **Bluetooth only** (no internet, no WiFi) and presents itself to Windows as a standard Bluetooth keyboard, so **no software is installed on the PC**.

This SRS is the contract for the build phase. Every technology decision in §6 is backed by `research.md`.

### 1.2 Scope

**In scope (v1):**

- Android app (Flutter UI + Kotlin platform channel) for a single phone + single Windows laptop.
- Bluetooth Classic HID Device profile: the phone registers as a Bluetooth keyboard; Windows uses its built-in HID driver.
- Driving mode: touch-rotated steering wheel (finger drag), RACE and BRAKE hold-pedals, HANDBRAKE button, ENTER/EXIT CAR button.
- On-foot mode: virtual joystick (8-way WASD), RUN toggle, JUMP button, ENTER CAR button.
- Manual mode switching driven by the ENTER/EXIT button plus a layout-only correction control.
- Game profiles for GTA V and GTA San Andreas (Original PC key mapping), selected before connecting.
- Settings: steering range, dead zone, sensitivity, flip controls (mirror layout), persisted on the phone.
- Safety behaviour: all keys release automatically on disconnect, app close, or control release.

**Out of scope (v1):**

- iOS, macOS, Linux, or console hosts.
- GTA Online guarantees under the fallback transport (see §6.3) — the primary HID transport is a real keyboard to the OS and has no such caveat, but anti-cheat behaviour is not ours to warrant.
- Analog steering/trigger axes (GTA keyboard control is binary; the app sends keyboard keys only).
- Mouse look / aiming / combat buttons (candidate v2: centre touchpad).
- Tilt/gyro steering (explicitly rejected by the user).
- Multiple phones, multiple PCs, cloud features, accounts, ads, in-app purchases, session limits.
- The SPP/Python fallback is **specified** in this SRS (§6.3) but **built only if** the §9.1 gate test fails.

### 1.3 Definitions

| Term | Meaning |
|---|---|
| **HID** | Human Interface Device — the standard Bluetooth/USB profile for keyboards, mice, gamepads |
| **HID Device role** | The phone acts *as* the keyboard (peripheral). The opposite — HID Host — is the phone talking *to* a keyboard; not used here |
| **BluetoothHidDevice** | Android API (API 28+, Android 9+) that lets an app register the phone as a HID device |
| **SDP record** | The Bluetooth service description the app registers; it tells Windows "this is a keyboard" (subclass `SUBCLASS1_KEYBOARD`) |
| **Report** | The 8-byte keyboard state packet sent to Windows on every key-state change (see FR-3) |
| **6KRO** | 6-key rollover — up to 6 simultaneous keycodes plus modifiers in one report; the boot-protocol limit |
| **SPP / RFCOMM** | Bluetooth Classic Serial Port Profile — a virtual serial (COM) port over Bluetooth; the fallback transport |
| **SendInput** | Windows API for injecting synthetic keystrokes; used only by the fallback's PC receiver |
| **Dead zone** | A small range around the wheel centre (or joystick centre) in which no key is sent |
| **Mode** | Which control layout is active: **Driving** or **On Foot** |
| **Game profile** | The key mapping + labels for the selected game (GTA V or GTA SA) |
| **Gate test** | The mandatory pre-build check (§9.1) proving the C67 supports the HID Device role |

### 1.4 References

- `research.md` — full research report with sources (Android API docs, pub.dev package pages, Microsoft docs, competitor app listings, GTA control references).
- Android `BluetoothHidDevice` API reference; Android Bluetooth permissions guide.
- USB HID Usage Tables (Usage Page 0x07) for keycodes.

---

## 2. Overall description

### 2.1 Product perspective

GTA Remote is a standalone, offline, single-purpose controller app. It has two runtime components:

1. **Flutter UI layer** — connect screen, controller screens (Driving / On Foot), settings. Handles all touch input and keeps a single "currently pressed keys" state.
2. **Kotlin platform component** — owns the Android Bluetooth HID stack: permissions, HID registration, pairing support, connection state, and sending keyboard reports. The Flutter layer talks to it over a MethodChannel (commands) and EventChannel (connection state).

Windows and GTA are unmodified. From their point of view, a Bluetooth keyboard has been paired.

### 2.2 User

One user: Muhammad, a beginner. He plays GTA V and GTA San Andreas on a Windows laptop; his phone is a realme C67. Design consequences: plain-language labels (words, not just key letters), very large touch targets, a guided first-time pairing flow, connection state always visible, and no configuration that can silently break the controls. The user reads Roman Urdu; in-app text is simple English words with icons (the established pattern from his previous apps), and this SRS carries a Roman Urdu summary (§0).

### 2.3 Operating environment

- Phone: realme C67 (4G or 5G variant), Android 13/14, realme UI 4.0, Bluetooth 5.0/5.2.
- Laptop: Windows 10/11 with Bluetooth; GTA V and/or GTA San Andreas (PC, keyboard controls at default bindings).
- Environment: same room, phone within a few metres of the laptop; **no internet or WiFi required at any point** (after the one-time app install).
- The app runs in the foreground with the screen on while playing (a hard constraint of the HID API — see §6.1).

### 2.4 Assumptions and constraints

- GTA keyboard bindings are at **game defaults**. If the user remaps keys in-game, the app's labels will not match (a Settings note states this).
- The phone's Bluetooth firmware exposes the HID Device role — **to be proven by the §9.1 gate test**, not assumed.
- Only one HID-device app may hold the registration; other remote/keyboard apps on the phone must be closed while GTA Remote runs.
- Everything is free: no paid plugins, no paid services, no ads SDK.
- The app is distributed as a sideloaded APK built via the project's existing free GitHub Actions pipeline.

### 2.5 Key design facts (from research)

- GTA keyboard steering is **binary** (A/D are on/off). The wheel therefore maps angle → key state; rotation range beyond ±90° adds finger work with zero precision gain.
- Bluetooth HID is **one-way**: the app sends keys; the game sends nothing back. The app **cannot detect** whether the character actually entered a car — mode switching is user-driven (§5.4).
- **GTA SA (Original PC) swaps Sprint and Jump vs GTA V** (SA: Sprint = Space, Jump = Left Shift; V: Sprint = Left Shift, Jump = Space). Game profiles (§5.1) exist because of this.

---

## 3. Key mappings

### 3.1 HID report format (both profiles)

Every state change sends one 8-byte report: byte 0 = modifier bitmask (Left Shift = `0x02`), byte 1 = `0x00`, bytes 2–7 = up to 6 keycodes.

| Control | HID usage |
|---|---|
| W / A / S / D | `0x1A` / `0x04` / `0x16` / `0x07` |
| F (enter/exit vehicle) | `0x09` |
| Space | `0x2C` |
| Left Shift | modifier byte bit `0x02` (not a keycode) |
| Enter (menus, bonus) | `0x28` |
| Escape (menus, bonus) | `0x29` |

### 3.2 Game profiles

| Action | GTA V profile | GTA SA profile (Original PC) |
|---|---|---|
| Accelerate / Move forward | W | W |
| Brake / Reverse / Move back | S | S |
| Steer / Move left | A | A |
| Steer / Move right | D | D |
| Enter / Exit vehicle | F | F |
| Handbrake (in vehicle) | Space | Space |
| Sprint / Run (on foot) | **Left Shift** | **Space** |
| Jump / Climb (on foot) | **Space** | **Left Shift** |

Button labels always follow the active profile (e.g. in the SA profile the JUMP button shows `JUMP (Shift)` and RUN shows `RUN (Space)`).

---

## 4. Screen inventory

| # | Screen | Purpose |
|---|---|---|
| S1 | Connect screen | Pick game, pick laptop, pair (first time) / connect, see status |
| S2 | Controller — Driving mode | Wheel + pedals + handbrake + enter/exit |
| S3 | Controller — On Foot mode | Joystick + run + jump + enter car |
| S4 | Settings | Steering feel, flip controls, profile defaults, help notes |

Detailed wireframes and rules are in §7.

---

## 5. Functional requirements

### 5.1 Connection and pairing

- **FR-1 — Game profile selection.** On the Connect screen, before connecting, the user selects the game: **[ GTA V ] [ GTA San Andreas ]**. The selection is remembered between sessions. The profile determines the Run/Jump key mapping and all button labels (§3.2).
- **FR-2 — Permission flow.** On first use, the app requests the Android 12+ runtime permissions it needs (`BLUETOOTH_CONNECT`, `BLUETOOTH_ADVERTISE`) with a short plain-language explanation shown *before* the system dialog ("GTA Remote needs Bluetooth permission to connect to your laptop. No internet is used."). If permission is denied, the app shows what to tap to allow it and does not proceed silently.
- **FR-3 — HID registration.** When the user opens the app (or taps Connect), the app registers itself as a Bluetooth HID keyboard (SDP name "GTA Remote", keyboard subclass, standard boot-keyboard report descriptor). The UI reflects the real registration state from the HID callbacks — never assumes success from a method call.
- **FR-4 — First-time pairing guide.** If no laptop is paired yet, the Connect screen shows numbered steps: (1) On your laptop open **Settings → Bluetooth & devices → Add device → Bluetooth**. (2) Select this phone. (3) Tap **Yes/Connect** on both screens if a code is shown. (4) Come back here and tap **Connect**. The app makes the phone discoverable while this guide is open.
- **FR-5 — Connect.** The Connect screen lists already-paired (bonded) devices; the user taps his laptop, then the big **Connect** button. The app performs register → connect in order and shows live progress (`Registering… → Connecting… → Connected`). On success it moves to the controller screen (On Foot mode by default — the player starts on foot).
- **FR-6 — Connection state always visible.** The controller screens show a permanent top-bar status: `● Connected — [Laptop name]` (green) or `● Disconnected` (red). The state comes from the HID connection callback, not from timers or guesses.
- **FR-7 — Reconnect.** If the connection drops, the app shows the disconnection overlay (FR-30) with a one-tap **Reconnect** button that repeats the register → connect sequence for the last-used laptop. Re-pairing is not required for an already-bonded laptop. If registration fails because another HID app holds it, the message says so in plain words ("Another remote app is using Bluetooth keyboard mode. Close it and try again.").

### 5.2 Driving mode

- **FR-8 — Steering wheel.** A wheel graphic (200–230 dp diameter) sits in the bottom corner on one side (default: left; mirrored by FR-25). The user rotates it by dragging anywhere on the wheel disc with one finger. Rotation is computed by the **delta-angle method**: each finger move's angular change around the wheel centre is added to the wheel angle, so grabbing the wheel at any point never makes it snap.
- **FR-9 — Steering range and key mapping.** Wheel angle is clamped to **±90°** by default (Settings option ±135°, FR-23). Mapping: angle < −(dead zone) → hold **A**; angle > +(dead zone) → hold **D**; inside the dead zone → neither key. Only one of A/D is ever sent at a time.
- **FR-10 — Spring return to centre.** When the steering finger lifts, A/D is released as the wheel crosses the dead zone and the wheel animates back to 0° in ~200 ms. The wheel never stays turned after release. A fixed ▲ marker on the bezel and a top spoke/dot on the wheel show straight-ahead.
- **FR-11 — RACE pedal.** A large hold-button (default: bottom-right, outer pedal, green, labelled `RACE` with sub-text `W`). Press-and-hold sends **W**; release removes it. The pedal captures its touch: sliding the thumb off the pedal does not cancel it; only lifting the finger releases it.
- **FR-12 — BRAKE pedal.** A large hold-button beside RACE (inner pedal, red/orange, labelled `BRAKE / REVERSE` with sub-text `S`). Press-and-hold sends **S**; release removes it. (In GTA, holding S while stopped reverses — the label teaches this; there is no separate reverse control.)
- **FR-13 — HANDBRAKE button.** A round hold/tap button above the BRAKE pedal (labelled `HANDBRAKE`, sub-text `Space`). While held, **Space** is included in the report.
- **FR-14 — Simultaneous driving input.** Wheel + RACE + HANDBRAKE (and any other combination up to the 6-keycode limit) must work at the same time: each control owns the finger that touched it, and every change rebuilds and sends the complete pressed-key set as one report.

### 5.3 On-foot mode

- **FR-15 — Movement joystick.** A fixed-base virtual joystick occupies the same screen position/size zone as the wheel (so the thumb does not relearn position on mode switch). Base 120–130 dp, touch area ~150 dp around it, knob travel 55–60 dp. The stick angle is quantised to **8 directions** (45° sectors), sending the matching WASD combination (e.g. up-right = W+D). Inside the radial dead zone (~13 dp) no movement keys are sent.
- **FR-16 — RUN toggle.** A large button (labelled `RUN`, with the profile's key as sub-text) toggles sprint: tap once → the profile's sprint key (GTA V: Left Shift; GTA SA: Space) is held continuously and the button stays lit showing `RUNNING`; tap again → released. RUN stays as set while the joystick is used; it is not auto-cancelled in v1.
- **FR-17 — JUMP button.** A large momentary button (labelled `JUMP`, with the profile's key as sub-text — Space for GTA V, Shift for GTA SA). Tap/hold sends the jump key; release removes it.
- **FR-18 — On-foot simultaneous input.** Joystick movement + RUN (toggled) + JUMP must combine correctly in the same report (e.g. W + Shift + Space held together = running jump forward).

### 5.4 Mode switching

- **FR-19 — ENTER/EXIT button.** One large button (≥120×64 dp) at the **top-centre**, in the identical position in both modes, inset ≥28 dp from the top edge. In On Foot mode it is labelled `ENTER CAR`; in Driving mode, `EXIT CAR`; sub-text `F`. Tapping it: (a) sends a tap of the **F** key (press report, then release report), and (b) switches the layout to the other mode.
- **FR-20 — Mode pill (layout-only correction).** A segmented control `[ 🚶 On Foot | 🚗 Driving ]` beside/under the ENTER/EXIT button shows the current mode. Tapping a side switches the **layout only — it sends no key**. This is the recovery path if the layout and the game disagree (e.g. F was pressed too far from a car).
- **FR-21 — Mode-change feedback.** On every mode change the app shows a brief (~600 ms) banner/edge flash — `🚗 DRIVING` or `🚶 ON FOOT` — plus a short haptic double-tick, and the current mode word stays large in the top bar.
- **FR-22 — Clean switch.** Switching modes releases all keys of the old mode before the new layout activates (e.g. switching to On Foot while RACE was held must not leave W stuck). The RUN toggle resets to off on every mode switch.

### 5.5 Settings

- **FR-23 — Steering range.** Choice: **±90° (default)** or **±135°**.
- **FR-24 — Steering feel.** Dead zone slider 0–15° (default 7°); sensitivity as three buttons — **Low / Medium (default) / High** — scaling how far the wheel turns for a given finger movement (0.7× / 1.0× / 1.4×).
- **FR-25 — Flip controls.** A switch that mirrors the controller horizontally (wheel/joystick on the right, pedals/actions on the left) for left-handed comfort.
- **FR-26 — Persistence.** All settings, the game profile, and the last-used laptop are saved on the phone and restored on the next launch.
- **FR-27 — Help notes.** Settings includes short plain-language notes: "Keep GTA keys on default settings", "Keep this app open while playing", "If connection fails, close other remote apps", and the battery tip ("Set GTA Remote battery to Unrestricted if the connection drops when the screen dims" — noting the screen is kept awake while connected, FR-31).

### 5.6 Safety and robustness

- **FR-28 — Release on disconnect.** If the Bluetooth connection drops for any reason, the app immediately clears its pressed-key state. Because HID reports are state-based and the link is gone, no key can remain held on the PC side beyond the connection loss itself; on reconnect the app sends one all-released (all-zero) report before any new input, so the game starts from a clean state.
- **FR-29 — Release on exit/background.** If the app is backgrounded, closed, or the user taps Disconnect, the app sends an all-released report (if still connected), then disconnects and unregisters. (The HID API also auto-unregisters a backgrounded app; the UI must handle returning to the foreground by re-registering and showing the true state.)
- **FR-30 — Disconnected overlay.** Whenever the controller screen is shown while disconnected, a large centre overlay blocks all controls: `⚠ Connection lost` + **Reconnect** button. Controls never accept input while disconnected.
- **FR-31 — Screen and orientation.** The controller screens lock to **landscape**, run in immersive full-screen, and **keep the screen on** while connected. All controls sit ≥24 dp from the screen edges (gesture-navigation zones) and respect the camera-cutout inset.
- **FR-32 — Safe back behaviour.** Pressing Android Back on a controller screen asks "Disconnect and go back?" (Confirm / Cancel) instead of disconnecting instantly.
- **FR-33 — Press feedback.** Every press gives three feedbacks: instant visual change (fill/scale), one short haptic tick (15–25 ms) on press-down, and a persistent lit state while held. Mode changes use a double-tick (FR-21).
- **FR-34 — Labels.** Every control shows an icon + a plain-language word (`RACE`, `BRAKE / REVERSE`, `HANDBRAKE`, `JUMP`, `RUN`, `ENTER CAR`, `EXIT CAR`) with the keyboard key as small sub-text. Colour code is consistent across both modes: green = go, red/orange = brake/stop, blue = movement, amber = enter/exit. Button text ≥16 sp; dark background theme.

---

## 6. Technology decisions

### 6.1 Primary transport — Bluetooth Classic HID Device (decided)

- **Stack:** Flutter UI + **hand-written Kotlin platform channel** using Android's `BluetoothHidDevice` (API 28+; the C67 runs API 33/34). No third-party Bluetooth plugin is on the critical path.
- **Why:** (1) **Zero PC software** — Windows' built-in HID driver does everything; this is the headline requirement. (2) The phone is indistinguishable from a real keyboard, so GTA's DirectInput/Raw Input and any anti-cheat see hardware input — immune to the injected-input failure class. (3) 6KRO + modifiers covers every GTA combination (worst case 4 keycodes + Shift). (4) Latency ~8–15 ms (BT HID 125 Hz reporting) is proven adequate for driving games. (5) The Kotlin surface is small and documented, with open-source precedents in the exact Flutter+Kotlin shape (Remote Numpad; `virtual_gamepad` example).
- **Accepted constraints:** the app must stay foreground (API auto-unregisters otherwise — acceptable for a controller; FR-29/FR-31 design around it); only one HID app may be registered at a time (FR-7 error message covers it); first pairing is initiated from Windows (FR-4 guides it).
- **Plugin spike (optional, time-boxed):** `universal_bluetooth_classic` (pub.dev, v1.3.0, ~2 months old) advertises HID SDP registration + `sendHidReport`. It may be spiked for half a day; if it does not demonstrably register the phone as a keyboard to Windows, it is discarded and the hand-written channel ships. The build does **not** depend on it.

### 6.2 Report protocol (primary)

State-based, as §3.1: the app maintains the pressed-key set; every touch down/up/move that changes the set rebuilds the 8-byte report and calls `sendReport`. No event queue, no repeats — the snapshot model self-corrects any missed update on the next change.

### 6.3 Fallback transport — SPP/RFCOMM (specified, built only if the gate fails)

- **Trigger:** the §9.1 gate test shows the C67 cannot act as a HID device.
- **Phone:** `flutter_bluetooth_serial_plus` (v0.5.7, maintained fork) as an SPP **client** connecting to the laptop's SPP service; sends full touch-state frames on every change.
- **PC:** a small Python receiver — `pyserial` reads the Windows **Incoming** Bluetooth COM port; `ctypes` SendInput with `KEYEVENTF_SCANCODE` presses/releases keys (scan codes: W `0x11`, A `0x1E`, S `0x1F`, D `0x20`, F `0x21`, Space `0x39`, L-Shift `0x2A`). Receiver must run before the game, at the same integrity level as the game, and release all keys if no frame arrives for >0.5 s.
- **Accepted costs (documented for the user before building):** a PC program to install (Python + `pip install pyserial`) and run every session; manual Incoming COM-port setup in Windows; COM numbers can change; injected input may be ignored by some games — the fallback must be tested in GTA SA and GTA V Story Mode before any promise, and GTA Online is explicitly not guaranteed.
- The Flutter UI, layouts, profiles, and settings are **identical** under either transport; only the transport layer behind the channel changes.

### 6.4 What is NOT used, and why

- **WiFi/UDP (the superseded v1 draft):** excluded by the user's requirement — Bluetooth, without internet.
- **BLE HID-over-GATT:** also needs no PC software, but requires hand-managing GATT services/advertising/bonding on Android — more work and less trodden than Classic HID. Research only if Classic HID fails the gate *and* SPP proves unworkable in GTA.
- **HID host-mode plugins** (`hid_tool` etc.): wrong direction (they let the phone talk *to* a keyboard).
- **XInput/gamepad emulation:** GTA Remote's spec is GTA's keyboard bindings; a gamepad report adds a descriptor and mapping layer with no benefit for these two games' keyboard controls.

---

## 7. UI specification (screen by screen)

Global rules (all controller screens): landscape locked, immersive full-screen, screen kept awake, dark theme, controls ≥24 dp from edges, ≥8 dp separation (12–16 dp between opposing controls), multi-touch with per-control finger ownership, colour code per FR-34, top bar always visible: `● Connected — [Laptop name]` left, current mode in large words centre, Settings + Disconnect icons right.

### 7.1 S1 — Connect screen

```
Portrait or landscape. Simple, one column, big buttons.

┌──────────────────────────────────────────┐
│            🚗  GTA REMOTE                │
│   Phone steering wheel for GTA on your   │
│   laptop — Bluetooth only, no internet   │
│                                          │
│   Which game will you play?              │
│   ┌──────────────┬──────────────────┐    │
│   │   GTA V  ●   │  GTA San Andreas │    │
│   └──────────────┴──────────────────┘    │
│                                          │
│   Your laptop:                           │
│   ┌──────────────────────────────────┐   │
│   │  💻 LAPTOP-XYZ            Paired │   │
│   └──────────────────────────────────┘   │
│                                          │
│   ┌──────────────────────────────────┐   │
│   │          CONNECT  ▶              │   │  <- biggest button
│   └──────────────────────────────────┘   │
│                                          │
│   First time? Pair like this:            │
│   1. Laptop: Settings → Bluetooth &      │
│      devices → Add device → Bluetooth    │
│   2. Select this phone, tap Yes on both  │
│   3. Come back and tap CONNECT           │
│                                          │
│   Status: Not connected                  │
└──────────────────────────────────────────┘
```

- Behaviour: FR-1 (game choice at top — it changes key mappings, so it comes before Connect), FR-4 (pairing steps always visible when no paired laptop is chosen; the phone is discoverable while this screen is open), FR-5 (device list shows bonded devices only — no scanning UI needed), FR-2 (permission explanation before the system dialog).
- States: `Not connected` / `Registering…` / `Connecting…` / error in plain words with a **Try again** button (including the "another remote app" message from FR-7).
- On successful connect → go to S3 (On Foot) — the player character starts on foot.

### 7.2 S2 — Controller: Driving mode

```
Landscape — both hands. Wheel LEFT, pedals RIGHT (mirrored if Flip controls is ON).

┌──────────────────────────────────────────────────────────────────────┐
│ ● Connected: LAPTOP-XYZ        🚗 DRIVING          ⚙ Settings  ⏻   │ <- top bar, always visible
│                                                                      │
│                  ┌─────────────────────────┐                         │
│                  │  🚗 EXIT CAR            │   <- F button, top-     │
│                  │      [ F ]  120x64dp    │      centre, inset      │
│                  └─────────────────────────┘      >=28dp from top     │
│                  [ 🚶 On Foot | 🚗 Driving ● ] <- mode pill (layout only)
│                                                                      │
│   ╭─────────╮                                        ┌──────────┐    │
│  ╱     ▲     ╲      <- fixed bezel ▲ = straight      │ HANDBRAKE│    │
│ │   ╭─────╮   │                                       │ (Space)  │    │
│ │   │  ◉  │   │   WHEEL 210-230dp diameter            │  72dp ⌀  │    │
│ │   ╰─────╮   │   Drag anywhere on the disc           └──────────┘    │
│  ╲    ╭─────╯  ╱    to ROTATE it. ±90°, springs       ┌────┬───────┐  │
│   ╰─────────╯       back to centre on release        │    │       │  │
│   LEFT THUMB                                         │BRKE│  RACE │  │
│                                                      │ S  │   W   │  │
│        (small steering-angle readout                 │RED │ GREEN │  │
│         in centre screen, e.g. "◀ 45°")              │84x │ 92x   │  │
│                                                      │130 │ 145dp │  │
│                                                      └────┴───────┘  │
│                                                       RIGHT THUMB    │
└──────────────────────────────────────────────────────────────────────┘
```

- Wheel: FR-8/FR-9/FR-10 (delta rotation, ±90° clamp, 7° default dead zone, ~200 ms spring return, centre marks).
- Pedals: FR-11/FR-12 — BRAKE inner (red), RACE outer (green, taller); 12–16 dp gap; touch-capture until finger lift.
- HANDBRAKE: FR-13, round button above BRAKE.
- F button + mode pill: FR-19/FR-20 — same position as S3.
- Centre of the screen stays mostly empty (angle readout only) — the user's eyes are on the laptop.

### 7.3 S3 — Controller: On Foot mode

```
Landscape — SAME top bar and SAME F-button position as Driving.

┌──────────────────────────────────────────────────────────────────────┐
│ ● Connected: LAPTOP-XYZ        🚶 ON FOOT           ⚙ Settings  ⏻   │
│                                                                      │
│                  ┌─────────────────────────┐                         │
│                  │   🚗 ENTER CAR          │   <- SAME F button,    │
│                  │      [ F ]  120x64dp    │      label flips with  │
│                  └─────────────────────────┘      mode               │
│                  [ 🚶 On Foot ● | 🚗 Driving ] <- mode pill          │
│                                                                      │
│      ╭───────────╮                               ┌────────┐          │
│    ╱   joystick    ╲                             │  JUMP  │  88dp ⌀  │
│   │   base 125dp    │                            │ (Space)│  BLUE    │
│   │      ╭───╮      │      MOVE                  └────────┘          │
│   │      │ ◉ │<── knob 60dp, slides 55dp          ┌────────┐          │
│   │      ╰───╯      │      8-way WASD             │  RUN   │  80dp ⌀  │
│    ╲               ╱                             │ TOGGLE │  AMBER   │
│      ╰───────────╯                               │(Shift) │ lit=ON   │
│   LEFT THUMB                                     └────────┘          │
│                                                     RIGHT THUMB    │
│   Touch area ~150dp around base.                 Labels follow the   │
│   Joystick sits where the wheel was.             game profile: GTA SA│
│                                                  shows JUMP (Shift)  │
│                                                  and RUN (Space).   │
└──────────────────────────────────────────────────────────────────────┘
```

- Joystick: FR-15 (fixed base where the wheel was, 8-way quantisation, ~13 dp dead zone).
- JUMP upper-right (most-used on-foot action), RUN toggle lower-right, lit + `RUNNING` while on: FR-16/FR-17.
- Labels are profile-driven (§3.2) — in the GTA SA profile the same two buttons read `JUMP (Shift)` and `RUN (Space)`.

### 7.4 S4 — Settings

```
┌──────────────────────────────────────────┐
│  ⚙ Settings                              │
│                                          │
│  Steering                                │
│   Wheel turn:   ( ● ±90° )  ( ○ ±135° )  │
│   Sensitivity:  [ Low | Medium | High ]  │
│   Dead zone:    ─────●──────  7°         │
│                                          │
│  Controls                                │
│   Flip controls (wheel on right): [ ○ ]  │
│                                          │
│  Game                                    │
│   Default game: [ GTA V | GTA SA ]       │
│   (Keys in GTA must be on Default.)      │
│                                          │
│  Help                                    │
│   • Keep this app open while playing.    │
│   • Close other remote apps if Connect   │
│     fails.                               │
│   • If connection drops when the screen  │
│     dims: Settings → Apps → GTA Remote → │
│     Battery → Unrestricted.              │
└──────────────────────────────────────────┘
```

- Implements FR-23 … FR-27. Reachable from the Connect screen and the controller top bar; changing settings mid-session never drops the connection and never leaves a key held (any change first sends an all-released report).

---

## 8. Non-functional requirements

- **NFR-1 — Latency.** End-to-end (finger move → key state on PC) target **≤ 30 ms**, expected ~8–15 ms from the BT HID report interval (125 Hz). No artificial throttling: reports are sent immediately on state change.
- **NFR-2 — Offline.** The app must work with **no internet and no WiFi** — no network calls, no analytics, no ads, no licence checks. Bluetooth only.
- **NFR-3 — Free.** Total cost of the system is zero: no paid plugins, SDKs, services, or PC software (primary transport). The fallback's only dependency (pyserial) is free and open-source.
- **NFR-4 — Reliability of input state.** The state-snapshot report model (FR-3/§6.2) guarantees the PC's view of held keys converges to the phone's on every change; disconnect/exit paths always end in an all-released state (FR-28/FR-29).
- **NFR-5 — Battery.** Screen stays on while connected (required for control), but the app draws a mostly-dark UI; no background work when disconnected. Wake lock is held only while connected.
- **NFR-6 — Compatibility.** minSdk 28 (Android 9) for the HID API; target device realme C67 on Android 13/14. Windows 10/11 with any standard Bluetooth adapter supporting HID hosts.
- **NFR-7 — Usability.** A first-time user reaches "connected and driving" using only the on-screen pairing guide (FR-4), with no external instructions. All gameplay controls ≥72 dp; pedals/wheel/joystick substantially larger (§7).
- **NFR-8 — Privacy.** The app collects nothing: no accounts, no identifiers, no usage data. Permissions are Bluetooth-only (plus vibration). Nothing leaves the phone except HID reports to the paired laptop.
- **NFR-9 — Build & delivery.** Built with the project's free GitHub Actions pipeline (as with Muhammad's previous apps) and delivered as an installable APK. Version 1 has no auto-update; fixes ship as new APKs.

---

## 9. Acceptance criteria and test checklist

### 9.1 ⚠️ Gate test (BEFORE building — must pass to use the primary transport)

- [ ] Install an existing free HID-keyboard app (e.g. Cordless free tier / Remote Numpad) on the realme C67; close all other remote/HID apps.
- [ ] Pair **from Windows** (Add device → phone), confirm passkey on both sides.
- [ ] Type from the phone into Notepad on the laptop — characters appear.
- [ ] Hold two keys at once from the phone (e.g. W+A) — both register (check with a key-state viewer or in-game).
- [ ] **Pass** → build the primary HID design. **Fail** (e.g. "Incorrect PIN", pairs as phone-only) → stop; switch to the §6.3 SPP fallback plan and re-test GTA SA + GTA V Story Mode input before committing.

### 9.2 Connection tests

- [ ] Fresh install: permission explanation appears before the system dialog; denying permission shows guidance, not a dead end.
- [ ] First pairing following only the in-app guide (FR-4) succeeds.
- [ ] Connect from the bonded list reaches `Connected` and opens the controller in On Foot mode.
- [ ] Disconnect via the app's button: keys released, state shows Disconnected.
- [ ] Kill Bluetooth on the laptop mid-session → phone shows the disconnected overlay within a few seconds; controls are blocked; Reconnect works after Bluetooth returns.
- [ ] Another HID app holding the registration → Connect fails with the plain-language FR-7 message.
- [ ] Background the app mid-session, return → app re-registers and shows the true state (reconnect required, no false "Connected").
- [ ] Re-pair cycle: after "Remove device" in Windows + forget on phone, pairing from scratch works again.

### 9.3 Driving tests (in GTA, both profiles where relevant)

- [ ] Drag wheel left/right: car steers; grabbing the wheel at the bottom does not snap it.
- [ ] Release the wheel mid-turn: wheel returns to centre in ~200 ms and the car stops turning (A/D released).
- [ ] Hold RACE: car accelerates; release: it stops accelerating. Hold BRAKE while stopped: car reverses.
- [ ] **Simultaneous:** hold RACE + steer + tap HANDBRAKE together — all three register (powerslide turn works); no key sticks afterwards.
- [ ] Dead zone: small wheel movements near centre do not steer.
- [ ] Thumb slides off RACE while holding: RACE stays on until the finger lifts.
- [ ] EXIT CAR button: character exits, layout switches to On Foot, no keys stuck.

### 9.4 On-foot tests

- [ ] Joystick: 8 directions all walk correctly (diagonals = two keys); centre = stand still.
- [ ] RUN toggle: tap once → character keeps sprinting while moving (button lit, `RUNNING`); tap again → walks.
- [ ] JUMP: character jumps. **Profile check — GTA V profile: JUMP sends Space, RUN sends Shift. GTA SA profile: JUMP sends Shift, RUN sends Space** (test in the actual games).
- [ ] Running jump: joystick forward + RUN on + JUMP = sprint-jump (3 inputs combined).
- [ ] ENTER CAR near a car: character enters, layout switches to Driving.

### 9.5 Mode-switch and desync tests

- [ ] Press ENTER CAR while too far from any car (game ignores it): layout wrongly shows Driving → user taps the mode pill's **On Foot** side → layout corrects, **no key is sent** by the pill.
- [ ] Switch modes while RACE is held → W is not stuck after the switch; RUN toggle is off after any switch.
- [ ] Mode banner + haptic double-tick fire on every switch; mode word in the top bar is correct at all times.

### 9.6 Safety tests

- [ ] Hold RACE, then walk out of Bluetooth range / turn off laptop Bluetooth: car stops (no runaway), phone shows the disconnected overlay.
- [ ] Hold RACE, then press Android Home: on return, no key is stuck; state is truthful.
- [ ] Hold RACE, then tap Disconnect: car stops immediately.
- [ ] Back button on the controller asks for confirmation; Cancel keeps playing.
- [ ] Screen never sleeps while connected; phone stays in landscape; controls unreachable by edge gestures (no accidental Back while steering).

### 9.7 Settings tests

- [ ] ±135° range, dead-zone slider, and sensitivity Low/High each produce a clearly different wheel feel and persist after app restart.
- [ ] Flip controls mirrors both controller modes and persists.
- [ ] Game profile + last laptop persist after restart.
- [ ] Changing a setting mid-session sends an all-released report first (no stuck key).

### 9.8 Environment tests

- [ ] Full session with phone in **airplane mode + Bluetooth on**: everything works (proves NFR-2, no internet/WiFi).
- [ ] Session length ≥ 30 minutes of continuous driving with no session limit, no ads, no prompts.
- [ ] Works in both GTA V and GTA San Andreas on the target laptop.

---

## 10. Decisions Muhammad must confirm before the build

1. **The gate test (§9.1)** needs ~30 minutes with the actual phone + laptop and an existing free HID app. It decides HID vs the SPP fallback — building starts after it.
2. **GTA San Andreas version:** is his SA the **Original** PC version or the **Definitive Edition**? (Definitive's Jump = Space like GTA V; Original swaps Jump/Run. The SRS ships both profiles' labels from the selected game, but the SA profile defaults depend on his version.)
3. **Wheel side:** default is wheel on the **left**, pedals on the right. Flip is in Settings either way — no decision blocks the build, but his preference sets the default.
4. **Scope confirmation:** v1 has **no aiming/combat buttons** (GTA aiming needs a mouse). If he wants shooting/aiming from the phone, that's a v2 addition (centre mouse touchpad) — confirm v1 without it.
