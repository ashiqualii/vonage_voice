# Vonage Voice — Flutter Plugin

A Flutter plugin for making and receiving voice calls using the **Vonage Client SDK**, with full native integration for both Android and iOS.

| Platform | Minimum Version |
|----------|----------------|
| Android  | API 24 (Android 7.0) |
| iOS      | 13.0 |

### Features

- Incoming and outgoing voice calls
- Native call UI — **CallKit** on iOS, **Telecom ConnectionService** on Android
- Push delivery — **PushKit VoIP** on iOS, **Firebase Cloud Messaging (FCM)** on Android
- Audio routing — earpiece, speaker, Bluetooth
- Call controls — mute, hold, DTMF tones
- Caller registry — map caller IDs to display names
- Background & killed state support on both platforms
- Drop-in replacement for TwilioVoice Flutter plugin

---

## Table of Contents

1. [Backend Setup](#1-backend-setup)
2. [Android Setup](#2-android-setup)
3. [iOS Setup](#3-ios-setup)
4. [Importing](#4-importing)
5. [Authentication & Session](#5-authentication--session)
6. [Permissions](#6-permissions)
7. [Push Notification Handling](#7-push-notification-handling)
8. [Call Events](#8-call-events)
9. [Making Outgoing Calls](#9-making-outgoing-calls)
10. [Handling Incoming Calls](#10-handling-incoming-calls)
11. [Call Controls](#11-call-controls)
12. [Caller Registry](#12-caller-registry)
13. [ActiveCall Model](#13-activecall-model)
14. [Platform-Specific Features](#14-platform-specific-features)
15. [API Reference](#15-api-reference)

---

## 1. Backend Setup

Before using this plugin, your **backend server** must be able to generate a **Vonage JWT** (JSON Web Token) for each user.

### Step 1 — Create a Vonage Application

1. Go to the [Vonage API Dashboard](https://dashboard.nexmo.com/applications).
2. Create a new application with **Voice** capability enabled.
3. Note your **Application ID** (e.g. `c923113f-73c7-4022-acb8-7d47a7b9fb61`).
4. Download the **private key** file — your backend needs this to sign JWTs.

### Step 2 — Generate JWT on Your Backend

Your backend generates a JWT for each user who needs to make or receive calls. The JWT contains:

| Claim | Description |
|-------|-------------|
| `application_id` | Your Vonage Application ID |
| `sub` | The Vonage user identity (e.g. `"alice"`, `"agent_42"`) |
| `exp` | Token expiration timestamp |
| `acl` | Access control — grant permissions for voice |

Example JWT generation (Node.js backend):

```js
const Vonage = require('@vonage/server-sdk');

const vonage = new Vonage({
  applicationId: 'YOUR_APPLICATION_ID',
  privateKey: './private.key',
});

// Generate JWT for a specific user
const jwt = vonage.generateJwt({
  sub: 'alice',
  exp: Math.floor(Date.now() / 1000) + 86400, // 24 hours
  acl: {
    paths: {
      '/*/users/**': {},
      '/*/conversations/**': {},
      '/*/sessions/**': {},
      '/*/devices/**': {},
      '/*/image/**': {},
      '/*/media/**': {},
      '/*/applications/**': {},
      '/*/push/**': {},
      '/*/knocking/**': {},
      '/*/legs/**': {},
    },
  },
});
```

Your Flutter app fetches this JWT from your backend and passes it to `setTokens()`.

### Step 3 — Upload Push Credentials to Vonage Dashboard

- **Android**: Upload your **Firebase Server Key** (or FCM v1 service account JSON) to the Vonage Dashboard under your application's push credentials.
- **iOS**: Upload your **VoIP Services push certificate** (`.p12` or `.pem`) to the Vonage Dashboard.

---

## 2. Android Setup

### 2.1 — Firebase Cloud Messaging (FCM)

> **FCM is mandatory on Android.** It delivers incoming call push notifications when the app is in the background or killed. Without FCM, incoming calls will not work.

#### Step 1 — Create a Firebase Project

1. Go to the [Firebase Console](https://console.firebase.google.com/).
2. Create a new project (or use an existing one).
3. Add an Android app with your package name (e.g. `com.example.myapp`).
4. Download `google-services.json` and place it in your app's `android/app/` directory.

#### Step 2 — Add the Google Services Plugin

In your **app-level** `android/app/build.gradle.kts`:

```kotlin
plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services") // ← Add this
}
```

Make sure the Google Services classpath is available. In your **project-level** `android/build.gradle` or `settings.gradle.kts`, the plugin must be resolvable. If using the `plugins` block in `settings.gradle.kts`:

```kotlin
plugins {
    id("com.google.gms.google-services") version "4.4.0" apply false
}
```

#### Step 3 — Add Firebase Messaging Dependency

Add `firebase_messaging` and `firebase_core` to your Flutter project:

```yaml
dependencies:
  firebase_core: ^3.0.0
  firebase_messaging: ^15.0.0
```

### 2.2 — AndroidManifest Permissions

The plugin's own `AndroidManifest.xml` declares all required permissions, which are **automatically merged** into your app at build time. For reference, these are the permissions the plugin uses:

```xml
<!-- Voice call (microphone) -->
<uses-permission android:name="android.permission.RECORD_AUDIO" />

<!-- Telecom ConnectionService -->
<uses-permission android:name="android.permission.MANAGE_OWN_CALLS" />
<uses-permission android:name="android.permission.CALL_PHONE" />
<uses-permission android:name="android.permission.READ_PHONE_STATE" />
<uses-permission android:name="android.permission.READ_PHONE_NUMBERS" />

<!-- Foreground service for active calls -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MICROPHONE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_PHONE_CALL" />

<!-- Push delivery when device restarts -->
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />

<!-- Notifications (Android 13+) -->
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

<!-- Network -->
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:name="android.permission.CHANGE_WIFI_STATE" />

<!-- Keep connection alive during call -->
<uses-permission android:name="android.permission.WAKE_LOCK" />
```

You do **not** need to add these manually — they are merged automatically from the plugin.

### 2.3 — ProGuard / R8

The plugin ships its own `consumerProguardFiles` that are automatically included when you build with R8 minification enabled. No extra ProGuard rules needed.

```kotlin
// In your app's build.gradle.kts — this just works:
buildTypes {
    release {
        isMinifyEnabled = true
        isShrinkResources = true
        proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
        // Plugin's consumer rules are merged automatically
    }
}
```

---

## 3. iOS Setup

### 3.1 — Podfile

Ensure your iOS deployment target is at least **13.0**. In `ios/Podfile`:

```ruby
platform :ios, '13.0'
```

Then run:

```bash
cd ios && pod install
```

### 3.2 — Info.plist

Add the following keys to your `ios/Runner/Info.plist`:

```xml
<!-- Required: Microphone permission description -->
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access to make and receive voice calls.</string>

<!-- Required: Background modes for VoIP and push -->
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
    <string>voip</string>
    <string>fetch</string>
    <string>remote-notification</string>
</array>
```

### 3.3 — Xcode Capabilities

Open your project in Xcode and enable the following capabilities under **Signing & Capabilities**:

| Capability | Details |
|-----------|---------|
| **Push Notifications** | Required for VoIP push delivery |
| **Background Modes** | Check: Audio, AirPlay and Picture in Picture · Voice over IP · Background fetch · Remote notifications |

### 3.4 — VoIP Push Certificate

1. Go to the [Apple Developer Portal](https://developer.apple.com/account/resources/certificates).
2. Create a **VoIP Services Certificate** for your app's Bundle ID.
3. Export it as `.p12`.
4. Upload the `.p12` to the **Vonage Dashboard** under your application's iOS push credentials.

### 3.5 — APNs Environment (Sandbox vs Production)

When calling `setTokens()`, the `isSandbox` parameter controls which Apple Push Notification environment is used:

| Build Type | `isSandbox` Value | APNs Environment |
|-----------|-------------------|------------------|
| Debug / Development | `true` | Sandbox |
| Release / Production | `false` (default) | Production |

> **Important:** If `isSandbox` is set incorrectly, VoIP pushes will not be delivered and incoming calls won't ring. Use `true` for debug builds and `false` for release builds.

---

## 4. Importing

```dart
import 'package:vonage_voice/vonage_voice.dart';
```

This single import gives you access to:

- `VonageVoice` — the main plugin class
- `VonageCall` — active call controls
- `CallEvent` — enum of all call events
- `ActiveCall` — model representing the current call
- `CallDirection` — enum (`incoming` / `outgoing`)

### Singleton Pattern

The plugin uses a **singleton** pattern. All access goes through two entry points:

```dart
// Session management (login, permissions, push, etc.)
VonageVoice.instance

// Active call controls (place, hangUp, mute, hold, etc.)
VonageVoice.instance.call
```

If you're migrating from the TwilioVoice Flutter plugin:

```dart
// Before (Twilio)
TwilioVoice.instance.setTokens(accessToken: jwt);
TwilioVoice.instance.call.hangUp();

// After (Vonage) — same API shape
VonageVoice.instance.setTokens(accessToken: jwt);
VonageVoice.instance.call.hangUp();
```

---

## 5. Authentication & Session

### Register JWT and Device Token

Call `setTokens()` to authenticate with Vonage and register for incoming calls:

```dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:vonage_voice/vonage_voice.dart';

Future<void> login(String jwtFromBackend) async {
  // Get FCM token (Android only — required for incoming calls)
  String? fcmToken;
  if (Platform.isAndroid) {
    fcmToken = await FirebaseMessaging.instance.getToken();
  }

  // Register with Vonage
  final success = await VonageVoice.instance.setTokens(
    accessToken: jwtFromBackend,    // JWT from your backend
    deviceToken: fcmToken,          // FCM token (Android) or null (iOS)
    isSandbox: false,               // true for iOS debug builds
  );

  if (success == true) {
    print('Logged in successfully');
  }
}
```

> **iOS Note:** On iOS, the plugin automatically handles VoIP push token registration via PushKit. You do **not** need to pass a device token — just pass `null` or omit it.

### Logout / Unregister

```dart
await VonageVoice.instance.unregister();
```

### Refresh Session

If your JWT is about to expire, refresh it without destroying the session:

```dart
await VonageVoice.instance.refreshSession(
  accessToken: newJwtFromBackend,
);
```

### Handle Device Token Refresh

When the FCM token is refreshed (Android), re-register it with your backend:

```dart
VonageVoice.instance.setOnDeviceTokenChanged((newToken) {
  // Send newToken to your backend, then call setTokens() again
  print('Device token refreshed: $newToken');
});
```

---

## 6. Permissions

### 6.1 — Microphone (Both Platforms)

```dart
final hasMic = await VonageVoice.instance.hasMicAccess();
if (!hasMic) {
  await VonageVoice.instance.requestMicAccess();
}
```

### 6.2 — Android-Only Permissions

Request all required Android permissions before making or receiving calls:

```dart
import 'dart:io';

Future<void> requestAllPermissions() async {
  if (!Platform.isAndroid) return;

  // Phone state
  if (!await VonageVoice.instance.hasReadPhoneStatePermission()) {
    await VonageVoice.instance.requestReadPhoneStatePermission();
  }

  // Call phone
  if (!await VonageVoice.instance.hasCallPhonePermission()) {
    await VonageVoice.instance.requestCallPhonePermission();
  }

  // Manage own calls (Telecom)
  if (!await VonageVoice.instance.hasManageOwnCallsPermission()) {
    await VonageVoice.instance.requestManageOwnCallsPermission();
  }

  // Read phone numbers
  if (!await VonageVoice.instance.hasReadPhoneNumbersPermission()) {
    await VonageVoice.instance.requestReadPhoneNumbersPermission();
  }

  // Notifications (Android 13+)
  if (!await VonageVoice.instance.hasNotificationPermission()) {
    await VonageVoice.instance.requestNotificationPermission();
  }

  // Microphone
  if (!await VonageVoice.instance.hasMicAccess()) {
    await VonageVoice.instance.requestMicAccess();
  }
}
```

### 6.3 — Phone Account Registration (Android)

Android requires your app to register as a **Telecom PhoneAccount** to handle calls through the system:

```dart
// Check if phone account is registered
final hasAccount = await VonageVoice.instance.hasRegisteredPhoneAccount();

if (!hasAccount) {
  await VonageVoice.instance.registerPhoneAccount();
}

// Check if the user has enabled the phone account in system settings
final isEnabled = await VonageVoice.instance.isPhoneAccountEnabled();

if (!isEnabled) {
  // Open system settings so the user can enable it
  await VonageVoice.instance.openPhoneAccountSettings();
}
```

### 6.4 — Full-Screen Intent (Android 14+)

On Android 14 (API 34) and above, `USE_FULL_SCREEN_INTENT` is a special permission. Without it, the incoming call notification won't show as a full-screen overlay on the lock screen.

```dart
final canShow = await VonageVoice.instance.canUseFullScreenIntent();

if (!canShow) {
  await VonageVoice.instance.openFullScreenIntentSettings();
}
```

### 6.5 — Battery Optimization (Android)

On OEMs like **Vivo**, **Xiaomi**, **OPPO**, and **Samsung**, aggressive battery optimization can kill the app process and prevent FCM from delivering incoming call pushes.

```dart
final isOptimized = await VonageVoice.instance.isBatteryOptimized();

if (isOptimized) {
  // Opens system dialog to exempt the app
  await VonageVoice.instance.requestBatteryOptimizationExemption();
}
```

> **Highly recommended:** Always check and request battery optimization exemption during onboarding. This is the #1 reason incoming calls fail on Chinese OEM devices.

### 6.6 — Auto-Reject Calls on Missing Permissions (Android)

Automatically reject incoming calls when required permissions are not granted:

```dart
// Enable auto-rejection
await VonageVoice.instance.rejectCallOnNoPermissions(shouldReject: true);

// Check current setting
final isRejecting = await VonageVoice.instance.isRejectingCallOnNoPermissions();
```

---

## 7. Push Notification Handling

On Android, incoming calls arrive as FCM push notifications. Flutter's `firebase_messaging` plugin intercepts these messages **before** the native Vonage SDK can process them. You must forward them manually.

### Background Handler (Top-Level Function)

```dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:vonage_voice/vonage_voice.dart';

// Must be a top-level function (not inside a class)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await VonageVoice.instance.processVonagePush(message.data);
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  runApp(MyApp());
}
```

### Foreground Handler

```dart
@override
void initState() {
  super.initState();

  // Forward FCM messages received while app is in foreground
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    if (message.data.isNotEmpty) {
      VonageVoice.instance.processVonagePush(message.data);
    }
  });
}
```

> **Why both handlers?** The background handler processes incoming call pushes when the app is backgrounded or killed. The foreground handler ensures pushes received while the app is active also reach the Vonage SDK.

> **iOS Note:** On iOS, incoming call pushes are delivered via **PushKit** directly to the native layer. The plugin handles this automatically — you do **not** need FCM on iOS.

---

## 8. Call Events

### Listening to Events

```dart
VonageVoice.instance.callEventsListener.listen((CallEvent event) {
  switch (event) {
    case CallEvent.incoming:
      final call = VonageVoice.instance.call.activeCall;
      print('Incoming call from ${call?.fromFormatted}');
      break;
    case CallEvent.ringing:
      print('Outgoing call is ringing');
      break;
    case CallEvent.connected:
      print('Call connected');
      break;
    case CallEvent.callEnded:
      print('Call ended');
      break;
    case CallEvent.hold:
      print('Call on hold');
      break;
    case CallEvent.unhold:
      print('Call resumed');
      break;
    case CallEvent.mute:
      print('Microphone muted');
      break;
    case CallEvent.unmute:
      print('Microphone unmuted');
      break;
    case CallEvent.speakerOn:
      print('Speaker enabled');
      break;
    case CallEvent.speakerOff:
      print('Speaker disabled');
      break;
    case CallEvent.bluetoothOn:
      print('Bluetooth audio connected');
      break;
    case CallEvent.bluetoothOff:
      print('Bluetooth audio disconnected');
      break;
    case CallEvent.missedCall:
      print('Missed call');
      break;
    case CallEvent.declined:
      print('Call declined');
      break;
    case CallEvent.reconnecting:
      print('Reconnecting...');
      break;
    case CallEvent.reconnected:
      print('Reconnected');
      break;
    default:
      break;
  }
});
```

### All Call Events

| Event | Description |
|-------|-------------|
| `incoming` | Incoming call invite received |
| `ringing` | Outbound call is ringing on the remote side |
| `connected` | Call media connected — both parties can speak |
| `reconnecting` | Call media is reconnecting after a network interruption |
| `reconnected` | Call media reconnected after a network interruption |
| `callEnded` | Call ended — local hangup or remote disconnect |
| `hold` | Call placed on hold |
| `unhold` | Call resumed from hold |
| `mute` | Microphone muted |
| `unmute` | Microphone unmuted |
| `speakerOn` | Audio routed to speakerphone |
| `speakerOff` | Audio routed away from speakerphone |
| `bluetoothOn` | Audio routed to Bluetooth headset |
| `bluetoothOff` | Audio routed away from Bluetooth headset |
| `declined` | Call was declined by remote party |
| `answer` | Incoming call was answered |
| `missedCall` | Incoming call was missed (cancelled before answered) |
| `returningCall` | Returning call event |
| `audioRouteChanged` | Audio route changed (iOS only) |
| `log` | Diagnostic / informational log event |
| `permission` | A runtime permission result was received |

---

## 9. Making Outgoing Calls

```dart
final success = await VonageVoice.instance.call.place(
  from: 'alice',           // Your Vonage user identity
  to: '+14155551234',      // Destination phone number or Vonage user
  extraOptions: {          // Optional: custom params sent to your backend
    'custom_key': 'value',
  },
);

if (success == true) {
  print('Call placed successfully');
}
```

The call flow after placing:

1. `CallEvent.ringing` — the remote side is ringing
2. `CallEvent.connected` — the call is answered and media is flowing
3. `CallEvent.callEnded` — the call ends

---

## 10. Handling Incoming Calls

When an incoming call arrives:

1. A `CallEvent.incoming` event is emitted.
2. On **iOS**, CallKit automatically shows the native incoming call screen.
3. On **Android**, the Telecom ConnectionService shows the incoming call notification.

```dart
VonageVoice.instance.callEventsListener.listen((event) {
  if (event == CallEvent.incoming) {
    // Get caller information
    final activeCall = VonageVoice.instance.call.activeCall;
    print('Incoming from: ${activeCall?.fromFormatted}');
    print('To: ${activeCall?.toFormatted}');
    print('Direction: ${activeCall?.callDirection}');
    print('Custom params: ${activeCall?.customParams}');
  }
});
```

### Answer an Incoming Call

```dart
await VonageVoice.instance.call.answer();
```

### Decline an Incoming Call

```dart
await VonageVoice.instance.call.hangUp();
```

---

## 11. Call Controls

All call controls are accessed via `VonageVoice.instance.call`.

### Hang Up

```dart
await VonageVoice.instance.call.hangUp();
```

### Mute / Unmute

```dart
// Mute the microphone
await VonageVoice.instance.call.toggleMute(true);

// Unmute the microphone
await VonageVoice.instance.call.toggleMute(false);

// Check if currently muted
final muted = await VonageVoice.instance.call.isMuted();
```

### Speaker

```dart
// Enable speakerphone
await VonageVoice.instance.call.toggleSpeaker(true);

// Disable speakerphone (back to earpiece)
await VonageVoice.instance.call.toggleSpeaker(false);

// Check if speaker is on
final speaker = await VonageVoice.instance.call.isOnSpeaker();
```

### Hold / Resume

```dart
// Put call on hold
await VonageVoice.instance.call.holdCall(holdCall: true);

// Resume call
await VonageVoice.instance.call.holdCall(holdCall: false);

// Check if on hold
final holding = await VonageVoice.instance.call.isHolding();
```

### Bluetooth Audio

```dart
// Route audio to Bluetooth headset
await VonageVoice.instance.call.toggleBluetooth(bluetoothOn: true);

// Route audio away from Bluetooth
await VonageVoice.instance.call.toggleBluetooth(bluetoothOn: false);

// Check current Bluetooth state
final btOn = await VonageVoice.instance.call.isBluetoothOn();

// Check if a Bluetooth audio device is connected and available
final btAvailable = await VonageVoice.instance.call.isBluetoothAvailable();

// Check if the device's Bluetooth adapter is enabled
final btEnabled = await VonageVoice.instance.call.isBluetoothEnabled();

// Show native "Turn on Bluetooth?" dialog
final userEnabled = await VonageVoice.instance.call.showBluetoothEnablePrompt();

// Open system Bluetooth settings to pair/connect devices
await VonageVoice.instance.call.openBluetoothSettings();
```

#### Full Bluetooth Flow Example

```dart
Future<void> toggleBluetooth(bool enable) async {
  if (!enable) {
    await VonageVoice.instance.call.toggleBluetooth(bluetoothOn: false);
    return;
  }

  // 1. Check if Bluetooth adapter is enabled
  final btEnabled = await VonageVoice.instance.call.isBluetoothEnabled() ?? false;
  if (!btEnabled) {
    final userEnabled = await VonageVoice.instance.call.showBluetoothEnablePrompt() ?? false;
    if (!userEnabled) return;
    await Future.delayed(const Duration(seconds: 2)); // Wait for devices to connect
  }

  // 2. Check if a Bluetooth audio device is available
  final btAvailable = await VonageVoice.instance.call.isBluetoothAvailable() ?? false;
  if (btAvailable) {
    await VonageVoice.instance.call.toggleBluetooth(bluetoothOn: true);
  } else {
    await VonageVoice.instance.call.openBluetoothSettings();
  }
}
```

### DTMF (Dial Tones)

Send DTMF tones during an active call (e.g. for IVR menus):

```dart
// Send a single digit
await VonageVoice.instance.call.sendDigits('1');

// Send multiple digits
await VonageVoice.instance.call.sendDigits('1234');

// Send special characters
await VonageVoice.instance.call.sendDigits('*#');
```

### Call Status

```dart
// Check if there is an active call
final onCall = await VonageVoice.instance.call.isOnCall();

// Get the Vonage call ID
final callId = await VonageVoice.instance.call.getSid();

// Get the active call object
final activeCall = VonageVoice.instance.call.activeCall;
```

---

## 12. Caller Registry

Map caller identities to human-readable display names. These names appear on the incoming call screen (CallKit on iOS, notification on Android).

```dart
// Register a caller name
await VonageVoice.instance.registerClient('user_123', 'John Doe');
await VonageVoice.instance.registerClient('user_456', 'Jane Smith');

// Remove a registered name
await VonageVoice.instance.unregisterClient('user_123');

// Set a fallback name for unregistered callers
await VonageVoice.instance.setDefaultCallerName('Unknown Caller');
```

---

## 13. ActiveCall Model

When a call is active (or pending), you can access its details:

```dart
final call = VonageVoice.instance.call.activeCall;

if (call != null) {
  print(call.from);           // Raw caller number/identity
  print(call.fromFormatted);  // Formatted: "(415) 555-1234"
  print(call.to);             // Raw destination number/identity
  print(call.toFormatted);    // Formatted destination
  print(call.initiated);      // DateTime when connected (null until connected)
  print(call.callDirection);  // CallDirection.incoming or .outgoing
  print(call.customParams);   // Map from your Vonage backend (nullable)
}
```

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `from` | `String` | Raw caller number or identity (`client:` prefix stripped) |
| `fromFormatted` | `String` | Human-readable formatted caller number |
| `to` | `String` | Raw destination number or identity |
| `toFormatted` | `String` | Human-readable formatted destination |
| `initiated` | `DateTime?` | Timestamp when call connected (null until `CallEvent.connected`) |
| `callDirection` | `CallDirection` | `.incoming` or `.outgoing` |
| `customParams` | `Map<String, dynamic>?` | Custom parameters from your Vonage backend |

### CallDirection Enum

| Value | Description |
|-------|-------------|
| `CallDirection.incoming` | Call received from a remote party |
| `CallDirection.outgoing` | Call placed by the local user |

---

## 14. Platform-Specific Features

### iOS Only

#### CallKit Icon

Set a custom icon displayed in the native CallKit UI:

```dart
await VonageVoice.instance.updateCallKitIcon(icon: 'CallKitIcon');
```

> The icon must be a 40x40pt template image added to your iOS app's asset catalog.

#### isSandbox Parameter

See [APNs Environment](#35--apns-environment-sandbox-vs-production) — controls whether VoIP pushes use Apple's sandbox or production environment.

### Android Only

#### Phone Account (Telecom ConnectionService)

See [Phone Account Registration](#63--phone-account-registration-android).

#### Battery Optimization Exemption

See [Battery Optimization](#65--battery-optimization-android).

#### Full-Screen Intent (Android 14+)

See [Full-Screen Intent](#64--full-screen-intent-android-14).

#### Missed Call Notifications

Control whether the plugin shows a notification for missed calls:

```dart
VonageVoice.instance.showMissedCallNotifications = true;  // or false
```

---

## 15. API Reference

### Session & Device Management — `VonageVoice.instance`

| Method | Returns | Platform | Description |
|--------|---------|----------|-------------|
| `setTokens({accessToken, deviceToken?, isSandbox?})` | `Future<bool?>` | Both | Register JWT and optional FCM token |
| `unregister({accessToken?})` | `Future<bool?>` | Both | End session and unregister push token |
| `refreshSession({accessToken})` | `Future<bool?>` | Both | Refresh JWT without destroying session |
| `callEventsListener` | `Stream<CallEvent>` | Both | Stream of typed call events |
| `setOnDeviceTokenChanged(callback)` | `void` | Both | Listen for FCM token refresh |
| `showMissedCallNotifications` (setter) | `void` | Both | Enable/disable missed call notifications |
| `processVonagePush(data)` | `Future<String?>` | Both | Forward FCM push payload to Vonage SDK |
| `registerClient(id, name)` | `Future<bool?>` | Both | Map caller ID to display name |
| `unregisterClient(id)` | `Future<bool?>` | Both | Remove caller ID mapping |
| `setDefaultCallerName(name)` | `Future<bool?>` | Both | Set fallback display name |
| `updateCallKitIcon({icon})` | `Future<bool?>` | iOS | Set CallKit UI icon |

### Permissions — `VonageVoice.instance`

| Method | Returns | Platform | Description |
|--------|---------|----------|-------------|
| `hasMicAccess()` | `Future<bool>` | Both | Check microphone permission |
| `requestMicAccess()` | `Future<bool?>` | Both | Request microphone permission |
| `hasReadPhoneStatePermission()` | `Future<bool>` | Android | Check READ_PHONE_STATE |
| `requestReadPhoneStatePermission()` | `Future<bool?>` | Android | Request READ_PHONE_STATE |
| `hasCallPhonePermission()` | `Future<bool>` | Android | Check CALL_PHONE |
| `requestCallPhonePermission()` | `Future<bool?>` | Android | Request CALL_PHONE |
| `hasManageOwnCallsPermission()` | `Future<bool>` | Android | Check MANAGE_OWN_CALLS |
| `requestManageOwnCallsPermission()` | `Future<bool?>` | Android | Request MANAGE_OWN_CALLS |
| `hasReadPhoneNumbersPermission()` | `Future<bool>` | Android | Check READ_PHONE_NUMBERS |
| `requestReadPhoneNumbersPermission()` | `Future<bool?>` | Android | Request READ_PHONE_NUMBERS |
| `hasNotificationPermission()` | `Future<bool>` | Android | Check POST_NOTIFICATIONS (API 33+) |
| `requestNotificationPermission()` | `Future<bool?>` | Android | Request POST_NOTIFICATIONS |
| `hasRegisteredPhoneAccount()` | `Future<bool>` | Android | Check PhoneAccount registration |
| `registerPhoneAccount()` | `Future<bool?>` | Android | Register Telecom PhoneAccount |
| `isPhoneAccountEnabled()` | `Future<bool>` | Android | Check if PhoneAccount is enabled |
| `openPhoneAccountSettings()` | `Future<bool?>` | Android | Open system phone account settings |
| `canUseFullScreenIntent()` | `Future<bool>` | Android | Check full-screen intent permission (API 34+) |
| `openFullScreenIntentSettings()` | `Future<bool?>` | Android | Open full-screen intent settings |
| `isBatteryOptimized()` | `Future<bool>` | Android | Check if app is battery optimized |
| `requestBatteryOptimizationExemption()` | `Future<bool?>` | Android | Request battery optimization exemption |
| `rejectCallOnNoPermissions({shouldReject})` | `Future<bool>` | Android | Auto-reject calls on missing permissions |
| `isRejectingCallOnNoPermissions()` | `Future<bool>` | Android | Check auto-reject setting |

### Call Controls — `VonageVoice.instance.call`

| Method | Returns | Platform | Description |
|--------|---------|----------|-------------|
| `place({from, to, extraOptions?})` | `Future<bool?>` | Both | Place an outbound call |
| `answer()` | `Future<bool?>` | Both | Answer a pending incoming call |
| `hangUp()` | `Future<bool?>` | Both | Hang up the active call |
| `isOnCall()` | `Future<bool>` | Both | Check if a call is in progress |
| `getSid()` | `Future<String?>` | Both | Get the active Vonage call ID |
| `activeCall` (getter) | `ActiveCall?` | Both | Get the current call state |
| `toggleMute(isMuted)` | `Future<bool?>` | Both | Mute/unmute microphone |
| `isMuted()` | `Future<bool?>` | Both | Check mute state |
| `toggleSpeaker(speakerIsOn)` | `Future<bool?>` | Both | Enable/disable speakerphone |
| `isOnSpeaker()` | `Future<bool?>` | Both | Check speaker state |
| `holdCall({holdCall})` | `Future<bool?>` | Both | Hold/resume the call |
| `isHolding()` | `Future<bool?>` | Both | Check hold state |
| `toggleBluetooth({bluetoothOn})` | `Future<bool?>` | Both | Route audio to/from Bluetooth |
| `isBluetoothOn()` | `Future<bool?>` | Both | Check Bluetooth audio state |
| `isBluetoothAvailable()` | `Future<bool?>` | Both | Check if Bluetooth device is connected |
| `isBluetoothEnabled()` | `Future<bool?>` | Both | Check if Bluetooth adapter is on |
| `showBluetoothEnablePrompt()` | `Future<bool?>` | Both | Show "Turn on Bluetooth?" dialog |
| `openBluetoothSettings()` | `Future<bool?>` | Both | Open system Bluetooth settings |
| `sendDigits(digits)` | `Future<bool?>` | Both | Send DTMF tones |

---

## License

See [LICENSE](LICENSE) for details.

