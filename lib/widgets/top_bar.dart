import 'package:flutter/material.dart';

import '../services/hid_service.dart';
import '../services/settings_service.dart';
import 'steer_mode_switch.dart';

/// Controller screen ki top bar (Muhammad ki revised design):
/// left = connection status pill, right = mode pill.
/// Driving mode me beech me drive-mode switch bhi aata hai
/// (v2: STEERING | TILT; v4: chaar modes).
/// Mode pill sirf layout badalta hai — koi key nahi bhejta (FR-20).
class ControllerTopBar extends StatelessWidget {
  const ControllerTopBar({
    super.key,
    required this.hidState,
    required this.driving,
    required this.onModeSelected,
    this.driveMode = DriveMode.steering,
    this.onDriveModeSelected,
    this.flipControls = false,
    this.onCheatsTap,
    this.onGuideTap,
    this.autoAimOn,
    this.onAutoAimTap,
  });

  final HidState hidState;

  /// True = Driving layout active hai.
  final bool driving;

  /// Mode pill se layout tabdeeli (true = Driving, false = On Foot).
  final ValueChanged<bool> onModeSelected;

  /// Drive-mode switch ki haalat — sirf driving me istemal hoti
  /// hai, aur switch bhi sirf tabhi nazar aata hai.
  final DriveMode driveMode;

  /// Naya drive mode chuna gaya. Null ho to switch nahi banta.
  final ValueChanged<DriveMode>? onDriveModeSelected;

  /// Controls ultay hain ya nahi — dusri satar (CHEATS / GUIDE)
  /// action-cluster wali taraf lagti hai, jahan neeche jagah
  /// zyada hai (v5).
  final bool flipControls;

  /// Dusri satar ke buttons (v5). Dono null hon to dusri satar
  /// nahi banti aur bar pehle jaisi aik satar ki rehti hai.
  final VoidCallback? onCheatsTap;
  final VoidCallback? onGuideTap;

  /// AUTO-AIM toggle (v5.4) — sirf ON FOOT mode me nazar aata
  /// hai. Null ho to pill nahi banta.
  final bool? autoAimOn;
  final VoidCallback? onAutoAimTap;

  @override
  Widget build(BuildContext context) {
    final showNavRow =
        onCheatsTap != null || onGuideTap != null || onAutoAimTap != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            // Status pill ko bachi hui jagah tak mehdood rakho — lamba
            // laptop naam mode pill ko screen se bahar nahi dhakelta.
            Flexible(
              child: Align(
                alignment: Alignment.centerLeft,
                child: _StatusPill(hidState: hidState),
              ),
            ),
            if (driving && onDriveModeSelected != null) ...[
              const SizedBox(width: 12),
              SteerModeSwitch(
                mode: driveMode,
                onSelected: onDriveModeSelected!,
              ),
            ],
            const SizedBox(width: 12),
            _ModePill(driving: driving, onModeSelected: onModeSelected),
          ],
        ),
        if (showNavRow) ...[
          const SizedBox(height: 6),
          // CHEATS / GUIDE — action-cluster wali taraf (na-flip par
          // dayein, flip par bayein), kyunke us taraf ke controls
          // neeche se shuru hote hain aur satar ko jagah milti hai.
          Row(
            mainAxisAlignment:
                flipControls ? MainAxisAlignment.start : MainAxisAlignment.end,
            children: [
              if (onCheatsTap != null)
                _NavPill(
                  icon: Icons.star,
                  iconColor: const Color(0xFFF7A81E),
                  label: 'CHEATS',
                  onTap: onCheatsTap!,
                ),
              if (onCheatsTap != null && onGuideTap != null)
                const SizedBox(width: 8),
              if (onGuideTap != null)
                _NavPill(
                  icon: Icons.menu_book,
                  iconColor: const Color(0xFFCBD5E1),
                  label: 'GUIDE',
                  onTap: onGuideTap!,
                ),
              // AUTO-AIM toggle (v5.4) — sirf ON FOOT me: larai
              // se pehle ON, baqi kaam ke liye OFF. Cluster/pad
              // ki jagah nahi khata — dusri satar me jagah thi.
              if (onAutoAimTap != null && !driving) ...[
                if (onCheatsTap != null || onGuideTap != null)
                  const SizedBox(width: 8),
                _NavPill(
                  icon: Icons.gps_fixed,
                  iconColor: (autoAimOn ?? true)
                      ? const Color(0xFF4ADE80)
                      : const Color(0xFF94A3B8),
                  label: (autoAimOn ?? true)
                      ? 'AUTO-AIM ON'
                      : 'AUTO-AIM OFF',
                  onTap: onAutoAimTap!,
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

/// Dusri satar ka chhota pill button (CHEATS / GUIDE) — bar ki
/// apni styling (gehra gola, orange kinara) me (v5).
class _NavPill extends StatelessWidget {
  const _NavPill({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: const Color(0xFF080A0E).withValues(alpha: 0.7),
          border: Border.all(
            color: const Color(0xFFFB923C).withValues(alpha: 0.35),
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: iconColor),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: Color(0xFFCBD5E1),
              ),
            ),
          ],
        ),
      ),
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
        color: const Color(0xFF080A0E).withValues(alpha: 0.7),
        border: Border.all(
          color: const Color(0xFFFB923C).withValues(alpha: 0.35),
        ),
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
        color: const Color(0xFF080A0E).withValues(alpha: 0.7),
        border: Border.all(
          color: const Color(0xFFFB923C).withValues(alpha: 0.35),
        ),
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
    final color = active ? const Color(0xFFFDBA74) : const Color(0xFF94A3B8);
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
