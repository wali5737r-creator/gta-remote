import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/game_profile.dart';
import '../services/settings_service.dart';
import '../widgets/premium_background.dart';

/// S4 — Settings (FR-23…FR-27).
///
/// Har tabdeeli foran save hoti hai. Controller screen settings ko sun
/// rahi hoti hai — tabdeeli par pehle saari keys chhutti hain.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsService _settings = SettingsService.instance;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _settings.addListener(_refresh);
  }

  @override
  void dispose() {
    _settings.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: PremiumBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
          children: [
            const _SectionTitle('Steering'),
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _RowLabel('How far the wheel turns (one side)'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _ChoiceChip(
                        label: '±90°',
                        selected: _settings.steeringRangeDeg == 90,
                        onTap: () => _settings.setSteeringRangeDeg(90),
                      ),
                      const SizedBox(width: 10),
                      _ChoiceChip(
                        label: '±135°',
                        selected: _settings.steeringRangeDeg == 135,
                        onTap: () => _settings.setSteeringRangeDeg(135),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const _RowLabel(
                      'Sensitivity — how fast steering follows your finger'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final level in SteeringSensitivity.values) ...[
                        _ChoiceChip(
                          label: level.label,
                          selected: _settings.sensitivity == level,
                          onTap: () => _settings.setSensitivity(level),
                        ),
                        const SizedBox(width: 10),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(
                        child: _RowLabel('Dead zone — quiet zone in the centre'),
                      ),
                      Text(
                        '${_settings.deadZoneDeg.round()}°',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFF97316),
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: _settings.deadZoneDeg,
                    min: 0,
                    max: 15,
                    divisions: 15,
                    activeColor: const Color(0xFFF97316),
                    onChanged: (value) => _settings.setDeadZoneDeg(
                      value.round().toDouble(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const _SectionTitle('Controls'),
            _Card(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Flip controls',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                subtitle: const Text(
                  'Steering on the right, pedals on the left (for left-handed use)',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                ),
                value: _settings.flipControls,
                onChanged: _settings.setFlipControls,
              ),
            ),
            const SizedBox(height: 20),
            const _SectionTitle('Game'),
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _RowLabel('Default game'),
                  const SizedBox(height: 8),
                  for (final profile in GameProfile.all)
                    _ProfileRadioRow(
                      profile: profile,
                      selected: _settings.profile.id == profile.id,
                      onTap: () => _settings.setProfile(profile),
                    ),
                  const SizedBox(height: 6),
                  const Text(
                    'Note: keep the keys on Default inside GTA, otherwise the button names will not match the game.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const _SectionTitle('Help'),
            const _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HelpLine('Keep this app open while playing — if you '
                      'close it, the Bluetooth keyboard closes too.'),
                  _HelpLine('If connecting fails, close other remote or '
                      'keyboard apps and try again — only one app can be '
                      'a Bluetooth keyboard at a time.'),
                  _HelpLine('If the connection keeps dropping: phone '
                      'Settings → Apps → Gaming Remote → Battery → set it to '
                      'Unrestricted.'),
                  _HelpLine('While driving, the switch at the top '
                      'changes how you steer: STEERING = touch wheel, '
                      'TILT = tilt the phone left/right, CONTROLLER = '
                      'gamepad stick, ARROWS = tap the ◀ ▶ buttons '
                      '(a short tap makes a small turn), FLY = one '
                      'handle, for planes and helicopters, CRICKET = '
                      'the Cricket 07 stage below. The steering '
                      'settings above (range, dead zone) are for the '
                      'touch wheel; sensitivity also applies to the '
                      'CONTROLLER stick.'),
                  _HelpLine('The CAMERA pad in the middle is the mouse '
                      '— drag your finger to turn the game camera. '
                      'Swimming direction follows the camera too (keep '
                      'RUN on to swim fast). The MAP button opens the '
                      'map/pause menu.'),
                  _HelpLine('On foot: hold ATTACK to fight or fire. '
                      'Hold AIM to aim, then fire with ATTACK. CROUCH '
                      'toggles crouching. The ◀ ▶ WPN buttons above '
                      'the joystick switch weapons (hold to cycle '
                      'fast). TAB taps the Tab key — for moments like '
                      '"Press TAB to buy the property".'),
                  _HelpLine('CHEATS (top of the controller): tap a '
                      'cheat and the remote types the code into your '
                      'game — San Andreas, Vice City and GTA 5. Stand '
                      'in the game world first (not in a menu). GUIDE '
                      'explains how missions work and where to find '
                      'them.'),
                  _HelpLine('While driving: hold HORN to sound the '
                      'horn (in STEERING mode it is the middle of '
                      'the wheel). MISSION starts vehicle missions '
                      '— sit in a taxi, police car or ambulance and '
                      'tap it (San Andreas: Caps Lock, GTA V: E).'),
                  _HelpLine('FLY mode (the switch at the top, while '
                      'driving) is for planes and helicopters: one '
                      'HANDLE does everything — push it left/right '
                      'to turn, push it up to climb (nose up), pull '
                      'it down to descend (nose down); a corner '
                      'push turns and climbs together. RACE is the '
                      'throttle, DOWN slows down or sinks. The '
                      'CAMERA pad still turns the camera. There is '
                      'no HORN or MISSION in FLY mode.'),
                  _HelpLine('CRICKET mode (the switch at the top, '
                      'while driving) is for EA Sports Cricket 07. '
                      'BATTING: tap a shot button (FRONT FOOT, BACK '
                      'FOOT or ADVANCE), hold LOFT for a lofted '
                      'shot, then swipe on the field towards where '
                      'the shot should go, just as the ball '
                      'arrives — a plain tap plays no shot, which '
                      'is how you leave a ball. BOWLING: drag on '
                      'the pitch to move the marker, then tap a '
                      'delivery button. CAMERA ULTA flips the '
                      'swipe directions — use it if you flipped '
                      'the camera inside the game.'),
                  _HelpLine('Everything is free — no ads, no time '
                      'limit, no internet needed.'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Game profile ke liye apna radio row (RadioListTile ke purane API se
/// bachne ke liye).
class _ProfileRadioRow extends StatelessWidget {
  const _ProfileRadioRow({
    required this.profile,
    required this.selected,
    required this.onTap,
  });

  final GameProfile profile;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected
                  ? const Color(0xFFF97316)
                  : const Color(0xFF64748B),
              size: 21,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.name,
                    style: const TextStyle(
                      fontSize: 14.5,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    profile.shortNote,
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
          color: Color(0xFFF97316),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF020617).withValues(alpha: 0.55),
        border: Border.all(color: const Color(0xFF262E3A)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

class _RowLabel extends StatelessWidget {
  const _RowLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFC2410C)
              : const Color(0xFF262E3A).withValues(alpha: 0.6),
          border: Border.all(
            color: selected
                ? const Color(0xFFF97316)
                : const Color(0xFF334155),
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : const Color(0xFFCBD5E1),
          ),
        ),
      ),
    );
  }
}

class _HelpLine extends StatelessWidget {
  const _HelpLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  ', style: TextStyle(color: Color(0xFFF97316))),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: Color(0xFFCBD5E1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
