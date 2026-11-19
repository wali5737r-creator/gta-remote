import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/game_key.dart';

/// Asli car jaisa steering wheel — ungli se ghumta hai.
///
/// - Rotation **delta-angle** tareeqay se hoti hai: ungli jahan se bhi
///   pakray, wheel wahan se snap nahi hota (FR-8).
/// - Angle ±range par clamp; dead zone ke andar koi key nahi (FR-9).
/// - Ungli uthte hi wheel ~200ms me spring se centre wapas (FR-10).
/// - Muhammad ki design note: wheel ke neeche koi caption text nahi.
class SteeringWheel extends StatefulWidget {
  const SteeringWheel({
    super.key,
    required this.size,
    required this.rangeDeg,
    required this.deadZoneDeg,
    required this.sensitivity,
    required this.onSteeringKeyChanged,
    this.onAngleChanged,
  });

  final double size;

  /// Aik side zyada se zyada kitne degrees (90 ya 135).
  final double rangeDeg;

  /// Centre dead zone (degrees).
  final double deadZoneDeg;

  /// Ungli ki harkat ka multiplier (0.7 / 1.0 / 1.4).
  final double sensitivity;

  /// Steering key tabdeel ho to: A, D, ya null (koi nahi).
  final ValueChanged<GameKey?> onSteeringKeyChanged;

  /// Angle readout ke liye (centre screen par chhota sa text).
  final ValueChanged<double>? onAngleChanged;

  @override
  State<SteeringWheel> createState() => _SteeringWheelState();
}

class _SteeringWheelState extends State<SteeringWheel>
    with SingleTickerProviderStateMixin {
  /// Centre se itne dp ke andar ungli ho to angle nahi naapte (shor zyada hai).
  static const double _centreIgnoreRadius = 24;

  double _angleDeg = 0;
  double? _lastFingerAngleRad;
  GameKey? _currentKey;
  int _lastReportedDegree = 0;

  late final AnimationController _springController;
  Animation<double>? _springAnimation;

  @override
  void initState() {
    super.initState();
    _springController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..addListener(() {
        final animation = _springAnimation;
        if (animation == null) return;
        setState(() => _angleDeg = animation.value);
        _evaluate();
      });
  }

  @override
  void dispose() {
    _springController.dispose();
    super.dispose();
  }

  /// Angle se steering key nikalo aur tabdeeli par khabar do.
  void _evaluate() {
    final GameKey? key;
    if (_angleDeg < -widget.deadZoneDeg) {
      key = GameKey.a;
    } else if (_angleDeg > widget.deadZoneDeg) {
      key = GameKey.d;
    } else {
      key = null;
    }
    if (key != _currentKey) {
      _currentKey = key;
      widget.onSteeringKeyChanged(key);
    }
    final rounded = _angleDeg.round();
    if (rounded != _lastReportedDegree) {
      _lastReportedDegree = rounded;
      widget.onAngleChanged?.call(_angleDeg);
    }
  }

  double? _fingerAngle(Offset localPosition) {
    final centre = Offset(widget.size / 2, widget.size / 2);
    final offset = localPosition - centre;
    if (offset.distance < _centreIgnoreRadius) return null;
    return math.atan2(offset.dy, offset.dx);
  }

  /// Do angles ka farq −180°..+180° ke andar rakho.
  double _wrapDelta(double deltaRad) {
    var delta = deltaRad;
    while (delta > math.pi) {
      delta -= 2 * math.pi;
    }
    while (delta < -math.pi) {
      delta += 2 * math.pi;
    }
    return delta;
  }

  void _handlePanStart(DragStartDetails details) {
    _springController.stop();
    _springAnimation = null;
    _lastFingerAngleRad = _fingerAngle(details.localPosition);
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    final current = _fingerAngle(details.localPosition);
    if (current == null) return; // centre ke paas — purana angle rakho
    final last = _lastFingerAngleRad;
    if (last != null) {
      final deltaDeg =
          _wrapDelta(current - last) * 180 / math.pi * widget.sensitivity;
      setState(() {
        _angleDeg = (_angleDeg + deltaDeg)
            .clamp(-widget.rangeDeg, widget.rangeDeg)
            .toDouble();
      });
      _evaluate();
    }
    _lastFingerAngleRad = current;
  }

  void _handlePanEnd() {
    _lastFingerAngleRad = null;
    // Spring return — natural ease-out curve, ~200ms (FR-10).
    _springAnimation = Tween<double>(begin: _angleDeg, end: 0).animate(
      CurvedAnimation(parent: _springController, curve: Curves.easeOutCubic),
    );
    _springController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: _handlePanStart,
            onPanUpdate: _handlePanUpdate,
            onPanEnd: (_) => _handlePanEnd(),
            onPanCancel: _handlePanEnd,
            child: Transform.rotate(
              angle: _angleDeg * math.pi / 180,
              child: CustomPaint(
                size: Size.square(widget.size),
                painter: _WheelPainter(),
              ),
            ),
          ),
          // Fixed bezel marker — seedhi simt (ye nahi ghumta).
          Positioned(
            top: -4,
            left: 0,
            right: 0,
            child: Center(
              child: CustomPaint(
                size: const Size(16, 11),
                painter: _MarkerPainter(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Chhota sa ▲ nishan (bezel par, seedhi simt dikhane ke liye).
class _MarkerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF2DD4BF);
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Leather rim + stitching + metal spokes + hub — mockup ke mutabiq.
class _WheelPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final rimWidth = size.width * 0.088;
    final rimRadius = radius - rimWidth / 2 - 2;

    // Zameen par naram sa saya.
    canvas.drawCircle(
      centre + const Offset(0, 10),
      radius - 2,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );

    // Andar ki disc (gehra radial).
    final discPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.2, -0.3),
        radius: 0.9,
        colors: const [Color(0xFF141D30), Color(0xFF0A0F1C)],
      ).createShader(Rect.fromCircle(center: centre, radius: radius));
    canvas.drawCircle(centre, rimRadius - rimWidth / 2 + 2, discPaint);

    _drawSpokes(canvas, centre, size, rimRadius);

    // Leather rim — sweep gradient se halki chamak.
    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = rimWidth
      ..shader = SweepGradient(
        colors: const [
          Color(0xFF2E3A50),
          Color(0xFF1D2637),
          Color(0xFF39465E),
          Color(0xFF232D42),
          Color(0xFF2E3A50),
        ],
      ).createShader(Rect.fromCircle(center: centre, radius: rimRadius));
    canvas.drawCircle(centre, rimRadius, rimPaint);

    // Rim ke andar wali halki roshni wali line.
    canvas.drawCircle(
      centre,
      rimRadius - rimWidth / 2 + 1.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: 0.10),
    );

    _drawStitching(canvas, centre, rimRadius - rimWidth / 2 - size.width * 0.026);
    _drawTopStripe(canvas, centre, rimRadius, rimWidth, size);
    _drawHub(canvas, centre, size);
  }

  void _drawSpokes(Canvas canvas, Offset centre, Size size, double rimRadius) {
    final spokePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF3A465C), Color(0xFF232D42)],
      ).createShader(Rect.fromCircle(center: centre, radius: rimRadius));

    // Horizontal spoke (left-right).
    final horizontal = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: centre,
        width: size.width * 0.80,
        height: size.height * 0.155,
      ),
      const Radius.circular(9),
    );
    canvas.drawRRect(horizontal, spokePaint);

    // Neeche wala spoke (centre se rim tak).
    final bottom = RRect.fromRectAndRadius(
      Rect.fromLTRB(
        centre.dx - size.width * 0.078,
        centre.dy,
        centre.dx + size.width * 0.078,
        centre.dy + rimRadius - 2,
      ),
      const Radius.circular(9),
    );
    canvas.drawRRect(bottom, spokePaint);
  }

  void _drawStitching(Canvas canvas, Offset centre, double stitchRadius) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFF94A3B8).withValues(alpha: 0.45);
    const dashCount = 64;
    const step = 2 * math.pi / dashCount;
    for (var i = 0; i < dashCount; i++) {
      final start = i * step;
      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: stitchRadius),
        start,
        step * 0.55,
        false,
        paint,
      );
    }
  }

  void _drawTopStripe(
    Canvas canvas,
    Offset centre,
    double rimRadius,
    double rimWidth,
    Size size,
  ) {
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    final stripe = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(0, -rimRadius),
        width: size.width * 0.062,
        height: rimWidth + 3,
      ),
      const Radius.circular(3),
    );
    canvas.drawRRect(stripe, Paint()..color = const Color(0xFFC0C7D1));
    canvas.restore();
  }

  void _drawHub(Canvas canvas, Offset centre, Size size) {
    final hubRadius = size.width * 0.185;
    // Hub ka saya.
    canvas.drawCircle(
      centre + const Offset(0, 4),
      hubRadius,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    final hubPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.45),
        radius: 1.0,
        colors: const [Color(0xFF4A5871), Color(0xFF1B2436)],
      ).createShader(Rect.fromCircle(center: centre, radius: hubRadius));
    canvas.drawCircle(centre, hubRadius, hubPaint);
    canvas.drawCircle(
      centre,
      hubRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFF101827),
    );
    // Beech me teal ring (horn pad ka nishan).
    canvas.drawCircle(
      centre,
      size.width * 0.088,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFF2DD4BF).withValues(alpha: 0.35),
    );
    canvas.drawCircle(
      centre,
      size.width * 0.088,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF2DD4BF),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
