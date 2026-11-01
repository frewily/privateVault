import 'package:flutter/foundation.dart';

import 'android_core_host.dart';
import 'core_host.dart';
import 'macos_core_host.dart';

CoreHost createCoreHost({TargetPlatform? platform}) {
  if (kIsWeb) return UnsupportedCoreHost();
  return switch (platform ?? defaultTargetPlatform) {
    TargetPlatform.macOS => MacOSCoreHost(),
    TargetPlatform.android => AndroidCoreHost(),
    _ => UnsupportedCoreHost(),
  };
}

class UnsupportedCoreHost implements CoreHost {
  @override
  CoreSnapshot get snapshot => const CoreSnapshot(
    phase: CorePhase.failed,
    message: '这个平台的本机服务尚未实现，请使用已支持的开发版。',
    errorCode: 'platform_not_supported',
  );
  @override
  Stream<CoreSnapshot> get changes => const Stream.empty();
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> readFixture() async {}
  @override
  Future<void> dispose() async {}
}
