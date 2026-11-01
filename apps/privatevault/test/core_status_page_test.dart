import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privatevault/app.dart';
import 'package:privatevault/core_host/core_host.dart';

import 'core_host/core_state_test.dart' show readyPayload;

class FakeHost implements CoreHost {
  final events = StreamController<CoreSnapshot>.broadcast();
  CoreSnapshot value = const CoreSnapshot.stopped();
  int starts = 0;
  int stops = 0;
  @override
  CoreSnapshot get snapshot => value;
  @override
  Stream<CoreSnapshot> get changes => events.stream;
  void emit(CoreSnapshot next) {
    value = next;
    events.add(next);
  }

  @override
  Future<void> start() async {
    starts++;
    emit(const CoreSnapshot(phase: CorePhase.starting, message: '正在准备本机服务…'));
  }

  @override
  Future<void> stop() async {
    stops++;
    emit(const CoreSnapshot.stopped());
  }

  @override
  Future<void> readFixture() async {}
  @override
  Future<void> dispose() => events.close();
}

void main() {
  testWidgets(
    'phone width preserves start, cancellation and verified fixture',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 760));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final host = FakeHost();
      await tester.pumpWidget(PrivateVaultApp(host: host));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('启动本机服务'));
      await tester.pump();
      expect(find.text('取消启动'), findsOneWidget);
      host.emit(CoreSnapshot.fromMap(readyPayload()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('样本.png · 内容校验一致'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await host.dispose();
    },
  );

  testWidgets('start, cancel, ready and stop follow the host state', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 760));
    final host = FakeHost();
    await tester.pumpWidget(PrivateVaultApp(host: host));
    expect(find.text('启动本机服务'), findsOneWidget);
    expect(find.text('登录'), findsNothing);
    await tester.tap(find.text('启动本机服务'));
    await tester.pump();
    expect(host.starts, 1);
    expect(find.text('取消启动'), findsOneWidget);
    await tester.tap(find.text('取消启动'));
    await tester.pump();
    expect(host.stops, 1);
    host.emit(CoreSnapshot.fromMap(readyPayload()));
    await tester.pumpAndSettle();
    expect(find.text('停止本机服务'), findsOneWidget);
    expect(find.text('样本.png · 内容校验一致'), findsOneWidget);
    await tester.tap(find.text('停止本机服务'));
    await tester.pumpAndSettle();
    expect(find.text('启动本机服务'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await host.dispose();
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('startup failure stays explicit and retryable', (tester) async {
    final host = FakeHost();
    await tester.pumpWidget(PrivateVaultApp(host: host));
    host.emit(
      const CoreSnapshot(
        phase: CorePhase.failed,
        message: '服务文件校验不通过，已阻止启动。',
        errorCode: 'integrity_mismatch',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('重试启动'), findsOneWidget);
    expect(find.text('已就绪'), findsNothing);
    expect(find.text('服务文件校验不通过，已阻止启动。'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await host.dispose();
  });
}
