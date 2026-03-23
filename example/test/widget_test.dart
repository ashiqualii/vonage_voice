// import 'dart:async';

// import 'package:flutter/material.dart';
// import 'package:flutter/src/services/platform_channel.dart';
// import 'package:flutter_test/flutter_test.dart';
// import 'package:vonage_voice/_internal/platform_interface/vonage_call_platform_interface.dart';
// import 'package:vonage_voice/vonage_voice.dart';
// import 'package:vonage_voice/_internal/platform_interface/vonage_voice_platform_interface.dart';
// import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// import 'package:vonage_voice_example/main.dart';

// // ── Mock platform for widget tests ────────────────────────────────────────

// class MockVonageVoicePlatform
//     with MockPlatformInterfaceMixin
//     implements VonageVoicePlatform {
//   bool loginCalled = false;
//   bool logoutCalled = false;

//   // Stream controller so we can push events during tests
//   final _eventController = StreamController<CallEvent>.broadcast();

//   /// Push a fake call event into the stream
//   void pushEvent(CallEvent event) => _eventController.add(event);

//   @override
//   Stream<CallEvent> get callEventsListener => _eventController.stream;

//   @override
//   Future<bool?> setTokens({
//     required String accessToken,
//     String? deviceToken,
//   }) async {
//     loginCalled = true;
//     return true;
//   }

//   @override
//   Future<bool?> unregister({String? accessToken}) async {
//     logoutCalled = true;
//     return true;
//   }

//   @override
//   Future<bool?> refreshSession({required String accessToken}) async => true;

//   @override
//   Future<bool?> requestMicAccess() async => true;

//   @override
//   Future<bool?> requestReadPhoneStatePermission() async => true;

//   @override
//   Future<bool?> requestCallPhonePermission() async => true;

//   @override
//   Future<bool?> requestManageOwnCallsPermission() async => true;

//   @override
//   Future<bool> hasMicAccess() async => true;

//   @override
//   Future<bool> hasReadPhoneStatePermission() async => true;

//   @override
//   Future<bool> hasCallPhonePermission() async => true;

//   @override
//   Future<bool> hasManageOwnCallsPermission() async => true;

//   @override
//   Future<bool> hasReadPhoneNumbersPermission() async => true;

//   @override
//   Future<bool?> requestReadPhoneNumbersPermission() async => true;

//   @override
//   Future<bool> hasBluetoothPermissions() async => false;

//   @override
//   Future<bool?> requestBluetoothPermissions() async => false;

//   @override
//   Future<bool> hasRegisteredPhoneAccount() async => true;

//   @override
//   Future<bool?> registerPhoneAccount() async => true;

//   @override
//   Future<bool> isPhoneAccountEnabled() async => true;

//   @override
//   Future<bool?> openPhoneAccountSettings() async => true;

//   @override
//   Future<bool> requiresBackgroundPermissions() async => false;

//   @override
//   Future<bool?> requestBackgroundPermissions() async => false;

//   @override
//   Future<bool?> showBackgroundCallUI() async => true;

//   @override
//   Future<bool?> updateCallKitIcon({String? icon}) async => true;

//   @override
//   Future<bool?> registerClient(String clientId, String clientName) async =>
//       true;

//   @override
//   Future<bool?> unregisterClient(String clientId) async => true;

//   @override
//   Future<bool?> setDefaultCallerName(String callerName) async => true;

//   @override
//   Future<bool> rejectCallOnNoPermissions({bool shouldReject = false}) async =>
//       true;

//   @override
//   Future<bool> isRejectingCallOnNoPermissions() async => false;

//   @override
//   set showMissedCallNotifications(bool value) {}

//   @override
//   OnDeviceTokenChanged? deviceTokenChanged;

//   @override
//   void setOnDeviceTokenChanged(OnDeviceTokenChanged deviceTokenChanged) {
//     this.deviceTokenChanged = deviceTokenChanged;
//   }

//   @override
//   VonageCallPlatform get call => _mockCall;
//   final _mockCall = _MockCallPlatform();

//   @override
//   CallEvent parseCallEvent(String state) => CallEvent.log;

//   @override
//   //  implement callEventsController
//   StreamController<String> get callEventsController =>
//       throw UnimplementedError();

//   @override
//   //  implement callEventsStream
//   Stream<String> get callEventsStream => throw UnimplementedError();

//   @override
//   //  implement eventChannel
//   EventChannel get eventChannel => throw UnimplementedError();

//   @override
//   void logLocalEvent(
//     String description, {
//     String prefix = "LOG",
//     String separator = "|",
//   }) {
//     //  implement logLocalEvent
//   }

//   @override
//   void logLocalEventEntries(
//     List<String> entries, {
//     String prefix = "LOG",
//     String separator = "|",
//   }) {
//     //  implement logLocalEventEntries
//   }

//   @override
//   //  implement sharedChannel
//   MethodChannel get sharedChannel => throw UnimplementedError();
// }

// class _MockCallPlatform implements VonageCallPlatform {
//   ActiveCall? _activeCall;

//   @override
//   ActiveCall? get activeCall => _activeCall;

//   @override
//   set activeCall(ActiveCall? v) => _activeCall = v;

//   @override
//   Future<bool?> place({
//     required String from,
//     required String to,
//     Map<String, dynamic>? extraOptions,
//   }) async {
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
//   Future<bool?> hangUp() async {
//     _activeCall = null;
//     return true;
//   }

//   @override
//   Future<bool> isOnCall() async => _activeCall != null;

//   @override
//   Future<String?> getSid() async => 'widget_test_call_id';

//   @override
//   Future<bool?> answer() async => true;

//   @override
//   Future<bool?> holdCall({bool holdCall = true}) async => true;

//   @override
//   Future<bool?> isHolding() async => false;

//   @override
//   Future<bool?> toggleMute(bool isMuted) async => true;

//   @override
//   Future<bool?> isMuted() async => false;

//   @override
//   Future<bool?> toggleSpeaker(bool speakerIsOn) async => true;

//   @override
//   Future<bool?> isOnSpeaker() async => false;

//   @override
//   Future<bool?> toggleBluetooth({bool bluetoothOn = true}) async => true;

//   @override
//   Future<bool?> isBluetoothOn() async => false;

//   @override
//   Future<bool?> sendDigits(String digits) async => true;

//   @override
//   //  implement callEventsController
//   StreamController<String> get callEventsController =>
//       throw UnimplementedError();

//   @override
//   //  implement callEventsStream
//   Stream<String> get callEventsStream => throw UnimplementedError();

//   @override
//   //  implement eventChannel
//   EventChannel get eventChannel => throw UnimplementedError();

//   @override
//   void logLocalEvent(
//     String description, {
//     String prefix = "LOG",
//     String separator = "|",
//   }) {
//     //  implement logLocalEvent
//   }

//   @override
//   void logLocalEventEntries(
//     List<String> entries, {
//     String prefix = "LOG",
//     String separator = "|",
//   }) {
//     //  implement logLocalEventEntries
//   }

//   @override
//   //  implement sharedChannel
//   MethodChannel get sharedChannel => throw UnimplementedError();
// }

// // ── Test setup helper ─────────────────────────────────────────────────────

// late MockVonageVoicePlatform mockPlatform;

// void setupMock() {
//   mockPlatform = MockVonageVoicePlatform();
//   VonageVoicePlatform.instance = mockPlatform;
// }

// // ══════════════════════════════════════════════════════════════════════════
// // WIDGET TESTS
// // ══════════════════════════════════════════════════════════════════════════

// void main() {
//   setUp(setupMock);

//   // ── LoginScreen ──────────────────────────────────────────────────────────

//   group('LoginScreen', () {
//     testWidgets('renders login button', (tester) async {
//       await tester.pumpWidget(const VonageExampleApp());

//       expect(find.text('Login'), findsOneWidget);
//       expect(find.text('Not logged in'), findsOneWidget);
//     });

//     testWidgets('shows loading indicator while logging in', (tester) async {
//       await tester.pumpWidget(const VonageExampleApp());

//       await tester.tap(find.text('Login'));
//       await tester.pump();

//       expect(find.byType(CircularProgressIndicator), findsOneWidget);
//     });

//     testWidgets('navigates to DialerScreen after successful login', (
//       tester,
//     ) async {
//       await tester.pumpWidget(const VonageExampleApp());

//       await tester.tap(find.text('Login'));
//       await tester.pumpAndSettle();

//       // Should be on dialer screen now
//       expect(find.text('Vonage Voice — Dialer'), findsOneWidget);
//       expect(mockPlatform.loginCalled, isTrue);
//     });
//   });

//   // ── DialerScreen ──────────────────────────────────────────────────────────

//   group('DialerScreen', () {
//     /// Helper: navigate past login to dialer
//     Future<void> navigateToDialer(WidgetTester tester) async {
//       await tester.pumpWidget(const VonageExampleApp());
//       await tester.tap(find.text('Login'));
//       await tester.pumpAndSettle();
//     }

//     testWidgets('renders phone number text field', (tester) async {
//       await navigateToDialer(tester);

//       expect(find.byType(TextField), findsOneWidget);
//     });

//     testWidgets('renders dialpad with all digits', (tester) async {
//       await navigateToDialer(tester);

//       for (final digit in [
//         '1',
//         '2',
//         '3',
//         '4',
//         '5',
//         '6',
//         '7',
//         '8',
//         '9',
//         '0',
//         '*',
//         '#',
//       ]) {
//         expect(find.text(digit), findsOneWidget);
//       }
//     });

//     testWidgets('tapping dialpad digit appends to text field', (tester) async {
//       await navigateToDialer(tester);

//       await tester.tap(find.text('4'));
//       await tester.pump();
//       await tester.tap(find.text('2'));
//       await tester.pump();

//       expect(find.text('42'), findsOneWidget);
//     });

//     testWidgets('renders Call button', (tester) async {
//       await navigateToDialer(tester);

//       expect(find.text('Call'), findsOneWidget);
//     });

//     testWidgets('shows error when Call tapped with empty number', (
//       tester,
//     ) async {
//       await navigateToDialer(tester);

//       await tester.tap(find.text('Call'));
//       await tester.pump();

//       expect(find.text('Enter a phone number'), findsOneWidget);
//     });

//     testWidgets('navigates to ActiveCallScreen after placing call', (
//       tester,
//     ) async {
//       await navigateToDialer(tester);

//       // Enter a number
//       await tester.enterText(find.byType(TextField), '+14155551234');
//       await tester.pump();

//       // Tap call
//       await tester.tap(find.text('Call'));
//       await tester.pumpAndSettle();

//       // Should be on active call screen
//       expect(find.byType(ActiveCallScreen), findsOneWidget);
//     });

//     testWidgets('logout button navigates back to login', (tester) async {
//       await navigateToDialer(tester);

//       await tester.tap(find.text('Logout'));
//       await tester.pumpAndSettle();

//       expect(find.text('Login'), findsOneWidget);
//       expect(mockPlatform.logoutCalled, isTrue);
//     });

//     testWidgets('incoming call event opens IncomingCallScreen', (tester) async {
//       await navigateToDialer(tester);

//       // Simulate incoming call — set activeCall then push event
//       mockPlatform.call.activeCall = ActiveCall(
//         from: '+14155559999',
//         to: 'me',
//         callDirection: CallDirection.incoming,
//       );
//       mockPlatform.pushEvent(CallEvent.incoming);
//       await tester.pumpAndSettle();

//       expect(find.byType(IncomingCallScreen), findsOneWidget);
//     });
//   });

//   // ── IncomingCallScreen ────────────────────────────────────────────────────

//   group('IncomingCallScreen', () {
//     final testCall = ActiveCall(
//       from: '+14155559999',
//       to: 'me',
//       callDirection: CallDirection.incoming,
//     );

//     testWidgets('renders caller number', (tester) async {
//       await tester.pumpWidget(
//         MaterialApp(home: IncomingCallScreen(activeCall: testCall)),
//       );

//       expect(find.text('(415) 555-9999'), findsOneWidget);
//     });

//     testWidgets('renders Incoming Call label', (tester) async {
//       await tester.pumpWidget(
//         MaterialApp(home: IncomingCallScreen(activeCall: testCall)),
//       );

//       expect(find.text('Incoming Call'), findsOneWidget);
//     });

//     testWidgets('renders Answer and Decline buttons', (tester) async {
//       await tester.pumpWidget(
//         MaterialApp(home: IncomingCallScreen(activeCall: testCall)),
//       );

//       expect(find.text('Answer'), findsOneWidget);
//       expect(find.text('Decline'), findsOneWidget);
//     });

//     testWidgets('tapping Decline pops screen', (tester) async {
//       await tester.pumpWidget(
//         MaterialApp(home: IncomingCallScreen(activeCall: testCall)),
//       );

//       await tester.tap(find.text('Decline'));
//       await tester.pumpAndSettle();

//       // Screen is popped — no longer visible
//       expect(find.byType(IncomingCallScreen), findsNothing);
//     });
//   });

//   // ── ActiveCallScreen ──────────────────────────────────────────────────────

//   group('ActiveCallScreen', () {
//     final testCall = ActiveCall(
//       from: '+14155551234',
//       to: 'me',
//       callDirection: CallDirection.outgoing,
//       initiated: DateTime.now(),
//     );

//     testWidgets('renders caller number and Connected status', (tester) async {
//       await tester.pumpWidget(
//         MaterialApp(home: ActiveCallScreen(activeCall: testCall)),
//       );

//       expect(find.text('Connected'), findsOneWidget);
//       expect(find.text('(415) 555-1234'), findsOneWidget);
//     });

//     testWidgets('renders Mute button', (tester) async {
//       await tester.pumpWidget(
//         MaterialApp(home: ActiveCallScreen(activeCall: testCall)),
//       );

//       expect(find.text('Mute'), findsOneWidget);
//     });

//     testWidgets('renders Speaker button', (tester) async {
//       await tester.pumpWidget(
//         MaterialApp(home: ActiveCallScreen(activeCall: testCall)),
//       );

//       expect(find.text('Speaker'), findsOneWidget);
//     });

//     testWidgets('renders Hold button', (tester) async {
//       await tester.pumpWidget(
//         MaterialApp(home: ActiveCallScreen(activeCall: testCall)),
//       );

//       expect(find.text('Hold'), findsOneWidget);
//     });

//     testWidgets('renders Bluetooth button', (tester) async {
//       await tester.pumpWidget(
//         MaterialApp(home: ActiveCallScreen(activeCall: testCall)),
//       );

//       expect(find.text('Bluetooth'), findsOneWidget);
//     });

//     testWidgets('renders Keypad button', (tester) async {
//       await tester.pumpWidget(
//         MaterialApp(home: ActiveCallScreen(activeCall: testCall)),
//       );

//       expect(find.text('Keypad'), findsOneWidget);
//     });

//     testWidgets('tapping Keypad shows dialpad', (tester) async {
//       await tester.pumpWidget(
//         MaterialApp(home: ActiveCallScreen(activeCall: testCall)),
//       );

//       await tester.tap(find.text('Keypad'));
//       await tester.pump();

//       // Dialpad digits should now be visible
//       expect(find.text('1'), findsOneWidget);
//       expect(find.text('0'), findsOneWidget);
//     });

//     testWidgets('tapping Mute toggles to Unmute label', (tester) async {
//       await tester.pumpWidget(
//         MaterialApp(home: ActiveCallScreen(activeCall: testCall)),
//       );

//       await tester.tap(find.text('Mute'));
//       await tester.pump();

//       expect(find.text('Unmute'), findsOneWidget);
//     });

//     testWidgets('tapping Hold toggles to Resume label', (tester) async {
//       await tester.pumpWidget(
//         MaterialApp(home: ActiveCallScreen(activeCall: testCall)),
//       );

//       await tester.tap(find.text('Hold'));
//       await tester.pump();

//       expect(find.text('Resume'), findsOneWidget);
//     });

//     testWidgets('call ended event updates status and pops', (tester) async {
//       await tester.pumpWidget(
//         MaterialApp(home: ActiveCallScreen(activeCall: testCall)),
//       );

//       // Push call ended event
//       mockPlatform.pushEvent(CallEvent.callEnded);
//       await tester.pump();

//       expect(find.text('Call ended'), findsOneWidget);
//     });

//     testWidgets('reconnecting event updates status', (tester) async {
//       await tester.pumpWidget(
//         MaterialApp(home: ActiveCallScreen(activeCall: testCall)),
//       );

//       mockPlatform.pushEvent(CallEvent.reconnecting);
//       await tester.pump();

//       expect(find.text('Reconnecting...'), findsOneWidget);
//     });

//     testWidgets('reconnected event resets status to Connected', (tester) async {
//       await tester.pumpWidget(
//         MaterialApp(home: ActiveCallScreen(activeCall: testCall)),
//       );

//       mockPlatform.pushEvent(CallEvent.reconnecting);
//       await tester.pump();
//       mockPlatform.pushEvent(CallEvent.reconnected);
//       await tester.pump();

//       expect(find.text('Connected'), findsOneWidget);
//     });
//   });
// }
