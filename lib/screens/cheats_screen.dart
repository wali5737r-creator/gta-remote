import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/cheats.dart';
import '../services/hid_service.dart';

/// CHEATS screen (v5) — the approved premium design
/// (`mockup/v5-cheats-premium.png`): dark gradient, three game
/// tabs (SAN ANDREAS orange, VICE CITY pink, GTA 5 green), and
/// grouped cheat cards, each with the code and a one-line hint.
///
/// Tapping a card makes the remote type the code on the laptop
/// like a real keyboard (`HidService.typeCheatCode`) — SA and VC
/// take the word typed directly in the game; GTA 5 goes through
/// its ~ console (open, type, Enter — all done by the typer).
class CheatsScreen extends StatefulWidget {
  const CheatsScreen({super.key});

  @override
  State<CheatsScreen> createState() => _CheatsScreenState();
}

class _CheatsScreenState extends State<CheatsScreen> {
  final HidService _hid = HidService.instance;

  int _gameIndex = 0;

  /// This screen started a send and is waiting for it to finish.
  bool _sending = false;

  /// The code currently being typed (for the status line and to
  /// highlight its card).
  String? _typingCode;

  String _status = 'Tap a cheat and it is typed into your game.';
  _StatusKind _statusKind = _StatusKind.idle;

  /// Keeps the buttons' disabled state honest if the screen is
  /// re-entered while a code is still being typed (the typer
  /// itself also refuses a second code while busy).
  Timer? _syncTimer;
  bool _lastHidTyping = false;

  CheatGame get _game => cheatGames[_gameIndex];

  bool get _busy => _sending || _hid.isTypingCheat;

  @override
  void initState() {
    super.initState();
    _lastHidTyping = _hid.isTypingCheat;
    _syncTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!mounted || _sending) return;
      final typing = _hid.isTypingCheat;
      if (typing != _lastHidTyping) {
        _lastHidTyping = typing;
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  Future<void> _onCheatTap(Cheat cheat) async {
    if (_busy) return;
    if (!_hid.current.isConnected) {
      setState(() {
        _status = 'Not connected — connect to your laptop first.';
        _statusKind = _StatusKind.error;
      });
      return;
    }
    HapticFeedback.lightImpact();
    setState(() {
      _sending = true;
      _lastHidTyping = true;
      _typingCode = cheat.code;
      _status = 'Typing ${cheat.code}…';
      _statusKind = _StatusKind.typing;
    });
    final result = await _hid.typeCheatCode(
      cheat.code,
      useConsole: _game.useConsole,
    );
    if (!mounted) return;
    setState(() {
      _sending = false;
      _lastHidTyping = false;
      _typingCode = null;
      // v6: typer ab teen sachay nateejay deta hai — status bhi
      // waisa hi sach bolta hai (v5 me har fail "connection lost"
      // ban jata tha, halanke aksar link theek hota tha aur sirf
      // aik report gira hota tha).
      switch (result) {
        case CheatSendResult.success:
          _status = 'Sent — check your game';
          _statusKind = _StatusKind.done;
        case CheatSendResult.sendFailed:
          _status = 'Could not send — check the connection and try again.';
          _statusKind = _StatusKind.error;
        case CheatSendResult.notConnected:
          _status = 'Connection lost — the code was not fully typed.';
          _statusKind = _StatusKind.error;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final game = _game;
    return Scaffold(
      backgroundColor: const Color(0xFF0A0F14),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF10161D),
              Color(0xFF0A0F14),
              Color(0xFF0D1218),
            ],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Soft glow in the active game's colour (premium touch
            // from the mockup — orange for San Andreas).
            Positioned(
              top: -120,
              right: -60,
              child: IgnorePointer(
                child: Container(
                  width: 320,
                  height: 320,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        game.accent.withValues(alpha: 0.13),
                        game.accent.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(context),
                  _buildTabs(),
                  _buildStatusLine(),
                  Expanded(child: _buildList(game)),
                  if (game.footerNote != null) _buildFooter(game),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '★',
                      style: TextStyle(
                        fontSize: 23,
                        color: Color(0xFFF7A81E),
                        shadows: [
                          Shadow(
                            color: Color(0xFFF7A81E),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: 9),
                    Text(
                      'CHEATS',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 3,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 2),
                Text(
                  'Tap any cheat — the remote types the code for you',
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF93A7B4)),
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

  Widget _buildTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 2, 22, 10),
      child: Row(
        children: [
          for (var i = 0; i < cheatGames.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: _buildTab(i)),
          ],
        ],
      ),
    );
  }

  Widget _buildTab(int index) {
    final game = cheatGames[index];
    final active = index == _gameIndex;
    return GestureDetector(
      onTap: () {
        if (index == _gameIndex) return;
        HapticFeedback.selectionClick();
        setState(() => _gameIndex = index);
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          gradient: active
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    game.accent.withValues(alpha: 0.20),
                    game.accent.withValues(alpha: 0.07),
                  ],
                )
              : null,
          color: active ? null : Colors.white.withValues(alpha: 0.04),
          border: Border.all(
            color: active
                ? game.accent.withValues(alpha: 0.65)
                : Colors.white.withValues(alpha: 0.07),
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: game.accent.withValues(alpha: 0.25),
                    blurRadius: 18,
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            Text(
              game.name,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
                color: game.accent,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${game.codeCount} CODES',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
                color: game.accent.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusLine() {
    final (icon, color) = switch (_statusKind) {
      _StatusKind.idle => (Icons.touch_app_outlined, const Color(0xFF8FA3B0)),
      _StatusKind.typing => (Icons.keyboard, _game.accent),
      _StatusKind.done => (Icons.check_circle, const Color(0xFF2EE66B)),
      _StatusKind.error => (Icons.error_outline, const Color(0xFFF87171)),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              _status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
          if (_busy)
            SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _game.accent,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildList(CheatGame game) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 2, 18, 14),
      children: [
        for (final category in game.categories) ...[
          _buildCategoryHeader(game, category.name),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 9,
              crossAxisSpacing: 10,
              childAspectRatio: 3.3,
            ),
            itemCount: category.cheats.length,
            itemBuilder: (context, i) =>
                _buildCheatCard(game, category.cheats[i]),
          ),
          const SizedBox(height: 6),
        ],
      ],
    );
  }

  Widget _buildCategoryHeader(CheatGame game, String name) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 7),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 14,
            decoration: BoxDecoration(
              color: game.accent,
              borderRadius: BorderRadius.circular(2),
              boxShadow: [
                BoxShadow(
                  color: game.accent.withValues(alpha: 0.7),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            name.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.5,
              color: game.accent,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    game.accent.withValues(alpha: 0.35),
                    game.accent.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheatCard(CheatGame game, Cheat cheat) {
    final busy = _busy;
    final isTypingThis = _typingCode == cheat.code;
    return Opacity(
      opacity: busy && !isTypingThis ? 0.45 : 1.0,
      child: GestureDetector(
        onTap: busy ? null : () => _onCheatTap(cheat),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: isTypingThis ? 0.10 : 0.055),
                Colors.white.withValues(alpha: 0.02),
              ],
            ),
            border: Border.all(
              color: isTypingThis
                  ? game.accent.withValues(alpha: 0.8)
                  : Colors.white.withValues(alpha: 0.09),
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
              if (isTypingThis)
                BoxShadow(
                  color: game.accent.withValues(alpha: 0.30),
                  blurRadius: 16,
                ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                cheat.code,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                cheat.hint,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  height: 1.15,
                  color: Color(0xFFA9BCC7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(CheatGame game) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 14,
            color: game.accent.withValues(alpha: 0.8),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              game.footerNote!,
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.3,
                color: Color(0xFF8FA3B0),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _StatusKind { idle, typing, done, error }
