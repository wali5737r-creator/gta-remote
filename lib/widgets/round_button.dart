import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Glossy gol button — ENTER/EXIT CAR, HANDBRAKE, JUMP ke liye.
///
/// Do tareeqay:
/// - [onTap]: ungli lagte hi action (enter/exit car).
/// - [onHeldChanged]: dabaye rakho to on, chhoro to off (handbrake, jump).
/// [lit] true ho to button roshan rehta hai (toggle ki haalat).
class RoundButton extends StatefulWidget {
  const RoundButton({
    super.key,
    required this.diameter,
    required this.label,
    this.subLabel,
    required this.gradientTop,
    required this.gradientBottom,
    required this.borderColor,
    this.onTap,
    this.onHeldChanged,
    this.lit = false,
  });

  final double diameter;

  /// Do lines ke liye '\n' use karo (masalan 'EXIT\nCAR').
  final String label;

  /// Key ki chhoti sub-text (masalan 'F', 'Space').
  final String? subLabel;

  final Color gradientTop;
  final Color gradientBottom;
  final Color borderColor;

  final VoidCallback? onTap;
  final ValueChanged<bool>? onHeldChanged;

  /// Toggle on ho to roshan (RUN button jaisa asar).
  final bool lit;

  @override
  State<RoundButton> createState() => _RoundButtonState();
}

class _RoundButtonState extends State<RoundButton> {
  int? _pointer;
  bool _pressed = false;

  void _down(int pointer) {
    if (_pointer != null) return;
    _pointer = pointer;
    setState(() => _pressed = true);
    HapticFeedback.lightImpact();
    if (widget.onHeldChanged != null) {
      widget.onHeldChanged!(true);
    } else {
      widget.onTap?.call();
    }
  }

  void _up(int pointer) {
    if (pointer != _pointer) return;
    _pointer = null;
    setState(() => _pressed = false);
    widget.onHeldChanged?.call(false);
  }

  @override
  void dispose() {
    if (_pressed) widget.onHeldChanged?.call(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = _pressed || widget.lit;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) => _down(event.pointer),
      onPointerUp: (event) => _up(event.pointer),
      onPointerCancel: (event) => _up(event.pointer),
      child: AnimatedScale(
        scale: _pressed ? 0.93 : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: Container(
          width: widget.diameter,
          height: widget.diameter,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [widget.gradientTop, widget.gradientBottom],
            ),
            border: Border.all(color: widget.borderColor, width: 2),
            boxShadow: [
              BoxShadow(
                color: widget.gradientBottom
                    .withValues(alpha: active ? 0.55 : 0.35),
                blurRadius: active ? 24 : 16,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                widget.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: widget.diameter * 0.165,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  height: 1.15,
                  color: Colors.white,
                ),
              ),
              if (widget.subLabel != null)
                Text(
                  widget.subLabel!,
                  style: TextStyle(
                    fontSize: widget.diameter * 0.115,
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
