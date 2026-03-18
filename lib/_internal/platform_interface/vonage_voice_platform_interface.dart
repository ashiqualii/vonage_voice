import 'dart:async';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../../vonage_voice.dart';
import '../method_channel/vonage_voice_method_channel.dart';
import 'shared_platform_interface.dart';
import 'vonage_call_platform_interface.dart';

/// Callback type for FCM device token refresh events.
typedef OnDeviceTokenChanged = Function(String token);

/// Abstract platform interface for Vonage Voice session and device management.
///
/// Defines all methods that operate at the session level:
/// token registration, permissions, phone account, notifications.
///
/// The concrete implementation is [MethodChannelVonageVoice].
///
/// Access via:
/// ```dart
/// VonageVoice.instance.setTokens(accessToken: jwt, deviceToken: fcmToken);
/// VonageVoice.instance.callEventsListener.listen((_) {});
/// VonageVoice.instance.call.hangUp();
/// ```
abstract class VonageVoicePlatform extends SharedPlatformInterface {
  VonageVoicePlatform() : super(token: _token);

  static final Object _token = Object();

  static VonageVoicePlatform _instance = MethodChannelVonageVoice();

  static VonageVoicePlatform get instance => _instance;

  static set instance(VonageVoicePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  // ── Call sub-interface ────────────────────────────────────────────────

  /// Access all active call controls via this property.
  ///
  /// Example:
  /// ```dart
  /// VonageVoice.instance.call.hangUp();
  /// VonageVoice.instance.call.toggleMute(true);
  /// ```
  VonageCallPlatform get call;

  // ── Event stream ──────────────────────────────────────────────────────

  /// Stream of typed [CallEvent] values from the native layer.
  ///
  /// Listen to this stream to react to call state changes:
  /// ```dart
  /// VonageVoice.instance.callEventsListener.listen((event) {
  ///   if (event == CallEvent.connected) { ... }
  /// });
  /// ```
  Stream<CallEvent> get callEventsListener;

  // ── FCM token callback ────────────────────────────────────────────────

  /// Optional callback fired when the FCM device token is refreshed.
  /// Use this to re-register the new token with your backend.
  OnDeviceTokenChanged? deviceTokenChanged;

  void setOnDeviceTokenChanged(OnDeviceTokenChanged deviceTokenChanged) {
    this.deviceTokenChanged = deviceTokenChanged;
  }

  // ── Session / registration ────────────────────────────────────────────

  /// Register Vonage JWT and optional FCM device token.
  ///
  /// Must be called before placing or receiving any calls.
  ///
  /// [accessToken] — Vonage JWT obtained from your backend
  /// [deviceToken] — FCM token for incoming call push notifications (optional)
  ///
  /// ```dart
  /// await VonageVoice.instance.setTokens(
  ///   accessToken: jwtFromBackend,
  ///   deviceToken: fcmToken,
  /// );
  /// ```
  Future<bool?> setTokens({required String accessToken, String? deviceToken});

  /// Whether to show a missed call notification.
  /// Persisted across app restarts until overridden.
  set showMissedCallNotifications(bool value);

  /// Unregisters the FCM token and ends the Vonage session.
  ///
  /// [accessToken] is unused — kept for API compatibility with Twilio plugin.
  Future<bool?> unregister({String? accessToken});

  /// Refresh an expiring JWT without destroying the session.
  ///
  /// Call this when your backend issues a new JWT before the current one expires.
  Future<bool?> refreshSession({required String accessToken});

  // ── Deprecated stubs (API compatibility) ─────────────────────────────

  @Deprecated('custom call UI not used anymore, has no effect')
  Future<bool> requiresBackgroundPermissions();

  @Deprecated('custom call UI not used anymore, has no effect')
  Future<bool?> requestBackgroundPermissions();

  // ── Telecom / PhoneAccount ────────────────────────────────────────────

  /// Returns true if the app has a registered Telecom PhoneAccount.
  /// Android only.
  Future<bool> hasRegisteredPhoneAccount();

  /// Registers this app as a call-capable account with Android Telecom.
  /// Android only.
  Future<bool?> registerPhoneAccount();

  /// Returns true if the app's PhoneAccount is enabled in system settings.
  /// Android only.
  Future<bool> isPhoneAccountEnabled();

  /// Opens the system phone account settings screen.
  /// Android only.
  Future<bool?> openPhoneAccountSettings();

  // ── Permissions ───────────────────────────────────────────────────────

  /// Returns true if microphone (RECORD_AUDIO) permission is granted.
  Future<bool> hasMicAccess();

  /// Requests microphone (RECORD_AUDIO) permission.
  Future<bool?> requestMicAccess();

  /// Returns true if READ_PHONE_STATE permission is granted. Android only.
  Future<bool> hasReadPhoneStatePermission();

  /// Requests READ_PHONE_STATE permission. Android only.
  Future<bool?> requestReadPhoneStatePermission();

  /// Returns true if CALL_PHONE permission is granted. Android only.
  Future<bool> hasCallPhonePermission();

  /// Requests CALL_PHONE permission. Android only.
  Future<bool?> requestCallPhonePermission();

  /// Returns true if MANAGE_OWN_CALLS permission is granted. Android only.
  Future<bool> hasManageOwnCallsPermission();

  /// Requests MANAGE_OWN_CALLS permission. Android only.
  Future<bool?> requestManageOwnCallsPermission();

  /// Returns true if READ_PHONE_NUMBERS permission is granted. Android only.
  Future<bool> hasReadPhoneNumbersPermission();

  /// Requests READ_PHONE_NUMBERS permission. Android only.
  Future<bool?> requestReadPhoneNumbersPermission();

  /// Deprecated — Bluetooth is now handled by the native call screen.
  @Deprecated('custom call UI not used anymore, has no effect')
  Future<bool> hasBluetoothPermissions();

  /// Deprecated — Bluetooth is now handled by the native call screen.
  @Deprecated('custom call UI not used anymore, has no effect')
  Future<bool?> requestBluetoothPermissions();

  // ── Call rejection behaviour ──────────────────────────────────────────

  /// Auto-reject incoming calls when required permissions are missing.
  ///
  /// [shouldReject] — true to reject immediately, false to let ring.
  /// Android only.
  Future<bool> rejectCallOnNoPermissions({bool shouldReject = false});

  /// Returns true if calls are being auto-rejected on missing permissions.
  /// Android only.
  Future<bool> isRejectingCallOnNoPermissions();

  // ── iOS CallKit ───────────────────────────────────────────────────────

  /// Sets a custom icon for the iOS CallKit UI.
  /// No-op on Android.
  Future<bool?> updateCallKitIcon({String? icon});

  // ── Caller registry ───────────────────────────────────────────────────

  /// Store a display name for a caller identity.
  ///
  /// Used to show a human-readable name instead of a raw ID
  /// on the incoming call screen.
  Future<bool?> registerClient(String clientId, String clientName);

  /// Remove a previously registered caller identity mapping.
  Future<bool?> unregisterClient(String clientId);

  /// Set the fallback display name for callers with no registered mapping.
  Future<bool?> setDefaultCallerName(String callerName);

  // ── Deprecated stubs ──────────────────────────────────────────────────

  /// Deprecated — ConnectionService replaced custom background UI.
  @Deprecated('custom call UI not used anymore, has no effect')
  Future<bool?> showBackgroundCallUI();

  // ── Event parsing ─────────────────────────────────────────────────────

  /// Parses a raw pipe-delimited event string from the native layer
  /// into a typed [CallEvent] enum value.
  ///
  /// Called internally by [callEventsListener] — you should not
  /// need to call this directly in your app.
  CallEvent parseCallEvent(String state);
}
