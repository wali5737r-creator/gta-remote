import 'package:flutter/material.dart';

/// One cheat code and the plain-English hint for what it does (v5).
class Cheat {
  const Cheat(this.code, this.hint);

  /// The word the game listens for — typed letter by letter by
  /// `HidService.typeCheatCode`.
  final String code;

  /// One-line explanation shown under the code on the card.
  final String hint;
}

/// A named group of cheats on one game's tab.
class CheatCategory {
  const CheatCategory(this.name, this.cheats);

  final String name;
  final List<Cheat> cheats;
}

/// One game's cheat tab: its codes, its accent colour, and how
/// its codes must be typed.
class CheatGame {
  const CheatGame({
    required this.name,
    required this.accent,
    required this.useConsole,
    required this.categories,
    this.footerNote,
  });

  /// Tab label, e.g. 'SAN ANDREAS'.
  final String name;

  /// The game's premium accent (SA orange, VC pink, GTA 5 green).
  final Color accent;

  /// GTA 5 types its codes into the ~ console; SA and VC take
  /// them typed directly in the game.
  final bool useConsole;

  final List<CheatCategory> categories;

  /// Small print under the list (null = no footer for this game).
  final String? footerNote;

  int get codeCount =>
      categories.fold(0, (sum, category) => sum + category.cheats.length);
}

/// All cheat data for the CHEATS screen (v5) — three games,
/// grouped the way the approved premium mockup shows them.
const List<CheatGame> cheatGames = [
  CheatGame(
    name: 'SAN ANDREAS',
    accent: Color(0xFFF7931E),
    useConsole: false,
    categories: [
      CheatCategory('Survival & Money', [
        Cheat('HESOYAM', 'Full health + armor + \$250,000'),
        Cheat('BAGUVIX', 'God mode: health never drops'),
        Cheat('CVWKXAM', 'Unlimited oxygen under water'),
        Cheat('AEDUWNV', 'Never hungry'),
      ]),
      CheatCategory('Weapons', [
        Cheat('LXGIWYL', 'Weapon set 1'),
        Cheat('KJKSZPJ', 'Weapon set 2 (strong)'),
        Cheat('UZUMYMW', 'Weapon set 3 (heaviest)'),
        Cheat('FULLCLIP', 'Infinite ammo, no reload'),
        Cheat('NCSGDAG', 'All weapon skills full'),
      ]),
      CheatCategory('Police', [
        Cheat('AEZAKMI', 'Police never chase you'),
        Cheat('ASNAEB', 'Clear all wanted stars'),
        Cheat('OSRBLHH', 'Add 2 wanted stars'),
        Cheat('BRINGITON', '6 stars: full police attack'),
      ]),
      CheatCategory('Vehicles & Flying', [
        Cheat('AIWPRTON', 'Tank (Rhino)'),
        Cheat('ROCKETMAN', 'Jetpack'),
        Cheat('AIYPWZQP', 'Parachute'),
        Cheat('URKQSRK', 'Stunt plane'),
        Cheat('JUMPJET', 'Fighter jet (Hydra)'),
        Cheat('OHDUDE', 'Attack helicopter (Hunter)'),
        Cheat('AGBDLCID', 'Monster truck'),
        Cheat('KGGGDKP', 'Hovercraft (Vortex)'),
        Cheat('AMOMHRER', 'Tanker truck'),
        Cheat('RZHSUEW', 'Golf cart (Caddy)'),
      ]),
      CheatCategory('Fun & World', [
        Cheat('VQIMAHA', 'All driving skills full'),
        Cheat('OGXSDAG', 'Maximum respect'),
        Cheat('LFGMHAL', 'Mega jump'),
        Cheat('IAVENJQ', 'Mega punch'),
        Cheat('BTCDBCB', 'CJ becomes fat'),
        Cheat('KVGYZQK', 'CJ becomes skinny'),
        Cheat('PLEASANTLYWARM', 'Sunny weather'),
        Cheat('XJVSNAJ', 'Always midnight'),
        Cheat('RIPAZHA', 'Cars fly'),
        Cheat('JCNRUAD', 'Cars explode on touch'),
        Cheat('COXEFGU', 'All cars have nitro'),
        Cheat('IOJUFZN', 'City riot (do not save after using)'),
        Cheat('SZCMAWO', 'Suicide (careful!)'),
      ]),
    ],
  ),
  CheatGame(
    name: 'VICE CITY',
    accent: Color(0xFFFF71CE),
    useConsole: false,
    footerNote:
        'Classic PC codes. Most also work in the Definitive Edition; a few may not.',
    categories: [
      CheatCategory('Survival & Money', [
        Cheat('ASPIRINE', 'Full health'),
        Cheat('PRECIOUSPROTECTION', 'Full armor'),
      ]),
      CheatCategory('Weapons', [
        Cheat('THUGSTOOLS', 'Weapon set 1'),
        Cheat('PROFESSIONALTOOLS', 'Weapon set 2 (strong)'),
        Cheat('NUTTERTOOLS', 'Weapon set 3 (heaviest)'),
      ]),
      CheatCategory('Police', [
        Cheat('LEAVEMEALONE', 'Clear wanted stars'),
        Cheat('YOUWONTTAKEMEALIVE', 'Add wanted stars'),
      ]),
      CheatCategory('Vehicles & Flying', [
        Cheat('PANZER', 'Tank (Rhino)'),
        Cheat('AMERICAHELICOPTER', 'Attack helicopter (Hunter)'),
        Cheat('TRAVELINSTYLE', 'Racing car'),
        Cheat('GETTHEREFAST', 'Sabre Turbo car'),
        Cheat('GETTHEREVERYFASTINDEED', 'Hotring racer'),
        Cheat('THELASTRIDE', 'Hearse car'),
        Cheat('ROCKANDROLLCAR', 'Limo'),
        Cheat('RUBBISHCAR', 'Garbage truck'),
        Cheat('BETTERTHANWALKING', 'Golf cart (Caddy)'),
        Cheat('SEAWAYS', 'Cars drive on water'),
        Cheat('COMEFLYWITHME', 'Cars fly'),
        Cheat('AIRSHIP', 'Boats fly'),
      ]),
      CheatCategory('Fun & World', [
        Cheat('BIGBANG', 'Blow up all nearby cars'),
        Cheat('GREENLIGHT', 'All traffic lights green'),
        Cheat('MIAMITRAFFIC', 'Angry drivers'),
        Cheat('ONSPEED', 'Game speed fast'),
        Cheat('BOOOOOORING', 'Game speed slow'),
        Cheat('ALOVELYDAY', 'Sunny weather'),
        Cheat('CATSANDDOGS', 'Stormy weather'),
        Cheat('FIGHTFIGHTFIGHT', 'People fight each other'),
        Cheat('CERTAINDEATH', 'Smoke a cigarette'),
        Cheat('DEEPFRIEDMARSBARS', 'Tommy becomes fat'),
        Cheat('PROGRAMMER', 'Tommy becomes skinny'),
        Cheat('STILLLIKEDRESSINGUP', 'Change clothes and skin'),
        Cheat('ICANTTAKEITANYMORE', 'Suicide (careful!)'),
      ]),
    ],
  ),
  CheatGame(
    name: 'GTA 5',
    accent: Color(0xFF9CCC4F),
    useConsole: true,
    footerNote:
        'The remote opens the console, types the code and presses Enter for you. Cheats pause achievements until you reload your save.',
    categories: [
      CheatCategory('Survival', [
        Cheat('PAINKILLER', 'God mode for 5 minutes'),
        Cheat('TURTLE', 'Full health + armor'),
        Cheat('POWERUP', 'Refill special ability'),
      ]),
      CheatCategory('Police', [
        Cheat('LAWYERUP', 'Remove 1 wanted star'),
        Cheat('FUGITIVE', 'Add 1 wanted star'),
      ]),
      CheatCategory('Weapons & Ability', [
        Cheat('DEADEYE', 'Slow-motion aiming'),
        Cheat('SLOWMO', 'Slow-motion world'),
        Cheat('CATCHME', 'Run very fast'),
        Cheat('GOTGILLS', 'Swim very fast'),
        Cheat('HOPTOIT', 'Super jump'),
        Cheat('SKYDIVE', 'Parachute'),
        Cheat('SKYFALL', 'Fall from the sky'),
        Cheat('LIQUOR', 'Drunk mode'),
      ]),
      CheatCategory('Vehicles', [
        Cheat('COMET', 'Comet sports car'),
        Cheat('RAPIDGT', 'Rapid GT car'),
        Cheat('VINEWOOD', 'Limo'),
        Cheat('TRASHED', 'Garbage truck'),
        Cheat('HOLEIN1', 'Golf cart (Caddy)'),
        Cheat('OFFROAD', 'Sanchez dirt bike'),
        Cheat('ROCKET', 'PCJ-600 bike'),
        Cheat('BANDIT', 'BMX bicycle'),
        Cheat('BUZZOFF', 'Buzzard attack helicopter'),
        Cheat('BARNSTORM', 'Stunt plane'),
        Cheat('FLYSPRAY', 'Crop duster plane'),
      ]),
      CheatCategory('Fun & World', [
        Cheat('MAKEITRAIN', 'Change the weather'),
        Cheat('SNOWDAY', 'Slippery cars (drift)'),
        Cheat('FLOATER', 'Moon gravity'),
      ]),
    ],
  ),
];
