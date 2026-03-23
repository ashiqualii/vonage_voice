// import 'dart:async';

// import 'package:flutter/src/services/platform_channel.dart';
// import 'package:flutter_test/flutter_test.dart';
// import 'package:vonage_voice/_internal/platform_interface/vonage_call_platform_interface.dart';
// import 'package:vonage_voice/vonage_voice.dart';
// import 'package:vonage_voice/_internal/platform_interface/vonage_voice_platform_interface.dart';
// import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// // ── Mock platform implementation ──────────────────────────────────────────

// /// Mock implementation of [VonageVoicePlatform] for unit testing.
// /// All methods return predictable values without hitting native code.
// class MockVonageVoicePlatform
//     with MockPlatformInterfaceMixin
//     implements VonageVoicePlatform {
//   // ── State tracking ──────────────────────────────────────────────────────
//   bool sessionCreated = false;
//   bool sessionDeleted = false;
//   bool sessionRefreshed = false;
//   String? lastJwt;
//   String? lastDeviceToken;
//   String? lastRegisteredClientId;
//   String? lastRegisteredClientName;
//   String? lastDefaultCallerName;
//   bool showNotificationsValue = true;
//   bool rejectOnNoPermissionsValue = false;

//   // ── Session ─────────────────────────────────────────────────────────────

//   @override
//   Future<bool?> setTokens({
//     required String accessToken,
//     String? deviceToken,
//   }) async {
//     lastJwt = accessToken;
//     lastDeviceToken = deviceToken;
//     sessionCreated = true;
//     return true;
//   }

//   @override
//   Future<bool?> unregister({String? accessToken}) async {
//     sessionDeleted = true;
//     return true;
//   }

//   @override
//   Future<bool?> refreshSession({required String accessToken}) async {
//     lastJwt = accessToken;
//     sessionRefreshed = true;
//     return true;
//   }

//   // ── Caller registry ──────────────────────────────────────────────────────

//   @override
//   Future<bool?> registerClient(String clientId, String clientName) async {
//     lastRegisteredClientId = clientId;
//     lastRegisteredClientName = clientName;
//     return true;
//   }

//   @override
//   Future<bool?> unregisterClient(String clientId) async {
//     lastRegisteredClientId = null;
//     return true;
//   }

//   @override
//   Future<bool?> setDefaultCallerName(String callerName) async {
//     lastDefaultCallerName = callerName;
//     return true;
//   }

//   // ── Notifications ────────────────────────────────────────────────────────

//   @override
//   set showMissedCallNotifications(bool value) {
//     showNotificationsValue = value;
//   }

//   @override
//   Future<bool> rejectCallOnNoPermissions({bool shouldReject = false}) async {
//     rejectOnNoPermissionsValue = shouldReject;
//     return true;
//   }

//   @override
//   Future<bool> isRejectingCallOnNoPermissions() async {
//     return rejectOnNoPermissionsValue;
//   }

//   // ── Permissions ───────────────────────────────────────────────────────────

//   @override
//   Future<bool> hasMicAccess() async => true;

//   @override
//   Future<bool?> requestMicAccess() async => true;

//   @override
//   Future<bool> hasReadPhoneStatePermission() async => true;

//   @override
//   Future<bool?> requestReadPhoneStatePermission() async => true;

//   @override
//   Future<bool> hasCallPhonePermission() async => true;

//   @override
//   Future<bool?> requestCallPhonePermission() async => true;

//   @override
//   Future<bool> hasManageOwnCallsPermission() async => true;

//   @override
//   Future<bool?> requestManageOwnCallsPermission() async => true;

//   @override
//   Future<bool> hasReadPhoneNumbersPermission() async => true;

//   @override
//   Future<bool?> requestReadPhoneNumbersPermission() async => true;

//   @override
//   Future<bool> hasBluetoothPermissions() async => false;

//   @override
//   Future<bool?> requestBluetoothPermissions() async => false;

//   // ── Telecom / PhoneAccount ────────────────────────────────────────────────

//   @override
//   Future<bool> hasRegisteredPhoneAccount() async => true;

//   @override
//   Future<bool?> registerPhoneAccount() async => true;

//   @override
//   Future<bool> isPhoneAccountEnabled() async => true;

//   @override
//   Future<bool?> openPhoneAccountSettings() async => true;

//   // ── Deprecated stubs ──────────────────────────────────────────────────────

//   @override
//   Future<bool> requiresBackgroundPermissions() async => false;

//   @override
//   Future<bool?> requestBackgroundPermissions() async => false;

//   @override
//   Future<bool?> showBackgroundCallUI() async => true;

//   @override
//   Future<bool?> updateCallKitIcon({String? icon}) async => true;

//   // ── Event stream ──────────────────────────────────────────────────────────

//   @override
//   Stream<CallEvent> get callEventsListener => const Stream<CallEvent>.empty();

//   @override
//   OnDeviceTokenChanged? deviceTokenChanged;

//   @override
//   void setOnDeviceTokenChanged(OnDeviceTokenChanged deviceTokenChanged) {
//     this.deviceTokenChanged = deviceTokenChanged;
//   }

//   @override
//   VonageCallPlatform get call => _mockCall;
//   final _mockCall = MockVonageCallPlatform();

//   @override
//   CallEvent parseCallEvent(String state) {
//     switch (state) {
//       case 'Call Ended':
//         return CallEvent.callEnded;
//       case 'Mute':
//         return CallEvent.mute;
//       case 'Unmute':
//         return CallEvent.unmute;
//       case 'Hold':
//         return CallEvent.hold;
//       case 'Unhold':
//         return CallEvent.unhold;
//       case 'Speaker On':
//         return CallEvent.speakerOn;
//       case 'Speaker Off':
//         return CallEvent.speakerOff;
//       case 'Bluetooth On':
//         return CallEvent.bluetoothOn;
//       case 'Bluetooth Off':
//         return CallEvent.bluetoothOff;
//       case 'Missed Call':
//         return CallEvent.missedCall;
//       case 'Reconnecting':
//         return CallEvent.reconnecting;
//       case 'Reconnected':
//         return CallEvent.reconnected;
//       default:
//         return CallEvent.log;
//     }
//   }

//   @override
//   // implement callEventsController
//   StreamController<String> get callEventsController =>
//       throw UnimplementedError();

//   @override
//   // implement callEventsStream
//   Stream<String> get callEventsStream => throw UnimplementedError();

//   @override
//   // implement eventChannel
//   EventChannel get eventChannel => throw UnimplementedError();

//   @override
//   void logLocalEvent(
//     String description, {
//     String prefix = "LOG",
//     String separator = "|",
//   }) {
//     // implement logLocalEvent
//   }

//   @override
//   void logLocalEventEntries(
//     List<String> entries, {
//     String prefix = "LOG",
//     String separator = "|",
//   }) {
//     // implement logLocalEventEntries
//   }

//   @override
//   // implement sharedChannel
//   MethodChannel get sharedChannel => throw UnimplementedError();
// }

// /// Mock implementation of [VonageCallPlatform].
// class MockVonageCallPlatform implements VonageCallPlatform {
//   ActiveCall? _activeCall;
//   bool callPlaced = false;
//   bool callAnswered = false;
//   bool callHungUp = false;
//   bool muted = false;
//   bool onSpeaker = false;
//   bool onHold = false;
//   bool bluetoothOn = false;
//   String? lastDigits;

//   @override
//   ActiveCall? get activeCall => _activeCall;

//   @override
//   set activeCall(ActiveCall? activeCall) => _activeCall = activeCall;

//   @override
//   Future<bool?> place({
//     required String from,
//     required String to,
//     Map<String, dynamic>? extraOptions,
//   }) async {
//     callPlaced = true;
//     _activeCall = ActiveCall(
//       from: from,
//       to: to,
//       callDirection: CallDirection.outgoing,
//     );
//     return true;
//   }

//   @override
//   Future<bool?> connect({Map<String, dynamic>? extraOptions}) async => false;

//   @override
//   Future<bool?> answer() async {
//     callAnswered = true;
//     return true;
//   }

//   @override
//   Future<bool?> hangUp() async {
//     callHungUp = true;
//     _activeCall = null;
//     return true;
//   }

//   @override
//   Future<bool> isOnCall() async => _activeCall != null;

//   @override
//   Future<String?> getSid() async => 'mock_call_id_123';

//   @override
//   Future<bool?> toggleMute(bool isMuted) async {
//     muted = isMuted;
//     return true;
//   }

//   @override
//   Future<bool?> isMuted() async => muted;

//   @override
//   Future<bool?> holdCall({bool holdCall = true}) async {
//     onHold = holdCall;
//     return true;
//   }

//   @override
//   Future<bool?> isHolding() async => onHold;

//   @override
//   Future<bool?> toggleSpeaker(bool speakerIsOn) async {
//     onSpeaker = speakerIsOn;
//     return true;
//   }

//   @override
//   Future<bool?> isOnSpeaker() async => onSpeaker;

//   @override
//   Future<bool?> toggleBluetooth({bool bluetoothOn = true}) async {
//     this.bluetoothOn = bluetoothOn;
//     return true;
//   }

//   @override
//   Future<bool?> isBluetoothOn() async => bluetoothOn;

//   @override
//   Future<bool?> sendDigits(String digits) async {
//     lastDigits = digits;
//     return true;
//   }

//   @override
//   // implement callEventsController
//   StreamController<String> get callEventsController =>
//       throw UnimplementedError();

//   @override
//   // implement callEventsStream
//   Stream<String> get callEventsStream => throw UnimplementedError();

//   @override
//   // implement eventChannel
//   EventChannel get eventChannel => throw UnimplementedError();

//   @override
//   void logLocalEvent(
//     String description, {
//     String prefix = "LOG",
//     String separator = "|",
//   }) {
//     // implement logLocalEvent
//   }

//   @override
//   void logLocalEventEntries(
//     List<String> entries, {
//     String prefix = "LOG",
//     String separator = "|",
//   }) {
//     // implement logLocalEventEntries
//   }

//   @override
//   // implement sharedChannel
//   MethodChannel get sharedChannel => throw UnimplementedError();
// }

// // ── Test setup helper ─────────────────────────────────────────────────────

// late MockVonageVoicePlatform mockPlatform;

// void setupMock() {
//   mockPlatform = MockVonageVoicePlatform();
//   VonageVoicePlatform.instance = mockPlatform;
// }

// // ══════════════════════════════════════════════════════════════════════════
// // TESTS
// // ══════════════════════════════════════════════════════════════════════════

// void main() {
//   TestWidgetsFlutterBinding.ensureInitialized();

//   setUp(setupMock);

//   // ── Session management ──────────────────────────────────────────────────

//   group('Session management', () {
//     test('setTokens() passes JWT to platform', () async {
//       const jwt = 'test_jwt_token_123';
//       final result = await VonageVoice.instance.setTokens(accessToken: jwt);

//       expect(result, isTrue);
//       expect(mockPlatform.sessionCreated, isTrue);
//       expect(mockPlatform.lastJwt, equals(jwt));
//     });

//     test('setTokens() passes both JWT and FCM token', () async {
//       const jwt = 'test_jwt';
//       const fcm = 'fcm_token_xyz';

//       await VonageVoice.instance.setTokens(accessToken: jwt, deviceToken: fcm);

//       expect(mockPlatform.lastJwt, equals(jwt));
//       expect(mockPlatform.lastDeviceToken, equals(fcm));
//     });

//     test('unregister() ends the session', () async {
//       final result = await VonageVoice.instance.unregister();

//       expect(result, isTrue);
//       expect(mockPlatform.sessionDeleted, isTrue);
//     });

//     test('refreshSession() updates JWT', () async {
//       const newJwt = 'refreshed_jwt_456';
//       final result = await VonageVoice.instance.refreshSession(
//         accessToken: newJwt,
//       );

//       expect(result, isTrue);
//       expect(mockPlatform.sessionRefreshed, isTrue);
//       expect(mockPlatform.lastJwt, equals(newJwt));
//     });
//   });

//   // ── Call controls ───────────────────────────────────────────────────────

//   group('Call controls', () {
//     test('place() creates outgoing call with correct params', () async {
//       final result = await VonageVoice.instance.call.place(
//         from: 'test_user',
//         to: '+14155551234',
//       );

//       expect(result, isTrue);
//       expect(mockPlatform.call.activeCall, isNotNull);
//       expect(mockPlatform.call.activeCall!.to, equals('+14155551234'));
//       expect(mockPlatform.call.activeCall!.from, equals('test_user'));
//       expect(
//         mockPlatform.call.activeCall!.callDirection,
//         equals(CallDirection.outgoing),
//       );
//     });

//     test('answer() answers incoming call', () async {
//       final result = await VonageVoice.instance.call.answer();

//       expect(result, isTrue);
//       expect(
//         (mockPlatform.call as MockVonageCallPlatform).callAnswered,
//         isTrue,
//       );
//     });

//     test('hangUp() clears active call', () async {
//       // Place a call first
//       await VonageVoice.instance.call.place(from: 'user', to: '+14155551234');
//       expect(mockPlatform.call.activeCall, isNotNull);

//       // Hang up
//       await VonageVoice.instance.call.hangUp();
//       expect(mockPlatform.call.activeCall, isNull);
//     });

//     test('isOnCall() returns true when active call exists', () async {
//       await VonageVoice.instance.call.place(from: 'user', to: '+14155551234');

//       final result = await VonageVoice.instance.call.isOnCall();
//       expect(result, isTrue);
//     });

//     test('isOnCall() returns false when no active call', () async {
//       final result = await VonageVoice.instance.call.isOnCall();
//       expect(result, isFalse);
//     });

//     test('getSid() returns call ID', () async {
//       final sid = await VonageVoice.instance.call.getSid();
//       expect(sid, equals('mock_call_id_123'));
//     });

//     test('sendDigits() passes digit string correctly', () async {
//       await VonageVoice.instance.call.sendDigits('1234');

//       expect(
//         (mockPlatform.call as MockVonageCallPlatform).lastDigits,
//         equals('1234'),
//       );
//     });
//   });

//   // ── Mute ────────────────────────────────────────────────────────────────

//   group('Mute', () {
//     test('toggleMute(true) mutes the call', () async {
//       await VonageVoice.instance.call.toggleMute(true);

//       final muted = await VonageVoice.instance.call.isMuted();
//       expect(muted, isTrue);
//     });

//     test('toggleMute(false) unmutes the call', () async {
//       await VonageVoice.instance.call.toggleMute(true);
//       await VonageVoice.instance.call.toggleMute(false);

//       final muted = await VonageVoice.instance.call.isMuted();
//       expect(muted, isFalse);
//     });
//   });

//   // ── Hold ────────────────────────────────────────────────────────────────

//   group('Hold', () {
//     test('holdCall(true) puts call on hold', () async {
//       await VonageVoice.instance.call.holdCall(holdCall: true);

//       final holding = await VonageVoice.instance.call.isHolding();
//       expect(holding, isTrue);
//     });

//     test('holdCall(false) resumes call from hold', () async {
//       await VonageVoice.instance.call.holdCall(holdCall: true);
//       await VonageVoice.instance.call.holdCall(holdCall: false);

//       final holding = await VonageVoice.instance.call.isHolding();
//       expect(holding, isFalse);
//     });
//   });

//   // ── Speaker ─────────────────────────────────────────────────────────────

//   group('Speaker', () {
//     test('toggleSpeaker(true) enables speakerphone', () async {
//       await VonageVoice.instance.call.toggleSpeaker(true);

//       final onSpeaker = await VonageVoice.instance.call.isOnSpeaker();
//       expect(onSpeaker, isTrue);
//     });

//     test('toggleSpeaker(false) disables speakerphone', () async {
//       await VonageVoice.instance.call.toggleSpeaker(true);
//       await VonageVoice.instance.call.toggleSpeaker(false);

//       final onSpeaker = await VonageVoice.instance.call.isOnSpeaker();
//       expect(onSpeaker, isFalse);
//     });
//   });

//   // ── Bluetooth ───────────────────────────────────────────────────────────

//   group('Bluetooth', () {
//     test('toggleBluetooth(true) enables Bluetooth audio', () async {
//       await VonageVoice.instance.call.toggleBluetooth(bluetoothOn: true);

//       final btOn = await VonageVoice.instance.call.isBluetoothOn();
//       expect(btOn, isTrue);
//     });

//     test('toggleBluetooth(false) disables Bluetooth audio', () async {
//       await VonageVoice.instance.call.toggleBluetooth(bluetoothOn: true);
//       await VonageVoice.instance.call.toggleBluetooth(bluetoothOn: false);

//       final btOn = await VonageVoice.instance.call.isBluetoothOn();
//       expect(btOn, isFalse);
//     });
//   });

//   // ── Caller registry ─────────────────────────────────────────────────────

//   group('Caller registry', () {
//     test('registerClient() stores caller name', () async {
//       final result = await VonageVoice.instance.registerClient(
//         'user_123',
//         'Alice Johnson',
//       );

//       expect(result, isTrue);
//       expect(mockPlatform.lastRegisteredClientId, equals('user_123'));
//       expect(mockPlatform.lastRegisteredClientName, equals('Alice Johnson'));
//     });

//     test('unregisterClient() removes caller mapping', () async {
//       await VonageVoice.instance.registerClient('user_123', 'Alice');
//       final result = await VonageVoice.instance.unregisterClient('user_123');

//       expect(result, isTrue);
//       expect(mockPlatform.lastRegisteredClientId, isNull);
//     });

//     test('setDefaultCallerName() stores fallback name', () async {
//       final result = await VonageVoice.instance.setDefaultCallerName('Unknown');

//       expect(result, isTrue);
//       expect(mockPlatform.lastDefaultCallerName, equals('Unknown'));
//     });
//   });

//   // ── Permissions ─────────────────────────────────────────────────────────

//   group('Permissions', () {
//     test('hasMicAccess() returns true', () async {
//       final result = await VonageVoice.instance.hasMicAccess();
//       expect(result, isTrue);
//     });

//     test('hasCallPhonePermission() returns true', () async {
//       final result = await VonageVoice.instance.hasCallPhonePermission();
//       expect(result, isTrue);
//     });

//     test('hasManageOwnCallsPermission() returns true', () async {
//       final result = await VonageVoice.instance.hasManageOwnCallsPermission();
//       expect(result, isTrue);
//     });

//     test('hasReadPhoneStatePermission() returns true', () async {
//       final result = await VonageVoice.instance.hasReadPhoneStatePermission();
//       expect(result, isTrue);
//     });

//     test('requestMicAccess() returns true', () async {
//       final result = await VonageVoice.instance.requestMicAccess();
//       expect(result, isTrue);
//     });
//   });

//   // ── Telecom ─────────────────────────────────────────────────────────────

//   group('Telecom / PhoneAccount', () {
//     test('hasRegisteredPhoneAccount() returns true', () async {
//       final result = await VonageVoice.instance.hasRegisteredPhoneAccount();
//       expect(result, isTrue);
//     });

//     test('isPhoneAccountEnabled() returns true', () async {
//       final result = await VonageVoice.instance.isPhoneAccountEnabled();
//       expect(result, isTrue);
//     });

//     test('registerPhoneAccount() returns true', () async {
//       final result = await VonageVoice.instance.registerPhoneAccount();
//       expect(result, isNotNull);
//     });
//   });

//   // ── Reject on no permissions ─────────────────────────────────────────────

//   group('Reject on no permissions', () {
//     test('rejectCallOnNoPermissions(true) sets flag', () async {
//       await VonageVoice.instance.rejectCallOnNoPermissions(shouldReject: true);

//       final rejecting = await VonageVoice.instance
//           .isRejectingCallOnNoPermissions();
//       expect(rejecting, isTrue);
//     });

//     test('rejectCallOnNoPermissions(false) clears flag', () async {
//       await VonageVoice.instance.rejectCallOnNoPermissions(shouldReject: true);
//       await VonageVoice.instance.rejectCallOnNoPermissions(shouldReject: false);

//       final rejecting = await VonageVoice.instance
//           .isRejectingCallOnNoPermissions();
//       expect(rejecting, isFalse);
//     });
//   });

//   // ── Event parsing ────────────────────────────────────────────────────────

//   group('Event parsing', () {
//     test('parses Call Ended correctly', () {
//       final event = mockPlatform.parseCallEvent('Call Ended');
//       expect(event, equals(CallEvent.callEnded));
//     });

//     test('parses Mute correctly', () {
//       final event = mockPlatform.parseCallEvent('Mute');
//       expect(event, equals(CallEvent.mute));
//     });

//     test('parses Unmute correctly', () {
//       final event = mockPlatform.parseCallEvent('Unmute');
//       expect(event, equals(CallEvent.unmute));
//     });

//     test('parses Hold correctly', () {
//       final event = mockPlatform.parseCallEvent('Hold');
//       expect(event, equals(CallEvent.hold));
//     });

//     test('parses Unhold correctly', () {
//       final event = mockPlatform.parseCallEvent('Unhold');
//       expect(event, equals(CallEvent.unhold));
//     });

//     test('parses Speaker On correctly', () {
//       final event = mockPlatform.parseCallEvent('Speaker On');
//       expect(event, equals(CallEvent.speakerOn));
//     });

//     test('parses Speaker Off correctly', () {
//       final event = mockPlatform.parseCallEvent('Speaker Off');
//       expect(event, equals(CallEvent.speakerOff));
//     });

//     test('parses Bluetooth On correctly', () {
//       final event = mockPlatform.parseCallEvent('Bluetooth On');
//       expect(event, equals(CallEvent.bluetoothOn));
//     });

//     test('parses Bluetooth Off correctly', () {
//       final event = mockPlatform.parseCallEvent('Bluetooth Off');
//       expect(event, equals(CallEvent.bluetoothOff));
//     });

//     test('parses Missed Call correctly', () {
//       final event = mockPlatform.parseCallEvent('Missed Call');
//       expect(event, equals(CallEvent.missedCall));
//     });

//     test('unknown event returns log', () {
//       final event = mockPlatform.parseCallEvent('some_unknown_event');
//       expect(event, equals(CallEvent.log));
//     });
//   });

//   // ── ActiveCall model ─────────────────────────────────────────────────────

//   group('ActiveCall model', () {
//     test('strips client: prefix from from/to', () {
//       final call = ActiveCall(
//         from: 'client:alice',
//         to: 'client:bob',
//         callDirection: CallDirection.incoming,
//       );

//       expect(call.from, equals('alice'));
//       expect(call.to, equals('bob'));
//     });

//     test('formats 10-digit number correctly', () {
//       final call = ActiveCall(
//         from: '+14155551234',
//         to: '+14158765432',
//         callDirection: CallDirection.outgoing,
//       );

//       expect(call.fromFormatted, equals('(415) 555-1234'));
//       expect(call.toFormatted, equals('(415) 876-5432'));
//     });

//     test('formats 7-digit number correctly', () {
//       final call = ActiveCall(
//         from: '5551234',
//         to: '5557890',
//         callDirection: CallDirection.outgoing,
//       );

//       expect(call.fromFormatted, equals('555-1234'));
//     });

//     test('callDirection is set correctly', () {
//       final incoming = ActiveCall(
//         from: '+1234',
//         to: '+5678',
//         callDirection: CallDirection.incoming,
//       );
//       final outgoing = ActiveCall(
//         from: '+1234',
//         to: '+5678',
//         callDirection: CallDirection.outgoing,
//       );

//       expect(incoming.callDirection, equals(CallDirection.incoming));
//       expect(outgoing.callDirection, equals(CallDirection.outgoing));
//     });

//     test('initiated is null by default', () {
//       final call = ActiveCall(
//         from: '+1234',
//         to: '+5678',
//         callDirection: CallDirection.outgoing,
//       );

//       expect(call.initiated, isNull);
//     });

//     test('initiated is set when provided', () {
//       final now = DateTime.now();
//       final call = ActiveCall(
//         from: '+1234',
//         to: '+5678',
//         callDirection: CallDirection.outgoing,
//         initiated: now,
//       );

//       expect(call.initiated, equals(now));
//     });

//     test('customParams are stored correctly', () {
//       final call = ActiveCall(
//         from: '+1234',
//         to: '+5678',
//         callDirection: CallDirection.incoming,
//         customParams: {'key': 'value', 'name': 'Alice'},
//       );

//       expect(call.customParams, isNotNull);
//       expect(call.customParams!['key'], equals('value'));
//       expect(call.customParams!['name'], equals('Alice'));
//     });
//   });
// }
