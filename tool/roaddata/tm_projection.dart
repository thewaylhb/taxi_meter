import 'dart:math';

/// Inverse Transverse Mercator projection for EPSG:5186
/// (Korea 2000 / Central Belt 2010): GRS80 ellipsoid, central meridian
/// 127°E, latitude of origin 38°N, false easting 200000m, false northing
/// 600000m, scale factor 1.0. Converts the projected meters used by the
/// ITS 표준노드링크 shapefile into WGS84 lat/lon degrees.
///
/// Formulas follow the standard ellipsoidal transverse-Mercator inverse
/// (Snyder, "Map Projections: A Working Manual", 1987) — the same equations
/// used for UTM inverse conversion, generalized for arbitrary k0/lat0/lon0.
class TmProjection {
  static const double _a = 6378137.0; // GRS80 semi-major axis
  static const double _f = 1 / 298.257222101; // GRS80 flattening
  static const double _lon0Deg = 127.0;
  static const double _lat0Deg = 38.0;
  static const double _k0 = 1.0;
  static const double _fe = 200000.0;
  static const double _fn = 600000.0;

  static final double _e2 = _f * (2 - _f);
  static final double _ep2 = _e2 / (1 - _e2);
  static final double _lon0 = _lon0Deg * pi / 180;
  static final double _lat0 = _lat0Deg * pi / 180;

  static double _meridianArc(double lat) {
    return _a *
        ((1 - _e2 / 4 - 3 * _e2 * _e2 / 64 - 5 * _e2 * _e2 * _e2 / 256) * lat -
            (3 * _e2 / 8 + 3 * _e2 * _e2 / 32 + 45 * _e2 * _e2 * _e2 / 1024) *
                sin(2 * lat) +
            (15 * _e2 * _e2 / 256 + 45 * _e2 * _e2 * _e2 / 1024) *
                sin(4 * lat) -
            (35 * _e2 * _e2 * _e2 / 3072) * sin(6 * lat));
  }

  /// Returns [lat, lon] in degrees for a projected point (x, y) in meters.
  static List<double> toWgs84(double x, double y) {
    final m1 = _meridianArc(_lat0) + (y - _fn) / _k0;
    final e1 = (1 - sqrt(1 - _e2)) / (1 + sqrt(1 - _e2));
    final mu = m1 /
        (_a * (1 - _e2 / 4 - 3 * _e2 * _e2 / 64 - 5 * _e2 * _e2 * _e2 / 256));

    final phi1 = mu +
        (3 * e1 / 2 - 27 * e1 * e1 * e1 / 32) * sin(2 * mu) +
        (21 * e1 * e1 / 16 - 55 * e1 * e1 * e1 * e1 / 32) * sin(4 * mu) +
        (151 * e1 * e1 * e1 / 96) * sin(6 * mu) +
        (1097 * e1 * e1 * e1 * e1 / 512) * sin(8 * mu);

    final sinPhi1 = sin(phi1);
    final cosPhi1 = cos(phi1);
    final tanPhi1 = tan(phi1);

    final c1 = _ep2 * cosPhi1 * cosPhi1;
    final t1 = tanPhi1 * tanPhi1;
    final n1 = _a / sqrt(1 - _e2 * sinPhi1 * sinPhi1);
    final r1 = _a *
        (1 - _e2) /
        pow(1 - _e2 * sinPhi1 * sinPhi1, 1.5);
    final d = (x - _fe) / (n1 * _k0);

    final lat = phi1 -
        (n1 * tanPhi1 / r1) *
            (d * d / 2 -
                (5 + 3 * t1 + 10 * c1 - 4 * c1 * c1 - 9 * _ep2) *
                    d *
                    d *
                    d *
                    d /
                    24 +
                (61 +
                        90 * t1 +
                        298 * c1 +
                        45 * t1 * t1 -
                        252 * _ep2 -
                        3 * c1 * c1) *
                    d *
                    d *
                    d *
                    d *
                    d *
                    d /
                    720);

    final lon = _lon0 +
        (d -
                (1 + 2 * t1 + c1) * d * d * d / 6 +
                (5 -
                        2 * c1 +
                        28 * t1 -
                        3 * c1 * c1 +
                        8 * _ep2 +
                        24 * t1 * t1) *
                    d *
                    d *
                    d *
                    d *
                    d /
                    120) /
            cosPhi1;

    return [lat * 180 / pi, lon * 180 / pi];
  }
}
