import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/core/database/database_provider.dart';
import 'package:instrument_pos/features/settings/data/database_backup_service.dart';

/// Backups open a throwaway connection to the live file, so the service is
/// built from the same [databaseProvider] instance the app uses.
final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(ref.watch(databaseProvider));
});

/// File dialogs for backup/restore, abstracted so widget tests can fake them.
abstract class BackupFileService {
  /// Save-location for an export. Null when cancelled.
  Future<String?> pickBackupDestination();

  /// Open dialog for a backup file to restore. Null when cancelled.
  Future<String?> pickBackupSource();
}

class DesktopBackupFileService implements BackupFileService {
  static const _database = XTypeGroup(
    label: 'SQLite database',
    extensions: ['db', 'sqlite', 'sqlite3'],
  );

  @override
  Future<String?> pickBackupDestination() async {
    final location = await getSaveLocation(
      suggestedName: 'instrument_pos_backup_${_stamp()}.db',
      acceptedTypeGroups: const [_database],
    );
    if (location == null) return null;
    var path = location.path;
    if (!_hasDatabaseExtension(path)) path = '$path.db';
    return path;
  }

  @override
  Future<String?> pickBackupSource() async {
    final file = await openFile(acceptedTypeGroups: const [_database]);
    return file?.path;
  }

  static bool _hasDatabaseExtension(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.db') ||
        lower.endsWith('.sqlite') ||
        lower.endsWith('.sqlite3');
  }

  static String _stamp() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}';
  }
}

final backupFileServiceProvider = Provider<BackupFileService>((ref) {
  return DesktopBackupFileService();
});
