import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/hardware_scanner_service.dart';
import '../services/offline_queue_service.dart';
import '../services/offline_manager.dart';
import '../services/websocket_service.dart';
import '../services/session_recovery_service.dart';
import '../widgets/responsive_utils.dart';
import '../widgets/add_shop_dialog.dart';
import '../widgets/add_product_dialog.dart';
import '../widgets/offline_banner.dart';
import 'login_screen.dart';
import 'inward_screen.dart';
import 'outward_screen.dart';
import 'serial_lookup_screen.dart';
import 'offline_queue_screen.dart';
import 'print_bill_screen.dart';
import 'quick_dispatch_screen.dart';
import 'godown_report_print_screen.dart';

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
    SessionRecoveryService().init();

    // Listen for hardware barcode scanner on home screen (auto-opens Serial Trace only when on home screen)
    _scannerSub = HardwareScannerService().registerListener((barcode) {
      if (!mounted) return;
      if (ModalRoute.of(context)?.isCurrent != true) return;
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
      title: 'Godown Bill Print',
      icon: Icons.print_rounded,
      iconColor: const Color(0xFF7C3AED),
      iconBg: const Color(0xFFF5F3FF),
      badgeText: 'Office PC',
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PrintBillScreen()),
        );
      },
    );

    final cardReportPrint = _buildActionCard(
      isTablet: isTablet,
      title: 'Stock Status Report',
      icon: Icons.table_chart_rounded,
      iconColor: const Color(0xFF0D9488),
      iconBg: const Color(0xFFCCFBF1),
      badgeText: 'Inventory Spool',
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const GodownReportPrintScreen()),
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

    final cardAddModel = _buildActionCard(
      isTablet: isTablet,
      title: 'Add Product Model',
      icon: Icons.add_shopping_cart_rounded,
      iconColor: const Color(0xFF4F46E5),
      iconBg: const Color(0xFFEEF2FF),
      badgeText: 'New Model',
      onTap: () async {
        final newProd = await showAddProductDialog(context);
        if (newProd != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Model "${newProd.brand} ${newProd.model}" created successfully!'),
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
            Focus(
              canRequestFocus: false,
              descendantsAreFocusable: false,
              skipTraversal: true,
              child: IconButton(
                focusNode: FocusNode(canRequestFocus: false, skipTraversal: true),
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
            ),
          Focus(
            canRequestFocus: false,
            descendantsAreFocusable: false,
            skipTraversal: true,
            child: IconButton(
              focusNode: FocusNode(canRequestFocus: false, skipTraversal: true),
              iconSize: isTablet ? 28 : 24,
              icon: const Icon(Icons.logout, color: Color(0xFF64748B)),
              tooltip: 'Logout',
              onPressed: _handleLogout,
            ),
          ),
          if (isTablet) const SizedBox(width: 8),
        ],
      ),
      body: Focus(
        canRequestFocus: false,
        descendantsAreFocusable: false,
        skipTraversal: true,
        child: SafeArea(
          child: Column(
          children: [
            const OfflineBanner(),
            Expanded(
              child: Stack(
                children: [
                  // Centered watermark logo
                  Positioned.fill(
                    child: Center(
                      child: IgnorePointer(
                        child: Opacity(
                          opacity: 0.09,
                          child: Image.asset(
                            'assets/images/logo.png',
                            width: isTablet ? 360 : 250,
                            height: isTablet ? 360 : 250,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Foreground Operations
                  RefreshIndicator(
                    onRefresh: () async {
                      await _refreshQueueCount();
                      await OfflineManager().syncFromBackend();
                      await SessionRecoveryService().checkActiveDraft();
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

                // Unsubmitted session recovery card (visible if crash / unexpected close occurred during session)
                ValueListenableBuilder<SessionDraft?>(
                  valueListenable: SessionRecoveryService().activeDraftNotifier,
                  builder: (context, draft, _) {
                    if (draft == null || draft.items.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: EdgeInsets.only(bottom: isTablet ? 20 : 16),
                      child: _buildUnsubmittedSessionCard(isTablet, draft),
                    );
                  },
                ),

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
                        Expanded(child: cardReportPrint),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: cardAddShop),
                        const SizedBox(width: 20),
                        Expanded(child: cardAddModel),
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
                  cardReportPrint,
                  const SizedBox(height: 14),
                  cardAddShop,
                  const SizedBox(height: 14),
                  cardAddModel,
                  if (cardQueue != null) ...[
                    const SizedBox(height: 14),
                    cardQueue,
                  ],
                ],
              ],
            ),
          ),
        ),
      ],
    ),
  ),
],
),
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
        color: Colors.white.withValues(alpha: 0.90),
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
      color: Colors.white.withValues(alpha: 0.90),
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

  Widget _buildUnsubmittedSessionCard(bool isTablet, SessionDraft draft) {
    Color primaryColor = const Color(0xFFD97706);
    Color bgColor = const Color(0xFFFFFBEB);
    Color borderColor = const Color(0xFFFDE68A);
    IconData icon = Icons.pending_actions_rounded;

    if (draft.type == SessionType.inward) {
      if (draft.inwardType == 'damaged') {
        primaryColor = const Color(0xFFDC2626);
        bgColor = const Color(0xFFFEF2F2);
        borderColor = const Color(0xFFFECACA);
        icon = Icons.warning_amber_rounded;
      } else if (draft.inwardType == 'return') {
        primaryColor = const Color(0xFFD97706);
        bgColor = const Color(0xFFFFFBEB);
        borderColor = const Color(0xFFFDE68A);
        icon = Icons.assignment_return_rounded;
      } else {
        primaryColor = const Color(0xFF059669);
        bgColor = const Color(0xFFECFDF5);
        borderColor = const Color(0xFFA7F3D0);
        icon = Icons.input_rounded;
      }
    } else if (draft.type == SessionType.quickDispatch) {
      primaryColor = const Color(0xFFEA580C);
      bgColor = const Color(0xFFFFF7ED);
      borderColor = const Color(0xFFFED7AA);
      icon = Icons.bolt_rounded;
    }

    final totalItems = draft.items.length;
    final String timeFormatted = TimeOfDay.fromDateTime(draft.updatedAt).format(context);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isTablet ? 18 : 16),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withValues(alpha: 0.12),
            offset: const Offset(0, 4),
            blurRadius: 14,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner Top Bar
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isTablet ? 18 : 14,
              vertical: isTablet ? 12 : 10,
            ),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(isTablet ? 16 : 14),
                topRight: Radius.circular(isTablet ? 16 : 14),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: primaryColor, size: isTablet ? 20 : 16),
                ),
                SizedBox(width: isTablet ? 10 : 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'Unsubmitted Session Detected',
                              style: TextStyle(
                                fontSize: isTablet ? 14 : 12,
                                fontWeight: FontWeight.bold,
                                color: primaryColor,
                                letterSpacing: 0.3,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: primaryColor,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Auto-Saved',
                              style: TextStyle(
                                fontSize: isTablet ? 10.5 : 9.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Last active at $timeFormatted • App closed or interrupted',
                        style: TextStyle(
                          fontSize: isTablet ? 12 : 10.5,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Body Content
          Padding(
            padding: EdgeInsets.all(isTablet ? 18 : 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            draft.typeTitle,
                            style: TextStyle(
                              fontSize: isTablet ? 18 : 15.5,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                          SizedBox(height: isTablet ? 6 : 4),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (draft.shopName != null && draft.shopName!.isNotEmpty)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.storefront_rounded, size: 14, color: Color(0xFF64748B)),
                                    const SizedBox(width: 4),
                                    Text(
                                      draft.shopName!,
                                      style: TextStyle(
                                        fontSize: isTablet ? 13 : 11.5,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF475569),
                                      ),
                                    ),
                                  ],
                                ),
                              if (draft.productName != null && draft.productName!.isNotEmpty)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.devices_rounded, size: 14, color: Color(0xFF64748B)),
                                    const SizedBox(width: 4),
                                    Text(
                                      draft.productName!,
                                      style: TextStyle(
                                        fontSize: isTablet ? 13 : 11.5,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF475569),
                                      ),
                                    ),
                                  ],
                                ),
                              if (draft.billNumber != null && draft.billNumber!.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Bill: ${draft.billNumber}',
                                    style: TextStyle(
                                      fontSize: isTablet ? 12 : 10.5,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF334155),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isTablet ? 12 : 10,
                        vertical: isTablet ? 8 : 6,
                      ),
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: borderColor),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$totalItems',
                            style: TextStyle(
                              fontSize: isTablet ? 20 : 17,
                              fontWeight: FontWeight.w800,
                              color: primaryColor,
                            ),
                          ),
                          Text(
                            totalItems == 1 ? 'Unit' : 'Units',
                            style: TextStyle(
                              fontSize: isTablet ? 11 : 9.5,
                              fontWeight: FontWeight.w600,
                              color: primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: isTablet ? 16 : 14),

                // Action buttons: Continue/Resume & Discard
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F172A),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: EdgeInsets.symmetric(vertical: isTablet ? 14 : 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(isTablet ? 12 : 10),
                          ),
                        ),
                        icon: const Icon(Icons.play_arrow_rounded, size: 20),
                        label: Text(
                          'Continue / Resume ($totalItems units)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: isTablet ? 14 : 12.5,
                          ),
                        ),
                        onPressed: () async {
                          if (draft.type == SessionType.outward) {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => OutwardScreen(restoredDraft: draft),
                              ),
                            );
                          } else if (draft.type == SessionType.inward) {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => InwardScreen(restoredDraft: draft),
                              ),
                            );
                          } else if (draft.type == SessionType.quickDispatch) {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => QuickDispatchScreen(restoredDraft: draft),
                              ),
                            );
                          }
                          _refreshQueueCount();
                          await SessionRecoveryService().checkActiveDraft();
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFDC2626),
                          side: const BorderSide(color: Color(0xFFFCA5A5)),
                          padding: EdgeInsets.symmetric(vertical: isTablet ? 14 : 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(isTablet ? 12 : 10),
                          ),
                        ),
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        label: Text(
                          'Discard',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: isTablet ? 13.5 : 12,
                          ),
                        ),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              title: const Row(
                                children: [
                                  Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 24),
                                  SizedBox(width: 8),
                                  Text(
                                    'Discard Draft?',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              content: Text(
                                'You have $totalItems scanned serial number${totalItems == 1 ? "" : "s"} in this ${draft.typeTitle} session.\n\nDiscarding will permanently delete this unsubmitted draft.',
                                style: const TextStyle(fontSize: 13, height: 1.4, color: Color(0xFF475569)),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFDC2626),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Discard Draft', style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          );

                          if (confirm == true) {
                            await SessionRecoveryService().clearDraft();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Unsubmitted session discarded'),
                                  duration: Duration(seconds: 2),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

