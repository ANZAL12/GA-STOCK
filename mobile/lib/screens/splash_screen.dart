import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/offline_manager.dart';
import 'device_approval_screen.dart';
import 'login_screen.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    final api = ApiService();
    await api.init();
    await OfflineManager().init();

    if (!mounted) return;

    // 1. If previously logged in, ALWAYS direct directly to HomeScreen, even if network is down
    if (api.isAuthenticated) {
      // Trigger background check if network is available without blocking navigation
      api.checkOrRegisterDevice().catchError((_) => false);

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
      return;
    }

    // 2. If not logged in, check device registration / approval
    bool approved = false;
    try {
      approved = await api.checkOrRegisterDevice().timeout(const Duration(seconds: 3));
    } catch (_) {
      approved = api.isDeviceApproved;
    }

    if (!mounted) return;

    if (!approved && !api.isDeviceApproved) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DeviceApprovalScreen()),
      );
      return;
    }

    // 3. Navigate to LoginScreen
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1B4B),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/images/logo.png', width: 72, height: 72, fit: BoxFit.contain),
            const SizedBox(height: 18),
            const Text(
              'GLOBAL AGENCIES',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Godown Scanner Suite',
              style: TextStyle(color: Color(0xFFC7D2FE), fontSize: 13),
            ),
            const SizedBox(height: 32),
            const CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
          ],
        ),
      ),
    );
  }
}
