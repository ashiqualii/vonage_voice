part of '../vonage_voice.dart';

/// Represents all possible call events emitted over the EventChannel.
///
/// These events are parsed from pipe-delimited strings sent by the
/// native layer (Android & iOS) and mapped to this typed enum on the Dart side.
///
/// Usage:
/// ```dart
/// VonageVoice.instance.callEventsListener.listen((event) {
///   switch (event) {
///     case CallEvent.incoming:
///       // show incoming call UI
///       break;
///     case CallEvent.connected:
///       // call connected
///       break;
///     case CallEvent.callEnded:
///       // clean up UI
///       break;
///   }
/// });
/// ```
enum CallEvent {
  /// Incoming call invite received
  incoming,

  /// Call is ringing — outbound call placed
  ringing,

  /// Call media connected — both parties can speak
  connected,

  /// Call media reconnected after a network interruption
  reconnected,

  /// Call media is reconnecting after a network interruption
  reconnecting,

  /// Call ended — local hangup or remote disconnect
  callEnded,

  /// Microphone unmuted
  unmute,

  /// Microphone muted
  mute,

  /// Audio routed to speakerphone
  speakerOn,

  /// Audio routed away from speakerphone
  speakerOff,

  /// Audio routed to Bluetooth headset
  bluetoothOn,

  /// Audio routed away from Bluetooth headset
  bluetoothOff,

  /// A diagnostic or informational log event
  log,

  /// Device token registration failed due to exceeding max devices limit
  deviceLimitExceeded,

  /// A runtime permission result received (microphone, phone state etc.)
  permission,

  /// Call was declined by remote party
  declined,

  /// Incoming call was answered
  answer,

  /// Incoming call was missed (cancelled before answered)
  missedCall,

  /// Returning call event (outgoing call placed back)
  returningCall,

  /// Audio route changed (e.g. speaker, bluetooth, earpiece) — iOS only
  audioRouteChanged,
}
