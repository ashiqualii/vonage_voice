// import 'package:flutter_test/flutter_test.dart';
// import 'package:integration_test/integration_test.dart';
// import 'package:vonage_voice/vonage_voice.dart';

// // ── Test JWT — replace with a valid short-lived JWT for real device runs ──
// // Generate via: https://developer.vonage.com/en/vonage-client-sdk/create-your-application
// const String kTestJwt = 'YOUR_VONAGE_TEST_JWT_HERE';

// // ══════════════════════════════════════════════════════════════════════════
// // INTEGRATION TESTS
// //
// // These tests run on a real Android device or emulator.
// // They test the full native ↔ Flutter channel round trip.
// //
// // Run with:
// //   flutter test integration_test/plugin_integration_test.dart
// //   --device-id=<your_device_id>
// //
// // NOTE: Requires a valid Vonage JWT in kTestJwt above.
// //       Call-related tests require a second device or Vonage test number.
// // ══════════════════════════════════════════════════════════════════════════

// void main() {
//   IntegrationTestWidgetsFlutterBinding.ensureInitialized();

//   // ── Permission checks ───────────────────────────────────────────────────

//   group('Permissions', () {
//     testWidgets('hasMicAccess returns a bool', (tester) async {
//       final result = await VonageVoice.instance.hasMicAccess();
//       expect(result, isA<bool>());
//     });

//     testWidgets('hasCallPhonePermission returns a bool', (tester) async {
//       final result = await VonageVoice.instance.hasCallPhonePermission();
//       expect(result, isA<bool>());
//     });

//     testWidgets('hasReadPhoneStatePermission returns a bool', (tester) async {
//       final result = await VonageVoice.instance.hasReadPhoneStatePermission();
//       expect(result, isA<bool>());
//     });

//     testWidgets('hasManageOwnCallsPermission returns a bool', (tester) async {
//       final result = await VonageVoice.instance.hasManageOwnCallsPermission();
//       expect(result, isA<bool>());
//     });

//     testWidgets('hasReadPhoneNumbersPermission returns a bool', (tester) async {
//       final result = await VonageVoice.instance.hasReadPhoneNumbersPermission();
//       expect(result, isA<bool>());
//     });

//     testWidgets('hasBluetoothPermissions returns false (deprecated)', (
//       tester,
//     ) async {
//       final result = await VonageVoice.instance.hasBluetoothPermissions();
//       // Deprecated — always returns false
//       expect(result, isFalse);
//     });
//   });

//   // ── Telecom / PhoneAccount ───────────────────────────────────────────────

//   group('Telecom', () {
//     testWidgets('hasRegisteredPhoneAccount returns a bool', (tester) async {
//       final result = await VonageVoice.instance.hasRegisteredPhoneAccount();
//       expect(result, isA<bool>());
//     });

//     testWidgets('isPhoneAccountEnabled returns a bool', (tester) async {
//       final result = await VonageVoice.instance.isPhoneAccountEnabled();
//       expect(result, isA<bool>());
//     });

//     testWidgets('registerPhoneAccount returns non-null', (tester) async {
//       final result = await VonageVoice.instance.registerPhoneAccount();
//       expect(result, isNotNull);
//     });
//   });

//   // ── Reject on no permissions ─────────────────────────────────────────────

//   group('Reject on no permissions', () {
//     testWidgets('can set and read rejectCallOnNoPermissions', (tester) async {
//       await VonageVoice.instance.rejectCallOnNoPermissions(shouldReject: true);
//       final result = await VonageVoice.instance
//           .isRejectingCallOnNoPermissions();
//       expect(result, isA<bool>());

//       // Reset to false
//       await VonageVoice.instance.rejectCallOnNoPermissions(shouldReject: false);
//     });
//   });

//   // ── Session management ───────────────────────────────────────────────────
//   // NOTE: Requires a valid JWT in kTestJwt

//   group('Session', () {
//     testWidgets('setTokens() returns true with valid JWT', (tester) async {
//       if (kTestJwt == 'YOUR_VONAGE_TEST_JWT_HERE') {
//         // Skip if no JWT provided
//         return;
//       }

//       final result = await VonageVoice.instance.setTokens(
//         accessToken: kTestJwt,
//       );
//       expect(result, isTrue);
//     });

//     testWidgets('unregister() returns true after session created', (
//       tester,
//     ) async {
//       if (kTestJwt == 'YOUR_VONAGE_TEST_JWT_HERE') return;

//       await VonageVoice.instance.setTokens(accessToken: kTestJwt);
//       final result = await VonageVoice.instance.unregister();
//       expect(result, isTrue);
//     });
//   });

//   // ── Caller registry ──────────────────────────────────────────────────────

//   group('Caller registry', () {
//     testWidgets('registerClient returns true', (tester) async {
//       final result = await VonageVoice.instance.registerClient(
//         'integration_test_user',
//         'Integration Test User',
//       );
//       expect(result, isTrue);
//     });

//     testWidgets('unregisterClient returns true', (tester) async {
//       await VonageVoice.instance.registerClient(
//         'integration_test_user',
//         'Integration Test User',
//       );
//       final result = await VonageVoice.instance.unregisterClient(
//         'integration_test_user',
//       );
//       expect(result, isTrue);
//     });

//     testWidgets('setDefaultCallerName returns true', (tester) async {
//       final result = await VonageVoice.instance.setDefaultCallerName(
//         'Test Caller',
//       );
//       expect(result, isTrue);
//     });
//   });

//   // ── Event stream ─────────────────────────────────────────────────────────

//   group('Event stream', () {
//     testWidgets('callEventsListener is a broadcast stream', (tester) async {
//       final stream = VonageVoice.instance.callEventsListener;

//       // Verify it is a broadcast stream — multiple listeners allowed
//       expect(stream.isBroadcast, isTrue);
//     });

//     testWidgets('callEventsListener can have multiple listeners', (
//       tester,
//     ) async {
//       final stream = VonageVoice.instance.callEventsListener;

//       // Should not throw — broadcast streams support multiple listeners
//       final sub1 = stream.listen((_) {});
//       final sub2 = stream.listen((_) {});

//       await sub1.cancel();
//       await sub2.cancel();
//     });
//   });

//   // ── Active call state ────────────────────────────────────────────────────

//   group('Active call state', () {
//     testWidgets('activeCall is null before any call is placed', (tester) async {
//       expect(VonageVoice.instance.call.activeCall, isNull);
//     });

//     testWidgets('isOnCall returns false when no call active', (tester) async {
//       final result = await VonageVoice.instance.call.isOnCall();
//       expect(result, isFalse);
//     });

//     testWidgets('getSid returns null when no call active', (tester) async {
//       final sid = await VonageVoice.instance.call.getSid();
//       // May be null or empty string — not a hard call SID until ringing
//       expect(sid, anyOf(isNull, isEmpty));
//     });
//   });

//   // ── Deprecated stubs ─────────────────────────────────────────────────────

//   group('Deprecated stubs', () {
//     testWidgets('showBackgroundCallUI returns true (no-op)', (tester) async {
//       final result = await VonageVoice.instance.showBackgroundCallUI();
//       expect(result, isTrue);
//     });

//     testWidgets('updateCallKitIcon returns non-null (no-op on Android)', (
//       tester,
//     ) async {
//       final result = await VonageVoice.instance.updateCallKitIcon(
//         icon: 'TestIcon',
//       );
//       expect(result, isNotNull);
//     });
//   });
// }
