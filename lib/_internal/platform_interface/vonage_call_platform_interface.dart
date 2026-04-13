import 'dart:async';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../../vonage_voice.dart';
import '../method_channel/vonage_call_method_channel.dart';
import 'shared_platform_interface.dart';

/// Abstract platform interface for all active call controls.
///
/// Defines every method that operates on an in-progress call:
/// answer, hangup, mute, speaker, bluetooth, DTMF.
///
/// The concrete implementation is [MethodChannelVonageCall] which
/// delegates each method to the native layer (Android & iOS) via MethodChannel.
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

  // ── Active Call State ─────────────────────────────────────────────────

  /// The currently active or most-recently-active voice call.
  ///
  /// Returns the [ActiveCall] object containing caller/callee identity,
  /// call direction, start time, and any custom parameters received from
  /// the Vonage backend.
  ///
  /// Returns `null` when no call is in progress.
  ///
  /// This property is updated automatically by the event parser whenever
  /// the native layer emits call-state events (Incoming, Ringing,
  /// Connected, Call Ended, etc.).
  ///
  /// ```dart
  /// final call = VonageVoice.instance.call.activeCall;
  /// if (call != null) {
  ///   print('On call with ${call.fromFormatted}');
  ///   print('Direction: ${call.callDirection}');
  /// }
  /// ```
  ActiveCall? get activeCall;

  /// Updates the active call state.
  ///
  /// Set to `null` when the call ends to clear the state.
  /// Normally you don't need to call this directly — the plugin's
  /// event parser updates it automatically.
  set activeCall(ActiveCall? activeCall);

  // ── Outbound Call ─────────────────────────────────────────────────────

  /// Places a new outbound VoIP call.
  ///
  /// This triggers the Vonage backend to initiate the call. On Android,
  /// the call is routed through the Telecom `ConnectionService` which
  /// shows a native dialing screen. On iOS, CallKit shows the native
  /// outgoing-call UI.
  ///
  /// [from] — your Vonage user identity or phone number (the caller).
  /// [to] — the destination phone number or Vonage user identity.
  /// [extraOptions] — optional key-value pairs forwarded to your Vonage
  ///   backend's NCCO answer URL. Use this to pass custom data like
  ///   caller display names, recording flags, etc.
  ///
  /// Returns `true` if the call was successfully initiated on the native
  /// layer. Returns `false` or `null` if the call failed to start.
  ///
  /// **Platform:** Android & iOS.
  ///
  /// ```dart
  /// await VonageVoice.instance.call.place(
  ///   from: 'my_vonage_user',
  ///   to: '+14155551234',
  ///   extraOptions: {'displayName': 'John Doe'},
  /// );
  /// ```
  ///
  /// See also: [activeCall], which is set to an outgoing [ActiveCall]
  /// immediately when this method is called.
  Future<bool?> place({
    required String from,
    required String to,
    Map<String, dynamic>? extraOptions,
  });

  /// **Deprecated** — Web-only method, not supported on Android or iOS.
  ///
  /// ### Why deprecated?
  /// This method was designed for the Vonage JavaScript SDK (web) which
  /// uses a different connection model. On mobile platforms (Android & iOS),
  /// outbound calls must always specify `from` and `to` parameters.
  ///
  /// ### Migration
  /// Use [place] instead, which works on both Android and iOS:
  ///
  /// ```dart
  /// // Before (old way — web only):
  /// await VonageVoice.instance.call.connect(
  ///   extraOptions: {'to': '+14155551234'},
  /// );
  ///
  /// // After (new way — works on Android & iOS):
  /// await VonageVoice.instance.call.place(
  ///   from: 'my_vonage_user',
  ///   to: '+14155551234',
  /// );
  /// ```
  ///
  /// Always returns `false` on mobile platforms.
  @Deprecated(
    'Web-only method — not supported on Android or iOS. '
    'Use place(from:, to:) for mobile outbound calls. '
    'Always returns false on mobile.',
  )
  Future<bool?> connect({Map<String, dynamic>? extraOptions});

  // ── Core Call Controls ────────────────────────────────────────────────

  /// Hangs up (disconnects) the currently active call.
  ///
  /// On **Android**, this triggers `CXEndCallAction` via the Telecom
  /// `ConnectionService`. On **iOS**, this triggers `CXEndCallAction`
  /// via CallKit.
  ///
  /// After a successful hangup, the native layer emits a
  /// [CallEvent.callEnded] event and [activeCall] is set to `null`.
  ///
  /// **Platform:** Android & iOS.
  ///
  /// ```dart
  /// await VonageVoice.instance.call.hangUp();
  /// ```
  Future<bool?> hangUp();

  /// Returns `true` if there is an active call in progress.
  ///
  /// On **Android**, checks the Telecom `ConnectionService` for active
  /// connections. On **iOS**, checks the CallKit call registry.
  ///
  /// **Platform:** Android & iOS.
  Future<bool> isOnCall();

  /// Triggers native re-emission of the current call state after a terminated
  /// process restart. Mirrors Twilio's `getActiveCallOnResumeFromTerminatedState`.
  ///
  /// Asks the native layer to emit a `Connected` or `Incoming` event to the
  /// Flutter event stream if there is an active or pending call. This unblocks
  /// the BLoC after an app restart caused by tapping an incoming call
  /// notification from a killed state.
  ///
  /// Returns `true` if the native side has an active call.
  ///
  /// **Platform:** Android only (no-op stub on iOS).
  Future<bool> getActiveCallOnResumeFromTerminatedState();

  /// Returns the Vonage call ID (session ID) of the active call.
  ///
  /// Returns `null` until the first [CallEvent.ringing] event fires,
  /// because the call ID is assigned by the Vonage backend after the
  /// call request is acknowledged.
  ///
  /// **Platform:** Android & iOS.
  ///
  /// ```dart
  /// final callId = await VonageVoice.instance.call.getSid();
  /// print('Active call ID: $callId');
  /// ```
  Future<String?> getSid();

  /// Answers a pending incoming call invite.
  ///
  /// On **Android**, this fulfils the Telecom `ConnectionService` answer
  /// action. On **iOS**, this fulfils the `CXAnswerCallAction` in CallKit.
  ///
  /// After answering, the native layer emits [CallEvent.answer] followed
  /// by [CallEvent.connected] once media is established.
  ///
  /// **Platform:** Android & iOS.
  ///
  /// ```dart
  /// // When you receive CallEvent.incoming:
  /// await VonageVoice.instance.call.answer();
  /// ```
  Future<bool?> answer();

  // ── Mute ──────────────────────────────────────────────────────────────

  /// Mutes or unmutes the local microphone.
  ///
  /// When [isMuted] is `true`, the remote party cannot hear the local user.
  /// When `false`, the microphone is active again.
  ///
  /// On **Android**, this updates the `Connection` audio state.
  /// On **iOS**, this triggers `CXSetMutedCallAction` in CallKit.
  ///
  /// **Platform:** Android & iOS.
  ///
  /// ```dart
  /// // Mute
  /// await VonageVoice.instance.call.toggleMute(true);
  ///
  /// // Unmute
  /// await VonageVoice.instance.call.toggleMute(false);
  /// ```
  Future<bool?> toggleMute(bool isMuted);

  /// Returns `true` if the microphone is currently muted.
  ///
  /// **Platform:** Android & iOS.
  Future<bool?> isMuted();

  // ── Speaker ───────────────────────────────────────────────────────────

  /// Routes call audio to or from the device's speakerphone.
  ///
  /// When [speakerIsOn] is `true`, audio output switches from the earpiece
  /// to the loudspeaker. When `false`, it switches back to earpiece or
  /// the currently connected Bluetooth device.
  ///
  /// On **Android**, this sets `AudioManager.MODE_IN_COMMUNICATION` and
  /// toggles the speaker route. On **iOS**, this overrides the
  /// `AVAudioSession` output port.
  ///
  /// **Platform:** Android & iOS.
  ///
  /// ```dart
  /// // Enable speaker
  /// await VonageVoice.instance.call.toggleSpeaker(true);
  ///
  /// // Disable speaker (back to earpiece/bluetooth)
  /// await VonageVoice.instance.call.toggleSpeaker(false);
  /// ```
  Future<bool?> toggleSpeaker(bool speakerIsOn);

  /// Returns `true` if audio is currently routed to the speakerphone.
  ///
  /// **Platform:** Android & iOS.
  Future<bool?> isOnSpeaker();

  // ── Bluetooth ─────────────────────────────────────────────────────────

  /// Routes call audio to or from a connected Bluetooth headset.
  ///
  /// When [bluetoothOn] is `true`, audio output switches to the paired
  /// Bluetooth device. When `false`, audio falls back to earpiece or speaker.
  ///
  /// On **Android**, this uses `AudioManager` to set the preferred audio
  /// device. On **iOS**, this uses `AVAudioSession.setPreferredInput()` to
  /// select the Bluetooth HFP/A2DP/LE port.
  ///
  /// **Platform:** Android & iOS.
  ///
  /// ```dart
  /// if (await VonageVoice.instance.call.isBluetoothAvailable() ?? false) {
  ///   await VonageVoice.instance.call.toggleBluetooth(bluetoothOn: true);
  /// }
  /// ```
  Future<bool?> toggleBluetooth({bool bluetoothOn = true});

  /// Returns `true` if audio is currently routed through a Bluetooth device.
  ///
  /// **Platform:** Android & iOS.
  Future<bool?> isBluetoothOn();

  /// Returns `true` if a Bluetooth audio device is connected and available
  /// for audio routing.
  ///
  /// Use this to check before calling [toggleBluetooth] — there's no point
  /// enabling Bluetooth routing if no device is connected.
  ///
  /// **Platform:** Android & iOS.
  Future<bool?> isBluetoothAvailable();

  /// Returns `true` if the device's Bluetooth adapter is turned on.
  ///
  /// On **iOS**, this returns the same value as [isBluetoothAvailable]
  /// because iOS doesn't expose the raw BT adapter state to apps.
  ///
  /// **Platform:** Android & iOS.
  Future<bool?> isBluetoothEnabled();

  /// Shows the native system dialog asking the user to turn on Bluetooth.
  ///
  /// On **Android**, this launches an `ACTION_REQUEST_ENABLE` intent.
  /// On **iOS**, this is a **no-op** (returns `false`) because iOS does
  /// not allow apps to programmatically prompt for Bluetooth.
  ///
  /// Returns `true` if the user enabled Bluetooth, `false` if they
  /// declined or if the prompt isn't available on the platform.
  ///
  /// **Platform:** Android only — returns `false` on iOS.
  Future<bool?> showBluetoothEnablePrompt();

  /// Opens the system Bluetooth settings screen to pair/connect devices.
  ///
  /// On **Android**, this opens the Bluetooth settings directly.
  /// On **iOS**, this opens the app's general settings page (iOS doesn't
  /// allow deep-linking to Bluetooth settings).
  ///
  /// **Platform:** Android & iOS.
  Future<bool?> openBluetoothSettings();

  // ── Audio Device Management ──────────────────────────────────────────

  /// Returns a list of all available audio output devices.
  ///
  /// The list includes built-in devices (earpiece, speaker) and any
  /// connected external devices (Bluetooth headsets, wired headphones).
  /// Multiple Bluetooth devices will appear as separate entries if more
  /// than one is paired and connected.
  ///
  /// Each [AudioDevice] has:
  /// - [AudioDevice.type] — the category (earpiece, speaker, bluetooth, wiredHeadset)
  /// - [AudioDevice.name] — human-readable name (e.g. "AirPods Pro")
  /// - [AudioDevice.isActive] — whether it is the current audio output
  /// - [AudioDevice.id] — platform-specific identifier for [selectAudioDevice]
  ///
  /// **Platform:** Android & iOS.
  ///
  /// ```dart
  /// final devices = await VonageVoice.instance.call.getAudioDevices();
  /// for (final device in devices) {
  ///   print('${device.name} (${device.type}) — active: ${device.isActive}');
  /// }
  /// ```
  Future<List<AudioDevice>> getAudioDevices();

  /// Selects a specific audio output device by its [AudioDevice.id].
  ///
  /// Use this to switch audio to a specific Bluetooth device, the earpiece,
  /// or the speaker. The [deviceId] should come from an [AudioDevice]
  /// previously returned by [getAudioDevices].
  ///
  /// Returns `true` if the device was successfully selected.
  ///
  /// **Platform:** Android & iOS.
  ///
  /// ```dart
  /// final devices = await VonageVoice.instance.call.getAudioDevices();
  /// final bt = devices.firstWhere((d) => d.type == AudioDeviceType.bluetooth);
  /// await VonageVoice.instance.call.selectAudioDevice(bt.id);
  /// ```
  Future<bool?> selectAudioDevice(String deviceId);

  // ── DTMF (Dual-Tone Multi-Frequency) ──────────────────────────────────

  /// Sends DTMF tones on the active call.
  ///
  /// DTMF tones are used for IVR (Interactive Voice Response) navigation
  /// — e.g. "Press 1 for sales, press 2 for support".
  ///
  /// [digits] — a string of DTMF characters to send. Valid characters
  /// are `0-9`, `*`, and `#`. Multiple digits can be sent at once.
  ///
  /// **Platform:** Android & iOS.
  ///
  /// ```dart
  /// // Send a single digit
  /// await VonageVoice.instance.call.sendDigits('1');
  ///
  /// // Send multiple digits at once
  /// await VonageVoice.instance.call.sendDigits('1234#');
  /// ```
  Future<bool?> sendDigits(String digits);
}
