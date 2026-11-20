import 'package:flutter/material.dart';

/// Analog stick — CONTROLLER mode ki steering (v4).
///
/// Gol base ke andar knob ungli ke saath chalta hai aur chhorne par
/// naram spring se centre wapas aa jata hai (WasdJoystick wala
/// tareeqa). Stick sirf normalised mor (−1..+1) report karta hai;
/// dead zone (0.12) aur PWM pulses controller ki steering engine
/// ke hain — bilkul wheel/tilt ki tarah.
///
/// Mor ka hisaab: knob ke poore safar (base ke kinare tak) par
/// ±1 — poora mor = poora lock. Ungli uthte hi 0 report hota hai
/// (knob ki animation sirf dikhawa hai, key pehle chhut-ti hai).
class AnalogStick extends StatefulWidget {
  const AnalogStick({
    super.key,
    required this.size,
    required this.onSteerChanged,
  });

  /// Base ka diameter (dp).
  final double size;

  /// Normalised mor badle to: −1 (poora left) .. +1 (poora right).
  /// Sirf horizontal hisaa steering hai — stick har simt ja sakta
  /// hai, lekin game ko sirf left/right chahiye.
  final ValueChanged<double> onSteerChanged;

  @override
  State<AnalogStick> createState() => _AnalogStickState();
}

class _AnalogStickState extends State<AnalogStick>
    with SingleTickerProviderStateMixin {
  Offset _knobOffset = Offset.zero;
  int? _pointer;
  double _lastSteer = 0;
  bool _active = false;

  late final AnimationController _returnController;
  Animation<Offset>? _returnAnimation;

  double get _knobSize => widget.size * 0.44;

  /// Knob centre kitna safar kar sakta hai — base ke andar rehte
  /// hue. Isi safar par mor ±1 banta hai.
  double get _maxTravel => widget.size / 2 - _knobSize / 2 - 4;

  @override
  void initState() {
    super.initState();
    _returnController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 130),
    )..addListener(() {
        final animation = _returnAnimation;
        if (animation == null) return;
        setState(() => _knobOffset = animation.value);
      });
  }

  @override
  void dispose() {
    // Widget khatam ho raha ho aur mor laga ho to foran 0 —
    // koi steering atak nahi sakti.
    if (_lastSteer != 0) {
      _lastSteer = 0;
      widget.onSteerChanged(0);
    }
    _returnController.dispose();
    super.dispose();
  }

  void _report(Offset offset) {
    final steer =
        (offset.dx / _maxTravel).clamp(-1.0, 1.0).toDouble();
    if ((steer - _lastSteer).abs() < 0.001) return;
    _lastSteer = steer;
    widget.onSteerChanged(steer);
  }

  void _updateFromPosition(Offset localPosition) {
    final centre = Offset(widget.size / 2, widget.size / 2);
    final vector = localPosition - centre;
    final length = vector.distance;
    final clamped = length > _maxTravel
        ? vector * (_maxTravel / length)
        : vector;
    setState(() => _knobOffset = clamped);
    _report(clamped);
  }

  void _release() {
    _pointer = null;
    setState(() => _active = false);
    // Pehle mor 0 report karo (key foran chhute), knob ki wapas
    // animation us ke baad sirf dikhawa hai.
    if (_lastSteer != 0) {
      _lastSteer = 0;
      widget.onSteerChanged(0);
    }
    _returnAnimation = Tween<Offset>(begin: _knobOffset, end: Offset.zero)
        .animate(
      CurvedAnimation(parent: _returnController, curve: Curves.easeOut),
    );
    _returnController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final knobSize = _knobSize;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            if (_pointer != null) return;
            _pointer = event.pointer;
            _returnController.stop();
            setState(() => _active = true);
            _updateFromPosition(event.localPosition);
          },
          onPointerMove: (event) {
            if (event.pointer != _pointer) return;
            _updateFromPosition(event.localPosition);
          },
          onPointerUp: (event) {
            if (event.pointer == _pointer) _release();
          },
          onPointerCancel: (event) {
            if (event.pointer == _pointer) _release();
          },
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              children: [
                // Base — gehra gol ghaira, gamepad stick jaisa.
                Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      colors: [Color(0xFF232A35), Color(0xFF0B0E13)],
                      stops: [0.0, 0.78],
                    ),
                    border: Border.all(
                      color: _active
                          ? const Color(0xFFF97316)
                          : const Color(0xFF374151),
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.55),
                        blurRadius: 22,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                ),
                // Knob — gunmetal gola, orange kinari (mockup jaisa).
                Positioned(
                  left: (size - knobSize) / 2 + _knobOffset.dx,
                  top: (size - knobSize) / 2 + _knobOffset.dy,
                  child: Container(
                    width: knobSize,
                    height: knobSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        center: Alignment(-0.35, -0.4),
                        radius: 1.05,
                        colors: [Color(0xFF9FB0C3), Color(0xFF39424F)],
                      ),
                      border: Border.all(
                        color: const Color(0xFFF97316),
                        width: 2.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.6),
                          blurRadius: 16,
                          offset: const Offset(0, 7),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        // Mockup (v4-3) ke mutabiq stick ke neeche chhota sa naam.
        const Text(
          'STEER',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 3,
            color: Color(0xFF8FA3B8),
          ),
        ),
      ],
    );
  }
}
