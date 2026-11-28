import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
import 'screens/splash_screen.dart';
import 'services/api_service.dart';
import 'services/sound_service.dart';
import 'services/hardware_scanner_service.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Bound image memory cache to avoid garbage collection stutter on 3GB RAM devices
  PaintingBinding.instance.imageCache.maximumSizeBytes = 40 * 1024 * 1024; // 40 MB
  PaintingBinding.instance.imageCache.maximumSize = 100;
  await SoundService().init();
  HardwareScannerService().init();
  runApp(const GodownScannerApp());
}

class GodownScannerApp extends StatelessWidget {
  const GodownScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'Global Agencies Scanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Inter',
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
      builder: (context, child) {
        return UserDisabledWatcher(child: child ?? const SizedBox());
      },
      home: const SplashScreen(),
    );
  }
}

class UserDisabledWatcher extends StatefulWidget {
  final Widget child;
  const UserDisabledWatcher({super.key, required this.child});

  @override
  State<UserDisabledWatcher> createState() => _UserDisabledWatcherState();
}

class _UserDisabledWatcherState extends State<UserDisabledWatcher> {
  bool _isDialogOpen = false;

  @override
  void initState() {
    super.initState();
    ApiService().userDisabledNotifier.addListener(_onUserDisabledChanged);
  }

  @override
  void dispose() {
    ApiService().userDisabledNotifier.removeListener(_onUserDisabledChanged);
    super.dispose();
  }

  void _onUserDisabledChanged() {
    final reason = ApiService().userDisabledNotifier.value;
    if (reason != null && !_isDialogOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isDialogOpen && ApiService().userDisabledNotifier.value != null) {
          _showForcedSignoutDialog(ApiService().userDisabledNotifier.value!);
        }
      });
    }
  }

  void _showForcedSignoutDialog(String reason) {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) return;
    _isDialogOpen = true;

    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogCtx) => PopScope(
        canPop: false,
        child: Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          elevation: 20,
          backgroundColor: Colors.white,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Warning Alert Badge
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFFEE2E2), width: 2),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.block_rounded,
                      color: Color(0xFFDC2626),
                      size: 34,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Account Deactivated',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  reason,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Warehouse scanning & stock access suspended.',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF475569),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Forced Sign Out Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: const Text(
                      'Forced Sign Out',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: () async {
                      _isDialogOpen = false;
                      await ApiService().logout();
                      ApiService().clearUserDisabled();
                      if (dialogCtx.mounted) {
                        Navigator.of(dialogCtx, rootNavigator: true).pop();
                      }
                      rootNavigatorKey.currentState?.pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                        (route) => false,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

