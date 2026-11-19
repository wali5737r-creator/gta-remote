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
                  const _RowLabel('Wheel kitna ghume (aik side)'),
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
                  const _RowLabel('Sensitivity — ungli par wheel ki raftar'),
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
                        child: _RowLabel('Dead zone — centre ki khamoshi'),
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
                  'Wheel right side, pedals left side (left-handed ke liye)',
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
                    'Note: GTA ke andar keys Default par rakho, warna button ke naam game se match nahi karenge.',
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
                  _HelpLine('Khelte waqt ye app khuli rakho — band ki to '
                      'Bluetooth keyboard bhi band ho jayega.'),
                  _HelpLine('Connect fail ho to dusri remote/keyboard apps '
                      'band karke dobara koshish karo — aik waqt me sirf aik '
                      'app Bluetooth keyboard ban sakti hai.'),
                  _HelpLine('Connection bar bar katay to: phone Settings → '
                      'Apps → AB GTA → Battery → Unrestricted kar do.'),
                  _HelpLine('Driving me upar wale STEERING | TILT switch '
                      'se steering ka tareeqa badal sakte ho — TILT me '
                      'phone ko left/right hilane se gari murti hai. '
                      'Upar wali steering settings (range, sensitivity, '
                      'dead zone) sirf touch wheel ke liye hain.'),
                  _HelpLine('Sab kuch free hai — koi ads nahi, koi time '
                      'limit nahi, internet ki zaroorat nahi.'),
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
