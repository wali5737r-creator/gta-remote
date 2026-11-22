import 'dart:async';

import 'package:flutter/services.dart';

import '../models/game_key.dart';

/// Laptop se Bluetooth connection ki haalat.
enum HidConnection { disconnected, connecting, connected, disconnecting }

/// Kotlin side se aane wali taaza tareen haalat (FR-6: haqiqat callbacks se
/// aati hai, andazay se nahi).
class HidState {
  const HidState({
    this.registered = false,
    this.connection = HidConnection.disconnected,
    this.deviceName,
    this.deviceAddress,
    this.error,
  });

  /// App Bluetooth HID keyboard ke tor par registered hai ya nahi.
  final bool registered;

  final HidConnection connection;

  /// Connected/connecting laptop ka naam aur address.
  final String? deviceName;
  final String? deviceAddress;

  /// Aakhri plain-language error (agar koi ho).
  final String? error;

  bool get isConnected => connection == HidConnection.connected;

  HidState copyWith({
    bool? registered,
    HidConnection? connection,
    String? deviceName,
    String? deviceAddress,
    String? error,
    bool clearError = false,
    bool clearDevice = false,
  }) {
    return HidState(
      registered: registered ?? this.registered,
      connection: connection ?? this.connection,
      deviceName: clearDevice ? null : (deviceName ?? this.deviceName),
      deviceAddress:
          clearDevice ? null : (deviceAddress ?? this.deviceAddress),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Pehle se paired (bonded) Bluetooth device.
class BondedDevice {
  const BondedDevice({
    required this.name,
    required this.address,
    this.majorClass = 0,
  });

  final String name;
  final String address;

  /// Bluetooth major device class (native side se): computer = 0x100,
  /// phone = 0x200, audio/video (earbuds waghera) = 0x400, 0 = maloom nahi.
  final int majorClass;

  bool get isComputer => majorClass == 0x100;
  bool get isPhone => majorClass == 0x200;
  bool get isAudio => majorClass == 0x400;

  factory BondedDevice.fromMap(Map<dynamic, dynamic> map) {
    return BondedDevice(
      name: (map['name'] as String?) ?? 'Unknown device',
      address: (map['address'] as String?) ?? '',
      majorClass: (map['majorClass'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Bluetooth HID keyboard + mouse ka Dart darwaza.
///
/// Kotlin side (`HidKeyboardManager`) se MethodChannel par commands aur
/// EventChannel par haqiqi connection state milti hai. Ye class pressed keys
/// ka aik set rakhti hai; har tabdeeli par poora 8-byte snapshot report
/// bhejti hai — is liye koi key atak (stuck) nahi sakti.
///
/// v3: device ab combo hai (keyboard + mouse). Mouse camera ghumane,
/// swimming ki simt aur menu pointer ke liye hai; us ka left button
/// ATTACK hai. Mouse buttons bhi state ki tarah rakhe jate hain aur
/// har safety path par zero hote hain — click bhi atak nahi sakta.
class HidService {
  HidService._() {
    _initEventStream();
  }

  static final HidService instance = HidService._();

  static const MethodChannel _methods = MethodChannel('gta_remote/hid');
  static const EventChannel _events = EventChannel('gta_remote/hid_events');

  /// HID mouse ke button bits (report ID 2, byte 0).
  static const int mouseButtonLeft = 0x01;
  static const int mouseButtonRight = 0x02;
  static const int mouseButtonMiddle = 0x04;

  final StreamController<HidState> _stateController =
      StreamController<HidState>.broadcast();
  HidState _current = const HidState();

  Stream<HidState> get states => _stateController.stream;
  HidState get current => _current;

  Set<GameKey> _pressedKeys = {};
  String _lastSentSignature = '';

  /// Is waqt dabaye hue mouse buttons (bitmask) — state ki tarah
  /// rakha jata hai taake harkat wali reports ke saath bhi sahi
  /// button haalat jaye, aur release hamesha pakka ho.
  int _mouseButtons = 0;

  void _initEventStream() {
    _events.receiveBroadcastStream().listen(
      (dynamic raw) {
        if (raw is! Map) return;
        final event = raw['event'] as String?;
        switch (event) {
          case 'appStatus':
            _update(_current.copyWith(
              registered: raw['registered'] as bool? ?? false,
              clearError: true,
            ));
            break;
          case 'connection':
            final stateName = raw['state'] as String? ?? 'disconnected';
            final connection = HidConnection.values.firstWhere(
              (value) => value.name == stateName,
              orElse: () => HidConnection.disconnected,
            );
            if (connection == HidConnection.disconnected) {
              // Link kat gaya to phone ki taraf se bhi saari keys saaf.
              // Mouse buttons bhi zero samjho — link katte hi laptop
              // ki taraf se bhi button chhut jata hai; hamari state
              // us se milti rehni chahiye, warna reconnect par purana
              // button "daba hua" samjha jayega.
              _pressedKeys = {};
              _lastSentSignature = '';
              _mouseButtons = 0;
              _update(_current.copyWith(
                connection: connection,
                clearDevice: true,
              ));
            } else {
              _update(_current.copyWith(
                connection: connection,
                deviceName: raw['name'] as String?,
                deviceAddress: raw['address'] as String?,
                clearError: true,
              ));
              if (connection == HidConnection.connected) {
                // FR-28: (dobara) connect hote hi maujooda — drop ke
                // baad khali — state ki aik report bhejo, taake game
                // saaf haalat se shuru ho aur koi purani key PC par
                // atki na rahe.
                _sendCurrentReport();
              }
            }
            break;
          case 'error':
            _update(_current.copyWith(
              error: raw['message'] as String? ?? 'Something went wrong.',
            ));
            break;
        }
      },
      onError: (Object error) {
        _update(
            _current.copyWith(error: 'Could not read the Bluetooth state.'));
      },
    );
  }

  void _update(HidState state) {
    _current = state;
    _stateController.add(state);
  }

  // ---------------------------------------------------------------------------
  // Permissions / Bluetooth on-off
  // ---------------------------------------------------------------------------

  Future<bool> hasPermissions() async {
    final result = await _methods.invokeMethod<bool>('hasPermissions');
    return result ?? false;
  }

  /// System permission dialog dikhata hai. Jawab: connect permission mila?
  Future<bool> requestPermissions() async {
    final result =
        await _methods.invokeMethod<Map<dynamic, dynamic>>(
      'requestPermissions',
    );
    return result?['connect'] as bool? ?? false;
  }

  Future<bool> isBluetoothEnabled() async {
    final result = await _methods.invokeMethod<bool>('isBluetoothEnabled');
    return result ?? false;
  }

  /// Bluetooth on karne ka system dialog. True = user ne on kar diya.
  Future<bool> requestEnableBluetooth() async {
    final result =
        await _methods.invokeMethod<bool>('requestEnableBluetooth');
    return result ?? false;
  }

  Future<void> openBluetoothSettings() async {
    await _methods.invokeMethod<void>('openBluetoothSettings');
  }

  /// App ki apni Settings screen (permission hamesha ke liye band ho to).
  Future<void> openAppSettings() async {
    await _methods.invokeMethod<void>('openAppSettings');
  }

  /// Phone ko itni dair ke liye discoverable banao (pehli pairing ke liye).
  Future<bool> makeDiscoverable() async {
    final result = await _methods.invokeMethod<bool>('makeDiscoverable');
    return result ?? false;
  }

  // ---------------------------------------------------------------------------
  // Devices / registration / connection
  // ---------------------------------------------------------------------------

  Future<List<BondedDevice>> getBondedDevices() async {
    final result = await _methods
        .invokeMethod<List<dynamic>>('getBondedDevices');
    if (result == null) return const [];
    return result
        .whereType<Map<dynamic, dynamic>>()
        .map(BondedDevice.fromMap)
        .where((device) => device.address.isNotEmpty)
        .toList();
  }

  /// HID keyboard ke tor par register karo. Future tab complete hota hai
  /// jab Android ka haqiqi callback registered=true keh de.
  Future<bool> registerApp() async {
    final result = await _methods.invokeMethod<bool>('registerApp');
    return result ?? false;
  }

  Future<void> unregisterApp() async {
    await _methods.invokeMethod<bool>('unregisterApp');
  }

  Future<bool> connect(String address) async {
    final result = await _methods.invokeMethod<bool>(
      'connect',
      <String, dynamic>{'address': address},
    );
    return result ?? false;
  }

  Future<void> disconnect() async {
    await _methods.invokeMethod<bool>('disconnect');
  }

  /// Register → connect ka poora silsila (FR-5/FR-7).
  ///
  /// Kamyabi par null, warna plain-language error message return hota hai.
  /// [onStatus] ko har marhalay ka text milta hai (UI progress ke liye).
  Future<String?> connectSequence(
    String address, {
    void Function(String status)? onStatus,
  }) async {
    try {
      if (!await isBluetoothEnabled()) {
        onStatus?.call('Turning Bluetooth on…');
        final enabled = await requestEnableBluetooth();
        if (!enabled) {
          return 'Bluetooth is off. Turn Bluetooth on in your phone settings, then try again.';
        }
      }

      if (!_current.registered) {
        onStatus?.call('Registering…');
        final registered = await registerApp()
            .timeout(const Duration(seconds: 10), onTimeout: () => false);
        if (!registered) {
          return 'Registration failed. If another remote or keyboard app is open, close it and try again.';
        }
      }

      if (_current.isConnected &&
          _current.deviceAddress == address) {
        return null; // pehle se isi laptop se connected hai
      }

      onStatus?.call('Connecting…');
      final accepted = await connect(address);
      if (!accepted) {
        return 'Could not start connecting. Check that Bluetooth is on on your laptop.';
      }

      // Haqiqi "connected" callback ka intezar.
      final connected = await _waitForConnection(address);
      if (!connected) {
        return _current.error ??
            'Could not connect. In your laptop\'s Bluetooth settings, remove this phone ("Remove device"), then keep the app open, pair again and tap CONNECT.';
      }
      return null;
    } on PlatformException catch (error) {
      return error.message ?? 'Something went wrong with Bluetooth.';
    }
  }

  /// [connect] ke baad asal "connected" callback ka intezar.
  ///
  /// Connected event aye to true; darmiyan me link kat jaye to **foran**
  /// false (user ko poore 20 second latka nahi rakhte); 20 second guzar
  /// jayen to maujooda haalat hi jawab hai. Pehle se connected ho to
  /// foran true — broadcast stream ka purana event dobara nahi aata,
  /// is liye maujooda state pehle check hoti hai.
  Future<bool> _waitForConnection(String address) async {
    if (_current.isConnected && _current.deviceAddress == address) {
      return true;
    }
    final completer = Completer<bool>();
    final subscription = states.listen((state) {
      if (completer.isCompleted) return;
      if (state.isConnected) {
        completer.complete(true);
      } else if (state.connection == HidConnection.disconnected) {
        completer.complete(false);
      }
    });
    try {
      return await completer.future.timeout(
        const Duration(seconds: 20),
        onTimeout: () => _current.isConnected,
      );
    } finally {
      await subscription.cancel();
    }
  }

  /// Disconnect ka saaf silsila (FR-29): pehle saari keys chhoro,
  /// phir disconnect, phir unregister.
  Future<void> disconnectSequence() async {
    releaseAllKeys();
    try {
      await disconnect();
      await unregisterApp();
    } on PlatformException {
      // App band ho rahi ho to native side khud saaf kar dega.
    }
  }

  // ---------------------------------------------------------------------------
  // Key reports
  // ---------------------------------------------------------------------------

  /// Pressed keys ka naya set do — poora snapshot report jata hai.
  void setPressedKeys(Set<GameKey> keys) {
    _pressedKeys = Set<GameKey>.of(keys);
    _sendCurrentReport();
  }

  /// Saari keys aik saath chhor do (safety — FR-28/FR-29).
  /// Mouse buttons bhi saath hi chhut-te hain — is aik function se
  /// har safety path (disconnect, pause, mode switch…) dono taraf
  /// saaf ho jata hai.
  void releaseAllKeys() {
    _pressedKeys = {};
    _sendCurrentReport();
    setMouseButtons(0);
  }

  // ---------------------------------------------------------------------------
  // Cheat typer (v5)
  // ---------------------------------------------------------------------------

  bool _isTypingCheat = false;

  /// Koi cheat code is waqt type ho raha hai ya nahi — CHEATS
  /// screen is se apne buttons band/chaalu rakhti hai.
  bool get isTypingCheat => _isTypingCheat;

  /// Aik raw keyboard report seedha channel par — snapshot wali
  /// dedup ([_lastSentSignature]) ko chhuta nahi. [keycode] null
  /// ho to khali (sab keys up) report jata hai.
  Future<void> _sendRawKeyboardReport(int? keycode) async {
    try {
      await _methods.invokeMethod<bool>('sendReport', <String, dynamic>{
        'modifier': 0,
        'keycodes': keycode == null ? <int>[] : <int>[keycode],
      });
    } on PlatformException {
      // Link kat gaya ho to agli check (isConnected) type rok degi.
    }
  }

  /// Cheat [code] ko asal keyboard ki tarah harf-ba-harf type karo
  /// (v5, CHEATS screen). GTA ke cheat systems type kiye hue lafz
  /// ko pehchante hain — har harf aik saaf down/up press hai
  /// (55 ms down, 40 ms gap), bilkul ungli se type karne jaisa.
  ///
  /// [useConsole] true (GTA V): pehle grave key (`) se console
  /// kholo, 300 ms ruko, code type karo, aakhir me Enter.
  /// SA / VC: seedha type — koi console nahi.
  ///
  /// Shuru me [releaseAllKeys] hota hai taake koi lagi hui key
  /// (masalan RACE) code ke harfon se na mil jaye. Aakhir me —
  /// kamyabi ho ya darmiyan me link kat jaye — typing flag saaf,
  /// dedup signature reset aur maujooda (khali) snapshot dobara
  /// jata hai, taake aam key reports phir se bilkul saaf chalein.
  ///
  /// Return: true = poora code type ho gaya; false = connected
  /// nahi tha, pehle se typing chal rahi thi, ya link darmiyan
  /// me kat gaya (code aadha gaya hoga — game me asar nahi hoga,
  /// kyunke cheat poora lafz mangta hai).
  Future<bool> typeCheatCode(
    String code, {
    required bool useConsole,
  }) async {
    if (!_current.isConnected || _isTypingCheat) return false;
    _isTypingCheat = true;
    var completed = false;
    try {
      releaseAllKeys();
      if (useConsole) {
        // GTA V ka console grave key (0x35) se khulta hai.
        await _sendRawKeyboardReport(0x35);
        await Future<void>.delayed(const Duration(milliseconds: 60));
        await _sendRawKeyboardReport(null);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      for (final unit in code.toUpperCase().codeUnits) {
        if (!_current.isConnected) return false;
        if (unit < 0x41 || unit > 0x5A) continue; // sirf A–Z
        // HID keycode: A = 0x04 … Z = 0x1D.
        await _sendRawKeyboardReport(0x04 + (unit - 0x41));
        await Future<void>.delayed(const Duration(milliseconds: 55));
        await _sendRawKeyboardReport(null);
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      if (useConsole) {
        if (!_current.isConnected) return false;
        await _sendRawKeyboardReport(0x28); // Enter
        await Future<void>.delayed(const Duration(milliseconds: 60));
        await _sendRawKeyboardReport(null);
      }
      completed = true;
      return true;
    } finally {
      _isTypingCheat = false;
      // Raw reports ne dedup ko nahi chhua — phir bhi signature
      // reset karke maujooda snapshot dobara bhejo, taake service
      // ki "aakhri bheji haalat" hamesha sach ho.
      _lastSentSignature = '';
      _sendCurrentReport();
      if (!completed) {
        // Darmiyan me kata to khali report pakki jaye (upar wali
        // _sendCurrentReport dedup se ruk sakti hai agar snapshot
        // pehle se khali tha) — koi harf PC par daba na reh jaye.
        await _sendRawKeyboardReport(null);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Mouse reports (v3)
  // ---------------------------------------------------------------------------

  /// Mouse ko harkat do (relative) — camera pad yahi bulata hai.
  /// Har call aik report hai kyunke dx/dy "harkat" hai, haalat nahi;
  /// dabaye hue buttons maujooda state se saath jate hain.
  void moveMouse(int dx, int dy) {
    if (dx == 0 && dy == 0) return;
    _sendMouseReport(dx, dy, _mouseButtons, 0);
  }

  /// Mouse buttons ki haalat badlo (masalan ATTACK dabana/chhorna).
  /// Haalat na badli ho to report nahi jata.
  void setMouseButtons(int buttons) {
    final masked = buttons & 0x07;
    if (masked == _mouseButtons) return;
    _mouseButtons = masked;
    _sendMouseReport(0, 0, masked, 0);
  }

  /// Aik mouse button ko on/off karo, baqi buttons ki haalat
  /// barqarar rakh kar (v4: ATTACK = left aur AIM = right aik
  /// saath bhi dab sakte hain — aik ka chhutna dusre ko nahi
  /// kaat-ta).
  void setMouseButton(int bit, bool down) {
    setMouseButtons(down ? (_mouseButtons | bit) : (_mouseButtons & ~bit));
  }

  /// Mouse wheel ka aik tick (v4: weapon switch). Wheel harkat
  /// hai, haalat nahi — har call aik report jata hai, dabaye hue
  /// buttons maujooda state ke saath.
  void wheelTick(int direction) {
    if (direction == 0) return;
    _sendMouseReport(0, 0, _mouseButtons, direction.sign);
  }

  void _sendMouseReport(int dx, int dy, int buttons, int wheel) {
    unawaited(
      _methods.invokeMethod<bool>('sendMouse', <String, dynamic>{
        'dx': dx,
        'dy': dy,
        'buttons': buttons,
        'wheel': wheel,
      }).catchError((Object _) => false),
    );
  }

  void _sendCurrentReport() {
    var modifier = 0;
    final keycodes = <int>[];
    for (final key in hidKeyOrder) {
      if (_pressedKeys.contains(key) && key.keycode != null) {
        keycodes.add(key.keycode!);
      }
    }
    if (_pressedKeys.contains(GameKey.shift)) {
      modifier |= GameKey.shiftModifierBit;
    }
    // Boot protocol: zyada se zyada 6 keycodes.
    final trimmed =
        keycodes.length > 6 ? keycodes.sublist(0, 6) : keycodes;
    final signature = '$modifier:${trimmed.join(',')}';
    if (signature == _lastSentSignature) return;
    _lastSentSignature = signature;
    unawaited(
      _methods.invokeMethod<bool>('sendReport', <String, dynamic>{
        'modifier': modifier,
        'keycodes': trimmed,
      }).catchError((Object _) => false),
    );
  }
}
