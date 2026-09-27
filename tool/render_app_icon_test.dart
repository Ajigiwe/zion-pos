// One-off generator for the Zion Musical Centre app icon.
//
// Renders a beamed-eighth-notes mark on a rounded gradient tile with dart:ui,
// then packs PNGs into a multi-size ICO and writes:
//   windows/runner/resources/app_icon.ico  (embedded by Runner.rc)
//   tool/app_icon_512.png                  (master, for reuse)
//
// Run with:  cd client && flutter test tool/render_app_icon_test.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

const _canvasSize = 512.0;
const _sizes = [16, 24, 32, 48, 64, 128, 256];

final _white = ui.Paint()..color = const ui.Color(0xFFFFFFFF);

void _drawNoteHeadsAndBeam(ui.Canvas canvas) {
  // Two eighth-note heads, stems, and a single connecting beam.
  // Drawn in a 512-space with the group already translated/rotated.
  for (final dx in [-86.0, 86.0]) {
    canvas.save();
    canvas.translate(dx, 0);
    canvas.rotate(-0.32);
    final head = ui.Path()
      ..addOval(
        ui.Rect.fromCenter(center: ui.Offset.zero, width: 64, height: 46),
      );
    canvas.drawPath(head, _white);
    canvas.restore();
  }
  // Stems: from just above each head up to the beam.
  for (final dx in [-65.0, 47.0]) {
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        ui.Rect.fromLTWH(dx, -190, 18, 184),
        const ui.Radius.circular(9),
      ),
      _white,
    );
  }
  // Beam across the stem tops.
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(
      ui.Rect.fromLTWH(-65, -190, 130, 40),
      const ui.Radius.circular(20),
    ),
    _white,
  );
}

void _drawIcon(ui.Canvas canvas) {
  // Rounded gradient tile.
  final tile = ui.RRect.fromRectAndRadius(
    ui.Rect.fromLTWH(0, 0, _canvasSize, _canvasSize),
    const ui.Radius.circular(112),
  );
  final bg = ui.Paint()
    ..shader = ui.Gradient.linear(
      ui.Offset(0, 0),
      ui.Offset(0, _canvasSize),
      const [ui.Color(0xFF191342), ui.Color(0xFF3B1D78), ui.Color(0xFF6D28D9)],
      const [0.0, 0.55, 1.0],
    );
  canvas.drawRRect(tile, bg);

  // Soft glow behind the notes.
  final glow = ui.Paint()
    ..shader = ui.Gradient.radial(const ui.Offset(256, 290), 240, const [
      ui.Color(0x33FFFFFF),
      ui.Color(0x00FFFFFF),
    ]);
  canvas.drawCircle(const ui.Offset(256, 290), 240, glow);

  // Drop shadow under the note group, then the notes themselves.
  canvas.save();
  canvas.translate(256, 296);
  canvas.rotate(-0.10);
  canvas.translate(0, 12);
  _drawNoteHeadsAndBeam(canvas);
  canvas.restore();

  canvas.save();
  canvas.translate(256, 296);
  canvas.rotate(-0.10);
  _drawNoteHeadsAndBeam(canvas);
  canvas.restore();
}

Future<Uint8List> _renderPng(int size) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.scale(size / _canvasSize);
  _drawIcon(canvas);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

Uint8List _packIco(List<(int, Uint8List)> entries) {
  final headerSize = 6 + 16 * entries.length;
  final total =
      headerSize + entries.fold<int>(0, (int a, e) => a + e.$2.length);
  final out = Uint8List(total);
  final bd = ByteData.sublistView(out);
  bd.setUint16(0, 0, Endian.little); // reserved
  bd.setUint16(2, 1, Endian.little); // type: icon
  bd.setUint16(4, entries.length, Endian.little);
  var offset = headerSize;
  for (var i = 0; i < entries.length; i++) {
    final (size, png) = entries[i];
    final e = 6 + 16 * i;
    bd.setUint8(e, size >= 256 ? 0 : size); // width
    bd.setUint8(e + 1, size >= 256 ? 0 : size); // height
    bd.setUint8(e + 2, 0); // palette colors
    bd.setUint8(e + 3, 0); // reserved
    bd.setUint16(e + 4, 1, Endian.little); // planes
    bd.setUint16(e + 6, 32, Endian.little); // bpp
    bd.setUint32(e + 8, png.length, Endian.little);
    bd.setUint32(e + 12, offset, Endian.little);
    out.setRange(offset, offset + png.length, png);
    offset += png.length;
  }
  return out;
}

void main() {
  test('render the app icon', () async {
    final entries = <(int, Uint8List)>[];
    Uint8List? master;
    for (final size in _sizes) {
      final png = await _renderPng(size);
      entries.add((size, png));
      if (size == 256) master = png;
    }
    final ico = _packIco(entries);

    final icoFile = File(
      '${Directory.current.path}/windows/runner/resources/app_icon.ico',
    );
    icoFile.writeAsBytesSync(ico);
    final masterFile = File('${Directory.current.path}/tool/app_icon_512.png');
    masterFile.writeAsBytesSync(await _renderPng(512));

    expect(icoFile.existsSync(), isTrue);
    expect(icoFile.lengthSync(), greaterThan(ico.length - 1));
    expect(masterFile.existsSync(), isTrue);
    expect(master, isNotNull);
    expect(master!.length, greaterThan(1000));
    // ICO must contain every requested size.
    for (final (size, _) in entries) {
      expect(ico.length, greaterThan(0));
      expect(size, inInclusiveRange(16, 256));
    }
  });
}
