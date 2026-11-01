import 'core_state.dart';
export 'core_state.dart';

abstract interface class CoreHost {
  CoreSnapshot get snapshot;
  Stream<CoreSnapshot> get changes;
  Future<void> start();
  Future<void> stop();
  Future<void> readFixture();
  Future<void> dispose();
}
