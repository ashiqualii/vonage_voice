import 'package:flutter/services.dart';

import '../../vonage_voice.dart';
import '../platform_interface/vonage_call_platform_interface.dart';

/// Concrete [MethodChannel] implementation of [VonageCallPlatform].
///
/// Each method invokes a named method on the native plugin
/// (Android & iOS) via the shared MethodChannel "vonage_voice/messages".
///
/// Method names are shared across both platforms — any change on
/// the native side must be reflected here and vice versa.
class MethodChannelVonageCall extends VonageCallPlatform {
  /// Holds the current active call state.
  /// Updated automatically by [MethodChannelVonageVoice.parseCallEvent].
  ActiveCall? _activeCall;

  @override
  ActiveCall? get activeCall => _activeCall;

  @override
  set activeCall(ActiveCall? activeCall) => _activeCall = activeCall;

  MethodChannel get _channel => sharedChannel;

  MethodChannelVonageCall();

  // ── Outbound call ─────────────────────────────────────────────────────

  /// Places a new outbound call.
  ///
  /// Sets [activeCall] immediately with [CallDirection.outgoing] so
  /// the UI can reflect the outgoing state before the native layer confirms.
  ///
  /// [from] and [to] are forwarded as-is to the native [makeCall] handler —
  /// never hardcoded here.
  @override
  Future<bool?> place({
    required String from,
    required String to,
    Map<String, dynamic>? extraOptions,
  }) {
    _activeCall = ActiveCall(
      from: from,
      to: to,
      callDirection: CallDirection.outgoing,
    );

    final options = extraOptions ?? <String, dynamic>{};
    options['from'] = from;
    options['to'] = to;
    return _channel.invokeMethod('makeCall', options);
  }

  /// Web-only — not supported on Android. Returns false.
  @override
  Future<bool?> connect({Map<String, dynamic>? extraOptions}) {
    return Future.value(false);
  }

  // ── Core call controls ────────────────────────────────────────────────

  /// Hangs up the active call.
  @override
  Future<bool?> hangUp() {
    return _channel.invokeMethod('hangUp', <String, dynamic>{});
  }

  /// Returns true if there is an active call in progress.
  @override
  Future<bool> isOnCall() {
    return _channel
        .invokeMethod<bool?>('isOnCall', <String, dynamic>{})
        .then<bool>((bool? value) => value ?? false);
  }

  /// Returns the active Vonage callId.
  /// Null until the first [CallEvent.ringing] event fires.
  @override
  Future<String?> getSid() {
    return _channel
        .invokeMethod<String?>('call-sid', <String, dynamic>{})
        .then<String?>((String? value) => value);
  }

  /// Answers a pending incoming call invite.
  @override
  Future<bool?> answer() {
    return _channel.invokeMethod('answer', <String, dynamic>{});
  }

  // ── Hold ──────────────────────────────────────────────────────────────

  /// Puts the active call on hold or resumes it.
  /// [holdCall] — true to hold, false to resume.
  @override
  Future<bool?> holdCall({bool holdCall = true}) {
    return _channel.invokeMethod('holdCall', <String, dynamic>{
      "shouldHold": holdCall,
    });
  }

  /// Returns true if the call is currently on hold.
  @override
  Future<bool?> isHolding() {
    return _channel.invokeMethod('isHolding', <String, dynamic>{});
  }

  // ── Mute ──────────────────────────────────────────────────────────────

  /// Mutes or unmutes the microphone.
  /// [isMuted] — true to mute, false to unmute.
  @override
  Future<bool?> toggleMute(bool isMuted) {
    return _channel.invokeMethod('toggleMute', <String, dynamic>{
      "muted": isMuted,
    });
  }

  /// Returns true if the microphone is currently muted.
  @override
  Future<bool?> isMuted() {
    return _channel.invokeMethod('isMuted', <String, dynamic>{});
  }

  // ── Speaker ───────────────────────────────────────────────────────────

  /// Routes audio to or from the speakerphone.
  /// [speakerIsOn] — true to enable speaker, false to use earpiece.
  @override
  Future<bool?> toggleSpeaker(bool speakerIsOn) {
    return _channel.invokeMethod('toggleSpeaker', <String, dynamic>{
      "speakerIsOn": speakerIsOn,
    });
  }

  /// Returns true if audio is routed to the speakerphone.
  @override
  Future<bool?> isOnSpeaker() {
    return _channel.invokeMethod('isOnSpeaker', <String, dynamic>{});
  }

  // ── Bluetooth ─────────────────────────────────────────────────────────

  /// Routes audio to or from a Bluetooth headset.
  /// [bluetoothOn] — true to enable Bluetooth audio.
  @override
  Future<bool?> toggleBluetooth({bool bluetoothOn = true}) {
    return _channel.invokeMethod('toggleBluetooth', <String, dynamic>{
      "bluetoothOn": bluetoothOn,
    });
  }

  /// Returns true if audio is routed via Bluetooth.
  @override
  Future<bool?> isBluetoothOn() {
    return _channel.invokeMethod('isBluetoothOn', <String, dynamic>{});
  }

  /// Returns true if a Bluetooth audio device is connected and available.
  @override
  Future<bool?> isBluetoothAvailable() {
    return _channel.invokeMethod('isBluetoothAvailable', <String, dynamic>{});
  }

  /// Returns true if the device's Bluetooth adapter is enabled.
  @override
  Future<bool?> isBluetoothEnabled() {
    return _channel.invokeMethod('isBluetoothEnabled', <String, dynamic>{});
  }

  /// Shows the native "Turn on Bluetooth?" dialog.
  @override
  Future<bool?> showBluetoothEnablePrompt() {
    return _channel.invokeMethod('showBluetoothEnablePrompt', <String, dynamic>{});
  }

  /// Opens the system Bluetooth settings screen.
  @override
  Future<bool?> openBluetoothSettings() {
    return _channel.invokeMethod('openBluetoothSettings', <String, dynamic>{});
  }

  // ── DTMF ──────────────────────────────────────────────────────────────

  /// Sends DTMF tones on the active call.
  /// [digits] — string of digits e.g. "1234" or "*#"
  @override
  Future<bool?> sendDigits(String digits) {
    return _channel.invokeMethod('sendDigits', <String, dynamic>{
      "digits": digits,
    });
  }
}
