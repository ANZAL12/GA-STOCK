import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/hardware_scanner_service.dart';
import '../services/offline_queue_service.dart';
import '../services/offline_manager.dart';
import '../services/websocket_service.dart';
import '../widgets/responsive_utils.dart';
import '../widgets/add_shop_dialog.dart';
import '../widgets/offline_banner.dart';
import 'login_screen.dart';
import 'inward_screen.dart';
import 'outward_screen.dart';
import 'serial_lookup_screen.dart';
import 'offline_queue_screen.dart';
import 'print_bill_screen.dart';
import 'quick_dispatch_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ApiService _api = ApiService();
  final OfflineQueueService _queue = OfflineQueueService();
  VoidCallback? _scannerSub;
  int _pendingQueueCount = 0;

  @override
  void initState() {
    super.initState();
    _refreshQueueCount();
    WebSocketService().connect();
    _api.preWarmCache();

    // Listen for hardware barcode scanner on home screen (auto-opens Serial Trace)
    _scannerSub = HardwareScannerService().registerListener((barcode) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SerialLookupScreen(initialSerial: barcode),
        ),
      );
    });
  }

  @override
  void dispose() {
    _scannerSub?.call();
    super.dispose();
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
    final isTablet = context.isTablet;

    // Action Cards
    final cardInward = _buildActionCard(
      isTablet: isTablet,
      title: 'Inward Stock Scan',
      icon: Icons.input_rounded,
      iconColor: const Color(0xFF059669),
      iconBg: const Color(0xFFECFDF5),
      badgeText: 'Inward Mode',
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const InwardScreen()),
        );
        _refreshQueueCount();
      },
    );

    final cardOutward = _buildActionCard(
      isTablet: isTablet,
      title: 'Outward Dispatch Scan',
      icon: Icons.output_rounded,
      iconColor: const Color(0xFFD97706),
      iconBg: const Color(0xFFFFFBEB),
      badgeText: 'Dispatch Mode',
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const OutwardScreen()),
        );
        _refreshQueueCount();
      },
    );

    final cardQuickScan = _buildActionCard(
      isTablet: isTablet,
      title: 'Quick Dispatch Scan',
      icon: Icons.bolt,
      iconColor: const Color(0xFFEA580C),
      iconBg: const Color(0xFFFFF7ED),
      badgeText: 'Direct Scan',
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const QuickDispatchScreen()),
        );
        _refreshQueueCount();
      },
    );

    final cardTrace = _buildActionCard(
      isTablet: isTablet,
      title: 'Serial Number Trace',
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
    );

    final cardPrint = _buildActionCard(
      isTablet: isTablet,
      title: 'Print / Export Bill',
      icon: Icons.print_rounded,
      iconColor: const Color(0xFF7C3AED),
      iconBg: const Color(0xFFF5F3FF),
      badgeText: 'PDF / Print',
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PrintBillScreen()),
        );
      },
    );

    final cardAddShop = _buildActionCard(
      isTablet: isTablet,
      title: 'Add New Shop',
      assetIconPath: 'assets/images/shop_icon.png',
      iconColor: const Color(0xFF0284C7),
      iconBg: const Color(0xFFF0F9FF),
      badgeText: 'Quick Add',
      onTap: () async {
        final newShop = await showAddShopDialog(context);
        if (newShop != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Shop "${newShop.name}" added successfully!'),
              backgroundColor: const Color(0xFF059669),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
    );

    Widget? cardQueue;
    if (_pendingQueueCount > 0) {
      cardQueue = _buildActionCard(
        isTablet: isTablet,
        title: 'Offline Sync Queue',
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
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        toolbarHeight: isTablet ? 72 : 56,
        backgroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            Image.asset(
              'assets/images/logo.png',
              width: isTablet ? 40 : 32,
              height: isTablet ? 40 : 32,
              fit: BoxFit.contain,
            ),
            SizedBox(width: isTablet ? 14 : 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Global Agencies',
                  style: TextStyle(
                    color: const Color(0xFF0F172A),
                    fontSize: isTablet ? 19 : 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  user != null ? '${user.fullName} (${user.role})' : 'Godown Terminal',
                  style: TextStyle(
                    color: const Color(0xFF64748B),
                    fontSize: isTablet ? 13 : 11,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          if (_pendingQueueCount > 0)
            IconButton(
              iconSize: isTablet ? 28 : 24,
              icon: Badge(
                label: Text('$_pendingQueueCount', style: TextStyle(fontSize: isTablet ? 12 : 10)),
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
            iconSize: isTablet ? 28 : 24,
            icon: const Icon(Icons.logout, color: Color(0xFF64748B)),
            tooltip: 'Logout',
            onPressed: _handleLogout,
          ),
          if (isTablet) const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const OfflineBanner(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  await _refreshQueueCount();
                  await OfflineManager().syncFromBackend();
                },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(
              horizontal: isTablet ? 28 : 20,
              vertical: isTablet ? 22 : 20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                Text(
                  'WAREHOUSE OPERATIONS',
                  style: TextStyle(
                    fontSize: isTablet ? 13 : 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
                SizedBox(height: isTablet ? 16 : 12),

                // Responsive layout: 2-column grid on tablets, stacked single column on phones
                if (isTablet) ...[
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: cardInward),
                        const SizedBox(width: 20),
                        Expanded(child: cardOutward),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: cardQuickScan),
                        const SizedBox(width: 20),
                        Expanded(child: cardTrace),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: cardPrint),
                        const SizedBox(width: 20),
                        Expanded(child: cardAddShop),
                      ],
                    ),
                  ),
                  if (cardQueue != null) ...[
                    const SizedBox(height: 20),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: cardQueue),
                          const SizedBox(width: 20),
                          const Expanded(child: SizedBox()),
                        ],
                      ),
                    ),
                  ],
                ] else ...[
                  cardInward,
                  const SizedBox(height: 14),
                  cardOutward,
                  const SizedBox(height: 14),
                  cardQuickScan,
                  const SizedBox(height: 14),
                  cardTrace,
                  const SizedBox(height: 14),
                  cardPrint,
                  const SizedBox(height: 14),
                  cardAddShop,
                  if (cardQueue != null) ...[
                    const SizedBox(height: 14),
                    cardQueue,
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    ],
  ),
),
);
  }

  Widget _buildActionCard({
    required bool isTablet,
    required String title,
    IconData? icon,
    String? assetIconPath,
    required Color iconColor,
    required Color iconBg,
    required String badgeText,
    required VoidCallback onTap,
  }) {
    if (isTablet) {
      return Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        elevation: 0,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            constraints: const BoxConstraints(minHeight: 130),
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: iconBg,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: assetIconPath != null
                          ? Padding(
                              padding: const EdgeInsets.all(12),
                              child: Image.asset(assetIconPath, fit: BoxFit.contain),
                            )
                          : Icon(
                              icon ?? Icons.circle,
                              color: iconColor,
                              size: 28,
                            ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: iconBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: iconColor.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Text(
                        badgeText,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: iconColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 20,
                      color: iconColor,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: assetIconPath != null
                    ? Padding(
                        padding: const EdgeInsets.all(10),
                        child: Image.asset(assetIconPath, fit: BoxFit.contain),
                      )
                    : Icon(
                        icon ?? Icons.circle,
                        color: iconColor,
                        size: 24,
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badgeText,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF475569),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: Color(0xFF94A3B8), size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

