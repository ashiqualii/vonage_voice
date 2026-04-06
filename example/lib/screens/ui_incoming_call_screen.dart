import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vonage_voice/vonage_voice.dart';
import 'ui_active_call_screen.dart';
import 'widgets/animated_ring.dart';

/// Full-screen incoming call UI with animated ring around caller avatar.
///
/// Listens to call events for auto-navigation:
/// - [CallEvent.connected] → push [ActiveCallScreen]
/// - [CallEvent.callEnded] / [CallEvent.missedCall] / [CallEvent.declined] → pop
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

  Future<void> _answer() async {
    if (_navigated) return;
    _navigated = true;
    final result = await VonageVoice.instance.call.answer();
    if (!mounted) return;
    if (result != true) {
      _navigated = false;
      return;
    }
    final call = VonageVoice.instance.call.activeCall ?? widget.activeCall;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => ActiveCallScreen(activeCall: call)),
    );
  }

  Future<void> _decline() async {
    if (_navigated) return;
    _navigated = true;
    await VonageVoice.instance.call.hangUp();
    if (mounted) Navigator.of(context).pop();
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '?';
    if (name.startsWith('+') ||
        name.codeUnits.every((c) =>
            (c >= 48 && c <= 57) || c == 32 || c == 45 || c == 40 || c == 41)) {
      return '#';
    }
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0].toUpperCase()}${parts[1][0].toUpperCase()}';
    }
    return parts[0][0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final callerDisplay = widget.activeCall.fromFormatted.isNotEmpty
        ? widget.activeCall.fromFormatted
        : widget.activeCall.from;

    return Scaffold(
      backgroundColor: const Color(0xFF1B1B2F),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),

            // ── "Call from" label ──────────────────────────────────────
            const Text(
              'Call from',
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
            const SizedBox(height: 8),

            // ── Caller name ───────────────────────────────────────────
            Text(
              callerDisplay,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),

            // ── Caller number ─────────────────────────────────────────
            if (widget.activeCall.from != callerDisplay)
              Text(
                widget.activeCall.from,
                style: const TextStyle(color: Colors.white54, fontSize: 16),
              ),
            const SizedBox(height: 12),

            const Text(
              'Incoming Call…',
              style: TextStyle(color: Colors.white38, fontSize: 14),
            ),

            const Spacer(flex: 1),

            // ── Animated ring with initials ───────────────────────────
            AnimatedRing(
              isConnected: false,
              size: 180,
              child: Container(
                width: 100,
                height: 100,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF346299),
                ),
                alignment: Alignment.center,
                child: Text(
                  _getInitials(callerDisplay),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            const Spacer(flex: 2),

            // ── Answer / Decline buttons ──────────────────────────────
            Padding(
              padding: const EdgeInsets.only(bottom: 60),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Accept
                  _CallActionButton(
                    icon: Icons.call,
                    label: 'Accept',
                    color: const Color(0xFF4CAF50),
                    onTap: _answer,
                  ),
                  // Decline
                  _CallActionButton(
                    icon: Icons.call_end,
                    label: 'Decline',
                    color: const Color(0xFFF44336),
                    onTap: _decline,
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

class _CallActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _CallActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
            child: Icon(icon, color: Colors.white, size: 30),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
      ],
    );
  }
}
