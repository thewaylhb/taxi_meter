import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';

import 'location_service.dart';

/// Current road name + speed limit at the device's GPS position, matched
/// against the bundled ITS 표준노드링크 (standard node-link) dataset
/// (`assets/roaddata/nodelink.bin`, built by tool/roaddata/build_roaddata.dart).
/// Fully offline: no network calls, just a local asset lookup.
class RoadMatch {
  final String? roadName;
  final int maxSpeedKmh; // 0 means unknown

  const RoadMatch({required this.roadName, required this.maxSpeedKmh});

  bool sameAs(RoadMatch? other) =>
      other != null &&
      other.roadName == roadName &&
      other.maxSpeedKmh == maxSpeedKmh;
}

class _DecodedLink {
  final int maxSpd;
  final String? roadName;
  final Float64List latLon; // [lat0, lon0, lat1, lon1, ...] in degrees

  _DecodedLink(this.maxSpd, this.roadName, this.latLon);
}

const double _cellDeg = 0.01;
const double _snapRadiusMeters = 35.0;
const double _metersPerDeg = 111320.0;

int _floorDiv(double v, double cell) => (v / cell).floor();

/// Bump this whenever tool/roaddata/build_roaddata.dart's output changes, so
/// devices holding an older extracted copy re-extract instead of reading
/// stale tile data.
const int _assetFormatVersion = 1;

/// Generous upper bound for the road-name string table region: comfortably
/// larger than any realistic deduplicated name list, but far below the
/// ~139MB of tile geometry that follows it, so reading this window doesn't
/// pull the whole asset into memory.
const int _maxStringTableBytes = 16 * 1024 * 1024;

/// Matches live GPS fixes to the nearest road segment and exposes the
/// result. Independent of [MeterController] in wiring, but only started
/// while a trip is actually running (see [RootScreen]) since that's the
/// only time the road/speed-limit banner is shown.
class RoadMatchService extends ChangeNotifier {
  RandomAccessFile? _raf;
  Future<void> _ioQueue = Future.value();

  late List<String> _stringTable;
  late Int32List _tileLatIdx;
  late Int32List _tileLonIdx;
  late Uint32List _tileOffset;
  late Uint32List _tileLength;

  final Map<int, List<_DecodedLink>> _tileCache = {};
  final List<int> _tileCacheOrder = [];
  static const int _maxCachedTiles = 64;

  StreamSubscription<Position>? _positionSub;
  RoadMatch? _current;
  RoadMatch? get current => _current;

  bool _ready = false;
  Future<void>? _loadFuture;

  Future<void> start() async {
    if (_positionSub != null) return;
    _positionSub = LocationService.positionStream().listen(_onPosition);
  }

  /// Stops matching and clears the current result. Loaded tile data and the
  /// open file handle are left intact so a later [start] doesn't have to
  /// re-extract or re-parse the header.
  Future<void> stop() async {
    await _positionSub?.cancel();
    _positionSub = null;
    if (_current != null) {
      _current = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _raf?.close();
    super.dispose();
  }

  /// Reads bytes at [offset] through the single shared [RandomAccessFile],
  /// queued so concurrent callers can't race each other's `setPosition`.
  Future<Uint8List> _readRange(int offset, int length) {
    final result = _ioQueue.then((_) async {
      final raf = _raf!;
      await raf.setPosition(offset);
      return raf.read(length);
    });
    _ioQueue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<File> _extractedFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/nodelink_v$_assetFormatVersion.bin');
  }

  Future<void> _ensureLoaded() {
    if (_ready) return Future.value();
    return _loadFuture ??= _doLoad().catchError((Object e) {
      _loadFuture = null;
      throw e;
    });
  }

  Future<void> _doLoad() async {
    final file = await _extractedFile();
    if (!await file.exists()) {
      // One-time (per app-storage lifetime / format version) copy from the
      // bundled asset to a real file, so later reads can be random-access
      // instead of holding the whole ~139MB asset in memory forever.
      final bytes = await rootBundle.load('assets/roaddata/nodelink.bin');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        flush: true,
      );
    }

    _raf = await file.open();

    final header = await _readRange(0, 24);
    final headerBd = ByteData.sublistView(header);
    final magic = headerBd.getUint32(0, Endian.big);
    if (magic != 0x52444E4C) {
      throw StateError('bad nodelink.bin magic');
    }
    final stringTableOffset = headerBd.getUint32(8, Endian.little);
    final stringTableCount = headerBd.getUint32(12, Endian.little);
    final tileDirOffset = headerBd.getUint32(16, Endian.little);
    final tileDirCount = headerBd.getUint32(20, Endian.little);

    final stringWindow = await _readRange(
      stringTableOffset,
      min(_maxStringTableBytes, tileDirOffset - stringTableOffset),
    );
    final stringBd = ByteData.sublistView(stringWindow);
    _stringTable = List<String>.filled(stringTableCount, '');
    int off = 0;
    for (int i = 0; i < stringTableCount; i++) {
      if (off + 2 > stringWindow.length) {
        throw StateError(
            'road name string table exceeds $_maxStringTableBytes bytes; '
            'raise _maxStringTableBytes');
      }
      final len = stringBd.getUint16(off, Endian.little);
      off += 2;
      _stringTable[i] = utf8.decode(stringWindow.sublist(off, off + len));
      off += len;
    }

    final dirBytes = await _readRange(tileDirOffset, tileDirCount * 16);
    final dirBd = ByteData.sublistView(dirBytes);
    _tileLatIdx = Int32List(tileDirCount);
    _tileLonIdx = Int32List(tileDirCount);
    _tileOffset = Uint32List(tileDirCount);
    _tileLength = Uint32List(tileDirCount);
    int dOff = 0;
    for (int i = 0; i < tileDirCount; i++) {
      _tileLatIdx[i] = dirBd.getInt32(dOff, Endian.little);
      _tileLonIdx[i] = dirBd.getInt32(dOff + 4, Endian.little);
      _tileOffset[i] = dirBd.getUint32(dOff + 8, Endian.little);
      _tileLength[i] = dirBd.getUint32(dOff + 12, Endian.little);
      dOff += 16;
    }
    _ready = true;
  }

  /// The tile directory is written sorted by `latIdx * 200000 + lonIdx`
  /// (see build_roaddata.dart), so lookups are a binary search.
  int? _findTileIndex(int latIdx, int lonIdx) {
    final target = latIdx * 200000 + lonIdx;
    int lo = 0, hi = _tileLatIdx.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final key = _tileLatIdx[mid] * 200000 + _tileLonIdx[mid];
      if (key == target) return mid;
      if (key < target) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return null;
  }

  Future<List<_DecodedLink>> _decodeTile(int dirIndex) async {
    final raw = await _readRange(_tileOffset[dirIndex], _tileLength[dirIndex]);
    final data = ByteData.sublistView(raw);
    final links = <_DecodedLink>[];
    int off = 0;
    final linkCount = data.getUint32(off, Endian.little);
    off += 4;
    for (int i = 0; i < linkCount; i++) {
      final maxSpd = data.getUint16(off, Endian.little);
      final nameIdx = data.getUint32(off + 2, Endian.little);
      final numPoints = data.getUint16(off + 6, Endian.little);
      off += 8;
      final latLon = Float64List(numPoints * 2);
      for (int p = 0; p < numPoints * 2; p++) {
        latLon[p] = data.getInt32(off, Endian.little) / 1e7;
        off += 4;
      }
      final name = nameIdx == 0xFFFFFFFF ? null : _stringTable[nameIdx];
      links.add(_DecodedLink(maxSpd, name, latLon));
    }
    return links;
  }

  Future<List<_DecodedLink>> _linksForTile(int latIdx, int lonIdx) async {
    final key = latIdx * 200000 + lonIdx;
    final cached = _tileCache[key];
    if (cached != null) return cached;
    final dirIndex = _findTileIndex(latIdx, lonIdx);
    final decoded =
        dirIndex == null ? <_DecodedLink>[] : await _decodeTile(dirIndex);
    _tileCache[key] = decoded;
    _tileCacheOrder.add(key);
    if (_tileCacheOrder.length > _maxCachedTiles) {
      final evict = _tileCacheOrder.removeAt(0);
      _tileCache.remove(evict);
    }
    return decoded;
  }

  Future<void> _onPosition(Position position) async {
    RoadMatch? next;
    try {
      next = await _matchAt(position.latitude, position.longitude);
    } catch (_) {
      // Road data unavailable/corrupt: keep showing the last known match
      // (or none) rather than letting the banner crash the app.
      return;
    }
    if (!(next?.sameAs(_current) ?? (next == null && _current == null))) {
      _current = next;
      notifyListeners();
    }
  }

  /// Exposed for tests: runs the exact matching path `_onPosition` uses,
  /// without needing a real GPS/platform stream.
  @visibleForTesting
  Future<RoadMatch?> debugMatchAt(double lat, double lon) => _matchAt(lat, lon);

  Future<RoadMatch?> _matchAt(double lat, double lon) async {
    await _ensureLoaded();
    final latIdx = _floorDiv(lat, _cellDeg);
    final lonIdx = _floorDiv(lon, _cellDeg);

    final metersPerDegLon = _metersPerDeg * cos(lat * pi / 180);
    double bestDistSq = double.infinity;
    _DecodedLink? best;

    final neighborTiles = <Future<List<_DecodedLink>>>[];
    for (int dla = -1; dla <= 1; dla++) {
      for (int dlo = -1; dlo <= 1; dlo++) {
        neighborTiles.add(_linksForTile(latIdx + dla, lonIdx + dlo));
      }
    }
    final tiles = await Future.wait(neighborTiles);

    for (final links in tiles) {
      for (final link in links) {
        final n = link.latLon.length ~/ 2;
        for (int i = 0; i < n - 1; i++) {
          final x1 = (link.latLon[i * 2 + 1] - lon) * metersPerDegLon;
          final y1 = (link.latLon[i * 2] - lat) * _metersPerDeg;
          final x2 = (link.latLon[i * 2 + 3] - lon) * metersPerDegLon;
          final y2 = (link.latLon[i * 2 + 2] - lat) * _metersPerDeg;
          final dx = x2 - x1;
          final dy = y2 - y1;
          final lenSq = dx * dx + dy * dy;
          double distSq;
          if (lenSq == 0) {
            distSq = x1 * x1 + y1 * y1;
          } else {
            var t = -(x1 * dx + y1 * dy) / lenSq;
            if (t < 0) t = 0;
            if (t > 1) t = 1;
            final px = x1 + t * dx;
            final py = y1 + t * dy;
            distSq = px * px + py * py;
          }
          if (distSq < bestDistSq) {
            bestDistSq = distSq;
            best = link;
          }
        }
      }
    }

    return (best != null && bestDistSq <= _snapRadiusMeters * _snapRadiusMeters)
        ? RoadMatch(roadName: best.roadName, maxSpeedKmh: best.maxSpd)
        : null;
  }
}
