/// Aik keyboard key jo app laptop ko bhej sakti hai.
///
/// Har key ya to HID keycode hai (USB HID Usage Page 0x07) ya Left Shift,
/// jo keycode nahi hota — woh report ke modifier byte ka bit 0x02 hai.
enum GameKey {
  w(0x1A, 'W'),
  a(0x04, 'A'),
  s(0x16, 'S'),
  d(0x07, 'D'),

  /// GTA me gari me bethna / utarna.
  f(0x09, 'F'),

  /// SA me crouch toggle (v4).
  c(0x06, 'C'),

  /// SA / SA Definitive me horn (v5). GTA V me horn E hai —
  /// profile tay karta hai konsi key jayegi.
  h(0x0B, 'H'),

  /// GTA V me horn aur interact/submission key (v5).
  e(0x08, 'E'),

  /// SA me property khareedna waghera (v5, paidal mode ka TAB button).
  tab(0x2B, 'Tab'),

  /// SA me taxi/vigilante jaisi vehicle missions shuru karna
  /// (v5, MISSION button). Ye toggle key hai — host par Caps Lock
  /// ki haalat badalti hai, bilkul asal keyboard ki tarah.
  capsLock(0x39, 'Caps'),
  space(0x2C, 'Space'),
  enter(0x28, 'Enter'),
  escape(0x29, 'Esc'),

  /// Left Shift — keycode null hai, ye modifier byte se jata hai.
  shift(null, 'Shift');

  const GameKey(this.keycode, this.label);

  /// HID keycode, ya null agar ye modifier key hai (Shift).
  final int? keycode;

  /// Button ke neeche chhoti sub-text ke liye naam.
  final String label;

  bool get isModifier => keycode == null;

  /// Left Shift ka modifier bit (HID report byte 0).
  static const int shiftModifierBit = 0x02;
}

/// Report me keycodes ki tay shuda tartib — har report aik jaisi bane
/// taake duplicate reports pehchanay ja sakain.
const List<GameKey> hidKeyOrder = [
  GameKey.w,
  GameKey.a,
  GameKey.s,
  GameKey.d,
  GameKey.f,
  GameKey.c,
  GameKey.h,
  GameKey.e,
  GameKey.tab,
  GameKey.capsLock,
  GameKey.space,
  GameKey.enter,
  GameKey.escape,
];
