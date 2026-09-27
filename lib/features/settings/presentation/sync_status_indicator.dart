import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/core/database/lan_sync_service.dart';
import 'package:instrument_pos/features/settings/presentation/network_settings_providers.dart';

/// Live sync state for a client terminal: green with the last successful
/// cycle, red with the exact reason the host is not answering.
///
/// The heartbeat that makes the host list this terminal as "connected" is the
/// only public endpoint — if the authenticated sync calls fail, everything
/// still *looks* fine while no data moves. This indicator is deliberately
/// hard to miss: it sits under the login form and in the sidebar of every
/// page.
class SyncStatusIndicator extends ConsumerWidget {
  const SyncStatusIndicator({super.key, this.compact = false});

  /// Tighter padding for the login card.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(networkSettingsControllerProvider);
    if (!settings.isClient) return const SizedBox.shrink();

    final sync = ref.watch(lanSyncServiceProvider);
    return ValueListenableBuilder<bool>(
      valueListenable: sync.isOnlineNotifier,
      builder: (context, online, _) => ValueListenableBuilder<String>(
        valueListenable: sync.statusNotifier,
        builder: (context, status, _) => ValueListenableBuilder<int>(
          valueListenable: sync.pendingSyncCountNotifier,
          builder: (context, pending, _) {
            final foreground = online
                ? const Color(0xFF15803D)
                : const Color(0xFFB91C1C);
            return Tooltip(
              message: status,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: compact ? 6 : 8,
                ),
                decoration: BoxDecoration(
                  color: online ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: online ? const Color(0xFF86EFAC) : const Color(0xFFFECACA),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: online
                            ? const Color(0xFF16A34A)
                            : const Color(0xFFDC2626),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        status,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                          color: foreground,
                        ),
                      ),
                    ),
                    if (pending > 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        '$pending waiting',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF92400E),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
