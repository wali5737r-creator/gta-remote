import 'package:flutter/material.dart';

/// Driving mode ka STEERING | TILT switch (v2) — top bar ke beech me.
///
/// Labels English hain (approved mockup tilt-design.html ke mutabiq),
/// active hissa garam orange gradient par safed text. Sirf driving
/// mode me nazar aata hai; paidal mode me steering ka koi sawal hi
/// nahi, is liye wahan chhupa rehta hai.
class SteerModeSwitch extends StatelessWidget {
  const SteerModeSwitch({
    super.key,
    required this.tiltMode,
    required this.onSelected,
  });

  /// True = TILT active, false = STEERING active.
  final bool tiltMode;

  /// true = TILT chuna, false = STEERING chuna.
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF080A0E).withValues(alpha: 0.7),
        border: Border.all(
          color: const Color(0xFFFB923C).withValues(alpha: 0.45),
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(
            'STEERING',
            active: !tiltMode,
            onTap: () => onSelected(false),
          ),
          _segment('TILT', active: tiltMode, onTap: () => onSelected(true)),
        ],
      ),
    );
  }

  Widget _segment(
    String label, {
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          gradient: active
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFF97316), Color(0xFFC2410C)],
                )
              : null,
          borderRadius: BorderRadius.circular(999),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: const Color(0xFFF97316).withValues(alpha: 0.35),
                    blurRadius: 12,
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
            color: active ? Colors.white : const Color(0xFF9FB0C3),
          ),
        ),
      ),
    );
  }
}
