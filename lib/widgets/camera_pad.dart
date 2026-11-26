import 'dart:async';

import 'package:flutter/material.dart';

/// CAMERA pad — ungli ghumane se laptop par mouse harkat karta hai.
///
/// GTA San Andreas me camera, swimming ki simt aur pause-menu ka
/// pointer — teeno mouse se chalte hain; keyboard-only remote par
/// camera aik hi angle par atak jata tha (v2 ki sab se bari kami).
/// Ye pad wahi mouse hai: ungli jidhar ghumao, camera udhar.
///
/// Kaam ka tareeqa:
/// - Raw [Listener], aik ungli ki malikiyat — baqi controls (pedals,
///   buttons) ki tarah koi gesture arena nahi; dusri ungli RACE
///   dabaye to bhi pad apni ungli par chalta hai.
/// - Ungli ki harkat [sensitivity] se barh kar jama hoti rehti hai
///   aur har ~12 ms par report jati hai — har report HID ki hadd
///   (±127) ke andar tukron me bant kar, taake tez jhatka bhi poora
///   pahunche, aadha na kate.
/// - Ungli uthte hi bachi hui harkat bhi foran bhej dete hain —
///   chhota sa flick bhi zaya nahi hota.
class CameraPad extends StatefulWidget {
  const CameraPad({
    super.key,
    required this.onMove,
    this.sensitivity = 2.2,
    this.yScale = 0.5,
    this.label = 'CAMERA',
    this.onTouchStart,
    this.onTouchEnd,
  });

  /// Mouse ki harkat bhejo (dx, dy) — har call ±127 ke andar hai.
  final void Function(int dx, int dy) onMove;

  /// Ungli ki harkat ka multiplier. 2.2 par halki si drag par
  /// camera aaram se ghum jata hai; 1.0 bohat sust lagta tha.
  final double sensitivity;

  /// Up/down (Y) harkat ka alag multiplier (v5.5). SA me nishana
  /// bandhte waqt up/down ka kul range bohat chhota hai — utni hi
  /// mouse harkat par camera seedha upar ya neeche ja kar atak
  /// jata tha, nishana aik jagah rukta hi nahi tha aur firing
  /// kharab hoti thi (Muhammad ki report, 2026-11-26). 0.5 par
  /// poora pad drag = takreeban poora up/down range, aur chhoti
  /// drag = chhoti, rukne wali harkat. Left/right pehle jaisi tez.
  final double yScale;

  /// Pad par likha naam — paidal mode me auto-aim chalu ho to
  /// 'AIM + CAMERA' (v5.4), warna 'CAMERA'.
  final String label;

  /// Ungli pad ko chhoo le (aim pakarne ke liye, v5.4) aur
  /// ungli uth jaye (aim chhorne ke liye).
  final VoidCallback? onTouchStart;
  final VoidCallback? onTouchEnd;

  @override
  State<CameraPad> createState() => _CameraPadState();
}

class _CameraPadState extends State<CameraPad> {
  /// Reports ke darmiyan waqfa — HID ki 125 Hz polling ke qareeb.
  static const Duration _flushInterval = Duration(milliseconds: 12);

  int? _pointer;
  Offset? _lastPosition;

  /// Jama shuda harkat (kesari/dashria hisse ke saath) — ahista
  /// drag par chhoti harkatein bhi zaya nahi hotin, waqt ke saath
  /// jama hokar report ban jati hain.
  double _pendingDx = 0;
  double _pendingDy = 0;

  Timer? _flushTimer;
  bool _dragging = false;

  @override
  void dispose() {
    _flushTimer?.cancel();
    _flushTimer = null;
    super.dispose();
  }

  /// Jama harkat ko ±127 ke tukron me bhej do.
  void _flush() {
    var dx = _pendingDx.round();
    var dy = _pendingDy.round();
    _pendingDx -= dx;
    _pendingDy -= dy;
    while (dx != 0 || dy != 0) {
      final chunkX = dx.clamp(-127, 127);
      final chunkY = dy.clamp(-127, 127);
      widget.onMove(chunkX, chunkY);
      dx -= chunkX;
      dy -= chunkY;
    }
  }

  void _handleDown(PointerDownEvent event) {
    if (_pointer != null) return; // pehli ungli hi malik hai
    _pointer = event.pointer;
    _lastPosition = event.localPosition;
    setState(() => _dragging = true);
    widget.onTouchStart?.call();
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(_flushInterval, (_) => _flush());
  }

  void _handleMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    final last = _lastPosition;
    if (last == null) return;
    final delta = event.localPosition - last;
    _lastPosition = event.localPosition;
    _pendingDx += delta.dx * widget.sensitivity;
    _pendingDy += delta.dy * widget.sensitivity * widget.yScale;
  }

  void _handleUp(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _lastPosition = null;
    _flush(); // bachi hui harkat bhi bhej do
    _flushTimer?.cancel();
    _flushTimer = null;
    widget.onTouchEnd?.call();
    if (mounted) setState(() => _dragging = false);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _handleDown,
      onPointerMove: _handleMove,
      onPointerUp: _handleUp,
      onPointerCancel: _handleUp,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: const Color(0xFF0B0E13).withValues(alpha: 0.38),
          border: Border.all(
            color: const Color(0xFFFB923C)
                .withValues(alpha: _dragging ? 0.85 : 0.38),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.mouse,
                  size: 15,
                  color:
                      const Color(0xFF94A3B8).withValues(alpha: 0.9),
                ),
                const SizedBox(width: 6),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.5,
                    color:
                        const Color(0xFF94A3B8).withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
