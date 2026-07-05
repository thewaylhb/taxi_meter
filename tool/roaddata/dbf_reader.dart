import 'dart:io';
import 'dart:typed_data';

class _FieldDef {
  final String name;
  final int length;
  _FieldDef(this.name, this.length);
}

/// Minimal DBF reader: exposes the raw bytes of each record so the caller
/// can pull out just the fields it needs (text fields are returned as raw
/// bytes since MOCT_LINK.dbf is CP949-encoded, not ASCII/UTF-8).
class DbfReader {
  final Uint8List _bytes;
  final int numRecords;
  final int _headerLen;
  final int _recordLen;
  final List<_FieldDef> _fields;

  DbfReader._(this._bytes, this.numRecords, this._headerLen, this._recordLen, this._fields);

  static DbfReader open(String path) {
    final bytes = File(path).readAsBytesSync();
    final bd = bytes.buffer.asByteData();
    final numRecords = bd.getUint32(4, Endian.little);
    final headerLen = bd.getUint16(8, Endian.little);
    final recordLen = bd.getUint16(10, Endian.little);

    final fields = <_FieldDef>[];
    int offset = 32;
    while (offset < headerLen - 1 && bytes[offset] != 0x0D) {
      final nameBytes = bytes.sublist(offset, offset + 11);
      final nullIdx = nameBytes.indexOf(0);
      final name = String.fromCharCodes(nameBytes.sublist(0, nullIdx < 0 ? 11 : nullIdx));
      final length = bytes[offset + 16];
      fields.add(_FieldDef(name, length));
      offset += 32;
    }
    return DbfReader._(bytes, numRecords, headerLen, recordLen, fields);
  }

  int fieldIndex(String name) => _fields.indexWhere((f) => f.name == name);

  int _fieldByteOffset(int fieldIdx) {
    int off = 1; // deletion flag byte
    for (int i = 0; i < fieldIdx; i++) {
      off += _fields[i].length;
    }
    return off;
  }

  /// Raw (still CP949) bytes of a text field, trailing spaces trimmed.
  Uint8List rawField(int record, int fieldIdx) {
    final recStart = _headerLen + record * _recordLen;
    final fOff = recStart + _fieldByteOffset(fieldIdx);
    final len = _fields[fieldIdx].length;
    int end = fOff + len;
    while (end > fOff && _bytes[end - 1] == 0x20) {
      end--;
    }
    return _bytes.sublist(fOff, end);
  }

  /// A numeric field parsed as an int (DBF numeric fields are stored as
  /// space-padded ASCII digits).
  int numField(int record, int fieldIdx) {
    final raw = rawField(record, fieldIdx);
    if (raw.isEmpty) return 0;
    return int.tryParse(String.fromCharCodes(raw).trim()) ?? 0;
  }
}
