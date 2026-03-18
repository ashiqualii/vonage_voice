import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'vonage_voice_method_channel.dart';

abstract class VonageVoicePlatform extends PlatformInterface {
  /// Constructs a VonageVoicePlatform.
  VonageVoicePlatform() : super(token: _token);

  static final Object _token = Object();

  static VonageVoicePlatform _instance = MethodChannelVonageVoice();

  /// The default instance of [VonageVoicePlatform] to use.
  ///
  /// Defaults to [MethodChannelVonageVoice].
  static VonageVoicePlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [VonageVoicePlatform] when
  /// they register themselves.
  static set instance(VonageVoicePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
