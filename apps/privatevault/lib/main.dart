import 'package:flutter/widgets.dart';

import 'app.dart';
import 'core_host/core_host_factory.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(PrivateVaultApp(host: createCoreHost()));
}
