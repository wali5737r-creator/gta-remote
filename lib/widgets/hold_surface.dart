import 'package:flutter/material.dart';

/// Aik ungli ko "capture" karne wala touch surface.
///
/// Ungli neeche jaye to held = true; ungli uthay (chahe woh slide karke
/// button se bahar nikal gayi ho) tab held = false. Pedals aur hold buttons
/// isi par bante hain — GTA me ungli slide hona aam hai, press tootna nahi
/// chahiye (FR-11/FR-12).
class HoldSurface extends StatefulWidget {
  const HoldSurface({
    super.key,
    required this.onHeldChanged,
    required this.builder,
  });

  final ValueChanged<bool> onHeldChanged;
  final Widget Function(BuildContext context, bool pressed) builder;

  @override
  State<HoldSurface> createState() => _HoldSurfaceState();
}

class _HoldSurfaceState extends State<HoldSurface> {
  int? _pointer;
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
    widget.onHeldChanged(value);
  }

  void _releasePointer(int pointer) {
    if (pointer != _pointer) return;
    _pointer = null;
    _setPressed(false);
  }

  @override
  void dispose() {
    // Widget khatam ho raha ho aur ungli abhi neeche ho to press chhor do.
    if (_pressed) widget.onHeldChanged(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        if (_pointer != null) return; // pehli ungli hi malik hai
        _pointer = event.pointer;
        _setPressed(true);
      },
      onPointerUp: (event) => _releasePointer(event.pointer),
      onPointerCancel: (event) => _releasePointer(event.pointer),
      child: widget.builder(context, _pressed),
    );
  }
}
