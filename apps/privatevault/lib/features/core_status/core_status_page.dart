import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core_host/core_host.dart';

class CoreStatusPage extends StatefulWidget {
  const CoreStatusPage({super.key, required this.host});
  final CoreHost host;
  @override
  State<CoreStatusPage> createState() => _CoreStatusPageState();
}

class _CoreStatusPageState extends State<CoreStatusPage> {
  late CoreSnapshot _snapshot;
  late final StreamSubscription<CoreSnapshot> _subscription;

  @override
  void initState() {
    super.initState();
    _snapshot = widget.host.snapshot;
    _subscription = widget.host.changes.listen((next) {
      if (mounted) setState(() => _snapshot = next);
    });
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final platformLabel = switch (defaultTargetPlatform) {
      TargetPlatform.android => '安卓开发版 · W01-A',
      TargetPlatform.macOS => 'Mac 开发版 · W01-M',
      _ => '本机开发版 · 平台适配待完成',
    };
    final ready = _snapshot.phase == CorePhase.ready;
    final failed = _snapshot.phase == CorePhase.failed;
    final status = switch (_snapshot.phase) {
      CorePhase.stopped => '尚未启动',
      CorePhase.starting => '正在启动',
      CorePhase.ready => '已就绪',
      CorePhase.stopping => '正在停止',
      CorePhase.failed => '需要处理',
    };
    final color = ready
        ? const Color(0xff287660)
        : failed
        ? const Color(0xffb44f54)
        : const Color(0xff716a83);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(compact ? 16 : 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0xff6b54c6),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: const Icon(
                          Icons.folder_special_outlined,
                          color: Colors.white,
                          size: 27,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'PrivateVault',
                              style: TextStyle(
                                fontSize: 25,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -.5,
                              ),
                            ),
                            Text(
                              platformLabel,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xff81798e),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: .09),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(
                            color: color,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 36),
                  const Text(
                    '先让本机服务准备好',
                    style: TextStyle(
                      fontSize: 29,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.8,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '由 PrivateVault 管理自己的服务，为之后的文件上传与媒体浏览做好准备。',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xff756d83),
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              ready
                                  ? Icons.check_circle_outline_rounded
                                  : failed
                                  ? Icons.info_outline_rounded
                                  : Icons.power_settings_new_rounded,
                              color: color,
                              size: 30,
                            ),
                            const SizedBox(width: 13),
                            Expanded(
                              child: Semantics(
                                liveRegion: true,
                                child: Text(
                                  _snapshot.message,
                                  key: const ValueKey('core-status-message'),
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            if (_snapshot.busy)
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          ready
                              ? '本机认证、测试目录和图片内容检查均已通过。'
                              : failed
                              ? '确认提示后可以重试，原有资料不会用于这项测试。'
                              : '启动后会自动检查服务，并读回一张自制测试图片。',
                          style: const TextStyle(
                            color: Color(0xff81798e),
                            fontSize: 13,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 23),
                        Wrap(
                          spacing: 12,
                          runSpacing: 10,
                          children: [
                            FilledButton.icon(
                              onPressed: _snapshot.busy
                                  ? null
                                  : () => unawaited(
                                      ready
                                          ? widget.host.stop()
                                          : widget.host.start(),
                                    ),
                              icon: Icon(
                                ready
                                    ? Icons.stop_rounded
                                    : failed
                                    ? Icons.refresh_rounded
                                    : Icons.play_arrow_rounded,
                                size: 19,
                              ),
                              label: Text(
                                ready
                                    ? '停止本机服务'
                                    : failed
                                    ? '重试启动'
                                    : '启动本机服务',
                              ),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 23,
                                  vertical: 18,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            if (_snapshot.phase == CorePhase.starting)
                              OutlinedButton(
                                onPressed: () => unawaited(widget.host.stop()),
                                child: const Text('取消启动'),
                              ),
                            if (ready)
                              OutlinedButton.icon(
                                onPressed: () =>
                                    unawaited(widget.host.readFixture()),
                                icon: const Icon(
                                  Icons.image_outlined,
                                  size: 18,
                                ),
                                label: const Text('再次检查测试图'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 18,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _card(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            width: compact ? 80 : 112,
                            height: compact ? 65 : 82,
                            child: _snapshot.fixture != null
                                ? Image.memory(
                                    _snapshot.fixture!.bytes,
                                    fit: BoxFit.cover,
                                    gaplessPlayback: true,
                                  )
                                : const ColoredBox(
                                    color: Color(0xffeeebf7),
                                    child: Icon(
                                      Icons.image_outlined,
                                      color: Color(0xffaaa0c7),
                                      size: 30,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 19),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ready ? '样本.png · 内容校验一致' : '自制测试图片',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 7),
                              Text(
                                ready
                                    ? '已通过本机核心读取 ${_snapshot.fixture!.byteLength} 字节'
                                    : '等待服务就绪后读取',
                                style: const TextStyle(
                                  color: Color(0xff81798e),
                                  fontSize: 12,
                                ),
                              ),
                              if (_snapshot.version case final version?)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    'OpenList $version',
                                    style: const TextStyle(
                                      color: Color(0xff9a91a7),
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 21),
                  const Text(
                    '本阶段使用独立测试环境，尚未连接网盘或个人媒体库。',
                    style: TextStyle(fontSize: 12, color: Color(0xff948b9f)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(25),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(19),
      border: Border.all(color: const Color(0xffeae5f2)),
    ),
    child: child,
  );
}
