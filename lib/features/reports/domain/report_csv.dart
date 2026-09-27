import 'package:instrument_pos/core/database/tables.dart';
import 'package:instrument_pos/features/reports/domain/report_models.dart';
import 'package:instrument_pos/features/sales/domain/sale_totals.dart';

/// Builds the financial-reconciliation CSV (design doc §34):
/// Total Sales, money received per accepted method, refunds per method and
/// Net Sales — the same numbers the Reports page renders.
String buildFinancialCsv(ReportData data) {
  final financial = data.financial;
  String esc(Object? value) {
    final text = value.toString();
    return text.contains(',') ||
            text.contains('"') ||
            text.contains('\n') ||
            text.contains(';')
        ? '"${text.replaceAll('"', '""')}"'
        : text;
  }

  final buffer = StringBuffer()
    ..writeln('Report,Financial reconciliation')
    ..writeln('Period,"${data.range.label}"')
    ..writeln('Generated,"${DateTime.now().toIso8601String()}"')
    ..writeln()
    ..writeln('Metric,Value')
    ..writeln('Total Sales,${financial.grossSales.toStringAsFixed(2)}')
    ..writeln('Discounts Given,${financial.discounts.toStringAsFixed(2)}')
    ..writeln('Sales Completed,${financial.saleCount}')
    ..writeln('Refunds,${financial.refundsTotal.toStringAsFixed(2)}')
    ..writeln('Net Sales,${financial.netSales.toStringAsFixed(2)}')
    ..writeln()
    ..writeln('Payments by Method,Amount,Count');

  for (final method in PaymentMethod.values) {
    final amount = financial.moneyByMethod(method);
    final count = financial.paymentsByMethodCount(method);
    if (amount == 0 && count == 0) continue;
    buffer.writeln('${esc(method.label)},${amount.toStringAsFixed(2)},$count');
  }

  buffer
    ..writeln()
    ..writeln('Refunds by Method,Amount,Count');
  for (final method in PaymentMethod.values) {
    final amount = financial.refundsByMethodTotal(method);
    final count = financial.refundsByMethodCount(method);
    if (amount == 0 && count == 0) continue;
    buffer.writeln('${esc(method.label)},${amount.toStringAsFixed(2)},$count');
  }

  return buffer.toString();
}

/// Builds a CSV of one breakdown table (cashier or product sections).
String buildBreakdownCsv({
  required String title,
  required List<List<String>> rows,
  required List<String> headers,
}) {
  String esc(Object? value) {
    final text = value.toString();
    return text.contains(',') ||
            text.contains('"') ||
            text.contains('\n') ||
            text.contains(';')
        ? '"${text.replaceAll('"', '""')}"'
        : text;
  }

  final buffer = StringBuffer()
    ..writeln(title)
    ..writeln(headers.map(esc).join(','));
  for (final row in rows) {
    buffer.writeln(row.map(esc).join(','));
  }
  return buffer.toString();
}
