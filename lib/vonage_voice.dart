
import 'vonage_voice_platform_interface.dart';

class VonageVoice {
  Future<String?> getPlatformVersion() {
    return VonageVoicePlatform.instance.getPlatformVersion();
  }
}
