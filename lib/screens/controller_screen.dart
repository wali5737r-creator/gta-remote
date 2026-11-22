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
///   ARROWS).
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
                      if (_driving)
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
