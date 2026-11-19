import 'package:flutter/material.dart';

import '../services/hid_service.dart';

/// Controller screen ki top bar (Muhammad ki revised design):
/// left = connection status pill, right = mode pill.
/// Mode pill sirf layout badalta hai — koi key nahi bhejta (FR-20).
class ControllerTopBar extends StatelessWidget {
  const ControllerTopBar({
    super.key,
    required this.hidState,
    required this.driving,
    required this.onModeSelected,
  });

  final HidState hidState;

  /// True = Driving layout active hai.
  final bool driving;

  /// Mode pill se layout tabdeeli (true = Driving, false = On Foot).
  final ValueChanged<bool> onModeSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Status pill ko bachi hui jagah tak mehdood rakho — lamba
        // laptop naam mode pill ko screen se bahar nahi dhakelta.
        Flexible(
          child: Align(
            alignment: Alignment.centerLeft,
            child: _StatusPill(hidState: hidState),
          ),
        ),
        const SizedBox(width: 10),
        _ModePill(driving: driving, onModeSelected: onModeSelected),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.hidState});

  final HidState hidState;

  @override
  Widget build(BuildContext context) {
    final connected = hidState.isConnected;
    final connecting =
        hidState.connection == HidConnection.connecting ||
            hidState.connection == HidConnection.disconnecting;
    final dotColor = connected
        ? const Color(0xFF22C55E)
        : (connecting ? const Color(0xFFFACC15) : const Color(0xFFEF4444));
    final text = connected
        ? 'Connected — ${hidState.deviceName ?? 'Laptop'}'
        : (connecting ? 'Connecting…' : 'Disconnected');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF020617).withValues(alpha: 0.65),
        border: Border.all(color: const Color(0xFF1E293B)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dotColor,
              boxShadow: [
                BoxShadow(
                  color: dotColor.withValues(alpha: 0.8),
                  blurRadius: 10,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Lamba laptop naam (masalan "DESKTOP-XXXXXX") mode pill ko
          // screen se bahar na dhakele — naam hadd par "…" ho jaye.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                color: Color(0xFFCBD5E1),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModePill extends StatelessWidget {
  const _ModePill({required this.driving, required this.onModeSelected});

  final bool driving;
  final ValueChanged<bool> onModeSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFF020617).withValues(alpha: 0.65),
        border: Border.all(color: const Color(0xFF334155)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(
            icon: Icons.directions_walk,
            label: 'ON FOOT',
            active: !driving,
            onTap: () => onModeSelected(false),
          ),
          _segment(
            icon: Icons.directions_car,
            label: 'DRIVING',
            active: driving,
            onTap: () => onModeSelected(true),
          ),
        ],
      ),
    );
  }

  Widget _segment({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    final color = active ? const Color(0xFFFACC15) : const Color(0xFF94A3B8);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
