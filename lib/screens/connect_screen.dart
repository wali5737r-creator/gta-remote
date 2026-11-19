import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/game_profile.dart';
import '../services/hid_service.dart';
import '../services/settings_service.dart';
import '../widgets/premium_background.dart';
import 'controller_screen.dart';
import 'settings_screen.dart';

/// S1 — Connect screen (FR-1…FR-7).
///
/// Game pehle select hota hai (keys usi par munhasir hain), phir paired
/// laptop, phir bara CONNECT button. Pehli dafa pairing ki guide hamesha
/// neeche mojood hai.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen>
    with WidgetsBindingObserver {
  final HidService _hid = HidService.instance;
  final SettingsService _settings = SettingsService.instance;

  bool? _permissionGranted;
  List<BondedDevice> _devices = const [];
  String? _selectedAddress;

  bool _busy = false;
  String _statusText = 'Not connected';
  String? _errorText;

  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _settings.addListener(_onSettingsChanged);
    _refreshDevices();
    // Pairing laptop par hoti hai aur phone app khuli rehti hai — koi
    // "resume" event nahi aata. Is liye har chand second me khamoshi se
    // dobara dekho, taake pairing mukammal hote hi laptop khud list me
    // aa jaye (list na badli ho to UI update nahi hota).
    _autoRefreshTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _refreshDevices(),
    );
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Settings waghera se wapas aane par permission + list dobara dekho
    // (masalan Settings se permission allow karke wapas aana).
    if (state == AppLifecycleState.resumed) {
      _refreshDevices();
    }
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshDevices() async {
    if (_busy) return; // Connect chal raha ho to darmiyan me na chhero.
    try {
      final granted = await _hid.hasPermissions();
      if (!mounted) return;
      if (granted != _permissionGranted) {
        setState(() => _permissionGranted = granted);
      }
      if (!granted) return;
      // Keyboard PEHLE se register kar lo: laptop ko pairing ke waqt hi
      // keyboard service nazar aani chahiye — agar pairing registration se
      // pehle ho jaye to laptop keyboard dhoond hi nahi pata aur baad me
      // HID connect fail ho jata hai.
      unawaited(_hid.registerApp().catchError((Object _) => false));
      final devices = await _hid.getBondedDevices();
      if (!mounted) return;
      final selectionValid = _selectedAddress != null &&
          devices.any((device) => device.address == _selectedAddress);
      if (_sameDevices(_devices, devices) && selectionValid) {
        return; // Kuch nahi badla — flicker na karo.
      }
      setState(() {
        _devices = devices;
        if (!selectionValid) {
          // Aakhri istemal shuda laptop pehle se select rakho. User ki
          // apni selection kabhi khud nahi badalte.
          final last = _settings.lastDeviceAddress;
          if (last != null &&
              devices.any((device) => device.address == last)) {
            _selectedAddress = last;
          } else if (devices.length == 1) {
            _selectedAddress = devices.first.address;
          } else {
            _selectedAddress = null;
          }
        }
      });
    } catch (_) {
      // Platform side se jawab na aye to screen khamosh na rahe.
      if (!mounted) return;
      setState(() {
        _errorText =
            'Bluetooth ki haalat nahi parhi ja saki. Thodi dair baad refresh (upar wala gol teer) dabao.';
      });
    }
  }

  bool _sameDevices(List<BondedDevice> a, List<BondedDevice> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].address != b[i].address || a[i].name != b[i].name) {
        return false;
      }
    }
    return true;
  }

  /// FR-2: system dialog se PEHLE plain-language explanation.
  Future<bool> _ensurePermissions() async {
    if (await _hid.hasPermissions()) {
      if (mounted) setState(() => _permissionGranted = true);
      return true;
    }
    if (!mounted) return false;
    final agreed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Bluetooth permission'),
        content: const Text(
          'GTA Remote ko Bluetooth permission chahiye taake ye tumhare '
          'laptop se connect ho sakay.\n\n'
          'Koi internet use nahi hota, aur koi data kahin nahi jata.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Samajh gaya — Allow karo'),
          ),
        ],
      ),
    );
    if (agreed != true) return false;
    final granted = await _hid.requestPermissions();
    if (!mounted) return granted;
    setState(() => _permissionGranted = granted);
    if (granted) {
      _refreshDevices();
    } else {
      // System dialog aye baghair inkaar = permission pehle se hamesha
      // ke liye band hai ("dobara na pocho"). Ab Settings wala rasta hi
      // bacha hai — warna "Allow Bluetooth" button hamesha gol gol
      // ghumta rahega.
      await _showPermissionSettingsDialog();
    }
    return granted;
  }

  /// Permission hamesha ke liye band ho to Settings ka rasta dikhao.
  Future<void> _showPermissionSettingsDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Permission Settings se do'),
        content: const Text(
          'Bluetooth permission pehle se band hai, is liye system dialog '
          'nahi aya.\n\n'
          'Settings kholo → Permissions → Nearby devices → Allow karo. '
          'Phir wapas aakar dobara koshish karo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Baad me'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              try {
                await _hid.openAppSettings();
              } on PlatformException {
                // Settings na khule to upar wale text me rasta likha hai.
              }
            },
            child: const Text('Settings kholo'),
          ),
        ],
      ),
    );
  }

  Future<void> _onConnectPressed() async {
    final address = _selectedAddress;
    if (address == null || _busy) return;
    // Busy FORAN lagao — permission ke intezar ke darmiyan tez
    // double-tap par do connect silsilay aik saath nahi chalte.
    setState(() {
      _busy = true;
      _errorText = null;
      _statusText = 'Taiyari ho rahi hai…';
    });

    if (!await _ensurePermissions()) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _statusText = 'Not connected';
        _errorText =
            'Bluetooth permission ke baghair connect nahi ho sakta. Upar wala "Allow Bluetooth" button dabao.';
      });
      return;
    }

    final device = _devices.firstWhere(
      (item) => item.address == address,
      orElse: () => BondedDevice(name: 'Laptop', address: address),
    );

    final error = await _hid.connectSequence(
      address,
      onStatus: (status) {
        if (mounted) setState(() => _statusText = status);
      },
    );
    if (!mounted) return;
    setState(() => _busy = false);

    if (error != null) {
      setState(() {
        _statusText = 'Not connected';
        _errorText = error;
      });
      return;
    }

    await _settings.setLastDevice(device.address, device.name);
    if (!mounted) return;
    setState(() => _statusText = 'Connected');
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ControllerScreen()),
    );
    if (mounted) {
      setState(() => _statusText = 'Not connected');
      _refreshDevices();
    }
  }

  Future<void> _makeDiscoverable() async {
    if (!await _ensurePermissions()) return;
    // Pehle keyboard register, phir discoverable — isi order se laptop
    // pairing ke waqt keyboard service dhoond sakta hai.
    await _hid.registerApp()
        .timeout(const Duration(seconds: 10), onTimeout: () => false);
    final started = await _hid.makeDiscoverable();
    if (!mounted) return;
    setState(() {
      _statusText = started
          ? 'Phone 5 minute ke liye discoverable hai — ab laptop se pair karo (neeche wale steps). Waqt khatam ho jaye to ye button dobara dabana.'
          : 'Discoverable nahi ho saka. Dobara koshish karo.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PremiumBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  children: [
                    _buildGameSelector(),
                    const SizedBox(height: 22),
                    _buildLaptopSection(),
                    const SizedBox(height: 22),
                    _buildConnectButton(),
                    const SizedBox(height: 14),
                    _buildStatusLine(),
                    const SizedBox(height: 22),
                    _buildPairingGuide(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 6),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GTA REMOTE',
                  style: TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Phone steering wheel — Bluetooth only, no internet',
                  style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: Color(0xFFCBD5E1)),
            tooltip: 'Settings',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SettingsScreen(),
                ),
              );
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
    );
  }

  Widget _buildGameSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Konsi game kheloge?',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 10),
        for (final profile in GameProfile.all) ...[
          _GameCard(
            profile: profile,
            selected: _settings.profile.id == profile.id,
            onTap: () => _settings.setProfile(profile),
          ),
          const SizedBox(height: 9),
        ],
      ],
    );
  }

  Widget _buildLaptopSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Tumhara laptop',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(
                Icons.refresh,
                size: 20,
                color: Color(0xFF94A3B8),
              ),
              tooltip: 'Dobara dekho',
              onPressed: _refreshDevices,
            ),
          ],
        ),
        if (_permissionGranted == false)
          _PermissionCard(onAllow: _ensurePermissions)
        else if (_devices.isEmpty)
          const _InfoCard(
            text:
                'Koi paired laptop nahi mila. Pehle neeche wali guide se laptop ke saath pair karo, phir yahan wapas aao.',
          )
        else
          for (final device in _devices)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: _DeviceCard(
                device: device,
                selected: _selectedAddress == device.address,
                onTap: () =>
                    setState(() => _selectedAddress = device.address),
              ),
            ),
      ],
    );
  }

  Widget _buildConnectButton() {
    final canConnect = _selectedAddress != null && !_busy;
    return SizedBox(
      height: 62,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: canConnect
                ? const [Color(0xFF14B8A6), Color(0xFF0F766E)]
                : const [Color(0xFF334155), Color(0xFF1E293B)],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: canConnect
              ? [
                  BoxShadow(
                    color: const Color(0xFF14B8A6).withValues(alpha: 0.4),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: canConnect ? _onConnectPressed : null,
            child: Center(
              child: _busy
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'CONNECT  ▶',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.5,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusLine() {
    return Column(
      children: [
        Text(
          'Status: $_statusText',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: Color(0xFFCBD5E1)),
        ),
        if (_errorText != null) ...[
          const SizedBox(height: 8),
          Text(
            _errorText!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13.5, color: Color(0xFFF87171)),
          ),
        ],
      ],
    );
  }

  Widget _buildPairingGuide() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF020617).withValues(alpha: 0.55),
        border: Border.all(color: const Color(0xFF1E293B)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pehli dafa? Pair aise karo:',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          const _GuideStep(
            number: 1,
            text:
                'Neeche wala button dabao — phone laptop ko nazar aane lagega.',
          ),
          const _GuideStep(
            number: 2,
            text:
                'Laptop par: Settings → Bluetooth & devices → Add device → Bluetooth.',
          ),
          const _GuideStep(
            number: 3,
            text:
                'Apna phone select karo. Code aye to dono screens par Yes/Connect dabao.',
          ),
          const _GuideStep(
            number: 4,
            text: 'Yahan wapas aakar apna laptop select karo aur CONNECT dabao.',
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _makeDiscoverable,
              icon: const Icon(Icons.bluetooth_searching, size: 19),
              label: const Text('Phone ko discoverable banao'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF2DD4BF),
                side: const BorderSide(color: Color(0xFF0F766E)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({
    required this.profile,
    required this.selected,
    required this.onTap,
  });

  final GameProfile profile;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
          decoration: BoxDecoration(
            color: const Color(0xFF020617).withValues(alpha: 0.55),
            border: Border.all(
              color: selected
                  ? const Color(0xFF2DD4BF)
                  : const Color(0xFF1E293B),
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected
                    ? const Color(0xFF2DD4BF)
                    : const Color(0xFF64748B),
                size: 21,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.name,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      profile.shortNote,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle,
                    color: Color(0xFF2DD4BF), size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.device,
    required this.selected,
    required this.onTap,
  });

  final BondedDevice device;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
          decoration: BoxDecoration(
            color: const Color(0xFF020617).withValues(alpha: 0.55),
            border: Border.all(
              color: selected
                  ? const Color(0xFF2DD4BF)
                  : const Color(0xFF1E293B),
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(Icons.laptop_windows,
                  color: Color(0xFFCBD5E1), size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  device.name,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F766E).withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Paired',
                  style: TextStyle(fontSize: 11.5, color: Color(0xFF5EEAD4)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({required this.onAllow});

  final Future<bool> Function() onAllow;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF020617).withValues(alpha: 0.55),
        border: Border.all(color: const Color(0xFF92400E)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Bluetooth permission chahiye',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Laptop ki list dekhne aur connect karne ke liye pehle Bluetooth permission do. Koi internet use nahi hota.',
            style: TextStyle(fontSize: 13.5, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 11),
          FilledButton(
            onPressed: onAllow,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
            ),
            child: const Text('Allow Bluetooth'),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF020617).withValues(alpha: 0.55),
        border: Border.all(color: const Color(0xFF1E293B)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13.5, color: Color(0xFF94A3B8)),
      ),
    );
  }
}

class _GuideStep extends StatelessWidget {
  const _GuideStep({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 21,
            height: 21,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF0F766E),
            ),
            child: Center(
              child: Text(
                '$number',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.35,
                color: Color(0xFFCBD5E1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
