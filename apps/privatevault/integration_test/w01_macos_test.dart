import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:privatevault/app.dart';
import 'package:privatevault/core_host/macos_core_host.dart';
import 'package:privatevault/core_host/core_state.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('bundled sandboxed core authenticates and reads the fixture', (
    tester,
  ) async {
    final host = MacOSCoreHost();
    try {
      await tester.pumpWidget(PrivateVaultApp(host: host));
      final starting = host.start();
      final stopping = host.stop();
      await Future.wait([
        starting,
        stopping,
      ]).timeout(const Duration(seconds: 45));
      await tester.pumpAndSettle();
      expect(host.snapshot.phase, CorePhase.stopped);
      for (var cycle = 0; cycle < 3; cycle++) {
        await host.start().timeout(const Duration(seconds: 45));
        await tester.pumpAndSettle();
        expect(host.snapshot.phase, CorePhase.ready);
        expect(
          host.snapshot.fixture?.sha256,
          'd70a3c38d62588d9a2b61b7f676fef022039df34c12c92bfade0129103005901',
        );
        expect(find.text('停止本机服务'), findsOneWidget);
        await host.readFixture();
        await host.stop();
        await tester.pumpAndSettle();
        expect(host.snapshot.phase, CorePhase.stopped);
        expect(find.text('启动本机服务'), findsOneWidget);
      }
    } finally {
      await host.stop();
      await host.dispose();
    }
  });
}
