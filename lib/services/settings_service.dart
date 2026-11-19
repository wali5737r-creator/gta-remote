import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/game_profile.dart';

/// Steering ki sensitivity — ungli ki harkat par wheel kitna ghume.
enum SteeringSensitivity {
  low(0.7, 'Low'),
  medium(1.0, 'Medium'),
  high(1.4, 'High');

  const SteeringSensitivity(this.factor, this.label);

  /// Ungli ke angle par lagne wala multiplier.
  final double factor;
  final String label;

  static SteeringSensitivity byName(String? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return medium;
  }
}

/// App ki tamam settings — phone par save hoti hain (FR-26).
///
/// Singleton hai; UI [ChangeNotifier] ko sun kar khud update hoti hai.
class SettingsService extends ChangeNotifier {
  SettingsService._();

  static final SettingsService instance = SettingsService._();

  static const _keyProfile = 'game_profile_id';
  static const _keySteeringRange = 'steering_range_deg';
  static const _keyDeadZone = 'steering_dead_zone_deg';
  static const _keySensitivity = 'steering_sensitivity';
  static const _keyFlipControls = 'flip_controls';
  static const _keyDeviceAddress = 'last_device_address';
  static const _keyDeviceName = 'last_device_name';

  bool _loaded = false;
  bool get loaded => _loaded;

  GameProfile _profile = GameProfile.gtaV;
  GameProfile get profile => _profile;

  /// Wheel kitna ghum sakta hai: 90 ya 135 degrees (aik side).
  double _steeringRangeDeg = 90;
  double get steeringRangeDeg => _steeringRangeDeg;

  /// Centre ke aas paas itne degrees me koi key nahi jati (default 7).
  double _deadZoneDeg = 7;
  double get deadZoneDeg => _deadZoneDeg;

  SteeringSensitivity _sensitivity = SteeringSensitivity.medium;
  SteeringSensitivity get sensitivity => _sensitivity;

  /// True ho to wheel right side, pedals left side (left-handed).
  bool _flipControls = false;
  bool get flipControls => _flipControls;

  String? _lastDeviceAddress;
  String? get lastDeviceAddress => _lastDeviceAddress;

  String? _lastDeviceName;
  String? get lastDeviceName => _lastDeviceName;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _profile = GameProfile.byId(prefs.getString(_keyProfile));
    _steeringRangeDeg = prefs.getDouble(_keySteeringRange) ?? 90;
    _deadZoneDeg = prefs.getDouble(_keyDeadZone) ?? 7;
    _sensitivity =
        SteeringSensitivity.byName(prefs.getString(_keySensitivity));
    _flipControls = prefs.getBool(_keyFlipControls) ?? false;
    _lastDeviceAddress = prefs.getString(_keyDeviceAddress);
    _lastDeviceName = prefs.getString(_keyDeviceName);
    _loaded = true;
    notifyListeners();
  }

  Future<void> setProfile(GameProfile profile) async {
    _profile = profile;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyProfile, profile.id);
  }

  Future<void> setSteeringRangeDeg(double value) async {
    _steeringRangeDeg = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keySteeringRange, value);
  }

  Future<void> setDeadZoneDeg(double value) async {
    _deadZoneDeg = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyDeadZone, value);
  }

  Future<void> setSensitivity(SteeringSensitivity value) async {
    _sensitivity = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySensitivity, value.name);
  }

  Future<void> setFlipControls(bool value) async {
    _flipControls = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyFlipControls, value);
  }

  Future<void> setLastDevice(String address, String name) async {
    _lastDeviceAddress = address;
    _lastDeviceName = name;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDeviceAddress, address);
    await prefs.setString(_keyDeviceName, name);
  }
}
