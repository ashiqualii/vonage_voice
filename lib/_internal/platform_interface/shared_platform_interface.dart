import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../method_channel/shared_platform_method_channel.dart';
import '../utils.dart';

/// Base platform interface shared by both [VonageVoicePlatform] and
/// [VonageCallPlatform].
///
/// Holds the [MethodChannel] and [EventChannel] instances used for
/// all communication between Flutter and native Android code.
///
/// Channel names:
///   MethodChannel → "vonage_voice/messages"
///   EventChannel  → "vonage_voice/events"
abstract class SharedPlatformInterface extends PlatformInterface {
  // ── Channel names ─────────────────────────────────────────────────────

  static const _kMethodChannelName = 'vonage_voice/messages';
  static const kEventChannelName = 'vonage_voice/events';

  // ── Flutter channels ──────────────────────────────────────────────────

  /// MethodChannel for sending commands from Flutter → native.
  MethodChannel get sharedChannel => _sharedChannel;
  final MethodChannel _sharedChannel = const MethodChannel(_kMethodChannelName);

  /// EventChannel for receiving events from native → Flutter.
  EventChannel get eventChannel => _eventChannel;
  final EventChannel _eventChannel = const EventChannel(kEventChannelName);

  // ── Internal event stream ─────────────────────────────────────────────

  /// Internal broadcast StreamController that bridges the native
  /// EventChannel into a Dart stream that can have multiple listeners.
  // ignore: close_sinks
  StreamController<String>? _callEventsController;

  StreamController<String> get callEventsController {
    _callEventsController ??= StreamController<String>.broadcast();
    return _callEventsController!;
  }

  /// Raw string event stream — pipe-delimited strings from native.
  /// Consumed internally by [VonageVoicePlatform.callEventsListener]
  /// which maps strings → [CallEvent] enum values.
  Stream<String> get callEventsStream => callEventsController.stream;

  // ── Constructor ───────────────────────────────────────────────────────

  SharedPlatformInterface({required super.token});

  static final Object _token = Object();

  static SharedPlatformInterface _instance = MethodChannelSharedPlatform(
    token: _token,
  );

  static SharedPlatformInterface get instance => _instance;

  static set instance(SharedPlatformInterface instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  // ── Local event helpers ───────────────────────────────────────────────

  /// Logs a list of event entries joined by [separator] into the event stream.
  ///
  /// Used to inject synthetic events into the existing communication flow.
  /// Format: "prefix|entry1|entry2|..."
  void logLocalEventEntries(
    List<String> entries, {
    String prefix = "LOG",
    String separator = "|",
  }) {
    logLocalEvent(
      entries.join(separator),
      prefix: prefix,
      separator: separator,
    );
  }

  /// Logs a single string event into the internal event stream.
  ///
  /// On non-web platforms this injects directly into [callEventsController].
  /// Format: "prefix|description" or just "description" if prefix is empty.
  void logLocalEvent(
    String description, {
    String prefix = "LOG",
    String separator = "|",
  }) async {
    if (!kIsWeb) {
      throw UnimplementedError(
        "Use eventChannel() via sendPhoneEvents on platform implementation",
      );
    }

    final message = prefix.isEmpty
        ? description
        : "$prefix$separator$description";

    printDebug("Sending event: $message");
    callEventsController.add(message);
  }
}
