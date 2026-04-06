import 'package:flutter/material.dart';

/// Reusable call control toggle button (mute, speaker, bluetooth, etc.)
///
/// Shows a circular icon with a label underneath.
/// When [active] is true, the circle is filled white with dark icon.
/// When disabled ([onTap] is null), the widget is semi-transparent.
class StateToggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;
  final Color? iconColor;

  const StateToggle({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.4,
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                color: iconColor ?? (active ? Colors.black87 : Colors.white),
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
