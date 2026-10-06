import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/offline_queue_service.dart';
import '../services/websocket_service.dart';
import 'login_screen.dart';
import 'inward_screen.dart';
import 'outward_screen.dart';
import 'serial_lookup_screen.dart';
import 'offline_queue_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ApiService _api = ApiService();
  final OfflineQueueService _queue = OfflineQueueService();
  int _pendingQueueCount = 0;

  @override
  void initState() {
    super.initState();
    _refreshQueueCount();
    WebSocketService().connect();
  }

  Future<void> _refreshQueueCount() async {
    final count = await _queue.queueCount();
    if (mounted) setState(() => _pendingQueueCount = count);
  }

  void _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm Logout', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to end your scanning session?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE11D48),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _api.logout();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _api.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Global Agencies',
              style: TextStyle(color: Color(0xFF0F172A), fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              user != null ? '${user.fullName} (${user.role})' : 'Godown Terminal',
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
            ),
          ],
        ),
        actions: [
          if (_pendingQueueCount > 0)
            IconButton(
              icon: Badge(
                label: Text('$_pendingQueueCount'),
                child: const Icon(Icons.cloud_upload_outlined, color: Color(0xFFD97706)),
              ),
              tooltip: 'Offline Queue',
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const OfflineQueueScreen()),
                );
                _refreshQueueCount();
              },
            ),
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFF64748B)),
            tooltip: 'Logout',
            onPressed: _handleLogout,
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshQueueCount,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top status banner
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1E1B4B), Color(0xFF312E81)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1E1B4B).withValues(alpha: 0.15),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.sensors, color: Colors.white, size: 26),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Godown Floor Scanner Active',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Device: ${_api.deviceUid?.substring(0, 8)}... (Authorized)',
                              style: const TextStyle(color: Color(0xFFC7D2FE), fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                const Text(
                  'WAREHOUSE OPERATIONS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                    color: Color(0xFF94A3B8),
                  ),
                ),
                const SizedBox(height: 12),

                // Card 1: Inward Stock Scan
                _buildActionCard(
                  title: 'Inward Stock Scan',
                  subtitle: 'Receive appliances from factory, scan serial numbers, and register onto godown shelves.',
                  icon: Icons.input_rounded,
                  iconColor: const Color(0xFF059669),
                  iconBg: const Color(0xFFECFDF5),
                  badgeText: 'Step 1: Select Model',
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const InwardScreen()),
                    );
                    _refreshQueueCount();
                  },
                ),
                const SizedBox(height: 14),

                // Card 2: Outward Dispatch Scan
                _buildActionCard(
                  title: 'Outward Dispatch Scan',
                  subtitle: 'Dispatch stock to shops. 4-case live validation: matched units & pre-go-live recorded only.',
                  icon: Icons.output_rounded,
                  iconColor: const Color(0xFFD97706),
                  iconBg: const Color(0xFFFFFBEB),
                  badgeText: 'Step 1: Select Shop',
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const OutwardScreen()),
                    );
                    _refreshQueueCount();
                  },
                ),
                const SizedBox(height: 14),

                // Card 3: Serial Number Lookup
                _buildActionCard(
                  title: 'Serial Number Trace',
                  subtitle: 'Scan any barcode to view full lifecycle: inward date, last shop, current status, and history.',
                  icon: Icons.search_rounded,
                  iconColor: const Color(0xFF3C3489),
                  iconBg: const Color(0xFFEEF2FF),
                  badgeText: 'Live Lookup',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SerialLookupScreen()),
                    );
                  },
                ),

                if (_pendingQueueCount > 0) ...[
                  const SizedBox(height: 14),
                  // Card 4: Offline Queue
                  _buildActionCard(
                    title: 'Offline Sync Queue',
                    subtitle: '$_pendingQueueCount batch(es) stored locally due to weak Wi-Fi. Tap to review and sync to server.',
                    icon: Icons.cloud_sync_outlined,
                    iconColor: const Color(0xFF2563EB),
                    iconBg: const Color(0xFFEFF6FF),
                    badgeText: '$_pendingQueueCount Pending',
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const OfflineQueueScreen()),
                      );
                      _refreshQueueCount();
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String badgeText,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: iconBg,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: iconColor, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                badgeText,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF475569),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.35),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
