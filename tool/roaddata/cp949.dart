import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Batch-decodes CP949 (EUC-KR extended) byte strings to UTF-8 using the
/// system `iconv` binary (present via Git for Windows / any Unix system).
/// One subprocess call handles the whole dataset instead of spawning a
/// process per record. Relies on 0x0A never appearing inside a CP949
/// multi-byte sequence, which holds for this codepage.
Future<List<String>> decodeCp949BatchAsync(List<Uint8List> rawNames) async {
  final joined = BytesBuilder();
  for (final raw in rawNames) {
    joined.add(raw);
    joined.addByte(0x0A);
  }
  final process = await Process.start('iconv', ['-f', 'CP949', '-t', 'UTF-8']);
  final stdoutFuture = process.stdout.fold<BytesBuilder>(
    BytesBuilder(),
    (b, chunk) => b..add(chunk),
  );
  final stderrFuture = process.stderr.transform(utf8.decoder).join();
  process.stdin.add(joined.toBytes());
  await process.stdin.close();

  final exitCode = await process.exitCode;
  final outBytes = (await stdoutFuture).toBytes();
  final stderrText = await stderrFuture;
  if (exitCode != 0) {
    throw StateError('iconv failed ($exitCode): $stderrText');
  }

  final decoded = utf8.decode(outBytes, allowMalformed: true);
  final lines = decoded.split('\n');
  // Trailing newline produces one extra empty entry.
  if (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }
  if (lines.length != rawNames.length) {
    throw StateError(
        'decoded line count ${lines.length} != input count ${rawNames.length}');
  }
  return lines;
}
