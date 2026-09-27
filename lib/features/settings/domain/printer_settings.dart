/// Configuration for POS receipt printing hardware and active printer target.
class PrinterSettings {
  const PrinterSettings({
    this.selectedPrinterUrl,
    this.selectedPrinterName,
    this.directPrinting = true,
  });

  /// Unique hardware URI / URL of the selected printer (e.g. Windows spooler path or network address).
  /// If null or empty, the operating system default printer is used.
  final String? selectedPrinterUrl;

  /// User-friendly display name of the selected printer.
  final String? selectedPrinterName;

  /// When true, prints receipts directly and silently to the selected printer without dialogs.
  /// When false, opens the native print preview dialog.
  final bool directPrinting;

  PrinterSettings copyWith({
    String? selectedPrinterUrl,
    String? selectedPrinterName,
    bool? directPrinting,
  }) {
    return PrinterSettings(
      selectedPrinterUrl: selectedPrinterUrl ?? this.selectedPrinterUrl,
      selectedPrinterName: selectedPrinterName ?? this.selectedPrinterName,
      directPrinting: directPrinting ?? this.directPrinting,
    );
  }

  bool get usesSystemDefault =>
      selectedPrinterUrl == null || selectedPrinterUrl!.isEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PrinterSettings &&
          runtimeType == other.runtimeType &&
          selectedPrinterUrl == other.selectedPrinterUrl &&
          selectedPrinterName == other.selectedPrinterName &&
          directPrinting == other.directPrinting;

  @override
  int get hashCode =>
      selectedPrinterUrl.hashCode ^
      selectedPrinterName.hashCode ^
      directPrinting.hashCode;
}

abstract final class PrinterSettingKeys {
  static const selectedPrinterUrl = 'printer.selectedUrl';
  static const selectedPrinterName = 'printer.selectedName';
  static const directPrinting = 'printer.directPrinting';

  static const allKeys = [
    selectedPrinterUrl,
    selectedPrinterName,
    directPrinting,
  ];
}
