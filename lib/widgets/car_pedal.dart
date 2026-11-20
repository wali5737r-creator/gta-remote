import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'hold_surface.dart';

/// Asli car jaisa pedal — metal arm + gunmetal pad (Racing Cockpit).
///
/// Muhammad ki final design (v2): BRAKE pehla (left), RACE uske baad
/// (right). RACE = lamba tang pad, BRAKE = chaura chhota pad. Dono par
/// halki green/red pehchan (border + glow + label) rehti hai taake
/// foran samajh aye konsa konsa hai.
/// Dabane par pad neeche jata hai aur glow tez ho jata hai (FR-33).
class CarPedal extends StatelessWidget {
  const CarPedal({
    super.key,
    required this.label,
    required this.subLabel,
    required this.accent,
    required this.tall,
    required this.onHeldChanged,
  });

  /// 'RACE' ya 'BRAKE'.
  final String label;

  /// Key ki sub-text: 'W' ya 'S'.
  final String subLabel;

  /// Pehchan ka rang (green = race, red = brake).
  final Color accent;

  /// True = lamba tang pad (RACE), false = chaura chhota pad (BRAKE).
  final bool tall;

  final ValueChanged<bool> onHeldChanged;

  // v3: pads ~15% chhote — v2 ke size par pedals aik dusre ke bohat
  // qareeb lagte the aur screen par bheed thi.
  double get _padWidth => tall ? 66 : 97;
  double get _padHeight => tall ? 126 : 82;

  @override
  Widget build(BuildContext context) {
    return HoldSurface(
      onHeldChanged: (held) {
        if (held) HapticFeedback.lightImpact();
        onHeldChanged(held);
      },
      builder: (context, pressed) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Metal arm — halka sa ghuma hua.
            Transform.rotate(
              angle: 0.10,
              child: Container(
                width: 11,
                height: 26,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Color(0xFF9CA3AF), Color(0xFF4B5563)],
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 1),
            // Gunmetal pad — vertical grip dhaariyon ke saath (.v1).
            AnimatedContainer(
              duration: const Duration(milliseconds: 90),
              curve: Curves.easeOut,
              transform: Matrix4.translationValues(0, pressed ? 3 : 0, 0),
              width: _padWidth,
              height: _padHeight,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF6B7280),
                    Color(0xFF374151),
                    Color(0xFF1F2937),
                    Color(0xFF4B5563),
                  ],
                  stops: [0.0, 0.4, 0.75, 1.0],
                ),
                border: Border.all(
                  color: accent.withValues(alpha: pressed ? 0.95 : 0.5),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(11),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: accent.withValues(alpha: pressed ? 0.42 : 0.18),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: CustomPaint(
                  painter: _GripRidgePainter(),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.5,
                color: accent,
              ),
            ),
            Text(
              subLabel,
              style: const TextStyle(
                fontSize: 10.5,
                letterSpacing: 1,
                color: Color(0xFF94A3B8),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Metal pad ki grip wali dhaariyan — khari (vertical) gehri lines,
/// mockup .v1 ke repeating pattern ki tarah. Pad ka gunmetal gradient
/// neeche se nazar aata rehta hai; ye sirf gehri dhaariyan dalta hai.
class _GripRidgePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final dark = Paint()..color = Colors.black.withValues(alpha: 0.38);
    const stripeWidth = 7.0;
    const period = 15.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawRect(Rect.fromLTWH(x, 0, stripeWidth, size.height), dark);
      x += period;
    }
    // Upar wali kinari par halki roshni.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, 2),
      Paint()..color = Colors.white.withValues(alpha: 0.16),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
