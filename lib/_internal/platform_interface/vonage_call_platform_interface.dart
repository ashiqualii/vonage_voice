import 'dart:async';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../../vonage_voice.dart';
import '../method_channel/vonage_call_method_channel.dart';
import 'shared_platform_interface.dart';

/// Abstract platform interface for all active call controls.
///
/// Defines every method that operates on an in-progress call:
/// answer, hangup, mute, hold, speaker, bluetooth, DTMF.
///
/// The concrete implementation is [MethodChannelVonageCall] which
/// delegates each method to the native Android layer via MethodChannel.
///
/// Access via:
/// ```dart
/// VonageVoice.instance.call.hangUp();
/// VonageVoice.instance.call.toggleMute(true);
/// VonageVoice.instance.call.activeCall; // current call state
/// ```
abstract class VonageCallPlatform extends SharedPlatformInterface {
  VonageCallPlatform() : super(token: _token);

  static final Object _token = Object();

  static VonageCallPlatform _instance = MethodChannelVonageCall();

  static VonageCallPlatform get instance => _instance;

  static set instance(VonageCallPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  // ── Active call state ─────────────────────────────────────────────────

  /// The currently active or pending call.
  /// Null when no call is in progress.
  ActiveCall? get activeCall;

  /// Update the active call state.
  /// Set to null when the call ends.
  set activeCall(ActiveCall? activeCall);

  // ── Outbound call ─────────────────────────────────────────────────────

  /// Places a new outbound call.
  ///
  /// [from] — caller identity (your Vonage user or number)
  /// [to]   — destination number or Vonage user identity
  /// [extraOptions] — optional custom params forwarded to your backend
  ///
  /// Returns true if the call was successfully initiated.
  Future<bool?> place({
    required String from,
    required String to,
    Map<String, dynamic>? extraOptions,
  });

  /// Places an outbound call using only [extraOptions].
  /// Web-only at this stage — returns false on mobile.
  Future<bool?> connect({Map<String, dynamic>? extraOptions});

  // ── Core call controls ────────────────────────────────────────────────

  /// Hangs up the active call.
  Future<bool?> hangUp();

  /// Returns true if there is an active call in progress.
  Future<bool> isOnCall();

  /// Returns the active call ID (Vonage callId).
  /// Null until the first [CallEvent.ringing] event.
  Future<String?> getSid();

  /// Answers a pending incoming call invite.
  Future<bool?> answer();

  // ── Hold ──────────────────────────────────────────────────────────────

  /// Puts the active call on hold or resumes it.
  ///
  /// [holdCall] — true to hold, false to resume.
  Future<bool?> holdCall({bool holdCall = true});

  /// Returns true if the call is currently on hold.
  Future<bool?> isHolding();

  // ── Mute ──────────────────────────────────────────────────────────────

  /// Mutes or unmutes the microphone.
  ///
  /// [isMuted] — true to mute, false to unmute.
  Future<bool?> toggleMute(bool isMuted);

  /// Returns true if the microphone is currently muted.
  Future<bool?> isMuted();

  // ── Speaker ───────────────────────────────────────────────────────────

  /// Routes audio to or from the speakerphone.
  ///
  /// [speakerIsOn] — true to enable speaker, false to use earpiece.
  Future<bool?> toggleSpeaker(bool speakerIsOn);

  /// Returns true if audio is currently routed to the speakerphone.
  Future<bool?> isOnSpeaker();

  // ── Bluetooth ─────────────────────────────────────────────────────────

  /// Routes audio to or from a Bluetooth headset.
  ///
  /// [bluetoothOn] — true to enable Bluetooth audio, false to disable.
  Future<bool?> toggleBluetooth({bool bluetoothOn = true});

  /// Returns true if audio is currently routed via Bluetooth.
  Future<bool?> isBluetoothOn();

  // ── DTMF ──────────────────────────────────────────────────────────────

  /// Sends DTMF tones on the active call.
  ///
  /// [digits] — string of digits to send e.g. "1234" or "*#"
  Future<bool?> sendDigits(String digits);
}
