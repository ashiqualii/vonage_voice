package com.iocod.vonage.vonage_voice.fcm

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
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
        android.util.Log.d("VonageFCM", "=== onMessageReceived CALLED ===")

        val data = remoteMessage.data
        if (data.isEmpty()) {
            android.util.Log.d("VonageFCM", "Empty data — ignoring")
            return
        }

        // Vonage pushes always contain a "nexmo" key.
        val nexmoRaw = data["nexmo"]
        if (nexmoRaw.isNullOrEmpty()) {
            android.util.Log.d("VonageFCM", "No 'nexmo' key — not a Vonage push, ignored")
            return
        }
        android.util.Log.d("VonageFCM", "Vonage push detected (has 'nexmo' key)")

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
        android.util.Log.d("VonageFCM", "Data string for SDK (first 200 chars): ${dataString.take(200)}")

        // Extract caller display info from the push payload.
        val callerDisplay = extractCallerDisplay(nexmoRaw)
        android.util.Log.d("VonageFCM", "Caller display extracted: $callerDisplay")

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
                android.util.Log.d("VonageFCM", "Starting placeholder foreground service IMMEDIATELY")
                applicationContext.startForegroundService(placeholderIntent)
            } else {
                applicationContext.startService(placeholderIntent)
            }
        } catch (e: Exception) {
            android.util.Log.e("VonageFCM", "Failed to start placeholder foreground service: ${e.message}", e)
        }

        // ── Create VoiceClient if app was killed ──────────────────────────
        var client = VonageClientHolder.voiceClient
        val clientWasNull = client == null
        if (client == null) {
            android.util.Log.w("VonageFCM", "VoiceClient null -- creating for background")
            client = VoiceClient(applicationContext)
            VonageClientHolder.voiceClient = client
            VonageClientHolder.isSessionReady = false
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
                android.util.Log.d("VonageFCM", "setCallInviteListener FIRED -- callId: $callId, from: $from")

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
                android.util.Log.d("VonageFCM", "Restoring session from stored JWT...")
                client.createSession(storedJwt) { error, sessionId ->
                    if (error != null) {
                        android.util.Log.e("VonageFCM", "Background createSession failed: ${error.message}")
                        // Session failed — still try processPushCallInvite as fallback
                        processInviteAndNotify(client, dataString, callerDisplay, clientWasNull, inviteHandledDirectly, wakeLock)
                    } else {
                        android.util.Log.d("VonageFCM", "Background session created: $sessionId")
                        VonageClientHolder.isSessionReady = true
                        // NOW process the push — session is active so the SDK
                        // will properly register the invite for answer().
                        processInviteAndNotify(client, dataString, callerDisplay, clientWasNull, inviteHandledDirectly, wakeLock)
                    }
                }
            } else {
                android.util.Log.w("VonageFCM", "No stored JWT -- answer will fail without session")
                // No JWT — try processing anyway (will show notification but answer will fail)
                processInviteAndNotify(client, dataString, callerDisplay, clientWasNull, inviteHandledDirectly, wakeLock)
            }
        } else {
            // Client was already alive (app in foreground/background) —
            // process the push inline. The plugin's own listener handles the invite.
            android.util.Log.d("VonageFCM", "Calling processPushCallInvite (client alive)...")
            try {
                val callId = client.processPushCallInvite(dataString)
                android.util.Log.d("VonageFCM", "processPushCallInvite returned: $callId")
                // Deduplicate: if the plugin already processed this push via Dart forwarding, skip.
                if (!callId.isNullOrEmpty() && !VonageClientHolder.markPushProcessed(callId)) {
                    android.util.Log.d("VonageFCM", "callId=$callId already processed by plugin — skipping")
                }
            } catch (e: Exception) {
                android.util.Log.e("VonageFCM", "processPushCallInvite threw: ${e.message}", e)
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
    private fun processInviteAndNotify(
        client: VoiceClient,
        dataString: String,
        callerDisplay: String?,
        clientWasNull: Boolean,
        inviteHandledDirectly: java.util.concurrent.atomic.AtomicBoolean,
        wakeLock: PowerManager.WakeLock?
    ) {
        android.util.Log.d("VonageFCM", "Calling processPushCallInvite (after session restore)...")
        try {
            val callId = client.processPushCallInvite(dataString)
            android.util.Log.d("VonageFCM", "processPushCallInvite returned: $callId")
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
                            android.util.Log.d("VonageFCM", "Sending incoming call intent with real callId: $callId")
                            applicationContext.startForegroundService(realIntent)
                        } else {
                            applicationContext.startService(realIntent)
                        }
                    } catch (e: Exception) {
                        android.util.Log.e("VonageFCM", "Error sending real incoming call intent: ${e.message}", e)
                    }
                }
            } else {
                android.util.Log.d("VonageFCM", "processPushCallInvite returned null -- waiting for listener")
            }
        } catch (e: Exception) {
            android.util.Log.e("VonageFCM", "processPushCallInvite threw: ${e.message}", e)
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
}