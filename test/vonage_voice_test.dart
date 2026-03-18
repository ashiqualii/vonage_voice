import 'package:flutter_test/flutter_test.dart';
import 'package:vonage_voice/vonage_voice.dart';
import 'package:vonage_voice/vonage_voice_platform_interface.dart';
import 'package:vonage_voice/vonage_voice_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockVonageVoicePlatform
    with MockPlatformInterfaceMixin
    implements VonageVoicePlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final VonageVoicePlatform initialPlatform = VonageVoicePlatform.instance;

  test('$MethodChannelVonageVoice is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelVonageVoice>());
  });

  test('getPlatformVersion', () async {
    VonageVoice vonageVoicePlugin = VonageVoice();
    MockVonageVoicePlatform fakePlatform = MockVonageVoicePlatform();
    VonageVoicePlatform.instance = fakePlatform;

    expect(await vonageVoicePlugin.getPlatformVersion(), '42');
  });
}
