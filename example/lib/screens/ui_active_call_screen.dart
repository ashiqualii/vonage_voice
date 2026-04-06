import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:vonage_voice/vonage_voice.dart';
import 'widgets/animated_ring.dart';
import 'widgets/call_features.dart';
import 'widgets/call_status.dart';

/// Active call screen with animated ring, call timer, audio controls,
/// DTMF keypad, and audio device picker.
///
/// Uses [CallSessionManager] for session tracking and call state persistence.
class ActiveCallScreen extends StatefulWidget {
  final ActiveCall activeCall;

  const ActiveCallScreen({super.key, required this.activeCall});

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen> {
  bool _callReady = false;
  bool _showDialpad = false;
  bool _isConnected = false;
  bool _bluetoothOn = false;
  bool _speakerOn = false;
  String _callStatus = 'Connecting...';
  DateTime? _callStartTime;
  List<AudioDevice> _audioDevices = [];
  final TextEditingController _dtmfController = TextEditingController();
  StreamSubscription<CallEvent>? _eventSub;

  @override
  void initState() {
    super.initState();
    _listenToCallEvents();
    _syncAudioState();
    _checkInitialCallState();
  }

  void _checkInitialCallState() {
    final activeCall = VonageVoice.instance.call.activeCall;
    if (activeCall != null) {
      // Check session manager for existing session state
      final session = VonageVoice.instance.callSessionManager.activeSession;
      if (session != null) {
        setState(() {
          _callReady = true;
          _isConnected = true;
          _callStatus = 'Connected';
          _callStartTime = session.startedAt;
        });
      } else {
        setState(() {
          _callReady = true;
          _callStatus = 'Connected';
          _isConnected = true;
          _callStartTime = DateTime.now();
        });
      }
    }
  }

  Future<void> _syncAudioState() async {
    final results = await Future.wait<bool?>([
      VonageVoice.instance.call.isBluetoothOn(),
      VonageVoice.instance.call.isOnSpeaker(),
      VonageVoice.instance.call.isMuted(),
    ]);
    if (!mounted) return;
    setState(() {
      _bluetoothOn = results[0] ?? false;
      _speakerOn = results[1] ?? false;
    });
  }

  void _listenToCallEvents() {
    _eventSub = VonageVoice.instance.callEventsListener.listen((event) {
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
            _isConnected = true;
            _callStatus = 'Connected';
            _callStartTime ??= DateTime.now();
          });
          break;
        case CallEvent.callEnded:
          setState(() {
            _callStatus = 'Call ended';
            _isConnected = false;
          });
          break;
        case CallEvent.speakerOn:
          setState(() {
            _speakerOn = true;
            _bluetoothOn = false;
          });
          break;
        case CallEvent.speakerOff:
          setState(() => _speakerOn = false);
          break;
        case CallEvent.bluetoothOn:
          setState(() {
            _bluetoothOn = true;
            _speakerOn = false;
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

  Future<void> _sendDtmf(String digit) async {
    await VonageVoice.instance.call.sendDigits(digit);
    setState(() => _dtmfController.text += digit);
  }

  Future<void> _refreshAudioDevices() async {
    try {
      final devices = await VonageVoice.instance.call.getAudioDevices();
      if (!mounted) return;
      setState(() => _audioDevices = devices);
    } catch (e) {
      log('Failed to refresh audio devices: $e');
    }
  }

  Future<void> _selectAudioDevice(String deviceId) async {
    try {
      await VonageVoice.instance.call.selectAudioDevice(deviceId);
      await Future.delayed(const Duration(milliseconds: 300));
      await Future.wait([_refreshAudioDevices(), _syncAudioState()]);
    } catch (e) {
      log('Failed to select audio device: $e');
    }
  }

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
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Row(
                        children: [
                          const Icon(Icons.speaker_group,
                              color: Colors.white70, size: 22),
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
                          IconButton(
                            icon: const Icon(Icons.refresh,
                                color: Colors.white54, size: 20),
                            onPressed: () async {
                              await _refreshAudioDevices();
                              setSheetState(() {});
                            },
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Colors.white12, height: 1),
                    if (_audioDevices.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Text('No audio devices found',
                            style: TextStyle(color: Colors.white38)),
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

  String _getInitials(String name) {
    if (name.isEmpty) return '?';
    if (name.startsWith('+') ||
        name.codeUnits.every((c) =>
            (c >= 48 && c <= 57) ||
            c == 32 ||
            c == 45 ||
            c == 40 ||
            c == 41)) {
      return '#';
    }
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0].toUpperCase()}${parts[1][0].toUpperCase()}';
    }
    return parts[0][0].toUpperCase();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _dtmfController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isOutgoing =
        widget.activeCall.callDirection == CallDirection.outgoing;
    final contact = isOutgoing
        ? (widget.activeCall.toFormatted.isNotEmpty
            ? widget.activeCall.toFormatted
            : widget.activeCall.to)
        : (widget.activeCall.fromFormatted.isNotEmpty
            ? widget.activeCall.fromFormatted
            : widget.activeCall.from.isNotEmpty
                ? widget.activeCall.from
                : widget.activeCall.to);

    return Scaffold(
      backgroundColor: const Color(0xFF1B1B2F),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 32),

            // ── Animated ring with initials ───────────────────────────
            AnimatedRing(
              isConnected: _isConnected,
              size: 140,
              child: Container(
                width: 80,
                height: 80,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF346299),
                ),
                alignment: Alignment.center,
                child: Text(
                  _getInitials(contact),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Contact name ──────────────────────────────────────────
            Text(
              contact,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),

            // ── Call status + timer + audio route ─────────────────────
            CallStatusWidget(
              statusText: _callStatus,
              callStartTime: _callStartTime,
              isConnected: _isConnected,
              bluetoothOn: _bluetoothOn,
              speakerOn: _speakerOn,
            ),

            // ── DTMF dialpad ─────────────────────────────────────────
            if (_showDialpad) ...[
              const SizedBox(height: 16),
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
              _DialPad(onDigitPressed: _sendDtmf),
            ],

            const Spacer(),

            // ── Controls ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: CallFeatures(
                callReady: _callReady,
                showDialpad: _showDialpad,
                onShowDialpad: () =>
                    setState(() => _showDialpad = !_showDialpad),
                onShowAudioPicker: _showAudioDevicePicker,
              ),
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

class _DialPad extends StatelessWidget {
  final void Function(String digit) onDigitPressed;

  const _DialPad({required this.onDigitPressed});

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
            return Padding(
              padding: const EdgeInsets.all(4),
              child: InkWell(
                onTap: () => onDigitPressed(digit),
                borderRadius: BorderRadius.circular(40),
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white12,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    digit,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      }).toList(),
    );
  }
}

class _AudioDeviceTile extends StatelessWidget {
  final AudioDevice device;
  final VoidCallback onTap;

  const _AudioDeviceTile({required this.device, required this.onTap});

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
