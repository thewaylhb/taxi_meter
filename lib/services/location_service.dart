import 'package:geolocator/geolocator.dart';

/// Thin wrapper around geolocator for permission handling + the raw position
/// stream. No accounts, no backend — this only talks to the OS location API.
class LocationService {
  static const _locationSettings = LocationSettings(
    accuracy: LocationAccuracy.best,
    distanceFilter: 0,
  );

  /// Ensures location services are on and permission is granted.
  /// Returns a human-readable error message, or null on success.
  static Future<String?> ensureReady() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return '위치 서비스가 꺼져 있습니다. 설정에서 위치 서비스를 켜주세요.';
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return '위치 권한이 거부되었습니다.';
      }
    }
    if (permission == LocationPermission.deniedForever) {
      return '위치 권한이 영구적으로 거부되었습니다. 앱 설정에서 권한을 허용해주세요.';
    }
    return null;
  }

  static Stream<Position> positionStream() {
    return Geolocator.getPositionStream(locationSettings: _locationSettings);
  }
}
