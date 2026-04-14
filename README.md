# Vonage Voice - Flutter Plugin

[![Platform](https://img.shields.io/badge/platform-android%20%7C%20ios-blue)](https://github.com/ashiqualii/vonage_voice)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

Build native-feeling voice calling into a Flutter app with the Vonage Client SDK.

This plugin is built around real mobile call behavior instead of a custom overlay-only approach:

- Android incoming calls are handled through native FCM delivery, Telecom, and ConnectionService.
- iOS incoming calls are handled through PushKit and CallKit.
- Background and killed-state incoming call delivery are supported.
- Audio controls, Bluetooth routing, hold, DTMF, caller-name mapping, session refresh, and logout are exposed in Dart.

The plugin is designed for a single active call flow and a host app that wants native system integration plus full control over its own Flutter UI.

| Platform | Minimum Version | Native Call Stack |
|----------|------------------|-------------------|
| Android  | API 24 (Android 7.0) | FCM + Telecom + ConnectionService |
| iOS      | 13.0 | PushKit + CallKit |

---

## Table of Contents

- [What This Plugin Handles](#what-this-plugin-handles)
- [Before You Start](#before-you-start)
- [How Calls Are Handled](#how-calls-are-handled)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Android Setup](#android-setup)
- [iOS Setup](#ios-setup)
- [Upload Push Credentials](#upload-push-credentials)
- [App Bootstrap](#app-bootstrap)
- [Login and Session Registration](#login-and-session-registration)
- [Receiving Incoming Calls](#receiving-incoming-calls)
- [Making Outgoing Calls](#making-outgoing-calls)
- [In-Call Controls](#in-call-controls)
- [Caller Display and Optional Behavior](#caller-display-and-optional-behavior)
- [Token Refresh, Token Rotation, and Logout](#token-refresh-token-rotation-and-logout)
- [Call Events](#call-events)
- [Full API Reference](#full-api-reference)
- [Troubleshooting](#troubleshooting)
- [Example App](#example-app)
- [License](#license)

---

## What This Plugin Handles

The plugin already implements these pieces for you:

- Native incoming and outgoing call integration on both platforms.
- Android native incoming-call delivery through `VonageFirebaseMessagingService`, `TVConnectionService`, Telecom, and the lock-screen incoming call UI.
- iOS native incoming-call delivery through PushKit, CallKit, and killed-state session recovery.
- Background, killed-state, and lock-screen call handling.
- Audio routing for earpiece, speaker, Bluetooth, and explicit audio-device selection.
- DTMF, mute, hold, active call metadata, missed-call notifications, and caller-name mapping.
- Session refresh, logout, push-token change callbacks, and Android reliability helpers such as battery-optimization and full-screen-intent checks.

Your app still owns:

- JWT generation on your backend.
- Platform configuration in the host app.
- Runtime permission onboarding.
- Your Flutter screens and navigation flow.
- Uploading push credentials to the Vonage Dashboard.

---

## Before You Start

You need these pieces before the plugin can work end to end:

| Requirement | Why It Is Needed | Where It Comes From |
|-------------|------------------|---------------------|
| Vonage Application with Voice enabled | Calls are routed through your Vonage application | [Vonage Dashboard](https://dashboard.nexmo.com/applications) |
| Backend endpoint that mints JWTs | Devices authenticate to Vonage with short-lived JWTs | Your backend |
| Android Firebase project | Android incoming calls are delivered via FCM | [Firebase Flutter setup](https://firebase.google.com/docs/flutter/setup) |
| iOS VoIP push certificate (`.p12`) | Vonage sends iOS incoming call pushes through APNs VoIP | Apple Developer account |
| Dashboard push credentials | Incoming calls will not arrive without uploaded Android/iOS push credentials | Vonage Dashboard |

Recommended assumptions for production:

- Issue JWTs per user from your backend, not from the client.
- Treat push credentials and JWT generation as backend-owned concerns.
- Route incoming and connected call state into your own Flutter screens; let the plugin handle the native system side.

---

## How Calls Are Handled

This section explains the real runtime behavior implemented in the repository so your app architecture matches what the plugin actually does.

### Android Incoming Calls

1. Vonage sends an FCM push to the device.
2. The plugin's native `VonageFirebaseMessagingService` receives and validates the push.
3. Native Android code persists the invite, starts or resumes the foreground call service, and lets the Vonage SDK resolve the real call invite.
4. `TVConnectionService` uses Android Telecom and the self-managed phone account flow to surface the call.
5. The plugin posts the incoming-call notification and, when permitted, launches the full-screen incoming-call UI for lock-screen and background scenarios.
6. Answer and decline actions are handled natively first, then mirrored into Flutter through the event stream.

Important Android behavior:

- Background and killed-state incoming calls are handled natively.
- You should not use Dart FCM forwarding as the normal Android path.
- When the app is already in the foreground, you still receive Flutter call events and should present your own in-app call UI.
- The plugin contains OEM-specific reliability workarounds for battery optimization, full-screen intent, and overlay-related launch behavior.

### Android Outgoing Calls

1. Flutter calls `VonageVoice.instance.call.place(...)`.
2. The plugin delegates to the native Android call layer.
3. Telecom and ConnectionService manage the call lifecycle and audio focus.
4. Flutter receives `ringing`, `connected`, `callEnded`, and related events.

### iOS Incoming Calls

1. Vonage sends a VoIP push through APNs.
2. PushKit delivers the push to the plugin.
3. The plugin reports the call to CallKit immediately so iOS can show the native incoming-call UI.
4. If the app was killed, the plugin restores the Vonage session from persisted JWT state and then resolves the real invite details.
5. Any answer or decline action tapped before the real call ID arrives is deferred and fulfilled as soon as the invite is resolved.
6. Flutter receives the resulting call events and active-call state.

Important iOS behavior:

- PushKit is the primary incoming-call path.
- The plugin owns `PKPushRegistry` by default.
- Killed-state incoming calls are explicitly handled in native code.
- CallKit audio activation is handled internally so the SDK can enable media when iOS activates the call audio session.

### iOS Outgoing Calls

1. Flutter calls `VonageVoice.instance.call.place(...)`.
2. The plugin creates a `CXStartCallAction` and hands the call to CallKit.
3. The Vonage iOS SDK starts the call.
4. CallKit and the plugin keep Flutter in sync with ringing and connected state.

### Push Forwarding Rule

Use this rule of thumb:

- Android: native FCM handling is primary. Do not build your normal Android incoming-call flow around `processVonagePush()` from Dart.
- iOS: PushKit is primary. Only call `processVonagePush()` if your host app also intercepts Vonage-related FCM data messages in Dart and you need to forward them to the plugin.

---

## Installation

Add the plugin first:

```yaml
dependencies:
  vonage_voice:
```

If you want Android incoming calls, add Firebase to the host app:

```yaml
dependencies:
  vonage_voice:
  firebase_core:
  firebase_messaging:
```

Notes:

- `firebase_core` and `firebase_messaging` are required for Android incoming-call delivery.
- On iOS, PushKit is the primary incoming-call mechanism. Firebase is only needed if your app also uses Firebase messaging and you want to forward matching data pushes through Dart.

Then fetch packages:

```bash
flutter pub get
```

---

## Quick Start

This is the shortest practical path to a working integration.

1. Configure Android Firebase if you need Android incoming calls.
2. Configure iOS capabilities and VoIP push setup if you need iOS incoming calls.
3. Upload push credentials to the Vonage Dashboard.
4. Request runtime permissions and Android system settings your app depends on.
5. Get a JWT from your backend and call `setTokens(...)`.
6. Listen to `callEventsListener` globally.
7. Build your own Flutter incoming/active-call screens on top of the plugin state.

Minimal login example:

```dart
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:vonage_voice/vonage_voice.dart';

Future<void> registerForCalls() async {
  final jwt = await yourBackend.getVonageJwt();

  String? deviceToken;
  if (Platform.isAndroid) {
    deviceToken = await FirebaseMessaging.instance.getToken();
  }

  final ok = await VonageVoice.instance.setTokens(
    accessToken: jwt,
    deviceToken: deviceToken,
    isSandbox: false,
  );

  if (ok != true) {
    throw Exception('Vonage registration failed');
  }
}
```

Then place a call:

```dart
await VonageVoice.instance.call.place(
  from: 'alice',
  to: '+14155551234',
);
```

And listen for events:

```dart
VonageVoice.instance.callEventsListener.listen((event) {
  print('Call event: $event');
});
```

---

## Android Setup

### 1. Add Firebase Configuration

Place your `google-services.json` in the host app's Android app module:

```text
android/app/google-services.json
```

If your host app uses Kotlin DSL, add the Google Services plugin to `android/app/build.gradle.kts`:

```kotlin
plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}
```

And make sure it is available from the root/settings plugin management block:

```kotlin
plugins {
    id("com.google.gms.google-services") version "4.4.0" apply false
}
```

### 2. What the Plugin Already Contributes on Android

You do not need to manually copy the plugin's manifest entries into your host app. The plugin already contributes:

- Android permissions used by the native calling stack.
- `TVConnectionService` for Telecom/ConnectionService integration.
- `VonageFirebaseMessagingService` for native FCM handling.
- Incoming-call activities and notification action receivers.
- Boot receiver support for post-reboot messaging recovery.
- Consumer ProGuard/R8 configuration merge behavior.

What still remains your responsibility is runtime onboarding and OS-level settings.

### 3. Runtime Onboarding Your App Should Perform

The plugin declares permissions in the manifest, but Android still requires runtime permission requests and a few system-level enablement flows.

Recommended onboarding sequence:

```dart
Future<void> prepareAndroidCalling() async {
  await VonageVoice.instance.requestMicAccess();
  await VonageVoice.instance.requestReadPhoneStatePermission();
  await VonageVoice.instance.requestCallPhonePermission();
  await VonageVoice.instance.requestManageOwnCallsPermission();
  await VonageVoice.instance.requestReadPhoneNumbersPermission();
  await VonageVoice.instance.requestNotificationPermission();

  if (!await VonageVoice.instance.hasRegisteredPhoneAccount()) {
    await VonageVoice.instance.registerPhoneAccount();
  }

  if (!await VonageVoice.instance.isPhoneAccountEnabled()) {
    await VonageVoice.instance.openPhoneAccountSettings();
  }

  if (!await VonageVoice.instance.canUseFullScreenIntent()) {
    await VonageVoice.instance.openFullScreenIntentSettings();
  }

  if (await VonageVoice.instance.isBatteryOptimized()) {
    await VonageVoice.instance.requestBatteryOptimizationExemption();
  }

  if (!await VonageVoice.instance.canDrawOverlays()) {
    await VonageVoice.instance.openOverlaySettings();
  }
}
```

### 4. Android Permissions and Settings Checklist

Use this as the practical checklist for a production host app.

| Item | Type | Why It Matters |
|------|------|----------------|
| `RECORD_AUDIO` | Runtime permission | Required for actual call audio |
| `READ_PHONE_STATE` | Runtime permission | Required for Telecom state integration |
| `CALL_PHONE` | Runtime permission | Required for outgoing call placement through Telecom |
| `MANAGE_OWN_CALLS` | Runtime permission | Required for self-managed Telecom integration |
| `READ_PHONE_NUMBERS` | Runtime permission | Recommended for PhoneAccount/OEM compatibility |
| `POST_NOTIFICATIONS` | Runtime permission on API 33+ | Required for incoming/missed-call notifications |
| PhoneAccount registration | System integration | Android Telecom flow depends on it |
| PhoneAccount enabled in settings | System setting | Users may still need to enable the account manually |
| `USE_FULL_SCREEN_INTENT` | Android 14+ special permission | Needed for full-screen lock-screen incoming-call UI |
| Battery optimization exemption | System setting | Critical on Vivo, Xiaomi, OPPO, realme, Samsung-style OEM power managers |
| Overlay permission | OEM-specific setting | Improves lock-screen launch reliability on Samsung and MIUI-family devices |

Permissions and capabilities the plugin already merges for native operation include foreground service, phone-call foreground service type, microphone foreground service type, wake lock, vibration, Bluetooth, internet/network, boot completed, audio routing, and related manifest entries.

### 5. Android Behavior Notes

- Android incoming calls do not require Dart-side FCM forwarding in the normal integration path.
- The plugin uses native FCM handling even when the Flutter engine is not running.
- On lock screen and background flows, the plugin can show native full-screen UI and notification actions without Flutter code executing first.
- The app should still listen to the Flutter event stream and drive its own in-app screens when already in the foreground.
- The plugin includes reboot handling so the device can reinitialize messaging after a reboot.

### 6. Android OEM Notes

These are not theoretical edge cases; they are exactly the class of problems the native Android implementation is already working around.

- Vivo, Xiaomi, OPPO, realme, and similar OEMs may kill the app aggressively unless battery optimization is disabled.
- Samsung and some other OEMs may need overlay permission for the lock-screen incoming-call activity path to be reliable.
- Android 14+ can refuse to display full-screen call UI until the user grants full-screen-intent permission.
- Android 13+ requires notification permission before incoming-call notifications can be shown at all.

---

## iOS Setup

### 1. Set the Minimum iOS Version

In the host app `ios/Podfile`:

```ruby
platform :ios, '13.0'
```

Then install pods:

```bash
cd ios && pod install
```

### 2. Update `Info.plist`

Add microphone usage and background modes to the host app's `Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access to make and receive voice calls.</string>

<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
    <string>voip</string>
    <string>fetch</string>
    <string>remote-notification</string>
</array>
```

### 3. Enable Xcode Capabilities

Open the host app in Xcode and enable these capabilities:

| Capability | What To Enable |
|------------|----------------|
| Push Notifications | Enable |
| Background Modes | Audio, AirPlay and Picture in Picture |
| Background Modes | Voice over IP |
| Background Modes | Background fetch |
| Background Modes | Remote notifications |

### 4. Make Sure Your Entitlements Match the Push Environment

Your app entitlement must include the APNs environment:

```xml
<key>aps-environment</key>
<string>development</string>
```

Use `development` for debug/sandbox and `production` for release builds that use production APNs.

### 5. PushKit Ownership Model

The default and recommended path is simple:

- Do not write custom PushKit ownership code.
- Let the plugin own `PKPushRegistry`.
- Keep your `AppDelegate` minimal.

That is the same style shown by the example app.

Advanced integration is supported if your host app already owns `PKPushRegistry` for `.voIP`:

- Set `VonageVoicePlugin.pushKitSetupByAppDelegate = true` before plugin registration.
- Forward the VoIP token, push payload, and push completion callback to the plugin.
- Do not let two different parts of the app create competing `PKPushRegistry` owners for `.voIP`.

If your app already integrates another VoIP SDK or a custom PushKit stack, decide ownership explicitly before wiring this plugin in.

### 6. `isSandbox` Must Match Your Build and Credential Environment

When you call `setTokens(...)`, the `isSandbox` argument must match the APNs environment used by your VoIP credentials.

| Build / Push Environment | `isSandbox` |
|--------------------------|-------------|
| Debug / sandbox APNs | `true` |
| Release / production APNs | `false` |

If this value is wrong, iOS incoming calls will silently fail even if the rest of the setup looks correct.

### 7. iOS Behavior Notes

- PushKit is the primary iOS incoming-call delivery path.
- The plugin reports the call to CallKit immediately, including killed-state handling.
- The plugin persists session data needed to recover from killed-state incoming calls.
- Deferred answer and decline actions are handled natively when a user taps before the full invite has been resolved.
- The plugin owns CallKit audio activation internally; your Flutter code should not try to replace that with a custom audio bootstrap.
- The plugin includes a minimal privacy manifest bundle, but your host app is still responsible for its own overall privacy declarations.

---

## Upload Push Credentials

Go to the Vonage Dashboard for the same application your backend is using to mint JWTs.

Dashboard path:

```text
Vonage Dashboard -> Applications -> Your Vonage Application -> Push Credentials
```

Upload:

- Android: Firebase Server Key or FCM v1 service-account credential flow used by your backend.
- iOS: VoIP push certificate exported as `.p12`.

Without this step, incoming calls will not work even if the app-side code is correct.

---

## App Bootstrap

This section covers the host-app bootstrap code you should wire once.

### Firebase Bootstrap

If your app uses Firebase messaging for Android incoming calls, initialize Firebase before calling into the plugin.

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}
```

### Optional iOS FCM Forwarding

Only use this when your app is also receiving Vonage-related Firebase data messages in Dart on iOS.

Background handler:

```dart
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:vonage_voice/vonage_voice.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Platform.isIOS && message.data.isNotEmpty) {
    await VonageVoice.instance.processVonagePush(message.data);
  }
}
```

Register it during startup:

```dart
FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
```

Foreground forwarding:

```dart
FirebaseMessaging.onMessage.listen((message) {
  if (Platform.isIOS && message.data.isNotEmpty) {
    VonageVoice.instance.processVonagePush(message.data);
  }
});
```

Do not use that as the normal Android incoming-call path.

---

## Login and Session Registration

Register the device after you have completed platform setup and runtime onboarding.

```dart
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:vonage_voice/vonage_voice.dart';

Future<void> loginToVonage() async {
  final jwt = await yourBackend.getVonageJwt();

  String? deviceToken;
  if (Platform.isAndroid) {
    deviceToken = await FirebaseMessaging.instance.getToken();
  }

  final ok = await VonageVoice.instance.setTokens(
    accessToken: jwt,
    deviceToken: deviceToken,
    isSandbox: false,
  );

  if (ok != true) {
    throw Exception('Vonage session registration failed');
  }
}
```

Parameter reference:

| Parameter | Required | Meaning |
|-----------|----------|---------|
| `accessToken` | Yes | JWT from your backend |
| `deviceToken` | Android incoming calls | FCM token. Pass `null` on iOS unless you have a separate reason to supply one |
| `isSandbox` | iOS only | `true` for sandbox/debug VoIP push environment, `false` for production |

Useful session-level options:

```dart
VonageVoice.instance.showMissedCallNotifications = true;

VonageVoice.instance.setOnDeviceTokenChanged((newToken) {
  // Send the new token to your backend if you mirror token state there.
});
```

If you want the plugin to auto-reject incoming calls when required permissions are missing on Android:

```dart
await VonageVoice.instance.rejectCallOnNoPermissions(shouldReject: true);
```

---

## Receiving Incoming Calls

Listen to call events at the app level so your UI can react consistently whether the call started in foreground, background, or after a resumed app state.

```dart
VonageVoice.instance.callEventsListener.listen((event) {
  switch (event) {
    case CallEvent.incoming:
      final activeCall = VonageVoice.instance.call.activeCall;
      print('Incoming call from ${activeCall?.fromFormatted ?? activeCall?.from}');
      break;
    case CallEvent.connected:
      print('Call connected');
      break;
    case CallEvent.callEnded:
      print('Call ended');
      break;
    default:
      break;
  }
});
```

### Answer or Decline from Flutter

```dart
await VonageVoice.instance.call.answer();
await VonageVoice.instance.call.hangUp();
```

The user can also answer or decline from the native call UI without any Flutter button existing on screen.

### Foreground UI Expectation

When the host app is already open, the plugin still emits Flutter events and keeps `activeCall` updated. You should treat those events as the signal to push your own in-app incoming-call or active-call screen.

### Resume and Killed-State Recovery

On Android, if your app needs to reconstruct call UI after a resume from background or after interacting with a notification, call:

```dart
await VonageVoice.instance.call.getActiveCallOnResumeFromTerminatedState();
```

Then read `VonageVoice.instance.call.activeCall` and your event stream to route the UI.

Common incoming event sequences:

| Scenario | Typical Events |
|----------|----------------|
| User answers | `incoming -> answer -> connected -> callEnded` |
| User declines | `incoming -> callEnded` |
| Caller hangs up first | `incoming -> missedCall` or `callEnded` |

---

## Making Outgoing Calls

### Place a Call

```dart
final ok = await VonageVoice.instance.call.place(
  from: 'alice',
  to: '+14155551234',
  extraOptions: {
    'displayName': 'Alice',
  },
);
```

Parameter reference:

| Parameter | Required | Meaning |
|-----------|----------|---------|
| `from` | Yes | Calling identity |
| `to` | Yes | Destination identity or phone number |
| `extraOptions` | No | Extra backend-facing call metadata |

### Outgoing Call Progress

```dart
VonageVoice.instance.callEventsListener.listen((event) {
  switch (event) {
    case CallEvent.ringing:
      print('Remote side is ringing');
      break;
    case CallEvent.connected:
      print('Call connected');
      break;
    case CallEvent.callEnded:
      print('Call finished');
      break;
    default:
      break;
  }
});
```

### Read Active Call Details

```dart
final call = VonageVoice.instance.call.activeCall;

if (call != null) {
  print(call.from);
  print(call.to);
  print(call.fromFormatted);
  print(call.toFormatted);
  print(call.callDirection);
  print(call.initiated);
  print(call.customParams);
}
```

Useful helpers:

```dart
final onCall = await VonageVoice.instance.call.isOnCall();
final sid = await VonageVoice.instance.call.getSid();
```

---

## In-Call Controls

All in-call controls live on `VonageVoice.instance.call`.

### Mute

```dart
await VonageVoice.instance.call.toggleMute(true);
await VonageVoice.instance.call.toggleMute(false);
final muted = await VonageVoice.instance.call.isMuted();
```

### Speaker

```dart
await VonageVoice.instance.call.toggleSpeaker(true);
await VonageVoice.instance.call.toggleSpeaker(false);
final speakerOn = await VonageVoice.instance.call.isOnSpeaker();
```

### Hold / Resume

```dart
await VonageVoice.instance.call.holdCall(holdCall: true);
await VonageVoice.instance.call.holdCall(holdCall: false);
final onHold = await VonageVoice.instance.call.isHolding();
```

### Bluetooth Routing

```dart
final bluetoothAvailable =
    await VonageVoice.instance.call.isBluetoothAvailable() ?? false;

if (bluetoothAvailable) {
  await VonageVoice.instance.call.toggleBluetooth(bluetoothOn: true);
}
```

Helpers:

```dart
final bluetoothOn = await VonageVoice.instance.call.isBluetoothOn();
final bluetoothEnabled = await VonageVoice.instance.call.isBluetoothEnabled();
await VonageVoice.instance.call.showBluetoothEnablePrompt();
await VonageVoice.instance.call.openBluetoothSettings();
```

### Explicit Audio Device Selection

```dart
final devices = await VonageVoice.instance.call.getAudioDevices();

for (final device in devices) {
  print('${device.name} ${device.type} active=${device.isActive}');
}

if (devices.isNotEmpty) {
  await VonageVoice.instance.call.selectAudioDevice(devices.first.id);
}
```

### DTMF

```dart
await VonageVoice.instance.call.sendDigits('1');
await VonageVoice.instance.call.sendDigits('1234#');
```

### End the Call

```dart
await VonageVoice.instance.call.hangUp();
```

---

## Caller Display and Optional Behavior

### Caller Registry

Map raw Vonage IDs or phone numbers to display names that the native call UI can show:

```dart
await VonageVoice.instance.registerClient('user_123', 'Alice Smith');
await VonageVoice.instance.registerClient('+14155551234', 'Support Desk');
await VonageVoice.instance.unregisterClient('user_123');
await VonageVoice.instance.setDefaultCallerName('Unknown Caller');
```

### Missed-Call Notifications

```dart
VonageVoice.instance.showMissedCallNotifications = true;
```

The setting is persisted by the native layer until changed again.

### iOS CallKit Icon

```dart
await VonageVoice.instance.updateCallKitIcon(icon: 'MyCallIcon');
```

Use a template-style image in the iOS asset catalog. A 40x40pt CallKit-friendly monochrome asset is the expected shape.

### Auto-Reject When Permissions Are Missing

```dart
await VonageVoice.instance.rejectCallOnNoPermissions(shouldReject: true);
```

This is useful on Android when you would rather decline a call than let the user answer into a broken audio/session state.

---

## Token Refresh, Token Rotation, and Logout

### Refresh a JWT Before It Expires

```dart
final freshJwt = await yourBackend.getFreshVonageJwt();
await VonageVoice.instance.refreshSession(accessToken: freshJwt);
```

If the session has already expired completely, call `setTokens(...)` again.

### React to Token Rotation

```dart
VonageVoice.instance.setOnDeviceTokenChanged((newToken) async {
  await yourBackend.updatePushToken(newToken);
});
```

### Logout

```dart
await VonageVoice.instance.unregister();
```

After logout, the device will stop receiving incoming-call pushes until you register a session again.

---

## Call Events

Use `VonageVoice.instance.callEventsListener` as the canonical source of call lifecycle changes.

| Event | Meaning |
|-------|---------|
| `incoming` | Incoming call invite arrived |
| `ringing` | Outgoing call is ringing remotely |
| `connected` | Media is connected |
| `reconnecting` | Call is trying to recover after network loss |
| `reconnected` | Call recovered after network interruption |
| `callEnded` | Call ended |
| `answer` | Incoming call was answered |
| `declined` | Call was declined |
| `missedCall` | Call invite ended before answer |
| `hold` | Call put on hold |
| `unhold` | Call resumed from hold |
| `mute` | Microphone muted |
| `unmute` | Microphone unmuted |
| `speakerOn` | Speaker route enabled |
| `speakerOff` | Speaker route disabled |
| `bluetoothOn` | Bluetooth route enabled |
| `bluetoothOff` | Bluetooth route disabled |
| `returningCall` | Return-call flow triggered |
| `audioRouteChanged` | Native audio route changed |
| `permission` | Permission-related event emitted |
| `log` | Native log/diagnostic event |

---

## Full API Reference

<details>
<summary><b>Session and Device APIs</b></summary>

### `VonageVoice.instance`

| Method / Property | Returns | Description |
|-------------------|---------|-------------|
| `setTokens({accessToken, deviceToken?, isSandbox?})` | `Future<bool?>` | Register or re-register the Vonage session |
| `unregister({accessToken?})` | `Future<bool?>` | Logout and unregister push state |
| `refreshSession({accessToken})` | `Future<bool?>` | Refresh the current JWT |
| `callEventsListener` | `Stream<CallEvent>` | Global call event stream |
| `setOnDeviceTokenChanged(callback)` | `void` | Listen for native push-token rotation |
| `showMissedCallNotifications` | setter | Enable or disable missed-call notifications |
| `hasMicAccess()` | `Future<bool>` | Check microphone access |
| `requestMicAccess()` | `Future<bool?>` | Request microphone access |
| `hasReadPhoneStatePermission()` | `Future<bool>` | Check Android `READ_PHONE_STATE` |
| `requestReadPhoneStatePermission()` | `Future<bool?>` | Request Android `READ_PHONE_STATE` |
| `hasCallPhonePermission()` | `Future<bool>` | Check Android `CALL_PHONE` |
| `requestCallPhonePermission()` | `Future<bool?>` | Request Android `CALL_PHONE` |
| `hasManageOwnCallsPermission()` | `Future<bool>` | Check Android `MANAGE_OWN_CALLS` |
| `requestManageOwnCallsPermission()` | `Future<bool?>` | Request Android `MANAGE_OWN_CALLS` |
| `hasReadPhoneNumbersPermission()` | `Future<bool>` | Check Android `READ_PHONE_NUMBERS` |
| `requestReadPhoneNumbersPermission()` | `Future<bool?>` | Request Android `READ_PHONE_NUMBERS` |
| `hasNotificationPermission()` | `Future<bool>` | Check Android notification permission |
| `requestNotificationPermission()` | `Future<bool?>` | Request Android notification permission |
| `hasRegisteredPhoneAccount()` | `Future<bool>` | Check Android PhoneAccount registration |
| `registerPhoneAccount()` | `Future<bool?>` | Register the Android PhoneAccount |
| `isPhoneAccountEnabled()` | `Future<bool>` | Check whether the PhoneAccount is enabled |
| `openPhoneAccountSettings()` | `Future<bool?>` | Open system PhoneAccount settings |
| `rejectCallOnNoPermissions({shouldReject})` | `Future<bool>` | Auto-reject incoming calls when required permissions are missing |
| `isRejectingCallOnNoPermissions()` | `Future<bool>` | Check the auto-reject setting |
| `processVonagePush(data)` | `Future<String?>` | Forward matching raw push data to the native layer |
| `isBatteryOptimized()` | `Future<bool>` | Check Android battery-optimization state |
| `requestBatteryOptimizationExemption()` | `Future<bool?>` | Ask for battery-optimization exemption |
| `canUseFullScreenIntent()` | `Future<bool>` | Check Android 14+ full-screen-intent eligibility |
| `openFullScreenIntentSettings()` | `Future<bool?>` | Open full-screen-intent settings |
| `canDrawOverlays()` | `Future<bool>` | Check overlay permission |
| `openOverlaySettings()` | `Future<bool?>` | Open overlay permission settings |
| `registerClient(clientId, clientName)` | `Future<bool?>` | Register caller name mapping |
| `unregisterClient(clientId)` | `Future<bool?>` | Remove caller mapping |
| `setDefaultCallerName(callerName)` | `Future<bool?>` | Set default caller name |
| `updateCallKitIcon({icon})` | `Future<bool?>` | Set iOS CallKit icon |

</details>

<details>
<summary><b>Call Control APIs</b></summary>

### `VonageVoice.instance.call`

| Method / Property | Returns | Description |
|-------------------|---------|-------------|
| `activeCall` | `ActiveCall?` | Current active or most recent call state |
| `place({from, to, extraOptions?})` | `Future<bool?>` | Place an outgoing call |
| `answer()` | `Future<bool?>` | Answer an incoming call |
| `hangUp()` | `Future<bool?>` | End or decline the current call |
| `isOnCall()` | `Future<bool>` | Check whether a call is active |
| `getActiveCallOnResumeFromTerminatedState()` | `Future<bool>` | Ask Android to re-emit active-call state after a terminated-state resume |
| `getSid()` | `Future<String?>` | Get the Vonage call ID |
| `toggleMute(isMuted)` | `Future<bool?>` | Mute or unmute the microphone |
| `isMuted()` | `Future<bool?>` | Check mute state |
| `toggleSpeaker(speakerIsOn)` | `Future<bool?>` | Route audio to or from speaker |
| `isOnSpeaker()` | `Future<bool?>` | Check speaker route state |
| `holdCall({holdCall})` | `Future<bool?>` | Hold or resume the call |
| `isHolding()` | `Future<bool?>` | Check hold state |
| `toggleBluetooth({bluetoothOn})` | `Future<bool?>` | Route audio to or from Bluetooth |
| `isBluetoothOn()` | `Future<bool?>` | Check whether Bluetooth is the active route |
| `isBluetoothAvailable()` | `Future<bool?>` | Check whether a Bluetooth audio device is available |
| `isBluetoothEnabled()` | `Future<bool?>` | Check whether Bluetooth is enabled |
| `showBluetoothEnablePrompt()` | `Future<bool?>` | Prompt the user to enable Bluetooth on Android |
| `openBluetoothSettings()` | `Future<bool?>` | Open Bluetooth settings |
| `getAudioDevices()` | `Future<List<AudioDevice>>` | List all available audio devices |
| `selectAudioDevice(deviceId)` | `Future<bool?>` | Select a specific audio device |
| `sendDigits(digits)` | `Future<bool?>` | Send DTMF tones |

</details>

---

## Troubleshooting

### Incoming Calls Do Not Arrive

- Verify that push credentials were uploaded to the correct Vonage application.
- Verify that the same Vonage application is the one your backend uses to mint JWTs.
- On Android, verify `google-services.json`, Firebase setup, and the Google Services plugin in the host app.
- On iOS, verify Push Notifications capability, Background Modes, `aps-environment`, and VoIP certificate upload.
- Verify that the device completed `setTokens(...)` successfully.

### iOS Incoming Calls Fail Silently

- Check `isSandbox`. The value must match the APNs environment used by the VoIP certificate and the build.
- If your app already owns `PKPushRegistry`, make sure ownership was intentionally handed off with `VonageVoicePlugin.pushKitSetupByAppDelegate = true` before plugin registration.
- Do not let two independent PushKit owners exist for `.voIP`.

### Android Incoming Calls Are Unreliable When the App Is Backgrounded or Killed

- Ask the user to exempt the app from battery optimization.
- Verify that the PhoneAccount was registered and enabled.
- On Android 13+, verify notification permission.
- On Android 14+, verify full-screen-intent permission.
- On Samsung and MIUI-style OEMs, verify overlay permission if lock-screen incoming-call UI is not surfacing reliably.

### Android Pushes Are Being Processed Twice

- Do not wire your normal Android incoming-call flow around `processVonagePush()` from Dart.
- Let the plugin's native FCM service own the Android push path.

### No Audio During Calls

- Verify microphone permission.
- Verify your app is not auto-rejecting calls because permissions are missing.
- If you built custom in-app audio controls, make sure you are reading the current route state from the plugin rather than assuming defaults.

### Foreground UI Feels Inconsistent

- Treat native call UI as the system integration layer.
- Treat Flutter event handling as the app UI layer.
- Always listen to `callEventsListener` and route your own incoming/active-call screens from that source of truth.

### JWT or Session Problems

- Refresh JWTs before expiry with `refreshSession(...)`.
- If the session has already expired, re-register with `setTokens(...)`.
- If the push token changes, update your backend-side device mapping if your backend stores it.

---

## Example App

The repository includes a working example app in [`example/`](example/) that demonstrates:

- Login and JWT registration.
- Android permission onboarding.
- Android battery optimization, full-screen intent, and overlay checks.
- iOS FCM forwarding pattern when Firebase messaging is present.
- Flutter incoming-call and active-call screens driven by the plugin event stream.

Use the example as an integration reference, but keep your production JWTs and push credentials in your own app/backend flow.

---

## License

See [LICENSE](LICENSE).