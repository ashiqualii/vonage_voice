package com.iocod.vonage.vonage_voice.fcm

import android.content.Intent
import android.os.Build 
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
        println("VonageFirebaseMessagingService created")
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

        // ── Create VoiceClient if app was killed ──────────────────────────
        var client = VonageClientHolder.voiceClient
        val clientWasNull = client == null
        if (client == null) {
            android.util.Log.w("VonageFCM", "VoiceClient null — creating for background")
            client = VoiceClient(applicationContext)
            VonageClientHolder.voiceClient = client
        }

        // Only register the listener when we just created the client (app was killed).
        // When the plugin is alive it has already set its own listener in
        // registerVoiceClientListeners() — overwriting it here would break
        // the foreground incoming call path.
        if (clientWasNull) {
            client.setCallInviteListener { callId, from, channelType ->
                android.util.Log.d("VonageFCM", "🔔 setCallInviteListener FIRED — callId: $callId from: $from")
                // Prefer the display name extracted from the push payload.
                val displayFrom = VonageClientHolder.pendingCallerDisplay ?: from
                VonageClientHolder.pendingCallerDisplay = null
                val intent = Intent(applicationContext, TVConnectionService::class.java).apply {
                    action = Constants.ACTION_INCOMING_CALL
                    putExtra(Constants.EXTRA_CALL_ID, callId)
                    putExtra(Constants.EXTRA_CALL_FROM, displayFrom)
                    putExtra(Constants.EXTRA_CALL_TO, "")
                }
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        android.util.Log.d("VonageFCM", "Starting foreground service for incoming call")
                        applicationContext.startForegroundService(intent)
                    } else {
                        applicationContext.startService(intent)
                    }
                } catch (e: Exception) {
                    android.util.Log.e("VonageFCM", "Error starting service: ${e.message}")
                }
            }
        }

        android.util.Log.d("VonageFCM", "Calling processPushCallInvite...")
        try {
            val callId = client.processPushCallInvite(dataString)
            android.util.Log.d("VonageFCM", "processPushCallInvite returned: $callId")
            // A null/empty callId is NORMAL — the SDK processes the push
            // asynchronously and fires setCallInviteListener when ready.
            // Null just means "no synchronous callId available", not failure.
            if (!callId.isNullOrEmpty()) {
                android.util.Log.d("VonageFCM", "✅ Incoming call processed with callId: $callId")
            } else {
                android.util.Log.d("VonageFCM", "ℹ️ processPushCallInvite returned null — waiting for setCallInviteListener callback")
            }
        } catch (e: Exception) {
            android.util.Log.e("VonageFCM", "❌ processPushCallInvite threw: ${e.message}")
        }
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
}