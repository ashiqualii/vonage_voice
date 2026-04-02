package com.iocod.vonage.vonage_voice.types

import com.iocod.vonage.vonage_voice.types.CallDirection
import com.iocod.vonage.vonage_voice.types.VNNativeCallEvents

/**
 * All event strings emitted to Flutter via EventChannel.
 *
 * Events are pipe-delimited strings: "TYPE|data1|data2|..."
 * The Dart side splits on "|" and reads each segment positionally.
 *
 * ─────────────────────────────────────────────────────────────────────────
 * CALL STATE EVENTS
 * ─────────────────────────────────────────────────────────────────────────
 *
 *  Ringing    → "Ringing|<from>|<to>|<direction>"
 *  Connected  → "Connected|<from>|<to>|<direction>"
 *  Incoming   → "Incoming|<from>|<to>|Incoming|<customParams>"
 *  Answer     → "Answer|<from>|<to>"
 *  Call Ended → "Call Ended"
 *  Missed     → "Missed Call"
 *  Rejected   → "Call Rejected"
 *  Reconnect  → "Reconnecting" / "Reconnected"
 *  Error      → "Call Error: <message>"
 *  Hold       → "Hold"
 *  Unhold     → "Unhold"
 *
 * ─────────────────────────────────────────────────────────────────────────
 * AUDIO STATE EVENTS
 * ─────────────────────────────────────────────────────────────────────────
 *
 *  Mute state     → "Mute" / "Unmute"
 *  Speaker state  → "Speaker On" / "Speaker Off"
 *  Bluetooth state→ "Bluetooth On" / "Bluetooth Off"
 *
 * ─────────────────────────────────────────────────────────────────────────
 * PERMISSION EVENTS
 * ─────────────────────────────────────────────────────────────────────────
 *
 *  Permission result → "PERMISSION|<name>|<true|false>"
 *  e.g.              → "PERMISSION|Microphone|true"
 *                    → "PERMISSION|Call Phone|false"
 *
 * ─────────────────────────────────────────────────────────────────────────
 */
object VNNativeCallEvents {

    // ── Separator used in all pipe-delimited event strings ────────────────
    const val SEPARATOR = "|"

    // ── Call state events ─────────────────────────────────────────────────

    /** Call is ringing — inbound or outbound. Append: |from|to|direction */
    const val EVENT_RINGING = "Ringing"

    /** Call media connected. Append: |from|to|direction */
    const val EVENT_CONNECTED = "Connected"

    /** Incoming call invite received. Append: |from|to|Incoming|customParams */
    const val EVENT_INCOMING = "Incoming"

    /** User answered the call. Append: |from|to */
    const val EVENT_ANSWER = "Answer"

    /** Call ended — local hangup or remote disconnect. */
    const val EVENT_CALL_ENDED = "Call Ended"

    /** Call was not answered in time. */
    const val EVENT_MISSED_CALL = "Missed Call"

    /** Call was explicitly rejected. */
    const val EVENT_CALL_REJECTED = "Call Rejected"

    /** Network reconnect started. */
    const val EVENT_RECONNECTING = "Reconnecting"

    /** Network reconnect succeeded. */
    const val EVENT_RECONNECTED = "Reconnected"

    /**
     * Call-level error. Build full string as:
     *   "Call Error: $message"
     */
    const val EVENT_CALL_ERROR_PREFIX = "Call Error: "

    // ── Audio state events ────────────────────────────────────────────────

    const val EVENT_MUTE        = "Mute"
    const val EVENT_UNMUTE      = "Unmute"
    const val EVENT_SPEAKER_ON  = "Speaker On"
    const val EVENT_SPEAKER_OFF = "Speaker Off"
    const val EVENT_BT_ON       = "Bluetooth On"
    const val EVENT_BT_OFF      = "Bluetooth Off"

    // ── Permission events ─────────────────────────────────────────────────

    /** Prefix for all permission result events. */
    const val EVENT_PERMISSION_PREFIX = "PERMISSION"

    /** Permission label strings — match what the Dart side expects. */
    const val PERMISSION_MICROPHONE         = "Microphone"
    const val PERMISSION_CALL_PHONE         = "Call Phone"
    const val PERMISSION_READ_PHONE_STATE   = "Read Phone State"
    const val PERMISSION_READ_PHONE_NUMBERS = "Read Phone Numbers"
    const val PERMISSION_MANAGE_CALLS       = "Manage Calls"
    const val PERMISSION_BLUETOOTH_CONNECT  = "Bluetooth Connect"
    const val PERMISSION_NOTIFICATIONS      = "Notifications"

    // ── Helper builders ───────────────────────────────────────────────────

    /**
     * Build a ringing or connected event string.
     *
     * Example output: "Ringing|+14155551234|+14158765432|Incoming"
     */
    fun callStateEvent(
        type: String,
        from: String,
        to: String,
        direction: CallDirection
    ): String = "$type$SEPARATOR$from$SEPARATOR$to$SEPARATOR${direction.value}"

    /**
     * Build an incoming call invite event string.
     *
     * Example output: "Incoming|+14155551234|+14158765432|Incoming|customKey=val"
     */
    fun incomingCallEvent(
        from: String,
        to: String,
        customParams: String = ""
    ): String = "$EVENT_INCOMING$SEPARATOR$from$SEPARATOR$to${SEPARATOR}Incoming$SEPARATOR$customParams"

    /**
     * Build a permission result event string.
     *
     * Example output: "PERMISSION|Microphone|true"
     */
    fun permissionEvent(permissionLabel: String, granted: Boolean): String =
        "$EVENT_PERMISSION_PREFIX$SEPARATOR$permissionLabel$SEPARATOR$granted"

    /**
     * Build a call error event string.
     *
     * Example output: "Call Error: Authorization failed"
     */
    fun callErrorEvent(message: String): String =
        "$EVENT_CALL_ERROR_PREFIX$message"
}