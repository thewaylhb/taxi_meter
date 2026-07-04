import 'package:intl/intl.dart';

final _wonFormat = NumberFormat.decimalPattern('ko_KR');

String formatWon(int won) => '${_wonFormat.format(won)}원';

String formatDistanceKm(double meters) => '${(meters / 1000).toStringAsFixed(2)}km';

String formatSpeedKmh(double kmh, {int decimals = 0}) =>
    '${kmh.toStringAsFixed(decimals)}km/h';

String formatDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes % 60;
  final seconds = d.inSeconds % 60;
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

String formatDateTime(DateTime t) {
  return DateFormat('yyyy.MM.dd HH:mm', 'ko_KR').format(t);
}
