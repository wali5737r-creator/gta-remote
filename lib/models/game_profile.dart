import 'game_key.dart';

/// Aik game ki key mapping — konsi action konsi key se hogi.
///
/// Teen profiles hain (Muhammad ki final requirement: app har GTA par chale):
/// - GTA V
/// - GTA San Andreas — Original PC version (Run/Jump GTA V se ulta hai)
/// - GTA San Andreas — Definitive Edition (Jump = Space, Run = Space)
class GameProfile {
  const GameProfile({
    required this.id,
    required this.name,
    required this.shortNote,
    required this.sprintKey,
    required this.jumpKey,
    required this.hornKey,
    required this.submissionKey,
  });

  /// Shared preferences me save karne ke liye pehchan.
  final String id;

  /// Selector par dikhne wala naam.
  final String name;

  /// Selector card par aik line ki note (Run/Jump keys).
  final String shortNote;

  /// Paidal mode me RUN button ye key dabata hai.
  final GameKey sprintKey;

  /// Paidal mode me JUMP button ye key dabata hai.
  final GameKey jumpKey;

  /// Driving me HORN button ye key dabata hai (v5).
  /// GTA V: E — SA (dono): H. Emergency gariyon me yahi key
  /// siren bhi chalati/band karti hai.
  final GameKey hornKey;

  /// Driving me MISSION button ye key dabata hai (v5) — taxi,
  /// vigilante, ambulance jaisi vehicle side-missions shuru
  /// karne ke liye. GTA V: E — SA (dono): Caps Lock.
  final GameKey submissionKey;

  // Driving keys teeno games me aik jaisi hain.
  GameKey get accelerateKey => GameKey.w;
  GameKey get brakeKey => GameKey.s;
  GameKey get steerLeftKey => GameKey.a;
  GameKey get steerRightKey => GameKey.d;
  GameKey get enterExitKey => GameKey.f;
  GameKey get handbrakeKey => GameKey.space;

  static const GameProfile gtaV = GameProfile(
    id: 'gta_v',
    name: 'GTA V',
    shortNote: 'Run = Shift • Jump = Space',
    sprintKey: GameKey.shift,
    jumpKey: GameKey.space,
    hornKey: GameKey.e,
    submissionKey: GameKey.e,
  );

  static const GameProfile saOriginal = GameProfile(
    id: 'gta_sa_original',
    name: 'GTA San Andreas — Original',
    shortNote: 'Run = Space • Jump = Shift',
    sprintKey: GameKey.space,
    jumpKey: GameKey.shift,
    hornKey: GameKey.h,
    submissionKey: GameKey.capsLock,
  );

  static const GameProfile saDefinitive = GameProfile(
    id: 'gta_sa_definitive',
    name: 'GTA San Andreas — Definitive',
    shortNote: 'Run = Space • Jump = Space',
    sprintKey: GameKey.space,
    jumpKey: GameKey.space,
    hornKey: GameKey.h,
    submissionKey: GameKey.capsLock,
  );

  static const List<GameProfile> all = [gtaV, saOriginal, saDefinitive];

  static GameProfile byId(String? id) {
    for (final profile in all) {
      if (profile.id == id) return profile;
    }
    return gtaV;
  }
}
