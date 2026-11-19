import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Premium dark background — Racing Cockpit theme (v2):
/// near-black carbon texture (halki diagonal bunai) + neeche-right
/// garam red glow aur upar-left halka orange glow.
/// Mockup (design-options.html .v1) ke look ke mutabiq.
class PremiumBackground extends StatelessWidget {
  const PremiumBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF11151C), Color(0xFF0B0E13), Color(0xFF07090C)],
          stops: [0.0, 0.6, 1.0],
        ),
      ),
      child: Stack(
        children: [
          // Carbon ki bunai — sasti CustomPaint, koi image asset nahi.
          // RepaintBoundary: texture aik dafa paint ho kar cache rahe,
          // upar ke controls ke rebuild par dobara na bane.
          const Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(painter: _CarbonPainter()),
            ),
          ),
          // Upar-left halka orange glow.
          Positioned(
            top: -140,
            left: -100,
            child: _Glow(
              color: const Color(0xFFF97316).withValues(alpha: 0.10),
              size: 340,
            ),
          ),
          // Neeche-right garam red glow (mockup .v1 jaisa).
          Positioned(
            bottom: -160,
            right: -80,
            child: _Glow(
              color: const Color(0xFFEF4444).withValues(alpha: 0.12),
              size: 360,
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Carbon fibre jaisi diagonal bunai: do simton (±45°) me halki aur
/// gehri dhaariyan aik dusre ko kaat-ti hain — bilkul CSS ke
/// repeating-linear-gradient wale pattern ki tarah.
class _CarbonPainter extends CustomPainter {
  const _CarbonPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const band = 7.0;
    final light = Paint()..color = Colors.white.withValues(alpha: 0.020);
    final dark = Paint()..color = Colors.black.withValues(alpha: 0.17);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final angle in [math.pi / 4, -math.pi / 4]) {
      canvas.save();
      canvas.translate(size.width / 2, size.height / 2);
      canvas.rotate(angle);
      // Ghumi hui haalat me poori screen cover karne ke liye span.
      final span = (size.width + size.height) / 2 + band;
      var y = -span;
      var isLight = true;
      while (y < span) {
        canvas.drawRect(
          Rect.fromLTWH(-span, y, span * 2, band),
          isLight ? light : dark,
        );
        y += band;
        isLight = !isLight;
      }
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}
