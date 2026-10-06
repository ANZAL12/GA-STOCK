import 'package:flutter/material.dart';
import '../services/api_service.dart';
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

    // 1. Check or register device (with 3 second timeout so splash never hangs)
    bool approved = false;
    try {
      approved = await api.checkOrRegisterDevice().timeout(const Duration(seconds: 3));
    } catch (_) {
      approved = false;
    }

    if (!mounted) return;

    if (!approved) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DeviceApprovalScreen()),
      );
      return;
    }

    // 2. Check auth
    if (api.isAuthenticated) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF1E1B4B),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.white),
            SizedBox(height: 16),
            Text(
              'GLOBAL AGENCIES',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Godown Scanner Suite',
              style: TextStyle(color: Color(0xFFC7D2FE), fontSize: 13),
            ),
            SizedBox(height: 32),
            CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
          ],
        ),
      ),
    );
  }
}
