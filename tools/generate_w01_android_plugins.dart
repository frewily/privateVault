// Use the pinned Flutter generator for the selected mode before direct Gradle.
// Flutter 3.47.5 excludes dev-only plugins from release dependencies; its Java
// registrant must be generated with the same filter. No pub get or downloads.
import 'dart:io';

import 'package:flutter_tools/src/base/template.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/context_runner.dart';
import 'package:flutter_tools/src/flutter_plugins.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/isolated/mustache_template.dart';
import 'package:flutter_tools/src/project.dart';
import 'package:unified_analytics/unified_analytics.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2 ||
      !const ['release', 'debug'].contains(arguments[1])) {
    throw ArgumentError('Expected project directory and release|debug');
  }
  Cache.flutterRoot = Platform.environment['FLUTTER_ROOT']!;
  await runInContext<void>(
    () async {
      await injectPlugins(
        FlutterProject.fromDirectory(globals.fs.directory(arguments[0])),
        releaseMode: arguments[1] == 'release',
        androidPlatform: true,
      );
    },
    overrides: {
      TemplateRenderer: () => const MustacheTemplateRenderer(),
      Analytics: () => const NoOpAnalytics(),
    },
  );
}
