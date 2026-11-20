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
      final fetched = await _hid.getBondedDevices();
      if (!mounted) return;
      // Laptop (computer class) sab se upar — list me earbuds aur
      // dusre phones bhi hote hain, beginner ko apna laptop pehle
      // nazar aana chahiye. Har group ke andar asal tartib barqarar.
      final devices = <BondedDevice>[
        ...fetched.where((device) => device.isComputer),
        ...fetched.where((device) => !device.isComputer),
      ];
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
          } else {
            // List me sirf aik hi computer ho to wahi laptop hai —
            // khud select kar lo, chahe saath earbuds waghera bhi hon.
            final computers =
                devices.where((device) => device.isComputer).toList();
            if (computers.length == 1) {
              _selectedAddress = computers.first.address;
            } else if (devices.length == 1) {
              _selectedAddress = devices.first.address;
            } else {
              _selectedAddress = null;
            }
          }
        }
      });
    } catch (_) {
      // Platform side se jawab na aye to screen khamosh na rahe.
      if (!mounted) return;
      setState(() {
        _errorText =
            'Could not read the Bluetooth state. Wait a moment, then tap refresh (the round arrow at the top).';
      });
    }
  }

  bool _sameDevices(List<BondedDevice> a, List<BondedDevice> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].address != b[i].address ||
          a[i].name != b[i].name ||
          a[i].majorClass != b[i].majorClass) {
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
          'AB GTA needs Bluetooth permission so it can connect to '
          'your laptop.\n\n'
          'No internet is used, and no data goes anywhere.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Got it — Allow'),
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
        title: const Text('Give permission from Settings'),
        content: const Text(
          'Bluetooth permission is switched off, so the system dialog '
          'did not appear.\n\n'
          'Open Settings → Permissions → Nearby devices → Allow. '
          'Then come back and try again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Later'),
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
            child: const Text('Open Settings'),
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
      _statusText = 'Getting ready…';
    });

    if (!await _ensurePermissions()) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _statusText = 'Not connected';
        _errorText =
            'Cannot connect without Bluetooth permission. Tap the "Allow Bluetooth" button above.';
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
          ? 'Your phone is discoverable for 5 minutes — now pair from your laptop (steps below). If the time runs out, tap this button again.'
          : 'Could not become discoverable. Try again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    // Pehli dafa wala user yahin atakta hai: koi laptop paired nahi.
    // Us ke liye pairing guide CONNECT se PEHLE, bilkul samne rakho —
    // warna woh khali list aur band button dekh kar phas jata hai.
    // Laptop maujood ho to guide aakhir me sirf reference ke liye hai.
    final noLaptopYet = _permissionGranted == true && _devices.isEmpty;
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
                    if (noLaptopYet) ...[
                      _buildPairingGuide(),
                      const SizedBox(height: 22),
                    ],
                    _buildConnectButton(),
                    if (_devices.isNotEmpty &&
                        _selectedAddress == null &&
                        !_busy) ...[
                      const SizedBox(height: 10),
                      const Text(
                        'Select your laptop above first, then tap CONNECT.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFFFACC15),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    _buildStatusLine(),
                    if (!noLaptopYet) ...[
                      const SizedBox(height: 22),
                      _buildPairingGuide(),
                    ],
                    const SizedBox(height: 22),
                    _buildTroubleshootingCard(),
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
                  'AB GTA',
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
          'Which game will you play?',
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
              'Your laptop',
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
              tooltip: 'Refresh',
              onPressed: _refreshDevices,
            ),
          ],
        ),
        if (_permissionGranted == false)
          _PermissionCard(onAllow: _ensurePermissions)
        else if (_devices.isEmpty)
          const _InfoCard(
            text:
                'No paired laptop found. First pair with your laptop using the guide below, then come back here.',
          )
        else
          for (final device in _devices)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: _DeviceCard(
                device: device,
                selected: _selectedAddress == device.address,
                isLastUsed: device.address == _settings.lastDeviceAddress,
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
                ? const [Color(0xFFFB923C), Color(0xFFEA580C)]
                : const [Color(0xFF374151), Color(0xFF1F2937)],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: canConnect
              ? [
                  BoxShadow(
                    color: const Color(0xFFF97316).withValues(alpha: 0.4),
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
        border: Border.all(color: const Color(0xFF262E3A)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'First time? Pair like this:',
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
                'Tap the button below — your phone will become visible to the laptop.',
          ),
          const _GuideStep(
            number: 2,
            text:
                'On your laptop: Settings → Bluetooth & devices → Add device → Bluetooth.',
          ),
          const _GuideStep(
            number: 3,
            text:
                'Select your phone. If a code appears, tap Yes/Connect on both screens.',
          ),
          const _GuideStep(
            number: 4,
            text: 'Come back here, select your laptop and tap CONNECT.',
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _makeDiscoverable,
              icon: const Icon(Icons.bluetooth_searching, size: 19),
              label: const Text('Make phone discoverable'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFB923C),
                side: const BorderSide(color: Color(0xFFC2410C)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Masla aye to hal — bilkul wahi jagah jahan connect fail hota hai.
  /// Sab se aam wajahen tartib se: purani ghalat pairing, dusri remote
  /// app, Bluetooth band, battery pabandi.
  Widget _buildTroubleshootingCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF020617).withValues(alpha: 0.55),
        border: Border.all(color: const Color(0xFF262E3A)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Theme(
        // ExpansionTile ki apni divider lines is design me nahi chahiye.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: const ExpansionTile(
          tilePadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 14),
          iconColor: Color(0xFFFB923C),
          collapsedIconColor: Color(0xFF94A3B8),
          title: Text(
            'Having trouble? Check these',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          children: [
            _HelpPoint(
              'Connection keeps failing? In your laptop\'s Bluetooth '
              'settings, remove this phone ("Remove device"), then keep '
              'this app open and pair again — old pairings often go bad.',
            ),
            _HelpPoint(
              'Is Bluetooth ON on your laptop? And keep the "Add device" '
              'page open while you make the phone discoverable.',
            ),
            _HelpPoint(
              'Close any other remote or keyboard app (for example PC '
              'Remote) — only one app can be a Bluetooth keyboard at a '
              'time.',
            ),
            _HelpPoint(
              'Keep the phone and laptop close together. Still not '
              'working? Turn Bluetooth off and on again on both.',
            ),
            _HelpPoint(
              'Connection keeps dropping? Phone Settings → Apps → '
              'AB GTA → Battery → set it to Unrestricted.',
            ),
          ],
        ),
      ),
    );
  }
}

/// Masla-hal card ki aik line (bullet ke saath).
class _HelpPoint extends StatelessWidget {
  const _HelpPoint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  ', style: TextStyle(color: Color(0xFFFB923C))),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: Color(0xFFCBD5E1),
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
                  ? const Color(0xFFF97316)
                  : const Color(0xFF262E3A),
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
                    ? const Color(0xFFF97316)
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
                    color: Color(0xFFF97316), size: 20),
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
    required this.isLastUsed,
    required this.onTap,
  });

  final BondedDevice device;
  final bool selected;

  /// Ye wahi laptop hai jo pichli dafa istemal hua tha.
  final bool isLastUsed;
  final VoidCallback onTap;

  /// Device ki qisam ke hisab se icon — list me earbuds aur dusre
  /// phones bhi hote hain; icon se foran pata chale konsa laptop hai.
  IconData get _icon {
    if (device.isComputer) return Icons.laptop_windows;
    if (device.isPhone) return Icons.smartphone;
    if (device.isAudio) return Icons.headphones;
    return Icons.bluetooth;
  }

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
                  ? const Color(0xFFF97316)
                  : const Color(0xFF262E3A),
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(_icon, color: const Color(0xFFCBD5E1), size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  device.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              if (isLastUsed) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Last laptop',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFFFCD34D),
                    ),
                  ),
                ),
                const SizedBox(width: 7),
              ],
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEA580C).withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Paired',
                  style: TextStyle(fontSize: 11.5, color: Color(0xFFFDBA74)),
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
            'Bluetooth permission needed',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Give Bluetooth permission first, to see the laptop list and connect. No internet is used.',
            style: TextStyle(fontSize: 13.5, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 11),
          FilledButton(
            onPressed: onAllow,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEA580C),
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
        border: Border.all(color: const Color(0xFF262E3A)),
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
              color: Color(0xFFEA580C),
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
