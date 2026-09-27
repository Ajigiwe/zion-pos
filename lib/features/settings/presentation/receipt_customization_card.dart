import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/core/database/tables.dart';
import 'package:instrument_pos/core/store_info.dart';
import 'package:instrument_pos/features/auth/presentation/session_provider.dart';
import 'package:instrument_pos/features/sales/domain/receipt.dart';
import 'package:instrument_pos/features/sales/domain/receipt_customization.dart';
import 'package:instrument_pos/features/sales/domain/sale_totals.dart';
import 'package:instrument_pos/features/sales/presentation/receipt_view.dart';
import 'package:instrument_pos/features/settings/presentation/receipt_settings_providers.dart';
import 'package:instrument_pos/features/settings/presentation/store_settings_providers.dart';

class ReceiptCustomizationCard extends ConsumerStatefulWidget {
  const ReceiptCustomizationCard({super.key});

  @override
  ConsumerState<ReceiptCustomizationCard> createState() =>
      _ReceiptCustomizationCardState();
}

class _ReceiptCustomizationCardState
    extends ConsumerState<ReceiptCustomizationCard> {
  final _headerCustomTextController = TextEditingController();
  final _footerMessageController = TextEditingController();

  late bool _showStoreName;
  late bool _showStoreAddress;
  late bool _showStorePhone;
  late bool _showCashierName;
  late bool _showItemPriceMath;
  late bool _showTax;
  late bool _showDiscount;
  late bool _showPaymentBreakdown;
  late bool _showChangeDue;
  late bool _showBarcode;
  late bool _showCustomerSignature;
  late String _paperWidth;
  late double _sideMargin;
  late double _bottomFeedSpace;

  bool _initialized = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _headerCustomTextController.dispose();
    _footerMessageController.dispose();
    super.dispose();
  }

  void _syncFromCustomization(ReceiptCustomization config) {
    _headerCustomTextController.text = config.headerCustomText;
    _footerMessageController.text = config.footerMessage;
    _showStoreName = config.showStoreName;
    _showStoreAddress = config.showStoreAddress;
    _showStorePhone = config.showStorePhone;
    _showCashierName = config.showCashierName;
    _showItemPriceMath = config.showItemPriceMath;
    _showTax = config.showTax;
    _showDiscount = config.showDiscount;
    _showPaymentBreakdown = config.showPaymentBreakdown;
    _showChangeDue = config.showChangeDue;
    _showBarcode = config.showBarcode;
    _showCustomerSignature = config.showCustomerSignature;
    _paperWidth = config.paperWidth;
    _sideMargin = config.sideMargin;
    _bottomFeedSpace = config.bottomFeedSpace;
    _initialized = true;
  }

  ReceiptCustomization _currentEditingConfig() {
    return ReceiptCustomization(
      showStoreName: _showStoreName,
      showStoreAddress: _showStoreAddress,
      showStorePhone: _showStorePhone,
      headerCustomText: _headerCustomTextController.text.trim(),
      showCashierName: _showCashierName,
      showItemPriceMath: _showItemPriceMath,
      showTax: _showTax,
      showDiscount: _showDiscount,
      showPaymentBreakdown: _showPaymentBreakdown,
      showChangeDue: _showChangeDue,
      footerMessage: _footerMessageController.text.trim(),
      showBarcode: _showBarcode,
      showCustomerSignature: _showCustomerSignature,
      paperWidth: _paperWidth,
      sideMargin: _sideMargin,
      bottomFeedSpace: _bottomFeedSpace,
    );
  }

  Future<void> _save() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    setState(() => _isSaving = true);
    try {
      final config = _currentEditingConfig();
      await ref
          .read(receiptCustomizationControllerProvider.notifier)
          .save(config, actingUserId: user.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Receipt customization saved successfully.'),
          backgroundColor: Color(0xFF16A34A),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save settings: $e'),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _openLivePreview() {
    final store = ref.read(storeInfoControllerProvider);
    final editingConfig = _currentEditingConfig();

    final sampleContent = ReceiptContent(
      store: store,
      receiptNumber: 'REC-2026-0089',
      createdAt: DateTime.now(),
      cashierName: ref.read(currentUserProvider)?.displayName ?? 'Jane Doe (Admin)',
      totals: const SaleTotals(
        grossSubtotal: 140.00,
        discount: 10.00,
        taxIncluded: 17.50,
        total: 147.50,
      ),
      lines: const [
        (name: 'Yamaha F310 Acoustic Guitar', quantity: 1, unitPrice: 90.00),
        (name: 'D\'Addario Guitar Strings Set', quantity: 2, unitPrice: 25.00),
      ],
      payments: const [
        PaymentDraft(
          method: PaymentMethod.cash,
          amount: 150.00,
        ),
      ],
      change: 2.50,
      customization: editingConfig,
    );

    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440, maxHeight: 720),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.receipt_long, color: Color(0xFF0284C7)),
                    const SizedBox(width: 8),
                    const Text(
                      'Live Receipt Preview (80mm)',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  color: const Color(0xFFF1F5F9),
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: SingleChildScrollView(
                      child: Container(
                        decoration: BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ReceiptView(content: sampleContent),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Close Preview'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final liveConfig = ref.watch(receiptCustomizationControllerProvider);

    if (!_initialized) {
      _syncFromCustomization(liveConfig);
    }

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
                    color: const Color(0xFF0284C7).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.receipt_long_outlined,
                    color: Color(0xFF0284C7),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Receipt Customization (80mm)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      'Toggle sections and customize text on printed & digital receipts',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _openLivePreview,
                  icon: const Icon(Icons.visibility_outlined, size: 16),
                  label: const Text('Live Preview'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0284C7),
                    side: const BorderSide(color: Color(0xFFBAE6FD)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 16),

            // Section 1: Header
            _buildSectionHeader('Header & Store Branding'),
            const SizedBox(height: 8),
            _buildSwitchTile(
              title: 'Show Store Name',
              subtitle: 'Display the business name at top of receipt',
              value: _showStoreName,
              onChanged: (v) => setState(() => _showStoreName = v),
            ),
            _buildSwitchTile(
              title: 'Show Store Address',
              subtitle: 'Display store physical address from store profile',
              value: _showStoreAddress,
              onChanged: (v) => setState(() => _showStoreAddress = v),
            ),
            _buildSwitchTile(
              title: 'Show Store Phone Number',
              subtitle: 'Display contact number below address',
              value: _showStorePhone,
              onChanged: (v) => setState(() => _showStorePhone = v),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _headerCustomTextController,
              decoration: InputDecoration(
                labelText: 'Header Slogan / Motto (Optional)',
                hintText: 'e.g., Dealers in Quality Musical Instruments & Audio Equipment',
                prefixIcon: const Icon(Icons.format_quote_outlined, size: 18),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
              ),
            ),

            const SizedBox(height: 20),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 16),

            // Section 2: Items & Line Calculation
            _buildSectionHeader('Item & Line Breakdown'),
            const SizedBox(height: 8),
            _buildSwitchTile(
              title: 'Show Cashier Name',
              subtitle: 'Print serving cashier / staff member name',
              value: _showCashierName,
              onChanged: (v) => setState(() => _showCashierName = v),
            ),
            _buildSwitchTile(
              title: 'Show Unit Price Math (Qty × Unit Price)',
              subtitle: 'Display individual unit rates (e.g. 2 x 45.00)',
              value: _showItemPriceMath,
              onChanged: (v) => setState(() => _showItemPriceMath = v),
            ),
            _buildSwitchTile(
              title: 'Show Tax / VAT Line',
              subtitle: 'Display calculated tax row if applicable',
              value: _showTax,
              onChanged: (v) => setState(() => _showTax = v),
            ),
            _buildSwitchTile(
              title: 'Show Discount Line',
              subtitle: 'Display discount savings if applied',
              value: _showDiscount,
              onChanged: (v) => setState(() => _showDiscount = v),
            ),

            const SizedBox(height: 20),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 16),

            // Section 3: Payment & Settlement
            _buildSectionHeader('Payment & Settlement'),
            const SizedBox(height: 8),
            _buildSwitchTile(
              title: 'Show Payment Method Breakdown',
              subtitle: 'List payments made (Cash, MoMo, Card, Split)',
              value: _showPaymentBreakdown,
              onChanged: (v) => setState(() => _showPaymentBreakdown = v),
            ),
            _buildSwitchTile(
              title: 'Show Change Due',
              subtitle: 'Print returned change for cash transactions',
              value: _showChangeDue,
              onChanged: (v) => setState(() => _showChangeDue = v),
            ),

            const SizedBox(height: 20),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 16),

            // Section 4: Footer & Barcode
            _buildSectionHeader('Footer, Barcode & Policy'),
            const SizedBox(height: 8),
            TextField(
              controller: _footerMessageController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Footer Message / Return Policy',
                hintText: 'Goods sold in good condition are not returnable without receipt.\nThank you for your business!',
                prefixIcon: const Icon(Icons.announcement_outlined, size: 18),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            _buildSwitchTile(
              title: 'Show Receipt Barcode (Code128)',
              subtitle: 'Enables instant receipt scanning for returns & audits',
              value: _showBarcode,
              onChanged: (v) => setState(() => _showBarcode = v),
            ),
            _buildSwitchTile(
              title: 'Show Customer Signature Line',
              subtitle: 'For credit/card/signed delivery confirmation',
              value: _showCustomerSignature,
              onChanged: (v) => setState(() => _showCustomerSignature = v),
            ),

            const SizedBox(height: 20),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 16),

            // Section 5: Paper Roll & Margin Calibration
            _buildSectionHeader('Paper Roll & Margin Calibration'),
            const SizedBox(height: 10),
            Text(
              'Paper Roll Width',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: '80mm',
                  label: Text('80mm Standard Roll'),
                  icon: Icon(Icons.receipt_long),
                ),
                ButtonSegment(
                  value: '58mm',
                  label: Text('58mm Slim Roll'),
                  icon: Icon(Icons.receipt),
                ),
              ],
              selected: {_paperWidth},
              onSelectionChanged: (set) {
                if (set.isNotEmpty) {
                  setState(() => _paperWidth = set.first);
                }
              },
            ),
            const SizedBox(height: 16),

            // Side Margin Control
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Printable Side Margin',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Pull text inward if edges get cut off on physical paper',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
                    ),
                  ],
                ),
                Text(
                  '${_sideMargin.toInt()} mm',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            Slider(
              value: _sideMargin.clamp(4.0, 28.0),
              min: 4.0,
              max: 28.0,
              divisions: 24,
              label: '${_sideMargin.toInt()} mm',
              onChanged: (v) => setState(() => _sideMargin = v),
            ),

            const SizedBox(height: 12),

            // Bottom Paper Feed Control
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Bottom Paper Feed Space',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Advance paper past printer tear bar / cutter',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
                    ),
                  ],
                ),
                Text(
                  '${_bottomFeedSpace.toInt()} mm',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            Slider(
              value: _bottomFeedSpace.clamp(20.0, 100.0),
              min: 20.0,
              max: 100.0,
              divisions: 16,
              label: '${_bottomFeedSpace.toInt()} mm',
              onChanged: (v) => setState(() => _bottomFeedSpace = v),
            ),

            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _syncFromCustomization(const ReceiptCustomization());
                    });
                  },
                  child: const Text('Reset to Defaults'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check, size: 18),
                  label: Text(_isSaving ? 'Saving...' : 'Save Receipt Settings'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Color(0xFF334155),
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Color(0xFF0F172A),
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
      ),
      dense: true,
      contentPadding: EdgeInsets.zero,
      activeColor: const Color(0xFF0284C7),
    );
  }
}
