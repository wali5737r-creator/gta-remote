# GTA Remote — QA Audit Report

**Date:** 2026-11-19
**Scope:** Full audit of `lib/`, Kotlin platform channel, manifest, pubspec,
gradle, and the CI workflow — against `docs/SRS.md`, `docs/research.md`, and
`BUILD_NOTES.md`. Focus: the failure modes this app class (Bluetooth HID
device) commonly hits on real hardware, found and fixed *before* the user
hits them.
**Method:** Static review of every file (no SDK/device on this machine —
see "Could not verify" at the end). All fixes are in code, uncommitted;
the main agent owns git/CI.

**Result: 2 critical, 6 major, 7 minor issues found — all fixed.**
(One of the criticals is the hardening of the already-applied v1.1 fix.)

---

## First: the v1.1 fix — verified correct and complete

The live bug (pairing OK, CONNECT timed out after 20 s while Windows showed
"Connected") was root-caused to registration happening only at CONNECT-tap
time, i.e. after pairing, so Windows' cached SDP record had no HID service.

Checked the v1.1 diff end-to-end:

- `connect_screen.dart` registers the HID app as soon as the device list
  loads (permission granted) **and** again inside the discoverable flow
  *before* the discoverable intent fires — so the SDP record exists before
  any pairing attempt. ✔
- Kotlin `onHostPause()` no longer unregisters — pairing-confirm and
  discoverable-consent system dialogs pause the activity, and unregistering
  there would have removed the SDP record mid-pairing (the same bug in a
  second costume). It still sends the zero report, so the stuck-key safety
  property is kept. ✔
- The Dart timeout error now tells the user to **Remove device** on the
  laptop and re-pair with the app open — necessary because the *existing*
  bond on Muhammad's laptop was created with the old, broken order and
  Windows will keep using its cached SDP record until the device is
  removed and re-paired. ✔

The fix is sound. The issues below are everything *else* found around it.

---

## CRITICAL

### C1 — Registration could wedge permanently in a "busy" state
**Files:** `HidKeyboardManager.kt` (registration machinery)

**Evidence:** The manager kept a *single* `pendingRegisterResult`.
- If a second `registerApp` arrived while one was pending, it was answered
  with a hard `busy` PlatformException. v1.1's early registration made this
  likely: the connect screen registers on open, and if the profile proxy is
  slow, the user's CONNECT tap calls `registerApp` again → instant failure
  with the confusing message "Registration pehle se chal rahi hai." — even
  though registration was about to succeed.
- `onServiceDisconnected` (Bluetooth toggled off/on, stack restart) never
  completed the pending result at all. The Dart future timed out after
  10 s, but the Kotlin side stayed wedged: every later `registerApp` hit
  the `busy` branch until the profile service happened to reconnect.
- If `proxy.registerApp()` was accepted but the stack never delivered
  `onAppStatusChanged` (a known flaky-stack behaviour), the pending result
  leaked forever with the same wedge effect.

**Fix:** Replaced the single pending result with a **waiter list** +
`registerCallInFlight` flag:
- Every `registerApp` call joins the waiter list; one real
  `BluetoothHidDevice.registerApp()` call serves all of them; the single
  `onAppStatusChanged` callback completes all waiters (success or the
  plain-language failure).
- `onServiceDisconnected` now fails all waiters with a plain-language
  message and clears the stale `targetDevice` too.
- If an in-flight call is older than 4 s when a new request arrives
  (callback presumably lost), the register call is re-issued once instead
  of wedging.

### C2 — Device list never refreshed after pairing completed
**File:** `lib/screens/connect_screen.dart`

**Evidence:** The bonded-device list was loaded only in `initState`, on
manual refresh-icon tap, and after returning from the controller. Pairing
is initiated **from the laptop** while the phone app sits in the
foreground, so no lifecycle event fires on the phone when the bond is
created. The exact user flow — pair on Windows, look at phone, laptop
missing from the list, tap CONNECT on whatever *is* selected — ends in
the generic timeout error. This is the second half of the live bug's user
experience.

**Fix:**
- A silent auto-refresh every **4 s** while the connect screen is open
  (skipped while a connect is in progress). It only calls `setState` when
  the bonded list actually changed — no flicker.
- `WidgetsBindingObserver`: refresh on `resumed` (covers returning from
  phone Settings after granting permission, etc.).
- Selection logic hardened: auto-refresh no longer overrides the user's
  manual selection; auto-select (last-used laptop, or the single device)
  only happens when the current selection is empty or its device vanished.
- `_refreshDevices` is now wrapped in try/catch — a platform failure shows
  a plain-language error instead of dying silently as an unhandled async
  error with an empty list.

---

## MAJOR

### M1 — `connect()` had no bond-state check and wasn't idempotent
**File:** `HidKeyboardManager.kt` → `connect()`

**Evidence:** Connecting to a device whose pairing was removed on the
laptop (or never completed) just burned the full Dart-side 20 s timeout
and produced the generic error. Separately, `BluetoothHidDevice.connect()`
returns `false` on several stacks when the device is *already*
connected/connecting — Dart would report that as "Connect shuru nahi ho
saka" for a connection that was actually fine.

**Fix:** `connect()` now (a) checks `bondState` first and returns a
`not_paired` error with exact guidance ("…paired nahi hai. Pehle neeche
wali guide se pair karo, phir CONNECT dabao."), and (b) returns success
immediately if the same device is already CONNECTED/CONNECTING, letting
the state callback deliver the truth.

### M2 — Connect wait never failed fast (full 20 s hang on instant rejects)
**File:** `lib/services/hid_service.dart` → `connectSequence`

**Evidence:** The wait was `states.firstWhere(isConnected)` with a 20 s
timeout. If the stack rejected the L2CAP connection in 2 s, the user
still stared at "Connect ho raha hai…" for the remaining 18 s. (The
timeout fallback returning `_current` did cover the theoretical
missed-event case on a broadcast stream, but at maximum latency.)

**Fix:** New `_waitForConnection()` helper: completes **true** on the
connected event, **false immediately** on a disconnected event during
the attempt, and only uses the 20 s timeout as a backstop (returning
`_current.isConnected`). It also checks `_current` first, closing the
broadcast missed-event hole properly.

### M3 — FR-28's all-released report on (re)connect was missing
**File:** `lib/services/hid_service.dart` → event handler

**Evidence:** SRS FR-28 requires one all-released (clean-state) report
after reconnect, before any new input. Nothing sent one: after a drop,
the pressed set was cleared locally, but the first report only went out
on the user's next key change.

**Fix:** When a `connected` state event arrives, the service now sends
the current snapshot report. After a drop that snapshot is the empty
set (disconnect clears it and resets the send signature), so a real
zero report reaches the laptop; on first connect it establishes the
baseline. Safe if a duplicate connected event ever arrives mid-game —
it re-sends the *current* pressed set, which is the correct state.

### M4 — Permanently-denied Bluetooth permission looped forever
**Files:** `lib/screens/connect_screen.dart`, `HidKeyboardManager.kt`,
`lib/services/hid_service.dart`

**Evidence:** If the user had denied BLUETOOTH_CONNECT with "don't ask
again" (or realme UI's equivalent), `requestPermissions` returned
`false` instantly with no system dialog, and the UI just said "tap Allow
Bluetooth" — an infinite loop with no exit.

**Fix:** When a permission request completes denied, the app now shows
a dialog explaining the manual path and a **"Settings kholo"** button
that opens the app's system Settings page (new native `openAppSettings`
method → `ACTION_APPLICATION_DETAILS_SETTINGS`; Dart wrapper added).
The dialog text gives the exact path: Permissions → Nearby devices →
Allow. Returning from Settings triggers the C2 resume-refresh, which
re-reads the permission state automatically.

### M5 — CONNECT double-tap race
**File:** `lib/screens/connect_screen.dart` → `_onConnectPressed`

**Evidence:** `_busy` was set only *after* the permission await. Two
fast taps both passed the `!_busy` guard and started two overlapping
`connectSequence`s — double register/connect calls racing, with the
loser's error overwriting the winner's result.

**Fix:** `_busy = true` is now set synchronously at the top of the
handler and cleared on every exit path (permission-denied branch
included).

### M6 — Unguarded intent launches could crash the app
**File:** `HidKeyboardManager.kt` → `requestEnableBluetooth`,
`makeDiscoverable`

**Evidence:** Both called `activity.startActivityForResult(...)` with no
try/catch. If no activity can handle the intent (rare, but exactly the
kind of OEM-stack surprise this audit targets), the
`ActivityNotFoundException` crashes the app. `makeDiscoverable` also
didn't handle a null Bluetooth adapter.

**Fix:** Both launches are wrapped; failures complete the pending
result with a plain-language error telling the user what to do in
Settings instead. Null-adapter check added to `makeDiscoverable`
(`requestEnableBluetooth` already had one).

---

## MINOR

### m1 — setState-after-dispose gaps in the connect flow
`_ensurePermissions` set state after an await with no `mounted` check;
the permission-denied branch of `_onConnectPressed` did the same.
Guards added in the M4/M5 rewrites.

### m2 — F-tap vs mode-pill race could desync the layout
**File:** `lib/screens/controller_screen.dart` → `_onEnterExitTap`
The F-tap waited 130 ms and then flipped to `!_driving`. A mode-pill tap
inside that window flipped the mode first, and the F-tap then flipped it
*back* — while the game had received F — recreating exactly the desync
the pill exists to repair. Fix: the target mode is captured before the
delay and `_switchMode(target)` no-ops if the pill already set it.

### m3 — Opening Settings mid-hold could leave a key logically held
`_openSettings` now clears all key sources before pushing the Settings
route (with a `setState` so the RUN toggle's lit state also resets).
Belt-and-braces on top of pointer-routing behaviour: leaving the
controls always ends input.

### m4 — Steering wheel / joystick didn't release their key on dispose
`HoldSurface` and `RoundButton` already notify release in `dispose()`;
`SteeringWheel` and `WasdJoystick` didn't. The controller clears sources
on mode switch and screen dispose, so this was defence-in-depth — now
all four input widgets honour the "a key can never stick" invariant by
themselves.

### m5 — Stale comment in MainActivity contradicted v1.1
The `onPause` comment still said the manager "unregisters" on pause —
the exact behaviour v1.1 removed to fix the live bug. Comment corrected
so a future maintainer doesn't "restore" the bug. (Same stale wording
exists in `BUILD_NOTES.md`'s file map — documentation only, left for
the main agent.)

### m6 — Discoverable window wasn't communicated
The discoverable grant is 300 s; the success status now says the phone
is discoverable **for 5 minutes** and to tap again if it expires,
instead of leaving the user wondering why the laptop stopped seeing
the phone mid-pairing.

### m7 — `onServiceDisconnected` left a stale `targetDevice`
Cleared as part of the C1 rewrite (a later manual Disconnect could
otherwise target a device from a dead stack session).

---

## Verified correct — no change needed

- **HID descriptor vs payload:** the descriptor declares Report ID 1 and
  an 8-byte input report (modifier byte, reserved byte, 6 keycodes) plus
  the LED output report. `sendReport(device, 1, 8-byte data)` matches —
  the Android API prepends the report ID itself, so the payload correctly
  excludes it. This is the canonical AOSP boot-keyboard descriptor.
- **Keycodes:** W 0x1A, A 0x04, S 0x16, D 0x07, F 0x09, Space 0x2C,
  Enter 0x28, Esc 0x29 — all correct USB HID usage IDs; Left Shift is
  modifier bit **0x02** ✔. Fixed report ordering, signature dedupe, and
  the 6-key cap are correct.
- **Game profiles:** GTA V Run=Shift/Jump=Space; SA Original
  Run=Space/Jump=Shift; SA Definitive Run=Space/Jump=Space ✔ (spec).
  Note: in SA Definitive, RUN (toggle) and JUMP share Space — holding
  RUN keeps Space held, so JUMP can't register separately while RUN is
  on. That is the profile's real mapping, not a code bug; in-game
  behaviour is in the unverifiable list below.
- **Zero-report / release paths:** native `onPause`, `disconnectInternal`,
  `dispose`, Dart `disconnectSequence`, lifecycle paused/inactive,
  mode switch, settings change — every exit path ends all-released ✔.
- **Controller chrome:** wakelock follows connection state, landscape +
  immersive applied on entry and restored (portrait + edge-to-edge) on
  dispose, settings round-trip re-applies landscape ✔. Back button asks
  before disconnecting (FR-32) ✔. Disconnected overlay blocks all
  controls (FR-30) ✔.
- **Permissions/native safety:** every other Bluetooth call is already
  wrapped for `SecurityException`; empty `grantResults` (interrupted
  request) is treated as denied, not a crash ✔. No `BLUETOOTH_SCAN`
  declared — correct, the app never scans ✔.
- **Manifest:** BLUETOOTH/ADMIN capped at SDK 30, CONNECT + ADVERTISE
  runtime permissions present, VIBRATE present, **no INTERNET** ✔.
- **Settings/persistence:** profile, steering range/dead zone/
  sensitivity, flip, and last device all persist and restore; the
  connect screen pre-selects the last-used laptop ✔ (FR-26).
- **CI workflow (area 9):** `.github/workflows/build-apk.yml` backs up
  and restores **both** Kotlin files, the manifest, and
  `build.gradle.kts` around `flutter create`, and deletes the generated
  wrong-package `com/muhammad/gta_remote` directory. Styles, launcher
  icons, gradle wrapper and `${applicationName}` all come from
  `flutter create` ✔. Nothing in the code references a file that flow
  won't produce.

---

## Could NOT verify without a device / build

1. **The gate question itself** — whether realme UI on the C67 exposes
   the HID Device role. Pairing succeeded on the user's device, which
   is encouraging, and the SDP-ordering cause of the live bug is fixed;
   but only a re-pair (after Remove device) + CONNECT on the real phone
   proves the HID connection completes.
2. **Compilation** — no Flutter/Android SDK on this machine; all edits
   were re-read for syntax/API correctness, but the first proof is the
   next CI build.
3. **L2CAP collision behaviour** — if Windows auto-connects at the same
   moment the user taps CONNECT, stack behaviour varies; the app now
   takes its state purely from callbacks, so whichever side wins is
   handled, but the exact realme/Windows interaction is untestable here.
4. **Windows SDP re-read on an existing bond** — if the user does *not*
   Remove device first, the old cached SDP record may still break
   connect; the error copy already instructs the re-pair.
5. **realme UI specifics** — permission dialog/"don't ask again"
   behaviour, battery management throttling Bluetooth in the background,
   and the discoverable consent dialog's exact result codes.
6. **In-game verification** — 6KRO combos (W+A+Space+Shift) in GTA,
   input latency feel, and SA Definitive's shared-Space RUN/JUMP
   behaviour in the actual game.
