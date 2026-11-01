import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:privatevault/core_host/core_state.dart';

Map<String, Object?> readyPayload({int revision = 2}) {
  final bytes = File('assets/w01_sample.png').readAsBytesSync();
  return {
    'phase': 'ready',
    'message': '测试通过',
    'version': 'v4.2.8',
    'revision': revision,
    'fixture': {
      'name': '样本.png',
      'byteLength': bytes.length,
      'sha256':
          'd70a3c38d62588d9a2b61b7f676fef022039df34c12c92bfade0129103005901',
      'bytesBase64': base64Encode(bytes),
    },
  };
}

void main() {
  test(
    'ready requires the expected core and complete fixture display data',
    () {
      expect(CoreSnapshot.fromMap(readyPayload()).phase, CorePhase.ready);
      final missing = readyPayload()..remove('fixture');
      expect(CoreSnapshot.fromMap(missing).phase, CorePhase.failed);
      final version = readyPayload()..['version'] = 'another-core';
      expect(CoreSnapshot.fromMap(version).phase, CorePhase.failed);
    },
  );

  test('truncated and oversized fixture payloads are rejected', () {
    final map = readyPayload();
    final fixture = map['fixture']! as Map<String, Object?>;
    fixture['byteLength'] = 1;
    expect(CoreSnapshot.fromMap(map).phase, CorePhase.failed);
    fixture['byteLength'] = 1000000;
    expect(CoreSnapshot.fromMap(map).phase, CorePhase.failed);
    fixture['bytesBase64'] = 'not-valid-base64';
    expect(FixtureResult.fromMap(fixture), isNull);
  });

  test('unknown native state cannot become successful empty data', () {
    expect(
      CoreSnapshot.fromMap({'phase': 'unknown', 'message': 'raw'}).errorCode,
      'bridge_unavailable',
    );
    expect(CoreSnapshot.fromMap(null).phase, CorePhase.failed);
  });
}
