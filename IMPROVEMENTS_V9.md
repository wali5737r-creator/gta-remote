# IMPROVEMENTS_V9 — v5.5: Camera pad up/down (Y) sensitivity fix

## Malik ki report (2026-11-26)

"Nishana set krta hu to wo ak jga pe set ni hota — bht ziada upr ko
camera chla jta ya nichy. Asy firing ni hoti, mission fail hojta."

Pehle din Glint ne ghalat samjha tha (up/down sust hai) — malik ki
tafseel se asal masla saaf hua: **up/down BAHUT TEZ hai**. Nishana
bandhte waqt halki si drag par camera seedha upar ya neeche ja kar
atak jata hai; darmiyan me rukta hi nahi.

## Root cause (code + game, dono check kiye)

- App ka pipeline (pad → Dart → Kotlin → HID report) dx aur dy ko
  **bilkul aik tareeqe se** bhejta hai — v5.3/v5.4 ka diff bhi
  check kiya: move wale hisse me koi tabdeeli nahi thi. App ki
  taraf se dy ghalat nahi ja raha tha.
- Asal wajah game ki hai: SA me nishana bandhte waqt up/down ka
  kul range bohat chhota hai (left/right 360° ghum sakta hai,
  up/down sirf aik hadd tak). Utni hi mouse harkat up/down par
  poora range tay kar deti hai → nishana seedha kinare par.
- Pad ki geometry isay barhati hai: pad chaura zyada, uncha kam
  hai — ungli ka chhota sa up/down drag bhi bare counts bhejta tha
  (sensitivity 2.2, koi Y scale nahi tha).

## Fix (Dart-only, sirf `camera_pad.dart`)

- `CameraPad` me naya param `yScale = 0.5` (default sab pads par).
- `_handleMove`: `_pendingDy += delta.dy * sensitivity * yScale`.
- Left/right (dx) bilkul pehle jaisa. Sirf Y aadha.
- Nateeja: poora pad up/down drag ≈ poora aim range; chhoti drag
  = chhoti, rukne wali harkat — nishana darmiyan me set ho sakega.

## Teen nazariye (user / tester / expert)

- **User:** nishana ab rukega; firing aur mission par seedha asar.
  Koi naya button/setting nahi seekhna — pad pehle jaisa hi hai.
- **Tester:** traces —
  T1: paidal, AUTO-AIM ON, pad par halki up drag → aim thoda upar,
  kinare par nahi. T2: poori up drag → aim poora upar (range khatam).
  T3: left/right drag → pehle jaisi tez. T4: driving/FLY pad →
  camera up/down bhi naram (matlooba). T5: pause-menu map pointer
  → Y aadhi speed (kabul — pointer phir bhi aaram se chalta hai).
  T6: CRICKET mode → pad istemal hi nahi hota, asar nahi.
- **Expert:** change sirf aik multiplier hai; HID descriptor,
  Kotlin, report format — sab untouched. `_flush` ki ±127 chunking
  dono mehvaron par pehle ki tarah kaam karti hai (dy ab chhota
  jama hota hai, chunking par bojh kam). Koi state, koi timer,
  koi lifecycle tabdeel nahi — regression ka khatra kam tareen.

## HID / re-pair

`android/` ke neeche ZERO tabdeeli; descriptor md5
`ba778a379ab87a7f50ec5d2810479153` barqarar → **no re-pair,
v5.4 ke upar install.**

## Findings

0 critical, 0 major, 0 minor. Aik qabool-shuda asar: map pointer
ki Y speed bhi aadhi (T5) — nishane wale faide ke muqable me
na qabil-e-zikr.

## Not device-verified (malik ka session faisla karega)

- Nishana ab darmiyan me rukta hai ya nahi (asli test).
- 0.5 ka scale sahi hai ya aur kam/zyada chahiye — malik ki
  report par constant badal kar patch build ban sakta hai.
