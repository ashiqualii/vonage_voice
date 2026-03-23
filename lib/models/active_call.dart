part of '../vonage_voice.dart';

/// Represents the direction of a voice call.
enum CallDirection {
  /// Call received from a remote party
  incoming,

  /// Call placed by the local user
  outgoing,
}

/// Holds the state of the currently active or pending voice call.
///
/// Created and updated automatically by [VonageVoice] when call
/// events are received from the native layer.
///
/// Access via:
/// ```dart
/// final activeCall = VonageVoice.instance.call.activeCall;
/// print(activeCall?.from);     // caller number
/// print(activeCall?.to);       // callee number
/// print(activeCall?.initiated); // call start time
/// ```
class ActiveCall {
  /// Raw destination number / identity (client: prefix stripped)
  final String to;

  /// Human-readable formatted destination number
  final String toFormatted;

  /// Raw caller number / identity (client: prefix stripped)
  final String from;

  /// Human-readable formatted caller number
  final String fromFormatted;

  /// Timestamp when the call was connected.
  /// Only set after a [CallEvent.connected] event.
  final DateTime? initiated;

  /// Whether this is an inbound or outbound call
  final CallDirection callDirection;

  /// Optional custom parameters passed from your Vonage backend.
  /// Only available after [CallEvent.ringing] and [CallEvent.answer] events.
  final Map<String, dynamic>? customParams;

  ActiveCall({
    required String from,
    required String to,
    this.initiated,
    required this.callDirection,
    this.customParams,
  }) : to = to.replaceAll("client:", ""),
       from = from.replaceAll("client:", ""),
       toFormatted = _prettyPrintNumber(to),
       fromFormatted = _prettyPrintNumber(from);

  /// Formats a raw phone number or client identity into a readable string.
  ///
  /// Examples:
  ///   "+14155551234"   → "(415) 555-1234"
  ///   "client:alice"  → "alice"
  ///   "1234567"       → "123-4567"
  static String _prettyPrintNumber(String phoneNumber) {
    if (phoneNumber.isEmpty) return "";

    // Strip client: prefix — show just the identity name
    if (phoneNumber.contains('client:')) {
      return phoneNumber.split(':')[1];
    }

    // Strip leading +
    if (phoneNumber.substring(0, 1) == '+') {
      phoneNumber = phoneNumber.substring(1);
    }

    // 7-digit local number
    if (phoneNumber.length == 7) {
      return "${phoneNumber.substring(0, 3)}-${phoneNumber.substring(3)}";
    }

    // Shorter than 10 digits — return as-is
    if (phoneNumber.length < 10) return phoneNumber;

    // 10 or 11 digit number — format as (NXX) NXX-XXXX
    int start = 0;
    if (phoneNumber.length == 11) start = 1;

    return "(${phoneNumber.substring(start, start + 3)}) "
        "${phoneNumber.substring(start + 3, start + 6)}-"
        "${phoneNumber.substring(start + 6)}";
  }

  @override
  String toString() {
    return 'ActiveCall{'
        'to: $to, '
        'toFormatted: $toFormatted, '
        'from: $from, '
        'fromFormatted: $fromFormatted, '
        'initiated: $initiated, '
        'callDirection: $callDirection, '
        'customParams: $customParams'
        '}';
  }
}
