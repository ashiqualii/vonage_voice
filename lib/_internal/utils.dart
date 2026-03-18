import 'dart:developer';

import 'package:flutter/foundation.dart';

/// Prints [message] to the console only in debug mode.
///
/// Wraps [debugPrint] so logs are automatically stripped
/// from release builds and don't pollute production output.
///
/// Usage:
/// ```dart
/// printDebug('Call connected: $callId');
/// ```
void printDebug(String message) {
  if (kDebugMode) {
    log('[VonageVoice] $message');
  }
}
