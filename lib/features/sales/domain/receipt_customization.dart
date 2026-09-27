/// Customization options for 80 mm / 58 mm thermal receipts and on-screen receipt views.
class ReceiptCustomization {
  const ReceiptCustomization({
    this.showStoreName = true,
    this.showStoreAddress = true,
    this.showStorePhone = true,
    this.headerCustomText = 'Dealers in Quality Musical Instruments & Audio Equipment',
    this.showCashierName = true,
    this.showItemPriceMath = true,
    this.showTax = true,
    this.showDiscount = true,
    this.showPaymentBreakdown = true,
    this.showChangeDue = true,
    this.footerMessage =
        'Goods sold in good condition are not returnable without receipt.\nThank you for your business!',
    this.showBarcode = true,
    this.showCustomerSignature = false,
    this.paperWidth = '80mm',
    this.sideMargin = 14.0,
    this.bottomFeedSpace = 50.0,
  });

  final bool showStoreName;
  final bool showStoreAddress;
  final bool showStorePhone;
  final String headerCustomText;
  final bool showCashierName;
  final bool showItemPriceMath;
  final bool showTax;
  final bool showDiscount;
  final bool showPaymentBreakdown;
  final bool showChangeDue;
  final String footerMessage;
  final bool showBarcode;
  final bool showCustomerSignature;

  /// Thermal roll paper width: '80mm' or '58mm'.
  final String paperWidth;

  /// Horizontal printable side margin in pt/mm (default 14.0, range 4.0 – 28.0).
  /// Increase to pull text inward and prevent clipping on physical printer hardware edges.
  final double sideMargin;

  /// Trailing blank paper feed in pt/mm (default 50.0, range 20.0 – 100.0).
  /// Advances paper past the printer's tear bar / cutter so barcodes aren't cut off or stuck inside.
  final double bottomFeedSpace;

  ReceiptCustomization copyWith({
    bool? showStoreName,
    bool? showStoreAddress,
    bool? showStorePhone,
    String? headerCustomText,
    bool? showCashierName,
    bool? showItemPriceMath,
    bool? showTax,
    bool? showDiscount,
    bool? showPaymentBreakdown,
    bool? showChangeDue,
    String? footerMessage,
    bool? showBarcode,
    bool? showCustomerSignature,
    String? paperWidth,
    double? sideMargin,
    double? bottomFeedSpace,
  }) {
    return ReceiptCustomization(
      showStoreName: showStoreName ?? this.showStoreName,
      showStoreAddress: showStoreAddress ?? this.showStoreAddress,
      showStorePhone: showStorePhone ?? this.showStorePhone,
      headerCustomText: headerCustomText ?? this.headerCustomText,
      showCashierName: showCashierName ?? this.showCashierName,
      showItemPriceMath: showItemPriceMath ?? this.showItemPriceMath,
      showTax: showTax ?? this.showTax,
      showDiscount: showDiscount ?? this.showDiscount,
      showPaymentBreakdown: showPaymentBreakdown ?? this.showPaymentBreakdown,
      showChangeDue: showChangeDue ?? this.showChangeDue,
      footerMessage: footerMessage ?? this.footerMessage,
      showBarcode: showBarcode ?? this.showBarcode,
      showCustomerSignature:
          showCustomerSignature ?? this.showCustomerSignature,
      paperWidth: paperWidth ?? this.paperWidth,
      sideMargin: sideMargin ?? this.sideMargin,
      bottomFeedSpace: bottomFeedSpace ?? this.bottomFeedSpace,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReceiptCustomization &&
          runtimeType == other.runtimeType &&
          showStoreName == other.showStoreName &&
          showStoreAddress == other.showStoreAddress &&
          showStorePhone == other.showStorePhone &&
          headerCustomText == other.headerCustomText &&
          showCashierName == other.showCashierName &&
          showItemPriceMath == other.showItemPriceMath &&
          showTax == other.showTax &&
          showDiscount == other.showDiscount &&
          showPaymentBreakdown == other.showPaymentBreakdown &&
          showChangeDue == other.showChangeDue &&
          footerMessage == other.footerMessage &&
          showBarcode == other.showBarcode &&
          showCustomerSignature == other.showCustomerSignature &&
          paperWidth == other.paperWidth &&
          sideMargin == other.sideMargin &&
          bottomFeedSpace == other.bottomFeedSpace;

  @override
  int get hashCode => Object.hash(
    showStoreName,
    showStoreAddress,
    showStorePhone,
    headerCustomText,
    showCashierName,
    showItemPriceMath,
    showTax,
    showDiscount,
    showPaymentBreakdown,
    showChangeDue,
    footerMessage,
    showBarcode,
    showCustomerSignature,
    paperWidth,
    sideMargin,
    bottomFeedSpace,
  );
}

/// Setting keys used in SQLite `settings` table.
abstract final class ReceiptSettingKeys {
  static const showStoreName = 'receipt.showStoreName';
  static const showStoreAddress = 'receipt.showStoreAddress';
  static const showStorePhone = 'receipt.showStorePhone';
  static const headerCustomText = 'receipt.headerCustomText';
  static const showCashierName = 'receipt.showCashierName';
  static const showItemPriceMath = 'receipt.showItemPriceMath';
  static const showTax = 'receipt.showTax';
  static const showDiscount = 'receipt.showDiscount';
  static const showPaymentBreakdown = 'receipt.showPaymentBreakdown';
  static const showChangeDue = 'receipt.showChangeDue';
  static const footerMessage = 'receipt.footerMessage';
  static const showBarcode = 'receipt.showBarcode';
  static const showCustomerSignature = 'receipt.showCustomerSignature';
  static const paperWidth = 'receipt.paperWidth';
  static const sideMargin = 'receipt.sideMargin';
  static const bottomFeedSpace = 'receipt.bottomFeedSpace';

  static const allKeys = [
    showStoreName,
    showStoreAddress,
    showStorePhone,
    headerCustomText,
    showCashierName,
    showItemPriceMath,
    showTax,
    showDiscount,
    showPaymentBreakdown,
    showChangeDue,
    footerMessage,
    showBarcode,
    showCustomerSignature,
    paperWidth,
    sideMargin,
    bottomFeedSpace,
  ];
}
