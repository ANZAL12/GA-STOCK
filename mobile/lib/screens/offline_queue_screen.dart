import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/offline_queue_service.dart';
import '../widgets/responsive_utils.dart';

class OfflineQueueScreen extends StatefulWidget {
  const OfflineQueueScreen({super.key});

  @override
  State<OfflineQueueScreen> createState() => _OfflineQueueScreenState();
}

class _OfflineQueueScreenState extends State<OfflineQueueScreen> {
  final OfflineQueueService _queue = OfflineQueueService();
  List<QueuedBatch> _batches = [];
  List<QueuedProduct> _pendingProducts = [];
  List<QueuedShop> _pendingShops = [];
  bool _loading = true;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _loadQueue();
  }

  Future<void> _loadQueue() async {
    final list = await _queue.getQueue();
    final prods = await _queue.getPendingProducts();
    final shops = await _queue.getPendingShops();
    if (mounted) {
      setState(() {
        _batches = list;
        _pendingProducts = prods;
        _pendingShops = shops;
        _loading = false;
      });
    }
  }

  Future<void> _triggerSync() async {
    setState(() => _syncing = true);

    final res = await _queue.syncAll();
    await _loadQueue();

    if (!mounted) return;
    setState(() => _syncing = false);

    final synced = res['synced'] ?? 0;
    final failed = res['failed'] ?? 0;
    final List errors = res['errors'] ?? [];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              failed == 0 ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
              color: failed == 0 ? const Color(0xFF059669) : const Color(0xFFE11D48),
            ),
            const SizedBox(width: 8),
            Text(
              failed == 0 ? 'Sync Complete!' : 'Sync Report',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Successfully uploaded $synced batch(es).', style: const TextStyle(fontSize: 13)),
            if (failed > 0) ...[
              const SizedBox(height: 8),
              Text(
                '$failed batch(es) failed to sync:',
                style: const TextStyle(fontSize: 12, color: Color(0xFFE11D48), fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              for (final err in errors)
                Text('• $err', style: const TextStyle(fontSize: 11, color: Color(0xFFE11D48))),
            ],
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E1B4B)),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteBatch(QueuedBatch batch) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: Color(0xFFE11D48)),
            SizedBox(width: 8),
            Text('Delete Queued Batch?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${batch.description}"?\n\nAll ${batch.totalSerialsCount} scanned serial numbers in this batch will be permanently removed from this device\'s offline queue.',
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE11D48)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Batch', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _queue.remove(batch.id);
      await _loadQueue();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Offline batch deleted from queue.')),
        );
      }
    }
  }

  void _openBatchDetails(QueuedBatch batch) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _BatchDetailsSheet(
        batch: batch,
        onBatchChanged: () async {
          await _loadQueue();
        },
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year;
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/$y at $h:$min';
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = context.isTablet;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF0F172A),
        title: const Text('Offline Sync Queue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          if (_batches.isNotEmpty || _pendingProducts.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 22),
              tooltip: 'Refresh Queue',
              onPressed: _loadQueue,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_batches.isEmpty && _pendingProducts.isEmpty && _pendingShops.isEmpty)
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.cloud_done_outlined, size: 56, color: Colors.grey[300]),
                      const SizedBox(height: 12),
                      const Text(
                        'All clear! No offline scans in queue.',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B), fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Scans recorded without Wi-Fi will appear here.',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      color: const Color(0xFFFFFBEB),
                      child: Row(
                        children: [
                          const Icon(Icons.wifi_off, size: 18, color: Color(0xFFD97706)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              () {
                                final parts = <String>[];
                                if (_pendingProducts.isNotEmpty) parts.add('${_pendingProducts.length} new model(s)');
                                if (_pendingShops.isNotEmpty) parts.add('${_pendingShops.length} new shop(s)');
                                parts.add('${_batches.length} batch(es)');
                                return '${parts.join(" & ")} stored locally awaiting upload to server.';
                              }(),
                              style: const TextStyle(fontSize: 12, color: Color(0xFFD97706), fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_pendingProducts.isNotEmpty)
                      Container(
                        margin: EdgeInsets.symmetric(
                          horizontal: isTablet ? 32 : 16,
                          vertical: 6,
                        ),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFBBF7D0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.inventory_2_outlined, size: 16, color: Color(0xFF15803D)),
                                const SizedBox(width: 6),
                                Text(
                                  'Offline-Created Models (${_pendingProducts.length})',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF15803D)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ..._pendingProducts.map((p) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  const Icon(Icons.arrow_right, size: 16, color: Color(0xFF16A34A)),
                                  Expanded(
                                    child: Text(
                                      '${p.brand} ${p.model} (${p.categoryName ?? "General"})',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF166534)),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFDCFCE7),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text('Pending Sync', style: TextStyle(fontSize: 10, color: Color(0xFF15803D), fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            )),
                          ],
                        ),
                      ),
                    if (_pendingShops.isNotEmpty)
                      Container(
                        margin: EdgeInsets.symmetric(
                          horizontal: isTablet ? 32 : 16,
                          vertical: 6,
                        ),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F9FF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFBAE6FD)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.storefront_outlined, size: 16, color: Color(0xFF0369A1)),
                                const SizedBox(width: 6),
                                Text(
                                  'Offline-Created Shops (${_pendingShops.length})',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0369A1)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ..._pendingShops.map((s) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  const Icon(Icons.arrow_right, size: 16, color: Color(0xFF0284C7)),
                                  Expanded(
                                    child: Text(
                                      s.city.trim().isNotEmpty ? '${s.name} (${s.city.trim()})' : s.name,
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF075985)),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE0F2FE),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text('Pending Sync', style: TextStyle(fontSize: 10, color: Color(0xFF0369A1), fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            )),
                          ],
                        ),
                      ),
                    Expanded(
                      child: ListView.separated(
                        padding: EdgeInsets.symmetric(
                          horizontal: isTablet ? 32 : 16,
                          vertical: 16,
                        ),
                        itemCount: _batches.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (ctx, idx) {
                          final b = _batches[idx];
                          final isInward = b.type == QueueType.inward;
                          final serialCount = b.totalSerialsCount;

                          return Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            elevation: 0,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => _openBatchDetails(b),
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            color: isInward ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Icon(
                                            isInward ? Icons.input_rounded : Icons.output_rounded,
                                            color: isInward ? const Color(0xFF059669) : const Color(0xFFD97706),
                                            size: 22,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: isInward ? const Color(0xFFECFDF5) : const Color(0xFFFFF7ED),
                                                      borderRadius: BorderRadius.circular(6),
                                                      border: Border.all(
                                                        color: isInward ? const Color(0xFFA7F3D0) : const Color(0xFFFFEDD5),
                                                      ),
                                                    ),
                                                    child: Text(
                                                      isInward ? 'INWARD BATCH' : 'OUTWARD DISPATCH',
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.bold,
                                                        color: isInward ? const Color(0xFF047857) : const Color(0xFFC2410C),
                                                      ),
                                                    ),
                                                  ),
                                                  const Spacer(),
                                                  IconButton(
                                                    icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Color(0xFF94A3B8)),
                                                    tooltip: 'Delete batch',
                                                    padding: EdgeInsets.zero,
                                                    constraints: const BoxConstraints(),
                                                    onPressed: () => _confirmDeleteBatch(b),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                b.description,
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Recorded ${_formatDateTime(b.createdAt)}',
                                                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    const Divider(height: 1, color: Color(0xFFF1F5F9)),
                                    const SizedBox(height: 10),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF1F5F9),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.qr_code_rounded, size: 14, color: Color(0xFF475569)),
                                              const SizedBox(width: 6),
                                              Text(
                                                '$serialCount serial(s) scanned',
                                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              'Tap to view serials',
                                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF2563EB)),
                                            ),
                                            SizedBox(width: 4),
                                            Icon(Icons.arrow_forward_ios_rounded, size: 12, color: Color(0xFF2563EB)),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                      ),
                      child: SafeArea(
                        child: SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 0,
                            ),
                            icon: _syncing
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                  )
                                : const Icon(Icons.cloud_upload_outlined, size: 20),
                            label: Text(
                              _syncing ? 'Uploading to Server...' : 'Sync All to Server (${_batches.length + _pendingProducts.length + _pendingShops.length})',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            onPressed: _syncing ? null : _triggerSync,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _BatchDetailsSheet extends StatefulWidget {
  final QueuedBatch batch;
  final VoidCallback onBatchChanged;

  const _BatchDetailsSheet({
    required this.batch,
    required this.onBatchChanged,
  });

  @override
  State<_BatchDetailsSheet> createState() => _BatchDetailsSheetState();
}

class _BatchDetailsSheetState extends State<_BatchDetailsSheet> {
  final OfflineQueueService _queue = OfflineQueueService();
  late QueuedBatch _batch;
  String _searchQuery = '';
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _batch = widget.batch;
  }

  Future<void> _syncThisBatch() async {
    setState(() => _isSyncing = true);
    try {
      await _queue.syncSingle(_batch.id);
      widget.onBatchChanged();
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Batch uploaded and synced successfully!'),
          backgroundColor: Color(0xFF059669),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSyncing = false);
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.error_outline_rounded, color: Color(0xFFE11D48)),
              SizedBox(width: 8),
              Text('Sync Failed'),
            ],
          ),
          content: Text(
            e.toString().replaceAll('Exception: ', ''),
            style: const TextStyle(fontSize: 13),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E1B4B)),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _removeSerial(QueuedSerialDetail item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove Serial?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text(
          'Remove serial "${item.serialNumber}" from this offline queued batch?',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE11D48)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final updated = _batch.removeSerial(item.serialNumber);
      await _queue.update(updated);
      widget.onBatchChanged();

      if (updated.totalSerialsCount == 0) {
        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All serials removed. Empty batch cleared from queue.')),
        );
      } else {
        if (mounted) {
          setState(() => _batch = updated);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Removed ${item.serialNumber}')),
          );
        }
      }
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied "$text" to clipboard'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year;
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/$y at $h:$min';
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = context.isTablet;
    final isInward = _batch.type == QueueType.inward;
    final allSerials = _batch.serialDetails;

    final filteredSerials = _searchQuery.isEmpty
        ? allSerials
        : allSerials.where((s) {
            final q = _searchQuery.toLowerCase();
            return s.serialNumber.toLowerCase().contains(q) ||
                s.productName.toLowerCase().contains(q) ||
                s.model.toLowerCase().contains(q) ||
                s.brand.toLowerCase().contains(q);
          }).toList();

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isInward ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isInward ? Icons.input_rounded : Icons.output_rounded,
                    color: isInward ? const Color(0xFF059669) : const Color(0xFFD97706),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isInward ? 'Inward Stock Batch' : 'Outward Dispatch Batch',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _batch.description,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 24, color: Color(0xFF64748B)),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFFE2E8F0)),

          // Scrollable Body
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(
                horizontal: isTablet ? 32 : 16,
                vertical: 14,
              ),
              children: [
                // Batch Details Meta Card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFFBEB),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFFDE68A)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.cloud_off_rounded, size: 12, color: Color(0xFFD97706)),
                                SizedBox(width: 4),
                                Text(
                                  'OFFLINE QUEUED',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFB45309)),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            _formatDateTime(_batch.createdAt),
                            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (!isInward && _batch.shopName.isNotEmpty) ...[
                        _buildMetaRow(Icons.storefront_rounded, 'Destination Shop', _batch.shopName),
                        const SizedBox(height: 6),
                      ],
                      if (!isInward && _batch.billNumber != null && _batch.billNumber!.isNotEmpty) ...[
                        _buildMetaRow(Icons.receipt_long_rounded, 'Bill Number', _batch.billNumber!),
                        const SizedBox(height: 6),
                      ],
                      if (_batch.deliveryReference != null && _batch.deliveryReference!.isNotEmpty) ...[
                        _buildMetaRow(Icons.local_shipping_outlined, 'Delivery Ref', _batch.deliveryReference!),
                        const SizedBox(height: 6),
                      ],
                      if (_batch.invoiceReference != null && _batch.invoiceReference!.isNotEmpty) ...[
                        _buildMetaRow(Icons.description_outlined, 'Invoice Ref', _batch.invoiceReference!),
                        const SizedBox(height: 6),
                      ],
                      if (isInward && _batch.inwardType != null) ...[
                        _buildMetaRow(
                          Icons.category_outlined,
                          'Inward Type',
                          _batch.inwardType == 'damaged'
                              ? 'Damaged Stock'
                              : _batch.inwardType == 'return'
                                  ? 'Customer / Shop Return'
                                  : 'New Stock Inward',
                        ),
                        const SizedBox(height: 6),
                      ],
                      if (_batch.remarks != null && _batch.remarks!.isNotEmpty) ...[
                        _buildMetaRow(Icons.comment_outlined, 'Remarks', _batch.remarks!),
                        const SizedBox(height: 6),
                      ],
                      _buildMetaRow(
                        Icons.numbers_rounded,
                        'Total Serials Scanned',
                        '${allSerials.length} unit(s)',
                        isHighlight: true,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Scanned Serials Header & Search
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Scanned Serials',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A)),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2563EB),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${allSerials.length}',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                    if (filteredSerials.length != allSerials.length)
                      Text(
                        'Showing ${filteredSerials.length} of ${allSerials.length}',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                      ),
                  ],
                ),

                const SizedBox(height: 10),

                // Search Box
                TextField(
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                  decoration: InputDecoration(
                    hintText: 'Search serial number or model...',
                    hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                    prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF64748B)),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () => setState(() => _searchQuery = ''),
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // List of serial cards
                if (filteredSerials.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    alignment: Alignment.center,
                    child: Text(
                      _searchQuery.isEmpty ? 'No serial numbers in this batch.' : 'No serial matching "$_searchQuery".',
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                    ),
                  )
                else
                  ...filteredSerials.map((s) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '#${s.index}',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        s.serialNumber,
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: Color(0xFF0F172A),
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                    if (s.unitType != null)
                                      Container(
                                        margin: const EdgeInsets.only(right: 6),
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: s.unitType!.toLowerCase() == 'indoor'
                                              ? const Color(0xFFF3E8FF)
                                              : const Color(0xFFCCFBF1),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          s.unitType!.toUpperCase(),
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: s.unitType!.toLowerCase() == 'indoor'
                                                ? const Color(0xFF7E22CE)
                                                : const Color(0xFF0F766E),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${s.brand.isNotEmpty ? "${s.brand} • " : ""}${s.model.isNotEmpty ? s.model : s.productName}',
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 18, color: Color(0xFF64748B)),
                            tooltip: 'Copy serial number',
                            onPressed: () => _copyToClipboard(s.serialNumber),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFFEF4444)),
                            tooltip: 'Remove serial from batch',
                            onPressed: () => _removeSerial(s),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),

          // Bottom Action Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF64748B),
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      icon: _isSyncing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_upload_outlined, size: 18),
                      label: Text(
                        _isSyncing ? 'Uploading...' : 'Sync This Batch Now',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: _isSyncing ? null : _syncThisBatch,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaRow(IconData icon, String label, String value, {bool isHighlight = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: isHighlight ? const Color(0xFF2563EB) : const Color(0xFF64748B)),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 12,
            fontWeight: isHighlight ? FontWeight.bold : FontWeight.w500,
            color: isHighlight ? const Color(0xFF1E293B) : const Color(0xFF64748B),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isHighlight ? const Color(0xFF2563EB) : const Color(0xFF0F172A),
            ),
          ),
        ),
      ],
    );
  }
}
