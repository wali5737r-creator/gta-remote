# IMPROVEMENTS_V8 — v5.4 Two-button fight: pad aims, ATTACK fires

Teen nazariye se jaiza — user, tester, expert — final APK bhejne se pehle.
Muhammad ki darkhwast (2026-11-24/25, teen paigham, aik design):
1. AIM phir ATTACK — do alag buttons dabane me waqt lagta hai.
2. Fight ke waqt nishana ATTACK par set ho; baqi jagah ATTACK
   use ho to nahi — if-else jaisa; band karne ka button bhi ho.
3. **Aakhri design: do button se kaam ho** — mouse (pad) se
   direction set karna phir ATTACK dabana mushkil hai; **nishana
   touch pad par hi set karo**.

## §1 Kya badla (aakhri design)

- **CAMERA pad (paidal mode, `camera_pad.dart` + controller):**
  pad chhoote hi right (aim) bit lag jata hai — **drag = simt +
  nishana**, ungli uthte hi nishana chhutta hai. Driving/FLY me
  pad sirf camera rehta hai (gaari/jahaz me aim ka koi kaam nahi).
  Pad ka label auto-aim ON + paidal ho to **'AIM + CAMERA'**.
- **ATTACK (paidal mode):** dabate hi LEFT (fire) + RIGHT (aim)
  dono bits — sub-label **'Aim + Fire'**.
- **AUTO-AIM toggle pill (top bar, dusri satar, sirf ON FOOT):**
  'AUTO-AIM ON' (hara) / 'AUTO-AIM OFF' (grey). OFF par ATTACK
  sirf fire aur pad sirf camera — pehle jaisa. Pasand
  `SettingsService.autoAim` me save hoti hai (default ON).
- **AIM button:** waisa hi rehta hai — baghair fire ke sirf
  nishana (door se dekhna / scope).
- **Aim ke malik (refcount):** `_aimHolders` Set — 'aim', 'attack',
  'pad' teeno right bit ko pakar sakte hain; bit tabhi chhutta
  hai jab teeno chhor dein. `_padTouched` flag toggle ke waqt
  sync ke liye; `_clearAllKeys` dono saaf karta hai.
- `pubspec.yaml`: `5.4.0+6`. `android/` me ZERO change.

## §2 User lens (Muhammad ke haath se)

- Larai me sirf DO cheezein: **pad ghumao** (nishana + simt aik
  saath) aur **ATTACK dabao** (goli). AIM button ab zaroori nahi.
- Pad se ungli uthte hi nishana chhutta hai — ghoomte waqt bhi
  aim nahi atakta.
- Bina bandooq ke ghumne / mukka marne ke liye: **AUTO-AIM OFF**
  kar do — ATTACK sirf fire/mukka, pad sirf camera. Aik tap,
  upar pill par.
- Button ki jagah/size aik jaisi — haath ki adat nahi badlegi;
  naya pill upar hai, cluster/pad ki jagah nahi khata.

## §3 Tester lens — har rasta trace kiya

- T1 Pad chhoo → right=1 (aim), drag → camera ghumta hai aim
  karte hue. Ungli uthao → right=0. ✓
- T2 Pad chhua hua, ATTACK dabao/chhoro → aim rehta hai jab
  tak pad chhua hai (malik 'pad' baqi). ✓
- T3 ATTACK akela dabao → left=1, right=1; chhoro → dono 0. ✓
- T4 AIM dabaye rakho, pad chhoo/chhoro → aim AIM ki wajah se
  rehta hai; AIM chhorne par 0. ✓
- T5 AUTO-AIM OFF (ATTACK daba hua) → right foran 0, left=1
  rehta hai (fire jaari); dobara dabane ki zaroorat nahi. ✓
- T6 AUTO-AIM OFF (pad chhua hua) → right foran 0; pad chhorne
  par bhi 0 (onTouchEnd hamesha chhorta hai — stuck-aim ka
  rasta band). ✓
- T7 AUTO-AIM OFF, phir ON (pad chhua hua) → right foran 1. ✓
- T8 Pad chhua hua, mode badlo / disconnect → `_clearAllKeys`
  → holders khaali + `_padTouched=false` + mouse=0; wapas
  aane par koi atka aim nahi. ✓
- T9 Driving me pad chhoo → right kabhi nahi lagta (sirf
  camera). FLY me bhi nahi. ✓
- T10 Bandooq nahi hai to pad chhoone se SA melee target-lock
  ho sakta hai (qareeb ped ho to) — toggle OFF is ka hal hai;
  default ON is liye ke larai hi asal istemal hai. (Known,
  qubool-shuda.)
- Edge: CAMERA pad drag ATTACK dabaye hue bhi `_mouseButtons`
  ke saath report bhejta hai — aim karte hue camera ghumna
  theek hai. WPN wheel-tick / CHEATS typer mouse bits ko nahi
  chhoote. Koi naya HID report type nahi.

## §4 Expert lens

- Malik-gin (refcount) pattern teeno sources par: seedha
  `setMouseButton(right, false)` kisi bhi release par dusre
  malik ka aim tor deta — is liye helper zaroori tha.
- **No-notify setter:** `setAutoAim` `notifyListeners` NAHI
  karta — notify karte hi controller ka `_onSettingsChanged`
  saari keys (daba hua ATTACK bhi) chhor deta. Screen toggle
  handler me apni `setState` se dobara banti hai. Ye service
  ke baqi setters se farq hai — wajah code me likhi hai.
- `_padTouched` + `_clearAllKeys` me us ka reset: mode switch
  ke waqt pad ka `_handleUp` kabhi nahi aata (purana pad
  dispose ho jata hai) — reset na hota to toggle handler
  bekaar me 'pad' malik jor deta.
- Koi Kotlin/Java change nahi, koi naya permission/dependency
  nahi — compile risk taqreeban zero; Actions build hi compile
  ka saboot hai (is machine par Dart SDK nahi).
- Label 'AIM + CAMERA' 136 dp pad me fit hota hai (icon + text
  ~121 dp) — driving wale chaure pad par label 'CAMERA' hi
  rehta hai.

## §5 Descriptor / re-pair — build ke baad verify karna

- `git diff HEAD -- android/` EMPTY hona chahiye; descriptor +
  SDP + QOS md5 `ba778a379ab87a7f50ec5d2810479153` waisa hi rehna
  chahiye jaisa v4/v5/v5.1/v5.2/v5.3 me tha → **no re-pair**,
  v5.3 ke upar install karo.
- Binary manifest me label "Gaming Remote" + versionName 5.4.0
  check karna.

## §6 Malik ko device par verify karna hai

- Paidal mode, bandooq le kar: pad chhoo → CJ aim kare;
  drag → aim ghume; ATTACK dabao → fire aim ke saath.
- Pad se ungli uthao → aim chhute.
- AUTO-AIM OFF karo → ATTACK sirf fire, pad sirf camera.
- AIM akela dabao → sirf nishana, goli nahi.
- Mode switch ke baad aim atakna nahi chahiye.
