package com.iocod.vonage.vonage_voice.fcm

import android.content.Intent
import androidx.localbroadcastmanager.content.LocalBroadcastManager
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.iocod.vonage.vonage_voice.constants.Constants
import com.iocod.vonage.vonage_voice.service.VonageClientHolder
import com.vonage.voice.api.VoiceClient

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

        val data = remoteMessage.data
        if (data.isEmpty()) return

        // Check if this FCM message is a Vonage voice push
        if (!VoiceClient.Companion.isPushNotification(data)) return

        // Get VoiceClient instance held by the plugin
        // If the app was killed and restarted by FCM, the client may not
        // be initialised yet — in that case we cannot process the invite
        val client = VonageClientHolder.voiceClient ?: run {
            broadcastError("VoiceClient not initialised — cannot process push invite")
            return
        }

        // Process the push payload — this validates the invite and fires
        // the callInviteListener that was registered in VonageVoicePlugin
        val callId = client.processPushCallInvite(data.toString())

        if (callId.isNullOrEmpty()) {
            broadcastError("processPushCallInvite returned null callId")
            return
        }

        // The actual BROADCAST_CALL_INVITE is sent by the callInviteListener
        // in VonageVoicePlugin once the SDK confirms the invite is valid.
        // We do not broadcast here to avoid double-firing.
    }

    // ── Broadcast helpers ─────────────────────────────────────────────────

    private fun broadcastError(message: String) {
        val intent = Intent(Constants.BROADCAST_CALL_FAILED).apply {
            putExtra("error", message)
        }
        broadcastManager.sendBroadcast(intent)
    }
}