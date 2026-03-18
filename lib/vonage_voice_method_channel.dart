import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'vonage_voice_platform_interface.dart';

/// An implementation of [VonageVoicePlatform] that uses method channels.
class MethodChannelVonageVoice extends VonageVoicePlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('vonage_voice');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
