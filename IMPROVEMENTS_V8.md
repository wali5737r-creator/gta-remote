# IMPROVEMENTS_V8 — v5.4 ATTACK auto-aim (aim + fire, aik button)

Teen nazariye se jaiza — user, tester, expert — final APK bhejne se pehle.
Muhammad ki darkhwast (2026-11-24): AIM phir ATTACK — do alag buttons
dabane me waqt lagta hai; ATTACK ke andar hi nishana lagane wala
function rakh do. Koi naya button nahi, koi layout change nahi.

## §1 Kya badla

- `controller_screen.dart` (Dart-only):
  - `_attackButton` (paidal mode): dabate hi LEFT (fire) **aur**
    RIGHT (aim) dono mouse bits lagte hain; chhorne par dono chhut-te
    hain. Sub-label `Mouse` → `Aim + Fire`.
  - `_aimButton`: ab sirf nishana (baghair fire) — `setMouseButton`
    ki jagah `_setAimHeldBy('aim', held)`.
  - Naya helper `_setAimHeldBy(source, held)` + field
    `_aimHolders` (Set<String>): right bit tabhi chhutta hai jab
    'aim' AUR 'attack' dono malik chhor dein.
  - `_clearAllKeys()` me `_aimHolders.clear()` — safety paths par
    bookkeeping bhi saaf (service `releaseAllKeys()` mouse bits ko
    pehle hi zero karta hai).
- `pubspec.yaml`: `5.4.0+6`.
- `android/` me ZERO change — descriptor/SDP/QOS untouched.

## §2 User lens (Muhammad ke haath se)

- Larai me aik hi ungli ka kaam: ATTACK dabao = nishana + goli,
  dono aik saath. AIM dabane ka waqt bach gaya.
- AIM button phir bhi maujood hai — jab sirf dekhna ho (door se
  nishana, baghair goli chalaye) to wohi purana tareeqa.
- Button ki jagah/size aik jaisi — haath ki adat nahi badlegi.
- Label `Aim + Fire` bata deta hai ke button ab kya karta hai.

## §3 Tester lens — har rasta trace kiya

- T1 ATTACK dabao → mouse report left=1, right=1 (do reports,
  aik ke peeche aik, ~1 ms farq; game ko dono bits aik saath
  milte hain). Chhoro → left=0, right=0. ✓
- T2 AIM dabaye rakho, phir ATTACK dabao/chhoro → ATTACK
  chhorne ke baad right=1 rehta hai (malik 'aim' baqi hai).
  AIM chhorne par right=0. ✓
- T3 ATTACK dabaye rakho, phir AIM dabao/chhoro → right=1
  rehta hai (malik 'attack' baqi hai). ✓
- T4 ATTACK dabaye hue mode badlo / disconnect / pause →
  `_clearAllKeys()` → `_aimHolders` khaali + service mouse=0.
  Wapas aane par koi atka hua aim nahi. ✓
- T5 ATTACK par tez tap-tap → har press/release jora barabar
  (left/right dono symmetric) — koi bit atak nahi sakta. ✓
- T6 Bandooq nahi hai to ATTACK dabane se sirf mouse bits
  lagte hain, game kuch nahi karta — pehle jaisa hi. ✓
- Edge: CAMERA pad drag ATTACK dabaye hue bhi `_mouseButtons`
  ke saath report bhejta hai — pehle bhi AIM dabaye hue aisa hi
  tha; camera aim karte hue ghumti hai, jo theek hai. ✓
- Edge: WPN wheel-tick aur CHEATS typer mouse bits ko nahi
  chhoote — un par koi asar nahi. ✓
- Koi naya HID report type nahi — mouse report wahi purani hai,
  sirf bits ka jor badla hai.

## §4 Expert lens

- Malik-gin (refcount) pattern: do sources aik shared bit ko
  pakar sakte hain — yahi sahi design hai; seedha
  `setMouseButton(right, false)` ATTACK release par AIM ko
  ghalat tor deta, is liye helper zaroori tha.
- State aik jagah hai (`_aimHolders` screen me); service ka
  `_mouseButtons` hi asal sach hai; `_clearAllKeys` dono ko
  saath saaf karta hai — stale-holder ka rasta band hai.
- Koi Kotlin/Java change nahi, koi naya permission nahi, koi
  naya dependency nahi — compile risk taqreeban zero; Actions
  build hi compile ka saboot hai (is machine par Dart SDK nahi).
- ATTACK dabane par do mouse reports bhejte hain (left, phir
  right). Aik report me dono bits bhejna bhi mumkin tha, lekin
  helper ko single source of truth rakhna zyada mehfooz hai;
  1 ms ka farq game me nazar nahi ata. Minor, theek hai.

## §5 Descriptor / re-pair — build ke baad verify karna

- `git diff HEAD -- android/` EMPTY hona chahiye; descriptor +
  SDP + QOS md5 `ba778a379ab87a7f50ec5d2810479153` waisa hi rehna
  chahiye jaisa v4/v5/v5.1/v5.2/v5.3 me tha → **no re-pair**,
  v5.3 ke upar install karo.
- Binary manifest me label "Gaming Remote" + versionName 5.4.0
  check karna.

## §6 Malik ko device par verify karna hai

- Paidal mode me bandooq le kar ATTACK dabao — CJ ko aim karte
  hue fire karna chahiye (pehle sirf fire hota tha).
- AIM akela dabao — sirf nishana, goli nahi.
- AIM dabaye rakh kar ATTACK dabao/chhoro — aim nahi tootna
  chahiye.
- Kisi mode switch ke baad aim atakna nahi chahiye.
