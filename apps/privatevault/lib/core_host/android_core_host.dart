import 'channel_core_host.dart';

/// Android uses the same display contract; Kotlin owns service lifecycle.
class AndroidCoreHost extends ChannelCoreHost {
  AndroidCoreHost({super.methods, super.events});
}
