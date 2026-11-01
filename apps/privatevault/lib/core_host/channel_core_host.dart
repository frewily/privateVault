import 'dart:async';

import 'package:flutter/services.dart';

import 'core_host.dart';

class ChannelCoreHost implements CoreHost {
  ChannelCoreHost({MethodChannel? methods, EventChannel? events})
    : _methods = methods ?? const MethodChannel('dev.privatevault.w01/core'),
      _events =
          events ?? const EventChannel('dev.privatevault.w01/core_events') {
    _subscription = _events.receiveBroadcastStream().listen(
      (Object? event) => _accept(CoreSnapshot.fromMap(event)),
      onError: (Object error) =>
          _accept(const CoreSnapshot.unavailable(), force: true),
    );
    unawaited(_invoke('snapshot'));
  }

  final MethodChannel _methods;
  final EventChannel _events;
  final _changes = StreamController<CoreSnapshot>.broadcast();
  late final StreamSubscription<Object?> _subscription;
  CoreSnapshot _snapshot = const CoreSnapshot.stopped();
  bool _disposed = false;

  @override
  CoreSnapshot get snapshot => _snapshot;
  @override
  Stream<CoreSnapshot> get changes => _changes.stream;

  void _accept(CoreSnapshot next, {bool force = false}) {
    if (_disposed || (!force && next.revision < _snapshot.revision)) return;
    _snapshot = next;
    _changes.add(next);
  }

  Future<void> _invoke(String method) async {
    if (_disposed) return;
    try {
      _accept(
        CoreSnapshot.fromMap(await _methods.invokeMethod<Object?>(method)),
      );
    } on PlatformException {
      _accept(const CoreSnapshot.unavailable(), force: true);
    } on MissingPluginException {
      _accept(const CoreSnapshot.unavailable(), force: true);
    }
  }

  @override
  Future<void> start() => _invoke('start');
  @override
  Future<void> stop() => _invoke('stop');
  @override
  Future<void> readFixture() => _invoke('read_fixture');
  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription.cancel();
    await _changes.close();
  }
}
