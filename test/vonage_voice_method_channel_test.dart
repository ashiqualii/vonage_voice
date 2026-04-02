import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vonage_voice/vonage_voice.dart';
import 'package:vonage_voice/_internal/method_channel/vonage_voice_method_channel.dart';
import 'package:vonage_voice/_internal/method_channel/vonage_call_method_channel.dart';

// ── Fake MethodChannel handler ────────────────────────────────────────────

/// Intercepts all MethodChannel calls and returns controlled responses
/// without hitting any native Android code.
class FakeMethodChannelHandler {
  final Map<String, dynamic> _responses = {};
  final List<MethodCall> _callLog = [];

  /// Register a fake response for a method name.
  void setResponse(String method, dynamic response) {
    _responses[method] = response;
  }

  /// Returns all recorded method calls for assertions.
  List<MethodCall> get callLog => List.unmodifiable(_callLog);

  /// Returns the last recorded call for a given method name.
  MethodCall? lastCallFor(String method) {
    return _callLog.lastWhere(
      (c) => c.method == method,
      orElse: () => MethodCall(method),
    );
  }

  /// Installs this handler on the test binding.
  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('vonage_voice/messages'),
          (MethodCall call) async {
            _callLog.add(call);
            if (_responses.containsKey(call.method)) {
              return _responses[call.method];
            }
            return true;
          },
        );
  }

  /// Removes this handler — call in tearDown.
  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('vonage_voice/messages'),
          null,
        );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// TESTS
// ══════════════════════════════════════════════════════════════════════════

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeMethodChannelHandler handler;
  late MethodChannelVonageVoice voice;
  late MethodChannelVonageCall call;

  setUp(() {
    handler = FakeMethodChannelHandler();
    handler.install();
    voice = MethodChannelVonageVoice();
    call = MethodChannelVonageCall();
  });

  tearDown(() {
    handler.uninstall();
  });

  // ── setTokens ───────────────────────────────────────────────────────────

  group('setTokens()', () {
    test('invokes tokens method with jwt key', () async {
      handler.setResponse('tokens', true);

      await voice.setTokens(
        accessToken:
            'eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9.eyJpYXQiOjE3NzM3MzY5MTMsImV4cCI6MTc3Mzc0NDExMywianRpIjoiN2JlZTRhNTQtNmJkMi00NGIxLWE0ZmQtODkzYjM5ZjM2ZGEyIiwiYXBwbGljYXRpb25faWQiOiJjOTIzMTEzZi03M2M3LTQwMjItYWNiOC03ZDQ3YTdiOWZiNjEiLCJhY2wiOnsicGF0aHMiOnsiLyovdXNlcnMvKioiOnt9LCIvKi9jb252ZXJzYXRpb25zLyoqIjp7fSwiLyovc2Vzc2lvbnMvKioiOnt9LCIvKi9kZXZpY2VzLyoqIjp7fSwiLyovaW1hZ2UvKioiOnt9LCIvKi9tZWRpYS8qKiI6e30sIi8qL2FwcGxpY2F0aW9ucy8qKiI6e30sIi8qL3B1c2gvKioiOnt9LCIvKi9rbm9ja2luZy8qKiI6e30sIi8qL2xlZ3MvKioiOnt9LCIvdjEvZmlsZXMvKioiOnt9fX0sInN1YiI6Imhhcmlpb19lMTc3MDI4NzU5NSJ9.iN65Wj9hRG1a_idd5YtHanI10lMkuQXmV3EfUHEDp2FmjZKoFQdo7PLFLCqlDQbUuDtV15vTjIcT6lwdjJBEcUq4DH1vupfAIl7JjTvi3O8Vaj8JTcTgyb-N4mNWxJQx2XDGr2NNXN6GT7PA4TAyboCaUZl_VSDz5u0HsMOsjpLXzSY-aysDYit5zE9vN8s1AdgKvxiDJY_g8pQTOOs7DWL0nTE1EPqGBsFL_FMSB4DMnEOtgoi7Ao6vu1Jr6hjWRE71QBem7EpYGvE8uXKPuhZ-evXG6HQijBOMBXq2gyxcaCbSnK2kCmlWC7072mzycFkkgnDaZnpbwtJ4p_6y0g',
      );

      final recorded = handler.lastCallFor('tokens');
      expect(recorded, isNotNull);
      expect(recorded!.method, equals('tokens'));
      expect(
        recorded.arguments['jwt'],
        equals(
          'eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9.eyJpYXQiOjE3NzM3MzY5MTMsImV4cCI6MTc3Mzc0NDExMywianRpIjoiN2JlZTRhNTQtNmJkMi00NGIxLWE0ZmQtODkzYjM5ZjM2ZGEyIiwiYXBwbGljYXRpb25faWQiOiJjOTIzMTEzZi03M2M3LTQwMjItYWNiOC03ZDQ3YTdiOWZiNjEiLCJhY2wiOnsicGF0aHMiOnsiLyovdXNlcnMvKioiOnt9LCIvKi9jb252ZXJzYXRpb25zLyoqIjp7fSwiLyovc2Vzc2lvbnMvKioiOnt9LCIvKi9kZXZpY2VzLyoqIjp7fSwiLyovaW1hZ2UvKioiOnt9LCIvKi9tZWRpYS8qKiI6e30sIi8qL2FwcGxpY2F0aW9ucy8qKiI6e30sIi8qL3B1c2gvKioiOnt9LCIvKi9rbm9ja2luZy8qKiI6e30sIi8qL2xlZ3MvKioiOnt9LCIvdjEvZmlsZXMvKioiOnt9fX0sInN1YiI6Imhhcmlpb19lMTc3MDI4NzU5NSJ9.iN65Wj9hRG1a_idd5YtHanI10lMkuQXmV3EfUHEDp2FmjZKoFQdo7PLFLCqlDQbUuDtV15vTjIcT6lwdjJBEcUq4DH1vupfAIl7JjTvi3O8Vaj8JTcTgyb-N4mNWxJQx2XDGr2NNXN6GT7PA4TAyboCaUZl_VSDz5u0HsMOsjpLXzSY-aysDYit5zE9vN8s1AdgKvxiDJY_g8pQTOOs7DWL0nTE1EPqGBsFL_FMSB4DMnEOtgoi7Ao6vu1Jr6hjWRE71QBem7EpYGvE8uXKPuhZ-evXG6HQijBOMBXq2gyxcaCbSnK2kCmlWC7072mzycFkkgnDaZnpbwtJ4p_6y0g',
        ),
      );
    });

    test('passes deviceToken when provided', () async {
      handler.setResponse('tokens', true);

      await voice.setTokens(
        accessToken: 'jwt_123',
        deviceToken: 'fcm_token_xyz',
      );

      final recorded = handler.lastCallFor('tokens');
      expect(recorded!.arguments['deviceToken'], equals('fcm_token_xyz'));
    });

    test('deviceToken is null when not provided', () async {
      handler.setResponse('tokens', true);

      await voice.setTokens(accessToken: 'jwt_123');

      final recorded = handler.lastCallFor('tokens');
      expect(recorded!.arguments['deviceToken'], isNull);
    });

    test('passes isSandbox=true when specified', () async {
      handler.setResponse('tokens', true);

      await voice.setTokens(accessToken: 'jwt_123', isSandbox: true);

      final recorded = handler.lastCallFor('tokens');
      expect(recorded!.arguments['isSandbox'], isTrue);
    });

    test('isSandbox defaults to false', () async {
      handler.setResponse('tokens', true);

      await voice.setTokens(accessToken: 'jwt_123');

      final recorded = handler.lastCallFor('tokens');
      expect(recorded!.arguments['isSandbox'], isFalse);
    });
  });

  // ── unregister ──────────────────────────────────────────────────────────

  group('unregister()', () {
    test('invokes unregister method', () async {
      handler.setResponse('unregister', true);

      await voice.unregister();

      final recorded = handler.lastCallFor('unregister');
      expect(recorded, isNotNull);
      expect(recorded!.method, equals('unregister'));
    });
  });

  // ── refreshSession ──────────────────────────────────────────────────────

  group('refreshSession()', () {
    test('invokes refreshSession with new jwt', () async {
      handler.setResponse('refreshSession', true);

      await voice.refreshSession(accessToken: 'new_jwt_456');

      final recorded = handler.lastCallFor('refreshSession');
      expect(recorded!.arguments['jwt'], equals('new_jwt_456'));
    });
  });

  // ── makeCall ────────────────────────────────────────────────────────────

  group('place()', () {
    test('invokes makeCall with from and to', () async {
      handler.setResponse('makeCall', true);

      await call.place(from: 'test_user', to: '+14155551234');

      final recorded = handler.lastCallFor('makeCall');
      expect(recorded, isNotNull);
      expect(recorded!.arguments['from'], equals('test_user'));
      expect(recorded.arguments['to'], equals('+14155551234'));
    });

    test('sets activeCall immediately on place()', () async {
      handler.setResponse('makeCall', true);

      await call.place(from: 'me', to: '+14155551234');

      expect(call.activeCall, isNotNull);
      expect(call.activeCall!.to, equals('+14155551234'));
      expect(call.activeCall!.callDirection, equals(CallDirection.outgoing));
    });

    test('merges extraOptions into call payload', () async {
      handler.setResponse('makeCall', true);

      await call.place(
        from: 'me',
        to: '+14155551234',
        extraOptions: {'customKey': 'customValue'},
      );

      final recorded = handler.lastCallFor('makeCall');
      expect(recorded!.arguments['customKey'], equals('customValue'));
    });
  });

  // ── hangUp ──────────────────────────────────────────────────────────────

  group('hangUp()', () {
    test('invokes hangUp method', () async {
      handler.setResponse('hangUp', true);

      await call.hangUp();

      final recorded = handler.lastCallFor('hangUp');
      expect(recorded, isNotNull);
      expect(recorded!.method, equals('hangUp'));
    });
  });

  // ── answer ──────────────────────────────────────────────────────────────

  group('answer()', () {
    test('invokes answer method', () async {
      handler.setResponse('answer', true);

      await call.answer();

      final recorded = handler.lastCallFor('answer');
      expect(recorded, isNotNull);
    });
  });

  // ── isOnCall ────────────────────────────────────────────────────────────

  group('isOnCall()', () {
    test('returns true when native returns true', () async {
      handler.setResponse('isOnCall', true);

      final result = await call.isOnCall();
      expect(result, isTrue);
    });

    test('returns false when native returns false', () async {
      handler.setResponse('isOnCall', false);

      final result = await call.isOnCall();
      expect(result, isFalse);
    });

    test('defaults to false when native returns null', () async {
      handler.setResponse('isOnCall', null);

      final result = await call.isOnCall();
      expect(result, isFalse);
    });
  });

  // ── getSid ──────────────────────────────────────────────────────────────

  group('getSid()', () {
    test('returns call ID from native', () async {
      handler.setResponse('call-sid', 'call_abc_123');

      final sid = await call.getSid();
      expect(sid, equals('call_abc_123'));
    });

    test('returns null when no active call', () async {
      handler.setResponse('call-sid', null);

      final sid = await call.getSid();
      expect(sid, isNull);
    });
  });

  // ── toggleMute ──────────────────────────────────────────────────────────

  group('toggleMute()', () {
    test('invokes toggleMute with muted=true', () async {
      handler.setResponse('toggleMute', true);

      await call.toggleMute(true);

      final recorded = handler.lastCallFor('toggleMute');
      expect(recorded!.arguments['muted'], isTrue);
    });

    test('invokes toggleMute with muted=false', () async {
      handler.setResponse('toggleMute', true);

      await call.toggleMute(false);

      final recorded = handler.lastCallFor('toggleMute');
      expect(recorded!.arguments['muted'], isFalse);
    });
  });

  // ── toggleSpeaker ────────────────────────────────────────────────────────

  group('toggleSpeaker()', () {
    test('invokes toggleSpeaker with speakerIsOn=true', () async {
      handler.setResponse('toggleSpeaker', true);

      await call.toggleSpeaker(true);

      final recorded = handler.lastCallFor('toggleSpeaker');
      expect(recorded!.arguments['speakerIsOn'], isTrue);
    });

    test('invokes toggleSpeaker with speakerIsOn=false', () async {
      handler.setResponse('toggleSpeaker', true);

      await call.toggleSpeaker(false);

      final recorded = handler.lastCallFor('toggleSpeaker');
      expect(recorded!.arguments['speakerIsOn'], isFalse);
    });
  });

  // ── toggleBluetooth ──────────────────────────────────────────────────────

  group('toggleBluetooth()', () {
    test('invokes toggleBluetooth with bluetoothOn=true', () async {
      handler.setResponse('toggleBluetooth', true);

      await call.toggleBluetooth(bluetoothOn: true);

      final recorded = handler.lastCallFor('toggleBluetooth');
      expect(recorded!.arguments['bluetoothOn'], isTrue);
    });

    test('invokes toggleBluetooth with bluetoothOn=false', () async {
      handler.setResponse('toggleBluetooth', true);

      await call.toggleBluetooth(bluetoothOn: false);

      final recorded = handler.lastCallFor('toggleBluetooth');
      expect(recorded!.arguments['bluetoothOn'], isFalse);
    });
  });

  // ── sendDigits ───────────────────────────────────────────────────────────

  group('sendDigits()', () {
    test('invokes sendDigits with correct digits', () async {
      handler.setResponse('sendDigits', true);

      await call.sendDigits('1234');

      final recorded = handler.lastCallFor('sendDigits');
      expect(recorded!.arguments['digits'], equals('1234'));
    });

    test('handles special DTMF characters', () async {
      handler.setResponse('sendDigits', true);

      await call.sendDigits('*#');

      final recorded = handler.lastCallFor('sendDigits');
      expect(recorded!.arguments['digits'], equals('*#'));
    });
  });

  // ── registerClient ───────────────────────────────────────────────────────

  group('registerClient()', () {
    test('invokes registerClient with id and name', () async {
      handler.setResponse('registerClient', true);

      await voice.registerClient('user_123', 'Alice Johnson');

      final recorded = handler.lastCallFor('registerClient');
      expect(recorded!.arguments['id'], equals('user_123'));
      expect(recorded.arguments['name'], equals('Alice Johnson'));
    });
  });

  // ── unregisterClient ─────────────────────────────────────────────────────

  group('unregisterClient()', () {
    test('invokes unregisterClient with id', () async {
      handler.setResponse('unregisterClient', true);

      await voice.unregisterClient('user_123');

      final recorded = handler.lastCallFor('unregisterClient');
      expect(recorded!.arguments['id'], equals('user_123'));
    });
  });

  // ── setDefaultCallerName ─────────────────────────────────────────────────

  group('setDefaultCallerName()', () {
    test('invokes defaultCaller method', () async {
      handler.setResponse('defaultCaller', true);

      await voice.setDefaultCallerName('Unknown Caller');

      final recorded = handler.lastCallFor('defaultCaller');
      expect(recorded!.arguments['defaultCaller'], equals('Unknown Caller'));
    });
  });

  // ── processVonagePush ────────────────────────────────────────────────────

  group('processVonagePush()', () {
    test('invokes processVonagePush with data map', () async {
      handler.setResponse('processVonagePush', 'call_id_abc');

      final result = await voice.processVonagePush({
        'nexmo': 'data',
        'channel': 'phone',
      });

      expect(result, equals('call_id_abc'));
      final recorded = handler.lastCallFor('processVonagePush');
      expect(recorded, isNotNull);
      expect(recorded!.arguments['data'], isA<Map>());
      expect(recorded.arguments['data']['nexmo'], equals('data'));
    });

    test('returns null when not a Vonage push', () async {
      handler.setResponse('processVonagePush', null);

      final result = await voice.processVonagePush({'other': 'payload'});
      expect(result, isNull);
    });
  });

  // ── parseCallEvent ───────────────────────────────────────────────────────

  group('parseCallEvent()', () {
    test('parses Ringing| event', () {
      final event = voice.parseCallEvent(
        'Ringing|+14155551234|+14158765432|Outgoing',
      );
      expect(event, equals(CallEvent.ringing));
      expect(voice.call.activeCall, isNotNull);
      expect(
        voice.call.activeCall!.callDirection,
        equals(CallDirection.outgoing),
      );
    });

    test('parses Connected| event and sets initiated', () {
      final event = voice.parseCallEvent(
        'Connected|+14155551234|+14158765432|Incoming',
      );
      expect(event, equals(CallEvent.connected));
      expect(voice.call.activeCall!.initiated, isNotNull);
    });

    test('parses Incoming| event', () {
      final event = voice.parseCallEvent(
        'Incoming|+14155551234|+14158765432|Incoming',
      );
      expect(event, equals(CallEvent.incoming));
      expect(
        voice.call.activeCall!.callDirection,
        equals(CallDirection.incoming),
      );
    });

    test('parses Answer event', () {
      final event = voice.parseCallEvent(
        'Answer|+14155551234|+14158765432|Incoming',
      );
      expect(event, equals(CallEvent.answer));
    });

    test('parses Call Ended and clears activeCall', () {
      // Set active call first
      voice.parseCallEvent('Ringing|+1234|+5678|Outgoing');
      expect(voice.call.activeCall, isNotNull);

      // End the call
      final event = voice.parseCallEvent('Call Ended');
      expect(event, equals(CallEvent.callEnded));
      expect(voice.call.activeCall, isNull);
    });

    test('parses PERMISSION| event', () {
      final event = voice.parseCallEvent('PERMISSION|Microphone|true');
      expect(event, equals(CallEvent.permission));
    });

    test('parses Reconnecting event', () {
      final event = voice.parseCallEvent('Reconnecting');
      expect(event, equals(CallEvent.reconnecting));
    });

    test('parses Reconnected event', () {
      final event = voice.parseCallEvent('Reconnected');
      expect(event, equals(CallEvent.reconnected));
    });

    test('parses Mute event', () {
      expect(voice.parseCallEvent('Mute'), equals(CallEvent.mute));
    });

    test('parses Unmute event', () {
      expect(voice.parseCallEvent('Unmute'), equals(CallEvent.unmute));
    });

    test('parses Speaker On event', () {
      expect(voice.parseCallEvent('Speaker On'), equals(CallEvent.speakerOn));
    });

    test('parses Speaker Off event', () {
      expect(voice.parseCallEvent('Speaker Off'), equals(CallEvent.speakerOff));
    });

    test('parses Bluetooth On event', () {
      expect(
        voice.parseCallEvent('Bluetooth On'),
        equals(CallEvent.bluetoothOn),
      );
    });

    test('parses Bluetooth Off event', () {
      expect(
        voice.parseCallEvent('Bluetooth Off'),
        equals(CallEvent.bluetoothOff),
      );
    });

    test('parses Missed Call event and clears activeCall', () {
      // Set active call first
      voice.parseCallEvent('Incoming|+1234|+5678|Incoming');
      expect(voice.call.activeCall, isNotNull);

      final event = voice.parseCallEvent('Missed Call');
      expect(event, equals(CallEvent.missedCall));
      expect(voice.call.activeCall, isNull);
    });

    test('parses Declined and clears activeCall', () {
      voice.parseCallEvent('Incoming|+1234|+5678|Incoming');
      expect(voice.call.activeCall, isNotNull);

      final event = voice.parseCallEvent('Declined');
      expect(event, equals(CallEvent.declined));
      expect(voice.call.activeCall, isNull);
    });

    test('parses Call Rejected and clears activeCall', () {
      voice.parseCallEvent('Incoming|+1234|+5678|Incoming');
      expect(voice.call.activeCall, isNotNull);

      final event = voice.parseCallEvent('Call Rejected');
      expect(event, equals(CallEvent.declined));
      expect(voice.call.activeCall, isNull);
    });

    test('LOG with Vonage error 31603 returns declined', () {
      voice.parseCallEvent('Incoming|+1234|+5678|Incoming');
      expect(voice.call.activeCall, isNotNull);

      final event = voice.parseCallEvent('LOG|Error 31603: Call rejected');
      expect(event, equals(CallEvent.declined));
      expect(voice.call.activeCall, isNull);
    });

    test('LOG with Vonage error 31486 returns declined', () {
      voice.parseCallEvent('Incoming|+1234|+5678|Incoming');

      final event = voice.parseCallEvent('LOG|Error 31486: Busy here');
      expect(event, equals(CallEvent.declined));
      expect(voice.call.activeCall, isNull);
    });

    test('LOG with "call rejected" text returns declined', () {
      voice.parseCallEvent('Incoming|+1234|+5678|Incoming');

      final event = voice.parseCallEvent('LOG|call rejected by remote');
      expect(event, equals(CallEvent.declined));
      expect(voice.call.activeCall, isNull);
    });

    test('LOG with "Rejecting invite" does NOT return declined', () {
      voice.parseCallEvent('Incoming|+1234|+5678|Incoming');

      final event = voice.parseCallEvent('LOG|Rejecting invite id=abc-123');
      expect(event, equals(CallEvent.log));
      // activeCall should still be set — this is a harmless native log
      expect(voice.call.activeCall, isNotNull);
    });

    test('LOG without error codes returns log', () {
      final event = voice.parseCallEvent('LOG|Session created successfully');
      expect(event, equals(CallEvent.log));
    });

    test('parses ReturningCall event', () {
      final event = voice.parseCallEvent('ReturningCall|+1234|+5678|Outgoing');
      expect(event, equals(CallEvent.returningCall));
      expect(
        voice.call.activeCall!.callDirection,
        equals(CallDirection.outgoing),
      );
    });

    test('parses AudioRoute| event', () {
      final event = voice.parseCallEvent('AudioRoute|Speaker');
      expect(event, equals(CallEvent.audioRouteChanged));
    });

    test('parses Connected| event with custom params', () {
      final event = voice.parseCallEvent(
        'Connected|+1234|+5678|Incoming|{"key":"value"}',
      );
      expect(event, equals(CallEvent.connected));
      expect(voice.call.activeCall!.customParams, isNotNull);
      expect(voice.call.activeCall!.customParams!['key'], equals('value'));
    });

    test('parses Incoming| with custom params', () {
      final event = voice.parseCallEvent(
        'Incoming|caller|callee|Incoming|{"foo":"bar"}',
      );
      expect(event, equals(CallEvent.incoming));
      expect(voice.call.activeCall!.customParams!['foo'], equals('bar'));
    });

    test('Incoming| sets correct from/to', () {
      voice.parseCallEvent('Incoming|alice|bob|Incoming');
      expect(voice.call.activeCall!.from, equals('alice'));
      expect(voice.call.activeCall!.to, equals('bob'));
    });

    test('Connected| sets initiated timestamp', () {
      voice.parseCallEvent('Connected|a|b|Outgoing');
      expect(voice.call.activeCall!.initiated, isNotNull);
      expect(
        voice.call.activeCall!.initiated!
            .difference(DateTime.now())
            .inSeconds
            .abs(),
        lessThan(2),
      );
    });

    test('Ringing| does not set initiated', () {
      voice.parseCallEvent('Ringing|a|b|Outgoing');
      expect(voice.call.activeCall!.initiated, isNull);
    });

    test('parses simple Connected (no pipe) event', () {
      expect(voice.parseCallEvent('Connected'), equals(CallEvent.connected));
    });

    test('parses simple Ringing (no pipe) event', () {
      expect(voice.parseCallEvent('Ringing'), equals(CallEvent.ringing));
    });

    test('ActiveCall strips client: prefix', () {
      voice.parseCallEvent('Incoming|client:alice|client:bob|Incoming');
      expect(voice.call.activeCall!.from, equals('alice'));
      expect(voice.call.activeCall!.to, equals('bob'));
    });

    test('parses Call Error prefix as log', () {
      final event = voice.parseCallEvent('Call Error: Authorization failed');
      expect(event, equals(CallEvent.log));
    });

    test('unknown event returns log', () {
      final event = voice.parseCallEvent('some_unknown_state');
      expect(event, equals(CallEvent.log));
    });
  });
}
