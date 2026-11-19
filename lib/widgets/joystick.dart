import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/game_key.dart';

/// Fixed-base 8-way WASD joystick — paidal mode ke liye (FR-15).
///
/// Base wahi jagah hai jahan driving me wheel hota hai. Stick ki simt
/// 8 hisson (45° sectors) me taqseem hoti hai; har simt WASD ka
/// combination bhejti hai. Centre dead zone me koi key nahi jati.
class WasdJoystick extends StatefulWidget {
  const WasdJoystick({
    super.key,
    required this.size,
    required this.onKeysChanged,
  });

  final double size;

  /// Joystick ki keys tabdeel hon to (masalan {W, D}).
  final ValueChanged<Set<GameKey>> onKeysChanged;

  @override
  State<WasdJoystick> createState() => _WasdJoystickState();
}

class _WasdJoystickState extends State<WasdJoystick>
    with SingleTickerProviderStateMixin {
  /// Radial dead zone (dp) — is se kam harkat par koi key nahi.
  static const double _deadZone = 13;

  /// Simt ke hisab se keys: E, NE, N, NW, W, SW, S, SE.
  static const List<Set<GameKey>> _sectorKeys = [
    {GameKey.d},
    {GameKey.w, GameKey.d},
    {GameKey.w},
    {GameKey.w, GameKey.a},
    {GameKey.a},
    {GameKey.s, GameKey.a},
    {GameKey.s},
    {GameKey.s, GameKey.d},
  ];

  Offset _knobOffset = Offset.zero;
  int? _pointer;
  Set<GameKey> _currentKeys = const {};

  late final AnimationController _returnController;
  Animation<Offset>? _returnAnimation;

  double get _maxTravel => widget.size * 0.27;

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
    _returnController.dispose();
    super.dispose();
  }

  void _updateFromPosition(Offset localPosition) {
    final centre = Offset(widget.size / 2, widget.size / 2);
    final vector = localPosition - centre;
    final length = vector.distance;
    final clamped = length > _maxTravel
        ? vector * (_maxTravel / length)
        : vector;
    setState(() => _knobOffset = clamped);

    final Set<GameKey> keys;
    if (length < _deadZone) {
      keys = const {};
    } else {
      var degrees = (math.atan2(-vector.dy, vector.dx) * 180 / math.pi + 360) %
          360;
      final sector = ((degrees + 22.5) / 45).floor() % 8;
      keys = _sectorKeys[sector];
    }
    if (!_sameKeys(keys, _currentKeys)) {
      _currentKeys = keys;
      widget.onKeysChanged(keys);
    }
  }

  bool _sameKeys(Set<GameKey> a, Set<GameKey> b) =>
      a.length == b.length && a.containsAll(b);

  void _release() {
    _pointer = null;
    if (_currentKeys.isNotEmpty) {
      _currentKeys = const {};
      widget.onKeysChanged(const {});
    }
    // Knob naram se centre wapas.
    _returnAnimation = Tween<Offset>(begin: _knobOffset, end: Offset.zero)
        .animate(
      CurvedAnimation(parent: _returnController, curve: Curves.easeOut),
    );
    _returnController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final knobSize = widget.size * 0.42;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        if (_pointer != null) return;
        _pointer = event.pointer;
        _returnController.stop();
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
        width: widget.size,
        height: widget.size,
        child: Stack(
          children: [
            // Base — gehra gol ghaira, simt ke teer.
            Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  colors: [Color(0xFF16203A), Color(0xFF0B1220)],
                  stops: [0.0, 0.75],
                ),
                border: Border.all(color: const Color(0xFF334155), width: 3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.55),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
            ),
            const _DirectionArrows(),
            // Knob — teal, chamak ke saath.
            Positioned(
              left: (widget.size - knobSize) / 2 + _knobOffset.dx,
              top: (widget.size - knobSize) / 2 + _knobOffset.dy,
              child: Container(
                width: knobSize,
                height: knobSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    center: Alignment(-0.35, -0.4),
                    radius: 1.05,
                    colors: [Color(0xFF5EEAD4), Color(0xFF0F766E)],
                  ),
                  border:
                      Border.all(color: const Color(0xFF99F6E4), width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.6),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Base par chaar simton ke halke teer.
class _DirectionArrows extends StatelessWidget {
  const _DirectionArrows();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      color: Color(0xFF64748B),
      fontSize: 15,
      fontWeight: FontWeight.w800,
    );
    return const Stack(
      children: [
        Positioned(top: 7, left: 0, right: 0, child: Center(child: Text('▲', style: style))),
        Positioned(bottom: 7, left: 0, right: 0, child: Center(child: Text('▼', style: style))),
        Positioned(left: 9, top: 0, bottom: 0, child: Center(child: Text('◀', style: style))),
        Positioned(right: 9, top: 0, bottom: 0, child: Center(child: Text('▶', style: style))),
      ],
    );
  }
}
