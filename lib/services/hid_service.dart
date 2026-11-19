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
  const BondedDevice({required this.name, required this.address});

  final String name;
  final String address;

  factory BondedDevice.fromMap(Map<dynamic, dynamic> map) {
    return BondedDevice(
      name: (map['name'] as String?) ?? 'Unknown device',
      address: (map['address'] as String?) ?? '',
    );
  }
}

/// Bluetooth HID keyboard ka Dart darwaza.
///
/// Kotlin side (`HidKeyboardManager`) se MethodChannel par commands aur
/// EventChannel par haqiqi connection state milti hai. Ye class pressed keys
/// ka aik set rakhti hai; har tabdeeli par poora 8-byte snapshot report
/// bhejti hai — is liye koi key atak (stuck) nahi sakti.
class HidService {
  HidService._() {
    _initEventStream();
  }

  static final HidService instance = HidService._();

  static const MethodChannel _methods = MethodChannel('gta_remote/hid');
  static const EventChannel _events = EventChannel('gta_remote/hid_events');

  final StreamController<HidState> _stateController =
      StreamController<HidState>.broadcast();
  HidState _current = const HidState();

  Stream<HidState> get states => _stateController.stream;
  HidState get current => _current;

  Set<GameKey> _pressedKeys = {};
  String _lastSentSignature = '';

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
              _pressedKeys = {};
              _lastSentSignature = '';
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
            }
            break;
          case 'error':
            _update(_current.copyWith(
              error: raw['message'] as String? ?? 'Kuch ghalat ho gaya.',
            ));
            break;
        }
      },
      onError: (Object error) {
        _update(_current.copyWith(error: 'Bluetooth state nahi mil saki.'));
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
        onStatus?.call('Bluetooth on kiya ja raha hai…');
        final enabled = await requestEnableBluetooth();
        if (!enabled) {
          return 'Bluetooth band hai. Phone ki settings se Bluetooth on karke dobara koshish karo.';
        }
      }

      if (!_current.registered) {
        onStatus?.call('Register ho raha hai…');
        final registered = await registerApp()
            .timeout(const Duration(seconds: 10), onTimeout: () => false);
        if (!registered) {
          return 'Registration nahi ho saki. Agar koi aur remote/keyboard app khuli hai to use band karke dobara koshish karo.';
        }
      }

      if (_current.isConnected &&
          _current.deviceAddress == address) {
        return null; // pehle se isi laptop se connected hai
      }

      onStatus?.call('Connect ho raha hai…');
      final accepted = await connect(address);
      if (!accepted) {
        return 'Connect shuru nahi ho saka. Laptop ki Bluetooth on hai, ye check karo.';
      }

      // Haqiqi "connected" callback ka intezar.
      final connected = await states
          .firstWhere((state) => state.isConnected)
          .timeout(const Duration(seconds: 20), onTimeout: () => _current)
          .then((state) => state.isConnected);
      if (!connected) {
        return _current.error ??
            'Connect nahi ho saka. Laptop par is phone ko pair kiya hua hai, ye check karo — warna neeche wali pairing guide se pehle pair karo.';
      }
      return null;
    } on PlatformException catch (error) {
      return error.message ?? 'Bluetooth me kuch ghalat ho gaya.';
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
  void releaseAllKeys() {
    _pressedKeys = {};
    _sendCurrentReport();
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
