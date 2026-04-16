import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../vonage_voice.dart';
import '../platform_interface/vonage_call_platform_interface.dart';
import '../platform_interface/vonage_voice_platform_interface.dart';
import '../utils.dart';
import 'vonage_call_method_channel.dart';

/// Concrete [MethodChannel] implementation of [VonageVoicePlatform].
///
/// Handles session management, permissions, phone account setup,
/// caller registry, and event stream parsing.
///
/// The [parseCallEvent] method is the central event router — it converts
/// every pipe-delimited string from the native layer into a typed
/// [CallEvent] and updates [call.activeCall] accordingly.
class MethodChannelVonageVoice extends VonageVoicePlatform {
  static VonageVoicePlatform get instance => VonageVoicePlatform.instance;

  /// Call controls sub-interface
  late final VonageCallPlatform _call = MethodChannelVonageCall();

  @override
  VonageCallPlatform get call => _call;

  /// Manages call session state across events.
  final CallSessionManager _callSessionManager = CallSessionManager();

  @override
  CallSessionManager get callSessionManager => _callSessionManager;

  /// Cached event stream — created once and reused
  Stream<CallEvent>? _callEventsListener;

  MethodChannel get _channel => sharedChannel;
  EventChannel get _eventChannel => eventChannel;

  // ── Event stream ──────────────────────────────────────────────────────

  /// Stream of typed [CallEvent] values from the native layer.
  ///
  /// The raw EventChannel strings are mapped through [parseCallEvent]
  /// before being emitted to listeners.
  @override
  Stream<CallEvent> get callEventsListener {
    _callEventsListener ??= _eventChannel
        .receiveBroadcastStream()
        .map((dynamic event) => parseCallEvent(event))
        .asBroadcastStream();
    return _callEventsListener!;
  }

  @override
  void setOnDeviceTokenChanged(OnDeviceTokenChanged deviceTokenChanged) {
    this.deviceTokenChanged = deviceTokenChanged;
  }

  // ── Session / registration ────────────────────────────────────────────

  /// Register Vonage JWT and optional FCM device token.
  ///
  /// [accessToken] — Vonage JWT from your backend (maps to 'jwt' on native)
  /// [deviceToken] — FCM token for incoming call push notifications
  /// [isSandbox] — iOS only: use sandbox APNS (default: false = production)
  ///
  /// The native layer uses 'tokens' as the method name for compatibility.
  @override
  Future<bool?> setTokens({
    required String accessToken,
    String? deviceToken,
    bool isSandbox = false,
  }) {
    return _channel.invokeMethod('tokens', <String, dynamic>{
      "jwt": accessToken,
      "deviceToken": deviceToken,
      "isSandbox": isSandbox,
    });
  }

  /// Show or hide missed call notifications.
  @override
  set showMissedCallNotifications(bool value) {
    _channel.invokeMethod('showNotifications', <String, dynamic>{
      "show": value,
    });
  }

  /// Unregisters FCM token and ends the Vonage session.
  /// [accessToken] is unused — kept for Twilio API compatibility.
  @override
  Future<bool?> unregister({String? accessToken}) {
    return _channel.invokeMethod('unregister', <String, dynamic>{
      "deviceToken": accessToken,
    });
  }

  /// Refresh an expiring JWT without destroying the session.
  @override
  Future<bool?> refreshSession({required String accessToken}) {
    return _channel.invokeMethod('refreshSession', <String, dynamic>{
      "jwt": accessToken,
    });
  }

  // ── Deprecated — Background Permissions ──────────────────────────────
  //
  // Kept for backward compatibility. These methods are no-ops.
  // See VonageVoicePlatform for full migration documentation.
  //
  // Old behaviour: checked/requested SYSTEM_ALERT_WINDOW for overlay UI.
  // New behaviour: ConnectionService (Android) and CallKit (iOS) handle
  //                the native incoming-call screen automatically.

  /// **Deprecated** — Always returns `false`.
  ///
  /// Background permissions are no longer needed because Android's
  /// `ConnectionService` shows the native incoming-call screen.
  /// See [VonageVoicePlatform.requiresBackgroundPermissions] for
  /// full migration details.
  @Deprecated(
    'No longer needed — Android ConnectionService shows the native incoming-call '
    'screen automatically. Remove calls to this method. Always returns false.',
  )
  @override
  Future<bool> requiresBackgroundPermissions() => Future.value(false);

  /// **Deprecated** — Always returns `false`.
  ///
  /// See [VonageVoicePlatform.requestBackgroundPermissions] for
  /// full migration details.
  @Deprecated(
    'No longer needed — Android ConnectionService handles background calls '
    'automatically. Remove calls to this method. Always returns false.',
  )
  @override
  Future<bool?> requestBackgroundPermissions() => Future.value(false);

  // ── Telecom / PhoneAccount ────────────────────────────────────────────

  @override
  Future<bool> hasRegisteredPhoneAccount() {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return Future.value(true);
    }
    return _channel
        .invokeMethod<bool?>('hasRegisteredPhoneAccount', {})
        .then<bool>((bool? value) => value ?? false);
  }

  @override
  Future<bool?> registerPhoneAccount() {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return Future.value(true);
    }
    return _channel.invokeMethod('registerPhoneAccount', {});
  }

  @override
  Future<bool> isPhoneAccountEnabled() {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return Future.value(true);
    }
    return _channel
        .invokeMethod<bool?>('isPhoneAccountEnabled', {})
        .then<bool>((bool? value) => value ?? false);
  }

  @override
  Future<bool?> openPhoneAccountSettings() {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return Future.value(true);
    }
    return _channel.invokeMethod('openPhoneAccountSettings', {});
  }

  // ── Permissions ───────────────────────────────────────────────────────

  @override
  Future<bool> hasMicAccess() {
    return _channel
        .invokeMethod<bool?>('hasMicPermission', {})
        .then<bool>((bool? value) => value ?? false);
  }

  @override
  Future<bool?> requestMicAccess() {
    return _channel.invokeMethod('requestMicPermission', {});
  }

  @override
  Future<bool> hasReadPhoneStatePermission() {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return Future.value(true);
    }
    return _channel
        .invokeMethod<bool?>('hasReadPhoneStatePermission', {})
        .then<bool>((bool? value) => value ?? false);
  }

  @override
  Future<bool?> requestReadPhoneStatePermission() {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return Future.value(true);
    }
    return _channel.invokeMethod('requestReadPhoneStatePermission', {});
  }

  @override
  Future<bool> hasCallPhonePermission() {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return Future.value(true);
    }
    return _channel
        .invokeMethod<bool?>('hasCallPhonePermission', {})
        .then<bool>((bool? value) => value ?? false);
  }

  @override
  Future<bool?> requestCallPhonePermission() {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return Future.value(true);
    }
    return _channel.invokeMethod('requestCallPhonePermission', {});
  }

  @override
  Future<bool> hasManageOwnCallsPermission() {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return Future.value(true);
    }
    return _channel
        .invokeMethod<bool?>('hasManageOwnCallsPermission', {})
        .then<bool>((bool? value) => value ?? false);
  }

  @override
  Future<bool?> requestManageOwnCallsPermission() {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return Future.value(true);
    }
    return _channel.invokeMethod('requestManageOwnCallsPermission', {});
  }

  @override
  Future<bool> hasReadPhoneNumbersPermission() {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return Future.value(true);
    }
    return _channel
        .invokeMethod<bool?>('hasReadPhoneNumbersPermission', {})
        .then<bool>((bool? value) => value ?? false);
  }

  @override
  Future<bool?> requestReadPhoneNumbersPermission() {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return Future.value(true);
    }
    return _channel.invokeMethod('requestReadPhoneNumbersPermission', {});
  }

  // ── Deprecated — Bluetooth Permissions ────────────────────────────────
  //
  // Kept for backward compatibility. These methods are no-ops.
  // See VonageVoicePlatform for full migration documentation.
  //
  // Old behaviour: checked/requested BLUETOOTH_CONNECT for custom call UI.
  // New behaviour: Telecom/CallKit handles BT routing. Use
  //                VonageCallPlatform.toggleBluetooth() to switch routes.

  /// **Deprecated** — Always returns `false`.
  ///
  /// Bluetooth permissions are no longer needed. The native Telecom/CallKit
  /// layer manages audio routing automatically.
  /// See [VonageVoicePlatform.hasBluetoothPermissions] for migration details.
  @Deprecated(
    'No longer needed — the native Telecom/CallKit layer manages Bluetooth '
    'audio routing automatically. Use call.toggleBluetooth() instead. '
    'Always returns false on Android, true on iOS.',
  )
  @override
  Future<bool> hasBluetoothPermissions() => Future.value(false);

  /// **Deprecated** — Always returns `false`.
  ///
  /// See [VonageVoicePlatform.requestBluetoothPermissions] for migration.
  @Deprecated(
    'No longer needed — the native Telecom/CallKit layer manages Bluetooth '
    'audio routing automatically. Use call.toggleBluetooth() instead. '
    'Always returns false on Android, true on iOS.',
  )
  @override
  Future<bool?> requestBluetoothPermissions() => Future.value(false);

  // ── Notification permission ───────────────────────────────────────

  @override
  Future<bool> hasNotificationPermission() {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return Future.value(true);
    }
    return _channel
        .invokeMethod<bool?>('hasNotificationPermission', {})
        .then<bool>((bool? value) => value ?? false);
  }

  @override
  Future<bool?> requestNotificationPermission() {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return Future.value(true);
    }
    return _channel.invokeMethod('requestNotificationPermission', {});
  }

  // ── Call rejection behaviour ──────────────────────────────────────────

  @override
  Future<bool> rejectCallOnNoPermissions({bool shouldReject = false}) {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return Future.value(true);
    }
    return _channel
        .invokeMethod<bool?>('rejectCallOnNoPermissions', {
          "shouldReject": shouldReject,
        })
        .then<bool>((bool? value) => value ?? false);
  }

  @override
  Future<bool> isRejectingCallOnNoPermissions() {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return Future.value(false);
    }
    return _channel
        .invokeMethod<bool?>('isRejectingCallOnNoPermissions', {})
        .then<bool>((bool? value) => value ?? false);
  }

  // ── iOS CallKit ───────────────────────────────────────────────────────

  /// No-op on Android — iOS only.
  @override
  Future<bool?> updateCallKitIcon({String? icon}) {
    return _channel.invokeMethod('updateCallKitIcon', <String, dynamic>{
      "icon": icon,
    });
  }

  // ── Caller registry ───────────────────────────────────────────────────

  @override
  Future<bool?> registerClient(String clientId, String clientName) {
    return _channel.invokeMethod('registerClient', <String, dynamic>{
      "id": clientId,
      "name": clientName,
    });
  }

  @override
  Future<bool?> unregisterClient(String clientId) {
    return _channel.invokeMethod('unregisterClient', <String, dynamic>{
      "id": clientId,
    });
  }

  @override
  Future<bool?> setDefaultCallerName(String callerName) {
    return _channel.invokeMethod('defaultCaller', <String, dynamic>{
      "defaultCaller": callerName,
    });
  }

  @override
  Future<String?> processVonagePush(Map<String, dynamic> data) {
    return _channel.invokeMethod<String?>(
      'processVonagePush',
      <String, dynamic>{"data": data},
    );
  }

  // ── Battery / power optimization ──────────────────────────────────────

  @override
  Future<bool> isBatteryOptimized() {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return Future.value(false);
    }
    return _channel
        .invokeMethod<bool?>('isBatteryOptimized', {})
        .then<bool>((bool? value) => value ?? true);
  }

  @override
  Future<bool?> requestBatteryOptimizationExemption() {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return Future.value(true);
    }
    return _channel.invokeMethod('requestBatteryOptimizationExemption', {});
  }

  // ── Full-screen intent permission ─────────────────────────────────────

  @override
  Future<bool> canUseFullScreenIntent() {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return Future.value(true);
    }
    return _channel
        .invokeMethod<bool?>('canUseFullScreenIntent', {})
        .then<bool>((bool? value) => value ?? false);
  }

  @override
  Future<bool?> openFullScreenIntentSettings() {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return Future.value(true);
    }
    return _channel.invokeMethod('openFullScreenIntentSettings', {});
  }

  // ── Overlay / "Display over other apps" permission ──────────────────

  @override
  Future<bool> canDrawOverlays() {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return Future.value(true);
    }
    return _channel
        .invokeMethod<bool?>('canDrawOverlays', {})
        .then<bool>((bool? value) => value ?? false);
  }

  @override
  Future<bool?> openOverlaySettings() {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return Future.value(true);
    }
    return _channel.invokeMethod('openOverlaySettings', {});
  }

  // ── Deprecated — Background Call UI ──────────────────────────────────
  //
  // Kept for backward compatibility. This method is a no-op.
  // See VonageVoicePlatform.showBackgroundCallUI for full migration docs.
  //
  // Old behaviour: showed custom floating overlay during backgrounded calls.
  // New behaviour: ConnectionService (Android) / CallKit (iOS) show native UI.

  /// **Deprecated** — Always returns `true` (no-op success).
  ///
  /// Custom background call UI is no longer used. The native OS call
  /// notification handles it automatically.
  /// See [VonageVoicePlatform.showBackgroundCallUI] for migration details.
  @Deprecated(
    'No longer needed — ConnectionService (Android) and CallKit (iOS) show the '
    'native background call UI automatically. Remove calls to this method. '
    'Always returns true.',
  )
  @override
  Future<bool?> showBackgroundCallUI() => Future.value(true);

  // ── Event parser ──────────────────────────────────────────────────────

  /// Parses a raw pipe-delimited event string from the native layer
  /// (Android & iOS) into a typed [CallEvent] and updates
  /// [call.activeCall] as needed.
  ///
  /// Both platforms emit the same pipe-delimited format:
  ///   "Ringing|+14155551234|+14158765432|Outgoing"
  ///   "Connected|+14155551234|+14158765432|Incoming"
  ///   "Incoming|+14155551234|+14158765432|Incoming|{customParams}"
  ///   "PERMISSION|Microphone|true"  (Android only)
  ///   "AudioRoute|speaker|bluetoothAvailable=true"  (iOS only)
  ///   "Call Ended"
  ///   "Call Error: some message"
  @override
  CallEvent parseCallEvent(String state) {
    // ── Device token refresh ──────────────────────────────────────────
    if (state.startsWith("DEVICETOKEN|")) {
      final token = state.split('|')[1];
      deviceTokenChanged?.call(token);
      return CallEvent.log;
    }

    // ── Permission result ─────────────────────────────────────────────
    if (state.startsWith("PERMISSION|")) {
      final tokens = state.split('|');
      printDebug(
        "Permission result — name: ${tokens[1]}, granted: ${tokens[2]}",
      );
      return CallEvent.permission;
    }

    // ── Log / error events ────────────────────────────────────────────
    if (state.startsWith("LOG|")) {
      final tokens = state.split('|');
      printDebug(tokens[1]);

      // Vonage error codes that map to a declined / rejected call
      if (tokens[1].contains("31603") ||
          tokens[1].contains("31486") ||
          tokens[1].toLowerCase().contains("call rejected")) {
        call.activeCall = null;
        _callSessionManager.clear();
        return CallEvent.declined;
      }
      return CallEvent.log;
    }

    // ── Call Error prefix ─────────────────────────────────────────────
    if (state.startsWith("Call Error:")) {
      printDebug(state);
      if (state.contains("max-device-limit") ||
          state.contains("exceeding max devices limit")) {
        return CallEvent.deviceLimitExceeded;
      }
      return CallEvent.log;
    }

    // ── Connected ─────────────────────────────────────────────────────
    if (state.startsWith("Connected|")) {
      final parsed = _createCallFromState(state, initiated: true);
      if (parsed != null) {
        call.activeCall = parsed;
        // Update session: promote ringing → active, or create new
        final sid = parsed.from + parsed.to;
        final existing = _callSessionManager.ringingSession;
        if (existing != null) {
          _callSessionManager.updateSession(
            existing.callSid,
            (s) => s.copyWith(
              status: CallStatus.active,
              connectionStatus: 'Connected',
              activeCall: parsed,
            ),
          );
        } else {
          _callSessionManager.addSession(CallSession(
            callSid: sid,
            activeCall: parsed,
            status: CallStatus.active,
            connectionStatus: 'Connected',
            callerName: parsed.fromFormatted,
            callerNumber: parsed.from,
            startedAt: DateTime.now(),
            direction: parsed.callDirection,
          ));
        }
        printDebug(
          'Connected — From: ${parsed.from}, '
          'To: ${parsed.to}, '
          'Direction: ${parsed.callDirection}',
        );
      }
      return CallEvent.connected;
    }

    // ── Incoming call invite ──────────────────────────────────────────
    if (state.startsWith("Incoming|")) {
      final parsed = _createCallFromState(
        state,
        callDirection: CallDirection.incoming,
      );
      if (parsed != null) {
        call.activeCall = parsed;
        final sid = parsed.from + parsed.to;
        _callSessionManager.addSession(CallSession(
          callSid: sid,
          activeCall: parsed,
          status: CallStatus.ringing,
          connectionStatus: 'Ringing',
          callerName: parsed.fromFormatted,
          callerNumber: parsed.from,
          startedAt: DateTime.now(),
          direction: CallDirection.incoming,
        ));
        printDebug(
          'Incoming — From: ${parsed.from}, '
          'To: ${parsed.to}',
        );
      }
      return CallEvent.incoming;
    }

    // ── Ringing (outbound) ────────────────────────────────────────────
    if (state.startsWith("Ringing|")) {
      final parsed = _createCallFromState(state);
      if (parsed != null) {
        call.activeCall = parsed;
        final sid = parsed.from + parsed.to;
        _callSessionManager.addSession(CallSession(
          callSid: sid,
          activeCall: parsed,
          status: CallStatus.ringing,
          connectionStatus: 'Ringing',
          callerName: parsed.toFormatted,
          callerNumber: parsed.to,
          startedAt: DateTime.now(),
          direction: parsed.callDirection,
        ));
        printDebug(
          'Ringing — From: ${parsed.from}, '
          'To: ${parsed.to}, '
          'Direction: ${parsed.callDirection}',
        );
      }
      return CallEvent.ringing;
    }

    // ── Answer ────────────────────────────────────────────────────────
    if (state.startsWith("Answer")) {
      final parsed = _createCallFromState(
        state,
        callDirection: CallDirection.incoming,
      );
      if (parsed != null) {
        call.activeCall = parsed;
        printDebug(
          'Answer — From: ${parsed.from}, '
          'To: ${parsed.to}',
        );
      }
      return CallEvent.answer;
    }

    // ── Returning call ────────────────────────────────────────────────
    if (state.startsWith("ReturningCall")) {
      final parsed = _createCallFromState(
        state,
        callDirection: CallDirection.outgoing,
      );
      if (parsed != null) {
        call.activeCall = parsed;
        printDebug(
          'Returning Call — From: ${parsed.from}, '
          'To: ${parsed.to}',
        );
      }
      return CallEvent.returningCall;
    }

    // ── Reconnecting ──────────────────────────────────────────────────
    if (state.startsWith("Reconnecting")) {
      return CallEvent.reconnecting;
    }

    // ── Audio route change (iOS) ──────────────────────────────────────
    if (state.startsWith("AudioRoute|")) {
      printDebug('Audio route changed: $state');
      return CallEvent.audioRouteChanged;
    }

    // ── Simple single-word events ─────────────────────────────────────
    switch (state) {
      case 'Ringing':
        return CallEvent.ringing;
      case 'Connected':
        return CallEvent.connected;
      case 'Call Ended':
        call.activeCall = null;
        _callSessionManager.clear();
        return CallEvent.callEnded;
      case 'Missed Call':
        call.activeCall = null;
        _callSessionManager.clear();
        return CallEvent.missedCall;
      case 'Call Rejected':
      case 'Declined':
        call.activeCall = null;
        _callSessionManager.clear();
        return CallEvent.declined;
      case 'Unmute':
        return CallEvent.unmute;
      case 'Mute':
        return CallEvent.mute;
      case 'Speaker On':
        return CallEvent.speakerOn;
      case 'Speaker Off':
        return CallEvent.speakerOff;
      case 'Bluetooth On':
        return CallEvent.bluetoothOn;
      case 'Bluetooth Off':
        return CallEvent.bluetoothOff;
      case 'Reconnected':
        return CallEvent.reconnected;
      default:
        printDebug('Unrecognised event: $state');
        return CallEvent.log;
    }
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────

/// Creates an [ActiveCall] from a pipe-delimited event string.
///
/// Format: "EventType|from|to|direction|{customParams}"
///
/// [callDirection] overrides the direction parsed from the string.
/// [initiated] sets the call start timestamp when true.
ActiveCall? _createCallFromState(
  String state, {
  CallDirection? callDirection,
  bool initiated = false,
}) {
  final tokens = state.split('|');

  // Need at least 3 segments: EventType|from|to
  if (tokens.length < 3) {
    return null;
  }

  final direction =
      callDirection ??
      (tokens.length > 3 && "incoming" == tokens[3].toLowerCase()
          ? CallDirection.incoming
          : CallDirection.outgoing);

  return ActiveCall(
    from: tokens[1],
    to: tokens[2],
    initiated: initiated ? DateTime.now() : null,
    callDirection: direction,
    customParams: _parseCustomParams(tokens),
  );
}

/// Parses optional JSON custom params from the 5th pipe segment.
///
/// Returns null if there is no 5th segment or it is not valid JSON.
Map<String, dynamic>? _parseCustomParams(List<String> tokens) {
  if (tokens.length != 5) return null;
  try {
    return jsonDecode(tokens[4]) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}
