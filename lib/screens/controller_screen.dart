import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/game_key.dart';
import '../models/game_profile.dart';
import '../services/hid_service.dart';
import '../services/settings_service.dart';
import '../widgets/analog_stick.dart';
import '../widgets/camera_pad.dart';
import '../widgets/car_pedal.dart';
import '../widgets/cricket_gesture_area.dart';
import '../widgets/fly_stick.dart';
import '../widgets/hold_surface.dart';
import '../widgets/joystick.dart';
import '../widgets/premium_background.dart';
import '../widgets/round_button.dart';
import '../widgets/steer_arrows.dart';
import '../widgets/steering_wheel.dart';
import '../widgets/top_bar.dart';
import 'cheats_screen.dart';
import 'guide_screen.dart';
import 'settings_screen.dart';

/// Controller screen — Driving aur On Foot dono modes.
///
/// Har control apni keys ka "source" rakhta hai (race, joystick, pwm…);
/// tamam sources ka union hi HID report banta hai. Is design se koi key
/// atak nahi sakti: source saaf = key gayi.
///
/// Layout (Muhammad ki design, v2 — Racing Cockpit; v3/v4 additions):
/// - Top bar: status pill (left) + mode pill (right); driving me
///   beech me drive-mode switch (STEERING | TILT | CONTROLLER |
///   ARROWS | FLY).
/// - ENTER/EXIT CAR gol button pedals ke cluster ke UPAR, HANDBRAKE ke
///   saath — dono modes me bilkul wahi jagah.
/// - Pedals: BRAKE pehla (left), RACE baad me (right).
/// - TILT mode me wheel nahi hota: BRAKE neeche-left, RACE
///   neeche-right, aur steering phone hilane se hoti hai.
/// - Wheel ke neeche koi caption text nahi.
/// - v3: beech me CAMERA pad (HID mouse) — camera, swimming ki simt
///   aur menu pointer; action row me MAP (Esc tap); paidal mode me
///   ATTACK (mouse left click, dabaye rakho). Steering ab PWM hai —
///   halka mor halki pulse deta hai, poora mor lagi hui key.
/// - v4: CONTROLLER mode (gamepad stick + trigger buttons) aur
///   ARROWS mode (tap wale steer buttons, minimum pulse ke saath) —
///   dono khalis izafa hain, purane modes bilkul nahi badle. Paidal
///   mode me AIM (mouse right, dabaye rakho), CROUCH (C tap) aur
///   weapon switch (mouse wheel ticks) bhi jud gaye.
/// - v5: top bar ki dusri satar me CHEATS (tap karo, remote code
///   type kar deta hai) aur GUIDE (missions ki rehnumai) ke pills;
///   har driving mode me HORN (STEERING me wheel ka hub, TILT me
///   BRAKE ke upar gol button, CONTROLLER/ARROWS me cluster ke
///   saath gol button) aur MISSION pill (vehicle side-missions
///   wali key ka saaf tap); paidal mode me TAB pill (property
///   khareedna waghera). HID descriptor bilkul nahi badla —
///   saara kaam Dart me hai.
/// - v6: FLY mode — jahaz/helicopter ke liye aik handle (mor
///   A/D + naak ArrowDown/ArrowUp, flight-stick inversion ke
///   saath), RACE + DOWN compact pedals, beech me CAMERA pad +
///   EXIT/MAP; HORN/MISSION FLY me nahi. Cheat typer reliable
///   hua (har send ka boolean jawab + retries). HID descriptor
///   phir bhi bilkul nahi badla — saara kaam Dart me hai.
/// - v7: CRICKET mode — EA Sports Cricket 07 ke liye alag
///   stage jo driving stage ki jagah aati hai: BATTING (puri
///   screen par swipe = shot, simt = arrow keys; shot buttons
///   FRONT FOOT S / BACK FOOT W / ADVANCE D; LOFT = Shift hold;
///   tap = ball chorna) aur BOWLING (drag = marker ki arrow
///   keys, delivery buttons S/A/D/W/Shift). Saare buttons aik
///   hi taraf chhote gol (76 dp) hain; CAMERA pad is mode me
///   nahi (Cricket 07 sirf keyboard par hai). HID descriptor
///   phir bhi bilkul nahi badla — saara kaam Dart me hai.
class ControllerScreen extends StatefulWidget {
  const ControllerScreen({super.key});

  @override
  State<ControllerScreen> createState() => _ControllerScreenState();
}

class _ControllerScreenState extends State<ControllerScreen>
    with WidgetsBindingObserver {
  final HidService _hid = HidService.instance;
  final SettingsService _settings = SettingsService.instance;

  StreamSubscription<HidState>? _hidSubscription;
  HidState _hidState = HidService.instance.current;

  /// True = Driving, false = On Foot. Player paidal shuru hota hai (FR-5).
  bool _driving = false;

  /// Har control ki apni keys: source ka naam -> keys.
  final Map<String, Set<GameKey>> _keySources = {};

  bool _runOn = false;
  bool _fTapInProgress = false;

  /// Steering ka tareeqa (sirf driving me): touch wheel
  /// (STEERING), phone hilana (TILT), analog stick (CONTROLLER)
  /// ya tap wale buttons (ARROWS). Settings se restore hota hai
  /// aur switch se badalte hi wahan save ho jata hai.
  DriveMode _driveMode = DriveMode.steering;

  /// Sirf TILT check karne ke liye asaan roop — tilt ki tamam
  /// purani logic isi par chalti hai, aur woh sirf TILT mode me
  /// hi sach hoti hai.
  bool get _tiltMode => _driveMode == DriveMode.tilt;

  // --- Tilt steering (v2) ------------------------------------------------

  StreamSubscription<AccelerometerEvent>? _tiltSubscription;

  /// Baseline: tilt shuru hote waqt gravity ka in-plane angle
  /// (degrees) — pehli readings ke ausat se banta hai (neeche
  /// dekho). Saari naap is ke nisbat hoti hai — phone jis haalat
  /// me pakra hai, wahi "seedha" hai.
  double? _tiltBaselineDeg;

  /// Baseline ginne ke liye pehli readings ka majmua (vector sum) —
  /// aik akeli reading par baseline nahi banta.
  double _tiltBaseSumX = 0;
  double _tiltBaseSumY = 0;
  DateTime? _tiltBaseStart;

  /// Phone flat hone ka waqt — itni dair flat rahe to lagi hui
  /// tilt steering chhor dete hain (koi key atak nahi sakti).
  DateTime? _tiltFlatSince;

  /// Low-pass smoothing ke baad ki gravity (phone ke x/y axes par).
  double _tiltSmoothX = 0;
  double _tiltSmoothY = 0;
  bool _tiltHasSmooth = false;

  /// Itne degrees se zyada jhukao par steering lagti hai…
  static const double _tiltEngageDeg = 12;

  /// …aur itne se kam par chhut-ti hai (hysteresis — wheel ki tarah,
  /// taake hadd par key jhatkay na khaye).
  static const double _tiltReleaseDeg = 8;

  /// Tilt ka poora mor (full lock) itne degrees par — PWM engine ke
  /// normalised hisaab ke liye (engage 12° → 12/45, release 8° → 8/45).
  static const double _tiltFullScaleDeg = 45;

  // --- PWM steering engine (v3) ------------------------------------------
  //
  // v2 me steering seedha on/off thi: chhota sa mor bhi A/D ko poora
  // daba deta tha — "thora sa move kro to gari puri move hojti".
  // Ab wheel/tilt sirf normalised mor (−1..+1) dete hain; ye engine
  // use A/D ki pulses me badalta hai: 100 ms ki window me key-down
  // waqt = 25 ms + 75 ms × duty, jahan duty dead zone ke baad ke
  // mor ke hisaab se hai. Duty ≥ 0.98 par key lagi rehti hai.
  // Engine har 20 ms tick karta hai; window ka hisaab error
  // diffusion se bant-ta hai taake lambay arsay ka duty bilkul
  // wahi rahe jo formula kehta hai.

  /// Kaun sa steering source active hai: 'wheel' | 'tilt' | null.
  String? _steerSourceId;

  /// Normalised mor: −1 (poora left) .. +1 (poora right).
  double _steerValue = 0;

  /// Normalised dead zone (lagne ki hadd) aur chhutne ki hadd —
  /// active source ke hisaab se (wheel: deadZone/range, tilt: 12/45).
  double _steerEngageN = 0;
  double _steerReleaseN = 0;

  /// Engine is waqt kis simt ki key chala raha hai (left/right/null).
  GameKey? _pwmDirectionKey;

  /// HID report me is waqt asal lagi hui PWM key (pulses ke saath
  /// badalti hai) — source 'pwm'.
  GameKey? _pwmAppliedKey;

  /// Error-diffusion ka jama hisaab (window ki duty bantne ke liye).
  double _pwmAccumulator = 0;

  Timer? _pwmTimer;

  // --- Momentary (tap) keys (v3) ------------------------------------------

  /// Tap wali key itni dair dabi rehti hai — aik saaf, poora press.
  static const Duration _tapPressDuration = Duration(milliseconds: 150);

  /// Aik tap ke baad itni dair dusra tap nazarandaz — double-fire
  /// nahi hota (ENTER/EXIT ke "ulta kaam" wali shikayat ka aik sabab
  /// yahi tha: do tap = andar + bahar, ulta asar).
  static const Duration _tapLockoutDuration = Duration(milliseconds: 250);

  /// Jin tap ids par abhi lockout chal raha hai.
  final Set<String> _tapLockouts = {};

  /// Har tap id ki nasal (generation) — purana delayed release naye
  /// press ki key ko galti se nahi kaat sakta.
  final Map<String, int> _tapGenerations = {};

  /// Aakhri ENTER/EXIT tap ka waqt (us ki apni lockout ke liye —
  /// mode switch wali lambi kahani _fTapInProgress se alag).
  DateTime? _lastFTapAt;

  // --- Stick steering (v4, CONTROLLER mode) -------------------------------

  /// Stick ki fixed dead zone (normalised) — is se chhota mor
  /// steering nahi lagata. Settings wali dead zone sirf wheel ki
  /// hai; stick ki ye apni tay shuda hadd hai.
  static const double _stickDeadZone = 0.12;

  /// Stick ki release hadd — engage se kam, taake hadd par mor
  /// jhatkay na khaye (wheel/tilt wali hysteresis ki tarah).
  static const double _stickRelease = 0.08;

  // --- Arrows steering (v4, ARROWS mode) ----------------------------------
  //
  // ◀ ▶ buttons seedha A/D dabate hain (source 'buttons') — PWM
  // nahi. Is mode ki jaan "aik tap = halki si move" hai: jaldi tap
  // par bhi key kam az kam itni dair zaroor dabti hai, warna 20-30
  // ms ka tap game tak aksar pahunchta hi nahi aur button murda
  // lagta hai.

  /// Tap ki minimum pulse — is se jaldi chhorne par bhi key kul
  /// itni dair dabi rehti hai.
  static const Duration _arrowMinPulse = Duration(milliseconds: 90);

  /// Ungli asal me dabi hui hai ya nahi (left/right).
  final Map<bool, bool> _arrowHeld = {true: false, false: false};

  /// Har taraf ke press ki shuruaat ka waqt (minimum pulse ginne
  /// ke liye).
  final Map<bool, DateTime> _arrowPressedAt = {};

  /// Minimum pulse poora karne ke intezar wale timers (left/right).
  final Map<bool, Timer> _arrowTailTimers = {};

  /// Baseline itni dair ki readings ka ausat hota hai.
  static const Duration _tiltBaselineWindow = Duration(milliseconds: 300);

  /// Phone itni dair flat rahe to lagi hui tilt key chhut jati hai.
  static const Duration _tiltFlatReleaseDelay = Duration(milliseconds: 250);

  /// Steering angle sirf readout ke liye hai — ValueNotifier is liye
  /// ke har degree ki tabdeeli par poori controller screen dobara na
  /// bane (steering ke doran ye second me darjanon dafa badalta hai).
  final ValueNotifier<double> _wheelAngle = ValueNotifier<double>(0);

  String? _bannerText;
  Timer? _bannerTimer;

  bool _reconnecting = false;
  String? _reconnectError;

  bool get _connected => _hidState.isConnected;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _applyLandscape();
    _hidState = _hid.current;
    _hidSubscription = _hid.states.listen((state) {
      if (!mounted) return;
      setState(() => _hidState = state);
      if (state.isConnected) {
        WakelockPlus.enable();
        _updateTiltSubscription();
      } else {
        WakelockPlus.disable();
        _stopTilt();
        _clearAllKeys();
      }
    });
    if (_connected) WakelockPlus.enable();
    _settings.addListener(_onSettingsChanged);
    _driveMode = _settings.driveMode;
    // Pehle frame ke baad maujooda mode ka banner aik dafa dikhao —
    // user ko foran tasdeeq mil jati hai ke woh controller par hai
    // aur kis mode me hai (connect kamyab hone ka sab se wazeh ishara).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _connected) {
        _showBanner(_modeBannerText);
      }
    });
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _cricketShotTimer?.cancel();
    _cricketShotTimer = null;
    _pwmTimer?.cancel();
    _pwmTimer = null;
    for (final timer in _arrowTailTimers.values) {
      timer.cancel();
    }
    _arrowTailTimers.clear();
    _stopTilt();
    _wheelAngle.dispose();
    _settings.removeListener(_onSettingsChanged);
    _hidSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _hid.releaseAllKeys();
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _applyLandscape() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // App background me jaye to saari keys chhor do (FR-29) aur
    // tilt sensor bhi band kar do.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _stopTilt();
      _clearAllKeys();
      _hid.releaseAllKeys();
    } else if (state == AppLifecycleState.resumed) {
      // Wapas aane par tilt (agar on tha) dobara shuru — baseline
      // taaza banta hai, purani simt par key nahi atki rehti.
      _updateTiltSubscription();
    }
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    // Setting badli to pehle saari keys chhoro (koi atak na jaye), phir
    // nayi settings ke saath dobara banao.
    _clearAllKeys();
    setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Key management
  // ---------------------------------------------------------------------------

  void _setSourceKeys(String source, Set<GameKey> keys) {
    if (keys.isEmpty) {
      _keySources.remove(source);
    } else {
      _keySources[source] = keys;
    }
    _syncKeys();
  }

  void _syncKeys() {
    final union = <GameKey>{};
    for (final keys in _keySources.values) {
      union.addAll(keys);
    }
    _hid.setPressedKeys(union);
  }

  void _clearAllKeys() {
    _keySources.clear();
    _runOn = false;
    // ARROWS ki haalat bhi saaf — koi minimum-pulse timer purani
    // key ko dobara nahi laga sakta. (Timers yahin cancel hote
    // hain; sources upar saaf ho chuke hain.)
    _resetArrows();
    // FLY handle ki simtain bhi saaf — warna naye mode me ghuste
    // hi purani simt ka hisaab pehli feed par galat key laga
    // sakta tha. (Source upar saaf ho chuka hai.)
    _resetFlyStick();
    // CRICKET ki arzi haalat bhi saaf — shot ki khirki ka timer
    // ruk jaye aur pasand FRONT FOOT par wapas aa jaye, warna
    // mode switch ke baad purana timer nayi haalat par chal
    // sakta tha. (Sources upar saaf ho chuke hain.)
    _resetCricketState();
    // PWM engine bhi saaf — warna mode switch ke baad purani
    // steering pulse chalti rahegi. (Sources pehle saaf ho chuke
    // hain, is liye engine ko source-sync ki zaroorat nahi.)
    _resetSteerEngine(syncSource: false);
    _hid.releaseAllKeys();
  }

  // ---------------------------------------------------------------------------
  // PWM steering engine (v3)
  // ---------------------------------------------------------------------------

  /// Steering source (wheel ya tilt) apna normalised mor de.
  /// [engage]/[release] usi source ki normalised haddein hain.
  void _setSteerInput({
    required String source,
    required double value,
    required double engage,
    required double release,
  }) {
    _steerSourceId = source;
    _steerValue = value;
    _steerEngageN = engage;
    _steerReleaseN = release;
    _pwmTimer ??= Timer.periodic(
      const Duration(milliseconds: 20),
      (_) => _pwmTick(),
    );
  }

  /// Engine ko poora band/saaf karo. [syncSource] true ho to 'pwm'
  /// source bhi union se nikalta hai (masalan tilt rukte waqt, jab
  /// baqi sources abhi zinda hain); _clearAllKeys me sources pehle
  /// hi saaf hote hain, wahan false rakho.
  void _resetSteerEngine({bool syncSource = true}) {
    _steerSourceId = null;
    _steerValue = 0;
    _pwmDirectionKey = null;
    _pwmAccumulator = 0;
    _pwmTimer?.cancel();
    _pwmTimer = null;
    if (_pwmAppliedKey != null) {
      _pwmAppliedKey = null;
      if (syncSource) _setSourceKeys('pwm', const {});
    }
  }

  /// Har 20 ms: maujooda mor se simt tay karo (hysteresis ke saath),
  /// phir duty ke hisaab se is tick par key dabani hai ya nahi.
  void _pwmTick() {
    if (_steerSourceId == null || !_driving) {
      _setPwmKey(null);
      return;
    }
    final profile = _settings.profile;
    final left = profile.steerLeftKey;
    final right = profile.steerRightKey;
    final s = _steerValue;
    final engage = _steerEngageN;
    final release = _steerReleaseN;

    GameKey? direction = _pwmDirectionKey;
    if (direction == right) {
      if (s < -engage) {
        direction = left; // seedha dusri simt
      } else if (s <= release) {
        direction = null;
      }
    } else if (direction == left) {
      if (s > engage) {
        direction = right;
      } else if (s >= -release) {
        direction = null;
      }
    } else if (s > engage) {
      direction = right;
    } else if (s < -engage) {
      direction = left;
    }
    if (direction != _pwmDirectionKey) {
      _pwmDirectionKey = direction;
      // Nayi simt foran lage — pehli tick par hi key dab jaye,
      // diffusion ka hisaab intezar na karwaye.
      _pwmAccumulator = direction == null ? 0 : 1.0;
    }
    if (direction == null) {
      _setPwmKey(null);
      return;
    }

    // Duty: dead zone ke baad mor kitna gehra hai (0..1).
    final duty =
        ((s.abs() - engage) / (1 - engage)).clamp(0.0, 1.0).toDouble();
    if (duty >= 0.98) {
      _setPwmKey(direction); // poora mor — key lagi rahe
      return;
    }
    // 100 ms window me key-down waqt = 25 + 75 × duty ms.
    // 20 ms ki ticks par ye hisaab error diffusion se bant-ta hai:
    // har tick apna hissa jama karta hai; jama 1 ho jaye to is tick
    // key dabti hai. Lambay arsay ka duty formula ke ain mutabiq.
    _pwmAccumulator += (25 + 75 * duty) / 100;
    if (_pwmAccumulator >= 1) {
      _pwmAccumulator -= 1;
      _setPwmKey(direction);
    } else {
      _setPwmKey(null);
    }
  }

  void _setPwmKey(GameKey? key) {
    if (key == _pwmAppliedKey) return;
    _pwmAppliedKey = key;
    _setSourceKeys('pwm', key == null ? const {} : {key});
  }

  /// Touch wheel ka angle → normalised mor. Dead zone aur release
  /// hadd wheel ki purani degrees wali hisaab se hi aati hai
  /// (release = dead zone − min(2°, 35%)) — sirf normalised hai.
  void _feedWheelSteer(double angleDeg) {
    if (!_driving || _driveMode != DriveMode.steering) return;
    final range = _settings.steeringRangeDeg;
    final deadZone = _settings.deadZoneDeg;
    final releaseDeg = math.max(
      0.0,
      deadZone - math.min(2.0, deadZone * 0.35),
    );
    _setSteerInput(
      source: 'wheel',
      value: (angleDeg / range).clamp(-1.0, 1.0).toDouble(),
      engage: deadZone / range,
      release: releaseDeg / range,
    );
  }

  /// Tilt ka delta (degrees) → normalised mor (poora mor = 45°).
  void _feedTiltSteer(double deltaDeg) {
    if (!_driving || _driveMode != DriveMode.tilt) return;
    _setSteerInput(
      source: 'tilt',
      value: (deltaDeg / _tiltFullScaleDeg).clamp(-1.0, 1.0).toDouble(),
      engage: _tiltEngageDeg / _tiltFullScaleDeg,
      release: _tiltReleaseDeg / _tiltFullScaleDeg,
    );
  }

  /// Stick ka normalised mor → wahi PWM engine (v4). Sensitivity
  /// lagti hai (wheel ki tarah multiplier), dead zone stick ki
  /// apni fixed 0.12 hai — Settings ki range/dead zone is par
  /// nahi lagti (woh wheel ki hain, Settings help me likha hai).
  void _feedStickSteer(double steer) {
    if (!_driving || _driveMode != DriveMode.controller) return;
    _setSteerInput(
      source: 'stick',
      value: (steer * _settings.sensitivity.factor)
          .clamp(-1.0, 1.0)
          .toDouble(),
      engage: _stickDeadZone,
      release: _stickRelease,
    );
  }

  // ---------------------------------------------------------------------------
  // Arrows steering (v4) — tap wale ◀ ▶ buttons
  // ---------------------------------------------------------------------------

  /// Arrow button ki haalat badli (widget se). [left] true = ◀.
  ///
  /// Dabane par key foran lagti hai. Chhorne par: press 90 ms se
  /// kam raha ho to key baqi waqt tak lagi rehti hai (minimum
  /// pulse), warna foran chhut-ti hai. Dono taraf aik saath lagi
  /// hon to dono cancel — koi key nahi.
  void _onArrowHeldChanged(bool left, bool held) {
    if (!_driving || _driveMode != DriveMode.arrows) return;
    if (held) {
      // Dobara dabane par purani tail ka timer maar do — warna
      // woh is press ko waqt se pehle kaat dega.
      _arrowTailTimers[left]?.cancel();
      _arrowTailTimers.remove(left);
      _arrowHeld[left] = true;
      _arrowPressedAt[left] = DateTime.now();
    } else {
      _arrowHeld[left] = false;
      final pressedAt = _arrowPressedAt[left];
      final elapsed = pressedAt == null
          ? _arrowMinPulse
          : DateTime.now().difference(pressedAt);
      if (elapsed < _arrowMinPulse) {
        // Minimum pulse baqi hai — key lagi rehne do, waqt poora
        // hote hi _applyArrows dobara hisaab karega.
        _arrowTailTimers[left]?.cancel();
        _arrowTailTimers[left] = Timer(
          _arrowMinPulse - elapsed,
          () {
            _arrowTailTimers.remove(left);
            _applyArrows();
          },
        );
      }
    }
    _applyArrows();
  }

  /// Aik taraf ki key asal me lagi honi chahiye ya nahi: ungli
  /// dabi ho, ya minimum pulse ki tail abhi chal rahi ho.
  bool _arrowEffective(bool left) =>
      (_arrowHeld[left] ?? false) || _arrowTailTimers.containsKey(left);

  /// Dono taraf ki haalat se 'buttons' source tay karo.
  void _applyArrows() {
    if (!_driving || _driveMode != DriveMode.arrows) return;
    final leftOn = _arrowEffective(true);
    final rightOn = _arrowEffective(false);
    final profile = _settings.profile;
    if (leftOn && rightOn) {
      // Dono aik saath = cancel. Tail khatam hone par dusri
      // taraf khud lag jayegi (uska timer _applyArrows bulayega).
      _setSourceKeys('buttons', const {});
    } else if (leftOn) {
      _setSourceKeys('buttons', {profile.steerLeftKey});
    } else if (rightOn) {
      _setSourceKeys('buttons', {profile.steerRightKey});
    } else {
      _setSourceKeys('buttons', const {});
    }
  }

  /// ARROWS ki saari haalat saaf (mode switch / clear-all par).
  void _resetArrows() {
    for (final timer in _arrowTailTimers.values) {
      timer.cancel();
    }
    _arrowTailTimers.clear();
    _arrowHeld[true] = false;
    _arrowHeld[false] = false;
    _arrowPressedAt.clear();
  }

  // ---------------------------------------------------------------------------
  // FLY steering (v6) — jahaz/helicopter ka handle
  // ---------------------------------------------------------------------------

  /// Handle ke mehwar kis simt me lage hue hain: −1 / 0 / +1.
  /// X: −1 = left mor, +1 = right mor.
  /// Y: −1 = handle UPAR, +1 = handle NEECHE.
  int _flyXDir = 0;
  int _flyYDir = 0;

  /// Handle ki dead zone: mehwar 0.25 se aage jaye to key lagti
  /// hai, 0.18 se neeche aaye to chhut-ti hai — beech wali patti
  /// maujooda haalat rakhti hai, taake kinare par key flicker
  /// na kare (hysteresis).
  static const double _flyEngage = 0.25;
  static const double _flyRelease = 0.18;

  /// FlyStick ke dono mehwar → 'flystick' source ki keys.
  ///
  /// TRACE (IMPROVEMENTS_V6.md me bhi bilkul yahi hai):
  /// - handle LEFT   → profile.steerLeftKey (A)
  /// - handle RIGHT  → profile.steerRightKey (D)
  /// - handle UPAR   → {arrowDown, numpad2, numpad5} — NOSE UP.
  /// - handle NEECHE → {arrowUp, numpad8} — NOSE DOWN.
  ///
  /// Pitch ke set itne bare KYUN hain (v5.2 fix — is hisse ko
  /// "saaf" karke keys kam NA karna):
  /// - GTA SA (2005) jahaz ko arrow keys se bilkul NAHI
  ///   ghumata. Pitch wahan "Special Control" mehwar par hai:
  ///   **Numpad 2 = naak UPAR, Numpad 8 = naak NEECHE** (SA ka
  ///   mashhoor laptop masla; SA DirectInput scancodes parhta
  ///   hai, is liye NumLock ki haalat se koi farq nahi parta).
  ///   Sirf arrows bhejne par jahaz sirf dorta raha, ura nahi —
  ///   yahi v5.1 ka owner-device bug tha.
  /// - GTA V: **Numpad 8 = naak NEECHE, Numpad 5 = naak UPAR**.
  /// - Arrows phir bhi set mai rakhe hain: VC aur dusri games
  ///   un se pitch karti hain, aur in games mai numpad keys ka
  ///   koi ulta asar nahi.
  /// - Naak UPAR wale set mai numpad2 (SA) aur numpad5 (V)
  ///   dono hain taake handle har game mai kaam kare.
  ///
  /// Flight-stick convention bhi yaad rahe: GTA SA me
  /// ArrowDown/Numpad 2 jahaz ki naak UPAR uthata hai — handle
  /// UPAR = naak UPAR wala ulta lagne wala mapping jaan-boojh
  /// kar hai. Ise "seedha" karne ki koshish NA karna.
  ///
  /// Dono mehwar azad hain: diagonal (mor + climb/descend aik
  /// saath) mumkin hai — key-set architecture tamam keys aik hi
  /// report me bhej deta hai. Stick chhute hi widget (0, 0)
  /// bhejta hai aur tamam keys chhut jati hain. Koi PWM nahi —
  /// keys seedhi hold hoti hain jab tak mehwar dead zone se
  /// bahar hai. Settings ki sensitivity yahan nahi lagti (woh
  /// wheel/stick ki cheez hai).
  void _feedFlyStick(double x, double y) {
    if (!_driving || _driveMode != DriveMode.fly) return;
    var xd = _flyXDir;
    if (x >= _flyEngage) {
      xd = 1;
    } else if (x <= -_flyEngage) {
      xd = -1;
    } else if (x.abs() <= _flyRelease) {
      xd = 0;
    }
    var yd = _flyYDir;
    if (y <= -_flyEngage) {
      yd = -1;
    } else if (y >= _flyEngage) {
      yd = 1;
    } else if (y.abs() <= _flyRelease) {
      yd = 0;
    }
    _flyXDir = xd;
    _flyYDir = yd;
    final profile = _settings.profile;
    final keys = <GameKey>{};
    if (xd < 0) keys.add(profile.steerLeftKey);
    if (xd > 0) keys.add(profile.steerRightKey);
    if (yd < 0) {
      // NOSE UP: arrowDown (VC waghera) + numpad2 (SA) + numpad5 (V)
      keys.add(GameKey.arrowDown);
      keys.add(GameKey.numpad2);
      keys.add(GameKey.numpad5);
    }
    if (yd > 0) {
      // NOSE DOWN: arrowUp (VC waghera) + numpad8 (SA aur V dono)
      keys.add(GameKey.arrowUp);
      keys.add(GameKey.numpad8);
    }
    _setSourceKeys('flystick', keys);
  }

  /// FLY handle ki haalat saaf (mode switch / clear-all par).
  void _resetFlyStick() {
    _flyXDir = 0;
    _flyYDir = 0;
  }

  // ---------------------------------------------------------------------------
  // CRICKET mode (v7) — EA Sports Cricket 07
  // ---------------------------------------------------------------------------
  //
  // Cricket 07 sirf keyboard par hai — is mode me na CAMERA pad
  // hai, na pedals. Do tabs hain: BATTING (swipe = shot) aur
  // BOWLING (drag = marker). Game ki asal keys (us ke apne
  // control documentation se — koi key ijad nahi ki gayi):
  // batting S = front foot, W = back foot, D = advance / run,
  // A = cancel run, Shift = lofted, arrows = shot ki simt,
  // Esc = pause; bowling S = seedhi ball, A/D/W = variations,
  // Shift = slower, arrows (lage hue) = marker ki harkat.

  /// Kaun sa tab active hai: false = BATTING, true = BOWLING.
  bool _cricketBowling = false;

  /// Chuna hua shot (batting): FRONT FOOT (S) default hai.
  /// Har clear-all par wapas FRONT FOOT ho jata hai
  /// ([_resetCricketState]).
  GameKey _cricketShotKey = GameKey.s;

  /// LOFT button is waqt daba hua hai ya nahi. Ye sirf aik
  /// haalat hai — khud koi key NAHI bhejti: Shift shot wale
  /// snapshot me tabhi shamil hota hai jab swipe fire ho
  /// (Cricket 07 me akela Shift kuch nahi karta — bilkul
  /// waisay hi).
  bool _cricketLoftHeld = false;

  /// Swipe wale shot ki 120 ms wali khirki ka timer + nasal.
  Timer? _cricketShotTimer;
  int _cricketShotGeneration = 0;

  /// Is se chhota swipe "tap" hai — koi shot nahi (ball chorna).
  static const double _cricketSwipeMinDistance = 40;

  /// Shot wala snapshot itni dair daba rehta hai — game ko aik
  /// saaf, poora press mile (momentary presses ke 150 ms se
  /// zara kam: shot ke baad agli ball par foran dusra swipe
  /// bhi lag sake).
  static const Duration _cricketShotDuration =
      Duration(milliseconds: 120);

  /// Bowling marker ki dead zone: drag ka vector kisi mehwar
  /// par itne dp se aage jaye tab woh simt ki arrow lagti hai.
  static const double _cricketMarkerDeadZone = 10;

  /// CRICKET ki arzi haalat saaf — har clear-all ke saath
  /// chalti hai (mode switch, tab switch, Settings khulna,
  /// disconnect, background — sab raste). Sources _clearAllKeys
  /// khud saaf karti hai; yahan sirf timer/nasal/jhande hain.
  /// CAMERA ULTA is me NAHI hai — woh saved pasand hai
  /// (Settings), arzi haalat nahi.
  void _resetCricketState() {
    _cricketShotTimer?.cancel();
    _cricketShotTimer = null;
    _cricketShotGeneration++;
    _cricketLoftHeld = false;
    _cricketShotKey = GameKey.s;
  }

  /// Batting tab: swipe khatam hua. Vector se 8-simti sector
  /// banta hai; chuna hua shot (aur LOFT daba ho to Shift)
  /// us ke saath aik hi snapshot me 120 ms ke liye jata hai.
  ///
  /// Simt ka hisaab (broadcast camera — game ki default):
  /// swipe ki screen simt HI arrow combo hai:
  ///   ↘ {Down, Right} on-drive   ↓ {Down} seedha
  ///   ↙ {Down, Left} cover       ← {Left} point
  ///   ↖ {Up, Left} third man     ↑ {Up} peeche (keeper ki taraf)
  ///   ↗ {Up, Right} fine leg     → {Right} leg side
  /// CAMERA ULTA on ho to dono mehwar ulta — hisaab se pehle
  /// vector palat jata hai (sector +4 wali hi baat hai).
  void _onCricketSwipe(Offset delta) {
    if (!_driving ||
        _driveMode != DriveMode.cricket ||
        _cricketBowling) {
      return;
    }
    var dx = delta.dx;
    var dy = delta.dy;
    if (delta.distance < _cricketSwipeMinDistance) {
      // Tap hai — shot nahi. Cricket 07 me ball chorna matlab
      // hai koi shot key hi na dabana; yahan bilkul wahi hota
      // hai: kuch nahi jata.
      return;
    }
    if (_settings.cricketCameraFlip) {
      dx = -dx;
      dy = -dy;
    }
    // 8-way sector: atan2 screen coordinates me hai (0° = dayein,
    // 90° = neeche), is liye sector seedha neeche wali table hai.
    final sector =
        (((math.atan2(dy, dx) / (math.pi / 4)).round() % 8) + 8) % 8;
    final keys = <GameKey>{};
    switch (sector) {
      case 0: // → leg side
        keys.add(GameKey.arrowRight);
      case 1: // ↘ on-drive
        keys
          ..add(GameKey.arrowDown)
          ..add(GameKey.arrowRight);
      case 2: // ↓ seedha
        keys.add(GameKey.arrowDown);
      case 3: // ↙ cover
        keys
          ..add(GameKey.arrowDown)
          ..add(GameKey.arrowLeft);
      case 4: // ← point
        keys.add(GameKey.arrowLeft);
      case 5: // ↖ third man
        keys
          ..add(GameKey.arrowUp)
          ..add(GameKey.arrowLeft);
      case 6: // ↑ peeche
        keys.add(GameKey.arrowUp);
      case 7: // ↗ fine leg
        keys
          ..add(GameKey.arrowUp)
          ..add(GameKey.arrowRight);
    }
    keys.add(_cricketShotKey);
    if (_cricketLoftHeld) keys.add(GameKey.shift);
    _fireCricketShot(keys);
    HapticFeedback.lightImpact();
  }

  /// Shot wala snapshot 'cricket_shot' source me 120 ms ke
  /// liye lagao. Darmiyan me dusra swipe aa jaye to naya set
  /// purani jagah le leta hai aur waqt dobara shuru hota hai
  /// (generation guard — purana timer naye shot ko nahi kaat
  /// sakta). Koi lockout NAHI hai: agli ball par foran dusra
  /// shot lagna chahiye.
  void _fireCricketShot(Set<GameKey> keys) {
    final generation = ++_cricketShotGeneration;
    _setSourceKeys('cricket_shot', keys);
    _cricketShotTimer?.cancel();
    _cricketShotTimer = Timer(_cricketShotDuration, () {
      if (_cricketShotGeneration == generation) {
        _setSourceKeys('cricket_shot', const {});
      }
    });
  }

  /// Bowling tab: drag ka vector → marker ki arrow keys
  /// ('cricket_marker' source). Har mehwar azad hai — diagonal
  /// drag par dono arrows aik saath lagti hain, bilkul game ke
  /// asal marker ki tarah. CAMERA ULTA yahan NAHI lagta (woh
  /// sirf batting swipes ke liye hai).
  void _onCricketMarkerDrag(Offset delta) {
    if (!_driving ||
        _driveMode != DriveMode.cricket ||
        !_cricketBowling) {
      return;
    }
    final keys = <GameKey>{};
    if (delta.dx <= -_cricketMarkerDeadZone) {
      keys.add(GameKey.arrowLeft);
    } else if (delta.dx >= _cricketMarkerDeadZone) {
      keys.add(GameKey.arrowRight);
    }
    if (delta.dy <= -_cricketMarkerDeadZone) {
      keys.add(GameKey.arrowUp);
    } else if (delta.dy >= _cricketMarkerDeadZone) {
      keys.add(GameKey.arrowDown);
    }
    _setSourceKeys('cricket_marker', keys);
  }

  /// Bowling drag khatam — marker ki tamam arrows chhor do.
  void _onCricketMarkerEnd() {
    _setSourceKeys('cricket_marker', const {});
  }

  /// BATTING/BOWLING tab badlo: pehle saari keys chhoro
  /// (clear-all — shot ki khirki aur marker dono saaf), phir
  /// tab badlo. Shot ki pasand bhi FRONT FOOT par wapas
  /// (clear-all ka hissa).
  void _switchCricketTab(bool bowling) {
    if (_cricketBowling == bowling) return;
    _clearAllKeys();
    setState(() => _cricketBowling = bowling);
    HapticFeedback.lightImpact();
  }

  /// Shot chuno (FRONT FOOT / BACK FOOT / ADVANCE) — sirf
  /// pasand badalti hai, koi key nahi jati. Agla swipe isi
  /// shot ko lagayega.
  void _selectCricketShot(GameKey key) {
    if (_cricketShotKey == key) return;
    setState(() => _cricketShotKey = key);
  }

  /// CAMERA ULTA toggle — saved pasand hai (Settings service),
  /// is liye wahan likhi jati hai. Settings badalte hi
  /// controller ki aam discipline chalti hai: _onSettingsChanged
  /// pehle saari keys saaf karti hai, phir screen dobara banti
  /// hai — toggle ki roshni wahan se khud taaza ho jati hai.
  void _toggleCricketCameraFlip() {
    unawaited(
      _settings.setCricketCameraFlip(!_settings.cricketCameraFlip),
    );
  }

  // ---------------------------------------------------------------------------
  // Mode switching (FR-19/FR-20/FR-21/FR-22)
  // ---------------------------------------------------------------------------

  void _switchMode(bool driving) {
    if (_driving == driving) return;
    _clearAllKeys();
    setState(() => _driving = driving);
    _updateTiltSubscription();
    _showBanner(_modeBannerText);
    _doubleHaptic();
  }

  /// Mode banner ka text. Drive mode STEERING ke ilawa ho to
  /// driving banner me us ka zikr bhi — warna user wheel dhoondta
  /// rahega ke gayab kahan gaya.
  String get _modeBannerText {
    if (!_driving) return '🚶  ON FOOT';
    return switch (_driveMode) {
      DriveMode.steering => '🚗  DRIVING',
      DriveMode.tilt => '🚗  DRIVING • TILT',
      DriveMode.controller => '🚗  DRIVING • CONTROLLER',
      DriveMode.arrows => '🚗  DRIVING • ARROWS',
      DriveMode.fly => '✈  DRIVING • FLY',
      DriveMode.cricket => '🏏  CRICKET — Cricket 07',
    };
  }

  /// Mode banner ~650ms ke liye dikhao (FR-21).
  void _showBanner(String text) {
    if (mounted) setState(() => _bannerText = text);
    _bannerTimer?.cancel();
    _bannerTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _bannerText = null);
    });
  }

  Future<void> _doubleHaptic() async {
    await HapticFeedback.lightImpact();
    await Future<void>.delayed(const Duration(milliseconds: 90));
    await HapticFeedback.lightImpact();
  }

  // ---------------------------------------------------------------------------
  // Tilt steering (v2) — phone hilane se steering
  // ---------------------------------------------------------------------------

  /// Drive-mode switch: pehle saari keys chhoro (clear-all path —
  /// mouse buttons bhi usi se zero hote hain), phir tareeqa badlo
  /// aur choice yaad kar lo (agli dafa bhi yahi milega). Tilt
  /// sensor sirf TILT me chalta hai — baqi modes me
  /// _updateTiltSubscription use band rakhta hai.
  void _switchDriveMode(DriveMode mode) {
    if (_driveMode == mode) return;
    _clearAllKeys();
    setState(() => _driveMode = mode);
    unawaited(_settings.setDriveMode(mode));
    _updateTiltSubscription();
    // Layout achanak badalne par user ko foran pata chale ke hua
    // kya hai — khaaskar TILT par, jahan steering ab ungli se
    // nahi, phone hilane se hogi.
    _showBanner(switch (mode) {
      DriveMode.steering => '🎡  STEERING — turn with your finger',
      DriveMode.tilt => '📱  TILT — tilt your phone',
      DriveMode.controller => '🎮  CONTROLLER — steer with the stick',
      DriveMode.arrows => '◀ ▶  ARROWS — tap for a small turn',
      DriveMode.fly => '✈  FLY — one handle for planes & helicopters',
      DriveMode.cricket => '🏏  CRICKET — swipe to bat, drag to bowl',
    });
  }

  /// Tilt sensor sirf tab chale jab driving + TILT + connection
  /// teeno on hon — paidal mode, STEERING mode, disconnect aur
  /// background me band. Connection ki shart is liye bhi ke
  /// disconnect ke doran chalta sensor reconnect wali pehli
  /// report me purani tilt key ghusa sakta tha; ab reconnect par
  /// sensor taaza baseline ke saath hi chalega.
  void _updateTiltSubscription() {
    if (_driving && _tiltMode && _connected) {
      _startTilt();
    } else {
      _stopTilt();
    }
  }

  void _startTilt() {
    if (_tiltSubscription != null) return;
    // Baseline aur smoothing har shuruaat par taaza — phone jis
    // haalat me pakra hai, wahi "seedha" hai.
    _resetTiltBaseline();
    _tiltHasSmooth = false;
    // Game wali raftar (20ms) lazmi mango — default raftar 200ms
    // hai; us par low-pass ke saath steering ~0.7s late ho jati,
    // khel bilkul bekaar.
    _tiltSubscription = accelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen(
      _onTiltEvent,
      onError: (Object _) {
        // Sensor na mile / stream band ho jaye to TILT khamoshi se
        // murda nahi rehta: is session ke liye STEERING par wapas
        // aa jao aur user ko bata bhi do — switch jhooti haalat
        // nahi dikhata. Save ki hui pasand nahi badalte; agli dafa
        // TILT dobara azma sakta hai. Pedals/buttons chalte rahenge.
        _stopTilt();
        if (mounted && _tiltMode) {
          _clearAllKeys();
          setState(() => _driveMode = DriveMode.steering);
          _showBanner('⚠ Tilt sensor not found — STEERING is on');
        }
      },
    );
  }

  /// Baseline ginna dobara shuru se — purana majmua saaf.
  void _resetTiltBaseline() {
    _tiltBaselineDeg = null;
    _tiltBaseSumX = 0;
    _tiltBaseSumY = 0;
    _tiltBaseStart = null;
    _tiltFlatSince = null;
  }

  void _stopTilt() {
    _tiltSubscription?.cancel();
    _tiltSubscription = null;
    _resetTiltBaseline();
    // Tilt se chal rahi steering (PWM source) bhi saath band —
    // engine reset 'pwm' source ko union se nikal deta hai.
    // Lekin engine sirf tab reset karo jab woh TILT ka ho:
    // _updateTiltSubscription har connected event par _stopTilt
    // bulata hai, aur STEERING mode me woh call wheel ki zinda
    // steering ko galti se nahi kaat sakti. (Baaki har raste par
    // _clearAllKeys engine ko waisay hi reset karta hai.)
    if (_steerSourceId == 'tilt') {
      _resetSteerEngine();
    }
  }

  void _onTiltEvent(AccelerometerEvent event) {
    // Halki low-pass smoothing — haath ki larazish (jitter) khatam.
    if (!_tiltHasSmooth) {
      _tiltSmoothX = event.x;
      _tiltSmoothY = event.y;
      _tiltHasSmooth = true;
    } else {
      const alpha = 0.25;
      _tiltSmoothX += alpha * (event.x - _tiltSmoothX);
      _tiltSmoothY += alpha * (event.y - _tiltSmoothY);
    }
    final magnitude = math.sqrt(
      _tiltSmoothX * _tiltSmoothX + _tiltSmoothY * _tiltSmoothY,
    );
    if (magnitude < 2.5) {
      // Phone bohat flat para hai — in-plane angle bharosay ke
      // qabil nahi. Aik jhatke par steering rehne do, lekin flat
      // para rahe to lagi hui steering chhor do — is app ka asool
      // hai ke koi key kabhi atakti nahi (phone meiz par rakh kar
      // chale jao to gari gol gol nahi ghumegi). Baseline rehta
      // hai — phone uthate hi steering wapas aa jati hai, kyunke
      // agla durust sample dobara feed kar dega.
      _tiltFlatSince ??= DateTime.now();
      if (_steerSourceId == 'tilt' &&
          _pwmDirectionKey != null &&
          DateTime.now().difference(_tiltFlatSince!) >=
              _tiltFlatReleaseDelay) {
        _resetSteerEngine();
      }
      return;
    }
    _tiltFlatSince = null;
    final angleDeg = math.atan2(_tiltSmoothY, _tiltSmoothX) * 180 / math.pi;
    if (_tiltBaselineDeg == null) {
      // Baseline pehli ~300ms ki readings ka AUSAT hai, aik akeli
      // reading nahi — switch dabane ki jhatka ya haath ki larazish
      // baseline ko aik taraf nahi dhakelti (warna seedha chalti
      // gari bhi halki si aik taraf kheenchti rehti).
      _tiltBaseStart ??= DateTime.now();
      _tiltBaseSumX += _tiltSmoothX;
      _tiltBaseSumY += _tiltSmoothY;
      if (DateTime.now().difference(_tiltBaseStart!) >=
          _tiltBaselineWindow) {
        _tiltBaselineDeg =
            math.atan2(_tiltBaseSumY, _tiltBaseSumX) * 180 / math.pi;
      }
      return;
    }
    // Accelerometer asal me "up" vector report karta hai (gravity
    // ke bar-aks simt). Phone ko clockwise ghumane (steer right)
    // se is vector ka device-frame angle UTNA HI BADHTA hai —
    // dono landscape simton me. Worked example (landscape-left):
    // seedha pakadne par angle 0°; 20° right ghumao par +20°.
    // Is liye delta = current − baseline hi clockwise-positive
    // hai. (v2 ka pehla hisaab baseline − current tha — woh
    // steering ko ulta kar deta: right hilao, gari left jaye.)
    var delta = angleDeg - _tiltBaselineDeg!;
    while (delta > 180) {
      delta -= 360;
    }
    while (delta < -180) {
      delta += 360;
    }
    if (delta.abs() > 100) {
      // Phone dusri landscape simt par palat diya (ya ulta kar
      // diya) — purana baseline bekaar hai. Steering chhoro aur
      // naya baseline banne do, warna aik simt ki key hamesha ke
      // liye lagi rahegi.
      _resetSteerEngine();
      _resetTiltBaseline();
      return;
    }
    // Steering seedha key nahi — normalised mor PWM engine ko do
    // (lagna 12°, chhutna 8° wali hysteresis engine ke andar hai).
    _feedTiltSteer(delta);
  }

  /// ENTER/EXIT CAR button: F key ka saaf tap + layout tabdeel (FR-19).
  ///
  /// v3: press ab 150 ms ka aik saaf, poora dabao hai aur 250 ms ki
  /// lockout ke saath — v2 me ungli ki halki larazish ya ghalti se
  /// dusra tap lag jane par game do dafa F samajhta tha (bandah bahar
  /// nikal kar dobara andar) aur button "ulta" lagta tha.
  Future<void> _onEnterExitTap() async {
    if (!_connected || _fTapInProgress) return;
    final now = DateTime.now();
    if (_lastFTapAt != null &&
        now.difference(_lastFTapAt!) < _tapLockoutDuration) {
      return;
    }
    _lastFTapAt = now;
    _fTapInProgress = true;
    // Nishana PEHLE tay kar lo: darmiyan (150ms) me user mode pill dab
    // de to ye tap mode ko dobara nahi palat-ti — warna layout game se
    // desync ho jati hai, aur pill usi desync ki marammat ke liye hai.
    final targetDriving = !_driving;
    _clearAllKeys();
    _setSourceKeys('ftap', {_settings.profile.enterExitKey});
    await Future<void>.delayed(_tapPressDuration);
    if (!mounted) {
      _fTapInProgress = false;
      return;
    }
    _setSourceKeys('ftap', const {});
    _switchMode(targetDriving);
    _fTapInProgress = false;
  }

  /// Aik saaf momentary press: key 150 ms dabi rahe, phir chhute;
  /// 250 ms tak dusra press nazarandaz (double-fire lockout).
  /// JUMP aur MAP (Esc) isi se chalte hain.
  ///
  /// Generation guard: darmiyan me mode switch/clear ho jaye to
  /// purana delayed release naye press ki key nahi kaat sakta.
  Future<void> _momentaryKeyPress(String id, GameKey key) async {
    if (!_connected) return;
    if (_tapLockouts.contains(id)) return;
    _tapLockouts.add(id);
    unawaited(
      Future<void>.delayed(_tapLockoutDuration).then((_) {
        _tapLockouts.remove(id);
      }),
    );
    final generation = (_tapGenerations[id] ?? 0) + 1;
    _tapGenerations[id] = generation;
    final source = 'tap_$id';
    _setSourceKeys(source, {key});
    await Future<void>.delayed(_tapPressDuration);
    if (_tapGenerations[id] == generation) {
      _setSourceKeys(source, const {});
    }
  }

  // ---------------------------------------------------------------------------
  // Exit / disconnect
  // ---------------------------------------------------------------------------

  Future<void> _confirmExit() async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Disconnect?'),
        content: const Text(
          'Go back and disconnect? All keys in the game will be released.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (shouldExit == true && mounted) {
      await _hid.disconnectSequence();
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _openSettings() async {
    // Settings par jane se pehle saari keys chhoro — dusri ungli se
    // pedal dabaye hue Settings khul bhi jaye to koi key game me
    // atki na rahe. (setState is liye ke RUN button ki roshni bhi
    // foran bujh jaye.)
    setState(() => _clearAllKeys());
    // Tilt sensor bhi band karo: Settings screen portrait hai, aur
    // route push karne se app pause nahi hoti — sensor chalta raha
    // to phone portrait ghumte hi (~90° ka farq) jhooti steering
    // key lag jayegi aur Settings khule hone ke bawajood game me
    // gari murti rahegi. Wapas aane par taaza baseline ke saath
    // dobara chalega.
    _stopTilt();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
    // Settings screen portrait thi — controller ki landscape wapas lagao.
    _applyLandscape();
    _updateTiltSubscription();
  }

  /// CHEATS screen kholo (v5) — Settings wala hi safety rasta:
  /// pehle saari keys chhoro aur tilt band karo, taake codes
  /// browse karte hue game me koi key atki na rahe. Wapas aane
  /// par landscape aur tilt subscription taaza ho jate hain.
  Future<void> _openCheats() async {
    setState(() => _clearAllKeys());
    _stopTilt();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const CheatsScreen()),
    );
    _applyLandscape();
    _updateTiltSubscription();
  }

  /// MISSIONS GUIDE kholo (v5) — wahi safety rasta jo CHEATS ka
  /// hai: keys pehle chhoro, tilt band, wapas par sab taaza.
  Future<void> _openGuide() async {
    setState(() => _clearAllKeys());
    _stopTilt();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const GuideScreen()),
    );
    _applyLandscape();
    _updateTiltSubscription();
  }

  Future<void> _reconnect() async {
    final address = _settings.lastDeviceAddress;
    if (address == null || _reconnecting) return;
    setState(() {
      _reconnecting = true;
      _reconnectError = null;
    });
    final error = await _hid.connectSequence(address);
    if (!mounted) return;
    setState(() {
      _reconnecting = false;
      _reconnectError = error;
    });
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // System font bohat bara ho (accessibility) to tay-shuda size ke
    // controls (pedals, RUN button, pills) phat sakte hain — controller
    // par font scale ko mehfooz hadd me rakho, layout kabhi na toote.
    final media = MediaQuery.of(context);
    final fontFactor = (media.textScaler.scale(14) / 14).clamp(0.85, 1.15);
    return MediaQuery(
      data: media.copyWith(textScaler: TextScaler.linear(fontFactor)),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _confirmExit();
        },
        child: Scaffold(
          body: PremiumBackground(
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Chhoti landscape height (chhote phones) par wheel
                  // chhota aur button cluster halka sa scale-down —
                  // warna ENTER CAR top bar ke neeche ghus sakta hai.
                  final shortScreen = constraints.maxHeight < 360;
                  final wheelSize = (constraints.maxHeight * 0.60)
                      .clamp(shortScreen ? 165.0 : 185.0, 230.0);
                  final clusterScale = shortScreen ? 0.86 : 1.0;
                  final flip = _settings.flipControls;
                  return Stack(
                    children: [
                      Positioned(
                        top: 6,
                        left: 16,
                        right: 16,
                        child: ControllerTopBar(
                          hidState: _hidState,
                          driving: _driving,
                          onModeSelected: _switchMode,
                          driveMode: _driveMode,
                          onDriveModeSelected: _switchDriveMode,
                          flipControls: flip,
                          onCheatsTap: _openCheats,
                          onGuideTap: _openGuide,
                        ),
                      ),
                      _buildModeContent(wheelSize, clusterScale),
                      // MISSION pill (v5) — sirf driving me, steering
                      // controls wali taraf upar. Top bar ki dusri
                      // satar ke neeche; wheel, pad aur cluster sab
                      // se saaf faasla (hisaab IMPROVEMENTS_V5 me).
                      // v6: FLY me MISSION nahi (jahaz me submission
                      // wala kaam nahi; Muhammad ki hidayat).
                      // v7: CRICKET me bhi nahi — woh GTA ki stage
                      // hi nahi, wahan ye pill bekaar ghus jayegi.
                      if (_driving &&
                          _driveMode != DriveMode.fly &&
                          _driveMode != DriveMode.cricket)
                        Positioned(
                          top: 82,
                          left: flip ? 32 : null,
                          right: flip ? null : 32,
                          child: _missionButton(),
                        ),
                      if (_driving && _driveMode == DriveMode.steering)
                        _buildAngleReadout(),
                      _buildGhostButtons(),
                      if (_bannerText != null) _buildBanner(),
                      if (!_connected) _buildDisconnectedOverlay(),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Mode ke controls — AnimatedSwitcher se naram tabdeeli (~250ms).
  Widget _buildModeContent(double wheelSize, double clusterScale) {
    final flip = _settings.flipControls;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.97, end: 1.0).animate(animation),
            child: child,
          ),
        );
      },
      child: _driving
          ? switch (_driveMode) {
              DriveMode.steering =>
                _buildDrivingLayer(wheelSize, flip, clusterScale),
              DriveMode.tilt => _buildTiltDrivingLayer(flip, clusterScale),
              DriveMode.controller =>
                _buildControllerDrivingLayer(flip, clusterScale),
              DriveMode.arrows =>
                _buildArrowsDrivingLayer(flip, clusterScale),
              DriveMode.fly => _buildFlyDrivingLayer(flip, clusterScale),
              DriveMode.cricket =>
                _buildCricketLayer(flip, clusterScale),
            }
          : _buildOnFootLayer(wheelSize, flip, clusterScale),
    );
  }

  /// TILT mode ki driving layer (v2): wheel wali jagah par koi
  /// wheel ya gauge nahi — BRAKE pedal neeche-left (jahan wheel
  /// tha), RACE pedal neeche-right, aur EXIT CAR + HANDBRAKE RACE
  /// ke upar bilkul steering mode wali jagah par. Steering sirf
  /// phone hilane se hoti hai (PWM engine, source 'tilt').
  /// v3: beech me CAMERA pad — BRAKE tang hai, is liye pad ko
  /// steering mode se zyada jagah milti hai.
  Widget _buildTiltDrivingLayer(bool flip, double clusterScale) {
    final profile = _settings.profile;
    // Pad ki kinariyaan: BRAKE wali taraf 34 + 97 (pedal) + 12 gap;
    // cluster wali taraf 26 + 198 (sab se chauri row) + 12 gap.
    const brakeSide = 143.0;
    const clusterSide = 236.0;
    return Stack(
      key: const ValueKey('driving-tilt'),
      children: [
        _buildCameraPad(
          left: flip ? clusterSide : brakeSide,
          right: flip ? brakeSide : clusterSide,
        ),
        Positioned(
          left: flip ? null : 34,
          right: flip ? 34 : null,
          bottom: 16,
          child: Transform.scale(
            scale: clusterScale,
            alignment: flip ? Alignment.bottomRight : Alignment.bottomLeft,
            child: _brakePedal(profile),
          ),
        ),
        Positioned(
          left: flip ? 26 : null,
          right: flip ? null : 26,
          bottom: 16,
          child: Transform.scale(
            scale: clusterScale,
            alignment: flip ? Alignment.bottomLeft : Alignment.bottomRight,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _topActionRow(profile),
                const SizedBox(height: 12),
                _racePedal(profile),
              ],
            ),
          ),
        ),
        // HORN (v5) — TILT me wheel nahi hota, is liye BRAKE ke
        // upar alag gol button (BRAKE: bottom 16, oonchai 148 →
        // upar ki kinari 164; horn bottom 176 = 12 ka gap).
        // Brake wali taraf hi rehta hai — flip par us ke saath
        // dusri taraf chala jata hai.
        Positioned(
          left: flip ? null : 53,
          right: flip ? 53 : null,
          bottom: 176,
          child: _hornButton(profile),
        ),
      ],
    );
  }

  /// CONTROLLER mode ki driving layer (v4, approved mockup v4-3):
  /// peeche halki gamepad silhouette, left par analog stick
  /// (STEER), beech me CAMERA pad, right par RACE/BRAKE trigger
  /// buttons aur un ke neeche EXIT CAR • MAP • HANDBRAKE wali
  /// gol row. Purane modes se kuch nahi badla — ye alag layer hai.
  Widget _buildControllerDrivingLayer(bool flip, double clusterScale) {
    final profile = _settings.profile;
    // Pad ki kinariyaan: stick wali taraf 34 + 148 (stick) + 12
    // gap; cluster wali taraf 26 + 198 (sab se chauri row) + 12.
    const stickSide = 194.0;
    const clusterSide = 236.0;
    return Stack(
      key: const ValueKey('driving-controller'),
      children: [
        // Gamepad silhouette — sab se peeche, sirf dikhawa
        // (IgnorePointer painter, touch is se guzar jata hai).
        const Positioned(
          left: 48,
          right: 48,
          top: 56,
          bottom: 8,
          child: CustomPaint(painter: _GamepadSilhouettePainter()),
        ),
        _buildCameraPad(
          left: flip ? clusterSide : stickSide,
          right: flip ? stickSide : clusterSide,
        ),
        Positioned(
          left: flip ? null : 34,
          right: flip ? 34 : null,
          bottom: 16,
          child: Transform.scale(
            scale: clusterScale,
            alignment: flip ? Alignment.bottomRight : Alignment.bottomLeft,
            child: AnalogStick(
              size: 148,
              onSteerChanged: _feedStickSteer,
            ),
          ),
        ),
        Positioned(
          left: flip ? 26 : null,
          right: flip ? null : 26,
          bottom: 16,
          child: Transform.scale(
            scale: clusterScale,
            alignment: flip ? Alignment.bottomLeft : Alignment.bottomRight,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _raceTrigger(profile),
                const SizedBox(height: 10),
                _brakeTrigger(profile),
                const SizedBox(height: 12),
                _topActionRow(profile),
                const SizedBox(height: 10),
                // HORN (v5) — action row ke neeche, cluster ki
                // chauraai (198) ke beech me gol button.
                SizedBox(
                  width: 198,
                  child: Center(child: _hornButton(profile)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// ARROWS mode ki driving layer (v4, approved mockup v4-4):
  /// left par do baray ◀ ▶ buttons (saaf gap ke saath), beech me
  /// CAMERA pad, right par bilkul steering mode wala cluster
  /// (action row + BRAKE/RACE pedals). Tap = halki si move
  /// (minimum pulse), dabaye rakho = lagi hui steering.
  Widget _buildArrowsDrivingLayer(bool flip, double clusterScale) {
    final profile = _settings.profile;
    // Pad ki kinariyaan: arrows wali taraf 30 + 88 + 16 + 88 +
    // 12 gap; cluster wali taraf steering mode wali hi (236).
    const arrowsSide = 234.0;
    const clusterSide = 236.0;
    final arrows = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ◀ hamesha pair ke left par — flip par pair dusri taraf
        // jata hai, lekin teeron ki simt nahi palat-ti (warna
        // steering ulti ho jayegi).
        SteerArrowButton(
          left: true,
          onHeldChanged: (held) => _onArrowHeldChanged(true, held),
        ),
        const SizedBox(width: 16),
        SteerArrowButton(
          left: false,
          onHeldChanged: (held) => _onArrowHeldChanged(false, held),
        ),
      ],
    );
    return Stack(
      key: const ValueKey('driving-arrows'),
      children: [
        _buildCameraPad(
          left: flip ? clusterSide : arrowsSide,
          right: flip ? arrowsSide : clusterSide,
        ),
        Positioned(
          left: flip ? null : 30,
          right: flip ? 30 : null,
          bottom: 84,
          child: Transform.scale(
            scale: clusterScale,
            alignment: flip ? Alignment.bottomRight : Alignment.bottomLeft,
            child: arrows,
          ),
        ),
        // HORN (v5) — arrows wali taraf, pair ke upar gol button
        // (pair ki upar wali kinari bottom 84 + 88 = 172 from
        // bottom; horn top 126 → pair se 12 ka gap, MISSION pill
        // (neeche 82..114) se bhi 12 ka gap).
        Positioned(
          left: flip ? null : 97,
          right: flip ? 97 : null,
          top: 126,
          child: _hornButton(profile, diameter: 50),
        ),
        Positioned(
          left: flip ? 26 : null,
          right: flip ? null : 26,
          bottom: 16,
          child: Transform.scale(
            scale: clusterScale,
            alignment: flip ? Alignment.bottomLeft : Alignment.bottomRight,
            child: _buildDrivingCluster(profile),
          ),
        ),
      ],
    );
  }

  /// FLY column ke upar wali chhoti sky-blue sar-khiti (caption).
  Widget _flyCaption(String text) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 2.5,
        color: Color(0xFF7DD3FC),
      ),
    );
  }

  /// FLY mode ki driving layer (v6) — Muhammad ki corrected
  /// design: aik HANDLE (stick) jo mor aur naak dono deta hai,
  /// dusri taraf RACE + DOWN pedals, beech me CAMERA pad aur us
  /// ke neeche EXIT/MAP. Na HORN hai na MISSION (pill build() me
  /// FLY ke liye band hai). Tafseel + hisaab IMPROVEMENTS_V6.md.
  ///
  /// Geometry (640×360): side margins 16; handle column 196
  /// (stick 176 + HANDLE caption); pedals column 118; beech ke
  /// gaps 12; CAMERA column = 640 − 16 − 196 − 12 − 118 − 12
  /// − 16 = 270 chauri. Side columns top 84, bottom 16; CAMERA
  /// column bottom 72 taake EXIT/MAP row centre ke ghost
  /// buttons (y ≥ 295) se na takraye — baqi modes ke pad wali
  /// hi hifazat. Flip par handle ↔ pedals tarafain badalti
  /// hain; CAMERA beech me rehta hai (pitch hamesha central).
  ///
  /// Pedals poore [CarPedal] widgets nahi hain: RACE (192) +
  /// BRAKE (148) upar-neeche 340 ban-te hain jo 260 ke stage
  /// me nahi sama sakte — is liye [_FlyPedal] unhi rangon wale
  /// compact pedal pads hain (hisaab QA doc me).
  Widget _buildFlyDrivingLayer(bool flip, double clusterScale) {
    final profile = _settings.profile;
    final handle = Positioned(
      left: flip ? null : 16,
      right: flip ? 16 : null,
      top: 84,
      bottom: 16,
      width: 196,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Transform.scale(
            scale: clusterScale,
            child: FlyStick(size: 176, onAxesChanged: _feedFlyStick),
          ),
        ],
      ),
    );
    final pedals = Positioned(
      left: flip ? 16 : null,
      right: flip ? null : 16,
      top: 84,
      bottom: 16,
      width: 118,
      child: Transform.scale(
        scale: clusterScale,
        alignment: Alignment.bottomCenter,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            _flyCaption('THROTTLE'),
            const SizedBox(height: 6),
            _FlyPedal(
              height: 118,
              label: 'RACE',
              subLabel: '${profile.accelerateKey.label} — speed / climb',
              gradientTop: const Color(0xFF22C55E),
              gradientBottom: const Color(0xFF15803D),
              borderColor: const Color(0xFF86EFAC),
              glow: const Color(0xFF22C55E),
              onHeldChanged: (held) {
                _setSourceKeys(
                  'race',
                  held ? {profile.accelerateKey} : const {},
                );
              },
            ),
            const SizedBox(height: 10),
            _FlyPedal(
              height: 84,
              label: 'DOWN',
              subLabel: '${profile.brakeKey.label} — brake / descend',
              gradientTop: const Color(0xFFEF4444),
              gradientBottom: const Color(0xFFB91C1C),
              borderColor: const Color(0xFFFCA5A5),
              glow: const Color(0xFFEF4444),
              onHeldChanged: (held) {
                _setSourceKeys(
                  'brake',
                  held ? {profile.brakeKey} : const {},
                );
              },
            ),
          ],
        ),
      ),
    );
    final camera = Positioned(
      left: flip ? 146 : 224,
      right: flip ? 224 : 146,
      top: 84,
      bottom: 72,
      child: Column(
        children: [
          _flyCaption('CAMERA'),
          const SizedBox(height: 6),
          Expanded(
            child: CameraPad(
              onMove: (dx, dy) => _hid.moveMouse(dx, dy),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _enterExitButton(),
              const SizedBox(width: 12),
              _mapButton(),
            ],
          ),
        ],
      ),
    );
    return Stack(
      key: const ValueKey('driving-fly'),
      children: [camera, handle, pedals],
    );
  }

  /// CRICKET mode ki layer (v7) — approved mockups
  /// (v7-cricket-mode-4 batting, v7-cricket-bowling bowling):
  /// aik taraf gesture hissa (upar BATTING/BOWLING tabs),
  /// darmiyan me patli lakeer, dusri taraf SAARE buttons aik
  /// hi cluster me — chhote gol 76 dp, 3 ke grid me, koi
  /// button khincha hua (stretched) nahi. Flip controls par
  /// cluster aur gesture tarafain badal lete hain — baqi
  /// modes wali mirroring yahan bhi sasti par gayi (sirf
  /// left/right ki qeemtain palat-ti hain).
  ///
  /// Geometry (640×360): stage top 84 (top bar ki dono satron
  /// ke neeche, FLY wali hi hifazat). Cluster 252 chaura
  /// (3 × 76 + 2 × 12) aur 252 uncha (3 satrain) — 260 unche
  /// stage me beech me rehta hai; chhote screens par
  /// clusterScale (0.86) use halka chhota karta hai, baqi
  /// modes ki tarah. Gesture hissa = 640 − 16 (margin) − 252
  /// (cluster) − 25 (lakeer + 2 × gap) − 16 (margin) = 331
  /// chaura — 330 ki kam-az-kam shart poori. Gesture ka
  /// neeche kinara bottom 72 par hai: centre ke ghost buttons
  /// (Settings/Disconnect, x ≈ 266…374, y ≥ 300) se wahi
  /// hifazat jo CAMERA pad ki hai. Cluster neeche tak ja
  /// sakta hai kyunke woh x ≥ 372 se shuru hota hai — ghost
  /// zone se bahar (visual kinara 371 par khatam hota hai).
  Widget _buildCricketLayer(bool flip, double clusterScale) {
    final gesture = Positioned(
      top: 84,
      bottom: 72,
      left: flip ? 293 : 16,
      right: flip ? 16 : 293,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CricketTabSwitch(
            bowling: _cricketBowling,
            onSelected: _switchCricketTab,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _cricketBowling
                ? CricketBowlingArea(
                    onDragChanged: _onCricketMarkerDrag,
                    onDragEnd: _onCricketMarkerEnd,
                  )
                : CricketBattingArea(onSwipe: _onCricketSwipe),
          ),
        ],
      ),
    );
    final divider = Positioned(
      top: 100,
      bottom: 88,
      left: flip ? null : 359,
      right: flip ? 359 : null,
      width: 1,
      child: Container(color: Colors.white.withValues(alpha: 0.10)),
    );
    final cluster = Positioned(
      top: 84,
      bottom: 16,
      left: flip ? 16 : null,
      right: flip ? null : 16,
      width: 252,
      child: Transform.scale(
        scale: clusterScale,
        alignment: flip ? Alignment.centerLeft : Alignment.centerRight,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: _cricketBowling
              ? _bowlingClusterRows()
              : _battingClusterRows(),
        ),
      ),
    );
    return Stack(
      key: const ValueKey('driving-cricket'),
      children: [gesture, divider, cluster],
    );
  }

  /// CRICKET ka gol button (76 dp) — [RoundButton] hi hai,
  /// bas cricket ke rang aik jagah tay hain taake tamam
  /// buttons bilkul aik jaise lagen: aam = gehra sabz glass,
  /// selected/go = roshan sabz, LOFT = narangi (mockup wala).
  Widget _cricketRoundButton({
    required String label,
    String? subLabel,
    bool selected = false,
    bool loft = false,
    bool go = false,
    VoidCallback? onTap,
    ValueChanged<bool>? onHeldChanged,
  }) {
    final Color top;
    final Color bottom;
    final Color border;
    if (loft) {
      top = const Color(0xFF8A5A18);
      bottom = const Color(0xFF4A2E08);
      border = const Color(0xFFF7931E);
    } else if (selected || go) {
      top = const Color(0xFF1D6A38);
      bottom = const Color(0xFF0E3D1F);
      border = const Color(0xFF2EE66B);
    } else {
      top = const Color(0xFF16241B);
      bottom = const Color(0xFF0A140D);
      border = const Color(0xFF4B5563);
    }
    return RoundButton(
      diameter: 76,
      label: label,
      subLabel: subLabel,
      gradientTop: top,
      gradientBottom: bottom,
      borderColor: border,
      lit: selected,
      onTap: onTap,
      onHeldChanged: onHeldChanged,
    );
  }

  /// BATTING cluster ki teen satrain (mockup v7-cricket-mode-4):
  /// shot chunna (FRONT FOOT / BACK FOOT / ADVANCE), phir
  /// LOFT (hold) + RUN + CANCEL, aakhir me PAUSE + MENU +
  /// CAMERA ULTA. RUN/CANCEL/PAUSE/MENU saaf-tap wale helper
  /// ([_momentaryKeyPress], 150 ms + lockout) se jate hain.
  List<Widget> _battingClusterRows() {
    return [
      Row(
        children: [
          _cricketRoundButton(
            label: 'FRONT\nFOOT',
            subLabel: 'S',
            selected: _cricketShotKey == GameKey.s,
            onTap: () => _selectCricketShot(GameKey.s),
          ),
          const SizedBox(width: 12),
          _cricketRoundButton(
            label: 'BACK\nFOOT',
            subLabel: 'W',
            selected: _cricketShotKey == GameKey.w,
            onTap: () => _selectCricketShot(GameKey.w),
          ),
          const SizedBox(width: 12),
          _cricketRoundButton(
            label: 'ADVANCE',
            subLabel: 'D',
            selected: _cricketShotKey == GameKey.d,
            onTap: () => _selectCricketShot(GameKey.d),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          _cricketRoundButton(
            label: 'LOFT',
            subLabel: 'Shift',
            loft: true,
            // Sirf haalat note hoti hai — Shift shot wale
            // snapshot me swipe ke waqt shamil hota hai
            // (_onCricketSwipe dekho). Akela LOFT dabane se
            // koi key nahi jati, bilkul game ki tarah.
            onHeldChanged: (held) => _cricketLoftHeld = held,
          ),
          const SizedBox(width: 12),
          _cricketRoundButton(
            label: 'RUN',
            subLabel: 'D',
            go: true,
            onTap: () => _momentaryKeyPress('cricket_run', GameKey.d),
          ),
          const SizedBox(width: 12),
          _cricketRoundButton(
            label: 'CANCEL',
            subLabel: 'A',
            onTap: () =>
                _momentaryKeyPress('cricket_cancel', GameKey.a),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          _cricketRoundButton(
            label: 'PAUSE',
            subLabel: 'Esc',
            onTap: () =>
                _momentaryKeyPress('cricket_pause', GameKey.escape),
          ),
          const SizedBox(width: 12),
          _cricketRoundButton(
            label: 'MENU',
            subLabel: 'S',
            onTap: () => _momentaryKeyPress('cricket_menu', GameKey.s),
          ),
          const SizedBox(width: 12),
          _cricketRoundButton(
            label: 'CAMERA\nULTA',
            subLabel: 'Flip',
            selected: _settings.cricketCameraFlip,
            onTap: _toggleCricketCameraFlip,
          ),
        ],
      ),
    ];
  }

  /// BOWLING cluster ki satrain (mockup v7-cricket-bowling):
  /// delivery buttons + PAUSE + MENU + CAMERA ULTA.
  ///
  /// VARIATION 1/2/3 ke naam jaan-boojh kar aam (generic)
  /// hain: kaunsi key konsi ball deti hai, ye BOWLER par
  /// munhasir hai (fast bowler ki swing/cutter, spinner ki
  /// dusri variations) aur game khud screen par har delivery
  /// ka naam dikhata hai. Button par jhoota tay naam likhna
  /// galat rahnumai hoti — is liye sirf number + asal key.
  /// Saare delivery buttons momentary hain (150 ms saaf tap);
  /// SLOWER sirf Shift modifier ka snapshot hai.
  List<Widget> _bowlingClusterRows() {
    return [
      Row(
        children: [
          _cricketRoundButton(
            label: 'SEEDHI\nBALL',
            subLabel: 'S',
            go: true,
            onTap: () =>
                _momentaryKeyPress('cricket_bowl_stock', GameKey.s),
          ),
          const SizedBox(width: 12),
          _cricketRoundButton(
            label: 'VARIATION\n1',
            subLabel: 'A',
            onTap: () =>
                _momentaryKeyPress('cricket_bowl_var1', GameKey.a),
          ),
          const SizedBox(width: 12),
          _cricketRoundButton(
            label: 'VARIATION\n2',
            subLabel: 'D',
            onTap: () =>
                _momentaryKeyPress('cricket_bowl_var2', GameKey.d),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          _cricketRoundButton(
            label: 'VARIATION\n3',
            subLabel: 'W',
            onTap: () =>
                _momentaryKeyPress('cricket_bowl_var3', GameKey.w),
          ),
          const SizedBox(width: 12),
          _cricketRoundButton(
            label: 'SLOWER',
            subLabel: 'Shift',
            onTap: () => _momentaryKeyPress(
              'cricket_bowl_slower',
              GameKey.shift,
            ),
          ),
          const SizedBox(width: 12),
          _cricketRoundButton(
            label: 'PAUSE',
            subLabel: 'Esc',
            onTap: () =>
                _momentaryKeyPress('cricket_pause', GameKey.escape),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          _cricketRoundButton(
            label: 'MENU',
            subLabel: 'S',
            onTap: () => _momentaryKeyPress('cricket_menu', GameKey.s),
          ),
          const SizedBox(width: 12),
          _cricketRoundButton(
            label: 'CAMERA\nULTA',
            subLabel: 'Flip',
            selected: _settings.cricketCameraFlip,
            onTap: _toggleCricketCameraFlip,
          ),
        ],
      ),
    ];
  }

  /// CONTROLLER mode ka RACE trigger — bara sabz hold button
  /// (pedal wala hi behaviour, gamepad wali shakal).
  Widget _raceTrigger(GameProfile profile) {
    return _TriggerButton(
      label: 'RACE',
      subLabel: profile.accelerateKey.label,
      gradientTop: const Color(0xFF22C55E),
      gradientBottom: const Color(0xFF15803D),
      borderColor: const Color(0xFF86EFAC),
      glow: const Color(0xFF22C55E),
      onHeldChanged: (held) {
        _setSourceKeys('race', held ? {profile.accelerateKey} : const {});
      },
    );
  }

  /// CONTROLLER mode ka BRAKE trigger — RACE ke bilkul neeche,
  /// laal hold button.
  Widget _brakeTrigger(GameProfile profile) {
    return _TriggerButton(
      label: 'BRAKE',
      subLabel: profile.brakeKey.label,
      gradientTop: const Color(0xFFEF4444),
      gradientBottom: const Color(0xFFB91C1C),
      borderColor: const Color(0xFFFCA5A5),
      glow: const Color(0xFFEF4444),
      onHeldChanged: (held) {
        _setSourceKeys('brake', held ? {profile.brakeKey} : const {});
      },
    );
  }

  /// CAMERA pad — dono taraf ke controls se kam az kam 12 dp gap
  /// ke saath beech ki khali jagah par. Upar top bar (sab se unchi
  /// chrome ~51 par khatam) se 13, neeche ghost buttons se 12.
  /// Stack me pehle rakha hai taake kisi overlap ki surat me
  /// buttons hamesha upar rahen.
  Widget _buildCameraPad({required double left, required double right}) {
    return Positioned(
      left: left,
      right: right,
      top: 64,
      bottom: 72,
      child: CameraPad(
        onMove: (dx, dy) => _hid.moveMouse(dx, dy),
      ),
    );
  }

  /// Cluster ki sab se upar wali row: ENTER/EXIT • MAP • HANDBRAKE.
  /// Teeno driving clusters (steering/tilt) yahi istemal karte hain
  /// taake positions kabhi drift na hon.
  Widget _topActionRow(GameProfile profile) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _enterExitButton(),
        const SizedBox(width: 12),
        _mapButton(),
        const SizedBox(width: 12),
        _handbrakeButton(profile),
      ],
    );
  }

  Widget _buildDrivingLayer(double wheelSize, bool flip, double clusterScale) {
    final profile = _settings.profile;
    final wheel = SteeringWheel(
      size: wheelSize,
      rangeDeg: _settings.steeringRangeDeg,
      sensitivity: _settings.sensitivity.factor,
      onAngleChanged: (angle) {
        _wheelAngle.value = angle;
        _feedWheelSteer(angle);
      },
      // Hub dabaye rakho = HORN (v5) — source 'horn', profile
      // ki horn key (SA: H, GTA V: E).
      onHornHeldChanged: (held) {
        _setSourceKeys('horn', held ? {profile.hornKey} : const {});
      },
    );
    final cluster = _buildDrivingCluster(profile);
    // Pad ki kinariyaan: wheel wali taraf 34 + wheel + 12 gap;
    // cluster wali taraf 26 + 198 (sab se chauri row) + 12 gap.
    final wheelSide = 34 + wheelSize + 12;
    const clusterSide = 236.0;
    return Stack(
      key: const ValueKey('driving'),
      children: [
        _buildCameraPad(
          left: flip ? clusterSide : wheelSide,
          right: flip ? wheelSide : clusterSide,
        ),
        Positioned(
          left: flip ? null : 34,
          right: flip ? 34 : null,
          bottom: 20,
          child: wheel,
        ),
        Positioned(
          left: flip ? 26 : null,
          right: flip ? null : 26,
          bottom: 16,
          child: Transform.scale(
            scale: clusterScale,
            alignment: flip ? Alignment.bottomLeft : Alignment.bottomRight,
            child: cluster,
          ),
        ),
      ],
    );
  }

  Widget _buildOnFootLayer(double wheelSize, bool flip, double clusterScale) {
    final profile = _settings.profile;
    final joystick = WasdJoystick(
      size: wheelSize * 0.88,
      onKeysChanged: (keys) => _setSourceKeys('joystick', keys),
    );
    final cluster = _buildOnFootCluster(profile);
    // Pad ki kinariyaan: joystick wali taraf 44 + joystick + 12 gap;
    // cluster wali taraf 26 + 220 (sab se chauri row) + 12 gap.
    // Paidal mode me camera sab se zyada chalta hai (chalna +
    // dekhna + swimming ki simt) — pad yahan jaan hai.
    final joystickSide = 44 + wheelSize * 0.88 + 12;
    const clusterSide = 258.0;
    return Stack(
      key: const ValueKey('onfoot'),
      children: [
        _buildCameraPad(
          left: flip ? clusterSide : joystickSide,
          right: flip ? joystickSide : clusterSide,
        ),
        Positioned(
          left: flip ? null : 44,
          right: flip ? 44 : null,
          bottom: 26,
          child: joystick,
        ),
        // Weapon switch (v4) — joystick ke upar wali khali jagah
        // me chhoti si pair: ◀ pichla hathyar, ▶ agla (mouse wheel
        // ke ticks). Joystick wali taraf hi rehti hai (flip par
        // joystick ke saath dusri taraf), cluster se takrati nahi.
        Positioned(
          left: flip ? null : 44,
          right: flip ? 44 : null,
          top: 64,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _WeaponTickButton(
                forward: false,
                onTick: () => _hid.wheelTick(-1),
              ),
              const SizedBox(width: 8),
              _WeaponTickButton(
                forward: true,
                onTick: () => _hid.wheelTick(1),
              ),
              const SizedBox(width: 12),
              // TAB (v5) — property khareedne waghera ke liye
              // ("Press TAB to buy the property"): CROUCH/MAP
              // wala hi saaf-tap helper. Row ab joystick wali
              // taraf 44..232 tak hai — CAMERA pad (246 se) se
              // 14 ka gap barqarar.
              _tabButton(),
            ],
          ),
        ),
        Positioned(
          left: flip ? 26 : null,
          right: flip ? null : 26,
          bottom: 16,
          child: Transform.scale(
            scale: clusterScale,
            alignment: flip ? Alignment.bottomLeft : Alignment.bottomRight,
            child: cluster,
          ),
        ),
      ],
    );
  }

  /// ENTER/EXIT CAR gol button — dono modes me bilkul wahi jagah:
  /// right cluster ki sab se upar wali row, pehli position.
  /// Racing Cockpit: garam orange gradient.
  Widget _enterExitButton() {
    return RoundButton(
      diameter: 58,
      label: _driving ? 'EXIT\nCAR' : 'ENTER\nCAR',
      subLabel: _settings.profile.enterExitKey.label,
      gradientTop: const Color(0xFFFB923C),
      gradientBottom: const Color(0xFFC2410C),
      borderColor: const Color(0xFFFDBA74),
      onTap: _onEnterExitTap,
    );
  }

  /// MAP button (v3) — Esc ka saaf tap. SA Original me map pause
  /// menu ke andar hai; ye wahi menu kholta hai, phir CAMERA pad
  /// wahan pointer hai aur (paidal mode me) ATTACK click hai.
  /// Dono layouts me action row ki dusri position — jagah nahi
  /// badalti.
  Widget _mapButton() {
    return RoundButton(
      diameter: 58,
      label: 'MAP',
      subLabel: GameKey.escape.label,
      gradientTop: const Color(0xFF475569),
      gradientBottom: const Color(0xFF1E293B),
      borderColor: const Color(0xFF94A3B8),
      onTap: () => _momentaryKeyPress('map', GameKey.escape),
    );
  }

  /// HANDBRAKE gol button — action row ki teesri position (driving),
  /// garam red gradient (Racing Cockpit).
  Widget _handbrakeButton(GameProfile profile) {
    return RoundButton(
      diameter: 58,
      label: 'HAND\nBRAKE',
      subLabel: profile.handbrakeKey.label,
      gradientTop: const Color(0xFFEF4444),
      gradientBottom: const Color(0xFFB91C1C),
      borderColor: const Color(0xFFFCA5A5),
      onHeldChanged: (held) {
        _setSourceKeys(
          'handbrake',
          held ? {profile.handbrakeKey} : const {},
        );
      },
    );
  }

  /// HORN gol button (v5) — dabaye rakho to horn bajta hai,
  /// chhoro to band (source 'horn', profile ki horn key: SA me
  /// H, GTA V me E — emergency gariyon me yahi key siren bhi
  /// chalati hai). TILT aur CONTROLLER/ARROWS modes me istemal
  /// hota hai; STEERING me horn wheel ke hub me hai.
  Widget _hornButton(GameProfile profile, {double diameter = 58}) {
    return RoundButton(
      diameter: diameter,
      label: 'HORN',
      subLabel: profile.hornKey.label,
      gradientTop: const Color(0xFFF59E0B),
      gradientBottom: const Color(0xFFB45309),
      borderColor: const Color(0xFFFCD34D),
      onHeldChanged: (held) {
        _setSourceKeys('horn', held ? {profile.hornKey} : const {});
      },
    );
  }

  /// MISSION pill (v5, sirf driving) — vehicle side-missions
  /// (taxi, vigilante, ambulance…) shuru karne wali key ka aik
  /// saaf tap: SA me Caps Lock, GTA V me E (profile ki
  /// submissionKey), MAP/JUMP wala hi 150 ms + lockout helper.
  /// SA me ye key toggle hai — dusra tap mission band karta hai,
  /// bilkul asal keyboard ki tarah.
  Widget _missionButton() {
    final profile = _settings.profile;
    return _PillButton(
      width: 108,
      height: 32,
      label: 'MISSION',
      subLabel: profile.submissionKey.label,
      gradientTop: const Color(0xFF0369A1),
      gradientBottom: const Color(0xFF0C4A6E),
      borderColor: const Color(0xFF38BDF8),
      onTap: () => _momentaryKeyPress('mission', profile.submissionKey),
    );
  }

  /// ATTACK button (v3, sirf paidal mode) — mouse ka LEFT button.
  /// Dabaye rakho to daba rehta hai (larai/fire), chhoro to chhut
  /// jata hai. Mouse button ki haalat HidService rakhta hai aur har
  /// safety path (mode switch, disconnect, pause, dispose) par
  /// zero hoti hai — click atak nahi sakta.
  /// v4: setMouseButton se sirf apna bit badalta hai — AIM (right
  /// button) aik saath daba ho to woh nahi kat-ta.
  Widget _attackButton() {
    return RoundButton(
      diameter: 80,
      label: 'ATTACK',
      subLabel: 'Mouse',
      gradientTop: const Color(0xFFDC2626),
      gradientBottom: const Color(0xFF7F1D1D),
      borderColor: const Color(0xFFFCA5A5),
      onHeldChanged: (held) {
        _hid.setMouseButton(HidService.mouseButtonLeft, held);
      },
    );
  }

  /// AIM button (v4, sirf paidal mode) — mouse ka RIGHT button,
  /// dabaye rakho. SA ki gunplay: AIM dabaye rakh kar ATTACK se
  /// fire hota hai — dono mouse buttons HidService me alag bits
  /// hain, aik saath dab sakte hain, aur har safety path par dono
  /// zero hote hain (releaseAllKeys).
  Widget _aimButton() {
    return _PillButton(
      width: 96,
      height: 48,
      label: 'AIM',
      subLabel: 'Mouse R',
      gradientTop: const Color(0xFF475569),
      gradientBottom: const Color(0xFF1E293B),
      borderColor: const Color(0xFF94A3B8),
      onHeldChanged: (held) {
        _hid.setMouseButton(HidService.mouseButtonRight, held);
      },
    );
  }

  /// CROUCH button (v4, sirf paidal mode) — C key ka aik saaf
  /// tap. SA me C crouch toggle hai: aik tap = baithna, dusra
  /// tap = khara hona. Is liye hold nahi, momentary press hai
  /// (150 ms + lockout, JUMP/MAP wala hi helper).
  Widget _crouchButton() {
    return _PillButton(
      width: 92,
      height: 48,
      label: 'CROUCH',
      subLabel: GameKey.c.label,
      gradientTop: const Color(0xFF4B5563),
      gradientBottom: const Color(0xFF1F2937),
      borderColor: const Color(0xFF9CA3AF),
      onTap: () => _momentaryKeyPress('crouch', GameKey.c),
    );
  }

  /// TAB pill (v5, sirf paidal mode) — Tab key ka aik saaf tap,
  /// weapon-switch pair ke saath wali row me. GTA ke woh lamhe
  /// jahan game kehta hai "Press TAB" (property khareedna,
  /// stats dekhna) — pehle remote me ye key thi hi nahi.
  Widget _tabButton() {
    return _PillButton(
      width: 72,
      height: 48,
      label: 'TAB',
      gradientTop: const Color(0xFF4B5563),
      gradientBottom: const Color(0xFF1F2937),
      borderColor: const Color(0xFF9CA3AF),
      onTap: () => _momentaryKeyPress('tab', GameKey.tab),
    );
  }

  /// BRAKE pedal — chaura chhota pad, red pehchan.
  Widget _brakePedal(GameProfile profile) {
    return CarPedal(
      label: 'BRAKE',
      subLabel: profile.brakeKey.label,
      accent: const Color(0xFFF87171),
      tall: false,
      onHeldChanged: (held) {
        _setSourceKeys(
          'brake',
          held ? {profile.brakeKey} : const {},
        );
      },
    );
  }

  /// RACE pedal — lamba tang pad, green pehchan.
  Widget _racePedal(GameProfile profile) {
    return CarPedal(
      label: 'RACE',
      subLabel: profile.accelerateKey.label,
      accent: const Color(0xFF4ADE80),
      tall: true,
      onHeldChanged: (held) {
        _setSourceKeys(
          'race',
          held ? {profile.accelerateKey} : const {},
        );
      },
    );
  }

  Widget _buildDrivingCluster(GameProfile profile) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _topActionRow(profile),
        const SizedBox(height: 12),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // BRAKE pehla (left), RACE baad me (right) — final design (v2).
            _brakePedal(profile),
            const SizedBox(width: 20),
            _racePedal(profile),
          ],
        ),
      ],
    );
  }

  Widget _buildOnFootCluster(GameProfile profile) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _enterExitButton(),
            const SizedBox(width: 12),
            _mapButton(),
            const SizedBox(width: 12),
            // ATTACK action row ki teesri position par — driving me
            // yahi jagah HANDBRAKE ki hai; ungli ki jagah nahi badalti.
            _attackButton(),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _RunToggleButton(
              on: _runOn,
              keyLabel: profile.sprintKey.label,
              onTap: () {
                setState(() => _runOn = !_runOn);
                _setSourceKeys(
                  'run',
                  _runOn ? {profile.sprintKey} : const {},
                );
              },
            ),
            const SizedBox(width: 18),
            RoundButton(
              diameter: 80,
              label: 'JUMP',
              subLabel: profile.jumpKey.label,
              gradientTop: const Color(0xFF4B5563),
              gradientBottom: const Color(0xFF1F2937),
              borderColor: const Color(0xFFFB923C),
              // v3: JUMP ab hold nahi — aik saaf 150 ms press
              // (lockout ke saath), bilkul ENTER/EXIT ki tarah.
              onTap: () =>
                  _momentaryKeyPress('jump', profile.jumpKey),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Teesri (secondary) row (v4): AIM + CROUCH — compact pill
        // buttons. Row ki chauraai (200) pehli row (220) se kam
        // hai, is liye CAMERA pad ki jagah bilkul nahi badli.
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _aimButton(),
            const SizedBox(width: 12),
            _crouchButton(),
          ],
        ),
      ],
    );
  }

  /// Centre screen par chhota steering angle readout (SRS §7.2).
  /// Sirf ye chhota sa text dobara banta hai jab angle badle —
  /// poori screen nahi (ValueNotifier). Touch is par se guzar jata hai.
  Widget _buildAngleReadout() {
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      bottom: 0,
      child: IgnorePointer(
        child: Center(
          child: ValueListenableBuilder<double>(
            valueListenable: _wheelAngle,
            builder: (context, angle, _) {
              if (angle.abs() < 1) return const SizedBox.shrink();
              final arrow = angle < 0 ? '◀' : '▶';
              return Text(
                '$arrow ${angle.abs().round()}°',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: const Color(0xFF94A3B8).withValues(alpha: 0.85),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Neeche centre me chhote ghost buttons: Settings + Disconnect.
  /// (Top bar me sirf status + mode pill hai — revised design.)
  Widget _buildGhostButtons() {
    return Positioned(
      bottom: 12,
      left: 0,
      right: 0,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _GhostIconButton(icon: Icons.settings, onTap: _openSettings),
            const SizedBox(width: 12),
            _GhostIconButton(
              icon: Icons.power_settings_new,
              onTap: _confirmExit,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBanner() {
    return Positioned(
      top: 76,
      left: 0,
      right: 0,
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.85, end: 1.0),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          builder: (context, scale, child) {
            return Transform.scale(scale: scale, child: child);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF020617).withValues(alpha: 0.78),
              border: Border.all(color: const Color(0xFFF97316), width: 1.5),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              _bannerText!,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Connection kat jaye to controls band + bara warning (FR-30).
  Widget _buildDisconnectedOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.74),
        child: Center(
          child: Container(
            width: 340,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF10141B),
              border: Border.all(color: const Color(0xFF374151)),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.bluetooth_disabled,
                  size: 44,
                  color: Color(0xFFEF4444),
                ),
                const SizedBox(height: 12),
                const Text(
                  '⚠ Connection lost',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Bluetooth disconnected. All keys have been released — the car will not drive on its own.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                ),
                if (_reconnectError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _reconnectError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFF87171),
                      fontSize: 13.5,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _reconnecting ? null : _reconnect,
                  icon: _reconnecting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const Icon(Icons.bluetooth_connected),
                  label: Text(_reconnecting ? 'Connecting…' : 'Reconnect'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFEA580C),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 26,
                      vertical: 13,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Back — Connect screen'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// RUN toggle — aik tap par bhagna on (lit), dusre tap par off (FR-16).
/// Baqi controls ki tarah raw pointer par chalta hai: ungli LAGTE hi
/// toggle hota hai (tap ke uthne ka intezar nahi) — game me har
/// millisecond keemti hai, aur gesture arena ka koi jhanjhat nahi.
class _RunToggleButton extends StatefulWidget {
  const _RunToggleButton({
    required this.on,
    required this.keyLabel,
    required this.onTap,
  });

  final bool on;
  final String keyLabel;
  final VoidCallback onTap;

  @override
  State<_RunToggleButton> createState() => _RunToggleButtonState();
}

class _RunToggleButtonState extends State<_RunToggleButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final on = widget.on;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) {
        setState(() => _pressed = true);
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 100,
          height: 63,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: on
                  ? const [Color(0xFFFBBF24), Color(0xFFD97706)]
                  : const [Color(0xFFF59E0B), Color(0xFFB45309)],
            ),
            border: Border.all(
              color: const Color(0xFFFCD34D),
              width: on ? 3 : 2,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF59E0B)
                    .withValues(alpha: on ? 0.55 : 0.32),
                blurRadius: on ? 26 : 16,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'RUN',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  color: Colors.white,
                ),
              ),
              Text(
                on ? '● RUNNING' : widget.keyLabel,
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1,
                  fontWeight: on ? FontWeight.w800 : FontWeight.w400,
                  color: const Color(0xFFFEF3C7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// CONTROLLER mode ka trigger button (v4) — chaura gol-kinara
/// hold button, gamepad ke trigger jaisa (RACE/BRAKE).
/// HoldSurface par banta hai — pedals wala hi capture behaviour:
/// ungli slide ho jaye to bhi press nahi toot-ta.
class _TriggerButton extends StatelessWidget {
  const _TriggerButton({
    required this.label,
    required this.subLabel,
    required this.gradientTop,
    required this.gradientBottom,
    required this.borderColor,
    required this.glow,
    required this.onHeldChanged,
  });

  final String label;
  final String subLabel;
  final Color gradientTop;
  final Color gradientBottom;
  final Color borderColor;
  final Color glow;
  final ValueChanged<bool> onHeldChanged;

  @override
  Widget build(BuildContext context) {
    return HoldSurface(
      onHeldChanged: (held) {
        if (held) HapticFeedback.lightImpact();
        onHeldChanged(held);
      },
      builder: (context, pressed) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, pressed ? 2 : 0, 0),
          width: 198,
          height: 54,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [gradientTop, gradientBottom],
            ),
            border: Border.all(
              color: borderColor,
              width: pressed ? 3 : 2,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: glow.withValues(alpha: pressed ? 0.5 : 0.28),
                blurRadius: pressed ? 24 : 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.5,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                subLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Compact pill button (v4) — paidal mode ki secondary row ke
/// liye (AIM hold, CROUCH tap). RoundButton wala hi raw-pointer
/// tareeqa: aik ungli ki malikiyat, dispose par khud release.
class _PillButton extends StatefulWidget {
  const _PillButton({
    required this.width,
    required this.height,
    required this.label,
    this.subLabel,
    required this.gradientTop,
    required this.gradientBottom,
    required this.borderColor,
    this.onTap,
    this.onHeldChanged,
  });

  final double width;
  final double height;
  final String label;
  final String? subLabel;
  final Color gradientTop;
  final Color gradientBottom;
  final Color borderColor;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onHeldChanged;

  @override
  State<_PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<_PillButton> {
  int? _pointer;
  bool _pressed = false;

  void _down(int pointer) {
    if (_pointer != null) return;
    _pointer = pointer;
    setState(() => _pressed = true);
    HapticFeedback.lightImpact();
    if (widget.onHeldChanged != null) {
      widget.onHeldChanged!(true);
    } else {
      widget.onTap?.call();
    }
  }

  void _up(int pointer) {
    if (pointer != _pointer) return;
    _pointer = null;
    setState(() => _pressed = false);
    widget.onHeldChanged?.call(false);
  }

  @override
  void dispose() {
    if (_pressed) widget.onHeldChanged?.call(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) => _down(event.pointer),
      onPointerUp: (event) => _up(event.pointer),
      onPointerCancel: (event) => _up(event.pointer),
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [widget.gradientTop, widget.gradientBottom],
            ),
            border: Border.all(
              color: widget.borderColor,
              width: _pressed ? 3 : 2,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: widget.gradientBottom
                    .withValues(alpha: _pressed ? 0.5 : 0.3),
                blurRadius: _pressed ? 20 : 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                widget.label,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                  color: Colors.white,
                ),
              ),
              if (widget.subLabel != null) ...[
                const SizedBox(width: 7),
                Text(
                  widget.subLabel!,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Weapon switch button (v4) — chhota sa ◀ / ▶, mouse wheel ka
/// tick bhejta hai. Aik tap = aik tick (aik hathyar aage/peeche);
/// dabaye rakho to pehle 400 ms baad har 200 ms par tick — kayi
/// hathyar hon to list tezi se guzar jati hai. Chhorne/cancel/
/// dispose par repeat khud band — koi timer latka nahi rehta.
class _WeaponTickButton extends StatefulWidget {
  const _WeaponTickButton({required this.forward, required this.onTick});

  /// True = agla hathyar (▶), false = pichla (◀).
  final bool forward;

  /// Aik wheel tick bhejo.
  final VoidCallback onTick;

  @override
  State<_WeaponTickButton> createState() => _WeaponTickButtonState();
}

class _WeaponTickButtonState extends State<_WeaponTickButton> {
  int? _pointer;
  bool _pressed = false;
  Timer? _repeatTimer;

  void _stopRepeat() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
  }

  void _down(int pointer) {
    if (_pointer != null) return;
    _pointer = pointer;
    setState(() => _pressed = true);
    HapticFeedback.lightImpact();
    widget.onTick();
    _stopRepeat();
    _repeatTimer = Timer(const Duration(milliseconds: 400), () {
      _repeatTimer = Timer.periodic(
        const Duration(milliseconds: 200),
        (_) => widget.onTick(),
      );
    });
  }

  void _up(int pointer) {
    if (pointer != _pointer) return;
    _pointer = null;
    _stopRepeat();
    setState(() => _pressed = false);
  }

  @override
  void dispose() {
    _stopRepeat();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) => _down(event.pointer),
      onPointerUp: (event) => _up(event.pointer),
      onPointerCancel: (event) => _up(event.pointer),
      child: AnimatedScale(
        scale: _pressed ? 0.93 : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF2A313B), Color(0xFF12161D)],
            ),
            border: Border.all(
              color: _pressed
                  ? const Color(0xFFF97316)
                  : const Color(0xFF4B5563),
              width: 2,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                widget.forward ? '▶' : '◀',
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.0,
                  color: Color(0xFFF59E0B),
                ),
              ),
              const Text(
                'WPN',
                style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// CONTROLLER mode ke peeche ki halki gamepad silhouette (v4,
/// mockup v4-3) — aik bara gol-kinara wala khaka aur neeche dono
/// taraf grip wale gol hisse. Sirf dikhawa hai: rang bohat halka,
/// aur ye painter touch ko chhuta hi nahi (Positioned ke andar
/// CustomPaint hit-test nahi karta, upar ke controls apni jagah
/// par hain).
class _GamepadSilhouettePainter extends CustomPainter {
  const _GamepadSilhouettePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFFF97316).withValues(alpha: 0.16);
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white.withValues(alpha: 0.025);

    // Body — bohat gol kinaron wala bara khaka.
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height * 0.88),
      Radius.circular(size.height * 0.42),
    );
    canvas.drawRRect(body, fill);
    canvas.drawRRect(body, stroke);

    // Grips — neeche dono konon par gol ubhar (controller ke
    // pakadne wale hisse), khake se halke se bahar tak.
    final gripRadius = size.height * 0.30;
    for (final cx in [size.width * 0.07, size.width * 0.93]) {
      final grip = Rect.fromCircle(
        center: Offset(cx, size.height * 0.86),
        radius: gripRadius,
      );
      canvas.drawOval(grip, fill);
      canvas.drawOval(grip, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// FLY mode ka compact pedal pad (v6) — [CarPedal] ke rangon
/// wala hold button, magar baghair metal arm/labels ke, taake
/// RACE + DOWN upar-neeche aik column me sama jayein (poore
/// CarPedal 192 + 148 = 340 dp hote hain; stage sirf 260 dp
/// hai — hisaab IMPROVEMENTS_V6.md me). Behaviour bilkul
/// pedal wala hai: [HoldSurface] ungli capture karta hai,
/// slide-out par bhi press nahi toot-ta, dispose par press
/// khud chhut jata hai.
class _FlyPedal extends StatelessWidget {
  const _FlyPedal({
    required this.height,
    required this.label,
    required this.subLabel,
    required this.gradientTop,
    required this.gradientBottom,
    required this.borderColor,
    required this.glow,
    required this.onHeldChanged,
  });

  final double height;
  final String label;
  final String subLabel;
  final Color gradientTop;
  final Color gradientBottom;
  final Color borderColor;
  final Color glow;
  final ValueChanged<bool> onHeldChanged;

  @override
  Widget build(BuildContext context) {
    return HoldSurface(
      onHeldChanged: onHeldChanged,
      builder: (context, pressed) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: 118,
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [gradientTop, gradientBottom],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: borderColor.withValues(alpha: pressed ? 0.95 : 0.55),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: glow.withValues(alpha: pressed ? 0.4 : 0.15),
                blurRadius: pressed ? 20 : 10,
              ),
              const BoxShadow(
                color: Color(0x73000000),
                blurRadius: 14,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subLabel,
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.5,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// CRICKET ke BATTING | BOWLING tabs (v7) — SteerModeSwitch
/// wali hi gol-patti shakal, cricket ke sabz rangon me.
/// Tap par controller tab badalta hai (keys saaf karna usi
/// ka kaam hai — ye widget sirf pasand batata hai).
class _CricketTabSwitch extends StatelessWidget {
  const _CricketTabSwitch({
    required this.bowling,
    required this.onSelected,
  });

  /// True = BOWLING tab active hai.
  final bool bowling;

  /// Naya tab chuna gaya (true = BOWLING).
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF060C08).withValues(alpha: 0.7),
        border: Border.all(
          color: const Color(0xFF2EE66B).withValues(alpha: 0.45),
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(
            '🏏 BATTING',
            active: !bowling,
            onTap: () => onSelected(false),
          ),
          _segment(
            'BOWLING',
            active: bowling,
            onTap: () => onSelected(true),
          ),
        ],
      ),
    );
  }

  Widget _segment(
    String label, {
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF2EE66B).withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: active
                ? const Color(0xFF7BF79F)
                : const Color(0xFFDFE9EF),
          ),
        ),
      ),
    );
  }
}

/// Neeche centre ke chhote translucent icon buttons.
/// Nazar 42dp ka gol button ata hai, lekin chhune ka hissa 48dp hai —
/// ungli se miss kam hota hai.
class _GhostIconButton extends StatelessWidget {
  const _GhostIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF020617).withValues(alpha: 0.55),
              border: Border.all(color: const Color(0xFF374151)),
            ),
            child: Icon(icon, size: 20, color: const Color(0xFFCBD5E1)),
          ),
        ),
      ),
    );
  }
}
