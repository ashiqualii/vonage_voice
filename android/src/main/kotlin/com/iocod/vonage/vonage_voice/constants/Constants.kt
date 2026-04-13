package com.iocod.vonage.vonage_voice.constants

object Constants {

    // ── Method channel argument keys ──────────────────────────────────────
    const val PARAM_JWT          = "jwt"
    const val PARAM_FCM_TOKEN    = "deviceToken"
    const val PARAM_TO           = "to"
    const val PARAM_FROM         = "from"
    const val PARAM_CALL_ID      = "callId"
    const val PARAM_DIGITS       = "digits"
    const val PARAM_SPEAKER_IS_ON = "speakerIsOn"
    const val PARAM_BLUETOOTH_ON  = "bluetoothOn"
    const val PARAM_MUTED        = "muted"
    const val PARAM_DEFAULT_CALLER = "defaultCaller"
    const val PARAM_CLIENT_ID    = "id"
    const val PARAM_CLIENT_NAME  = "name"
    const val PARAM_SHOW         = "show"
    const val PARAM_SHOULD_REJECT = "shouldReject"
    const val PARAM_DEVICE_ID      = "deviceId"

    // ── SharedPreferences ─────────────────────────────────────────────────
    const val PREFS_NAME                  = "com.iocod.vonage.vonage_voicePreferences"
    const val KEY_DEFAULT_CALLER          = "defaultCaller"
    const val KEY_REJECT_ON_NO_PERMISSIONS = "rejectOnNoPermissions"
    const val KEY_SHOW_NOTIFICATIONS      = "show-notifications"
    const val CLIENT_ID_PREFIX             = "client_"

    // ── Default display values ────────────────────────────────────────────
    const val DEFAULT_UNKNOWN_CALLER = "Unknown"

    // ── Foreground service notification ───────────────────────────────────
    const val NOTIFICATION_ID           = 101
    const val NOTIFICATION_CHANNEL_ID   = "vonage_voice_channel"
    const val NOTIFICATION_CHANNEL_NAME = "Vonage Voice Calls"
    const val INCOMING_CALL_CHANNEL_ID   = "vonage_incoming_call_channel_v2"
    const val INCOMING_CALL_CHANNEL_NAME = "Vonage Incoming Calls"
    /** Old channel ID that had sound/vibration — delete on startup. */
    const val INCOMING_CALL_CHANNEL_ID_OLD = "vonage_incoming_call_channel"

    // ── Intent actions: Flutter → TVConnectionService ─────────────────────
    const val ACTION_INCOMING_CALL      = "com.iocod.vonage.ACTION_INCOMING_CALL"
    const val ACTION_CANCEL_CALL_INVITE = "com.iocod.vonage.ACTION_CANCEL_CALL_INVITE"
    const val ACTION_PLACE_OUTGOING_CALL = "com.iocod.vonage.ACTION_PLACE_OUTGOING_CALL"
    const val ACTION_ANSWER             = "com.iocod.vonage.ACTION_ANSWER"
    const val ACTION_HANGUP             = "com.iocod.vonage.ACTION_HANGUP"
    const val ACTION_SEND_DIGITS        = "com.iocod.vonage.ACTION_SEND_DIGITS"
    const val ACTION_TOGGLE_SPEAKER     = "com.iocod.vonage.ACTION_TOGGLE_SPEAKER"
    const val ACTION_TOGGLE_BLUETOOTH   = "com.iocod.vonage.ACTION_TOGGLE_BLUETOOTH"
    const val ACTION_TOGGLE_MUTE        = "com.iocod.vonage.ACTION_TOGGLE_MUTE"
    const val ACTION_CLEANUP            = "com.iocod.vonage.ACTION_CLEANUP"

    // ── Intent extra keys ─────────────────────────────────────────────────
    const val EXTRA_CALL_ID         = "EXTRA_CALL_ID"
    const val EXTRA_CALL_FROM       = "EXTRA_CALL_FROM"
    const val EXTRA_CALL_TO         = "EXTRA_CALL_TO"
    const val EXTRA_JWT             = "EXTRA_JWT"
    const val EXTRA_OUTGOING_PARAMS = "EXTRA_OUTGOING_PARAMS"
    const val EXTRA_DIGITS          = "EXTRA_DIGITS"
    const val EXTRA_SPEAKER_STATE   = "EXTRA_SPEAKER_STATE"
    const val EXTRA_BLUETOOTH_STATE = "EXTRA_BLUETOOTH_STATE"
    const val EXTRA_MUTE_STATE      = "EXTRA_MUTE_STATE"
    const val EXTRA_FCM_DATA        = "EXTRA_FCM_DATA"
    const val EXTRA_CALL_DIRECTION   = "EXTRA_CALL_DIRECTION"

    // ── LocalBroadcast actions: service → VonageVoicePlugin ──────────────
    const val BROADCAST_CALL_RINGING           = "com.iocod.vonage.CALL_RINGING"
    const val BROADCAST_CALL_CONNECTED         = "com.iocod.vonage.CALL_CONNECTED"
    const val BROADCAST_CALL_ANSWERED          = "com.iocod.vonage.CALL_ANSWERED"
    const val BROADCAST_CALL_ENDED             = "com.iocod.vonage.CALL_ENDED"
    const val BROADCAST_CALL_INVITE            = "com.iocod.vonage.CALL_INVITE"
    const val BROADCAST_CALL_INVITE_CANCELLED  = "com.iocod.vonage.CALL_INVITE_CANCELLED"
    const val BROADCAST_CALL_RECONNECTING      = "com.iocod.vonage.CALL_RECONNECTING"
    const val BROADCAST_CALL_RECONNECTED       = "com.iocod.vonage.CALL_RECONNECTED"
    const val BROADCAST_CALL_FAILED            = "com.iocod.vonage.CALL_FAILED"
    const val BROADCAST_MUTE_STATE             = "com.iocod.vonage.MUTE_STATE"
    const val BROADCAST_SPEAKER_STATE          = "com.iocod.vonage.SPEAKER_STATE"
    const val BROADCAST_BLUETOOTH_STATE        = "com.iocod.vonage.BLUETOOTH_STATE"
    const val BROADCAST_SYSTEM_DISCONNECT      = "com.iocod.vonage.SYSTEM_DISCONNECT"
    const val BROADCAST_NEW_FCM_TOKEN          = "com.iocod.vonage.NEW_FCM_TOKEN"
    const val BROADCAST_PERMISSION_RESULT      = "com.iocod.vonage.PERMISSION_RESULT"
    /** Sent by TVConnectionService when the real callId is available after placeholder startup. */
    const val BROADCAST_REAL_CALL_READY        = "com.iocod.vonage.REAL_CALL_READY"

    const val ACTION_NOTIFICATION_ANSWER  = "com.iocod.vonage.NOTIFICATION_ANSWER"
    const val ACTION_NOTIFICATION_DECLINE = "com.iocod.vonage.NOTIFICATION_DECLINE"
}