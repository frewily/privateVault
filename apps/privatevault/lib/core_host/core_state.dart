import 'dart:convert';
import 'dart:typed_data';

enum CorePhase { stopped, starting, ready, stopping, failed }

class FixtureResult {
  const FixtureResult({
    required this.name,
    required this.byteLength,
    required this.sha256,
    required this.bytes,
  });
  final String name;
  final int byteLength;
  final String sha256;
  final Uint8List bytes;

  static FixtureResult? fromMap(Object? value) {
    if (value is! Map) return null;
    final encoded = value['bytesBase64'];
    final size = value['byteLength'];
    final digest = value['sha256'];
    if (value['name'] != '样本.png' ||
        encoded is! String ||
        encoded.length > 90000 ||
        size is! int ||
        size <= 0 ||
        size > 65536 ||
        digest is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest))
      return null;
    try {
      final bytes = base64Decode(encoded);
      if (bytes.length != size) return null;
      return FixtureResult(
        name: '样本.png',
        byteLength: size,
        sha256: digest,
        bytes: bytes,
      );
    } on FormatException {
      return null;
    }
  }
}

class CoreSnapshot {
  const CoreSnapshot({
    required this.phase,
    required this.message,
    this.version,
    this.errorCode,
    this.fixture,
    this.revision = 0,
  });
  const CoreSnapshot.stopped()
    : this(phase: CorePhase.stopped, message: '本机服务尚未启动');
  const CoreSnapshot.unavailable()
    : this(
        phase: CorePhase.failed,
        message: '无法连接本机服务管理器，请重新打开开发版。',
        errorCode: 'bridge_unavailable',
      );
  final CorePhase phase;
  final String message;
  final String? version;
  final String? errorCode;
  final FixtureResult? fixture;
  final int revision;

  bool get busy => phase == CorePhase.starting || phase == CorePhase.stopping;

  factory CoreSnapshot.fromMap(Object? value) {
    if (value is! Map ||
        value['phase'] is! String ||
        value['message'] is! String) {
      return const CoreSnapshot.unavailable();
    }
    final phases = CorePhase.values.where(
      (phase) => phase.name == value['phase'],
    );
    if (phases.isEmpty) return const CoreSnapshot.unavailable();
    final phase = phases.single;
    final fixture = FixtureResult.fromMap(value['fixture']);
    if (phase == CorePhase.ready &&
        (value['version'] != 'v4.2.8' || fixture == null)) {
      return const CoreSnapshot.unavailable();
    }
    // Native messages are an allowlisted display contract; never forward exception text.
    return CoreSnapshot(
      phase: phase,
      message: value['message'] as String,
      version: value['version'] is String ? value['version'] as String : null,
      errorCode: value['errorCode'] is String
          ? value['errorCode'] as String
          : null,
      fixture: fixture,
      revision: value['revision'] is int ? value['revision'] as int : 0,
    );
  }
}
