import 'dart:async';
import 'package:flutter/material.dart';

/// Displays call status text and a running call timer.
///
/// The timer starts from [callStartTime] and updates every second.
class CallStatusWidget extends StatefulWidget {
  final String statusText;
  final DateTime? callStartTime;
  final bool isConnected;
  final bool bluetoothOn;
  final bool speakerOn;

  const CallStatusWidget({
    super.key,
    required this.statusText,
    this.callStartTime,
    this.isConnected = false,
    this.bluetoothOn = false,
    this.speakerOn = false,
  });

  @override
  State<CallStatusWidget> createState() => _CallStatusWidgetState();
}

class _CallStatusWidgetState extends State<CallStatusWidget> {
  Timer? _timer;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _startTimerIfNeeded();
  }

  @override
  void didUpdateWidget(covariant CallStatusWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isConnected && !oldWidget.isConnected) {
      _startTimerIfNeeded();
    }
    if (!widget.isConnected && oldWidget.isConnected) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _startTimerIfNeeded() {
    if (!widget.isConnected || widget.callStartTime == null) return;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsed = DateTime.now().difference(widget.callStartTime!);
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) return '$hours:$minutes:$seconds';
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.statusText,
          style: const TextStyle(color: Colors.white54, fontSize: 14),
        ),
        if (widget.isConnected && widget.callStartTime != null) ...[
          const SizedBox(height: 4),
          Text(
            _formatDuration(_elapsed),
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 13,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
        if (widget.isConnected) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.bluetoothOn
                    ? Icons.bluetooth_audio
                    : widget.speakerOn
                        ? Icons.volume_up
                        : Icons.hearing,
                color: Colors.white38,
                size: 14,
              ),
              const SizedBox(width: 4),
              Text(
                widget.bluetoothOn
                    ? 'Bluetooth'
                    : widget.speakerOn
                        ? 'Speaker'
                        : 'Earpiece',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
