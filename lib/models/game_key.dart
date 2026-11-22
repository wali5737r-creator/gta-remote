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

  // v6 (FLY mode): jahaz ki naak upar/neeche ke liye asli arrow
  // keys. GTA SA mai ArrowDown = naak UPAR, ArrowUp = naak
  // NEECHE (flight-stick convention) — ye ulta asar jaan-boojh
  // kar hai; controller ki FLY layer mai trace maujood hai.
  arrowUp(0x52, 'ArrowUp'),
  arrowDown(0x51, 'ArrowDown'),

  // v5.2 (FLY fix): numpad ki pitch keys. GTA SA (2005) jahaz ko
  // arrow keys se NAHI ghumata — pitch us ke "Special Control"
  // mehwar par hai: Numpad 2 = naak UPAR, Numpad 8 = naak NEECHE.
  // GTA V: Numpad 5 = naak UPAR, Numpad 8 = naak NEECHE. Is liye
  // FLY handle arrows ke SAATH ye keys bhi bhejta hai (tafseel
  // controller ki _feedFlyStick trace mai). Keycodes USB HID
  // standard ke hain: KP2 = 0x5A, KP5 = 0x5D, KP8 = 0x60.
  numpad2(0x5A, 'Numpad 2'),
  numpad5(0x5D, 'Numpad 5'),
  numpad8(0x60, 'Numpad 8'),

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
  // v6: FLY pitch keys (arrows) list ke aakhir mai — purani keys ki
  // relative order bilkul nahi badli, is liye purane key-set
  // snapshots ke report bytes pehle jaise hi rehte hain.
  GameKey.arrowUp,
  GameKey.arrowDown,
  // v5.2: numpad pitch keys bhi bilkul aakhir mai (arrows ke baad) —
  // wahi byte-identity wala usool: purane tamam key sets ke report
  // bytes na-badla rehte hain.
  GameKey.numpad2,
  GameKey.numpad5,
  GameKey.numpad8,
];
