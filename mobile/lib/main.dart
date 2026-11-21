import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';
import 'services/hardware_scanner_service.dart';
import 'services/memory_guard.dart';
import 'services/sound_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MemoryGuard.instance.attach();
  HardwareScannerService().init();
  // Defer audio pool so the first frame is not blocked on 3GB devices
  WidgetsBinding.instance.addPostFrameCallback((_) {
    SoundService().init();
  });
  runApp(const GodownScannerApp());
}

class GodownScannerApp extends StatelessWidget {
  const GodownScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Global Agencies Scanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E1B4B),
          primary: const Color(0xFF1E1B4B),
          secondary: const Color(0xFF3C3489),
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF0F172A),
          elevation: 0,
          centerTitle: false,
        ),
      ),
      scrollBehavior: const _LowRamScrollBehavior(),
      home: const SplashScreen(),
    );
  }
}

/// Clamping overscroll avoids the glow/stretch saveLayer cost on Mali GPUs.
class _LowRamScrollBehavior extends MaterialScrollBehavior {
  const _LowRamScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics();
}
