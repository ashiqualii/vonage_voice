part of '../vonage_voice.dart';

/// Manages a list of active [CallSession]s.
///
/// One source of truth per call. Mirrors how the native layers work:
/// - Android: `activeConnections: HashMap<String, TVCallConnection>`
/// - iOS: `activeCalls: [UUID: String]`
class CallSessionManager {
  final List<CallSession> _sessions = [];

  // ---------------------------------------------------------------------------
  // Mutations
  // ---------------------------------------------------------------------------

  /// Adds a new call session. No-op if a session with the same callSid exists.
  void addSession(CallSession session) {
    if (_sessions.any((s) => s.callSid == session.callSid)) return;
    _sessions.add(session);
  }

  /// Removes the session with the given [callSid].
  void removeSession(String callSid) {
    _sessions.removeWhere((s) => s.callSid == callSid);
  }

  /// Updates the [CallStatus] of the session identified by [callSid].
  void updateStatus(String callSid, CallStatus status) {
    final index = _sessions.indexWhere((s) => s.callSid == callSid);
    if (index == -1) return;
    _sessions[index] = _sessions[index].copyWith(status: status);
  }

  /// Generic update — applies [updater] to the session with [callSid].
  void updateSession(
      String callSid, CallSession Function(CallSession) updater) {
    final index = _sessions.indexWhere((s) => s.callSid == callSid);
    if (index == -1) return;
    _sessions[index] = updater(_sessions[index]);
  }

  /// Removes all sessions.
  void clear() {
    _sessions.clear();
  }

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

  /// Returns the session with the given [callSid], or `null` if not found.
  CallSession? getSession(String callSid) {
    for (final s in _sessions) {
      if (s.callSid == callSid) return s;
    }
    return null;
  }

  /// The currently active (connected) call session, or `null`.
  CallSession? get activeSession {
    for (final s in _sessions) {
      if (s.status == CallStatus.active) return s;
    }
    return null;
  }

  /// The currently ringing call session, or `null`.
  CallSession? get ringingSession {
    for (final s in _sessions) {
      if (s.status == CallStatus.ringing) return s;
    }
    return null;
  }

  /// All sessions (unmodifiable view).
  List<CallSession> get allSessions => List.unmodifiable(_sessions);

  /// Number of tracked sessions.
  int get sessionCount => _sessions.length;

  /// Whether there are any sessions at all.
  bool get hasSessions => _sessions.isNotEmpty;

  /// Whether a ringing call exists.
  bool get hasRingingCall =>
      _sessions.any((s) => s.status == CallStatus.ringing);

  @override
  String toString() {
    return 'CallSessionManager{sessions: $_sessions}';
  }
}
