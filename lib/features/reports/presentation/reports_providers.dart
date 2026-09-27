import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/core/database/database_provider.dart';
import 'package:instrument_pos/features/reports/data/reports_repository.dart';
import 'package:instrument_pos/features/reports/domain/report_models.dart';
import 'package:instrument_pos/features/reports/presentation/report_export_service.dart';

final reportsRepositoryProvider = Provider<ReportsRepository>((ref) {
  return ReportsRepository(ref.watch(databaseProvider));
});

final reportExportServiceProvider = Provider<ReportExportService>((ref) {
  return DesktopReportExportService();
});

/// The range currently selected on the Reports page.
class SelectedReportRange extends Notifier<TimelineRange> {
  @override
  TimelineRange build() => TimelineRange.today;

  void select(TimelineRange range) => state = range;
}

final selectedReportRangeProvider =
    NotifierProvider<SelectedReportRange, TimelineRange>(
      SelectedReportRange.new,
    );

/// Report data for the selected range. Auto-disposed so switching ranges or
/// reopening the page always re-reads fresh ledger numbers.
final reportDataProvider = FutureProvider.autoDispose<ReportData>((ref) {
  final range = ref.watch(selectedReportRangeProvider).resolve(DateTime.now());
  return ref.watch(reportsRepositoryProvider).load(range);
});
