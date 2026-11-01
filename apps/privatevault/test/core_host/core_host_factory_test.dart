import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privatevault/core_host/core_host_factory.dart';
import 'package:privatevault/core_host/core_state.dart';

void main() {
  test(
    'Windows has an explicit unsupported state and never calls a Mac bridge',
    () async {
      final host = createCoreHost(platform: TargetPlatform.windows);
      expect(host, isA<UnsupportedCoreHost>());
      expect(host.snapshot.phase, CorePhase.failed);
      expect(host.snapshot.errorCode, 'platform_not_supported');
      await host.start();
      expect(host.snapshot.phase, CorePhase.failed);
      await host.dispose();
    },
  );
}
