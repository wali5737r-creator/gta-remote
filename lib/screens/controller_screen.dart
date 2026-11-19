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
import '../widgets/car_pedal.dart';
import '../widgets/joystick.dart';
import '../widgets/premium_background.dart';
import '../widgets/round_button.dart';
import '../widgets/steering_wheel.dart';
import '../widgets/top_bar.dart';
import 'settings_screen.dart';

/// Controller screen — Driving aur On Foot dono modes.
///
/// Har control apni keys ka "source" rakhta hai (wheel, race, joystick…);
/// tamam sources ka union hi HID report banta hai. Is design se koi key
/// atak nahi sakti: source saaf = key gayi.
///
/// Layout (Muhammad ki design, v2 — Racing Cockpit):
/// - Top bar: status pill (left) + mode pill (right); driving me
///   beech me STEERING | TILT switch.
/// - ENTER/EXIT CAR gol button pedals ke cluster ke UPAR, HANDBRAKE ke
///   saath — dono modes me bilkul wahi jagah.
/// - Pedals: BRAKE pehla (left), RACE baad me (right).
/// - TILT mode me wheel nahi hota: BRAKE neeche-left, RACE
///   neeche-right, aur steering phone hilane se hoti hai.
/// - Wheel ke neeche koi caption text nahi.
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

  /// Steering ka tareeqa (sirf driving me): false = touch wheel
  /// (STEERING), true = phone hilana (TILT). Settings se restore
  /// hota hai aur switch se badalte hi wahan save ho jata hai.
  bool _tiltMode = false;

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
  /// tilt key chhor dete hain (koi key atak nahi sakti).
  DateTime? _tiltFlatSince;

  /// Low-pass smoothing ke baad ki gravity (phone ke x/y axes par).
  double _tiltSmoothX = 0;
  double _tiltSmoothY = 0;
  bool _tiltHasSmooth = false;

  /// Tilt se is waqt lagi hui steering key (source 'tilt').
  GameKey? _tiltKey;

  /// Itne degrees se zyada jhukao par key lagti hai…
  static const double _tiltEngageDeg = 12;

  /// …aur itne se kam par chhut-ti hai (hysteresis — wheel ki tarah,
  /// taake hadd par key jhatkay na khaye).
  static const double _tiltReleaseDeg = 8;

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
    _tiltMode = _settings.tiltSteering;
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
    _hid.releaseAllKeys();
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

  /// Mode banner ka text. TILT ki purani pasand restore hui ho to
  /// driving banner me us ka zikr bhi — warna user wheel dhoondta
  /// rahega ke gayab kahan gaya.
  String get _modeBannerText => _driving
      ? (_tiltMode ? '🚗  DRIVING • TILT' : '🚗  DRIVING')
      : '🚶  ON FOOT';

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

  /// STEERING | TILT switch: pehle saari keys chhoro, phir tareeqa
  /// badlo aur choice yaad kar lo (agli dafa bhi yahi milega).
  void _switchSteerMode(bool tilt) {
    if (_tiltMode == tilt) return;
    _clearAllKeys();
    setState(() => _tiltMode = tilt);
    unawaited(_settings.setTiltSteering(tilt));
    _updateTiltSubscription();
    // Wheel achanak gayab/maujood hone par user ko foran pata chale
    // ke hua kya hai — khaaskar TILT par, jahan steering ab ungli
    // se nahi, phone hilane se hogi.
    _showBanner(
      tilt ? '📱  TILT — phone hilao' : '🎡  STEERING — ungli se ghumao',
    );
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
    _tiltKey = null;
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
          setState(() => _tiltMode = false);
          _showBanner('⚠ Tilt sensor nahi mila — STEERING on hai');
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
    if (_tiltKey != null) {
      _tiltKey = null;
      _setSourceKeys('tilt', const {});
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
      // qabil nahi. Aik jhatke par key rehne do, lekin flat para
      // rahe to lagi hui key chhor do — is app ka asool hai ke
      // koi key kabhi atakti nahi (phone meiz par rakh kar chale
      // jao to gari gol gol nahi ghumegi).
      _tiltFlatSince ??= DateTime.now();
      if (_tiltKey != null &&
          DateTime.now().difference(_tiltFlatSince!) >=
              _tiltFlatReleaseDelay) {
        _tiltKey = null;
        _setSourceKeys('tilt', const {});
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
      // diya) — purana baseline bekaar hai. Key chhoro aur naya
      // baseline banne do, warna aik simt ki key hamesha ke liye
      // lagi rahegi.
      if (_tiltKey != null) {
        _tiltKey = null;
        _setSourceKeys('tilt', const {});
      }
      _resetTiltBaseline();
      return;
    }
    _evaluateTilt(delta);
  }

  /// Tilt angle se steering key — hysteresis ke saath (lagna 12°,
  /// chhutna 8°), bilkul wheel ke dead-zone wale asool par. Key
  /// source 'tilt' hai — pedals ke saath union me shamil hoti hai.
  void _evaluateTilt(double deltaDeg) {
    final profile = _settings.profile;
    final left = profile.steerLeftKey;
    final right = profile.steerRightKey;
    GameKey? key = _tiltKey;
    if (key == right) {
      if (deltaDeg < -_tiltEngageDeg) {
        key = left;
      } else if (deltaDeg <= _tiltReleaseDeg) {
        key = null;
      }
    } else if (key == left) {
      if (deltaDeg > _tiltEngageDeg) {
        key = right;
      } else if (deltaDeg >= -_tiltReleaseDeg) {
        key = null;
      }
    } else if (deltaDeg > _tiltEngageDeg) {
      key = right;
    } else if (deltaDeg < -_tiltEngageDeg) {
      key = left;
    } else {
      key = null;
    }
    if (key != _tiltKey) {
      _tiltKey = key;
      _setSourceKeys('tilt', key == null ? const {} : {key});
    }
  }

  /// ENTER/EXIT CAR button: F key tap + layout tabdeel (FR-19).
  Future<void> _onEnterExitTap() async {
    if (!_connected || _fTapInProgress) return;
    _fTapInProgress = true;
    // Nishana PEHLE tay kar lo: darmiyan (130ms) me user mode pill dab
    // de to ye tap mode ko dobara nahi palat-ti — warna layout game se
    // desync ho jati hai, aur pill usi desync ki marammat ke liye hai.
    final targetDriving = !_driving;
    _clearAllKeys();
    _setSourceKeys('ftap', {_settings.profile.enterExitKey});
    await Future<void>.delayed(const Duration(milliseconds: 130));
    if (!mounted) return;
    _setSourceKeys('ftap', const {});
    _switchMode(targetDriving);
    _fTapInProgress = false;
  }

  // ---------------------------------------------------------------------------
  // Exit / disconnect
  // ---------------------------------------------------------------------------

  Future<void> _confirmExit() async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Disconnect karun?'),
        content: const Text(
          'Disconnect karke wapas jayen? Game me saari keys chhut jayengi.',
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
                  return Stack(
                    children: [
                      Positioned(
                        top: 8,
                        left: 16,
                        right: 16,
                        child: ControllerTopBar(
                          hidState: _hidState,
                          driving: _driving,
                          onModeSelected: _switchMode,
                          tiltMode: _tiltMode,
                          onSteerModeSelected: _switchSteerMode,
                        ),
                      ),
                      _buildModeContent(wheelSize, clusterScale),
                      if (_driving && !_tiltMode) _buildAngleReadout(),
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
          ? (_tiltMode
              ? _buildTiltDrivingLayer(flip, clusterScale)
              : _buildDrivingLayer(wheelSize, flip, clusterScale))
          : _buildOnFootLayer(wheelSize, flip, clusterScale),
    );
  }

  /// TILT mode ki driving layer (v2): wheel wali jagah par koi
  /// wheel ya gauge nahi — BRAKE pedal neeche-left (jahan wheel
  /// tha), RACE pedal neeche-right, aur EXIT CAR + HANDBRAKE RACE
  /// ke upar bilkul steering mode wali jagah par. Steering sirf
  /// phone hilane se hoti hai (source 'tilt').
  Widget _buildTiltDrivingLayer(bool flip, double clusterScale) {
    final profile = _settings.profile;
    return Stack(
      key: const ValueKey('driving-tilt'),
      children: [
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
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _enterExitButton(),
                    const SizedBox(width: 14),
                    _handbrakeButton(profile),
                  ],
                ),
                const SizedBox(height: 10),
                _racePedal(profile),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDrivingLayer(double wheelSize, bool flip, double clusterScale) {
    final profile = _settings.profile;
    final wheel = SteeringWheel(
      size: wheelSize,
      rangeDeg: _settings.steeringRangeDeg,
      deadZoneDeg: _settings.deadZoneDeg,
      sensitivity: _settings.sensitivity.factor,
      onSteeringKeyChanged: (key) {
        _setSourceKeys(
          'wheel',
          key == null ? const {} : {key},
        );
      },
      onAngleChanged: (angle) => _wheelAngle.value = angle,
    );
    final cluster = _buildDrivingCluster(profile);
    return Stack(
      key: const ValueKey('driving'),
      children: [
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
    return Stack(
      key: const ValueKey('onfoot'),
      children: [
        Positioned(
          left: flip ? null : 44,
          right: flip ? 44 : null,
          bottom: 26,
          child: joystick,
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
      diameter: 68,
      label: _driving ? 'EXIT\nCAR' : 'ENTER\nCAR',
      subLabel: _settings.profile.enterExitKey.label,
      gradientTop: const Color(0xFFFB923C),
      gradientBottom: const Color(0xFFC2410C),
      borderColor: const Color(0xFFFDBA74),
      onTap: _onEnterExitTap,
    );
  }

  /// HANDBRAKE gol button — ENTER/EXIT ke saath wali position,
  /// garam red gradient (Racing Cockpit).
  Widget _handbrakeButton(GameProfile profile) {
    return RoundButton(
      diameter: 68,
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
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _enterExitButton(),
            const SizedBox(width: 14),
            _handbrakeButton(profile),
          ],
        ),
        const SizedBox(height: 10),
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
            // HANDBRAKE ki jagah khali — ENTER CAR ki position na badle.
            const SizedBox(width: 82),
          ],
        ),
        const SizedBox(height: 30),
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
              diameter: 94,
              label: 'JUMP',
              subLabel: profile.jumpKey.label,
              gradientTop: const Color(0xFF4B5563),
              gradientBottom: const Color(0xFF1F2937),
              borderColor: const Color(0xFFFB923C),
              onHeldChanged: (held) {
                _setSourceKeys(
                  'jump',
                  held ? {profile.jumpKey} : const {},
                );
              },
            ),
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
                  'Bluetooth kat gaya hai. Saari keys chhut gayi hain — gari apne aap nahi chalegi.',
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
                  label: Text(_reconnecting ? 'Connect ho raha…' : 'Reconnect'),
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
                  child: const Text('Wapas — Connect screen'),
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
          width: 118,
          height: 74,
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
