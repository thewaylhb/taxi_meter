// One-time / re-run-on-refresh preprocessing tool. Converts the ITS
// 표준노드링크 (standard node-link) shapefile into a compact binary asset
// the app can bundle and query fully offline.
//
// Usage:
//   dart run tool/roaddata/build_roaddata.dart <raw_shp_dir> <output_bin_path>
//
// <raw_shp_dir> must contain MOCT_LINK.shp, MOCT_LINK.shx, MOCT_LINK.dbf
// (as extracted from the data.go.kr 표준노드링크 download). Requires the
// `iconv` binary on PATH (ships with Git for Windows) to decode the
// CP949-encoded road names.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'cp949.dart';
import 'dbf_reader.dart';
import 'shp_reader.dart';
import 'tm_projection.dart';

const double _cellDeg = 0.01;

int _latIdx(double lat) => (lat / _cellDeg).floor();
int _lonIdx(double lon) => (lon / _cellDeg).floor();
int _tileKey(int latIdx, int lonIdx) => latIdx * 200000 + lonIdx;

class _LinkRecord {
  final int maxSpd;
  final int rawNameIndex; // index into the pre-dedup raw name list
  final Int32List pointsE7; // [latE7, lonE7, latE7, lonE7, ...]
  final int minLatIdx, maxLatIdx, minLonIdx, maxLonIdx;

  _LinkRecord(this.maxSpd, this.rawNameIndex, this.pointsE7, this.minLatIdx,
      this.maxLatIdx, this.minLonIdx, this.maxLonIdx);
}

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln(
        'usage: dart run tool/roaddata/build_roaddata.dart <raw_shp_dir> <output_bin_path>');
    exit(1);
  }
  final rawDir = args[0];
  final outputPath = args[1];

  final sw = Stopwatch()..start();
  final dbf = DbfReader.open('$rawDir/MOCT_LINK.dbf');
  final shp = ShpReader.open('$rawDir/MOCT_LINK.shp');
  final roadNameIdx = dbf.fieldIndex('ROAD_NAME');
  final maxSpdIdx = dbf.fieldIndex('MAX_SPD');
  if (roadNameIdx < 0 || maxSpdIdx < 0) {
    throw StateError('ROAD_NAME/MAX_SPD field not found in MOCT_LINK.dbf');
  }
  print('DBF opened: ${dbf.numRecords} records (${sw.elapsedMilliseconds}ms)');

  final records = <_LinkRecord>[];
  final rawNames = <Uint8List>[];
  int recordIndex = 0;
  while (shp.hasNext && recordIndex < dbf.numRecords) {
    final xy = shp.nextPoints();
    final n = xy.length ~/ 2;
    final ptsE7 = Int32List(n * 2);
    double minLat = 999, maxLat = -999, minLon = 999, maxLon = -999;
    for (int i = 0; i < n; i++) {
      final ll = TmProjection.toWgs84(xy[i * 2], xy[i * 2 + 1]);
      final lat = ll[0], lon = ll[1];
      ptsE7[i * 2] = (lat * 1e7).round();
      ptsE7[i * 2 + 1] = (lon * 1e7).round();
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lon < minLon) minLon = lon;
      if (lon > maxLon) maxLon = lon;
    }

    final maxSpd = dbf.numField(recordIndex, maxSpdIdx);
    rawNames.add(dbf.rawField(recordIndex, roadNameIdx));

    records.add(_LinkRecord(
      maxSpd,
      recordIndex,
      ptsE7,
      _latIdx(minLat),
      _latIdx(maxLat),
      _lonIdx(minLon),
      _lonIdx(maxLon),
    ));

    recordIndex++;
    if (recordIndex % 200000 == 0) {
      print('  parsed $recordIndex records (${sw.elapsedMilliseconds}ms)');
    }
  }
  print('Parsed $recordIndex link records total (${sw.elapsedMilliseconds}ms)');

  print('Decoding CP949 road names via iconv...');
  final decodedNames = await decodeCp949BatchAsync(rawNames);
  print('Decoded ${decodedNames.length} names (${sw.elapsedMilliseconds}ms)');

  final nameToIndex = <String, int>{};
  final dedupNames = <String>[];
  final linkNameIndex = List<int>.filled(records.length, 0xFFFFFFFF);
  for (int i = 0; i < records.length; i++) {
    final name = decodedNames[i];
    if (name.isEmpty) continue;
    final existing = nameToIndex[name];
    if (existing != null) {
      linkNameIndex[i] = existing;
    } else {
      final idx = dedupNames.length;
      dedupNames.add(name);
      nameToIndex[name] = idx;
      linkNameIndex[i] = idx;
    }
  }
  print('Deduplicated to ${dedupNames.length} unique road names '
      '(${sw.elapsedMilliseconds}ms)');

  print('Bucketing into $_cellDeg° tiles...');
  final tileLinks = <int, List<int>>{};
  for (int i = 0; i < records.length; i++) {
    final r = records[i];
    for (int la = r.minLatIdx; la <= r.maxLatIdx; la++) {
      for (int lo = r.minLonIdx; lo <= r.maxLonIdx; lo++) {
        (tileLinks[_tileKey(la, lo)] ??= <int>[]).add(i);
      }
    }
  }
  print('${tileLinks.length} tiles (${sw.elapsedMilliseconds}ms)');

  // --- Serialize ---
  final stringTableBytes = BytesBuilder();
  for (final name in dedupNames) {
    final utf8Bytes = utf8.encode(name);
    final lenBd = ByteData(2)..setUint16(0, utf8Bytes.length, Endian.little);
    stringTableBytes.add(lenBd.buffer.asUint8List());
    stringTableBytes.add(utf8Bytes);
  }
  final stringTableFinal = stringTableBytes.toBytes();

  final sortedTileKeys = tileLinks.keys.toList()..sort();
  final tileDataBytes = BytesBuilder();
  final tileDirEntries = <List<int>>[]; // [latIdx, lonIdx, offset, length]
  const headerLen = 24;
  final tileDataBase = headerLen + stringTableFinal.length;

  for (final key in sortedTileKeys) {
    final linkIdxs = tileLinks[key]!;
    final latIdx = key ~/ 200000;
    final lonIdx = key - latIdx * 200000;
    final blockStart = tileDataBase + tileDataBytes.length;

    final header = ByteData(4)..setUint32(0, linkIdxs.length, Endian.little);
    tileDataBytes.add(header.buffer.asUint8List());
    for (final li in linkIdxs) {
      final r = records[li];
      final n = r.pointsE7.length ~/ 2;
      final rec = ByteData(2 + 4 + 2);
      rec.setUint16(0, r.maxSpd, Endian.little);
      rec.setUint32(2, linkNameIndex[li], Endian.little);
      rec.setUint16(6, n, Endian.little);
      tileDataBytes.add(rec.buffer.asUint8List());
      final ptsBd = ByteData(n * 8);
      for (int p = 0; p < n * 2; p++) {
        ptsBd.setInt32(p * 4, r.pointsE7[p], Endian.little);
      }
      tileDataBytes.add(ptsBd.buffer.asUint8List());
    }

    final blockLen = tileDataBase + tileDataBytes.length - blockStart;
    tileDirEntries.add([latIdx, lonIdx, blockStart, blockLen]);
  }
  final tileDataFinal = tileDataBytes.toBytes();

  final tileDirBytes = BytesBuilder();
  for (final e in tileDirEntries) {
    final bd = ByteData(16);
    bd.setInt32(0, e[0], Endian.little);
    bd.setInt32(4, e[1], Endian.little);
    bd.setUint32(8, e[2], Endian.little);
    bd.setUint32(12, e[3], Endian.little);
    tileDirBytes.add(bd.buffer.asUint8List());
  }
  final tileDirFinal = tileDirBytes.toBytes();
  final tileDirOffset = tileDataBase + tileDataFinal.length;

  final header = ByteData(headerLen);
  header.setUint8(0, 0x52); // 'R'
  header.setUint8(1, 0x44); // 'D'
  header.setUint8(2, 0x4E); // 'N'
  header.setUint8(3, 0x4C); // 'L'
  header.setUint16(4, 1, Endian.little); // version
  header.setUint16(6, 0, Endian.little); // reserved
  header.setUint32(8, headerLen, Endian.little); // stringTableOffset
  header.setUint32(12, dedupNames.length, Endian.little); // stringTableCount
  header.setUint32(16, tileDirOffset, Endian.little); // tileDirOffset
  header.setUint32(20, tileDirEntries.length, Endian.little); // tileDirCount

  final outFile = File(outputPath);
  outFile.parent.createSync(recursive: true);
  final sink = outFile.openWrite();
  sink.add(header.buffer.asUint8List());
  sink.add(stringTableFinal);
  sink.add(tileDataFinal);
  sink.add(tileDirFinal);
  await sink.close();

  final totalBytes = headerLen +
      stringTableFinal.length +
      tileDataFinal.length +
      tileDirFinal.length;
  print('Wrote $outputPath: ${(totalBytes / 1024 / 1024).toStringAsFixed(1)} MB '
      '(${sw.elapsedMilliseconds}ms total)');
}
