package com.iocod.vonage.vonage_voice.types

/**
 * Enum of every method name the Flutter side can invoke over the MethodChannel.
 *
 * The [methodName] property must exactly match the string used in Dart:
 *   _channel.invokeMethod('tokens', {...})
 *
 * Usage in VonageVoicePlugin.onMethodCall():
 *   when (VNMethodChannels.fromMethodName(call.method)) {
 *       VNMethodChannels.TOKENS -> handleTokens(call, result)
 *       ...
 *   }
 */
enum class VNMethodChannels(val methodName: String) {

    // ── Session / registration ────────────────────────────────────────────

    /** Register JWT + optional FCM token. Starts the Vonage session. */
    TOKENS("tokens"),

    /** Unregister FCM push token and end the Vonage session. */
    UNREGISTER("unregister"),

    /** Refresh an expiring JWT without destroying the session. */
    REFRESH_SESSION("refreshSession"),

    // ── Core call controls ────────────────────────────────────────────────

    /** Place an outbound call via serverCall(). */
    MAKE_CALL("makeCall"),

    /** Hang up the active call. */
    HANG_UP("hangUp"),

    /** Answer a pending incoming call invite. */
    ANSWER("answer"),

    /** Send DTMF tones on the active call. */
    SEND_DIGITS("sendDigits"),

    // ── Audio routing ─────────────────────────────────────────────────────

    /** Route audio to / from the speakerphone. */
    TOGGLE_SPEAKER("toggleSpeaker"),

    /** Returns true if audio is currently routed to the speaker. */
    IS_ON_SPEAKER("isOnSpeaker"),

    /** Route audio to / from a Bluetooth headset. */
    TOGGLE_BLUETOOTH("toggleBluetooth"),

    /** Returns true if audio is currently routed via Bluetooth. */
    IS_BLUETOOTH_ON("isBluetoothOn"),

    /** Returns true if a Bluetooth audio device is connected and available. */
    IS_BLUETOOTH_AVAILABLE("isBluetoothAvailable"),

    /** Returns true if the device's Bluetooth adapter is enabled. */
    IS_BLUETOOTH_ENABLED("isBluetoothEnabled"),

    /** Shows the native "Turn on Bluetooth?" dialog. */
    SHOW_BLUETOOTH_ENABLE_PROMPT("showBluetoothEnablePrompt"),

    /** Opens Bluetooth settings to pair/connect devices. */
    OPEN_BLUETOOTH_SETTINGS("openBluetoothSettings"),

    /** Returns a list of all available audio output devices. */
    GET_AUDIO_DEVICES("getAudioDevices"),

    /** Selects a specific audio output device by platform ID. */
    SELECT_AUDIO_DEVICE("selectAudioDevice"),

    // ── Mute ─────────────────────────────────────────────────────────────

    /** Mute or unmute the microphone. */
    TOGGLE_MUTE("toggleMute"),

    /** Returns true if the microphone is currently muted. */
    IS_MUTED("isMuted"),

    // ── Call state queries ────────────────────────────────────────────────

    /** Returns true if there is an active call in progress. */
    IS_ON_CALL("isOnCall"),

    /** Returns the active call ID string, or null if no call is active. */
    CALL_SID("call-sid"),

    // ── Caller identity registry ──────────────────────────────────────────

    /** Store a display name for a caller ID. */
    REGISTER_CLIENT("registerClient"),

    /** Remove a stored caller ID → name mapping. */
    UNREGISTER_CLIENT("unregisterClient"),

    /** Set the fallback display name shown when the caller is unknown. */
    DEFAULT_CALLER("defaultCaller"),

    // ── Telecom / PhoneAccount ────────────────────────────────────────────

    /** Returns true if a Telecom PhoneAccount is registered. */
    HAS_REGISTERED_PHONE_ACCOUNT("hasRegisteredPhoneAccount"),

    /** Register this app as a call-capable account with the Android Telecom system. */
    REGISTER_PHONE_ACCOUNT("registerPhoneAccount"),

    /** Returns true if the PhoneAccount is enabled by the user in system settings. */
    IS_PHONE_ACCOUNT_ENABLED("isPhoneAccountEnabled"),

    /** Open the system phone account settings screen. */
    OPEN_PHONE_ACCOUNT_SETTINGS("openPhoneAccountSettings"),

    // ── Permissions ───────────────────────────────────────────────────────

    HAS_MIC_PERMISSION("hasMicPermission"),
    REQUEST_MIC_PERMISSION("requestMicPermission"),

    HAS_READ_PHONE_STATE_PERMISSION("hasReadPhoneStatePermission"),
    REQUEST_READ_PHONE_STATE_PERMISSION("requestReadPhoneStatePermission"),

    HAS_CALL_PHONE_PERMISSION("hasCallPhonePermission"),
    REQUEST_CALL_PHONE_PERMISSION("requestCallPhonePermission"),

    HAS_READ_PHONE_NUMBERS_PERMISSION("hasReadPhoneNumbersPermission"),
    REQUEST_READ_PHONE_NUMBERS_PERMISSION("requestReadPhoneNumbersPermission"),

    HAS_MANAGE_OWN_CALLS_PERMISSION("hasManageOwnCallsPermission"),
    REQUEST_MANAGE_OWN_CALLS_PERMISSION("requestManageOwnCallsPermission"),

    // ── Notification / behaviour settings ────────────────────────────────

    /** Show or hide the ongoing call notification. */
    SHOW_NOTIFICATIONS("showNotifications"),

    /** Configure whether to auto-reject calls when permissions are missing. */
    REJECT_CALL_ON_NO_PERMISSIONS("rejectCallOnNoPermissions"),

    /** Returns the current auto-reject setting. */
    IS_REJECTING_CALL_ON_NO_PERMISSIONS("isRejectingCallOnNoPermissions"),

    // ── Bluetooth permission (API 31+) ─────────────────────────────────

    /** Returns true if BLUETOOTH_CONNECT permission is granted (API 31+). */
    HAS_BLUETOOTH_PERMISSION("hasBluetoothPermission"),

    /** Request BLUETOOTH_CONNECT runtime permission (API 31+). */
    REQUEST_BLUETOOTH_PERMISSION("requestBluetoothPermission"),

    /** Returns true if POST_NOTIFICATIONS permission is granted (API 33+). */
    HAS_NOTIFICATION_PERMISSION("hasNotificationPermission"),

    /** Request POST_NOTIFICATIONS runtime permission (API 33+). */
    REQUEST_NOTIFICATION_PERMISSION("requestNotificationPermission"),

    /** No-op — ConnectionService replaced custom background UI. */
    BACKGROUND_CALL_UI("backgroundCallUi"),

    /** No-op — iOS only stub, not used on Android. */
    UPDATE_CALL_KIT_ICON("updateCallKitIcon"),

    /** Forward an FCM push payload to VoiceClient.processPushCallInvite(). */
    PROCESS_PUSH("processVonagePush"),

    // ── Battery / power optimization ──────────────────────────────────────

    /** Returns true if the app is exempt from battery optimization. */
    IS_BATTERY_OPTIMIZED("isBatteryOptimized"),

    /** Opens the system intent to request battery optimization exemption. */
    REQUEST_BATTERY_OPTIMIZATION_EXEMPTION("requestBatteryOptimizationExemption"),

    // ── Full-screen intent permission (API 34+) ──────────────────────────

    /** Returns true if USE_FULL_SCREEN_INTENT is granted. */
    CAN_USE_FULL_SCREEN_INTENT("canUseFullScreenIntent"),

    /** Opens system settings for USE_FULL_SCREEN_INTENT permission. */
    OPEN_FULL_SCREEN_INTENT_SETTINGS("openFullScreenIntentSettings"),

    // ── Overlay / "Display over other apps" permission ───────────────────

    /** Returns true if SYSTEM_ALERT_WINDOW (draw over other apps) is granted. */
    CAN_DRAW_OVERLAYS("canDrawOverlays"),

    /** Opens system settings for SYSTEM_ALERT_WINDOW permission. */
    OPEN_OVERLAY_SETTINGS("openOverlaySettings"),

    /**
     * Re-emits the current call state (pending invite or active connection)
     * to Flutter after a terminated-state restart.
     * Mirrors Twilio's `getActiveCallOnResumeFromTerminatedState`.
     * Returns true if native has an active call.
     */
    GET_ACTIVE_CALL_ON_RESUME("getActiveCallOnResumeFromTerminatedState");

    companion object {
        /**
         * Safely resolve a raw method name string to its enum entry.
         * Returns null if the method name is not recognised — the plugin
         * should call result.notImplemented() in that case.
         */
        fun fromMethodName(name: String): VNMethodChannels? =
            entries.firstOrNull { it.methodName == name }
    }
}