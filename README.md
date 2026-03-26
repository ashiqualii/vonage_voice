# Vonage Voice — Flutter Plugin

A Flutter plugin that lets you make and receive voice calls using the **Vonage Client SDK**. It works on both Android and iOS with native call screens built in — **CallKit** on iOS and **ConnectionService** on Android.

| Platform | Minimum Version |
|----------|----------------|
| Android  | API 24 (Android 7.0) |
| iOS      | 13.0 |

### What You Can Do With This Plugin

- Make outgoing voice calls
- Receive incoming voice calls (even when the app is in the background or killed)
- Native incoming call screen — CallKit on iOS, system notification on Android
- Control active calls — mute, hold, speaker, Bluetooth, DTMF tones
- Map caller IDs to display names so the call screen shows real names
- Audio routing — switch between earpiece, speaker, and Bluetooth during a call

---

## Table of Contents

1. [Before You Start](#1-before-you-start)
2. [Installation](#2-installation)
3. [Android Setup](#3-android-setup)
4. [iOS Setup](#4-ios-setup)
5. [Upload Push Credentials to Vonage](#5-upload-push-credentials-to-vonage)
6. [Import & Access the Plugin](#6-import--access-the-plugin)
7. [Login](#7-login)
8. [Permissions](#8-permissions)
9. [Making Outgoing Calls](#9-making-outgoing-calls)
10. [Receiving Incoming Calls](#10-receiving-incoming-calls)
11. [In-Call Controls](#11-in-call-controls)
12. [Caller Registry](#12-caller-registry)
13. [Token Refresh & Logout](#13-token-refresh--logout)
14. [All Call Events](#14-all-call-events)
15. [ActiveCall Model](#15-activecall-model)
16. [Platform-Specific Extras](#16-platform-specific-extras)
17. [Full API Reference](#17-full-api-reference)

---

## 1. Before You Start

Make sure you have these things ready before you begin:

- **A Vonage Application** with Voice capability enabled. You can create one from the [Vonage Dashboard](https://dashboard.nexmo.com/applications). Note down your **Application ID**.
- **A JWT (JSON Web Token)** for each user — your backend server generates this. You don't need to worry about how it's generated. Your app will just receive a JWT string from your backend API and pass it to this plugin.
- **Firebase set up in your project** (Android only) — Firebase Cloud Messaging (FCM) is used to deliver incoming call notifications on Android. If you haven't set up Firebase yet, follow the [official Firebase Flutter setup guide](https://firebase.google.com/docs/flutter/setup).
- **A VoIP push certificate** (`.p12` file) from Apple (iOS only) — this is needed so Vonage can send incoming call pushes to iOS devices. You create this in the [Apple Developer Portal](https://developer.apple.com/account/resources/certificates) under "VoIP Services Certificate" for your app's Bundle ID. Export it as a `.p12` file.

---

## 2. Installation

Add the plugin and Firebase packages to your `pubspec.yaml`:

```yaml
dependencies:
  vonage_voice:
  firebase_core:        
  firebase_messaging:  
```

Then run:

```bash
flutter pub get
```

---

## 3. Android Setup

### 3.1 — Add Firebase to Your Android App

1. Place your `google-services.json` file inside `android/app/`.
2. Add the Google Services plugin to your **app-level** `android/app/build.gradle.kts`:

```kotlin
plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services") // Add this line
}
```

3. Make sure the Google Services plugin is available in your **project-level** `settings.gradle.kts`:

```kotlin
plugins {
    id("com.google.gms.google-services") version "4.4.0" apply false
}
```

### 3.2 — Permissions (Automatic)

You do **not** need to add any permissions to your `AndroidManifest.xml`. The plugin declares all the permissions it needs (microphone, phone state, foreground service, notifications, etc.) and they get merged into your app automatically at build time.

### 3.3 — ProGuard / R8 (Automatic)

If you use code minification (`isMinifyEnabled = true`) in your release build, the plugin's ProGuard rules are also merged automatically. No extra setup needed.

---

## 4. iOS Setup

### 4.1 — Set Minimum iOS Version

In your `ios/Podfile`, make sure the platform target is at least 13.0:

```ruby
platform :ios, '13.0'
```

Then run:

```bash
cd ios && pod install
```

### 4.2 — Update Info.plist

Add these entries to `ios/Runner/Info.plist`:

```xml
<!-- Microphone permission — shown to the user when the app asks for mic access -->
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access to make and receive voice calls.</string>

<!-- Background modes — lets the app receive VoIP pushes and play audio in the background -->
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
    <string>voip</string>
    <string>fetch</string>
    <string>remote-notification</string>
</array>
```

### 4.3 — Enable Xcode Capabilities

Open your project in Xcode (`ios/Runner.xcworkspace`) and go to **Signing & Capabilities**. Add:

| Capability | What to Check |
|-----------|---------------|
| **Push Notifications** | Just enable it — no extra checkboxes |
| **Background Modes** | Check: **Audio, AirPlay and Picture in Picture**, **Voice over IP**, **Background fetch**, **Remote notifications** |

---

## 5. Upload Push Credentials to Vonage

For incoming calls to work, Vonage needs your push credentials so it can send notifications to your users' devices.

Go to the [Vonage Dashboard](https://dashboard.nexmo.com/applications) → your application → **Push Credentials**:

- **For Android:** Upload your Firebase **Server Key** (or FCM v1 service account JSON).
- **For iOS:** Upload your VoIP push certificate (`.p12` file).

Without this step, incoming calls will **not** work.

---

## 6. Import & Access the Plugin

```dart
import 'package:vonage_voice/vonage_voice.dart';
```

This gives you access to everything:

| Class | What It Does |
|-------|-------------|
| `VonageVoice` | Main plugin — login, permissions, push handling, caller registry |
| `VonageCall` | Call controls — place, answer, hang up, mute, speaker, hold, bluetooth, DTMF |
| `CallEvent` | All possible call events (incoming, connected, callEnded, mute, speakerOn, etc.) |
| `ActiveCall` | Details of the current call (from, to, direction, custom params) |
| `CallDirection` | Either `.incoming` or `.outgoing` |

### How to Access

The plugin uses a **singleton** — you access everything through `VonageVoice.instance`:

```dart
// For login, permissions, push handling:
VonageVoice.instance

// For call controls (place, answer, mute, speaker, etc.):
VonageVoice.instance.call
```

---

## 7. Login

To log in, you need two things:
1. **A JWT string** — get this from your backend API.
2. **An FCM token** (Android only) — this lets Vonage send incoming call notifications to the device.

```dart

Future<void> login() async {
  // Make sure Firebase is initialized first
  await Firebase.initializeApp();

  // Get your JWT from your backend
  final String jwt = await yourBackendApi.getVonageJwt();

  // Get FCM token (Android only — needed for incoming calls)
  String? fcmToken;
  if (Platform.isAndroid) {
    fcmToken = await FirebaseMessaging.instance.getToken();
  }

  // Register with Vonage
  final success = await VonageVoice.instance.setTokens(
    accessToken: jwt,           // Your JWT from backend
    deviceToken: fcmToken,      // FCM token (Android) — pass null on iOS
    isSandbox: false,           // iOS only: true for debug builds, false for release
  );

  if (success == true) {
    print('Logged in!');
  }
}
```

### What Each Parameter Means

| Parameter | Required | Description |
|-----------|----------|-------------|
| `accessToken` | Yes | The Vonage JWT string from your backend |
| `deviceToken` | Android only | The FCM token. On iOS, leave it as `null` — the plugin handles VoIP push tokens automatically via PushKit |
| `isSandbox` | iOS only | Set to `true` when running debug/development builds, `false` for release. This tells the plugin which Apple Push environment to use. If set wrong, incoming calls won't work on iOS |

---

## 8. Permissions

Before making or receiving calls, you need to request some permissions. The plugin gives you methods for each one.

### 8.1 — Microphone (Both Platforms)

This is the only permission needed on iOS. On Android, you need a few more.

```dart
if (!await VonageVoice.instance.hasMicAccess()) {
  await VonageVoice.instance.requestMicAccess();
}
```

### 8.2 — Android Permissions

On Android, several permissions are needed for the call system to work properly:

```dart
import 'dart:io';

Future<void> requestAndroidPermissions() async {
  if (!Platform.isAndroid) return;

  // Microphone — needed to capture voice during calls
  if (!await VonageVoice.instance.hasMicAccess()) {
    await VonageVoice.instance.requestMicAccess();
  }

  // Phone state — needed by Android's call system
  if (!await VonageVoice.instance.hasReadPhoneStatePermission()) {
    await VonageVoice.instance.requestReadPhoneStatePermission();
  }

  // Call phone — needed to place outgoing calls
  if (!await VonageVoice.instance.hasCallPhonePermission()) {
    await VonageVoice.instance.requestCallPhonePermission();
  }

  // Manage own calls — needed for Android's Telecom framework
  if (!await VonageVoice.instance.hasManageOwnCallsPermission()) {
    await VonageVoice.instance.requestManageOwnCallsPermission();
  }

  // Read phone numbers — needed by some phone manufacturers
  if (!await VonageVoice.instance.hasReadPhoneNumbersPermission()) {
    await VonageVoice.instance.requestReadPhoneNumbersPermission();
  }

  // Notifications (Android 13+) — needed to show call notifications
  if (!await VonageVoice.instance.hasNotificationPermission()) {
    await VonageVoice.instance.requestNotificationPermission();
  }
}
```

### 8.3 — Phone Account (Android)

Android needs your app to be registered as a "phone account" in the system before it can handle calls:

```dart
// Register the phone account (do this once, like on first launch)
if (!await VonageVoice.instance.hasRegisteredPhoneAccount()) {
  await VonageVoice.instance.registerPhoneAccount();
}

// Check if the user has enabled it in system settings
if (!await VonageVoice.instance.isPhoneAccountEnabled()) {
  // This opens the system settings screen where the user can enable it
  await VonageVoice.instance.openPhoneAccountSettings();
}
```

### 8.4 — Full-Screen Incoming Call (Android 14+)

On Android 14 and newer, you need a special permission to show the incoming call as a full-screen notification on the lock screen. Without it, it will only appear as a small notification.

```dart
if (!await VonageVoice.instance.canUseFullScreenIntent()) {
  await VonageVoice.instance.openFullScreenIntentSettings();
}
```

### 8.5 — Battery Optimization (Android — Important!)

Phone manufacturers like **Vivo, Xiaomi, OPPO, and Samsung** have aggressive battery management that can kill your app in the background. When this happens, incoming call notifications won't arrive.

**This is the #1 reason incoming calls fail on these devices.** Always request this during your app's setup:

```dart
if (await VonageVoice.instance.isBatteryOptimized()) {
  await VonageVoice.instance.requestBatteryOptimizationExemption();
}
```

### 8.6 — Auto-Reject Calls on Missing Permissions (Android, Optional)

You can tell the plugin to automatically reject incoming calls if the user hasn't granted the required permissions (like microphone). This prevents calls from connecting with no audio.

```dart
await VonageVoice.instance.rejectCallOnNoPermissions(shouldReject: true);

// Check the current setting:
final isRejecting = await VonageVoice.instance.isRejectingCallOnNoPermissions();
```

---

## 9. Making Outgoing Calls

### Place a Call

```dart
final success = await VonageVoice.instance.call.place(
  from: 'alice',             // Your Vonage user identity
  to: '+14155551234',        // Who you're calling (phone number or Vonage user)
  extraOptions: {            // Optional — custom data sent to your backend
    'displayName': 'Alice',
  },
);

if (success == true) {
  print('Call placed!');
}
```

| Parameter | Required | Description |
|-----------|----------|-------------|
| `from` | Yes | Your Vonage user identity (the caller) |
| `to` | Yes | The destination — a phone number like `+14155551234` or another Vonage user identity |
| `extraOptions` | No | A map of key-value pairs that gets forwarded to your Vonage backend. Use it to pass things like display names, recording flags, or any custom data |

### What Happens After You Place a Call

The plugin fires events as the call progresses. Listen to them to update your UI:

```dart
VonageVoice.instance.callEventsListener.listen((event) {
  switch (event) {
    case CallEvent.ringing:
      // The other person's phone is ringing
      print('Ringing...');
      break;
    case CallEvent.connected:
      // Both sides are connected — you can talk now
      print('Connected!');
      break;
    case CallEvent.callEnded:
      // The call is over
      print('Call ended');
      break;
    default:
      break;
  }
});
```

**Outgoing call flow:**
1. You call `place()` → the call starts
2. `CallEvent.ringing` → the other side is ringing
3. `CallEvent.connected` → call connected, both sides can talk
4. `CallEvent.callEnded` → call ended (either side hung up)

### Get Active Call Details

Once a call starts, you can access its details anytime:

```dart
final call = VonageVoice.instance.call.activeCall;

if (call != null) {
  print(call.from);           // Who's calling (e.g. "alice")
  print(call.to);             // Who's being called (e.g. "+14155551234")
  print(call.fromFormatted);  // Formatted nicely: "(415) 555-1234"
  print(call.toFormatted);    // Formatted nicely
  print(call.callDirection);  // CallDirection.outgoing
  print(call.initiated);      // DateTime when call connected (null until connected)
  print(call.customParams);   // Custom data from your backend (if any)
}
```

---

## 10. Receiving Incoming Calls

Incoming calls work differently on each platform:

- **Android:** Vonage sends a Firebase push notification → the plugin's native code picks it up → shows a system call notification (or full-screen UI on lock screen).
- **iOS:** Vonage sends a VoIP push via Apple's PushKit → the plugin handles it automatically → CallKit shows the native incoming call screen.

### 10.1 — Forward Firebase Push to Vonage (Android — Required)

On Android, Flutter's `firebase_messaging` package intercepts push messages **before** the native Vonage SDK can see them. You need to forward these messages so the plugin can process incoming calls.

You need **two** handlers — one for when the app is in the background/killed, and one for when it's in the foreground:

#### Background Handler

This must be a **top-level function** (not inside any class). Add it to your `main.dart`:

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:vonage_voice/vonage_voice.dart';

// Must be top-level — not inside a class
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (message.data.isNotEmpty) {
    await VonageVoice.instance.processVonagePush(message.data);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Register the background handler — must be before runApp()
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(MyApp());
}
```

#### Foreground Handler

Add this in your main screen's `initState()`:

```dart
@override
void initState() {
  super.initState();

  // Forward push messages received while app is open
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    if (message.data.isNotEmpty) {
      VonageVoice.instance.processVonagePush(message.data);
    }
  });
}
```

> **Why do you need both?** The background handler runs when the app is closed or in the background. The foreground handler runs when the app is open. Without both, you'll miss incoming calls in some situations.

> **iOS:** You don't need any of this on iOS. The plugin handles VoIP pushes automatically through PushKit. No Firebase code needed for iOS incoming calls.

### 10.2 — Listen for Incoming Calls

When an incoming call arrives, the plugin fires `CallEvent.incoming`. Listen for it:

```dart
VonageVoice.instance.callEventsListener.listen((event) {
  if (event == CallEvent.incoming) {
    // An incoming call is here!
    final call = VonageVoice.instance.call.activeCall;

    print('Incoming call from: ${call?.fromFormatted}');
    print('To: ${call?.toFormatted}');
    print('Direction: ${call?.callDirection}');   // CallDirection.incoming
    print('Custom params: ${call?.customParams}'); // Data from your backend

    // At this point, the native call screen is already showing
    // (CallKit on iOS, system notification on Android).
    // You can also build your own in-app incoming call UI if you want.
  }
});
```

### 10.3 — Answer or Decline

#### Answer the Call

```dart
await VonageVoice.instance.call.answer();
```

After answering, the plugin fires `CallEvent.answer` followed by `CallEvent.connected` once both sides can talk.

#### Decline the Call

```dart
await VonageVoice.instance.call.hangUp();
```

After declining, the plugin fires `CallEvent.callEnded`.

> **Note:** The user can also answer or decline from the native call screen (CallKit / system notification) without any Flutter code. The plugin handles that automatically.

### 10.4 — Incoming Call Event Flow

Here's the full sequence of events for an incoming call:

1. `CallEvent.incoming` → a call invite arrived
2. User answers → `CallEvent.answer` → `CallEvent.connected` → both sides can talk
3. Call ends → `CallEvent.callEnded`

Or if the user doesn't answer:
1. `CallEvent.incoming` → a call invite arrived
2. Caller gives up → `CallEvent.missedCall`

Or if the user declines:
1. `CallEvent.incoming` → a call invite arrived
2. User declines → `CallEvent.callEnded`

---

## 11. In-Call Controls

Once a call is connected, you can control it using `VonageVoice.instance.call`. Every action below fires a corresponding `CallEvent` so you can update your UI.

### 11.1 — Mute / Unmute

Stop or start sending your voice to the other person.

```dart
// Mute your microphone
await VonageVoice.instance.call.toggleMute(true);

// Unmute your microphone
await VonageVoice.instance.call.toggleMute(false);

// Check if you're currently muted
final isMuted = await VonageVoice.instance.call.isMuted();
```

**Events fired:**
- `CallEvent.mute` — when microphone is muted
- `CallEvent.unmute` — when microphone is unmuted

### 11.2 — Speaker On / Off

Switch between the earpiece (default) and the loudspeaker.

```dart
// Turn on speaker
await VonageVoice.instance.call.toggleSpeaker(true);

// Turn off speaker (back to earpiece)
await VonageVoice.instance.call.toggleSpeaker(false);

// Check if speaker is currently on
final isOnSpeaker = await VonageVoice.instance.call.isOnSpeaker();
```

**Events fired:**
- `CallEvent.speakerOn` — when audio switches to speaker
- `CallEvent.speakerOff` — when audio switches away from speaker

### 11.3 — Hold / Resume

Put the call on hold or resume it. The other person will hear silence (or hold music if your backend is set up for that).

```dart
// Put the call on hold
await VonageVoice.instance.call.holdCall(holdCall: true);

// Resume the call
await VonageVoice.instance.call.holdCall(holdCall: false);

// Check if the call is currently on hold
final isHolding = await VonageVoice.instance.call.isHolding();
```

**Events fired:**
- `CallEvent.hold` — when call is placed on hold
- `CallEvent.unhold` — when call is resumed

### 11.4 — Bluetooth Audio

Route the call audio to a connected Bluetooth headset or speaker. This section covers the full flow — from checking if Bluetooth is available to actually routing the audio.

#### Basic Usage

```dart
// Route audio to Bluetooth device
await VonageVoice.instance.call.toggleBluetooth(bluetoothOn: true);

// Route audio back to earpiece/speaker
await VonageVoice.instance.call.toggleBluetooth(bluetoothOn: false);

// Check if audio is currently going through Bluetooth
final isBtOn = await VonageVoice.instance.call.isBluetoothOn();
```

**Events fired:**
- `CallEvent.bluetoothOn` — when audio routes to Bluetooth
- `CallEvent.bluetoothOff` — when audio routes away from Bluetooth

#### Helper Methods

Before routing to Bluetooth, you might want to check a few things:

```dart
// Is a Bluetooth audio device connected and ready?
final isAvailable = await VonageVoice.instance.call.isBluetoothAvailable();

// Is the device's Bluetooth adapter turned on?
final isEnabled = await VonageVoice.instance.call.isBluetoothEnabled();

// Ask the user to turn on Bluetooth (Android only — does nothing on iOS)
final userSaidYes = await VonageVoice.instance.call.showBluetoothEnablePrompt();

// Open system Bluetooth settings so user can pair/connect a device
await VonageVoice.instance.call.openBluetoothSettings();
```

#### Full Bluetooth Flow (Recommended)

Here's how to handle Bluetooth properly in a real app — checking each step before proceeding:

```dart
Future<void> handleBluetoothToggle(bool enable) async {
  // Turning off is simple
  if (!enable) {
    await VonageVoice.instance.call.toggleBluetooth(bluetoothOn: false);
    return;
  }

  // Step 1: Is Bluetooth turned on?
  final btEnabled = await VonageVoice.instance.call.isBluetoothEnabled() ?? false;
  if (!btEnabled) {
    // Ask the user to turn it on (Android only)
    final userEnabled = await VonageVoice.instance.call.showBluetoothEnablePrompt() ?? false;
    if (!userEnabled) return; // User said no
    // Wait a moment for paired devices to auto-connect
    await Future.delayed(const Duration(seconds: 2));
  }

  // Step 2: Is a Bluetooth audio device connected?
  final btAvailable = await VonageVoice.instance.call.isBluetoothAvailable() ?? false;
  if (btAvailable) {
    // Device is connected — route audio to it
    await VonageVoice.instance.call.toggleBluetooth(bluetoothOn: true);
  } else {
    // No device connected — open settings so user can pair one
    await VonageVoice.instance.call.openBluetoothSettings();
  }
}
```

### 11.5 — DTMF Tones (Dial Pad)

Send dial tones during an active call. This is used for things like navigating phone menus ("Press 1 for sales...").

```dart
// Send a single digit
await VonageVoice.instance.call.sendDigits('1');

// Send multiple digits
await VonageVoice.instance.call.sendDigits('1234');

// Send special characters
await VonageVoice.instance.call.sendDigits('*#');
```

### 11.6 — Hang Up

```dart
await VonageVoice.instance.call.hangUp();
```

**Event fired:** `CallEvent.callEnded`

### 11.7 — Check Call Status

```dart
// Is there an active call right now?
final onCall = await VonageVoice.instance.call.isOnCall();

// Get the Vonage call ID (useful for logging or debugging)
final callId = await VonageVoice.instance.call.getSid();

// Get the full active call object
final activeCall = VonageVoice.instance.call.activeCall;
```

### 11.8 — Sync Your UI with Audio State

When a call connects (or reconnects), it's a good idea to check the current audio state so your UI buttons show the correct state. For example, if the user answered from a Bluetooth headset, your Bluetooth button should show as "on" right away.

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

  // Update your UI state with these values
  setState(() {
    _muted = isMuted;
    _speakerOn = isOnSpeaker;
    _bluetoothOn = isBtOn;
    _bluetoothAvailable = isBtAvailable;
  });
}
```

---

## 12. Caller Registry

You can map caller IDs to human-readable names. These names show up on the native incoming call screen (CallKit on iOS, system notification on Android).

```dart
// Register display names for known callers
await VonageVoice.instance.registerClient('user_123', 'John Doe');
await VonageVoice.instance.registerClient('user_456', 'Jane Smith');
await VonageVoice.instance.registerClient('+14155551234', 'Bob Jones');

// Remove a registered name
await VonageVoice.instance.unregisterClient('user_123');

// Set a fallback name for callers who are not registered
await VonageVoice.instance.setDefaultCallerName('Unknown Caller');
```

When someone calls, the plugin checks the registry:
1. If the caller's ID matches a registered name → that name is shown.
2. If no match → the default caller name is shown.
3. If no default is set → "Unknown Caller" is shown.

---

## 13. Token Refresh & Logout

### Refresh JWT Before It Expires

Vonage JWTs have an expiry time (usually 24 hours). Before it expires, refresh it so the session stays alive:

```dart
final freshJwt = await yourBackendApi.getNewVonageJwt();
await VonageVoice.instance.refreshSession(accessToken: freshJwt);
```

If the JWT has already expired, `refreshSession` won't work — you'll need to call `setTokens()` again to start a new session.

### Handle Device Token Changes

The FCM token can change at any time (e.g., when the user reinstalls the app or restores from a backup). Listen for changes and re-register:

```dart
VonageVoice.instance.setOnDeviceTokenChanged((newToken) {
  // Send this new token to your backend,
  // then call setTokens() again with the new token
  print('FCM token changed: $newToken');
});
```

### Logout

To log the user out and stop receiving incoming calls:

```dart
await VonageVoice.instance.unregister();
```

This unregisters the push token and ends the Vonage session. The device will no longer receive incoming call notifications until `setTokens()` is called again.

---

## 14. All Call Events

Listen to call events to know what's happening at any time:

```dart
VonageVoice.instance.callEventsListener.listen((CallEvent event) {
  // Handle the event
});
```

Here's every possible event:

| Event | When It Fires |
|-------|--------------|
| `incoming` | An incoming call invite arrived |
| `ringing` | Your outgoing call is ringing on the other person's phone |
| `connected` | Call is connected — both sides can talk |
| `reconnecting` | Call lost network — trying to reconnect |
| `reconnected` | Call reconnected after a network interruption |
| `callEnded` | Call is over (either side hung up, or an error) |
| `answer` | Incoming call was answered |
| `declined` | The other side declined the call |
| `missedCall` | Incoming call was not answered (caller gave up) |
| `hold` | Call was placed on hold |
| `unhold` | Call was resumed from hold |
| `mute` | Microphone was muted |
| `unmute` | Microphone was unmuted |
| `speakerOn` | Audio switched to speaker |
| `speakerOff` | Audio switched away from speaker |
| `bluetoothOn` | Audio switched to Bluetooth device |
| `bluetoothOff` | Audio switched away from Bluetooth |
| `returningCall` | A return call was placed |
| `audioRouteChanged` | Audio route changed (iOS only) |
| `log` | A diagnostic log event (for debugging) |
| `permission` | A permission result was received |

---

## 15. ActiveCall Model

When a call is active, you can access its details through `VonageVoice.instance.call.activeCall`. It returns an `ActiveCall` object (or `null` if there's no call).

```dart
final call = VonageVoice.instance.call.activeCall;

if (call != null) {
  print(call.from);           // "alice" or "+14155551234"
  print(call.fromFormatted);  // "(415) 555-1234" (nicely formatted)
  print(call.to);             // The destination
  print(call.toFormatted);    // Formatted destination
  print(call.initiated);      // DateTime when connected (null until connected)
  print(call.callDirection);  // CallDirection.incoming or .outgoing
  print(call.customParams);   // Map of custom data from your backend (can be null)
}
```

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `from` | `String` | The caller's ID or phone number (with `client:` prefix removed) |
| `fromFormatted` | `String` | Same, but formatted nicely (e.g. "(415) 555-1234") |
| `to` | `String` | The destination ID or phone number |
| `toFormatted` | `String` | Same, but formatted nicely |
| `initiated` | `DateTime?` | When the call connected. `null` until `CallEvent.connected` fires |
| `callDirection` | `CallDirection` | `.incoming` or `.outgoing` |
| `customParams` | `Map<String, dynamic>?` | Custom data from your Vonage backend. Can be `null` |

---

## 16. Platform-Specific Extras

### Missed Call Notifications (Both Platforms)

Control whether the plugin shows a notification when a call is missed:

```dart
// Show missed call notifications
VonageVoice.instance.showMissedCallNotifications = true;

// Don't show missed call notifications
VonageVoice.instance.showMissedCallNotifications = false;
```

### CallKit Icon (iOS Only)

Show a custom icon on the iOS CallKit incoming call screen:

```dart
await VonageVoice.instance.updateCallKitIcon(icon: 'MyCallIcon');
```

The icon must be a **40x40pt template image** (white content on transparent background) added to your iOS app's asset catalog in Xcode.

### APNs Sandbox vs Production (iOS Only)

The `isSandbox` parameter in `setTokens()` controls which Apple Push environment is used:

| Build Type | `isSandbox` | What Happens |
|-----------|-------------|-------------|
| Debug / development | `true` | Uses Apple's sandbox push environment |
| Release / production | `false` (default) | Uses Apple's production push environment |

If this is set wrong, incoming calls won't work on iOS.

---

## 17. Full API Reference

### Session & Device — `VonageVoice.instance`

| Method | Returns | Platform | Description |
|--------|---------|----------|-------------|
| `setTokens({accessToken, deviceToken?, isSandbox?})` | `Future<bool?>` | Both | Log in — register JWT and optional FCM token |
| `unregister({accessToken?})` | `Future<bool?>` | Both | Log out — end session and unregister push |
| `refreshSession({accessToken})` | `Future<bool?>` | Both | Refresh JWT without dropping the session |
| `callEventsListener` | `Stream<CallEvent>` | Both | Stream of all call events |
| `setOnDeviceTokenChanged(callback)` | `void` | Both | Listen for FCM/VoIP token changes |
| `showMissedCallNotifications` (setter) | `void` | Both | Enable or disable missed call notifications |
| `processVonagePush(data)` | `Future<String?>` | Both | Forward FCM push data to Vonage SDK |
| `registerClient(id, name)` | `Future<bool?>` | Both | Map a caller ID to a display name |
| `unregisterClient(id)` | `Future<bool?>` | Both | Remove a caller ID mapping |
| `setDefaultCallerName(name)` | `Future<bool?>` | Both | Set fallback name for unknown callers |
| `updateCallKitIcon({icon})` | `Future<bool?>` | iOS | Set the icon on CallKit call screen |

### Permissions — `VonageVoice.instance`

| Method | Returns | Platform | Description |
|--------|---------|----------|-------------|
| `hasMicAccess()` | `Future<bool>` | Both | Is microphone permission granted? |
| `requestMicAccess()` | `Future<bool?>` | Both | Ask for microphone permission |
| `hasReadPhoneStatePermission()` | `Future<bool>` | Android | Is READ_PHONE_STATE granted? |
| `requestReadPhoneStatePermission()` | `Future<bool?>` | Android | Ask for READ_PHONE_STATE |
| `hasCallPhonePermission()` | `Future<bool>` | Android | Is CALL_PHONE granted? |
| `requestCallPhonePermission()` | `Future<bool?>` | Android | Ask for CALL_PHONE |
| `hasManageOwnCallsPermission()` | `Future<bool>` | Android | Is MANAGE_OWN_CALLS granted? |
| `requestManageOwnCallsPermission()` | `Future<bool?>` | Android | Ask for MANAGE_OWN_CALLS |
| `hasReadPhoneNumbersPermission()` | `Future<bool>` | Android | Is READ_PHONE_NUMBERS granted? |
| `requestReadPhoneNumbersPermission()` | `Future<bool?>` | Android | Ask for READ_PHONE_NUMBERS |
| `hasNotificationPermission()` | `Future<bool>` | Android | Is POST_NOTIFICATIONS granted? (API 33+) |
| `requestNotificationPermission()` | `Future<bool?>` | Android | Ask for POST_NOTIFICATIONS |
| `hasRegisteredPhoneAccount()` | `Future<bool>` | Android | Is the phone account registered? |
| `registerPhoneAccount()` | `Future<bool?>` | Android | Register the app as a phone account |
| `isPhoneAccountEnabled()` | `Future<bool>` | Android | Is the phone account enabled by user? |
| `openPhoneAccountSettings()` | `Future<bool?>` | Android | Open system settings for phone accounts |
| `canUseFullScreenIntent()` | `Future<bool>` | Android | Can show full-screen call UI? (API 34+) |
| `openFullScreenIntentSettings()` | `Future<bool?>` | Android | Open settings for full-screen intent permission |
| `isBatteryOptimized()` | `Future<bool>` | Android | Is the app battery-optimized (bad for calls)? |
| `requestBatteryOptimizationExemption()` | `Future<bool?>` | Android | Ask to be exempt from battery optimization |
| `rejectCallOnNoPermissions({shouldReject})` | `Future<bool>` | Android | Auto-reject calls if permissions are missing |
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
| `toggleMute(isMuted)` | `Future<bool?>` | Both | Mute or unmute the mic |
| `isMuted()` | `Future<bool?>` | Both | Is the mic muted? |
| `toggleSpeaker(speakerIsOn)` | `Future<bool?>` | Both | Turn speaker on or off |
| `isOnSpeaker()` | `Future<bool?>` | Both | Is the speaker on? |
| `holdCall({holdCall})` | `Future<bool?>` | Both | Hold or resume the call |
| `isHolding()` | `Future<bool?>` | Both | Is the call on hold? |
| `toggleBluetooth({bluetoothOn})` | `Future<bool?>` | Both | Route audio to/from Bluetooth |
| `isBluetoothOn()` | `Future<bool?>` | Both | Is audio going through Bluetooth? |
| `isBluetoothAvailable()` | `Future<bool?>` | Both | Is a Bluetooth audio device connected? |
| `isBluetoothEnabled()` | `Future<bool?>` | Both | Is the Bluetooth adapter turned on? |
| `showBluetoothEnablePrompt()` | `Future<bool?>` | Android | Show "Turn on Bluetooth?" dialog |
| `openBluetoothSettings()` | `Future<bool?>` | Both | Open system Bluetooth settings |
| `sendDigits(digits)` | `Future<bool?>` | Both | Send DTMF tones |

---

## Example App

A full working example with login, dialer, incoming call screen, and active call screen is available in the [`example/`](example/) folder.

---

## License

See [LICENSE](LICENSE) for details.

