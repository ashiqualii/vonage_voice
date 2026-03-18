import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:vonage_voice/vonage_voice.dart';
import 'package:vonage_voice_example/firebase_options.dart';
import 'package:vonage_voice_example/keys.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
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
      home: const LoginScreen(),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// SCREEN 1 — Login
// ══════════════════════════════════════════════════════════════════════════

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

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

      // Get FCM token for incoming call push notifications
      final fcmToken = await FirebaseMessaging.instance.getToken();

      // Register JWT with Vonage + FCM token for incoming calls
      final result = await VonageVoice.instance.setTokens(
        accessToken: kTestJwt,
        deviceToken: fcmToken,
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
  bool _calling = false;
  String _status = 'Ready';

  @override
  void initState() {
    super.initState();
    _listenToCallEvents();
  }

  /// Listen to all call events globally.
  /// Handles incoming calls, call ended, and errors.
  void _listenToCallEvents() {
    _eventSub = VonageVoice.instance.callEventsListener.listen((
      CallEvent event,
    ) {
      switch (event) {
        // ── Incoming call ───────────────────────────────────────────────
        case CallEvent.incoming:
          final activeCall = VonageVoice.instance.call.activeCall;
          if (activeCall != null && mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => IncomingCallScreen(activeCall: activeCall),
              ),
            );
          }
          break;
        case CallEvent.ringing:
          // Outgoing call is ringing on remote side
          // ActiveCallScreen is already pushed by _makeCall()
          // so we just update the status — no navigation needed
          setState(() => _status = 'Ringing...');
          break;

        // ── Call connected ──────────────────────────────────────────────
        case CallEvent.connected:
          final activeCall = VonageVoice.instance.call.activeCall;
          if (activeCall != null && mounted) {
            // Replace incoming screen with active call screen
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => ActiveCallScreen(activeCall: activeCall),
              ),
            );
          }
          break;

        // ── Call ended ──────────────────────────────────────────────────
        case CallEvent.callEnded:
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
          setState(() => _status = 'Missed call');
          if (mounted) {
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
          break;

        // ── Declined ───────────────────────────────────────────────────
        case CallEvent.declined:
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
        from: 'test user',
        to: number,
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
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ActiveCallScreen(
              activeCall:
                  VonageVoice.instance.call.activeCall ??
                  ActiveCall(
                    from: 'me',
                    to: number,
                    callDirection: CallDirection.outgoing,
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
    _eventSub?.cancel();
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
      body: Padding(
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
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// SCREEN 3 — Incoming Call
// ══════════════════════════════════════════════════════════════════════════

class IncomingCallScreen extends StatelessWidget {
  final ActiveCall activeCall;

  const IncomingCallScreen({super.key, required this.activeCall});

  Future<void> _answer(BuildContext context) async {
    await VonageVoice.instance.call.answer();
    // ActiveCallScreen is pushed by the connected event listener in DialerScreen
  }

  Future<void> _reject(BuildContext context) async {
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
                    activeCall.fromFormatted.isNotEmpty
                        ? activeCall.fromFormatted
                        : activeCall.from,
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
  final TextEditingController _dtmfController = TextEditingController();
  StreamSubscription<CallEvent>? _eventSub;

  @override
  void initState() {
    super.initState();
    _listenToCallEvents();
    _syncAudioState();
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
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) Navigator.of(context).pop();
          });
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

                  // Row 2 — Dialpad toggle
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
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
