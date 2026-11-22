import 'package:flutter/material.dart';

/// CRICKET mode ke gesture hisse (v7) — approved mockups
/// `v7-cricket-mode-4` (batting) aur `v7-cricket-bowling`
/// (bowling) ke mutabiq.
///
/// Dono hisse sirf ungli ki harkat report karte hain — koi key
/// khud nahi bhejte. Keys ka faisla controller karta hai
/// (sources wali architecture), is liye in widgets ke dispose
/// hone se koi key atak hi nahi sakti: batting shot sirf ungli
/// UTHNE par banta hai, aur bowling marker ki keys controller
/// ke 'cricket_marker' source me rehti hain jo har clear-all
/// par saaf hoti hain (widget dispose par bhi onDragEnd jata
/// hai — belt-and-braces).
///
/// Raw [Listener] ka tareeqa baqi controls wala hi hai: pehli
/// ungli malik, baqi nazarandaz — is liye dusri ungli se LOFT
/// dabaye hue pehli ungli ka swipe bilkul saaf chalta hai.

/// Batting ka swipe hissa: poora hissa hi swipe ki jagah hai.
/// Ungli uthne par [onSwipe] ko shuru se aakhir tak ka vector
/// (dp me) milta hai — simt aur lambai controller tay karta
/// hai (40 dp se chhota = tap = koi shot nahi, ball chor do).
class CricketBattingArea extends StatefulWidget {
  const CricketBattingArea({super.key, required this.onSwipe});

  /// Swipe khatam hua — vector = aakhri position − pehli position.
  final ValueChanged<Offset> onSwipe;

  @override
  State<CricketBattingArea> createState() => _CricketBattingAreaState();
}

class _CricketBattingAreaState extends State<CricketBattingArea> {
  int? _pointer;
  Offset? _start;
  Offset? _current;

  void _down(PointerDownEvent event) {
    if (_pointer != null) return;
    _pointer = event.pointer;
    setState(() {
      _start = event.localPosition;
      _current = event.localPosition;
    });
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    setState(() => _current = event.localPosition);
  }

  void _up(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    final start = _start;
    final delta = start == null
        ? Offset.zero
        : event.localPosition - start;
    setState(() {
      _pointer = null;
      _start = null;
      _current = null;
    });
    if (start != null) widget.onSwipe(delta);
  }

  void _cancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    setState(() {
      _pointer = null;
      _start = null;
      _current = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _cancel,
      child: Container(
        decoration: _fieldDecoration,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const Positioned.fill(child: _PitchStrip(width: 92, alpha: 0.16)),
            // Simton ke naam — sirf dikhawa (IgnorePointer),
            // mockup wali jagahain (broadcast camera ke hisab
            // se: seedha shot neeche ki taraf aata hai).
            Positioned.fill(
              child: IgnorePointer(
                child: Stack(
                  children: [
                    _label(
                      const Alignment(-0.94, -0.94),
                      'SWIPE FOR THE SHOT',
                      caption: true,
                    ),
                    _label(const Alignment(0, -0.90), 'PEECHE ▼'),
                    _label(const Alignment(-0.72, -0.62), 'THIRD MAN'),
                    _label(const Alignment(0.72, -0.62), 'FINE LEG'),
                    _label(const Alignment(-0.94, 0), '◀ POINT'),
                    _label(const Alignment(0.94, 0), 'LEG SIDE ▶'),
                    _label(const Alignment(-0.78, 0.60), 'COVER'),
                    _label(const Alignment(0.78, 0.60), 'ON-DRIVE'),
                    _label(const Alignment(0, 0.72), '▲ SEEDHA'),
                    const Align(
                      alignment: Alignment(0, 0.95),
                      child: Text(
                        'Tap without a swipe = leave the ball',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                          color: Color(0xBFEAF5EC),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Swipe ki lakeer — ungli ke saath banti hai, uthte
            // hi ghayab (shot controller bhej chuka hota hai).
            Positioned.fill(
              child: CustomPaint(
                painter: _SwipeTrailPainter(start: _start, current: _current),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bowling ka drag hissa: ungli ghaseeto to marker hilega.
/// Drag ke doran [onDragChanged] ko anchor se mojooda vector
/// milta rehta hai; ungli uthte/cancel par [onDragEnd].
/// Marker wala gol nishan sirf dikhawa hai — asal marker game
/// ke andar controller ki bheji hui arrow keys se hilta hai.
class CricketBowlingArea extends StatefulWidget {
  const CricketBowlingArea({
    super.key,
    required this.onDragChanged,
    required this.onDragEnd,
  });

  /// Drag ka vector (anchor → mojooda position), dp me.
  final ValueChanged<Offset> onDragChanged;

  /// Ungli uth gayi ya drag cancel hua.
  final VoidCallback onDragEnd;

  @override
  State<CricketBowlingArea> createState() => _CricketBowlingAreaState();
}

class _CricketBowlingAreaState extends State<CricketBowlingArea> {
  int? _pointer;
  Offset? _anchor;
  Offset? _finger;

  bool get _dragging => _pointer != null;

  void _down(PointerDownEvent event) {
    if (_pointer != null) return;
    _pointer = event.pointer;
    _anchor = event.localPosition;
    setState(() => _finger = event.localPosition);
    widget.onDragChanged(Offset.zero);
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    setState(() => _finger = event.localPosition);
    widget.onDragChanged(event.localPosition - _anchor!);
  }

  void _end(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _anchor = null;
    setState(() => _finger = null);
    widget.onDragEnd();
  }

  @override
  void dispose() {
    // Widget drag ke beech me khatam ho jaye (tab/mode switch)
    // to marker ki keys controller par chhor do — woh waisay
    // hi clear-all se saaf hoti hain, ye sirf pakki hifazat hai.
    if (_dragging) widget.onDragEnd();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _end,
      onPointerCancel: _end,
      child: Container(
        decoration: _fieldDecoration,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            // Marker ki aaram ki jagah: pitch ke beech, good
            // length se zara neeche (mockup wali jagah).
            final rest = Offset(size.width / 2, size.height * 0.58);
            final markerPos = _finger == null
                ? rest
                : Offset(
                    _finger!.dx.clamp(17.0, size.width - 17),
                    _finger!.dy.clamp(17.0, size.height - 17),
                  );
            return Stack(
              fit: StackFit.expand,
              children: [
                const Positioned.fill(child: _PitchStrip(width: 120, alpha: 0.22)),
                // Pitch par zones ke naam (geoposition mockup
                // ke mutabiq: upar BOUNCER, beech GOOD LENGTH,
                // neeche YORKER) — sirf dikhawa.
                Positioned.fill(
                  child: IgnorePointer(
                    child: Stack(
                      children: [
                        _label(
                          const Alignment(-0.94, -0.94),
                          'PLACE THE BALL — DRAG',
                          caption: true,
                        ),
                        _zoneLabel(const Alignment(0, -0.52), 'BOUNCER'),
                        _zoneLabel(const Alignment(0, 0.08), 'GOOD LENGTH'),
                        _zoneLabel(const Alignment(0, 0.66), 'YORKER'),
                        _label(const Alignment(-0.94, 0), '◀ OFF SIDE'),
                        _label(const Alignment(0.94, 0), 'LEG SIDE ▶'),
                      ],
                    ),
                  ),
                ),
                // Marker — hara gol nishan, ungli ke saath chalta
                // hai; aaram ki haalat me good length par rehta hai.
                Positioned(
                  left: markerPos.dx - 17,
                  top: markerPos.dy - 17,
                  child: IgnorePointer(
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF2EE66B),
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF2EE66B)
                                .withValues(alpha: _dragging ? 0.65 : 0.4),
                            blurRadius: 16,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF2EE66B),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Dono hisson ki mushtarka pehchan: gehra sabz maidan, hari
/// kinari (mockup wale rang — Cricket ki apni pehchan, app ke
/// orange theme se alag jaan-boojh kar, jaise FLY ki sky-blue).
final BoxDecoration _fieldDecoration = BoxDecoration(
  gradient: const RadialGradient(
    center: Alignment(-0.36, -0.1),
    radius: 1.25,
    colors: [Color(0xFF17451F), Color(0xFF0E2C15), Color(0xFF081A0E)],
  ),
  border: Border.all(color: const Color(0x662EE66B)),
  borderRadius: BorderRadius.circular(18),
);

/// Kinare par simt ka naam (halka sabz-safed, sirf dikhawa).
Widget _label(Alignment alignment, String text, {bool caption = false}) {
  return Align(
    alignment: alignment,
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: caption ? 2.5 : 2,
        color: caption
            ? const Color(0xFF7BF79F)
            : const Color(0x99CFE8D6),
      ),
    ),
  );
}

/// Pitch ke upar zone ka naam (gehra rang — halki pitch par
/// parha jaye, mockup ki tarah).
Widget _zoneLabel(Alignment alignment, String text) {
  return Align(
    alignment: alignment,
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.5,
        color: Color(0xBF1E281E),
      ),
    ),
  );
}

/// Beech ki halki pitch patti + do crease lakeerain — dono
/// hisson me aik jaisi. Sirf dikhawa hai.
class _PitchStrip extends StatelessWidget {
  const _PitchStrip({required this.width, required this.alpha});

  final double width;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        return Stack(
          fit: StackFit.expand,
          children: [
            Align(
              alignment: Alignment.center,
              child: Container(
                width: width,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFFC9B083).withValues(alpha: alpha),
                      const Color(0xFFB39468).withValues(alpha: alpha),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            // Crease lakeerain — pitch se zara chauri, upar aur
            // neeche ke hisson par.
            for (final fraction in [0.18, 0.82])
              Positioned(
                top: h * fraction,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    width: width + 28,
                    height: 2,
                    color: Colors.white.withValues(alpha: 0.28),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Swipe ki lakeer: shuru par halka gola, ungli tak lakeer —
/// shot ki simt ka foran ishara. Ungli uthte hi state saaf,
/// lakeer ghayab.
class _SwipeTrailPainter extends CustomPainter {
  const _SwipeTrailPainter({required this.start, required this.current});

  final Offset? start;
  final Offset? current;

  @override
  void paint(Canvas canvas, Size size) {
    final from = start;
    final to = current;
    if (from == null || to == null) return;
    final line = Paint()
      ..color = const Color(0xFF7BF79F).withValues(alpha: 0.85)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(from, to, line);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0xFF7BF79F)
      ..strokeWidth = 2.5;
    canvas.drawCircle(from, 8, ring);
    final dot = Paint()..color = const Color(0xFF7BF79F);
    canvas.drawCircle(to, 5, dot);
  }

  @override
  bool shouldRepaint(covariant _SwipeTrailPainter oldDelegate) =>
      oldDelegate.start != start || oldDelegate.current != current;
}
