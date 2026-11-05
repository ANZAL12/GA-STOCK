import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/top_toast.dart';
import 'outward_screen.dart';

class TallyBillsScreen extends StatefulWidget {
  const TallyBillsScreen({super.key});

  @override
  State<TallyBillsScreen> createState() => _TallyBillsScreenState();
}

class _TallyBillsScreenState extends State<TallyBillsScreen> {
  final ApiService _api = ApiService();

  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  bool _loading = true;
  bool _syncing = false;
  String? _errorMessage;

  TallyStatus? _tallyStatus;
  List<TallySalesVoucher> _vouchers = [];

  // Filter state: 'all', 'pending', 'processed', 'cancelled'
  String _activeFilter = 'pending';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData({bool showIndicator = true}) async {
    if (showIndicator) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    try {
      final statusFuture = _api.getTallyStatus();

      bool? filterProcessed;
      bool? filterCancelled;

      if (_activeFilter == 'pending') {
        filterProcessed = false;
        filterCancelled = false;
      } else if (_activeFilter == 'processed') {
        filterProcessed = true;
      } else if (_activeFilter == 'cancelled') {
        filterCancelled = true;
      }

      final vouchersFuture = _api.getTallyVouchers(
        query: _searchController.text.trim().isEmpty ? null : _searchController.text.trim(),
        isProcessed: filterProcessed,
        isCancelled: filterCancelled,
        limit: 100,
      );

      final results = await Future.wait([statusFuture, vouchersFuture]);
      if (!mounted) return;

      setState(() {
        _tallyStatus = results[0] as TallyStatus;
        _vouchers = results[1] as List<TallySalesVoucher>;
        _loading = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = e.toString().replaceAll('Exception:', '').trim();
      });
    }
  }

  Future<void> _triggerSync({bool forceFull = false}) async {
    if (_syncing) return;
    setState(() => _syncing = true);
    HapticFeedback.lightImpact();

    try {
      final res = await _api.triggerTallySync(forceFull: forceFull);
      if (!mounted) return;
      final msg = res['message'] ?? 'Tally synchronization completed!';
      TopToast.show(context, message: msg, backgroundColor: const Color(0xFF059669));
      await _loadData(showIndicator: false);
    } catch (e) {
      if (!mounted) return;
      final err = e.toString().replaceAll('Exception:', '').trim();
      TopToast.show(context, message: 'Sync failed: $err', backgroundColor: const Color(0xFFDC2626));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _onSearchChanged(String val) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 350), () {
      _loadData(showIndicator: false);
    });
  }

  Future<void> _openVoucherDetail(TallySalesVoucher summary) async {
    HapticFeedback.lightImpact();
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _VoucherDetailDialog(
        voucherId: summary.id,
        initialSummary: summary,
        onStatusChanged: () => _loadData(showIndicator: false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF1E1B4B),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'TallyPrime Sales Bills',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (_tallyStatus != null)
              Text(
                _tallyStatus!.activeCompany != null
                    ? 'Company: ${_tallyStatus!.activeCompany}'
                    : 'Port ${_tallyStatus!.port} • ${_tallyStatus!.isConnected ? "Connected" : "Offline"}',
                style: const TextStyle(fontSize: 11, color: Color(0xFFC7D2FE)),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sync from Tally',
            icon: _syncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.sync_rounded),
            onPressed: _syncing ? null : () => _triggerSync(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadData(showIndicator: false),
        color: const Color(0xFF3C3489),
        child: Column(
          children: [
            // Status & Sync Banner
            _buildStatusHeader(isTablet),

            // Search Bar & Filters
            _buildSearchAndFilters(),

            // List of Sales Bills
            Expanded(
              child: _buildBody(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusHeader(bool isTablet) {
    if (_tallyStatus == null && _loading) return const SizedBox.shrink();

    final isOnline = _tallyStatus?.isConnected == true;
    final lastSync = _tallyStatus?.lastSyncAt;
    String lastSyncText = 'Never synced';
    if (lastSync != null) {
      try {
        final dt = DateTime.parse(lastSync).toLocal();
        final now = DateTime.now();
        if (now.difference(dt).inMinutes < 1) {
          lastSyncText = 'Just now';
        } else if (now.difference(dt).inHours < 1) {
          lastSyncText = '${now.difference(dt).inMinutes} min ago';
        } else {
          lastSyncText = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        }
      } catch (_) {}
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isOnline ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isOnline ? Icons.check_circle_rounded : Icons.cloud_off_rounded,
              color: isOnline ? const Color(0xFF059669) : const Color(0xFFDC2626),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      isOnline ? 'TallyPrime Online' : 'Tally Offline / Agent Ready',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isOnline ? const Color(0xFF059669) : const Color(0xFFB91C1C),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${_tallyStatus?.pendingVouchers ?? 0} Pending',
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF4F46E5),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Last synced: $lastSyncText • Port ${_tallyStatus?.port ?? 9000}',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF3C3489),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              backgroundColor: const Color(0xFFEEF2FF),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: _syncing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded, size: 16),
            label: Text(_syncing ? 'Syncing...' : 'Sync Now', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
            onPressed: _syncing ? null : () => _triggerSync(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          // Search box
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search by invoice number or party name...',
                hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF64748B)),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _loadData(showIndicator: false);
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('pending', 'Pending Dispatch', Icons.pending_actions_rounded),
                const SizedBox(width: 6),
                _buildFilterChip('processed', 'Processed in GA', Icons.check_circle_outline),
                const SizedBox(width: 6),
                _buildFilterChip('all', 'All Sales Bills', Icons.receipt_long_outlined),
                const SizedBox(width: 6),
                _buildFilterChip('cancelled', 'Cancelled Bills', Icons.cancel_outlined),
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String filterKey, String label, IconData icon) {
    final isSelected = _activeFilter == filterKey;
    return ChoiceChip(
      selected: isSelected,
      onSelected: (val) {
        if (val) {
          setState(() => _activeFilter = filterKey);
          _loadData(showIndicator: false);
        }
      },
      avatar: Icon(
        icon,
        size: 15,
        color: isSelected ? Colors.white : const Color(0xFF64748B),
      ),
      label: Text(label),
      selectedColor: const Color(0xFF1E1B4B),
      backgroundColor: Colors.white,
      labelStyle: TextStyle(
        fontSize: 11.5,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        color: isSelected ? Colors.white : const Color(0xFF334155),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isSelected ? const Color(0xFF1E1B4B) : const Color(0xFFCBD5E1),
        ),
      ),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF3C3489)),
            SizedBox(height: 14),
            Text('Loading Tally sales bills...', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded, size: 48, color: Color(0xFFDC2626)),
              const SizedBox(height: 12),
              Text(
                'Could not load Tally bills\n$_errorMessage',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF475569), fontSize: 13),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3C3489),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try Again'),
                onPressed: () => _loadData(),
              ),
            ],
          ),
        ),
      );
    }

    if (_vouchers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.receipt_long_outlined, size: 54, color: Color(0xFF94A3B8)),
              const SizedBox(height: 14),
              const Text(
                'No Sales Bills Found',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
              ),
              const SizedBox(height: 6),
              const Text(
                'Tap "Sync Now" to import sales invoices from TallyPrime,\nor check your search filters.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.sync_rounded, size: 18),
                label: const Text('Sync From Tally'),
                onPressed: _syncing ? null : () => _triggerSync(),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
      itemCount: _vouchers.length,
      itemBuilder: (ctx, idx) {
        final v = _vouchers[idx];
        return _buildVoucherCard(v);
      },
    );
  }

  Widget _buildVoucherCard(TallySalesVoucher v) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: v.isProcessed
              ? const Color(0xFFBBF7D0)
              : (v.isCancelled ? const Color(0xFFFECACA) : const Color(0xFFE2E8F0)),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => _openVoucherDetail(v),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Invoice # + Date + Status Badge
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        v.voucherNumber,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      v.voucherDate,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                    const Spacer(),
                    if (v.isCancelled)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFFECACA)),
                        ),
                        child: const Text(
                          'CANCELLED',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFDC2626),
                          ),
                        ),
                      )
                    else if (v.isProcessed)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFBBF7D0)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check, size: 12, color: Color(0xFF15803D)),
                            SizedBox(width: 3),
                            Text(
                              'Processed',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF15803D),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFFDE68A)),
                        ),
                        child: const Text(
                          'Pending Dispatch',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFB45309),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),

                // Party Name
                Text(
                  v.partyName,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                if (v.address != null && v.address!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    v.address!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                  ),
                ],
                const SizedBox(height: 10),

                // Footer Row: Item Count, Total Units, Godowns
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${v.itemCount} Items • ${v.totalQuantity.toStringAsFixed(v.totalQuantity.truncateToDouble() == v.totalQuantity ? 0 : 1)} Units',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF4338CA),
                        ),
                      ),
                    ),
                    if (v.godowns.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '📍 ${v.godowns.join(", ")}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                        ),
                      ),
                    ] else
                      const Spacer(),
                    if (!v.isProcessed && !v.isCancelled) ...[
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => OutwardScreen(fromTallyVoucher: v),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4F46E5),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.barcode_reader, size: 12, color: Colors.white),
                              SizedBox(width: 4),
                              Text(
                                'Start Scan',
                                style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right, size: 18, color: Color(0xFF94A3B8)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Voucher Details Modal (Strictly Non-Financial)
// ---------------------------------------------------------------------------

class _VoucherDetailDialog extends StatefulWidget {
  final String voucherId;
  final TallySalesVoucher initialSummary;
  final VoidCallback onStatusChanged;

  const _VoucherDetailDialog({
    required this.voucherId,
    required this.initialSummary,
    required this.onStatusChanged,
  });

  @override
  State<_VoucherDetailDialog> createState() => _VoucherDetailDialogState();
}

class _VoucherDetailDialogState extends State<_VoucherDetailDialog> {
  final ApiService _api = ApiService();
  bool _loading = true;
  TallySalesVoucher? _detail;
  String? _error;
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    _fetchDetail();
  }

  Future<void> _fetchDetail() async {
    try {
      final res = await _api.getTallyVoucherDetail(widget.voucherId);
      if (!mounted) return;
      setState(() {
        _detail = res;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception:', '').trim();
        _loading = false;
      });
    }
  }

  Future<void> _toggleProcessed() async {
    if (_detail == null || _updating) return;
    final newProcessed = !_detail!.isProcessed;
    setState(() => _updating = true);

    try {
      await _api.markTallyVoucherProcessed(
        _detail!.id,
        processed: newProcessed,
        notes: newProcessed ? 'Marked processed in mobile scanner' : null,
      );
      if (!mounted) return;
      setState(() {
        _detail = TallySalesVoucher(
          id: _detail!.id,
          guid: _detail!.guid,
          alterId: _detail!.alterId,
          voucherNumber: _detail!.voucherNumber,
          voucherDate: _detail!.voucherDate,
          voucherType: _detail!.voucherType,
          partyName: _detail!.partyName,
          partyLedgerName: _detail!.partyLedgerName,
          buyerName: _detail!.buyerName,
          address: _detail!.address,
          stateName: _detail!.stateName,
          companyName: _detail!.companyName,
          isCancelled: _detail!.isCancelled,
          isDeleted: _detail!.isDeleted,
          isProcessed: newProcessed,
          processedAt: newProcessed ? DateTime.now().toIso8601String() : null,
          itemCount: _detail!.itemCount,
          totalQuantity: _detail!.totalQuantity,
          godowns: _detail!.godowns,
          items: _detail!.items,
          notes: _detail!.notes,
        );
        _updating = false;
      });
      widget.onStatusChanged();
      TopToast.show(
        context,
        message: newProcessed ? 'Voucher marked as processed!' : 'Voucher unmarked.',
        backgroundColor: newProcessed ? const Color(0xFF059669) : const Color(0xFF334155),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _updating = false);
      TopToast.show(context, message: 'Update failed: $e', backgroundColor: const Color(0xFFDC2626));
    }
  }

  void _copyToOutward() {
    final v = _detail ?? widget.initialSummary;
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => OutwardScreen(fromTallyVoucher: v)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = _detail ?? widget.initialSummary;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 550, maxHeight: 700),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 14),
              decoration: const BoxDecoration(
                color: Color(0xFF1E1B4B),
                borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Invoice: ${v.voucherNumber}',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Date: ${v.voucherDate} • ${v.companyName ?? "Tally"}',
                          style: const TextStyle(fontSize: 11.5, color: Color(0xFFC7D2FE)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF3C3489)))
                  : ListView(
                      padding: const EdgeInsets.all(18),
                      children: [
                        if (_error != null) ...[
                          Container(
                            padding: const EdgeInsets.all(10),
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFFECACA)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline, color: Color(0xFFDC2626), size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(_error!, style: const TextStyle(color: Color(0xFF991B1B), fontSize: 11.5)),
                                ),
                              ],
                            ),
                          ),
                        ],
                        // Party details
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('PARTY / CUSTOMER', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                              const SizedBox(height: 4),
                              Text(v.partyName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                              if (v.address != null && v.address!.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(v.address!, style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
                              ],
                              if (v.stateName != null) ...[
                                const SizedBox(height: 2),
                                Text('State: ${v.stateName}', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Processed status bar
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                v.isProcessed ? '✓ Processed in GA STOCK' : '⏳ Pending Dispatch Scan',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12.5,
                                  color: v.isProcessed ? const Color(0xFF15803D) : const Color(0xFFB45309),
                                ),
                              ),
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: v.isProcessed ? const Color(0xFFFEF2F2) : const Color(0xFFECFDF5),
                                foregroundColor: v.isProcessed ? const Color(0xFFDC2626) : const Color(0xFF059669),
                                elevation: 0,
                                side: BorderSide(
                                  color: v.isProcessed ? const Color(0xFFFECACA) : const Color(0xFFA7F3D0),
                                ),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              ),
                              icon: _updating
                                  ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                                  : Icon(v.isProcessed ? Icons.undo_rounded : Icons.check_circle_outline, size: 16),
                              label: Text(
                                v.isProcessed ? 'Unmark' : 'Mark Processed',
                                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                              ),
                              onPressed: _updating ? null : _toggleProcessed,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Section Title: Inventory Items
                        Row(
                          children: [
                            const Text(
                              'Billed Inventory Items',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                            ),
                            const Spacer(),
                            Text(
                              '${v.items.length} Lines • Non-Financial',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Inventory Items List
                        ...v.items.map((itm) => _buildItemTile(itm)),
                      ],
                    ),
            ),

            // Footer action
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E1B4B),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                      icon: const Icon(Icons.output_rounded, size: 16),
                      label: const Text('Open Dispatch Scan', style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: _copyToOutward,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemTile(TallyVoucherItem itm) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  itm.itemName,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  itm.rawQtyText ?? '${itm.quantity.toStringAsFixed(itm.quantity.truncateToDouble() == itm.quantity ? 0 : 1)} ${itm.uom ?? "Units"}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF4338CA),
                  ),
                ),
              ),
            ],
          ),
          if (itm.godownName != null && itm.godownName!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 13, color: Color(0xFF059669)),
                const SizedBox(width: 3),
                Text(
                  'Godown: ${itm.godownName}',
                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF059669), fontWeight: FontWeight.w600),
                ),
                if (itm.batchName != null && itm.batchName!.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    '• Batch: ${itm.batchName}',
                    style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
