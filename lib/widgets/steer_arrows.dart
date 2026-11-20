import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ARROWS mode ka steer button (v4) — bara gol-kinara wala ◀ / ▶.
///
/// Raw [Listener] par chalta hai, bilkul baqi controls ki tarah:
/// aik ungli ki malikiyat, dabane par foran held = true, uthne /
/// cancel par false, aur widget khatam hote waqt dabaa hua ho to
/// khud release bhejta hai — key kisi surat atak nahi sakti.
///
/// "Aik tap = halki si move" wali minimum-pulse ki logic is widget
/// me nahi hai — woh controller screen rakhta hai (key sources usi
/// ke paas hain). Ye widget sirf dabana/chhorna batata hai.
class SteerArrowButton extends StatefulWidget {
  const SteerArrowButton({
    super.key,
    required this.left,
    required this.onHeldChanged,
    this.size = 88,
  });

  /// True = ◀ (left), false = ▶ (right).
  final bool left;

  final ValueChanged<bool> onHeldChanged;

  /// Button ka size (dp) — mockup ke baray buttons ke mutabiq.
  final double size;

  @override
  State<SteerArrowButton> createState() => _SteerArrowButtonState();
}

class _SteerArrowButtonState extends State<SteerArrowButton> {
  int? _pointer;
  bool _pressed = false;

  void _down(int pointer) {
    if (_pointer != null) return;
    _pointer = pointer;
    setState(() => _pressed = true);
    HapticFeedback.lightImpact();
    widget.onHeldChanged(true);
  }

  void _up(int pointer) {
    if (pointer != _pointer) return;
    _pointer = null;
    setState(() => _pressed = false);
    widget.onHeldChanged(false);
  }

  @override
  void dispose() {
    if (_pressed) widget.onHeldChanged(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) => _down(event.pointer),
      onPointerUp: (event) => _up(event.pointer),
      onPointerCancel: (event) => _up(event.pointer),
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF2A313B), Color(0xFF12161D)],
            ),
            border: Border.all(
              color: _pressed
                  ? const Color(0xFFF97316)
                  : const Color(0xFF4B3A28),
              width: 2,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
              if (_pressed)
                BoxShadow(
                  color: const Color(0xFFF97316).withValues(alpha: 0.35),
                  blurRadius: 22,
                ),
            ],
          ),
          child: Center(
            child: Text(
              widget.left ? '◀' : '▶',
              style: TextStyle(
                fontSize: size * 0.42,
                height: 1.0,
                color: _pressed
                    ? const Color(0xFFFB923C)
                    : const Color(0xFFF59E0B),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
