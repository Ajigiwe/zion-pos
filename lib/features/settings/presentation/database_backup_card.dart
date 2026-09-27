import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/core/database/database_provider.dart';
import 'package:instrument_pos/features/auth/presentation/session_provider.dart';
import 'package:instrument_pos/features/settings/data/database_backup_service.dart';
import 'package:instrument_pos/features/settings/presentation/backup_providers.dart';

/// Local backup/export and restore (§29). Export writes a consistent SQLite
/// snapshot through a save dialog; restore swaps the live database file and
/// restarts the app, so the whole screen resets into the login page.
class DatabaseBackupCard extends ConsumerStatefulWidget {
  const DatabaseBackupCard({super.key});

  @override
  ConsumerState<DatabaseBackupCard> createState() => _DatabaseBackupCardState();
}

class _DatabaseBackupCardState extends ConsumerState<DatabaseBackupCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.storage_outlined,
                    color: Color(0xFF059669),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Database backup',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Export a copy of the local database, or replace this device’s '
                        'data from a backup (§29).',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _exportBackup,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_alt, size: 18),
                  label: const Text('Export backup…'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _confirmRestore,
                  icon: const Icon(Icons.settings_backup_restore, size: 18),
                  label: const Text('Restore from backup…'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    side: const BorderSide(color: Color(0xFFFECACA)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _confirmWipeData,
                  icon: const Icon(Icons.delete_forever_outlined, size: 18),
                  label: const Text('Wipe all data…'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade800,
                    side: BorderSide(color: Colors.red.shade300),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _exportBackup() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    setState(() => _busy = true);
    try {
      final destination = await ref
          .read(backupFileServiceProvider)
          .pickBackupDestination();
      if (destination == null) return;
      await ref
          .read(backupServiceProvider)
          .exportBackup(destinationPath: destination, actingUserId: user.id);
      _snack('Backup saved.');
    } on BackupException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmRestore() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber, color: Color(0xFFB26A00)),
        title: const Text('Restore database?'),
        content: const Text(
          'Restoring replaces ALL data on this device (sales, products, '
          'stock, users and settings) with the contents of the backup file. '
          'You will be signed out and the app will restart.\n\n'
          'Consider exporting a backup of the current data first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _restoreDatabase(user.username);
  }

  Future<void> _restoreDatabase(String actingUsername) async {
    setState(() => _busy = true);
    try {
      final service = ref.read(backupServiceProvider);
      final db = ref.read(databaseProvider);
      final currentPath = await service.currentDatabasePath();
      if (currentPath.isEmpty) {
        _snack('This database cannot be restored (in-memory).');
        return;
      }
      final sourcePath = await ref
          .read(backupFileServiceProvider)
          .pickBackupSource();
      if (sourcePath == null) return;
      await restoreDatabaseFromBackup(
        db: db,
        currentPath: currentPath,
        sourcePath: sourcePath,
        actingUsername: actingUsername,
      );
      // On success the app restarts here; nothing further is shown.
    } on BackupException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmWipeData() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_rounded, color: Colors.red, size: 36),
        title: const Text('Wipe all data & reset store?'),
        content: const Text(
          'This will permanently erase ALL sales, stock history, products, '
          'categories, and audit logs.\n\n'
          'Mandatory Backup:\n'
          'A full database backup will automatically be exported and saved to your device BEFORE '
          'any data is wiped, ensuring you never lose your records.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Backup & Wipe All Data'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await _wipeData(user.id, user.username);
  }

  Future<void> _wipeData(String userId, String username) async {
    setState(() => _busy = true);
    try {
      final destination = await ref
          .read(backupFileServiceProvider)
          .pickBackupDestination();
      if (destination == null) return;

      await ref.read(backupServiceProvider).wipeDataWithBackup(
            backupDestinationPath: destination,
            actingUserId: userId,
            actingUsername: username,
          );
      _snack('Backup saved. All data wiped successfully.');
    } on BackupException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
