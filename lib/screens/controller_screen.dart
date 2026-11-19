import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
/// Layout (Muhammad ki revised design):
/// - Top bar: sirf status pill (left) + mode pill (right).
/// - ENTER/EXIT CAR gol button pedals ke cluster ke UPAR, HANDBRAKE ke
///   saath — dono modes me bilkul wahi jagah.
/// - Pedals: RACE pehla (left), BRAKE baad me (right).
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
  double _wheelAngleDeg = 0;

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
      } else {
        WakelockPlus.disable();
        _clearAllKeys();
      }
    });
    if (_connected) WakelockPlus.enable();
    _settings.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
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
    // App background me jaye to saari keys chhor do (FR-29).
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _clearAllKeys();
      _hid.releaseAllKeys();
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
    setState(() {
      _driving = driving;
      _bannerText = driving ? '🚗  DRIVING' : '🚶  ON FOOT';
    });
    _doubleHaptic();
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

  /// ENTER/EXIT CAR button: F key tap + layout tabdeel (FR-19).
  Future<void> _onEnterExitTap() async {
    if (!_connected || _fTapInProgress) return;
    _fTapInProgress = true;
    _clearAllKeys();
    _setSourceKeys('ftap', {_settings.profile.enterExitKey});
    await Future<void>.delayed(const Duration(milliseconds: 130));
    if (!mounted) return;
    _setSourceKeys('ftap', const {});
    _switchMode(!_driving);
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
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
    // Settings screen portrait thi — controller ki landscape wapas lagao.
    _applyLandscape();
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        body: PremiumBackground(
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wheelSize =
                    (constraints.maxHeight * 0.60).clamp(185.0, 230.0);
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
                      ),
                    ),
                    _buildModeContent(wheelSize),
                    if (_driving) _buildAngleReadout(),
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
    );
  }

  /// Mode ke controls — AnimatedSwitcher se naram tabdeeli (~250ms).
  Widget _buildModeContent(double wheelSize) {
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
          ? _buildDrivingLayer(wheelSize, flip)
          : _buildOnFootLayer(wheelSize, flip),
    );
  }

  Widget _buildDrivingLayer(double wheelSize, bool flip) {
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
      onAngleChanged: (angle) {
        if (mounted) setState(() => _wheelAngleDeg = angle);
      },
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
          child: cluster,
        ),
      ],
    );
  }

  Widget _buildOnFootLayer(double wheelSize, bool flip) {
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
          child: cluster,
        ),
      ],
    );
  }

  /// ENTER/EXIT CAR gol button — dono modes me bilkul wahi jagah:
  /// right cluster ki sab se upar wali row, pehli position.
  Widget _enterExitButton() {
    return RoundButton(
      diameter: 68,
      label: _driving ? 'EXIT\nCAR' : 'ENTER\nCAR',
      subLabel: _settings.profile.enterExitKey.label,
      gradientTop: const Color(0xFF14B8A6),
      gradientBottom: const Color(0xFF0F766E),
      borderColor: const Color(0xFF2DD4BF),
      onTap: _onEnterExitTap,
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
            RoundButton(
              diameter: 68,
              label: 'HAND\nBRAKE',
              subLabel: profile.handbrakeKey.label,
              gradientTop: const Color(0xFFF59E0B),
              gradientBottom: const Color(0xFFB45309),
              borderColor: const Color(0xFFFCD34D),
              onHeldChanged: (held) {
                _setSourceKeys(
                  'handbrake',
                  held ? {profile.handbrakeKey} : const {},
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // RACE pehla (left), BRAKE baad me (right) — revised design.
            CarPedal(
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
            ),
            const SizedBox(width: 20),
            CarPedal(
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
            ),
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
              gradientTop: const Color(0xFF38BDF8),
              gradientBottom: const Color(0xFF0369A1),
              borderColor: const Color(0xFF7DD3FC),
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
  Widget _buildAngleReadout() {
    final angle = _wheelAngleDeg;
    if (angle.abs() < 1) return const SizedBox.shrink();
    final arrow = angle < 0 ? '◀' : '▶';
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      bottom: 0,
      child: Center(
        child: Text(
          '$arrow ${angle.abs().round()}°',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            color: const Color(0xFF94A3B8).withValues(alpha: 0.85),
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
              border: Border.all(color: const Color(0xFF2DD4BF), width: 1.5),
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
              color: const Color(0xFF0B1220),
              border: Border.all(color: const Color(0xFF334155)),
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
                    backgroundColor: const Color(0xFF0F766E),
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
class _RunToggleButton extends StatelessWidget {
  const _RunToggleButton({
    required this.on,
    required this.keyLabel,
    required this.onTap,
  });

  final bool on;
  final String keyLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
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
              on ? '● RUNNING' : keyLabel,
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
    );
  }
}

/// Neeche centre ke chhote translucent icon buttons.
class _GhostIconButton extends StatelessWidget {
  const _GhostIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF020617).withValues(alpha: 0.55),
          border: Border.all(color: const Color(0xFF334155)),
        ),
        child: Icon(icon, size: 20, color: const Color(0xFFCBD5E1)),
      ),
    );
  }
}
