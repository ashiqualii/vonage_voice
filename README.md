# Vonage Voice — Flutter Plugin

<!-- Uncomment these badges once published to pub.dev -->
<!-- [![pub package](https://img.shields.io/pub/v/vonage_voice.svg)](https://pub.dev/packages/vonage_voice) -->
[![Platform](https://img.shields.io/badge/platform-android%20%7C%20ios-blue)](https://github.com/ashiqualii/vonage_voice)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

Make and receive voice calls in your Flutter app using the **Vonage Client SDK**. The plugin handles everything for you — native call screens (CallKit on iOS, ConnectionService on Android), background call delivery, and full in-call controls.

| Platform | Minimum Version |
|----------|----------------|
| Android  | API 24 (Android 7.0) |
| iOS      | 13.0 |

### Features

- Make outgoing voice calls
- Receive incoming calls — even when the app is in the background or killed
- Native incoming call screen (CallKit on iOS, system notification on Android)
- In-call controls — mute, hold, speaker, Bluetooth, DTMF tones
- Map caller IDs to display names on the call screen
- Audio routing — switch between earpiece, speaker, and Bluetooth

---

## Quick Start

This gives you the shortest path from zero to a working call. Each step links to a detailed section below if you need more info.

### Step 1 — Install

```yaml
# pubspec.yaml
dependencies:
  vonage_voice:
  firebase_core:         # Android only — for incoming calls
  firebase_messaging:    # Android only — for incoming calls
```

```bash
flutter pub get
```

### Step 2 — Platform Setup

**Android:** Drop your `google-services.json` into `android/app/` and add the Google Services plugin. See [Android Setup](#android-setup) for details.

**iOS:** Set `platform :ios, '13.0'` in your Podfile, add microphone + background mode entries to `Info.plist`, and enable Push Notifications + Background Modes in Xcode. See [iOS Setup](#ios-setup) for details.

**Both platforms:** Upload your push credentials (FCM server key for Android, VoIP `.p12` certificate for iOS) to the [Vonage Dashboard](https://dashboard.nexmo.com/applications) → your app → Push Credentials. Without this, incoming calls won't work.

### Step 3 — Login & Make a Call

```dart
import 'package:vonage_voice/vonage_voice.dart';

// Login
await VonageVoice.instance.setTokens(
  accessToken: jwtFromYourBackend,
  deviceToken: fcmToken,   // Android only — null on iOS
  isSandbox: false,        // iOS only — true for debug, false for release
);

// Place a call
await VonageVoice.instance.call.place(
  from: 'alice',
  to: '+14155551234',
);

// Listen for events
VonageVoice.instance.callEventsListener.listen((event) {
  print('Call event: $event');
});
```

That's it! For a complete working app with login, dialer, and call screens, check out the [`example/`](example/) folder.

---

## Table of Contents

**Getting Started**
- [Before You Start](#before-you-start)
- [Installation](#installation)
- [Android Setup](#android-setup)
- [iOS Setup](#ios-setup)
- [Upload Push Credentials](#upload-push-credentials)

**Usage**
- [Import & Access the Plugin](#import--access-the-plugin)
- [Login](#login)
- [Permissions](#permissions)
- [Making Outgoing Calls](#making-outgoing-calls)
- [Receiving Incoming Calls](#receiving-incoming-calls)
- [In-Call Controls](#in-call-controls)
- [Caller Registry](#caller-registry)
- [Token Refresh & Logout](#token-refresh--logout)

**Reference**
- [All Call Events](#all-call-events)
- [ActiveCall Model](#activecall-model)
- [Platform-Specific Extras](#platform-specific-extras)
- [Full API Reference](#full-api-reference)
- [Troubleshooting](#troubleshooting)

---

## Before You Start

Make sure you have these ready:

| What | Why | Where to Get It |
|------|-----|-----------------|
| **Vonage Application** (with Voice enabled) | The backend that routes your calls | [Vonage Dashboard](https://dashboard.nexmo.com/applications) |
| **JWT for each user** | Authenticates your user with Vonage | Your backend server generates this |
| **Firebase project** (Android only) | Delivers incoming call notifications via FCM | [Firebase Flutter setup guide](https://firebase.google.com/docs/flutter/setup) |
| **VoIP push certificate** `.p12` (iOS only) | Lets Vonage send call pushes to iOS devices | [Apple Developer Portal](https://developer.apple.com/account/resources/certificates) → VoIP Services Certificate |

---

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  vonage_voice:
  firebase_core:
  firebase_messaging:
```

```bash
flutter pub get
```

> **Note:** `firebase_core` and `firebase_messaging` are only required for Android incoming calls. iOS handles push delivery automatically through PushKit.

---

## Android Setup

### Add Firebase

1. Place `google-services.json` inside `android/app/`.

2. Add the Google Services plugin to `android/app/build.gradle.kts`:

```kotlin
plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services") // Add this
}
```

3. Make sure it's available in `settings.gradle.kts`:

```kotlin
plugins {
    id("com.google.gms.google-services") version "4.4.0" apply false
}
```

### Permissions & ProGuard

You don't need to add anything. The plugin declares all required permissions (microphone, phone state, foreground service, notifications, etc.) and ProGuard rules — they merge into your app automatically at build time.

---

## iOS Setup

### Set Minimum Version

In `ios/Podfile`:

```ruby
platform :ios, '13.0'
```

```bash
cd ios && pod install
```

### Update Info.plist

Add to `ios/Runner/Info.plist`:

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

### Enable Xcode Capabilities

Open `ios/Runner.xcworkspace` in Xcode → **Signing & Capabilities** → add:

| Capability | What to Check |
|-----------|---------------|
| **Push Notifications** | Just enable it |
| **Background Modes** | Check: Audio, AirPlay and Picture in Picture · Voice over IP · Background fetch · Remote notifications |

---

## Upload Push Credentials

Go to [Vonage Dashboard](https://dashboard.nexmo.com/applications) → your app → **Push Credentials**:

- **Android:** Upload your Firebase Server Key (or FCM v1 service account JSON)
- **iOS:** Upload your VoIP push certificate (`.p12` file)

> **This step is required.** Without it, incoming calls will not work on either platform.

---

## Import & Access the Plugin

```dart
import 'package:vonage_voice/vonage_voice.dart';
```

Everything is accessed through a singleton:

```dart
VonageVoice.instance          // Login, permissions, push handling, caller registry
VonageVoice.instance.call     // Call controls — place, answer, mute, speaker, etc.
```

| Class | Purpose |
|-------|---------|
| `VonageVoice` | Main plugin — login, permissions, push handling, caller registry |
| `VonageCall` | Call controls — place, answer, hang up, mute, speaker, hold, bluetooth, DTMF |
| `CallEvent` | All possible call events (incoming, connected, callEnded, mute, etc.) |
| `ActiveCall` | Details of the current call (from, to, direction, custom params) |
| `CallDirection` | `.incoming` or `.outgoing` |

---

## Login

You need two things:
1. **A JWT string** from your backend API
2. **An FCM token** (Android only) for incoming call notifications

```dart
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:vonage_voice/vonage_voice.dart';

Future<void> login() async {
  await Firebase.initializeApp();

  final String jwt = await yourBackendApi.getVonageJwt();

  String? fcmToken;
  if (Platform.isAndroid) {
    fcmToken = await FirebaseMessaging.instance.getToken();
  }

  final success = await VonageVoice.instance.setTokens(
    accessToken: jwt,
    deviceToken: fcmToken,   // null on iOS — plugin handles VoIP tokens via PushKit
    isSandbox: false,        // iOS only: true for debug, false for release
  );

  if (success == true) {
    print('Logged in!');
  }
}
```

| Parameter | Required | Description |
|-----------|----------|-------------|
| `accessToken` | Yes | Vonage JWT from your backend |
| `deviceToken` | Android only | FCM token. On iOS, pass `null` — the plugin handles VoIP tokens automatically |
| `isSandbox` | iOS only | `true` for debug builds, `false` for release. If set wrong, incoming calls won't work on iOS |

---

## Permissions

### The Easy Way — Request Everything at Once

Use this helper to request all permissions your app needs. Call it once during your app's setup flow (e.g. after login):

```dart
import 'dart:io';

Future<void> requestAllPermissions() async {
  // Microphone — required on both platforms
  if (!await VonageVoice.instance.hasMicAccess()) {
    await VonageVoice.instance.requestMicAccess();
  }

  if (!Platform.isAndroid) return;

  // Android-specific permissions
  if (!await VonageVoice.instance.hasReadPhoneStatePermission()) {
    await VonageVoice.instance.requestReadPhoneStatePermission();
  }
  if (!await VonageVoice.instance.hasCallPhonePermission()) {
    await VonageVoice.instance.requestCallPhonePermission();
  }
  if (!await VonageVoice.instance.hasManageOwnCallsPermission()) {
    await VonageVoice.instance.requestManageOwnCallsPermission();
  }
  if (!await VonageVoice.instance.hasReadPhoneNumbersPermission()) {
    await VonageVoice.instance.requestReadPhoneNumbersPermission();
  }
  if (!await VonageVoice.instance.hasNotificationPermission()) {
    await VonageVoice.instance.requestNotificationPermission();
  }

  // Phone account registration
  if (!await VonageVoice.instance.hasRegisteredPhoneAccount()) {
    await VonageVoice.instance.registerPhoneAccount();
  }
  if (!await VonageVoice.instance.isPhoneAccountEnabled()) {
    await VonageVoice.instance.openPhoneAccountSettings();
  }

  // Full-screen incoming call UI (Android 14+)
  if (!await VonageVoice.instance.canUseFullScreenIntent()) {
    await VonageVoice.instance.openFullScreenIntentSettings();
  }

  // Battery optimization exemption — critical for Chinese OEMs (Vivo, Xiaomi, OPPO)
  if (await VonageVoice.instance.isBatteryOptimized()) {
    await VonageVoice.instance.requestBatteryOptimizationExemption();
  }
}
```

> **Why so many permissions on Android?** Android's telecom framework requires several permissions to show call notifications, manage the phone account, and access the microphone. iOS only needs microphone permission — everything else is handled by CallKit and PushKit automatically.

### Auto-Reject on Missing Permissions (Optional)

You can tell the plugin to automatically reject incoming calls if the user hasn't granted required permissions (like microphone). This prevents calls with no audio:

```dart
await VonageVoice.instance.rejectCallOnNoPermissions(shouldReject: true);
```

---

## Making Outgoing Calls

### Place a Call

```dart
final success = await VonageVoice.instance.call.place(
  from: 'alice',
  to: '+14155551234',
  extraOptions: {
    'displayName': 'Alice',
  },
);
```

| Parameter | Required | Description |
|-----------|----------|-------------|
| `from` | Yes | Your Vonage user identity (the caller) |
| `to` | Yes | A phone number (`+14155551234`) or another Vonage user identity |
| `extraOptions` | No | Key-value pairs forwarded to your Vonage backend (display names, recording flags, etc.) |

### Listen for Call Progress

```dart
VonageVoice.instance.callEventsListener.listen((event) {
  switch (event) {
    case CallEvent.ringing:
      print('Ringing...');
      break;
    case CallEvent.connected:
      print('Connected!');
      break;
    case CallEvent.callEnded:
      print('Call ended');
      break;
    default:
      break;
  }
});
```

**Outgoing call flow:** `place()` → `ringing` → `connected` → `callEnded`

### Get Active Call Details

```dart
final call = VonageVoice.instance.call.activeCall;

if (call != null) {
  print(call.from);           // "alice"
  print(call.to);             // "+14155551234"
  print(call.fromFormatted);  // Formatted nicely
  print(call.toFormatted);    // "(415) 555-1234"
  print(call.callDirection);  // CallDirection.outgoing
  print(call.initiated);      // DateTime when connected (null until connected)
  print(call.customParams);   // Custom data from your backend
}
```

---

## Receiving Incoming Calls

Incoming calls work differently on each platform:

- **Android:** Vonage sends an FCM push → the plugin's native `VonageFirebaseMessagingService` picks it up automatically → shows system call notification / full-screen incoming call screen
- **iOS:** Vonage sends a VoIP push via PushKit → plugin handles it → CallKit shows the native call screen

### Forward Firebase Pushes (iOS via Flutter — Required)

On **iOS**, Flutter's `firebase_messaging` intercepts FCM messages before the native Vonage SDK sees them. You need to forward them to the plugin:

```dart
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:vonage_voice/vonage_voice.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Only forward on iOS — Android handles push natively
  if (Platform.isIOS && message.data.isNotEmpty) {
    await VonageVoice.instance.processVonagePush(message.data);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  runApp(MyApp());
}
```

And the foreground handler (in your main screen's `initState`):

```dart
@override
void initState() {
  super.initState();
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    // Only forward on iOS — Android handles push natively
    if (Platform.isIOS && message.data.isNotEmpty) {
      VonageVoice.instance.processVonagePush(message.data);
    }
  });
}
```

> **Android:** You do **not** need to forward FCM pushes on Android. The plugin's native `VonageFirebaseMessagingService` handles incoming call pushes automatically — even when the app is killed or backgrounded. Calling `processVonagePush()` on Android is unnecessary and the plugin will safely deduplicate if you do.
>
> **iOS:** You need both the background handler (`onBackgroundMessage`) and the foreground handler (`onMessage`). The plugin handles VoIP pushes through PushKit, but FCM data messages still need forwarding.

### Listen for Incoming Calls

```dart
VonageVoice.instance.callEventsListener.listen((event) {
  if (event == CallEvent.incoming) {
    final call = VonageVoice.instance.call.activeCall;
    print('Incoming call from: ${call?.fromFormatted}');
    // The native call screen is already showing at this point
  }
});
```

### Answer or Decline

```dart
await VonageVoice.instance.call.answer();   // Answer
await VonageVoice.instance.call.hangUp();   // Decline
```

> The user can also answer/decline from the native call screen (CallKit / system notification) without any Flutter code.

### Incoming Call Event Flow

| Scenario | Events |
|----------|--------|
| User answers | `incoming` → `answer` → `connected` → `callEnded` |
| User declines | `incoming` → `callEnded` |
| Caller gives up | `incoming` → `missedCall` |

---

## In-Call Controls

All controls are on `VonageVoice.instance.call`. Each action fires a corresponding `CallEvent`.

### Mute / Unmute

```dart
await VonageVoice.instance.call.toggleMute(true);   // Mute
await VonageVoice.instance.call.toggleMute(false);  // Unmute
final isMuted = await VonageVoice.instance.call.isMuted();
```
Events: `CallEvent.mute` / `CallEvent.unmute`

### Speaker

```dart
await VonageVoice.instance.call.toggleSpeaker(true);   // Speaker on
await VonageVoice.instance.call.toggleSpeaker(false);  // Speaker off
final isOnSpeaker = await VonageVoice.instance.call.isOnSpeaker();
```
Events: `CallEvent.speakerOn` / `CallEvent.speakerOff`

### Hold / Resume

```dart
await VonageVoice.instance.call.holdCall(holdCall: true);   // Hold
await VonageVoice.instance.call.holdCall(holdCall: false);  // Resume
final isHolding = await VonageVoice.instance.call.isHolding();
```
Events: `CallEvent.hold` / `CallEvent.unhold`

### Bluetooth Audio

```dart
await VonageVoice.instance.call.toggleBluetooth(bluetoothOn: true);   // Route to Bluetooth
await VonageVoice.instance.call.toggleBluetooth(bluetoothOn: false);  // Route away
final isBtOn = await VonageVoice.instance.call.isBluetoothOn();
```
Events: `CallEvent.bluetoothOn` / `CallEvent.bluetoothOff`

**Bluetooth helpers:**

```dart
// Is a Bluetooth audio device connected?
final isAvailable = await VonageVoice.instance.call.isBluetoothAvailable();

// Is the Bluetooth adapter turned on?
final isEnabled = await VonageVoice.instance.call.isBluetoothEnabled();

// Prompt user to turn on Bluetooth (Android only)
final userSaidYes = await VonageVoice.instance.call.showBluetoothEnablePrompt();

// Open Bluetooth settings
await VonageVoice.instance.call.openBluetoothSettings();
```

<details>
<summary><b>Full Bluetooth flow (recommended for production)</b></summary>

```dart
Future<void> handleBluetoothToggle(bool enable) async {
  if (!enable) {
    await VonageVoice.instance.call.toggleBluetooth(bluetoothOn: false);
    return;
  }

  // Step 1: Is Bluetooth turned on?
  final btEnabled = await VonageVoice.instance.call.isBluetoothEnabled() ?? false;
  if (!btEnabled) {
    final userEnabled = await VonageVoice.instance.call.showBluetoothEnablePrompt() ?? false;
    if (!userEnabled) return;
    await Future.delayed(const Duration(seconds: 2));
  }

  // Step 2: Is a Bluetooth audio device connected?
  final btAvailable = await VonageVoice.instance.call.isBluetoothAvailable() ?? false;
  if (btAvailable) {
    await VonageVoice.instance.call.toggleBluetooth(bluetoothOn: true);
  } else {
    await VonageVoice.instance.call.openBluetoothSettings();
  }
}
```

</details>

### DTMF Tones (Dial Pad)

Send tones during an active call (e.g. "Press 1 for sales..."):

```dart
await VonageVoice.instance.call.sendDigits('1');
await VonageVoice.instance.call.sendDigits('1234');
await VonageVoice.instance.call.sendDigits('*#');
```

### Hang Up

```dart
await VonageVoice.instance.call.hangUp();
```

### Check Call Status

```dart
final onCall = await VonageVoice.instance.call.isOnCall();
final callId = await VonageVoice.instance.call.getSid();
final activeCall = VonageVoice.instance.call.activeCall;
```

### Sync UI with Audio State

When a call connects, check the current audio state so your UI buttons are accurate:

```dart
VonageVoice.instance.callEventsListener.listen((event) {
  if (event == CallEvent.connected || event == CallEvent.reconnected) {
    _syncAudioState();
  }
});

Future<void> _syncAudioState() async {
  final isMuted = await VonageVoice.instance.call.isMuted() ?? false;
  final isOnSpeaker = await VonageVoice.instance.call.isOnSpeaker() ?? false;
  final isBtOn = await VonageVoice.instance.call.isBluetoothOn() ?? false;
  final isBtAvailable = await VonageVoice.instance.call.isBluetoothAvailable() ?? false;

  setState(() {
    _muted = isMuted;
    _speakerOn = isOnSpeaker;
    _bluetoothOn = isBtOn;
    _bluetoothAvailable = isBtAvailable;
  });
}
```

---

## Caller Registry

Map caller IDs to human-readable names. These show up on the native call screen:

```dart
// Register names
await VonageVoice.instance.registerClient('user_123', 'John Doe');
await VonageVoice.instance.registerClient('+14155551234', 'Bob Jones');

// Remove a name
await VonageVoice.instance.unregisterClient('user_123');

// Set fallback for unknown callers
await VonageVoice.instance.setDefaultCallerName('Unknown Caller');
```

When a call comes in, the plugin checks: registered name → default name → "Unknown Caller".

---

## Token Refresh & Logout

### Refresh JWT

Vonage JWTs expire (usually after 24 hours). Refresh before expiry:

```dart
final freshJwt = await yourBackendApi.getNewVonageJwt();
await VonageVoice.instance.refreshSession(accessToken: freshJwt);
```

> If the JWT has already expired, `refreshSession` won't work — call `setTokens()` again.

### Handle FCM Token Changes

```dart
VonageVoice.instance.setOnDeviceTokenChanged((newToken) {
  print('FCM token changed: $newToken');
  // Re-register with setTokens() using the new token
});
```

### Logout

```dart
await VonageVoice.instance.unregister();
```

This unregisters the push token and ends the session. No more incoming calls until `setTokens()` is called again.

---

## All Call Events

```dart
VonageVoice.instance.callEventsListener.listen((CallEvent event) {
  // Handle the event
});
```

| Event | When It Fires |
|-------|--------------|
| `incoming` | An incoming call invite arrived |
| `ringing` | Outgoing call is ringing on the other phone |
| `connected` | Call connected — both sides can talk |
| `reconnecting` | Lost network — trying to reconnect |
| `reconnected` | Reconnected after a network interruption |
| `callEnded` | Call is over (either side hung up, or error) |
| `answer` | Incoming call was answered |
| `declined` | The other side declined |
| `missedCall` | Incoming call was not answered |
| `hold` | Call placed on hold |
| `unhold` | Call resumed from hold |
| `mute` | Microphone muted |
| `unmute` | Microphone unmuted |
| `speakerOn` | Audio switched to speaker |
| `speakerOff` | Audio switched from speaker |
| `bluetoothOn` | Audio routed to Bluetooth |
| `bluetoothOff` | Audio routed from Bluetooth |
| `returningCall` | A return call was placed |
| `audioRouteChanged` | Audio route changed (iOS only) |
| `log` | Diagnostic log event (debugging) |
| `permission` | Permission result received |

---

## ActiveCall Model

Access via `VonageVoice.instance.call.activeCall` (returns `null` if no active call):

| Property | Type | Description |
|----------|------|-------------|
| `from` | `String` | Caller's ID or phone number |
| `fromFormatted` | `String` | Nicely formatted (e.g. "(415) 555-1234") |
| `to` | `String` | Destination ID or phone number |
| `toFormatted` | `String` | Nicely formatted |
| `initiated` | `DateTime?` | When connected — `null` until `connected` event |
| `callDirection` | `CallDirection` | `.incoming` or `.outgoing` |
| `customParams` | `Map<String, dynamic>?` | Custom data from your Vonage backend |

---

## Platform-Specific Extras

### Missed Call Notifications

```dart
VonageVoice.instance.showMissedCallNotifications = true;   // or false
```

### CallKit Icon (iOS Only)

```dart
await VonageVoice.instance.updateCallKitIcon(icon: 'MyCallIcon');
```

The icon must be a **40x40pt template image** (white on transparent) added to your iOS asset catalog in Xcode.

### APNs Sandbox vs Production (iOS Only)

| Build Type | `isSandbox` | Push Environment |
|-----------|-------------|-----------------|
| Debug | `true` | Apple sandbox |
| Release | `false` (default) | Apple production |

If set wrong, incoming calls won't work on iOS.

---

## Troubleshooting

### Incoming calls not working

1. **Push credentials not uploaded.** Go to [Vonage Dashboard](https://dashboard.nexmo.com/applications) → your app → Push Credentials. Upload FCM server key (Android) or VoIP `.p12` certificate (iOS).
2. **Wrong `isSandbox` value (iOS).** Use `true` for debug builds, `false` for release. Mismatched value = no pushes delivered.
3. **Firebase push not forwarded (iOS).** Make sure both the background handler (`FirebaseMessaging.onBackgroundMessage`) and foreground handler (`FirebaseMessaging.onMessage`) forward pushes to `processVonagePush()` with a `Platform.isIOS` guard. See [Receiving Incoming Calls](#receiving-incoming-calls). On Android, push handling is automatic — do **not** forward FCM pushes via Dart on Android.
4. **Battery optimization killing the app (Android).** Manufacturers like Vivo, Xiaomi, OPPO, and Samsung aggressively kill background apps. Call `requestBatteryOptimizationExemption()` and tell users to disable battery optimization for your app in system settings.
5. **Phone account not enabled (Android).** The plugin uses Android's Telecom framework with `CAPABILITY_SELF_MANAGED`. Call `registerPhoneAccount()` and verify with `isPhoneAccountEnabled()`. Some OEMs require the user to manually enable the phone account in Settings → Apps → Default Apps → Phone.
6. **Notification permission not granted (Android 13+).** Call `requestNotificationPermission()` — without it, incoming call notifications (including full-screen intent) cannot be posted.

### No audio during calls

- **Microphone permission not granted.** Call `requestMicAccess()` before placing or answering calls.
- **Auto-reject is on.** If you enabled `rejectCallOnNoPermissions(shouldReject: true)`, calls will be auto-rejected when permissions are missing.

### App killed on Chinese OEM devices

- **Vivo, Xiaomi, OPPO** have aggressive battery management beyond stock Android. Besides calling `requestBatteryOptimizationExemption()`, users may also need to manually whitelist your app in the manufacturer's battery/power manager settings (e.g. iManager on Vivo).

### Lock screen incoming call not showing (Xiaomi/Redmi/POCO)

- **MIUI overlay permission required.** On MIUI devices, the incoming call screen may not appear over the lock screen without `SYSTEM_ALERT_WINDOW` (overlay) permission. The plugin automatically applies `TYPE_APPLICATION_OVERLAY` on locked MIUI devices when the permission is granted. Guide users to Settings → Apps → your app → Permissions → Display pop-up windows to enable it.

### Lock screen incoming call shows as small notification instead of full-screen

- **Android 14+ (API 34):** Grant `USE_FULL_SCREEN_INTENT` — call `canUseFullScreenIntent()` to check, `openFullScreenIntentSettings()` to prompt.
- **Phone account not registered:** Call `registerPhoneAccount()` — the Telecom framework provides a BAL (Background Activity Launch) exemption that is the most reliable way to show activities on the lock screen.
- **Notifications disabled:** On Android 13+, call `requestNotificationPermission()` — `fullScreenIntent` requires an active notification.

---

## Full API Reference

<details>
<summary><b>Click to expand full API tables</b></summary>

### Session & Device — `VonageVoice.instance`

| Method | Returns | Platform | Description |
|--------|---------|----------|-------------|
| `setTokens({accessToken, deviceToken?, isSandbox?})` | `Future<bool?>` | Both | Log in — register JWT and optional FCM token |
| `unregister({accessToken?})` | `Future<bool?>` | Both | Log out — end session and unregister push |
| `refreshSession({accessToken})` | `Future<bool?>` | Both | Refresh JWT without dropping the session |
| `callEventsListener` | `Stream<CallEvent>` | Both | Stream of all call events |
| `setOnDeviceTokenChanged(callback)` | `void` | Both | Listen for FCM/VoIP token changes |
| `showMissedCallNotifications` (setter) | `void` | Both | Enable or disable missed call notifications |
| `processVonagePush(data)` | `Future<String?>` | iOS | Forward FCM push data to Vonage SDK (Android handles this natively — not needed) |
| `registerClient(id, name)` | `Future<bool?>` | Both | Map a caller ID to a display name |
| `unregisterClient(id)` | `Future<bool?>` | Both | Remove a caller ID mapping |
| `setDefaultCallerName(name)` | `Future<bool?>` | Both | Set fallback name for unknown callers |
| `updateCallKitIcon({icon})` | `Future<bool?>` | iOS | Set the icon on CallKit call screen |

### Permissions — `VonageVoice.instance`

| Method | Returns | Platform | Description |
|--------|---------|----------|-------------|
| `hasMicAccess()` | `Future<bool>` | Both | Is microphone permission granted? |
| `requestMicAccess()` | `Future<bool?>` | Both | Request microphone permission |
| `hasReadPhoneStatePermission()` | `Future<bool>` | Android | Is READ_PHONE_STATE granted? |
| `requestReadPhoneStatePermission()` | `Future<bool?>` | Android | Request READ_PHONE_STATE |
| `hasCallPhonePermission()` | `Future<bool>` | Android | Is CALL_PHONE granted? |
| `requestCallPhonePermission()` | `Future<bool?>` | Android | Request CALL_PHONE |
| `hasManageOwnCallsPermission()` | `Future<bool>` | Android | Is MANAGE_OWN_CALLS granted? |
| `requestManageOwnCallsPermission()` | `Future<bool?>` | Android | Request MANAGE_OWN_CALLS |
| `hasReadPhoneNumbersPermission()` | `Future<bool>` | Android | Is READ_PHONE_NUMBERS granted? |
| `requestReadPhoneNumbersPermission()` | `Future<bool?>` | Android | Request READ_PHONE_NUMBERS |
| `hasNotificationPermission()` | `Future<bool>` | Android | Is POST_NOTIFICATIONS granted? (API 33+) |
| `requestNotificationPermission()` | `Future<bool?>` | Android | Request POST_NOTIFICATIONS |
| `hasRegisteredPhoneAccount()` | `Future<bool>` | Android | Is the phone account registered? |
| `registerPhoneAccount()` | `Future<bool?>` | Android | Register app as a phone account |
| `isPhoneAccountEnabled()` | `Future<bool>` | Android | Is the phone account enabled? |
| `openPhoneAccountSettings()` | `Future<bool?>` | Android | Open system phone account settings |
| `canUseFullScreenIntent()` | `Future<bool>` | Android | Can show full-screen call UI? (API 34+) |
| `openFullScreenIntentSettings()` | `Future<bool?>` | Android | Open full-screen intent settings |
| `isBatteryOptimized()` | `Future<bool>` | Android | Is battery optimization active? |
| `requestBatteryOptimizationExemption()` | `Future<bool?>` | Android | Request battery optimization exemption |
| `rejectCallOnNoPermissions({shouldReject})` | `Future<bool>` | Android | Auto-reject if permissions missing |
| `isRejectingCallOnNoPermissions()` | `Future<bool>` | Android | Is auto-reject enabled? |

### Call Controls — `VonageVoice.instance.call`

| Method | Returns | Platform | Description |
|--------|---------|----------|-------------|
| `place({from, to, extraOptions?})` | `Future<bool?>` | Both | Place an outgoing call |
| `answer()` | `Future<bool?>` | Both | Answer an incoming call |
| `hangUp()` | `Future<bool?>` | Both | Hang up the current call |
| `isOnCall()` | `Future<bool>` | Both | Is there an active call? |
| `getSid()` | `Future<String?>` | Both | Get the Vonage call ID |
| `activeCall` (getter) | `ActiveCall?` | Both | Get current call details |
| `toggleMute(isMuted)` | `Future<bool?>` | Both | Mute or unmute mic |
| `isMuted()` | `Future<bool?>` | Both | Is mic muted? |
| `toggleSpeaker(speakerIsOn)` | `Future<bool?>` | Both | Turn speaker on/off |
| `isOnSpeaker()` | `Future<bool?>` | Both | Is speaker on? |
| `holdCall({holdCall})` | `Future<bool?>` | Both | Hold or resume call |
| `isHolding()` | `Future<bool?>` | Both | Is call on hold? |
| `toggleBluetooth({bluetoothOn})` | `Future<bool?>` | Both | Route audio to/from Bluetooth |
| `isBluetoothOn()` | `Future<bool?>` | Both | Is audio on Bluetooth? |
| `isBluetoothAvailable()` | `Future<bool?>` | Both | Is Bluetooth audio device connected? |
| `isBluetoothEnabled()` | `Future<bool?>` | Both | Is Bluetooth adapter on? |
| `showBluetoothEnablePrompt()` | `Future<bool?>` | Android | Show "Turn on Bluetooth?" dialog |
| `openBluetoothSettings()` | `Future<bool?>` | Both | Open system Bluetooth settings |
| `sendDigits(digits)` | `Future<bool?>` | Both | Send DTMF tones |

</details>

---

## Example App

A full working example with login, dialer, incoming call handling, and active call screen is in the [`example/`](example/) folder.

---

## Contributing

Contributions are welcome! If you find a bug or want to add a feature:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes
4. Open a pull request

For bugs, please [open an issue](https://github.com/ashiqualii/vonage_voice/issues) with steps to reproduce.

---

## License

See [LICENSE](LICENSE) for details.
