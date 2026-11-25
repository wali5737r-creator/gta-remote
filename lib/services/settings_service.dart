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

/// Driving me steering ka tareeqa (v4 — chaar modes; v6 — paanch;
/// v7 — chhe).
///
/// v2/v3 me ye sirf aik bool tha (STEERING ya TILT); v4 me CONTROLLER
/// (analog stick) aur ARROWS (tap wale steer buttons) bhi jud gaye.
/// v6 me FLY jud gaya — jahaz/helicopter ke liye aik handle
/// (left/right = mor A/D, up/down = naak ArrowDown/ArrowUp).
/// v7 me CRICKET jud gaya — ye steering ka tareeqa NAHI hai: ye
/// EA Sports Cricket 07 ke liye poori alag stage hai (batting ke
/// swipe shots + bowling ka marker drag), jo driving stage ki
/// jagah aa jati hai jab active ho.
/// Purane modes ki behaviour bilkul nahi badli — ye sirf pasand ki
/// pehchan hai, controller screen is ke hisab se layer chunti hai.
/// [byName] na-maloom naam par hamesha STEERING deta hai, is liye
/// purani save values (ya koi ajnabi value) crash nahi karti.
enum DriveMode {
  steering('STEERING'),
  tilt('TILT'),
  controller('CONTROLLER'),
  arrows('ARROWS'),
  fly('FLY'),
  cricket('CRICKET');

  const DriveMode(this.label);

  /// Top bar ke switch par dikhne wala naam.
  final String label;

  static DriveMode byName(String? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return steering;
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
  static const _keyTiltSteering = 'tilt_steering';
  static const _keyDriveMode = 'drive_mode';
  static const _keyCricketCameraFlip = 'cricket_camera_flip';
  static const _keyAutoAim = 'auto_aim';
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

  /// Driving me steering ka tareeqa (v4): touch wheel (STEERING),
  /// phone hilana (TILT), analog stick (CONTROLLER) ya tap wale
  /// steer buttons (ARROWS). Controller ke switch se badalta hai
  /// aur agli dafa ke liye yaad rehta hai.
  DriveMode _driveMode = DriveMode.steering;
  DriveMode get driveMode => _driveMode;

  /// CRICKET mode ki CAMERA ULTA pasand (v7): true ho to batting
  /// swipe ki dono simtain ulta jati hain — un players ke liye
  /// jinhon ne Cricket 07 ke andar camera flip kar rakha ho.
  /// Sirf batting swipes par lagti hai; bowling marker par nahi.
  bool _cricketCameraFlip = false;
  bool get cricketCameraFlip => _cricketCameraFlip;

  /// ATTACK ke saath auto-aim (v5.4): true ho to ATTACK dabate hi
  /// right (aim) bit bhi lagta hai — larai me aik button kaafi hai.
  /// False ho to ATTACK sirf fire hai (pehle jaisa). Default ON —
  /// Muhammad ne yehi feature manga tha; band karne ke liye top
  /// bar me AUTO-AIM pill hai.
  bool _autoAim = true;
  bool get autoAim => _autoAim;

  /// Sirf TILT wali purani haalat — v2/v3 ki pasand (tilt_steering
  /// bool) se migration aur tilt wale checks ke liye.
  bool get tiltSteering => _driveMode == DriveMode.tilt;

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
    // Drive mode: nayi key pehle dekho; na mile to v2/v3 ki bool
    // wali pasand (tilt_steering) se migration — TILT chuna tha to
    // TILT hi milega, warna STEERING.
    final savedMode = prefs.getString(_keyDriveMode);
    if (savedMode != null) {
      _driveMode = DriveMode.byName(savedMode);
    } else {
      _driveMode = (prefs.getBool(_keyTiltSteering) ?? false)
          ? DriveMode.tilt
          : DriveMode.steering;
    }
    _lastDeviceAddress = prefs.getString(_keyDeviceAddress);
    _lastDeviceName = prefs.getString(_keyDeviceName);
    _cricketCameraFlip = prefs.getBool(_keyCricketCameraFlip) ?? false;
    _autoAim = prefs.getBool(_keyAutoAim) ?? true;
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

  Future<void> setDriveMode(DriveMode value) async {
    _driveMode = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDriveMode, value.name);
    // Purani bool key bhi saath rakho — koi purana build wapas
    // lagaye to us ki pasand na khoye.
    await prefs.setBool(_keyTiltSteering, value == DriveMode.tilt);
  }

  Future<void> setCricketCameraFlip(bool value) async {
    _cricketCameraFlip = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyCricketCameraFlip, value);
  }

  /// Auto-aim save karo. Notify NAHI karta — ye toggle larai ke
  /// beech me bhi dab sakta hai, aur notify karte hi controller
  /// ka _onSettingsChanged saari keys (daba hua ATTACK bhi)
  /// chhor deta. Screen toggle handler me apni setState se
  /// dobara banti hai, is liye notify ki zaroorat nahi.
  Future<void> setAutoAim(bool value) async {
    _autoAim = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoAim, value);
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
