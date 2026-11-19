# GTA Remote — User / Tester / Expert Review & Improvements

**Date:** 2026-11-19
**Scope:** Full walk of `lib/`, the Kotlin channel, and the approved mockup
through three lenses — first-time **user**, QA **tester**, domain
**expert** — after the connection-flow debugging and the QA_REPORT fixes.
All QA_REPORT fixes (early registration, no unregister on pause, waiter
list, auto-refresh, fast-fail wait, permission Settings path) were checked
and are **not regressed** by anything below.
**Method:** Static review (no SDK/device on this machine, same limit as
the QA audit). Everything marked "changed" is implemented in code,
uncommitted — the main agent owns git/CI.

---

## AS A USER (beginner, first time, Roman Urdu)

### U1 — Paired-device list mixed the laptop with earbuds and other phones — FIXED
**Problem:** The list showed *every* bonded device with the same laptop
icon. In the real first session the list contained earbuds ("i12") and
someone else's phone next to the actual laptop — a beginner cannot tell
which row is his laptop, and tapping the wrong one burns a 20 s timeout.
**Fix:** The Kotlin side now also returns each device's Bluetooth
**major class**. The Dart list (a) sorts computers first, (b) shows a
matching icon per device (laptop / phone / headphones / bluetooth),
(c) auto-selects the single computer in the list even when earbuds are
also paired, and (d) marks the previously used laptop with an amber
**"Aakhri laptop"** chip. Auto-select still never overrides a manual
tap (QA C2 rule kept).

### U2 — Pairing guide was buried exactly when a first-timer needs it — FIXED
**Problem:** With no laptop paired, the screen order was: game cards →
"no laptop found" note → grey CONNECT → status → *then* the guide at the
very bottom. The user's actual next step (pair from the laptop) was the
last thing on the screen.
**Fix:** When permission is granted and no device is paired yet, the
pairing guide now renders **directly under the laptop section, before
the CONNECT button**. Once a laptop exists it returns to the bottom as
reference.

### U3 — No help where failures actually happen — FIXED
**Problem:** Troubleshooting notes existed only inside Settings. Connect
failures happen on the Connect screen, and the single most common cause
(a stale pairing made in the wrong order — the exact bug hit live) was
only mentioned inside one error string.
**Fix:** New collapsible card on the Connect screen —
**"Masla aa raha hai? Ye check karo"** — with the five most likely
causes/fixes in order: Remove device + re-pair with the app open,
laptop Bluetooth on + Add-device page open, close other remote/keyboard
apps, move closer / toggle Bluetooth, and the battery-Unrestricted tip.

### U4 — Grey CONNECT button didn't say why it's grey — FIXED
**Problem:** With devices listed but none selected, CONNECT just sat
grey with no explanation.
**Fix:** A yellow hint line appears under the button in exactly that
state: *"Pehle upar se apna laptop select karo, phir CONNECT dabao."*

### U5 — No confirmation moment on entering the controller — FIXED
**Problem:** After a successful connect the controller opened silently
in On Foot mode; the only success signal was the small status pill.
**Fix:** On entry, the controller now shows the mode banner once
("🚶 ON FOOT", same ~650 ms banner as mode switches), factored into a
shared `_showBanner()` — the user immediately knows: connected, and
which mode he's in.

### U6 — Long names could break rows — FIXED
Device names in the list are now single-line with ellipsis, and the
controller's status pill caps the laptop name at 200 dp with ellipsis
(see also T4).

---

## AS A TESTER (multi-touch, edge cases, hostile conditions)

### T1 — Steering wheel used the gesture arena; every other control didn't — FIXED (core finding)
**Problem:** Pedals, HANDBRAKE/JUMP, ENTER/EXIT and the joystick all use
raw `Listener` with per-pointer ownership — but the wheel used
`GestureDetector` pan. Consequences for the core FR-14 interaction
(steer with one thumb, hold RACE with the other, tap HANDBRAKE):
- Pan only starts after ~18 dp of drag (**touch slop**): the first
  degrees of every steering motion were swallowed — steering felt late
  and vague.
- The pan recognizer lives in the gesture arena; arena losses surface
  as `onPanCancel`, an extra failure mode the other controls don't have.
**Fix:** The wheel now uses a raw `Listener` with single-pointer
ownership, identical in kind to the joystick: down stops the spring and
anchors the finger angle, moves delta-rotate, up/cancel springs back.
**The entire driving surface is now arena-free** — simultaneous
independent touches cannot compete. Delta-angle math, centre-ignore
radius, clamp, sensitivity and spring behaviour are unchanged.

### T2 — A/D flicker at the dead-zone boundary — FIXED
**Problem:** With a single engage/release threshold, a wheel hovering at
the dead-zone edge (normal hand tremor) toggled A/D many times a second
— a burst of HID reports and a twitching car.
**Fix:** Hysteresis in the wheel's key evaluation: engage at the full
dead zone, release at dead zone − min(2°, 35% of dead zone). Direct
A↔D crossings still switch immediately. With dead zone 0 the behaviour
is identical to before.

### T3 — Large system font sizes could overflow fixed-size controls — FIXED
**Problem:** The controller uses fixed heights (RUN 118×74, pedals,
pills). At accessibility font scales (1.3×+) the two-line RUN button and
pedal labels would overflow their boxes (RenderFlex errors / clipped
text) mid-game.
**Fix:** The controller screen clamps the effective text scale to
**0.85–1.15** via a `MediaQuery` override — the layout can never break
during gameplay. The Connect/Settings screens stay fully scalable
(they scroll and wrap, so they don't need the clamp).

### T4 — Long laptop name could push the mode pill off-screen — FIXED
**Problem:** The top bar was `Row[pill, Spacer, mode pill]`; a long
device name (e.g. "DESKTOP-3F8K2P1-LONGNAME") sized the pill by content
and could overflow the row.
**Fix:** Status pill is width-bounded (`Flexible` slot + name capped at
200 dp with ellipsis); the mode pill always keeps its place.

### T5 — Short landscape screens could collide with the top bar — FIXED
**Problem:** On short landscape heights (~330 dp and below — small/old
phones), the ~300 dp driving cluster anchored at the bottom reaches to
within a few dp of the top bar; ENTER CAR could slide under the mode
pill.
**Fix:** Below 360 dp height the wheel's minimum size drops (185→165)
and the button clusters scale to 0.86 around their anchored corner.
The target device (C67, ~880×360 dp landscape) is unaffected.

### T6 — RUN toggle fired on tap-release, unlike every other control — FIXED
**Problem:** RUN was a `GestureDetector.onTap` — it toggled only when
the finger *lifted*, adding latency and behaving differently from the
pedals/buttons (which act on press-down).
**Fix:** RUN is now `Listener`-based, toggles on pointer-down, with the
same press-scale feedback as the round buttons.

### T7 — Small tap targets next to gameplay — FIXED (minor)
Ghost buttons (Settings / Disconnect) looked 42 dp but now also *touch*
at 48 dp (transparent margin). Mode-pill segments got slightly taller
padding (7→10 dp vertical). Disconnect remains protected by its
confirmation dialog, so an accidental tap still can't drop a session.

### Checked and found correct (no change)
- Rapid repeated CONNECT taps — guarded synchronously (QA M5).
- Rotate during connect — Connect is portrait-locked, controller
  landscape-locked; no mid-flow rotation states exist.
- Bluetooth toggled mid-flow — state comes only from callbacks (QA);
  the controller's disconnect overlay + Reconnect covers mid-game loss.
- Empty states — no permission / no devices / empty name all have
  dedicated cards or fallbacks.
- Joystick sector-boundary flicker (W vs W+D): both sets contain the
  primary direction key, so the car never stutters; a report per change
  is cheap and correct. Hysteresis deliberately **not** added here.
- Steering readout no longer rebuilds the screen (see E2) and is
  `IgnorePointer`, so it can never block a control.

---

## AS AN EXPERT (HID / controller polish)

### E1 — Report behaviour — verified, no change
Reports are strictly event-driven (state-snapshot on change, signature
dedupe, 6-key cap) — matching NFR-1's "no artificial throttling".
Steering is digital (A/D), so there is no analogue stream to rate-limit;
the host's 125 Hz HID polling is the pacing. QoS/SDP values are the
standard AOSP sample set already verified in the QA audit. Nothing to
tune without inventing numbers.

### E2 — Angle readout rebuilt the whole controller on every degree — FIXED
**Problem:** `onAngleChanged` called `setState` on the controller
state, rebuilding the entire control tree up to ~180 times per wheel
sweep — wasted frames exactly while the user is steering.
**Fix:** The angle now flows through a `ValueNotifier<double>`; only
the small readout `Text` rebuilds (`ValueListenableBuilder`), and the
readout is wrapped in `IgnorePointer`.

### E3 — Settings defaults for a beginner — verified, one note
Range ±90°, sensitivity Medium, dead zone 7° are sensible out-of-box
values, and with T2's hysteresis the 7° default no longer flickers.
Flip-controls off by default is right for the (right-handed) user.
No default changed.

### E4 — Steering sensitivity "curve" — analysed, deliberately NOT changed
The wheel is delta-based and its output is binary (A/D). A progressive
curve would only change how fast the *graphic* rotates relative to the
finger — it cannot change the car's steering, which is a key press.
The real feel levers (dead zone, hysteresis, spring timing, sensitivity
multiplier) already exist and are now correct. Changing the visual
curve blind — with no device here to feel it — risks making the wheel
feel disconnected from the finger. **Recommendation:** if Muhammad
reports the wheel "too slow to full lock" in real play, add a mild
progressive delta factor (×1.0 at centre → ×1.3 at full lock) behind
the existing sensitivity setting.

### E5 — Connection-quality indicator — deliberately NOT added
Over the HID profile there is no public API for link quality/RSSI of
the active connection; any gauge would be invented data, which breaks
this app's own rule (FR-6: state only from real callbacks). The honest
indicators already exist: live Connected/Connecting/Disconnected pill
from callbacks + instant disconnect overlay. **Not recommended** unless
a future version adds a measurable signal (e.g. report-ack timing).

### E6 — BRAKE label vs SRS FR-34 ("BRAKE / REVERSE") — NOT changed
The SRS text suggests the longer label to teach that S reverses when
stopped; Muhammad's approved mockup and the shipped design say "BRAKE"
(with the `S` sub-text). The approved design wins. If he ever asks why
the car reverses, the one-word label is the thing to revisit — noted
here only for the record.

---

## Files changed

| File | Changes |
|---|---|
| `lib/widgets/steering_wheel.dart` | T1 Listener conversion, T2 hysteresis |
| `lib/widgets/top_bar.dart` | T4 bounded status pill, T7 pill target size |
| `lib/screens/controller_screen.dart` | T3 font clamp, T5 compact scaling, T6 RUN toggle, T7 ghost targets, U5 entry banner, E2 notifier readout |
| `lib/screens/connect_screen.dart` | U1 sorting/selection/chips/icons, U2 guide placement, U3 troubleshooting card, U4 connect hint, U6 name ellipsis |
| `lib/services/hid_service.dart` | U1 `BondedDevice.majorClass` + class getters |
| `android/.../HidKeyboardManager.kt` | U1 `bondedDevices()` returns `majorClass` per device |

## Remaining recommendations (not implemented)

1. **E4** — progressive steering curve only if the user reports slow
   lock-to-lock feel on the real device.
2. **In-game verification session** (from QA report, still open): 6KRO
   combos, SA Definitive shared-Space RUN/JUMP behaviour, and wheel
   feel — all need the real phone + laptop; the Settings screen already
   exposes every knob those tests might want to turn.
3. **First-pair discoverability**: FR-4's "discoverable while the guide
   is open" remains a manual button (Android consent dialog) — the
   guide now sits in front of the first-time user (U2), which is the
   closest the platform allows.
