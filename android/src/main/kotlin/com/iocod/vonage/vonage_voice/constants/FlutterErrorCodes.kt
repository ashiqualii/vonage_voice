package com.iocod.vonage.vonage_voice.constants
/**
 * Error codes passed to Flutter via result.error(code, message, details).
 *
 * Usage example:
 *   result.error(FlutterErrorCodes.UNAVAILABLE_ERROR, "No active call", null)
 *
 * On the Dart side, catch these as PlatformException.code.
 */
object FlutterErrorCodes {

    // ── General errors ────────────────────────────────────────────────────

    /** A required resource (call, client, context) is not available. */
    const val UNAVAILABLE_ERROR = "UNAVAILABLE_ERROR"

    /** The operation was called with a missing or invalid argument. */
    const val INVALID_PARAMS = "INVALID_PARAMS"

    /** The Vonage VoiceClient has not been initialized (createSession not called). */
    const val CLIENT_NOT_INITIALISED = "CLIENT_NOT_INITIALISED"

    // ── Session / auth errors ─────────────────────────────────────────────

    /** createSession() failed — JWT may be invalid or expired. */
    const val SESSION_ERROR = "SESSION_ERROR"

    /** refreshSession() failed. */
    const val SESSION_REFRESH_ERROR = "SESSION_REFRESH_ERROR"

    // ── Call errors ───────────────────────────────────────────────────────

    /** No active call exists when the operation requires one. */
    const val NO_ACTIVE_CALL = "NO_ACTIVE_CALL"

    /** serverCall() / answer() failed at the SDK level. */
    const val CALL_ERROR = "CALL_ERROR"

    /** hangup() failed at the SDK level. */
    const val HANGUP_ERROR = "HANGUP_ERROR"

    // ── Push / FCM errors ─────────────────────────────────────────────────

    /** registerDevicePushToken() failed. */
    const val PUSH_REGISTRATION_ERROR = "PUSH_REGISTRATION_ERROR"

    /** processPushCallInvite() received an unrecognized payload. */
    const val PUSH_PROCESSING_ERROR = "PUSH_PROCESSING_ERROR"

    // ── Permission errors ─────────────────────────────────────────────────

    /** A required Android permission has been denied. */
    const val PERMISSION_DENIED = "PERMISSION_DENIED"

    /** The Telecom PhoneAccount has not been registered or enabled. */
    const val PHONE_ACCOUNT_ERROR = "PHONE_ACCOUNT_ERROR"
}