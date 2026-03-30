part of '../vonage_voice.dart';

/// The type of audio output device.
enum AudioDeviceType {
  /// Built-in earpiece (default for voice calls).
  earpiece,

  /// Built-in loudspeaker.
  speaker,

  /// Bluetooth device (SCO, A2DP, LE Audio, or HFP).
  bluetooth,

  /// Wired headset or headphones (3.5mm jack or USB-C).
  wiredHeadset,

  /// Unknown or unrecognised device type.
  unknown,
}

/// Represents a single audio output device available to the system.
///
/// Returned by [VonageVoice.instance.call.getAudioDevices].
///
/// Each device has a [type], a human-readable [name], and an [isActive]
/// flag indicating whether it is the currently selected audio output.
///
/// Multiple Bluetooth devices may appear in the list if more than one
/// is paired and connected simultaneously.
///
/// ```dart
/// final devices = await VonageVoice.instance.call.getAudioDevices();
/// for (final device in devices) {
///   print('${device.name} (${device.type}) — active: ${device.isActive}');
/// }
/// ```
class AudioDevice {
  /// The category of audio device.
  final AudioDeviceType type;

  /// Human-readable name of the device.
  ///
  /// For Bluetooth: the device's advertised name (e.g. "AirPods Pro").
  /// For built-in devices: "Earpiece", "Speaker", or similar.
  /// For wired: "Wired Headset" or "Headphones".
  final String name;

  /// `true` if this device is the currently active audio output.
  final bool isActive;

  /// Platform-specific device identifier.
  ///
  /// On Android: the `AudioDeviceInfo.id` (int as string).
  /// On iOS: the `AVAudioSessionPortDescription.uid`.
  ///
  /// Used internally by [selectAudioDevice] to address the correct device.
  final String id;

  const AudioDevice({
    required this.type,
    required this.name,
    required this.isActive,
    required this.id,
  });

  /// Creates an [AudioDevice] from a platform map.
  factory AudioDevice.fromMap(Map<String, dynamic> map) {
    return AudioDevice(
      type: _parseType(map['type'] as String? ?? 'unknown'),
      name: map['name'] as String? ?? 'Unknown',
      isActive: map['isActive'] as bool? ?? false,
      id: map['id'] as String? ?? '',
    );
  }

  static AudioDeviceType _parseType(String type) {
    switch (type) {
      case 'earpiece':
        return AudioDeviceType.earpiece;
      case 'speaker':
        return AudioDeviceType.speaker;
      case 'bluetooth':
        return AudioDeviceType.bluetooth;
      case 'wiredHeadset':
        return AudioDeviceType.wiredHeadset;
      default:
        return AudioDeviceType.unknown;
    }
  }

  @override
  String toString() => 'AudioDevice($type, "$name", active=$isActive, id=$id)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioDevice &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          type == other.type;

  @override
  int get hashCode => id.hashCode ^ type.hashCode;
}
