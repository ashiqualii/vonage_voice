import 'package:flutter/services.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../platform_interface/shared_platform_interface.dart';

/// Concrete base implementation of [SharedPlatformInterface].
///
/// Provides the [MethodChannel] and [EventChannel] instances to
/// both [MethodChannelVonageVoice] and [MethodChannelVonageCall].
///
/// This class exists purely to satisfy the [PlatformInterface] token
/// requirement — it holds no logic of its own.
class MethodChannelSharedPlatform extends SharedPlatformInterface {
  MethodChannelSharedPlatform({required super.token});
}
