import 'package:flutter/material.dart';
import '../services/offline_manager.dart';

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final offlineManager = OfflineManager();

    return ValueListenableBuilder<bool>(
      valueListenable: offlineManager.showOfflineWarningNotifier,
      builder: (context, showOfflineWarning, _) {
        return ValueListenableBuilder<int>(
          valueListenable: offlineManager.pendingDispatchCountNotifier,
          builder: (context, pendingCount, _) {
            // Only show offline banner if server has remained continuously unreachable for > 1 minute
            if (showOfflineWarning) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                color: const Color(0xFFB45309), // Amber-700
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off, color: Colors.white, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Server unreachable • Continuing offline',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            offlineManager.serials.isEmpty
                                ? 'Cache empty • Connect to server once to download stock'
                                : pendingCount > 0
                                    ? '${offlineManager.serials.length} serials cached • $pendingCount queued'
                                    : '${offlineManager.serials.length} serials cached • Instant matching',
                            style: const TextStyle(
                              color: Color(0xFFFEF3C7),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    InkWell(
                      onTap: () => offlineManager.checkServerHealth(),
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Retry',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            // If online with pending dispatches, auto-sync queued dispatches quietly in background
            if (offlineManager.isOnline && pendingCount > 0) {
              offlineManager.syncPendingDispatches();
            }

            return const SizedBox.shrink();
          },
        );
      },
    );
  }
}
