package com.iocod.vonage.vonage_voice.fcm

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.telecom.TelecomManager
import androidx.localbroadcastmanager.content.LocalBroadcastManager
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.iocod.vonage.vonage_voice.constants.Constants
import com.iocod.vonage.vonage_voice.service.TVConnectionService
import com.iocod.vonage.vonage_voice.service.VonageClientHolder
import com.vonage.voice.api.VoiceClient
import org.json.JSONObject

/**
 * VonageFirebaseMessagingService — FCM to Vonage call invite bridge.
 *
 * Extends [FirebaseMessagingService] to intercept FCM push messages
 * delivered by the Vonage backend when an incoming call arrives.
 *
 * This service runs even when the app is killed or backgrounded,
 * which is why incoming calls can wake the app up.
 *
 * Flow:
 *   Vonage backend
 *     → FCM push message (data payload)
 *       → onMessageReceived()
 *         → VoiceClient.processPushCallInvite()  [validates it is a Vonage call]
 *           → setCallInviteListener fires         [if valid call invite]
 *             → startService(ACTION_INCOMING_CALL) → TVConnectionService
 *               → LocalBroadcast → VonageVoicePlugin → Flutter "Incoming|..." event
 *
 * FCM token lifecycle:
 *   onNewToken() fires when FCM rotates the device token.
 *   We broadcast it via LocalBroadcastManager so VonageVoicePlugin
 *   can re-register it with Vonage via client.registerDevicePushToken().
 *
 * NOTE: Firebase must be configured in your app before this service works:
 *   1. Add google-services.json to android/app/
 *   2. Add Firebase dependencies to build.gradle
 *   3. Connect Vonage app to Firebase in the Vonage dashboard
 *   Until then, this service is registered but will simply receive no messages.
 */
class VonageFirebaseMessagingService : FirebaseMessagingService() {

    private lateinit var broadcastManager: LocalBroadcastManager

    override fun onCreate() {
        super.onCreate()
        broadcastManager = LocalBroadcastManager.getInstance(this)
        android.util.Log.d("VonageFCM", "VonageFirebaseMessagingService created")
    }

    // ── FCM token lifecycle ───────────────────────────────────────────────

    /**
     * Called by FCM when the device push token is created or rotated.
     *
     * We broadcast the new token so VonageVoicePlugin can call
     * client.registerDevicePushToken(token) to keep Vonage in sync.
     *
     * The plugin stores the returned deviceId so it can later call
     * client.unregisterDevicePushToken(deviceId) on logout.
     */
    override fun onNewToken(token: String) {
        super.onNewToken(token)

        val intent = Intent(Constants.BROADCAST_NEW_FCM_TOKEN).apply {
            putExtra(Constants.EXTRA_FCM_DATA, token)
        }
        broadcastManager.sendBroadcast(intent)
    }

    // ── Incoming message handling ─────────────────────────────────────────

    /**
     * Called when an FCM data message is received.
     *
     * We first check if it is a Vonage push message using
     * [VoiceClient.getPushNotificationType]. If it is an incoming call,
     * we process it via [VoiceClient.processPushCallInvite] which triggers
     * the callInviteListener registered in VonageVoicePlugin.
     *
     * Non-Vonage messages are ignored so other FCM channels in your app
     * are not affected.
     */
    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        super.onMessageReceived(remoteMessage)
        android.util.Log.i("VonageFCM", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        android.util.Log.i("VonageFCM", "[FCM-1] onMessageReceived — keys=${remoteMessage.data.keys}")

        val data = remoteMessage.data
        if (data.isEmpty()) {
            android.util.Log.w("VonageFCM", "[FCM-1] Empty data payload — ignoring")
            return
        }

        // ── Cellular call detection ───────────────────────────────────────
        // If the user is already on a cellular (SIM/carrier) call, skip
        // processing the VoIP invite entirely. The call will appear as
        // "missed" on the Vonage side. Without this check, the VoIP call
        // would interrupt the cellular call and both parties would lose audio.
        if (isDeviceInSystemCall()) {
            android.util.Log.w("VonageFCM", "[FCM-1] Device is in a cellular call — skipping VoIP invite")
            return
        }

        // ── Active Vonage call guard ──────────────────────────────────────
        // Vonage is single-call only (no hold/swap/conference). If there is
        // already an active or pending Vonage call, ignore the 2nd invite
        // entirely — it will appear as "missed" on the Vonage side.
        // This also covers cross-provider scenarios: Twilio calls use
        // ConnectionService so they are caught by isDeviceInSystemCall() above.
        if (TVConnectionService.hasActiveCall() || TVConnectionService.pendingInvites.isNotEmpty()) {
            android.util.Log.w("VonageFCM", "[FCM-1] Active Vonage call exists — skipping 2nd VoIP invite")
            return
        }

        // Vonage pushes always contain a "nexmo" key.
        val nexmoRaw = data["nexmo"]
        if (nexmoRaw.isNullOrEmpty()) {
            android.util.Log.d("VonageFCM", "[FCM-1] No 'nexmo' key — not a Vonage push, ignored")
            return
        }
        android.util.Log.i("VonageFCM", "[FCM-2] ✓ Vonage push detected")

        // Record timestamp so the Dart fallback path (processVonagePush)
        // can detect that a native FCM service is already processing this push
        // and skip to avoid double-processing.
        VonageClientHolder.lastNativePushTimestamp = System.currentTimeMillis()

        // ── Acquire WakeLock IMMEDIATELY ──────────────────────────────────
        // The SDK processes the push asynchronously. Without a WakeLock the
        // CPU may go back to sleep before the callback fires — especially
        // on OEMs like Vivo that aggressively suspend background processes.
        val wakeLock = acquireProcessingWakeLock()

        // The Vonage SDK's internal extractJsonFromPushData expects the data
        // in Kotlin Map.toString() format: {nexmo={"type":...}}
        // It does substringAfter("nexmo=").dropLast(1) to extract the JSON.
        // So we pass remoteMessage.data.toString() directly — NOT JSON.
        val dataString = data.toString()
        android.util.Log.d("VonageFCM", "[FCM-2] Data string (first 200): ${dataString.take(200)}")

        // Extract caller display info from the push payload.
        val callerDisplay = extractCallerDisplay(nexmoRaw)
        android.util.Log.i("VonageFCM", "[FCM-2] Caller display: $callerDisplay")

        // Store the display name so both FCM-service and plugin paths can use it.
        if (!callerDisplay.isNullOrEmpty()) {
            VonageClientHolder.pendingCallerDisplay = callerDisplay
        }

        // ── START FOREGROUND SERVICE IMMEDIATELY ──────────────────────────
        // On Android 12+ (API 31), apps have a very short window after
        // onMessageReceived() to call startForegroundService(). The Vonage
        // SDK processes the push asynchronously, so the setCallInviteListener
        // callback may fire AFTER the window closes — causing
        // ForegroundServiceStartNotAllowedException on stock Android or
        // the service simply never starting on aggressive OEMs like Vivo.
        //
        // Fix: start the service NOW with a placeholder intent (no callId).
        // ensureForeground() in TVConnectionService shows a "Processing
        // incoming call…" notification immediately. When processPushCallInvite
        // fires the invite listener, a second intent with real callId is sent
        // and the notification is updated with caller details.
        try {
            val placeholderIntent = Intent(applicationContext, TVConnectionService::class.java).apply {
                action = Constants.ACTION_INCOMING_CALL
                // No EXTRA_CALL_ID — handleIncomingCall will skip creating a
                // pendingInvite, but ensureForeground() already showed the notification.
                putExtra(Constants.EXTRA_CALL_FROM, callerDisplay ?: "Incoming Call")
                putExtra(Constants.EXTRA_CALL_TO, "")
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                android.util.Log.i("VonageFCM", "[FCM-3] Starting placeholder foreground service immediately")
                applicationContext.startForegroundService(placeholderIntent)
            } else {
                applicationContext.startService(placeholderIntent)
            }
            android.util.Log.i("VonageFCM", "[FCM-3] ✓ Placeholder foreground service started")
        } catch (e: Exception) {
            android.util.Log.e("VonageFCM", "[FCM-3] ✗ Failed to start placeholder foreground service: ${e.message}", e)
        }

        var client = VonageClientHolder.voiceClient
        // Treat "client exists but session not ready" the same as "no client" —
        // this handles the boot+unlock race condition where BootCompletedReceiver
        // created the VoiceClient but its async createSession hasn't completed yet.
        val clientWasNull = client == null || !VonageClientHolder.isSessionReady
        android.util.Log.i("VonageFCM", "[FCM-4] Client state: voiceClient=${if (client != null) "set" else "null"}, isSessionReady=${VonageClientHolder.isSessionReady}, clientWasNull=$clientWasNull")
        if (client == null) {
            android.util.Log.i("VonageFCM", "[FCM-4] Creating new VoiceClient (boot/killed path)")
            client = VoiceClient(applicationContext)
            VonageClientHolder.voiceClient = client
            VonageClientHolder.isSessionReady = false
        } else if (!VonageClientHolder.isSessionReady) {
            android.util.Log.w("VonageFCM", "[FCM-4] VoiceClient exists but session not ready (boot race) — will restore session")
        } else {
            android.util.Log.i("VonageFCM", "[FCM-4] VoiceClient alive and session ready — foreground/background path")
        }

        // Guard to prevent both the listener AND the direct processPushCallInvite
        // path from sending duplicate incoming call intents.
        val inviteHandledDirectly = java.util.concurrent.atomic.AtomicBoolean(false)

        // Only register the listener when we just created the client (app was killed).
        // When the plugin is alive it has already set its own listener in
        // registerVoiceClientListeners() — overwriting it here would break
        // the foreground incoming call path.
        if (clientWasNull) {
            client.setCallInviteListener { callId, from, channelType ->
                android.util.Log.i("VonageFCM", "[FCM-6] ✓ setCallInviteListener FIRED — callId=$callId, from=$from, channel=$channelType")

                // If we already handled the invite via processPushCallInvite's
                // returned callId, skip the listener to avoid duplicates.
                if (!inviteHandledDirectly.compareAndSet(false, true)) {
                    android.util.Log.d("VonageFCM", "Invite already handled directly -- skipping listener")
                    releaseProcessingWakeLock(wakeLock)
                    return@setCallInviteListener
                }

                // Prefer the display name extracted from the push payload.
                val displayFrom = VonageClientHolder.pendingCallerDisplay ?: from
                VonageClientHolder.pendingCallerDisplay = null

                // Send the REAL intent with callId — this updates the
                // placeholder notification with Answer/Decline buttons
                // and creates the pendingInvite in TVConnectionService.
                val intent = Intent(applicationContext, TVConnectionService::class.java).apply {
                    action = Constants.ACTION_INCOMING_CALL
                    putExtra(Constants.EXTRA_CALL_ID, callId)
                    putExtra(Constants.EXTRA_CALL_FROM, displayFrom)
                    putExtra(Constants.EXTRA_CALL_TO, "")
                }
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        android.util.Log.d("VonageFCM", "Updating foreground service with real callId")
                        applicationContext.startForegroundService(intent)
                    } else {
                        applicationContext.startService(intent)
                    }
                } catch (e: Exception) {
                    android.util.Log.e("VonageFCM", "Error updating service with callId: ${e.message}", e)
                } finally {
                    releaseProcessingWakeLock(wakeLock)
                }
            }

            // ── Cancel listener for killed-app state ─────────────────────
            // Without this, if the caller cancels or another device answers
            // before the user opens the app, the notification persists.
            client.setCallInviteCancelListener { callId, reason ->
                android.util.Log.d("VonageFCM", "setCallInviteCancelListener FIRED -- callId: $callId, reason: $reason")
                val cancelIntent = Intent(applicationContext, TVConnectionService::class.java).apply {
                    action = Constants.ACTION_CANCEL_CALL_INVITE
                    putExtra(Constants.EXTRA_CALL_ID, callId)
                }
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        applicationContext.startForegroundService(cancelIntent)
                    } else {
                        applicationContext.startService(cancelIntent)
                    }
                } catch (e: Exception) {
                    android.util.Log.e("VonageFCM", "Error sending cancel invite intent: ${e.message}", e)
                }
            }

            // ── Restore session from stored JWT ──────────────────────────
            // When the app was killed, the VoiceClient has no session.
            // Without a session, client.answer() will fail when the user
            // taps Answer. We restore the session FIRST, then process
            // the push — the SDK only registers the invite internally
            // when a valid session exists.
            val storedJwt = VonageClientHolder.getStoredJwt(applicationContext)
            if (!storedJwt.isNullOrEmpty()) {
                android.util.Log.i("VonageFCM", "[FCM-5] Stored JWT found (${storedJwt.length} chars) — restoring session...")
                restoreSessionWithRetry(client, storedJwt, dataString, callerDisplay, clientWasNull, inviteHandledDirectly, wakeLock, retriesLeft = 1)
            } else {
                android.util.Log.e("VonageFCM", "[FCM-5] ✗ No stored JWT — cannot restore session after reboot. User must login first!")
                // No JWT — try processing anyway (will show notification but answer will fail)
                processInviteAndNotify(client, dataString, callerDisplay, clientWasNull, inviteHandledDirectly, wakeLock)
            }
        } else {
            // Client was already alive (app in foreground/background) —
            // process the push inline. If Flutter IS running, its plugin
            // listener handles the invite. If Flutter is NOT running (process
            // alive from a previous FCM but Flutter engine never started), we
            // send the real intent to TVConnectionService directly — otherwise
            // nothing rings and the call appears stuck in "Processing".
            android.util.Log.i("VonageFCM", "[FCM-5] Client alive path — calling processPushCallInvite directly")
            try {
                val callId = client.processPushCallInvite(dataString)
                android.util.Log.i("VonageFCM", "[FCM-5] processPushCallInvite returned: $callId")
                if (!callId.isNullOrEmpty()) {
                    val isNew = VonageClientHolder.markPushProcessed(callId)
                    if (!isNew) {
                        android.util.Log.d("VonageFCM", "[FCM-5] callId=$callId already processed by plugin — skipping")
                    } else if (!VonageClientHolder.isFlutterInForeground) {
                        // Flutter is NOT running — plugin's setCallInviteListener won't fire.
                        // Send the real intent directly so TVConnectionService can ring.
                        val displayFrom = VonageClientHolder.pendingCallerDisplay
                            ?: callerDisplay
                            ?: Constants.DEFAULT_UNKNOWN_CALLER
                        VonageClientHolder.pendingCallerDisplay = null
                        android.util.Log.i("VonageFCM", "[FCM-7] Flutter NOT in foreground — sending real incoming call intent: callId=$callId, from=$displayFrom")
                        val realIntent = Intent(applicationContext, TVConnectionService::class.java).apply {
                            action = Constants.ACTION_INCOMING_CALL
                            putExtra(Constants.EXTRA_CALL_ID, callId)
                            putExtra(Constants.EXTRA_CALL_FROM, displayFrom)
                            putExtra(Constants.EXTRA_CALL_TO, "")
                        }
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                applicationContext.startForegroundService(realIntent)
                            } else {
                                applicationContext.startService(realIntent)
                            }
                            android.util.Log.i("VonageFCM", "[FCM-7] ✓ Real incoming call intent sent (client-alive, Flutter background)")
                        } catch (se: Exception) {
                            android.util.Log.e("VonageFCM", "[FCM-7] Failed to start real intent: ${se.message}", se)
                        }
                    } else {
                        android.util.Log.d("VonageFCM", "[FCM-5] Flutter in foreground — plugin listener will handle callId=$callId")
                    }
                }
            } catch (e: Exception) {
                android.util.Log.e("VonageFCM", "[FCM-5] processPushCallInvite threw: ${e.message}", e)
            }
            releaseProcessingWakeLock(wakeLock)
        }
    }

    /**
     * Process the push invite and send the incoming call intent to TVConnectionService.
     *
     * Called AFTER createSession() completes (or fails) when the app was killed.
     * This ensures the SDK has an active session when it processes the push,
     * so the invite is properly registered and client.answer(callId) will work.
     */
    /**
     * Attempt to restore a Vonage session from a stored JWT.
     *
     * After a device reboot, the network interface may not be fully up
     * when the first FCM push arrives. If [createSession] fails (network
     * error or JWT expiry), we retry once after a 2-second delay before
     * falling back to processing the push without a session (notification
     * will still appear but answering will fail without a valid session).
     */
    private fun restoreSessionWithRetry(
        client: VoiceClient,
        jwt: String,
        dataString: String,
        callerDisplay: String?,
        clientWasNull: Boolean,
        inviteHandledDirectly: java.util.concurrent.atomic.AtomicBoolean,
        wakeLock: PowerManager.WakeLock?,
        retriesLeft: Int
    ) {
        android.util.Log.i("VonageFCM", "[FCM-5a] Calling createSession (retriesLeft=$retriesLeft)...")
        client.createSession(jwt) { error, sessionId ->
            if (error != null) {
                android.util.Log.e("VonageFCM", "[FCM-5a] ✗ createSession failed (retriesLeft=$retriesLeft): ${error.message}")
                if (retriesLeft > 0) {
                    // Network may not be ready immediately after boot — retry after 2s
                    android.util.Log.i("VonageFCM", "[FCM-5a] Retrying createSession in 2000ms...")
                    android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                        restoreSessionWithRetry(client, jwt, dataString, callerDisplay, clientWasNull, inviteHandledDirectly, wakeLock, retriesLeft - 1)
                    }, 2000L)
                } else {
                    android.util.Log.e("VonageFCM", "[FCM-5a] ✗ createSession exhausted retries — processing push WITHOUT valid session (answer may fail)")
                    processInviteAndNotify(client, dataString, callerDisplay, clientWasNull, inviteHandledDirectly, wakeLock)
                }
            } else {
                android.util.Log.i("VonageFCM", "[FCM-5a] ✓ createSession succeeded: sessionId=$sessionId")
                VonageClientHolder.isSessionReady = true
                processInviteAndNotify(client, dataString, callerDisplay, clientWasNull, inviteHandledDirectly, wakeLock)
            }
        }
    }

    private fun processInviteAndNotify(
        client: VoiceClient,
        dataString: String,
        callerDisplay: String?,
        clientWasNull: Boolean,
        inviteHandledDirectly: java.util.concurrent.atomic.AtomicBoolean,
        wakeLock: PowerManager.WakeLock?
    ) {
        android.util.Log.i("VonageFCM", "[FCM-6] Calling processPushCallInvite...")
        try {
            val callId = client.processPushCallInvite(dataString)
            android.util.Log.i("VonageFCM", "[FCM-6] processPushCallInvite returned: $callId")
            if (!callId.isNullOrEmpty()) {
                android.util.Log.d("VonageFCM", "Incoming call processed with callId: $callId")

                if (clientWasNull && inviteHandledDirectly.compareAndSet(false, true)) {
                    val displayFrom = VonageClientHolder.pendingCallerDisplay ?: callerDisplay ?: "Unknown"
                    VonageClientHolder.pendingCallerDisplay = null

                    val realIntent = Intent(applicationContext, TVConnectionService::class.java).apply {
                        action = Constants.ACTION_INCOMING_CALL
                        putExtra(Constants.EXTRA_CALL_ID, callId)
                        putExtra(Constants.EXTRA_CALL_FROM, displayFrom)
                        putExtra(Constants.EXTRA_CALL_TO, "")
                    }
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            android.util.Log.i("VonageFCM", "[FCM-7] ✓ Sending real incoming call intent: callId=$callId, from=$displayFrom")
                            applicationContext.startForegroundService(realIntent)
                        } else {
                            applicationContext.startService(realIntent)
                        }
                        android.util.Log.i("VonageFCM", "[FCM-7] ✓ Incoming call intent sent — notification + ringtone should appear")
                        android.util.Log.i("VonageFCM", "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    } catch (e: Exception) {
                        android.util.Log.e("VonageFCM", "[FCM-7] ✗ Error sending real incoming call intent: ${e.message}", e)
                    }
                }
            } else {
                android.util.Log.i("VonageFCM", "[FCM-6] processPushCallInvite returned null — waiting for setCallInviteListener to fire")
            }
        } catch (e: Exception) {
            android.util.Log.e("VonageFCM", "[FCM-6] ✗ processPushCallInvite threw: ${e.message}", e)
        }
        releaseProcessingWakeLock(wakeLock)
    }

    // ── Push payload helpers ────────────────────────────────────────────────

    /**
     * Build data string in Kotlin Map.toString() format from an FCM data map.
     *
     * The Vonage SDK's internal `extractJsonFromPushData` expects:
     *   `{nexmo={"type":"member:invited",...}}`
     * It does `substringAfter("nexmo=").dropLast(1)` to extract the JSON.
     *
     * When called from the native `onMessageReceived`, we can use
     * `remoteMessage.data.toString()` directly. This helper exists for
     * the Dart fallback path where the data arrives as a re-constructed map.
     */
    @Suppress("unused")
    private fun buildNestedJson(data: Map<String, String>): String {
        return data.toString()
    }

    /**
     * Extract the caller display name from the Vonage push payload.
     *
     * Priority:
     *   1. push_info.from_user.display_name  (app-to-app calls)
     *   2. body.channel.from.number          (PSTN calls)
     */
    private fun extractCallerDisplay(nexmoRaw: String): String? {
        return try {
            val json = JSONObject(nexmoRaw)
            // App-to-app: push_info.from_user.display_name
            val fromUser = json.optJSONObject("push_info")
                ?.optJSONObject("from_user")
            val displayName = fromUser?.optString("display_name", null)
            if (!displayName.isNullOrEmpty()) return displayName

            // PSTN: body.channel.from.number
            json.optJSONObject("body")
                ?.optJSONObject("channel")
                ?.optJSONObject("from")
                ?.optString("number", null)
        } catch (_: Exception) {
            null
        }
    }

    // ── Broadcast helpers ─────────────────────────────────────────────────

    private fun broadcastError(message: String) {
        val intent = Intent(Constants.BROADCAST_CALL_FAILED).apply {
            putExtra("error", message)
        }
        broadcastManager.sendBroadcast(intent)
    }

    // ── WakeLock helpers ──────────────────────────────────────────────────

    /**
     * Acquire a partial WakeLock to keep the CPU alive while the Vonage SDK
     * processes the push asynchronously. Without this, aggressive OEMs like
     * Vivo may put the CPU back to sleep before setCallInviteListener fires.
     *
     * The lock auto-releases after 30 seconds as a safety net.
     */
    private fun acquireProcessingWakeLock(): PowerManager.WakeLock? {
        return try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            pm.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "VonageVoice:FCMProcessing"
            ).apply {
                acquire(30_000L) // 30s timeout safety net
            }
        } catch (e: Exception) {
            android.util.Log.e("VonageFCM", "Failed to acquire WakeLock: ${e.message}")
            null
        }
    }

    private fun releaseProcessingWakeLock(wakeLock: PowerManager.WakeLock?) {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock.release()
            }
        } catch (e: Exception) {
            android.util.Log.e("VonageFCM", "Failed to release WakeLock: ${e.message}")
        }
    }

    // ── Cellular call detection ───────────────────────────────────────────

    /**
     * Returns true if the device is currently in a cellular (SIM/carrier) call.
     *
     * Uses [TelecomManager.isInManagedCall] (API 31+) which returns true when
     * the user is on a carrier-managed call. On older APIs, falls back to
     * [TelecomManager.isInCall] which also detects VoIP calls registered via
     * ConnectionService, but that's acceptable since we don't want to interrupt
     * ANY active call.
     */
    private fun isDeviceInSystemCall(): Boolean {
        return try {
            val telecomManager = getSystemService(Context.TELECOM_SERVICE) as? TelecomManager
                ?: return false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                telecomManager.isInManagedCall
            } else {
                @Suppress("DEPRECATION")
                telecomManager.isInCall
            }
        } catch (e: SecurityException) {
            // READ_PHONE_STATE permission may not be granted — assume no call
            android.util.Log.w("VonageFCM", "isDeviceInSystemCall: SecurityException — ${e.message}")
            false
        } catch (e: Exception) {
            android.util.Log.w("VonageFCM", "isDeviceInSystemCall: ${e.message}")
            false
        }
    }
}