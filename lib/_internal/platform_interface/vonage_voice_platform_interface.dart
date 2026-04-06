import 'dart:async';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../../vonage_voice.dart';
import '../method_channel/vonage_voice_method_channel.dart';
import 'shared_platform_interface.dart';
import 'vonage_call_platform_interface.dart';

/// Callback invoked when the native push token changes and needs re-registration.
///
/// **Android:** fired when the FCM device token is refreshed by Google Play Services.
/// **iOS:** fired when PushKit delivers a new VoIP push token after the old one expires.
///
/// You should send the new [token] to your backend so Vonage can continue
/// delivering incoming-call push notifications to this device.
///
/// ```dart
/// VonageVoice.instance.setOnDeviceTokenChanged((newToken) {
///   myBackend.updatePushToken(newToken);
/// });
/// ```
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

  // ── Call session manager ──────────────────────────────────────────────

  /// Manages call session state across events.
  ///
  /// Tracks [CallSession] objects for each concurrent call,
  /// updating status as events flow in from the native layer.
  CallSessionManager get callSessionManager;

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

  // ── FCM / VoIP Token Callback ──────────────────────────────────────────

  /// Optional callback fired when the native push token is refreshed.
  ///
  /// **Android:** triggered by FCM token rotation (Google Play Services may
  /// rotate the token at any time — typically on app reinstall, data clear,
  /// or restore on a new device).
  ///
  /// **iOS:** triggered when PushKit delivers a new VoIP push token
  /// (e.g. after token expiry or device restore from backup).
  ///
  /// When this fires, send the new token to your backend so Vonage can
  /// continue delivering incoming-call push notifications.
  OnDeviceTokenChanged? deviceTokenChanged;

  /// Registers a callback that fires whenever the native push token changes.
  ///
  /// ```dart
  /// VonageVoice.instance.setOnDeviceTokenChanged((newToken) {
  ///   // Send this token to your server to update Vonage push registration.
  ///   myBackend.updatePushToken(newToken);
  /// });
  /// ```
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
  /// [isSandbox] — iOS only: whether to register VoIP push token with
  ///   Apple's sandbox (development) or production APNS. Defaults to `false`
  ///   (production). Set to `true` when running debug/development builds.
  ///   Ignored on Android.
  ///
  /// ```dart
  /// await VonageVoice.instance.setTokens(
  ///   accessToken: jwtFromBackend,
  ///   deviceToken: fcmToken,
  ///   isSandbox: true, // for development builds
  /// );
  /// ```
  Future<bool?> setTokens({
    required String accessToken,
    String? deviceToken,
    bool isSandbox = false,
  });

  /// Controls whether the plugin shows a local notification for missed calls.
  ///
  /// When `true`, the native layer posts a notification if an incoming call
  /// ends before the user answers (e.g. the caller hangs up or the invite
  /// times out). The setting is persisted in shared preferences and survives
  /// app restarts until you explicitly change it.
  ///
  /// **Platform:** Android & iOS.
  ///
  /// ```dart
  /// // Enable missed call notifications
  /// VonageVoice.instance.showMissedCallNotifications = true;
  ///
  /// // Disable them
  /// VonageVoice.instance.showMissedCallNotifications = false;
  /// ```
  set showMissedCallNotifications(bool value);

  /// Unregisters the push token and ends the current Vonage session.
  ///
  /// **Android:** unregisters the FCM device token from Vonage,
  /// then deletes the Vonage session.
  /// **iOS:** unregisters the VoIP push token, then deletes the session.
  ///
  /// After calling this, the device will no longer receive incoming call
  /// push notifications until [setTokens] is called again.
  ///
  /// [accessToken] is unused — kept for API compatibility with the
  /// Twilio Voice plugin migration path.
  ///
  /// Returns `true` if unregistration succeeded.
  ///
  /// ```dart
  /// await VonageVoice.instance.unregister();
  /// ```
  Future<bool?> unregister({String? accessToken});

  /// Refreshes the Vonage JWT without tearing down the active session.
  ///
  /// Vonage JWTs have a configurable TTL (typically 24 hours). Call this
  /// method before the current token expires to keep the session alive.
  /// If the token has already expired, the SDK will disconnect and you
  /// must call [setTokens] again to re-establish the session.
  ///
  /// **Platform:** Android & iOS.
  ///
  /// [accessToken] — the fresh JWT obtained from your backend.
  ///
  /// Returns `true` if the session was refreshed successfully.
  ///
  /// ```dart
  /// // Proactively refresh before expiry (e.g. on a timer)
  /// final freshJwt = await myBackend.getNewVonageJwt();
  /// await VonageVoice.instance.refreshSession(accessToken: freshJwt);
  /// ```
  Future<bool?> refreshSession({required String accessToken});

  // ── Deprecated — Background Permissions ──────────────────────────────
  //
  // These methods existed when the plugin used a custom overlay to display
  // an incoming-call UI while the app was in the background. That approach
  // required SYSTEM_ALERT_WINDOW ("draw over other apps") on Android.
  //
  // Now the plugin uses Android's ConnectionService (Telecom framework)
  // which shows the native incoming-call screen — no overlay permission
  // needed. On iOS, CallKit always handled this natively.
  //
  // Migration: simply remove any calls to these methods from your code.
  //
  // ─────────────────────────────────────────────────────────────────────

  /// **Deprecated** — No longer needed.
  ///
  /// ### Why deprecated?
  /// The plugin previously used a custom overlay UI for incoming calls in
  /// the background, which required the `SYSTEM_ALERT_WINDOW` permission
  /// on Android. Now, Android's `ConnectionService` (Telecom framework)
  /// handles the native incoming-call screen automatically.
  ///
  /// On iOS, CallKit has always managed this natively.
  ///
  /// ### Migration
  /// Remove the call — no replacement needed.
  ///
  /// ```dart
  /// // Before (old way):
  /// if (await VonageVoice.instance.requiresBackgroundPermissions()) {
  ///   await VonageVoice.instance.requestBackgroundPermissions();
  /// }
  ///
  /// // After (new way):
  /// // Just delete the above code — ConnectionService handles it.
  /// ```
  ///
  /// Always returns `false` — no permission is ever required.
  @Deprecated(
    'No longer needed — Android ConnectionService shows the native incoming-call '
    'screen automatically. Remove calls to this method. Always returns false.',
  )
  Future<bool> requiresBackgroundPermissions();

  /// **Deprecated** — No longer needed.
  ///
  /// ### Why deprecated?
  /// Previously requested `SYSTEM_ALERT_WINDOW` permission for a custom
  /// background call overlay. The plugin now uses `ConnectionService`
  /// which shows the native call UI without any special permission.
  ///
  /// ### Migration
  /// Remove the call — no replacement needed.
  ///
  /// ```dart
  /// // Before (old way):
  /// await VonageVoice.instance.requestBackgroundPermissions();
  ///
  /// // After (new way):
  /// // Delete the call. Android's Telecom framework manages it.
  /// ```
  ///
  /// Always returns `false`.
  @Deprecated(
    'No longer needed — Android ConnectionService handles background calls '
    'automatically. Remove calls to this method. Always returns false.',
  )
  Future<bool?> requestBackgroundPermissions();

  // ── Telecom / PhoneAccount (Android only) ─────────────────────────────

  /// Checks whether this app has registered a Telecom `PhoneAccount`.
  ///
  /// On Android, the plugin uses the Telecom `ConnectionService` framework
  /// to manage calls. Before the plugin can place or receive calls through
  /// the native call screen, the app must register a `PhoneAccount` with
  /// the system.
  ///
  /// **Platform:** Android only — always returns `true` on iOS.
  ///
  /// Returns `true` if the `PhoneAccount` exists.
  ///
  /// See also: [registerPhoneAccount], [isPhoneAccountEnabled].
  Future<bool> hasRegisteredPhoneAccount();

  /// Registers this app's `PhoneAccount` with Android's Telecom framework.
  ///
  /// Must be called once (typically on first launch or after app data clear)
  /// before the plugin can place or receive calls on Android.
  ///
  /// After registration, the user must also **enable** the phone account
  /// in system settings — check with [isPhoneAccountEnabled] and guide
  /// the user to [openPhoneAccountSettings] if needed.
  ///
  /// **Platform:** Android only — no-op on iOS (returns `true`).
  ///
  /// ```dart
  /// if (!await VonageVoice.instance.hasRegisteredPhoneAccount()) {
  ///   await VonageVoice.instance.registerPhoneAccount();
  /// }
  /// ```
  Future<bool?> registerPhoneAccount();

  /// Checks whether the app's `PhoneAccount` is enabled in system settings.
  ///
  /// Even after [registerPhoneAccount], the user may need to manually
  /// enable the account in Settings → Phone → Calling accounts.
  /// If this returns `false`, guide the user to enable it.
  ///
  /// **Platform:** Android only — always returns `true` on iOS.
  ///
  /// See also: [openPhoneAccountSettings].
  Future<bool> isPhoneAccountEnabled();

  /// Opens the system "Phone accounts" / "Calling accounts" settings screen.
  ///
  /// Use this when [isPhoneAccountEnabled] returns `false` to let the user
  /// enable the app's phone account.
  ///
  /// **Platform:** Android only — no-op on iOS (returns `true`).
  ///
  /// ```dart
  /// if (!await VonageVoice.instance.isPhoneAccountEnabled()) {
  ///   await VonageVoice.instance.openPhoneAccountSettings();
  /// }
  /// ```
  Future<bool?> openPhoneAccountSettings();

  // ── Permissions ───────────────────────────────────────────────────────

  /// Checks whether the microphone (`RECORD_AUDIO`) permission is granted.
  ///
  /// Voice calls require microphone access on both platforms.
  ///
  /// **Android:** checks `Manifest.permission.RECORD_AUDIO`.
  /// **iOS:** checks `AVAudioSession.recordPermission`.
  ///
  /// Returns `true` if permission is granted.
  ///
  /// See also: [requestMicAccess].
  Future<bool> hasMicAccess();

  /// Requests the microphone (`RECORD_AUDIO`) runtime permission.
  ///
  /// Shows the system permission dialog if not yet granted.
  ///
  /// **Android:** requests `Manifest.permission.RECORD_AUDIO`.
  /// **iOS:** requests `AVAudioSession.requestRecordPermission`.
  ///
  /// Returns `true` if the user granted permission.
  ///
  /// ```dart
  /// if (!await VonageVoice.instance.hasMicAccess()) {
  ///   await VonageVoice.instance.requestMicAccess();
  /// }
  /// ```
  Future<bool?> requestMicAccess();

  /// Checks whether `READ_PHONE_STATE` permission is granted.
  ///
  /// Required by Android's Telecom framework to manage calls properly.
  /// Without it, the plugin may not be able to detect the phone's call state.
  ///
  /// **Platform:** Android only — always returns `true` on iOS.
  ///
  /// See also: [requestReadPhoneStatePermission].
  Future<bool> hasReadPhoneStatePermission();

  /// Requests `READ_PHONE_STATE` runtime permission.
  ///
  /// **Platform:** Android only — no-op on iOS (returns `true`).
  Future<bool?> requestReadPhoneStatePermission();

  /// Checks whether `CALL_PHONE` permission is granted.
  ///
  /// Required for the Telecom `ConnectionService` to place outgoing calls.
  ///
  /// **Platform:** Android only — always returns `true` on iOS.
  ///
  /// See also: [requestCallPhonePermission].
  Future<bool> hasCallPhonePermission();

  /// Requests `CALL_PHONE` runtime permission.
  ///
  /// **Platform:** Android only — no-op on iOS (returns `true`).
  Future<bool?> requestCallPhonePermission();

  /// Checks whether `MANAGE_OWN_CALLS` permission is granted.
  ///
  /// Required by the Telecom framework so the app can manage its own
  /// VoIP calls through the `ConnectionService`.
  ///
  /// **Platform:** Android only — always returns `true` on iOS.
  ///
  /// See also: [requestManageOwnCallsPermission].
  Future<bool> hasManageOwnCallsPermission();

  /// Requests `MANAGE_OWN_CALLS` runtime permission.
  ///
  /// **Platform:** Android only — no-op on iOS (returns `true`).
  Future<bool?> requestManageOwnCallsPermission();

  /// Checks whether `READ_PHONE_NUMBERS` permission is granted.
  ///
  /// Needed by some OEMs for the Telecom `PhoneAccount` to display the
  /// app's calling account correctly in system settings.
  ///
  /// **Platform:** Android only — always returns `true` on iOS.
  ///
  /// See also: [requestReadPhoneNumbersPermission].
  Future<bool> hasReadPhoneNumbersPermission();

  /// Requests `READ_PHONE_NUMBERS` runtime permission.
  ///
  /// **Platform:** Android only — no-op on iOS (returns `true`).
  Future<bool?> requestReadPhoneNumbersPermission();

  // ── Deprecated — Bluetooth Permissions ─────────────────────────────
  //
  // These methods existed when the plugin handled Bluetooth audio routing
  // from a custom in-app call UI that needed BLUETOOTH_CONNECT permission.
  //
  // Now the native Telecom/CallKit layer manages audio routing, including
  // Bluetooth, without any special runtime permission from the app.
  //
  // Migration: remove calls to these methods. Use toggleBluetooth() on
  // the call interface if you need to programmatically switch audio routes.
  //
  // ─────────────────────────────────────────────────────────────────────

  /// **Deprecated** — Bluetooth permissions are no longer needed.
  ///
  /// ### Why deprecated?
  /// The plugin previously managed a custom in-app call UI that needed
  /// `BLUETOOTH_CONNECT` permission to route audio to BT headsets.
  /// Now, the native Telecom layer (Android) and CallKit (iOS) handle
  /// Bluetooth audio routing automatically.
  ///
  /// ### Migration
  /// Remove the call. If you need to switch audio routes programmatically,
  /// use [VonageCallPlatform.toggleBluetooth] instead:
  ///
  /// ```dart
  /// // Before (old way):
  /// if (!await VonageVoice.instance.hasBluetoothPermissions()) {
  ///   await VonageVoice.instance.requestBluetoothPermissions();
  /// }
  ///
  /// // After (new way):
  /// // Delete the permission check. Just toggle Bluetooth directly:
  /// await VonageVoice.instance.call.toggleBluetooth(bluetoothOn: true);
  /// ```
  ///
  /// Always returns `false` on Android. Returns `true` on iOS (no
  /// runtime Bluetooth permission is needed on iOS for audio routing).
  @Deprecated(
    'No longer needed — the native Telecom/CallKit layer manages Bluetooth '
    'audio routing automatically. Use call.toggleBluetooth() instead. '
    'Always returns false on Android, true on iOS.',
  )
  Future<bool> hasBluetoothPermissions();

  /// **Deprecated** — Bluetooth permissions are no longer needed.
  ///
  /// ### Why deprecated?
  /// Same as [hasBluetoothPermissions] — the native call layer handles
  /// Bluetooth without requiring a runtime permission from the app.
  ///
  /// ### Migration
  /// Remove the call. Use [VonageCallPlatform.toggleBluetooth] directly.
  ///
  /// Always returns `false` on Android, `true` on iOS.
  @Deprecated(
    'No longer needed — the native Telecom/CallKit layer manages Bluetooth '
    'audio routing automatically. Use call.toggleBluetooth() instead. '
    'Always returns false on Android, true on iOS.',
  )
  Future<bool?> requestBluetoothPermissions();

  // ── Notification Permission ────────────────────────────────────────

  /// Checks whether `POST_NOTIFICATIONS` permission is granted.
  ///
  /// On Android 13+ (API 33+), apps must request this permission at runtime
  /// before they can show any notifications — including missed-call and
  /// incoming-call notifications.
  ///
  /// **Platform:** Android only — always returns `true` on iOS and on
  /// Android versions below API 33 (where no runtime permission is needed).
  ///
  /// See also: [requestNotificationPermission].
  Future<bool> hasNotificationPermission();

  /// Requests `POST_NOTIFICATIONS` runtime permission.
  ///
  /// Shows the system permission dialog on Android 13+ (API 33+).
  /// Returns `true` immediately on older Android versions and on iOS.
  ///
  /// **Platform:** Android only — no-op on iOS (returns `true`).
  ///
  /// ```dart
  /// if (!await VonageVoice.instance.hasNotificationPermission()) {
  ///   await VonageVoice.instance.requestNotificationPermission();
  /// }
  /// ```
  Future<bool?> requestNotificationPermission();

  // ── Call Rejection Behaviour ──────────────────────────────────────────

  /// Configures whether to auto-reject incoming calls when required
  /// permissions (microphone, phone state, etc.) are missing.
  ///
  /// When [shouldReject] is `true`, the plugin will automatically decline
  /// incoming call invites if critical permissions haven't been granted.
  /// This prevents a poor UX where the call connects but the remote party
  /// can't hear anything because the mic permission was denied.
  ///
  /// When `false` (default), the call will ring normally and the user
  /// can answer — but audio may not work if permissions are missing.
  ///
  /// **Platform:** Android only — no-op on iOS (returns `true`).
  ///
  /// ```dart
  /// // Reject calls automatically if permissions aren't granted
  /// await VonageVoice.instance.rejectCallOnNoPermissions(shouldReject: true);
  /// ```
  Future<bool> rejectCallOnNoPermissions({bool shouldReject = false});

  /// Checks whether incoming calls are being auto-rejected when permissions
  /// are missing.
  ///
  /// Returns `true` if [rejectCallOnNoPermissions] was called with `true`.
  ///
  /// **Platform:** Android only — always returns `false` on iOS.
  Future<bool> isRejectingCallOnNoPermissions();

  // ── iOS CallKit ───────────────────────────────────────────────────────

  /// Sets a custom icon for the iOS CallKit incoming-call screen.
  ///
  /// The [icon] should be the name of an image asset in your iOS app's
  /// asset catalog (without the file extension). The image should be a
  /// 40×40 point template image (80×80 px @2x, 120×120 px @3x).
  ///
  /// If [icon] is `null`, the default "callkit_icon" asset name is used.
  ///
  /// **Platform:** iOS only — no-op on Android.
  ///
  /// ```dart
  /// await VonageVoice.instance.updateCallKitIcon(icon: 'my_call_icon');
  /// ```
  Future<bool?> updateCallKitIcon({String? icon});

  // ── Caller Registry ────────────────────────────────────────────────────

  /// Registers a display name for a specific caller identity.
  ///
  /// When an incoming call arrives, the plugin looks up the caller's
  /// identity in this registry. If found, the display name is shown on
  /// the native incoming-call screen (Android Telecom / iOS CallKit)
  /// instead of the raw Vonage user ID or phone number.
  ///
  /// The mapping is persisted in `SharedPreferences` (Android) /
  /// `UserDefaults` (iOS) and survives app restarts.
  ///
  /// **Platform:** Android & iOS.
  ///
  /// [clientId] — the Vonage user ID or phone number to map.
  /// [clientName] — the human-readable name to display.
  ///
  /// ```dart
  /// await VonageVoice.instance.registerClient('user-123', 'Alice Smith');
  /// await VonageVoice.instance.registerClient('+14155551234', 'Bob Jones');
  /// ```
  Future<bool?> registerClient(String clientId, String clientName);

  /// Removes a previously registered caller identity mapping.
  ///
  /// After removal, incoming calls from [clientId] will show the
  /// [setDefaultCallerName] fallback (or "Unknown Caller").
  ///
  /// **Platform:** Android & iOS.
  Future<bool?> unregisterClient(String clientId);

  /// Sets the fallback display name shown for callers with no registered
  /// identity mapping.
  ///
  /// Defaults to `"Unknown Caller"` if never set.
  ///
  /// **Platform:** Android & iOS.
  ///
  /// ```dart
  /// await VonageVoice.instance.setDefaultCallerName('Vonage Call');
  /// ```
  Future<bool?> setDefaultCallerName(String callerName);

  /// Forwards a raw FCM push payload to the native Vonage SDK for processing.
  ///
  /// When `firebase_messaging` intercepts an FCM message in Flutter land,
  /// the native Vonage SDK never sees it. Call this method from both
  /// [FirebaseMessaging.onMessage] and [FirebaseMessaging.onBackgroundMessage]
  /// so the SDK can detect and process incoming-call push notifications.
  ///
  /// **Android:** forwards [data] to `VoiceClient.processPushNotification()`.
  /// **iOS:** handled automatically via PushKit; this is a no-op but included
  /// for cross-platform API consistency.
  ///
  /// [data] — the `RemoteMessage.data` map from `firebase_messaging`.
  ///
  /// Returns the Vonage call ID if the push was a call invite, or `null`
  /// if it wasn't a Vonage push.
  ///
  /// ```dart
  /// FirebaseMessaging.onMessage.listen((message) {
  ///   VonageVoice.instance.processVonagePush(message.data);
  /// });
  ///
  /// // Also handle background messages:
  /// @pragma('vm:entry-point')
  /// Future<void> firebaseMessagingBackgroundHandler(RemoteMessage msg) async {
  ///   await VonageVoice.instance.processVonagePush(msg.data);
  /// }
  /// ```
  Future<String?> processVonagePush(Map<String, dynamic> data);

  // ── Battery / Power Optimization (Android only) ──────────────────────

  /// Checks whether the app is subject to Android's battery optimization.
  ///
  /// On OEMs like **Vivo, Xiaomi, OPPO, Samsung, and Huawei**, aggressive
  /// battery optimization kills background services and prevents FCM from
  /// delivering incoming-call push notifications when the app is closed.
  ///
  /// If this returns `true`, you should call
  /// [requestBatteryOptimizationExemption] to ask the user to exempt the app.
  ///
  /// **Platform:** Android only — always returns `false` on iOS.
  ///
  /// ```dart
  /// if (await VonageVoice.instance.isBatteryOptimized()) {
  ///   // Show a dialog explaining why the exemption is needed
  ///   await VonageVoice.instance.requestBatteryOptimizationExemption();
  /// }
  /// ```
  Future<bool> isBatteryOptimized();

  /// Opens the system dialog to exempt the app from battery optimization.
  ///
  /// This is **essential** on Vivo, Xiaomi, OPPO, Samsung, and other OEMs
  /// with aggressive battery management. Without this exemption, incoming
  /// calls will not work reliably when the app is in the background or killed.
  ///
  /// On stock Android, this opens the standard
  /// `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` dialog.
  ///
  /// **Platform:** Android only — no-op on iOS (returns `true`).
  Future<bool?> requestBatteryOptimizationExemption();

  // ── Full-Screen Intent Permission (Android 14+ / API 34+) ──────────

  /// Checks if the app can show full-screen incoming-call UI on the lock screen.
  ///
  /// Starting with **Android 14 (API 34)**, `USE_FULL_SCREEN_INTENT` is a
  /// special permission that must be explicitly granted by the user.
  /// Without it, incoming-call notifications will appear as a small
  /// heads-up notification instead of the full-screen incoming-call screen.
  ///
  /// **Platform:** Android only — always returns `true` on iOS and on
  /// Android versions below API 34 (where this permission is auto-granted).
  ///
  /// ```dart
  /// if (!await VonageVoice.instance.canUseFullScreenIntent()) {
  ///   // Guide the user to enable full-screen notifications
  ///   await VonageVoice.instance.openFullScreenIntentSettings();
  /// }
  /// ```
  ///
  /// See also: [openFullScreenIntentSettings].
  Future<bool> canUseFullScreenIntent();

  /// Opens the system settings screen where the user can grant
  /// `USE_FULL_SCREEN_INTENT` permission.
  ///
  /// Only meaningful on **Android 14+** (API 34+). On older versions and
  /// on iOS this is a no-op that returns `true`.
  ///
  /// **Platform:** Android only.
  Future<bool?> openFullScreenIntentSettings();

  // ── Overlay / "Display over other apps" permission ──────────────────

  /// Checks if the app has `SYSTEM_ALERT_WINDOW` ("Display over other apps")
  /// permission granted.
  ///
  /// On **Samsung** and many OEMs, this must be explicitly enabled for the
  /// native incoming call screen to launch from background/locked state.
  /// This is what **WhatsApp** and **Botim** use to show calls reliably.
  ///
  /// Returns `true` on iOS and on Android < 6.0 (auto-granted).
  ///
  /// ```dart
  /// if (!await VonageVoice.instance.canDrawOverlays()) {
  ///   await VonageVoice.instance.openOverlaySettings();
  /// }
  /// ```
  ///
  /// See also: [openOverlaySettings].
  Future<bool> canDrawOverlays();

  /// Opens the system settings screen where the user can grant
  /// `SYSTEM_ALERT_WINDOW` ("Display over other apps" / "Appear on top").
  ///
  /// **Platform:** Android only — no-op on iOS.
  Future<bool?> openOverlaySettings();

  // ── Deprecated — Background Call UI ─────────────────────────────────
  //
  // This method showed a custom floating overlay UI when a call was active
  // and the app was in the background. That approach required
  // SYSTEM_ALERT_WINDOW permission and a custom Android Service.
  //
  // Now the plugin uses ConnectionService (Android) and CallKit (iOS),
  // which show the native OS call notification / call screen automatically.
  //
  // Migration: remove the call — the native layer handles it.
  //
  // ─────────────────────────────────────────────────────────────────────

  /// **Deprecated** — Custom background call UI is no longer used.
  ///
  /// ### Why deprecated?
  /// The plugin previously showed a custom floating overlay (using
  /// `SYSTEM_ALERT_WINDOW`) when the app was backgrounded during a call.
  /// Now, `ConnectionService` (Android) and `CallKit` (iOS) manage the
  /// native call notification and ongoing-call UI automatically.
  ///
  /// ### Migration
  /// Remove the call — the native OS handles the background call UI.
  ///
  /// ```dart
  /// // Before (old way):
  /// await VonageVoice.instance.showBackgroundCallUI();
  ///
  /// // After (new way):
  /// // Delete the call. ConnectionService / CallKit shows the native UI.
  /// ```
  ///
  /// Always returns `true` (no-op success).
  @Deprecated(
    'No longer needed — ConnectionService (Android) and CallKit (iOS) show the '
    'native background call UI automatically. Remove calls to this method. '
    'Always returns true.',
  )
  Future<bool?> showBackgroundCallUI();

  // ── Event Parsing (internal) ────────────────────────────────────────

  /// Parses a raw pipe-delimited event string from the native layer
  /// into a typed [CallEvent] enum value.
  ///
  /// Both Android and iOS emit the same pipe-delimited string format over
  /// the `EventChannel`. This method is the central router that converts
  /// those strings into typed `CallEvent` values and updates
  /// [call.activeCall] state accordingly.
  ///
  /// **You should not need to call this directly** — it is invoked
  /// internally by [callEventsListener].
  ///
  /// Native event format examples:
  /// ```
  /// "Ringing|+14155551234|+14158765432|Outgoing"
  /// "Connected|+14155551234|+14158765432|Incoming"
  /// "Incoming|+14155551234|+14158765432|Incoming|{\"key\":\"value\"}"
  /// "PERMISSION|Microphone|true"   (Android only)
  /// "AudioRoute|speaker|bluetoothAvailable=true"  (iOS only)
  /// "Call Ended"
  /// "Call Error: some message"
  /// ```
  CallEvent parseCallEvent(String state);
}
