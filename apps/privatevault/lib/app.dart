import 'package:flutter/material.dart';

import 'core_host/core_host.dart';
import 'features/core_status/core_status_page.dart';

class PrivateVaultApp extends StatelessWidget {
  const PrivateVaultApp({super.key, required this.host});
  final CoreHost host;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'PrivateVault W01',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff6b54c6),
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: const Color(0xfff6f4fa),
      fontFamily: '.AppleSystemUIFont',
    ),
    home: CoreStatusPage(host: host),
  );
}
