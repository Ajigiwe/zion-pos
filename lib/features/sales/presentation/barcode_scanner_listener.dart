import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A widget that listens for keyboard-wedge barcode scanner input bursts.
///
/// Physical USB and Bluetooth barcode scanners emit characters rapidly in succession
/// followed by an Enter key. This widget captures those events and invokes [onBarcodeScanned].
class BarcodeScannerListener extends StatefulWidget {
  const BarcodeScannerListener({
    super.key,
    required this.child,
    required this.onBarcodeScanned,
    this.bufferTimeout = const Duration(milliseconds: 100),
    this.enabled = true,
  });

  final Widget child;
  final ValueChanged<String> onBarcodeScanned;
  final Duration bufferTimeout;
  final bool enabled;

  @override
  State<BarcodeScannerListener> createState() => _BarcodeScannerListenerState();
}

class _BarcodeScannerListenerState extends State<BarcodeScannerListener> {
  final StringBuffer _buffer = StringBuffer();
  DateTime _lastEventTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (!widget.enabled || !mounted) return false;

    // Only process KeyDown events
    if (event is! KeyDownEvent) return false;

    final now = DateTime.now();
    final elapsed = now.difference(_lastEventTime);
    _lastEventTime = now;

    // If too much time has passed between keystrokes, reset the buffer
    if (elapsed > widget.bufferTimeout) {
      _buffer.clear();
    }

    // Check for Enter key finishing the scan
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      final code = _buffer.toString().trim();
      _buffer.clear();

      // Only trigger if we collected at least 2 characters in a fast burst
      if (code.length >= 2) {
        widget.onBarcodeScanned(code);
        return true;
      }
      return false;
    }

    // Capture printable character
    final char = event.character;
    if (char != null && char.isNotEmpty && !char.contains(RegExp(r'[\r\n\t]'))) {
      _buffer.write(char);
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
