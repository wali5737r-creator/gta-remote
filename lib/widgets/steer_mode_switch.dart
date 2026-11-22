import 'package:flutter/material.dart';

import '../services/settings_service.dart';

/// Driving mode ka switch (v4; v6 me paanch segments) — top bar
/// ke beech me: STEERING | TILT | CONTROLLER | ARROWS | FLY.
///
/// Labels English hain (approved mockup v4-modes.html ke mutabiq),
/// active hissa garam orange gradient par safed text. Sirf driving
/// mode me nazar aata hai; paidal mode me steering ka koi sawal hi
/// nahi, is liye wahan chhupa rehta hai.
///
/// Segments tang screens (640 dp) par bhi status/mode pills ke
/// saath fit hon, is liye padding/font compact hai — style bilkul
/// wahi hai. v6 me paanchwein segment (FLY) ki jagah banane ke
/// liye horizontal padding 9 → 7, font 11 → 10.5 aur letter
/// spacing 0.8 → 0.5 hua; kul switch chauraai takreeban v5 wali
/// hi rehti hai aur paancho labels poore parhe jate hain
/// (hisaab IMPROVEMENTS_V6.md me).
class SteerModeSwitch extends StatelessWidget {
  const SteerModeSwitch({
    super.key,
    required this.mode,
    required this.onSelected,
  });

  /// Is waqt active drive mode.
  final DriveMode mode;

  /// Naya mode chuna gaya.
  final ValueChanged<DriveMode> onSelected;

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
          for (final value in DriveMode.values)
            _segment(
              value.label,
              active: mode == value,
              onTap: () => onSelected(value),
            ),
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
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 9),
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
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            color: active ? Colors.white : const Color(0xFF9FB0C3),
          ),
        ),
      ),
    );
  }
}
