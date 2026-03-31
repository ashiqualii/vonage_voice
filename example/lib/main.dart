import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:vonage_voice/vonage_voice.dart';
import 'package:vonage_voice_example/firebase_options.dart';
import 'package:vonage_voice_example/keys.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // This runs in a separate isolate when app is killed/backgrounded.
  // Forward push data to the native Vonage SDK so it can process
  // incoming call invites even when VonageFirebaseMessagingService
  // did not receive the FCM message.
  log('FCM background message received: ${message.data}');
  if (message.data.isNotEmpty) {
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

      // Get FCM token for incoming call push notifications
      String? fcmToken;
      if (Platform.isAndroid) {
        fcmToken = await FirebaseMessaging.instance.getToken();
      }

      // Register JWT with Vonage + FCM token for incoming calls
      final result = await VonageVoice.instance.setTokens(
        accessToken: kTestJwt,
        deviceToken: fcmToken,
        isSandbox: false,
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

class _DialerScreenState extends State<DialerScreen> {
  final TextEditingController _numberController = TextEditingController();
  StreamSubscription<CallEvent>? _eventSub;
  StreamSubscription<RemoteMessage>? _fcmForegroundSub;
  Timer? _incomingTimer;
  bool _calling = false;
  bool _onCallScreen = false;
  String _status = 'Ready';

  @override
  void initState() {
    super.initState();
    _listenToCallEvents();
    _listenToFcmForeground();
  }

  /// Forward foreground FCM messages to the native Vonage SDK.
  void _listenToFcmForeground() {
    _fcmForegroundSub = FirebaseMessaging.onMessage.listen((
      RemoteMessage message,
    ) {
      log('FCM foreground message: ${message.data}');
      if (message.data.isNotEmpty) {
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
  void dispose() {
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
// SCREEN 3 — Incoming Call
// ══════════════════════════════════════════════════════════════════════════

class IncomingCallScreen extends StatefulWidget {
  final ActiveCall activeCall;

  const IncomingCallScreen({super.key, required this.activeCall});

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  StreamSubscription<CallEvent>? _eventSub;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();

    // If the call was already cancelled before this screen mounted, pop back.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_navigated) return;
      final current = VonageVoice.instance.call.activeCall;
      if (current == null) {
        _navigated = true;
        if (mounted) Navigator.of(context).pop();
      }
    });

    // Listen for events so that answering from the notification
    // (which bypasses _answer()) still navigates to ActiveCallScreen.
    _eventSub = VonageVoice.instance.callEventsListener.listen((event) {
      if (!mounted || _navigated) return;
      switch (event) {
        case CallEvent.connected:
          _navigated = true;
          final call =
              VonageVoice.instance.call.activeCall ?? widget.activeCall;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => ActiveCallScreen(activeCall: call),
            ),
          );
          break;
        case CallEvent.callEnded:
        case CallEvent.missedCall:
        case CallEvent.declined:
          _navigated = true;
          if (mounted) Navigator.of(context).pop();
          break;
        default:
          break;
      }
    });
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }

  Future<void> _answer(BuildContext context) async {
    if (_navigated) return;
    _navigated = true;
    final result = await VonageVoice.instance.call.answer();
    if (!context.mounted) return;
    if (result != true) {
      // Answer failed — allow retry
      _navigated = false;
      return;
    }
    final call = VonageVoice.instance.call.activeCall ?? widget.activeCall;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => ActiveCallScreen(activeCall: call)),
    );
  }

  Future<void> _reject(BuildContext context) async {
    if (_navigated) return;
    _navigated = true;
    await VonageVoice.instance.call.hangUp();
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // ── Caller info ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(top: 80),
              child: Column(
                children: [
                  const Icon(
                    Icons.account_circle,
                    size: 100,
                    color: Colors.white54,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.activeCall.fromFormatted.isNotEmpty
                        ? widget.activeCall.fromFormatted
                        : widget.activeCall.from,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Incoming Call',
                    style: TextStyle(color: Colors.white54, fontSize: 16),
                  ),
                ],
              ),
            ),

            // ── Answer / Reject buttons ──────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(bottom: 60),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Reject
                  Column(
                    children: [
                      FloatingActionButton(
                        heroTag: 'reject',
                        backgroundColor: Colors.red,
                        onPressed: () => _reject(context),
                        child: const Icon(
                          Icons.call_end,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Decline',
                        style: TextStyle(color: Colors.white54),
                      ),
                    ],
                  ),

                  // Answer
                  Column(
                    children: [
                      FloatingActionButton(
                        heroTag: 'answer',
                        backgroundColor: Colors.green,
                        onPressed: () => _answer(context),
                        child: const Icon(
                          Icons.call,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Answer',
                        style: TextStyle(color: Colors.white54),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// SCREEN 4 — Active Call
// ══════════════════════════════════════════════════════════════════════════

class ActiveCallScreen extends StatefulWidget {
  final ActiveCall activeCall;

  const ActiveCallScreen({super.key, required this.activeCall});

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen> {
  bool _muted = false;
  bool _onSpeaker = false;
  bool _onHold = false;
  bool _bluetoothOn = false;
  bool btAvailable = false;
  bool _showDialpad = false;
  bool _callReady = false;
  String _callStatus = 'Connecting...';
  List<AudioDevice> _audioDevices = [];
  final TextEditingController _dtmfController = TextEditingController();
  StreamSubscription<CallEvent>? _eventSub;

  @override
  void initState() {
    super.initState();
    _listenToCallEvents();
    _syncAudioState();
    // If the call is already connected when this screen mounts
    // (e.g. answered from notification before Flutter was ready),
    // the 'connected' event was already consumed by DialerScreen.
    // Set the correct state immediately.
    _checkInitialCallState();
  }

  /// If the call is already active/connected when this screen is pushed,
  /// update the UI right away instead of waiting for another event.
  void _checkInitialCallState() {
    final activeCall = VonageVoice.instance.call.activeCall;
    if (activeCall != null) {
      setState(() {
        _callReady = true;
        _callStatus = 'Connected';
      });
    }
  }

  /// Query the actual audio routing state from the native layer.
  Future<void> _syncAudioState() async {
    final isBt = await VonageVoice.instance.call.isBluetoothOn() ?? false;
    final isSpeaker = await VonageVoice.instance.call.isOnSpeaker() ?? false;
    final isMuted = await VonageVoice.instance.call.isMuted() ?? false;
    final btAvail =
        await VonageVoice.instance.call.isBluetoothAvailable() ?? false;
    if (!mounted) return;
    setState(() {
      _bluetoothOn = isBt;
      _onSpeaker = isSpeaker;
      _muted = isMuted;
      btAvailable = btAvail;
    });
  }

  /// Listen for audio state changes while in the active call screen.
  void _listenToCallEvents() {
    _eventSub = VonageVoice.instance.callEventsListener.listen((
      CallEvent event,
    ) {
      if (!mounted) return;
      switch (event) {
        case CallEvent.ringing:
          _syncAudioState();
          setState(() {
            _callReady = true;
            _callStatus = 'Ringing...';
          });
          break;
        case CallEvent.connected:
          _syncAudioState();
          setState(() {
            _callReady = true;
            _callStatus = 'Connected';
          });
          break;
        case CallEvent.callEnded:
          setState(() => _callStatus = 'Call ended');
          // Navigation is handled by DialerScreen's popUntil(isFirst).
          // Do NOT pop here — a delayed pop() can race with popUntil()
          // and accidentally pop the DialerScreen itself, leaving a blank screen.
          break;
        case CallEvent.mute:
          setState(() => _muted = true);
          break;
        case CallEvent.unmute:
          setState(() => _muted = false);
          break;
        case CallEvent.speakerOn:
          setState(() {
            _onSpeaker = true;
            _bluetoothOn = false;
          });
          break;
        case CallEvent.speakerOff:
          setState(() => _onSpeaker = false);
          break;
        case CallEvent.hold:
          setState(() => _onHold = true);
          break;
        case CallEvent.unhold:
          setState(() => _onHold = false);
          break;
        case CallEvent.bluetoothOn:
          setState(() {
            _bluetoothOn = true;
            btAvailable = true;
            _onSpeaker = false;
          });
          break;
        case CallEvent.bluetoothOff:
          _syncAudioState();
          break;
        case CallEvent.reconnecting:
          setState(() => _callStatus = 'Reconnecting...');
          break;
        case CallEvent.reconnected:
          setState(() => _callStatus = 'Connected');
          break;
        default:
          break;
      }
    });
  }

  Future<void> _toggleMute() async {
    if (!_callReady) return;
    try {
      await VonageVoice.instance.call.toggleMute(!_muted);
    } catch (_) {}
  }

  Future<void> _toggleSpeaker() async {
    if (!_callReady) return;
    try {
      await VonageVoice.instance.call.toggleSpeaker(!_onSpeaker);
    } catch (_) {}
  }

  Future<void> _toggleHold() async {
    if (!_callReady) return;
    try {
      await VonageVoice.instance.call.holdCall(holdCall: !_onHold);
    } catch (_) {}
  }

  Future<void> _toggleBluetooth() async {
    if (!_callReady) return;
    try {
      // If already on BT, just turn it off
      if (_bluetoothOn) {
        await VonageVoice.instance.call.toggleBluetooth(bluetoothOn: false);
        return;
      }

      // Check if BT adapter is enabled on the device
      final btEnabled =
          await VonageVoice.instance.call.isBluetoothEnabled() ?? false;

      if (!btEnabled) {
        // Show native "Turn on Bluetooth?" dialog
        final userEnabled =
            await VonageVoice.instance.call.showBluetoothEnablePrompt() ??
            false;
        if (!userEnabled) return;

        // BT is now enabled — wait briefly for paired devices to auto-connect
        await Future.delayed(const Duration(seconds: 2));
      }

      // Check if a BT audio device is connected
      final btAvail =
          await VonageVoice.instance.call.isBluetoothAvailable() ?? false;

      if (btAvail) {
        // Device connected — route audio to it
        await VonageVoice.instance.call.toggleBluetooth(bluetoothOn: true);
      } else {
        // No device connected — open BT settings to pair/connect
        await VonageVoice.instance.call.openBluetoothSettings();
      }

      _syncAudioState();
    } catch (_) {}
  }

  Future<void> _hangUp() async {
    try {
      await VonageVoice.instance.call.hangUp();
    } catch (_) {}
  }

  Future<void> _sendDtmf(String digit) async {
    await VonageVoice.instance.call.sendDigits(digit);
    setState(() => _dtmfController.text += digit);
  }

  /// Fetches the current list of available audio output devices from the
  /// native platform and updates the local state.
  Future<void> _refreshAudioDevices() async {
    try {
      final devices = await VonageVoice.instance.call.getAudioDevices();
      if (!mounted) return;
      setState(() => _audioDevices = devices);
    } catch (e) {
      log('Failed to refresh audio devices: $e');
    }
  }

  /// Selects an audio device by its platform-specific [deviceId] and
  /// refreshes the device list + audio state indicators.
  Future<void> _selectAudioDevice(String deviceId) async {
    try {
      await VonageVoice.instance.call.selectAudioDevice(deviceId);
      // Allow the OS a moment to complete the route change, then
      // refresh both the device list and the top-level audio indicators.
      await Future.delayed(const Duration(milliseconds: 300));
      await Future.wait([_refreshAudioDevices(), _syncAudioState()]);
    } catch (e) {
      log('Failed to select audio device: $e');
    }
  }

  /// Opens a bottom sheet listing all available audio output devices.
  /// The user can tap a device to switch audio routing.
  void _showAudioDevicePicker() {
    _refreshAudioDevices().then((_) {
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xFF1E1E1E),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (sheetContext) {
          return StatefulBuilder(
            builder: (context, setSheetState) {
              return SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Header ────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.speaker_group,
                            color: Colors.white70,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Audio Output',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          // Refresh button
                          IconButton(
                            icon: const Icon(
                              Icons.refresh,
                              color: Colors.white54,
                              size: 20,
                            ),
                            onPressed: () async {
                              await _refreshAudioDevices();
                              setSheetState(() {});
                            },
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Colors.white12, height: 1),

                    // ── Device list ──────────────────────────────────
                    if (_audioDevices.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Text(
                          'No audio devices found',
                          style: TextStyle(color: Colors.white38),
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _audioDevices.length,
                        itemBuilder: (_, index) {
                          final device = _audioDevices[index];
                          return _AudioDeviceTile(
                            device: device,
                            onTap: () async {
                              Navigator.of(sheetContext).pop();
                              await _selectAudioDevice(device.id);
                            },
                          );
                        },
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              );
            },
          );
        },
      );
    });
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _dtmfController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final contact = widget.activeCall.fromFormatted.isNotEmpty
        ? widget.activeCall.fromFormatted
        : widget.activeCall.from.isNotEmpty
        ? widget.activeCall.from
        : widget.activeCall.to;

    return Scaffold(
      backgroundColor: Colors.black87,
      body: SafeArea(
        child: Column(
          children: [
            // ── Call info ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  const Icon(
                    Icons.account_circle,
                    size: 80,
                    color: Colors.white54,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    contact,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _callStatus,
                    style: const TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                  if (_onHold)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'On Hold',
                        style: TextStyle(color: Colors.orange, fontSize: 14),
                      ),
                    ),
                  if (_callReady)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _bluetoothOn
                                ? Icons.bluetooth_audio
                                : _onSpeaker
                                ? Icons.volume_up
                                : Icons.hearing,
                            color: Colors.white38,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _bluetoothOn
                                ? 'Bluetooth'
                                : _onSpeaker
                                ? 'Speaker'
                                : 'Earpiece',
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // ── DTMF dialpad toggle ──────────────────────────────────────
            if (_showDialpad) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: TextField(
                  controller: _dtmfController,
                  readOnly: true,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 20),
                  decoration: const InputDecoration(
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white30),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const SizedBox(height: 8),
              _DialPad(onDigitPressed: _sendDtmf, darkMode: true),
              const SizedBox(height: 8),
            ],

            const Spacer(),

            // ── Control buttons ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  // Row 1 — Mute, Speaker, Bluetooth, Hold
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _CallControlButton(
                        icon: _muted ? Icons.mic_off : Icons.mic,
                        label: _muted ? 'Unmute' : 'Mute',
                        active: _muted,
                        onTap: _callReady ? _toggleMute : null,
                      ),
                      _CallControlButton(
                        icon: _onSpeaker ? Icons.volume_up : Icons.volume_down,
                        label: 'Speaker',
                        active: _onSpeaker,
                        onTap: _callReady ? _toggleSpeaker : null,
                      ),
                      _CallControlButton(
                        icon: Icons.bluetooth_audio,
                        label: 'Bluetooth',
                        active: _bluetoothOn,
                        onTap: _callReady ? _toggleBluetooth : null,
                      ),
                      _CallControlButton(
                        icon: _onHold ? Icons.play_arrow : Icons.pause,
                        label: _onHold ? 'Resume' : 'Hold',
                        active: _onHold,
                        onTap: _callReady ? _toggleHold : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Row 2 — Audio Devices, Dialpad toggle
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _CallControlButton(
                        icon: Icons.speaker_group,
                        label: 'Audio',
                        active: false,
                        onTap: _callReady ? _showAudioDevicePicker : null,
                      ),
                      _CallControlButton(
                        icon: Icons.dialpad,
                        label: 'Keypad',
                        active: _showDialpad,
                        onTap: () =>
                            setState(() => _showDialpad = !_showDialpad),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // ── Hang up ──────────────────────────────────────────────────
            FloatingActionButton(
              heroTag: 'hangup',
              backgroundColor: Colors.red,
              onPressed: _hangUp,
              child: const Icon(Icons.call_end, color: Colors.white, size: 32),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// SHARED WIDGETS
// ══════════════════════════════════════════════════════════════════════════

/// Reusable dialpad widget — used in both DialerScreen and ActiveCallScreen.
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

/// Reusable call control toggle button (mute, speaker, hold, etc.)
class _CallControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  const _CallControlButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.4,
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? Colors.white : Colors.white12,
              ),
              child: Icon(
                icon,
                color: active ? Colors.black87 : Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single row in the audio device picker bottom sheet.
///
/// Shows the device icon, name, type badge, and a checkmark for the
/// currently active output device.
class _AudioDeviceTile extends StatelessWidget {
  final AudioDevice device;
  final VoidCallback onTap;

  const _AudioDeviceTile({required this.device, required this.onTap});

  /// Maps each [AudioDeviceType] to a descriptive icon.
  IconData _iconForType(AudioDeviceType type) {
    switch (type) {
      case AudioDeviceType.earpiece:
        return Icons.hearing;
      case AudioDeviceType.speaker:
        return Icons.volume_up;
      case AudioDeviceType.bluetooth:
        return Icons.bluetooth_audio;
      case AudioDeviceType.wiredHeadset:
        return Icons.headset;
      case AudioDeviceType.unknown:
        return Icons.device_unknown;
    }
  }

  /// Returns a human-readable label for the device type.
  String _labelForType(AudioDeviceType type) {
    switch (type) {
      case AudioDeviceType.earpiece:
        return 'Earpiece';
      case AudioDeviceType.speaker:
        return 'Speaker';
      case AudioDeviceType.bluetooth:
        return 'Bluetooth';
      case AudioDeviceType.wiredHeadset:
        return 'Wired';
      case AudioDeviceType.unknown:
        return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isActive = device.isActive;
    return ListTile(
      leading: Icon(
        _iconForType(device.type),
        color: isActive ? Colors.greenAccent : Colors.white54,
        size: 24,
      ),
      title: Text(
        device.name,
        style: TextStyle(
          color: isActive ? Colors.greenAccent : Colors.white,
          fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        _labelForType(device.type),
        style: const TextStyle(color: Colors.white38, fontSize: 12),
      ),
      trailing: isActive
          ? const Icon(Icons.check_circle, color: Colors.greenAccent, size: 22)
          : const Icon(Icons.circle_outlined, color: Colors.white24, size: 22),
      onTap: onTap,
    );
  }
}
