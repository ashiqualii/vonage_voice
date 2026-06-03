/// Vonage Voice Flutter Plugin
///
/// A drop-in replacement for the Twilio Voice Flutter plugin,
/// powered by the Vonage Client SDK for Android.
///
/// Quick start:
/// ```dart
/// // 1. Register JWT and FCM token
/// await VonageVoice.instance.setTokens(
///   accessToken: jwtFromBackend,
///   deviceToken: fcmToken,
/// );
///
/// // 2. Listen to call events
/// VonageVoice.instance.callEventsListener.listen((event) {
///   switch (event) {
///     case CallEvent.incoming:
///       final call = VonageVoice.instance.call.activeCall;
///       print('Incoming from ${call?.fromFormatted}');
///       break;
///     case CallEvent.connected:
///       print('Call connected');
///       break;
///     case CallEvent.callEnded:
///       print('Call ended');
///       break;
///     default:
///       break;
///   }
/// });
///
/// // 3. Place an outgoing call
/// await VonageVoice.instance.call.place(
///   from: 'your_vonage_user',
///   to: '+14155551234',
/// );
///
/// // 4. Hang up
/// await VonageVoice.instance.call.hangUp();
/// ```
library vonage_voice;

import 'package:vonage_voice/_internal/method_channel/vonage_call_method_channel.dart';
import '_internal/method_channel/vonage_voice_method_channel.dart';
import '_internal/platform_interface/vonage_voice_platform_interface.dart';

part 'models/active_call.dart';
part 'models/audio_device.dart';
part 'models/call_event.dart';
part 'models/call_session.dart';
part 'models/call_session_manager.dart';

/// Main entry point for the Vonage Voice Flutter plugin.
///
/// All session management methods are accessed directly on this class:
/// ```dart
/// VonageVoice.instance.setTokens(accessToken: jwt);
/// VonageVoice.instance.callEventsListener.listen((_) {});
/// ```
///
/// All active call controls are accessed via [VonageVoice.instance.call]:
/// ```dart
/// VonageVoice.instance.call.place(from: 'me', to: '+1234');
/// VonageVoice.instance.call.hangUp();
/// VonageVoice.instance.call.toggleMute(true);
/// VonageVoice.instance.call.activeCall; // current call state
/// ```
///
/// Drop-in replacement for TwilioVoice:
///   TwilioVoice.instance  →  VonageVoice.instance
///   TwilioVoice.instance.call  →  VonageVoice.instance.call
class VonageVoice extends MethodChannelVonageVoice {
  /// The singleton instance of the plugin.
  ///
  /// All interaction with the plugin goes through this getter.
  static VonageVoicePlatform get instance => MethodChannelVonageVoice.instance;
}

/// Provides access to active call controls.
///
/// Accessed via [VonageVoice.instance.call].
///
/// Drop-in replacement for Twilio's [Call] class:
///   Call()  →  VonageCall()
class VonageCall extends MethodChannelVonageCall {}
