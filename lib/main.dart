import 'package:flutter/material.dart';

import 'screens/connect_screen.dart';
import 'services/settings_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsService.instance.load();
  runApp(const GtaRemoteApp());
}

/// AB GTA — phone Bluetooth steering wheel ban jata hai.
///
/// Phone khud aik Bluetooth keyboard ban kar laptop se jurta hai —
/// na internet, na laptop par koi program. Driving mode me touch
/// steering wheel + RACE/BRAKE pedals, paidal mode me joystick +
/// RUN/JUMP. Teeno GTA profiles built-in hain: GTA V, GTA San Andreas
/// Original aur Definitive.
class GtaRemoteApp extends StatelessWidget {
  const GtaRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AB GTA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFF97316), // racing orange (v2 theme)
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0B0E13),
        useMaterial3: true,
      ),
      home: const ConnectScreen(),
    );
  }
}
