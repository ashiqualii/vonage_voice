package com.iocod.vonage.vonage_voice.types

/**
 * Represents the direction of a voice call.
 *
 * This is appended as the last segment in pipe-delimited event strings
 * sent over the EventChannel so the Dart side can distinguish between
 * an inbound and outbound call without extra parsing logic.
 *
 * Event string examples:
 *   "Ringing|+14155551234|+14158765432|Incoming"
 *   "Connected|+14155551234|+14158765432|Outgoing"
 *
 * Usage:
 *   val direction = if (isInbound) CallDirection.INCOMING else CallDirection.OUTGOING
 *   eventSink.success("Ringing|$from|$to|${direction.value}")
 */
enum class CallDirection(val value: String) {

    /** Call was received from a remote party — inbound. */
    INCOMING("Incoming"),

    /** Call was placed by the local user — outbound. */
    OUTGOING("Outgoing");

    companion object {

        /**
         * Safely resolve a raw string (e.g. from a stored Intent extra)
         * back to a [CallDirection] enum entry.
         *
         * Defaults to [INCOMING] if the string is unrecognised, since
         * an unknown inbound call is safer to surface than silently dropping it.
         */
        fun fromValue(value: String): CallDirection =
            entries.firstOrNull { it.value == value } ?: INCOMING
    }
}