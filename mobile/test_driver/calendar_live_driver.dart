import 'dart:io';
import 'dart:convert';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final directory = Directory(
    Platform.environment['CALENDAR_EVIDENCE_DIR'] ?? '../output/calendar-live',
  );
  await directory.create(recursive: true);
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      if (bytes.length < 8 || bytes[0] != 137 || bytes[1] != 80) return false;
      await File('${directory.path}/$name.png').writeAsBytes(bytes);
      return true;
    },
    writeResponseOnFailure: true,
    responseDataCallback: (data) async {
      final metadata = Map<String, dynamic>.from(data ?? {})
        ..remove('screenshots');
      await File(
        '${directory.path}/results.json',
      ).writeAsString(jsonEncode(metadata));
    },
  );
}
