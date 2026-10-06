import 'package:flutter/material.dart';
import '../services/offline_queue_service.dart';

class OfflineQueueScreen extends StatefulWidget {
  const OfflineQueueScreen({super.key});

  @override
  State<OfflineQueueScreen> createState() => _OfflineQueueScreenState();
}

class _OfflineQueueScreenState extends State<OfflineQueueScreen> {
  final OfflineQueueService _queue = OfflineQueueService();
  List<QueuedBatch> _batches = [];
  bool _loading = true;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _loadQueue();
  }

  Future<void> _loadQueue() async {
    final list = await _queue.getQueue();
    if (mounted) {
      setState(() {
        _batches = list;
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
        title: Text(
          failed == 0 ? 'Sync Complete!' : 'Sync Report',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Successfully uploaded $synced batch(es).', style: const TextStyle(fontSize: 13)),
            if (failed > 0) ...[
              const SizedBox(height: 8),
              Text('$failed batch(es) failed to sync:', style: const TextStyle(fontSize: 12, color: Color(0xFFE11D48))),
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

  Future<void> _deleteItem(String id) async {
    await _queue.remove(id);
    _loadQueue();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF0F172A),
        title: const Text('Offline Sync Queue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _batches.isEmpty
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
                              '${_batches.length} batch(es) stored locally awaiting upload to server.',
                              style: const TextStyle(fontSize: 12, color: Color(0xFFD97706), fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _batches.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (ctx, idx) {
                          final b = _batches[idx];
                          final isInward = b.type == QueueType.inward;
                          final serials = List.from(b.payload['serial_numbers'] ?? []);

                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: isInward ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    isInward ? Icons.input : Icons.output,
                                    color: isInward ? const Color(0xFF059669) : const Color(0xFFD97706),
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        b.description,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Recorded ${b.createdAt.hour.toString().padLeft(2, '0')}:${b.createdAt.minute.toString().padLeft(2, '0')} • ${serials.length} serials',
                                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 20, color: Color(0xFF94A3B8)),
                                  onPressed: () => _deleteItem(b.id),
                                ),
                              ],
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
                              _syncing ? 'Uploading to Server...' : 'Sync All to Server (${_batches.length})',
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
