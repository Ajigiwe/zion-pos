import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/features/products/data/products_repository.dart';
import 'package:instrument_pos/features/products/domain/product.dart';
import 'package:instrument_pos/features/products/presentation/products_providers.dart';

/// Interactive modal for scanning or inputting product barcodes.
class BarcodeScanDialog extends ConsumerStatefulWidget {
  const BarcodeScanDialog({
    super.key,
    this.title = 'Barcode Scanner',
    this.actionLabel = 'Add to Cart',
    this.onProductSelected,
    this.returnBarcodeOnly = false,
  });

  final String title;
  final String actionLabel;
  final ValueChanged<ProductWithStock>? onProductSelected;
  final bool returnBarcodeOnly;

  static Future<String?> showForBarcode(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => const BarcodeScanDialog(
        title: 'Scan or Enter Barcode',
        actionLabel: 'Use Barcode',
        returnBarcodeOnly: true,
      ),
    );
  }

  static Future<void> showForSales(
    BuildContext context, {
    required ValueChanged<ProductWithStock> onProductSelected,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => BarcodeScanDialog(
        title: 'Scan Barcode / Fast Ring-Up',
        actionLabel: 'Add to Cart',
        onProductSelected: onProductSelected,
      ),
    );
  }

  @override
  ConsumerState<BarcodeScanDialog> createState() => _BarcodeScanDialogState();
}

class _BarcodeScanDialogState extends ConsumerState<BarcodeScanDialog>
    with SingleTickerProviderStateMixin {
  final _barcodeController = TextEditingController();
  final _focusNode = FocusNode();
  ProductWithStock? _matchedProduct;
  bool _searching = false;
  String? _errorMessage;
  late AnimationController _animController;
  late Animation<double> _scanLineAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _scanLineAnimation = Tween<double>(begin: 0.1, end: 0.9).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );

    // Auto-focus barcode text field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _barcodeController.dispose();
    _focusNode.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _lookupBarcode(String query) async {
    final code = query.trim();
    if (code.isEmpty) {
      setState(() {
        _matchedProduct = null;
        _errorMessage = null;
      });
      return;
    }

    if (widget.returnBarcodeOnly) {
      Navigator.of(context).pop(code);
      return;
    }

    setState(() {
      _searching = true;
      _errorMessage = null;
    });

    try {
      final matches =
          await ref.read(productsRepositoryProvider).findByExact(code);
      if (!mounted) return;

      if (matches.isNotEmpty) {
        setState(() {
          _matchedProduct = matches.first;
          _searching = false;
          _errorMessage = null;
        });
      } else {
        setState(() {
          _matchedProduct = null;
          _searching = false;
          _errorMessage = 'No product found with barcode "$code"';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _searching = false;
          _errorMessage = 'Search error: $e';
        });
      }
    }
  }

  void _submitAction() {
    if (widget.returnBarcodeOnly) {
      final code = _barcodeController.text.trim();
      if (code.isNotEmpty) {
        Navigator.of(context).pop(code);
      }
      return;
    }

    if (_matchedProduct != null) {
      widget.onProductSelected?.call(_matchedProduct!);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.qr_code_scanner_rounded,
                      color: colorScheme.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Point USB/Bluetooth scanner or enter barcode',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Visual Scanner Target Box
              Container(
                height: 140,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.primary.withOpacity(0.4),
                    width: 2,
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Corner targeting brackets
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: CustomPaint(
                          painter: _ScannerReticlePainter(
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                    // Animated laser scan line
                    AnimatedBuilder(
                      animation: _scanLineAnimation,
                      builder: (context, child) {
                        return Positioned(
                          top: 140 * _scanLineAnimation.value,
                          left: 24,
                          right: 24,
                          child: Container(
                            height: 2,
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              boxShadow: [
                                BoxShadow(
                                  color: colorScheme.primary.withOpacity(0.8),
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    // Centered Status / Prompt
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.barcode_reader,
                          size: 36,
                          color: Colors.white.withOpacity(0.7),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'READY TO SCAN',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Barcode Input Field
              TextField(
                controller: _barcodeController,
                focusNode: _focusNode,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Barcode / SKU / Item Code',
                  hintText: 'e.g. 8901234567890',
                  prefixIcon: const Icon(Icons.qr_code_rounded),
                  suffixIcon: _barcodeController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            _barcodeController.clear();
                            _lookupBarcode('');
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onChanged: (val) {
                  setState(() {});
                },
                onSubmitted: _lookupBarcode,
              ),

              if (_searching) ...[
                const SizedBox(height: 12),
                const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ],

              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 18, color: Color(0xFFDC2626)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF991B1B),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Matched Product Preview Card
              if (_matchedProduct != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: colorScheme.primary.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.check_circle_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _matchedProduct!.product.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'SKU: ${_matchedProduct!.product.sku}  •  Stock: ${_matchedProduct!.stock.toStringAsFixed(0)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? const Color(0xFF94A3B8)
                                    : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '\$${_matchedProduct!.product.sellingPrice.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _matchedProduct != null ||
                            (widget.returnBarcodeOnly &&
                                _barcodeController.text.trim().isNotEmpty)
                        ? _submitAction
                        : () => _lookupBarcode(_barcodeController.text),
                    icon: Icon(
                      _matchedProduct != null || widget.returnBarcodeOnly
                          ? Icons.check_rounded
                          : Icons.search_rounded,
                      size: 18,
                    ),
                    label: Text(
                      _matchedProduct != null || widget.returnBarcodeOnly
                          ? widget.actionLabel
                          : 'Find Product',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScannerReticlePainter extends CustomPainter {
  const _ScannerReticlePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const cornerLength = 20.0;

    // Top-left
    canvas.drawLine(const Offset(0, 0), const Offset(cornerLength, 0), paint);
    canvas.drawLine(const Offset(0, 0), const Offset(0, cornerLength), paint);

    // Top-right
    canvas.drawLine(
      Offset(size.width, 0),
      Offset(size.width - cornerLength, 0),
      paint,
    );
    canvas.drawLine(
      Offset(size.width, 0),
      Offset(size.width, cornerLength),
      paint,
    );

    // Bottom-left
    canvas.drawLine(
      Offset(0, size.height),
      Offset(cornerLength, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(0, size.height),
      Offset(0, size.height - cornerLength),
      paint,
    );

    // Bottom-right
    canvas.drawLine(
      Offset(size.width, size.height),
      Offset(size.width - cornerLength, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(size.width, size.height),
      Offset(size.width, size.height - cornerLength),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
