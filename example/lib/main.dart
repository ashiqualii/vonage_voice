import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:vonage_voice/vonage_voice.dart';
import 'package:vonage_voice_example/firebase_options.dart';
import 'package:vonage_voice_example/keys.dart';
import 'package:vonage_voice_example/screens/ui_incoming_call_screen.dart';
import 'package:vonage_voice_example/screens/ui_active_call_screen.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // This runs in a separate isolate when app is killed/backgrounded.
  // On Android, VonageFirebaseMessagingService handles push processing
  // natively — calling processVonagePush here would double-process the
  // push and can confuse the Vonage SDK's invite state.
  // On iOS, there is no native FCM service so Dart must forward the push.
  log('FCM background message received: ${message.data}');
  if (Platform.isIOS && message.data.isNotEmpty) {
    try {
      await VonageVoice.instance.processVonagePush(message.data);
    } catch (e) {
      log('processVonagePush (background) error: $e');
    }
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // ── Register background message handler ───────────────────────────────
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(const VonageExampleApp());
}

// ─────────────────────────────────────────────────────────────────────────

class VonageExampleApp extends StatelessWidget {
  const VonageExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vonage Voice Example',
      theme: ThemeData(useMaterial3: true),
      home: const LoginScreen(isFromSplashScreen: true),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// SCREEN 1 — Login
// ══════════════════════════════════════════════════════════════════════════

class LoginScreen extends StatefulWidget {
  final bool isFromSplashScreen;
  const LoginScreen({super.key, this.isFromSplashScreen = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _loading = false;
  String _status = 'Not logged in';

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _status = 'Logging in...';
    });

    try {
      // Request required permissions before registering
      await VonageVoice.instance.requestMicAccess();
      await VonageVoice.instance.requestReadPhoneStatePermission();
      await VonageVoice.instance.requestCallPhonePermission();
      await VonageVoice.instance.requestManageOwnCallsPermission();
      await VonageVoice.instance.requestNotificationPermission();

      // ── Battery optimization exemption (critical for Vivo/Xiaomi/OPPO) ──
      // Without this, the OEM kills the app and FCM cannot deliver incoming
      // call pushes when the app is backgrounded or killed.
      final isBatteryOptimized = await VonageVoice.instance
          .isBatteryOptimized();
      if (isBatteryOptimized) {
        await VonageVoice.instance.requestBatteryOptimizationExemption();
      }

      // ── Full-screen intent permission (Android 14+ / API 34+) ──────────
      // Without this, the incoming call notification will not show as a
      // full-screen intent on the lock screen.
      final canFullScreen = await VonageVoice.instance.canUseFullScreenIntent();
      if (!canFullScreen) {
        await VonageVoice.instance.openFullScreenIntentSettings();
      }

      // ── "Display over other apps" (SYSTEM_ALERT_WINDOW) ────────────────
      // Required on Samsung and many OEMs for the native incoming call
      // screen to launch from background/locked state via startActivity().
      // This is what WhatsApp and Botim use to show calls reliably.
      final canOverlay = await VonageVoice.instance.canDrawOverlays();
      if (!canOverlay) {
        await VonageVoice.instance.openOverlaySettings();
      }

      // Get FCM token for incoming call push notifications
      String? fcmToken;
      if (Platform.isAndroid) {
        fcmToken = await FirebaseMessaging.instance.getToken();
      }

      // Register JWT with Vonage + FCM token for incoming calls
      final result = await VonageVoice.instance.setTokens(
        accessToken: kTestJwt,
        deviceToken: fcmToken,
        isSandbox: true,
      );

      if (result == true) {
        setState(() => _status = 'Logged in ✓');

        if (!mounted) return;

        // Navigate to dialer and start listening to call events
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DialerScreen()),
        );
      } else {
        setState(() => _status = 'Login failed — check JWT');
      }
    } catch (e) {
      setState(() => _status = 'Error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.isFromSplashScreen) {
      _login();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vonage Voice — Login')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _status,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _loading ? null : _login,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Login'),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// SCREEN 2 — Dialer
// ══════════════════════════════════════════════════════════════════════════

class DialerScreen extends StatefulWidget {
  const DialerScreen({super.key});

  @override
  State<DialerScreen> createState() => _DialerScreenState();
}

class _DialerScreenState extends State<DialerScreen>
    with WidgetsBindingObserver {
  final TextEditingController _numberController = TextEditingController(
    text: '13156057951',
  );
  StreamSubscription<CallEvent>? _eventSub;
  StreamSubscription<RemoteMessage>? _fcmForegroundSub;
  Timer? _incomingTimer;
  bool _calling = false;
  bool _onCallScreen = false;
  String _status = 'Ready';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listenToCallEvents();
    _listenToFcmForeground();
    _checkActiveCallOnResume();
  }

  /// Forward foreground FCM messages to the native Vonage SDK.
  /// On Android, VonageFirebaseMessagingService already processes the
  /// push natively — calling processVonagePush from Dart would
  /// double-process it and can break the invite state.
  /// On iOS, there is no native FCM service so Dart must forward.
  void _listenToFcmForeground() {
    _fcmForegroundSub = FirebaseMessaging.onMessage.listen((
      RemoteMessage message,
    ) {
      log('FCM foreground message: ${message.data}');
      if (Platform.isIOS && message.data.isNotEmpty) {
        VonageVoice.instance.processVonagePush(message.data);
      }
    });
  }

  /// Listen to all call events globally.
  /// Handles incoming calls, call ended, and errors.
  /// When a call screen is showing, skip navigation events to avoid
  /// conflicting with the ActiveCallScreen's own listener.
  void _listenToCallEvents() {
    _eventSub = VonageVoice.instance.callEventsListener.listen((
      CallEvent event,
    ) {
      log('Call event: $event');

      // Skip navigation events while a call screen is active —
      // ActiveCallScreen handles its own connected/callEnded events.
      if (_onCallScreen) {
        switch (event) {
          case CallEvent.callEnded:
          case CallEvent.missedCall:
          case CallEvent.declined:
            // These pop back to dialer — handle below
            break;
          default:
            return;
        }
      }

      switch (event) {
        // ── Incoming call ───────────────────────────────────────────────
        case CallEvent.incoming:
          log('CallEvent.incoming received');
          setState(() => _status = 'incoming...');

          _incomingTimer?.cancel();
          _incomingTimer = Timer(const Duration(milliseconds: 100), () {
            if (!mounted || _onCallScreen) return;

            final activeCall = VonageVoice.instance.call.activeCall;
            log('activeCall: ${activeCall?.from} -> ${activeCall?.to}');

            if (activeCall != null) {
              log('Navigating to IncomingCallScreen');
              _onCallScreen = true;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => IncomingCallScreen(activeCall: activeCall),
                ),
              );
            } else {
              log('activeCall is NULL -- cannot navigate');
              setState(() => _status = 'Error: activeCall not set');
            }
          });
          break;
        case CallEvent.ringing:
          log('CallEvent.ringing -- outgoing call is ringing');
          // Outgoing call is ringing on remote side
          // ActiveCallScreen is already pushed by _makeCall()
          // so we just update the status — no navigation needed
          setState(() => _status = 'Ringing...');
          break;

        // ── Call connected ──────────────────────────────────────────────
        case CallEvent.connected:
          log('CallEvent.connected');
          // Cancel incoming timer — if the call was answered before
          // the IncomingCallScreen was pushed (e.g. answered from CallKit
          // notification while app was in background), prevent the
          // IncomingCallScreen from being pushed on top of ActiveCallScreen.
          _incomingTimer?.cancel();
          final activeCall = VonageVoice.instance.call.activeCall;
          if (activeCall != null && mounted) {
            log('Navigating to ActiveCallScreen');
            _onCallScreen = true;
            // Push active call screen (don't replace — DialerScreen stays in stack)
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ActiveCallScreen(activeCall: activeCall),
              ),
            );
          } else {
            log('activeCall is NULL on connected event');
          }
          break;

        // ── Call ended ──────────────────────────────────────────────────
        case CallEvent.callEnded:
          _incomingTimer?.cancel();
          _onCallScreen = false;
          setState(() {
            _calling = false;
            _status = 'Call ended';
          });
          // Pop any call screen back to dialer
          if (mounted) {
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
          break;

        // ── Missed call ─────────────────────────────────────────────────
        case CallEvent.missedCall:
          _incomingTimer?.cancel();
          _onCallScreen = false;
          setState(() => _status = 'Missed call');
          if (mounted) {
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
          break;

        // ── Declined ───────────────────────────────────────────────────
        case CallEvent.declined:
          _incomingTimer?.cancel();
          _onCallScreen = false;
          setState(() {
            _calling = false;
            _status = 'Call declined';
          });
          if (mounted) {
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
          break;

        // ── Errors / logs ───────────────────────────────────────────────
        case CallEvent.log:
          break;

        default:
          break;
      }
    });
  }

  Future<void> _makeCall() async {
    final number = _numberController.text.trim();
    if (number.isEmpty) {
      setState(() => _status = 'Enter a phone number');
      return;
    }

    setState(() {
      _calling = true;
      _status = 'Calling $number...';
    });

    try {
      final result = await VonageVoice.instance.call.place(
        from: '13044622020',
        to: number,
        // extraOptions: {"userID": "4514", "assignID": "4514", 'is_phone': 1},
      );

      if (result != true) {
        setState(() {
          _calling = false;
          _status = 'Failed to place call';
        });
        return;
      }

      // Navigate to active call screen
      if (mounted) {
        _onCallScreen = true;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ActiveCallScreen(
              activeCall:
                  VonageVoice.instance.call.activeCall ??
                  ActiveCall(
                    from: '13044622020',
                    to: number,
                    callDirection: CallDirection.outgoing,
                    // customParams: {
                    //   "userID": "4514",
                    //   "assignID": "4514",
                    //   'is_phone': 1,
                    // },
                  ),
            ),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _calling = false;
        _status = 'Error: $e';
      });
    }
  }

  Future<void> _logout() async {
    await VonageVoice.instance.unregister();
    if (mounted) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkActiveCallOnResume();
    }
  }

  /// When the app resumes, check if there is an active call that we should
  /// navigate to (e.g. user answered from notification while app was in bg).
  void _checkActiveCallOnResume() {
    if (_onCallScreen) return;
    final session = VonageVoice.instance.callSessionManager.activeSession;
    final activeCall = VonageVoice.instance.call.activeCall;
    if (session != null && activeCall != null) {
      _onCallScreen = true;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ActiveCallScreen(activeCall: activeCall),
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _incomingTimer?.cancel();
    _eventSub?.cancel();
    _fcmForegroundSub?.cancel();
    _numberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vonage Voice — Dialer'),
        actions: [TextButton(onPressed: _logout, child: const Text('Logout'))],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Status ──────────────────────────────────────────────────
              Text(
                _status,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 24),

              // ── Phone number input ───────────────────────────────────────
              TextField(
                controller: _numberController,
                keyboardType: TextInputType.phone,
                readOnly: true,
                decoration: InputDecoration(
                  hintText: 'Phone number',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                  suffixIcon: IconButton(
                    icon: Icon(Icons.backspace_outlined, color: Colors.black54),
                    onPressed: () {
                      if (_numberController.text.isNotEmpty) {
                        setState(() {
                          _numberController.text = _numberController.text
                              .substring(0, _numberController.text.length - 1);
                        });
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Dial button ──────────────────────────────────────────────
              ElevatedButton.icon(
                onPressed: _calling ? null : _makeCall,
                icon: _calling
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.call),
                label: Text(_calling ? 'Calling...' : 'Call'),
              ),
              const SizedBox(height: 32),

              // ── Dialpad ──────────────────────────────────────────────────
              const Text(
                'Dialpad',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              _DialPad(
                onDigitPressed: (digit) {
                  _numberController.text += digit;
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// SHARED WIDGETS
// ══════════════════════════════════════════════════════════════════════════

/// Reusable dialpad widget — used in DialerScreen.
class _DialPad extends StatelessWidget {
  final void Function(String digit) onDigitPressed;
  final bool darkMode;

  const _DialPad({required this.onDigitPressed, this.darkMode = false});

  static const _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['*', '0', '#'],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: _rows.map((row) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: row.map((digit) {
            return _DialPadKey(
              digit: digit,
              darkMode: darkMode,
              onTap: () => onDigitPressed(digit),
            );
          }).toList(),
        );
      }).toList(),
    );
  }
}

/// Single dialpad key button.
class _DialPadKey extends StatelessWidget {
  final String digit;
  final bool darkMode;
  final VoidCallback onTap;

  const _DialPadKey({
    required this.digit,
    required this.onTap,
    this.darkMode = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(40),
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: darkMode ? Colors.white12 : Colors.grey.shade200,
          ),
          alignment: Alignment.center,
          child: Text(
            digit,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w500,
              color: darkMode ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }
}
