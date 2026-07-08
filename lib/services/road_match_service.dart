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

/// A nearest-link match, carrying enough to both display (road name/speed
/// limit) and disambiguate it from a nearby road (the matched segment's
/// direction, as a local east/north vector — only its direction matters,
/// not its magnitude).
///
/// Compares equal by road name + speed limit only (not by segment
/// direction, which varies fix-to-fix even while on the same road), so the
/// hysteresis state machine in [RoadMatchService] can tell "still the same
/// road" apart from "a different road is now nearest" without caring which
/// physical link/segment object produced it. This also makes it possible to
/// drive [RoadMatchService.debugOnPosition] with synthetic candidates in
/// tests, instead of needing real coordinates from the bundled dataset.
@visibleForTesting
class RoadMatchCandidate {
  final String? roadName;
  final int maxSpeedKmh;
  final double segDx;
  final double segDy;

  const RoadMatchCandidate({
    required this.roadName,
    required this.maxSpeedKmh,
    this.segDx = 0,
    this.segDy = 0,
  });

  @override
  bool operator ==(Object other) =>
      other is RoadMatchCandidate &&
      other.roadName == roadName &&
      other.maxSpeedKmh == maxSpeedKmh;

  @override
  int get hashCode => Object.hash(roadName, maxSpeedKmh);
}

/// A single GPS fix kept only long enough to estimate the vehicle's current
/// direction of travel (see [RoadMatchService._estimateHeading]).
class _Fix {
  final double lat;
  final double lon;
  final DateTime time;

  const _Fix(this.lat, this.lon, this.time);
}

/// A candidate that has become the nearest match but hasn't yet been
/// adopted as [RoadMatchService._matchedCandidate] — see the dwell-time
/// logic in [RoadMatchService._onPosition].
class _Pending {
  final RoadMatchCandidate? candidate;
  final DateTime since;

  const _Pending(this.candidate, this.since);
}

/// Raw result of the real nearest-link search over the bundled dataset,
/// before it's wrapped into a [RoadMatchCandidate].
class _NearestResult {
  final _DecodedLink? link;
  final double segDx;
  final double segDy;

  const _NearestResult(this.link, this.segDx, this.segDy);

  static const none = _NearestResult(null, 0, 0);
}

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
  RoadMatchService() : _debugLookup = null;

  /// Drives the hysteresis state machine with a synthetic lookup instead of
  /// the real bundled dataset, so tests can exercise dwell-time/heading
  /// behavior without needing real nearby-road coordinates. See
  /// [debugOnPosition].
  @visibleForTesting
  RoadMatchService.debugWithLookup(this._debugLookup);

  final Future<RoadMatchCandidate?> Function(double lat, double lon)?
      _debugLookup;

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

  // --- Hysteresis state (prevents the displayed road/speed-limit from
  // flickering to a nearby ramp/side-road link near interchanges) ---

  /// Candidate currently adopted for display. `null` means "no road nearby"
  /// is the adopted state, which is a real state distinct from
  /// [_hasMatchedOnce] being false (nothing adopted yet).
  RoadMatchCandidate? _matchedCandidate;
  bool _hasMatchedOnce = false;

  /// The last few raw fixes, used only to estimate the current heading.
  final List<_Fix> _recentFixes = [];
  static const int _headingFixCount = 3;
  static const double _minHeadingDisplacementMeters = 8.0;
  static const double _minHeadingSpeedKmh = 8.0;

  /// A candidate that has overtaken [_matchedCandidate] as the nearest
  /// match, and how long it's been the nearest continuously.
  _Pending? _pending;
  static const Duration _dwellDefault = Duration(seconds: 3);
  static const Duration _dwellHeadingAligned = Duration(seconds: 1);

  /// How much closer (in degrees) the candidate's own direction must be to
  /// the estimated heading than the currently-matched road's direction is,
  /// before we trust that the vehicle has actually turned onto it. Tunable;
  /// not load-bearing for correctness the way the *relative* comparison
  /// itself is (see [_requiredDwell]).
  static const double _headingRelativeMarginDegrees = 15.0;

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
    final lat = position.latitude;
    final lon = position.longitude;
    final now = position.timestamp;
    _recordFix(lat, lon, now);

    RoadMatchCandidate? candidate;
    try {
      candidate = _debugLookup != null
          ? await _debugLookup(lat, lon)
          : await _lookupReal(lat, lon);
    } catch (_) {
      // Road data unavailable/corrupt: keep showing the last known match
      // (or none) rather than letting the banner crash the app.
      return;
    }

    // Nothing adopted yet (service just started): take the first reading
    // immediately, there's no prior match that could "flicker" away from.
    if (!_hasMatchedOnce) {
      _hasMatchedOnce = true;
      _matchedCandidate = candidate;
      _pending = null;
      _applyMatched();
      return;
    }

    if (candidate == _matchedCandidate) {
      // Still tracking the same road (or still "no road nearby"): any
      // earlier switch attempt was transient, so drop it. Refresh the
      // stored candidate (segDx/segDy can differ fix-to-fix even for the
      // same road) so _requiredDwell always compares against the most
      // recently confirmed direction of the road we're actually on.
      _matchedCandidate = candidate;
      _pending = null;
      return;
    }

    // The nearest road has changed. Require it to either stay the nearest
    // for a dwell period, or clearly line up with our direction of travel,
    // before actually switching the displayed road/speed limit. This is
    // what keeps a ramp that's momentarily closer than the main road (GPS
    // noise near an interchange) from instantly overwriting the display.
    final pending = _pending;
    if (pending == null || pending.candidate != candidate) {
      _pending = _Pending(candidate, now);
      return;
    }

    final elapsed = now.difference(pending.since);
    if (elapsed < _requiredDwell(candidate)) {
      return;
    }

    _matchedCandidate = candidate;
    _pending = null;
    _applyMatched();
  }

  void _applyMatched() {
    final matched = _matchedCandidate;
    final next = matched == null
        ? null
        : RoadMatch(roadName: matched.roadName, maxSpeedKmh: matched.maxSpeedKmh);
    if (!(next?.sameAs(_current) ?? (next == null && _current == null))) {
      _current = next;
      notifyListeners();
    }
  }

  Future<RoadMatchCandidate?> _lookupReal(double lat, double lon) async {
    final r = await _nearest(lat, lon);
    final link = r.link;
    if (link == null) return null;
    return RoadMatchCandidate(
      roadName: link.roadName,
      maxSpeedKmh: link.maxSpd,
      segDx: r.segDx,
      segDy: r.segDy,
    );
  }

  void _recordFix(double lat, double lon, DateTime time) {
    _recentFixes.add(_Fix(lat, lon, time));
    if (_recentFixes.length > _headingFixCount) {
      _recentFixes.removeAt(0);
    }
  }

  /// Estimates the vehicle's current direction of travel from the oldest to
  /// the newest of the last [_headingFixCount] fixes, as a local east/north
  /// meter vector (not normalized — only its direction is used). Returns
  /// `null` when there isn't enough history yet, or the vehicle is moving
  /// too slowly/too little for the fixes' GPS noise to give a trustworthy
  /// direction (e.g. stopped in traffic near a junction).
  _Fix? get _oldestFix =>
      _recentFixes.length >= _headingFixCount ? _recentFixes.first : null;

  ({double dx, double dy})? _estimateHeading() {
    final oldest = _oldestFix;
    if (oldest == null) return null;
    final newest = _recentFixes.last;
    final elapsedMs = newest.time.difference(oldest.time).inMilliseconds;
    if (elapsedMs <= 0) return null;

    final metersPerDegLon = _metersPerDeg * cos(oldest.lat * pi / 180);
    final dx = (newest.lon - oldest.lon) * metersPerDegLon;
    final dy = (newest.lat - oldest.lat) * _metersPerDeg;
    final distance = sqrt(dx * dx + dy * dy);
    if (distance < _minHeadingDisplacementMeters) return null;

    final speedKmh = distance / elapsedMs * 1000 * 3.6;
    if (speedKmh < _minHeadingSpeedKmh) return null;

    return (dx: dx, dy: dy);
  }

  /// How long [candidate] must remain the nearest link before we actually
  /// switch the display to it. Defaults to a flat dwell period (absorbs GPS
  /// jitter near an interchange); shortened only when the vehicle's
  /// estimated heading has swung meaningfully *closer* to the candidate's
  /// own direction than to the currently-matched road's — good evidence
  /// we're actually turning onto it rather than just passing close to it.
  ///
  /// This is deliberately a comparison against the currently-matched road's
  /// angle, not a fixed absolute threshold on the candidate's angle alone:
  /// at a shallow-angle national-road fork, a ramp can diverge from the
  /// main road by less than any reasonable fixed threshold for a good
  /// distance past the split, while the vehicle is still on the main road.
  /// An absolute threshold would fast-track that as confidently as a real
  /// turn. Comparing the two angles instead only fast-tracks once the
  /// heading has actually rotated toward the candidate, which is what
  /// happens as the vehicle follows the fork's curve — however shallow the
  /// fork looks from a single static angle.
  Duration _requiredDwell(RoadMatchCandidate? candidate) {
    if (candidate == null) return _dwellDefault;
    final current = _matchedCandidate;
    if (current == null) return _dwellDefault;
    final heading = _estimateHeading();
    if (heading == null) return _dwellDefault;

    final angleCandidate = _angleToLineDegrees(
        heading.dx, heading.dy, candidate.segDx, candidate.segDy);
    final angleCurrent = _angleToLineDegrees(
        heading.dx, heading.dy, current.segDx, current.segDy);

    final swungTowardCandidate =
        angleCandidate + _headingRelativeMarginDegrees < angleCurrent;
    return swungTowardCandidate ? _dwellHeadingAligned : _dwellDefault;
  }

  /// Unsigned angle in degrees (0-90) between direction vector (dx1, dy1)
  /// and the *line* through (dx2, dy2) — i.e. it folds to the acute angle,
  /// since a road link's digitized point order doesn't necessarily match
  /// the direction of travel along it.
  double _angleToLineDegrees(double dx1, double dy1, double dx2, double dy2) {
    final mag1 = sqrt(dx1 * dx1 + dy1 * dy1);
    final mag2 = sqrt(dx2 * dx2 + dy2 * dy2);
    if (mag1 == 0 || mag2 == 0) return 90.0;
    final cosTheta = ((dx1 * dx2 + dy1 * dy2) / (mag1 * mag2)).clamp(-1.0, 1.0);
    final degrees = acos(cosTheta) * 180 / pi;
    return degrees > 90 ? 180 - degrees : degrees;
  }

  /// Exposed for tests: runs the plain nearest-link lookup with no
  /// hysteresis/dwell state, without needing a real GPS/platform stream.
  @visibleForTesting
  Future<RoadMatch?> debugMatchAt(double lat, double lon) async {
    final r = await _nearest(lat, lon);
    return r.link == null
        ? null
        : RoadMatch(roadName: r.link!.roadName, maxSpeedKmh: r.link!.maxSpd);
  }

  /// Exposed for tests: runs the exact hysteresis/dwell-time path
  /// `start()`'s position-stream subscription uses, without needing a real
  /// GPS/platform stream. Combine with [RoadMatchService.debugWithLookup] to
  /// drive it with synthetic candidates.
  @visibleForTesting
  Future<void> debugOnPosition(Position position) => _onPosition(position);

  Future<_NearestResult> _nearest(double lat, double lon) async {
    await _ensureLoaded();
    final latIdx = _floorDiv(lat, _cellDeg);
    final lonIdx = _floorDiv(lon, _cellDeg);

    final metersPerDegLon = _metersPerDeg * cos(lat * pi / 180);
    double bestDistSq = double.infinity;
    _DecodedLink? best;
    double bestDx = 0;
    double bestDy = 0;

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
            bestDx = dx;
            bestDy = dy;
          }
        }
      }
    }

    return (best != null && bestDistSq <= _snapRadiusMeters * _snapRadiusMeters)
        ? _NearestResult(best, bestDx, bestDy)
        : _NearestResult.none;
  }
}
