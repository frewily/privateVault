import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privatevault/core_host/macos_core_host.dart';
import 'package:privatevault/core_host/android_core_host.dart';
import 'package:privatevault/core_host/core_host.dart';

import 'core_state_test.dart' show readyPayload;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('test.pv/core');
  const events = EventChannel('test.pv/events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    messenger.setMockMethodCallHandler(
      const MethodChannel('test.pv/events'),
      (_) async => null,
    );
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('test.pv/events'),
      null,
    );
  });

  final factories = <String, CoreHost Function()>{
    'macOS': () => MacOSCoreHost(methods: methods, events: events),
    'Android': () => AndroidCoreHost(methods: methods, events: events),
  };
  for (final entry in factories.entries) {
    group(entry.key, () {
      test(
        'a late initial snapshot cannot replace a newer ready event',
        () async {
          final initial = Completer<Object?>();
          messenger.setMockMethodCallHandler(
            methods,
            (call) async => call.method == 'snapshot'
                ? initial.future
                : readyPayload(revision: 4),
          );
          final host = entry.value();
          await host.start();
          expect(host.snapshot.phase, CorePhase.ready);
          initial.complete({
            'phase': 'stopped',
            'message': '旧状态',
            'revision': 0,
          });
          await Future<void>.delayed(Duration.zero);
          expect(host.snapshot.phase, CorePhase.ready);
          await host.dispose();
        },
      );

      test(
        'raw platform exception details never become display messages',
        () async {
          messenger.setMockMethodCallHandler(
            methods,
            (_) async => throw PlatformException(
              code: 'failure',
              message: 'password=secret http://private.invalid',
            ),
          );
          final host = entry.value();
          await host.start();
          expect(host.snapshot.phase, CorePhase.failed);
          expect(host.snapshot.message, isNot(contains('secret')));
          expect(host.snapshot.message, isNot(contains('http')));
          await host.dispose();
        },
      );

      test(
        'inflight callbacks after dispose cannot write to a closed stream',
        () async {
          final pending = Completer<Object?>();
          messenger.setMockMethodCallHandler(methods, (_) => pending.future);
          final host = entry.value();
          final operation = host.start();
          await host.dispose();
          pending.complete(readyPayload());
          await operation;
        },
      );
    });
  }
}
