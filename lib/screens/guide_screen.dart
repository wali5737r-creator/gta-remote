import 'package:flutter/material.dart';

import '../widgets/premium_background.dart';

/// MISSIONS GUIDE (v5) — one scrollable page that teaches a
/// beginner how missions work in the three games: follow the
/// letter on the radar, stand in the glowing marker. The remote
/// itself is only a keyboard — it cannot see inside the game —
/// so this guide is the honest way to "find a mission": the
/// steps are always the same, in every game.
class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  static const Color _saAccent = Color(0xFFF7931E);
  static const Color _vcAccent = Color(0xFFFF71CE);
  static const Color _gta5Accent = Color(0xFF9CCC4F);
  static const Color _text = Color(0xFFD7E3EA);
  static const Color _muted = Color(0xFF93A7B4);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // PremiumBackground ke gradient ka darmiyani rang — kinare
      // par kahin khali jagah dikhe to wahi rang mile.
      backgroundColor: const Color(0xFF0B0E13),
      body: PremiumBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 22),
                  children: [
                    _buildHowMissionsWork(),
                    _buildGameSection(
                      title: 'GTA SAN ANDREAS',
                      accent: _saAccent,
                      lines: const [
                        'S — Sweet: Grove Street, in front of his house. The first missions start here.',
                        'R — Ryder: Grove Street, his house with the pickup truck.',
                        'BS — Big Smoke: his house in Idlewood.',
                        'OG — OG Loc: after he comes home, Grove Street area.',
                        "Save your game at CJ's house (Johnson House, Grove Street) — walk to the disk icon inside.",
                        'Gun shop (Ammu-Nation) opens after the first few missions.',
                        'Los Santos Airport: bottom of the city, by the sea. A private jet (Shamal) parks there — climb in with the jetpack.',
                        'Las Venturas Airport: top-right city. The big passenger plane (AT-400) waits in the biggest hangar. That area is locked at the start — use the AEZAKMI cheat so police leave you alone.',
                        'Vehicle missions (taxi, police, ambulance): sit in the vehicle and press the MISSION button in this remote.',
                      ],
                    ),
                    _buildGameSection(
                      title: 'VICE CITY',
                      accent: _vcAccent,
                      lines: const [
                        'Letters on the radar are mission bosses — the letter is the first letter of their name. Stand in the pink marker to start.',
                        'First save point: Ocean View Hotel (disk icon). Later you can buy properties with their own save points.',
                        'V — your own mansion story missions (later in the game).',
                      ],
                    ),
                    _buildGameSection(
                      title: 'GTA 5',
                      accent: _gta5Accent,
                      lines: const [
                        'M — Michael, F — Franklin, T — Trevor, L — Lester. Go to the letter on the map and walk into the glowing marker.',
                        'Save at safehouse beds, or use Quick Save on the in-game phone.',
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MISSIONS GUIDE',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.5,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'How to find and start missions in every game',
                  style: TextStyle(fontSize: 12.5, color: _muted),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.07),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                ),
              ),
              child: const Icon(Icons.close, size: 17, color: Color(0xFFDFE9EF)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHowMissionsWork() {
    const steps = [
      'Look at the small map (radar) — a big letter shows where a mission is waiting.',
      'Go to that letter.',
      'Stand in the glowing marker (red in San Andreas, pink in Vice City). The mission starts by itself.',
      'In the mission, follow the marker on the radar — it always shows where to go next.',
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.055),
            Colors.white.withValues(alpha: 0.02),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ALL GAMES — HOW MISSIONS WORK',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF2EE66B),
                    ),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF06280F),
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      steps[i],
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.3,
                        color: _text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGameSection({
    required String title,
    required Color accent,
    required List<String> lines,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 15,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.7),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.5,
                  color: accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        accent.withValues(alpha: 0.35),
                        accent.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      '•',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      line,
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.3,
                        color: _text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
