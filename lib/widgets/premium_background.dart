import 'package:flutter/material.dart';

/// Premium dark background — gehra navy gradient + naram teal/blue glow.
/// Mockup (design.html) ke look ke mutabiq.
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
          colors: [Color(0xFF131C2E), Color(0xFF0B1220), Color(0xFF0A0F1C)],
          stops: [0.0, 0.6, 1.0],
        ),
      ),
      child: Stack(
        children: [
          // Upar-left teal glow.
          Positioned(
            top: -140,
            left: -100,
            child: _Glow(
              color: const Color(0xFF2DD4BF).withValues(alpha: 0.13),
              size: 340,
            ),
          ),
          // Neeche-right halka blue glow.
          Positioned(
            bottom: -160,
            right: -80,
            child: _Glow(
              color: const Color(0xFF2563EB).withValues(alpha: 0.10),
              size: 360,
            ),
          ),
          child,
        ],
      ),
    );
  }
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
