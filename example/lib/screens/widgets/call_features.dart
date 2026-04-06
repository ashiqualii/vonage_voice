import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vonage_voice/vonage_voice.dart';
import 'state_toggle.dart';

/// Call control features — mute, speaker, bluetooth, audio picker, keypad, hangup.
///
/// Listens to [VonageVoice.instance.callEventsListener] and syncs state
/// from the native layer via `Future.wait()` on each relevant event.
class CallFeatures extends StatefulWidget {
  final bool callReady;
  final VoidCallback? onShowDialpad;
  final VoidCallback? onShowAudioPicker;
  final bool showDialpad;

  const CallFeatures({
    super.key,
    required this.callReady,
    this.onShowDialpad,
    this.onShowAudioPicker,
    this.showDialpad = false,
  });

  @override
  State<CallFeatures> createState() => _CallFeaturesState();
}

class _CallFeaturesState extends State<CallFeatures> {
  late final StreamSubscription<CallEvent> _subscription;

  bool _muted = false;
  bool _speaker = false;
  bool _bluetooth = false;

  final _vn = VonageVoice.instance;

  @override
  void initState() {
    super.initState();
    _syncState();
    _subscription = _vn.callEventsListener.listen((event) {
      switch (event) {
        case CallEvent.mute:
        case CallEvent.unmute:
        case CallEvent.speakerOn:
        case CallEvent.speakerOff:
        case CallEvent.bluetoothOn:
        case CallEvent.bluetoothOff:
        case CallEvent.connected:
        case CallEvent.callEnded:
        case CallEvent.reconnecting:
        case CallEvent.audioRouteChanged:
          _syncState();
          break;
        default:
          break;
      }
    });
  }

  Future<void> _syncState() async {
    final results = await Future.wait<bool?>([
      _vn.call.isMuted(),
      _vn.call.isOnSpeaker(),
      _vn.call.isBluetoothOn(),
    ]);
    if (!mounted) return;
    setState(() {
      _muted = results[0] ?? false;
      _speaker = results[1] ?? false;
      _bluetooth = results[2] ?? false;
    });
  }

  Future<void> _toggleMute() async {
    if (!widget.callReady) return;
    await _vn.call.toggleMute(!_muted);
  }

  Future<void> _toggleSpeaker() async {
    if (!widget.callReady) return;
    await _vn.call.toggleSpeaker(!_speaker);
  }

  Future<void> _toggleBluetooth() async {
    if (!widget.callReady) return;
    if (_bluetooth) {
      await _vn.call.toggleBluetooth(bluetoothOn: false);
      return;
    }
    final btEnabled = await _vn.call.isBluetoothEnabled() ?? false;
    if (!btEnabled) {
      final userEnabled = await _vn.call.showBluetoothEnablePrompt() ?? false;
      if (!userEnabled) return;
      await Future.delayed(const Duration(seconds: 2));
    }
    final btAvail = await _vn.call.isBluetoothAvailable() ?? false;
    if (btAvail) {
      await _vn.call.toggleBluetooth(bluetoothOn: true);
    } else {
      await _vn.call.openBluetoothSettings();
    }
    _syncState();
  }

  Future<void> _hangUp() async {
    await _vn.call.hangUp();
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Row 1 — Mute, Speaker, Bluetooth
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            StateToggle(
              icon: _muted ? Icons.mic_off : Icons.mic,
              label: _muted ? 'Unmute' : 'Mute',
              active: _muted,
              onTap: widget.callReady ? _toggleMute : null,
            ),
            StateToggle(
              icon: _speaker ? Icons.volume_up : Icons.volume_down,
              label: 'Speaker',
              active: _speaker,
              onTap: widget.callReady ? _toggleSpeaker : null,
            ),
            StateToggle(
              icon: Icons.bluetooth_audio,
              label: 'Bluetooth',
              active: _bluetooth,
              onTap: widget.callReady ? _toggleBluetooth : null,
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Row 2 — Audio Devices, Keypad
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            StateToggle(
              icon: Icons.speaker_group,
              label: 'Audio',
              active: false,
              onTap: widget.callReady ? widget.onShowAudioPicker : null,
            ),
            StateToggle(
              icon: Icons.dialpad,
              label: 'Keypad',
              active: widget.showDialpad,
              onTap: widget.onShowDialpad,
            ),
          ],
        ),
        const SizedBox(height: 32),

        // Hang up button
        FloatingActionButton(
          heroTag: 'hangup',
          backgroundColor: Colors.red,
          onPressed: _hangUp,
          child: const Icon(Icons.call_end, color: Colors.white, size: 32),
        ),
      ],
    );
  }
}
