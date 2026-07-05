import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:geolocator/geolocator.dart';

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

/// Matches live GPS fixes to the nearest road segment and exposes the
/// result. Independent of [MeterController] — this runs continuously
/// regardless of whether a trip is active, since the road/speed-limit
/// banner is meant to be visible everywhere.
class RoadMatchService extends ChangeNotifier {
  ByteData? _data;
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

  bool _loading = false;
  bool _ready = false;

  Future<void> start() async {
    if (_positionSub != null) return;
    _positionSub = LocationService.positionStream().listen(_onPosition);
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }

  Future<void> _ensureLoaded() async {
    if (_ready || _loading) return;
    _loading = true;
    try {
      final bytes = await rootBundle.load('assets/roaddata/nodelink.bin');
      _data = bytes;
      final magic = bytes.getUint32(0, Endian.big);
      if (magic != 0x52444E4C) {
        throw StateError('bad nodelink.bin magic');
      }
      final stringTableOffset = bytes.getUint32(8, Endian.little);
      final stringTableCount = bytes.getUint32(12, Endian.little);
      final tileDirOffset = bytes.getUint32(16, Endian.little);
      final tileDirCount = bytes.getUint32(20, Endian.little);

      _stringTable = List<String>.filled(stringTableCount, '');
      int off = stringTableOffset;
      for (int i = 0; i < stringTableCount; i++) {
        final len = bytes.getUint16(off, Endian.little);
        off += 2;
        _stringTable[i] = utf8.decode(bytes.buffer.asUint8List(off, len));
        off += len;
      }

      _tileLatIdx = Int32List(tileDirCount);
      _tileLonIdx = Int32List(tileDirCount);
      _tileOffset = Uint32List(tileDirCount);
      _tileLength = Uint32List(tileDirCount);
      int dOff = tileDirOffset;
      for (int i = 0; i < tileDirCount; i++) {
        _tileLatIdx[i] = bytes.getInt32(dOff, Endian.little);
        _tileLonIdx[i] = bytes.getInt32(dOff + 4, Endian.little);
        _tileOffset[i] = bytes.getUint32(dOff + 8, Endian.little);
        _tileLength[i] = bytes.getUint32(dOff + 12, Endian.little);
        dOff += 16;
      }
      _ready = true;
    } finally {
      _loading = false;
    }
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

  List<_DecodedLink> _decodeTile(int dirIndex) {
    final data = _data!;
    final links = <_DecodedLink>[];
    int off = _tileOffset[dirIndex];
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

  List<_DecodedLink> _linksForTile(int latIdx, int lonIdx) {
    final key = latIdx * 200000 + lonIdx;
    final cached = _tileCache[key];
    if (cached != null) return cached;
    final dirIndex = _findTileIndex(latIdx, lonIdx);
    final decoded = dirIndex == null ? <_DecodedLink>[] : _decodeTile(dirIndex);
    _tileCache[key] = decoded;
    _tileCacheOrder.add(key);
    if (_tileCacheOrder.length > _maxCachedTiles) {
      final evict = _tileCacheOrder.removeAt(0);
      _tileCache.remove(evict);
    }
    return decoded;
  }

  Future<void> _onPosition(Position position) async {
    final next = await _matchAt(position.latitude, position.longitude);
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

    for (int dla = -1; dla <= 1; dla++) {
      for (int dlo = -1; dlo <= 1; dlo++) {
        final links = _linksForTile(latIdx + dla, lonIdx + dlo);
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
    }

    return (best != null && bestDistSq <= _snapRadiusMeters * _snapRadiusMeters)
        ? RoadMatch(roadName: best.roadName, maxSpeedKmh: best.maxSpd)
        : null;
  }
}
