import 'package:flutter/material.dart';

/// FLY mode ka handle (v6) — jahaz/helicopter ke liye aik hi
/// stick jo mor (left/right) aur naak (up/down) dono deta hai.
///
/// Mechanics [AnalogStick] wali hi hain (gol base, ungli ke
/// saath chalta knob, chhorne par naram spring se centre
/// wapas) — farq sirf itna ke ye DONO mehwar (axes) report
/// karta hai: x = −1 (poora left) .. +1 (poora right),
/// y = −1 (poora upar) .. +1 (poora neeche). Dead zone (0.25)
/// aur axes → keys ki mapping controller ki FLY feed ke paas
/// hai; stick sirf khaam (raw) qeemtain deta hai.
///
/// Ungli uthte hi (0, 0) report hota hai — knob ki wapsi
/// animation sirf dikhawa hai, keys pehle chhut-ti hain.
/// Widget khatam (dispose) ho aur mor laga ho to bhi (0, 0)
/// jata hai, taake koi key atak na jaye.
class FlyStick extends StatefulWidget {
  const FlyStick({
    super.key,
    required this.size,
    required this.onAxesChanged,
  });

  /// Base ka diameter (dp).
  final double size;

  /// Dono mehwar badlein to: (x, y), har aik −1..+1.
  final void Function(double x, double y) onAxesChanged;

  @override
  State<FlyStick> createState() => _FlyStickState();
}

class _FlyStickState extends State<FlyStick>
    with SingleTickerProviderStateMixin {
  Offset _knobOffset = Offset.zero;
  int? _pointer;
  double _lastX = 0;
  double _lastY = 0;
  bool _active = false;

  late final AnimationController _returnController;
  Animation<Offset>? _returnAnimation;

  double get _knobSize => widget.size * 0.44;

  /// Knob centre kitna safar kar sakta hai — base ke andar rehte
  /// hue. Isi safar par mehwar ±1 banta hai.
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
    // Widget khatam ho raha ho aur koi mehwar laga ho to foran
    // (0, 0) — koi key atak nahi sakti.
    if (_lastX != 0 || _lastY != 0) {
      _lastX = 0;
      _lastY = 0;
      widget.onAxesChanged(0, 0);
    }
    _returnController.dispose();
    super.dispose();
  }

  void _report(Offset offset) {
    final x = (offset.dx / _maxTravel).clamp(-1.0, 1.0).toDouble();
    final y = (offset.dy / _maxTravel).clamp(-1.0, 1.0).toDouble();
    if ((x - _lastX).abs() < 0.001 && (y - _lastY).abs() < 0.001) {
      return;
    }
    _lastX = x;
    _lastY = y;
    widget.onAxesChanged(x, y);
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
    // Pehle (0, 0) report karo (keys foran chhutein), knob ki
    // wapas animation us ke baad sirf dikhawa hai.
    if (_lastX != 0 || _lastY != 0) {
      _lastX = 0;
      _lastY = 0;
      widget.onAxesChanged(0, 0);
    }
    _returnAnimation = Tween<Offset>(begin: _knobOffset, end: Offset.zero)
        .animate(
      CurvedAnimation(parent: _returnController, curve: Curves.easeOut),
    );
    _returnController.forward(from: 0);
  }

  /// Base ke kinare par aik simt ka teer — knob ke safar se
  /// bahar, hamesha nazar aata hai (handle ki chaar simtain).
  Widget _arrow(Alignment alignment, String glyph) {
    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: Text(
          glyph,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF7DD3FC).withValues(alpha: 0.75),
          ),
        ),
      ),
    );
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
                // Base — gehra gol ghaira, FLY ki sky-blue kinari.
                Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      colors: [Color(0xFF1D2A38), Color(0xFF0B0E13)],
                      stops: [0.0, 0.78],
                    ),
                    border: Border.all(
                      color: _active
                          ? const Color(0xFF38BDF8)
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
                // Chaar simton ke teer — upar = naak upar,
                // neeche = naak neeche, left/right = mor.
                _arrow(Alignment.topCenter, '▲'),
                _arrow(Alignment.bottomCenter, '▼'),
                _arrow(Alignment.centerLeft, '◀'),
                _arrow(Alignment.centerRight, '▶'),
                // Knob — gunmetal gola, sky-blue kinari.
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
                        color: const Color(0xFF38BDF8),
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
        // AnalogStick ke 'STEER' caption jaisa naam.
        const Text(
          'HANDLE',
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
