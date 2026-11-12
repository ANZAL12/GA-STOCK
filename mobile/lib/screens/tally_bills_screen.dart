import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/sound_service.dart';
import '../services/websocket_service.dart';
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
  StreamSubscription? _wsSubscription;
  VoidCallback? _newBillSub;

  @override
  void initState() {
    super.initState();
    _api.tallyBillProcessedNotifier.addListener(_onBillProcessed);
    _initLiveUpdates();
    _loadData();
  }

  void _initLiveUpdates() {
    WebSocketService().connect();
    _wsSubscription = WebSocketService().stream.listen((event) {
      if (!mounted) return;
      final type = event['event']?.toString() ?? event['type']?.toString();
      final data = event['data'];

      if (type == 'tally_bill_created' && data is Map<String, dynamic>) {
        try {
          final vch = TallySalesVoucher.fromJson(data);
          final query = _searchController.text.trim().toLowerCase();
          final matches = query.isEmpty ||
              vch.voucherNumber.toLowerCase().contains(query) ||
              vch.partyName.toLowerCase().contains(query);

          if (matches) {
            setState(() {
              _vouchers.removeWhere((v) =>
                  v.id == vch.id ||
                  v.voucherNumber.trim().toLowerCase() == vch.voucherNumber.trim().toLowerCase());
              _vouchers.insert(0, vch);
            });
            HapticFeedback.mediumImpact();
            SoundService().playScannerBeep();
            TopToast.show(
              context,
              message: '⚡ New Tally Bill: ${vch.voucherNumber} (${vch.partyName})',
              backgroundColor: const Color(0xFF0284C7),
            );
          }
        } catch (e) {
          debugPrint('[TallyBills] Failed to parse real-time voucher: $e');
        }
      } else if ((type == 'tally_bill_cancelled' || type == 'bill_cancelled') && data is Map<String, dynamic>) {
        final bNum = (data['bill_number'] ?? data['voucher_number'])?.toString().trim().toLowerCase();
        if (bNum != null && bNum.isNotEmpty) {
          setState(() {
            _vouchers.removeWhere((v) => v.voucherNumber.trim().toLowerCase() == bNum);
          });
        }
      } else if (type == 'tally_bill_processed' && data is Map<String, dynamic>) {
        final processedId = data['id']?.toString();
        final voucherNum = data['voucher_number']?.toString().trim().toLowerCase();
        setState(() {
          _vouchers.removeWhere((x) =>
              x.id == processedId ||
              x.voucherNumber.trim().toLowerCase() == voucherNum);
        });
      }
    });

    _newBillSub = () {
      final newBill = _api.latestTallyBillNotifier.value;
      if (newBill != null && mounted) {
        final query = _searchController.text.trim().toLowerCase();
        final matches = query.isEmpty ||
            newBill.voucherNumber.toLowerCase().contains(query) ||
            newBill.partyName.toLowerCase().contains(query);
        if (matches) {
          setState(() {
            _vouchers.removeWhere((v) =>
                v.id == newBill.id ||
                v.voucherNumber.trim().toLowerCase() == newBill.voucherNumber.trim().toLowerCase());
            _vouchers.insert(0, newBill);
          });
        }
      }
    };
    _api.latestTallyBillNotifier.addListener(_newBillSub!);
  }

  void _onBillProcessed() {
    if (mounted) {
      final processedId = _api.tallyBillProcessedNotifier.value;
      if (processedId != null) {
        setState(() {
          _vouchers.removeWhere((x) =>
              x.id == processedId ||
              x.voucherNumber.trim().toLowerCase() == processedId.trim().toLowerCase());
        });
      }
      _loadData(showIndicator: false);
    }
  }

  @override
  void dispose() {
    _api.tallyBillProcessedNotifier.removeListener(_onBillProcessed);
    if (_newBillSub != null) {
      _api.latestTallyBillNotifier.removeListener(_newBillSub!);
    }
    _wsSubscription?.cancel();
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
      final vouchersFuture = _api.getTallyVouchers(
        query: _searchController.text.trim().isEmpty ? null : _searchController.text.trim(),
        isProcessed: false,
        isCancelled: false,
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
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _VoucherDetailDialog(
        voucherId: summary.id,
        initialSummary: summary,
        onStatusChanged: () => _loadData(showIndicator: false),
      ),
    );
    _loadData(showIndicator: false);
  }

  @override
  Widget build(BuildContext context) {
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
            // Search Bar
            _buildSearchBar(),

            // List of Sales Bills
            Expanded(
              child: _buildBody(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
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
                'Pull down to refresh or tap below to sync from TallyPrime.',
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
          color: const Color(0xFFE2E8F0),
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
                // Top Row: Invoice # + Date
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
                if (v.vehicleNumber != null && v.vehicleNumber!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(Icons.local_shipping_outlined, size: 14, color: Color(0xFF0284C7)),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'Vehicle: ${v.vehicleNumber!}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0369A1),
                          ),
                        ),
                      ),
                      if (v.transporterName != null && v.transporterName!.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '• ${v.transporterName!}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
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

                // Footer Row: Item Count, Total Units, Godowns, Start Scan
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
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () async {
                        final didDispatch = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OutwardScreen(fromTallyVoucher: v),
                          ),
                        );
                        if (didDispatch == true && mounted) {
                          setState(() {
                            _vouchers.removeWhere((x) => x.id == v.id);
                          });
                        }
                        _loadData(showIndicator: false);
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                              style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
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

  void _copyToOutward() async {
    final v = _detail ?? widget.initialSummary;
    Navigator.pop(context, true);
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => OutwardScreen(fromTallyVoucher: v)),
    );
    widget.onStatusChanged();
  }

  Future<void> _deleteVoucher() async {
    final v = _detail ?? widget.initialSummary;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Delete Bill?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text('Are you sure you want to remove bill ${v.voucherNumber}? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Bill'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await _api.deleteTallyVoucher(v.id);
        if (!mounted) return;
        Navigator.pop(context, true);
        widget.onStatusChanged();
        TopToast.show(context, message: 'Bill ${v.voucherNumber} removed.', backgroundColor: const Color(0xFF059669));
      } catch (e) {
        if (!mounted) return;
        TopToast.show(context, message: 'Delete failed: $e', backgroundColor: const Color(0xFFDC2626));
      }
    }
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
                    icon: const Icon(Icons.delete_outline, color: Color(0xFFFCA5A5)),
                    tooltip: 'Delete Bill',
                    onPressed: _deleteVoucher,
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
                        if ((v.vehicleNumber != null && v.vehicleNumber!.isNotEmpty) ||
                            (v.transporterName != null && v.transporterName!.isNotEmpty) ||
                            (v.deliveryNote != null && v.deliveryNote!.isNotEmpty) ||
                            (v.destination != null && v.destination!.isNotEmpty)) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0F9FF),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFBAE6FD)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.local_shipping_rounded, color: Color(0xFF0284C7), size: 22),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'DISPATCH / VEHICLE (FROM TALLY)',
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                                      ),
                                      if (v.vehicleNumber != null && v.vehicleNumber!.isNotEmpty) ...[
                                        const SizedBox(height: 3),
                                        Text(
                                          'Vehicle: ${v.vehicleNumber!}',
                                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Color(0xFF0369A1)),
                                        ),
                                      ],
                                      if (v.transporterName != null && v.transporterName!.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          'Transporter: ${v.transporterName!}',
                                          style: const TextStyle(fontSize: 12, color: Color(0xFF0284C7)),
                                        ),
                                      ],
                                      if (v.deliveryNote != null && v.deliveryNote!.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          'Doc / LR No: ${v.deliveryNote!}',
                                          style: const TextStyle(fontSize: 12, color: Color(0xFF0284C7)),
                                        ),
                                      ],
                                      if (v.destination != null && v.destination!.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          'Destination: ${v.destination!}',
                                          style: const TextStyle(fontSize: 12, color: Color(0xFF0284C7)),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),

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
