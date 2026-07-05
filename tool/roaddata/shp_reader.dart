import 'dart:io';
import 'dart:typed_data';

/// Minimal reader for shapefile PolyLine (shapeType 3) records. Iterates
/// records in file order, which lines up 1:1 with the matching .dbf's
/// record order (the shapefile spec guarantees this correspondence).
class ShpReader {
  final Uint8List _bytes;
  final ByteData _bd;
  int _offset = 100; // main file header is 100 bytes

  ShpReader._(this._bytes, this._bd);

  static ShpReader open(String path) {
    final bytes = File(path).readAsBytesSync();
    return ShpReader._(bytes, bytes.buffer.asByteData());
  }

  bool get hasNext => _offset < _bytes.length - 8;

  /// Returns a flat list of [x0, y0, x1, y1, ...] for the next record's
  /// single-part polyline (MOCT_LINK is always numParts == 1).
  Float64List nextPoints() {
    final contentLength = _bd.getUint32(_offset + 4, Endian.big); // 16-bit words
    final recStart = _offset + 8;
    final shapeType = _bd.getInt32(recStart, Endian.little);
    if (shapeType != 3) {
      throw StateError('Unexpected shapeType $shapeType at offset $recStart');
    }
    final numParts = _bd.getInt32(recStart + 4 + 32, Endian.little);
    final numPoints = _bd.getInt32(recStart + 4 + 32 + 4, Endian.little);
    final pointsStart = recStart + 4 + 32 + 4 + 4 + numParts * 4;

    final out = Float64List(numPoints * 2);
    for (int i = 0; i < numPoints; i++) {
      out[i * 2] = _bd.getFloat64(pointsStart + i * 16, Endian.little);
      out[i * 2 + 1] = _bd.getFloat64(pointsStart + i * 16 + 8, Endian.little);
    }

    _offset = recStart + contentLength * 2;
    return out;
  }
}
