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
  /// Holds the current active call state — updated automatically
  /// by [MethodChannelVonageVoice.parseCallEvent] when native events arrive.
  ///
  /// Contains the caller/callee identity, direction, start time, and
  /// any custom parameters. `null` when no call is active.
  ActiveCall? _activeCall;

  /// Returns the current [ActiveCall] or `null` if idle.
  @override
  ActiveCall? get activeCall => _activeCall;

  /// Updates the active call state. Set to `null` when the call ends.
  @override
  set activeCall(ActiveCall? activeCall) => _activeCall = activeCall;

  MethodChannel get _channel => sharedChannel;

  MethodChannelVonageCall();

  // ── Outbound Call ─────────────────────────────────────────────────────

  /// Places a new outbound VoIP call via the native `makeCall` method.
  ///
  /// Sets [activeCall] immediately with [CallDirection.outgoing] so the
  /// UI can reflect the dialing state before the native layer confirms.
  ///
  /// [from] and [to] are merged into [extraOptions] and forwarded to the
  /// native handler as-is — never hardcoded on the Dart side.
  ///
  /// On **Android**, this triggers `ConnectionService.onCreateOutgoingConnection()`.
  /// On **iOS**, this triggers `CXStartCallAction` in CallKit.
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

  /// **Deprecated** — Web-only, not supported on mobile. Always returns `false`.
  ///
  /// Use [place] instead for Android & iOS outbound calls.
  /// See [VonageCallPlatform.connect] for full migration details.
  @Deprecated(
    'Web-only method — not supported on Android or iOS. '
    'Use place(from:, to:) for mobile outbound calls. '
    'Always returns false on mobile.',
  )
  @override
  Future<bool?> connect({Map<String, dynamic>? extraOptions}) {
    return Future.value(false);
  }

  // ── Core Call Controls ────────────────────────────────────────────────

  /// Hangs up the active call via the native `hangUp` method.
  ///
  /// Triggers `CXEndCallAction` (iOS) or disconnects the
  /// `ConnectionService` connection (Android).
  @override
  Future<bool?> hangUp() {
    return _channel.invokeMethod('hangUp', <String, dynamic>{});
  }

  /// Returns `true` if there is an active call in progress.
  ///
  /// On Android, queries the `ConnectionService`. On iOS, queries CallKit.
  @override
  Future<bool> isOnCall() {
    return _channel
        .invokeMethod<bool?>('isOnCall', <String, dynamic>{})
        .then<bool>((bool? value) => value ?? false);
  }

  /// Triggers native re-emission of the current call state after a terminated
  /// process restart. Mirrors Twilio's `getActiveCallOnResumeFromTerminatedState`.
  @override
  Future<bool> getActiveCallOnResumeFromTerminatedState() {
    return _channel
        .invokeMethod<bool?>(
          'getActiveCallOnResumeFromTerminatedState',
          <String, dynamic>{},
        )
        .then<bool>((bool? value) => value ?? false);
  }

  /// Returns the active Vonage call ID (session identifier).
  ///
  /// `null` until the first [CallEvent.ringing] event fires because
  /// the call ID is assigned server-side by Vonage.
  @override
  Future<String?> getSid() {
    return _channel
        .invokeMethod<String?>('call-sid', <String, dynamic>{})
        .then<String?>((String? value) => value);
  }

  /// Answers a pending incoming call invite.
  ///
  /// On Android, fulfils the `ConnectionService` answer action.
  /// On iOS, fulfils `CXAnswerCallAction` in CallKit.
  @override
  Future<bool?> answer() {
    return _channel.invokeMethod('answer', <String, dynamic>{});
  }

  // ── Mute ──────────────────────────────────────────────────────────────

  /// Mutes or unmutes the local microphone.
  ///
  /// [isMuted] — `true` to mute, `false` to unmute.
  /// On iOS, triggers `CXSetMutedCallAction` in CallKit.
  @override
  Future<bool?> toggleMute(bool isMuted) {
    return _channel.invokeMethod('toggleMute', <String, dynamic>{
      "muted": isMuted,
    });
  }

  /// Returns `true` if the microphone is currently muted.
  @override
  Future<bool?> isMuted() {
    return _channel.invokeMethod('isMuted', <String, dynamic>{});
  }

  // ── Speaker ───────────────────────────────────────────────────────────

  /// Routes call audio to or from the speakerphone.
  ///
  /// [speakerIsOn] — `true` to enable speaker, `false` for earpiece.
  /// On Android uses `AudioManager`, on iOS overrides `AVAudioSession`.
  @override
  Future<bool?> toggleSpeaker(bool speakerIsOn) {
    return _channel.invokeMethod('toggleSpeaker', <String, dynamic>{
      "speakerIsOn": speakerIsOn,
    });
  }

  /// Returns `true` if audio is routed to the speakerphone.
  @override
  Future<bool?> isOnSpeaker() {
    return _channel.invokeMethod('isOnSpeaker', <String, dynamic>{});
  }

  // ── Bluetooth ─────────────────────────────────────────────────────────

  /// Routes call audio to or from a Bluetooth headset.
  ///
  /// [bluetoothOn] — `true` to enable Bluetooth audio.
  /// On iOS uses `AVAudioSession.setPreferredInput()` for BT HFP/A2DP/LE.
  @override
  Future<bool?> toggleBluetooth({bool bluetoothOn = true}) {
    return _channel.invokeMethod('toggleBluetooth', <String, dynamic>{
      "bluetoothOn": bluetoothOn,
    });
  }

  /// Returns `true` if audio is currently routed through a Bluetooth device.
  @override
  Future<bool?> isBluetoothOn() {
    return _channel.invokeMethod('isBluetoothOn', <String, dynamic>{});
  }

  /// Returns `true` if a Bluetooth audio device is connected and available.
  @override
  Future<bool?> isBluetoothAvailable() {
    return _channel.invokeMethod('isBluetoothAvailable', <String, dynamic>{});
  }

  /// Returns `true` if the device's Bluetooth adapter is enabled.
  ///
  /// On iOS, returns the same value as [isBluetoothAvailable] since
  /// iOS doesn't expose the raw Bluetooth adapter state to apps.
  @override
  Future<bool?> isBluetoothEnabled() {
    return _channel.invokeMethod('isBluetoothEnabled', <String, dynamic>{});
  }

  /// Shows the native "Turn on Bluetooth?" system dialog.
  ///
  /// **Android only** — returns `false` on iOS (not supported by Apple).
  @override
  Future<bool?> showBluetoothEnablePrompt() {
    return _channel.invokeMethod(
      'showBluetoothEnablePrompt',
      <String, dynamic>{},
    );
  }

  /// Opens the system Bluetooth settings screen.
  ///
  /// On iOS, opens the app's general Settings page (Apple doesn't allow
  /// deep-linking directly to Bluetooth settings).
  @override
  Future<bool?> openBluetoothSettings() {
    return _channel.invokeMethod('openBluetoothSettings', <String, dynamic>{});
  }

  // ── Audio Device Management ─────────────────────────────────────────

  /// Returns all available audio output devices with their active state.
  ///
  /// The native layer returns a List<Map> which is parsed into
  /// [AudioDevice] objects. Includes earpiece, speaker, and all
  /// connected Bluetooth devices.
  @override
  Future<List<AudioDevice>> getAudioDevices() async {
    final result = await _channel.invokeMethod<List<dynamic>>(
      'getAudioDevices',
      <String, dynamic>{},
    );
    if (result == null) return [];
    return result
        .whereType<Map>()
        .map((m) => AudioDevice.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  /// Selects a specific audio output device by its platform identifier.
  ///
  /// [deviceId] — the [AudioDevice.id] from [getAudioDevices].
  @override
  Future<bool?> selectAudioDevice(String deviceId) {
    return _channel.invokeMethod('selectAudioDevice', <String, dynamic>{
      "deviceId": deviceId,
    });
  }

  // ── DTMF ──────────────────────────────────────────────────────────────

  /// Sends DTMF tones on the active call for IVR navigation.
  ///
  /// [digits] — DTMF characters (`0-9`, `*`, `#`).
  @override
  Future<bool?> sendDigits(String digits) {
    return _channel.invokeMethod('sendDigits', <String, dynamic>{
      "digits": digits,
    });
  }
}
