package com.iocod.vonage.vonage_voice.receivers

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.firebase.messaging.FirebaseMessaging
import com.iocod.vonage.vonage_voice.service.VonageClientHolder
import com.vonage.voice.api.VoiceClient

/**
 * BootCompletedReceiver — re-registers Vonage push token after device reboot.
 *
 * After a reboot, the app process is killed and the Vonage backend no longer
 * knows where to send incoming call push notifications. This receiver:
 *
 *   1. Reads the stored JWT from SharedPreferences
 *   2. Creates a VoiceClient and restores the session
 *   3. Gets the current FCM token
 *   4. Re-registers it with Vonage via registerDevicePushToken()
 *
 * This ensures incoming calls work immediately after reboot, without the
 * user needing to manually open the app.
 *
 * directBootAware=true ensures it also receives LOCKED_BOOT_COMPLETED.
 * However, SharedPreferences (credential-encrypted storage) is only
 * available after the user unlocks the device. For LOCKED_BOOT_COMPLETED,
 * we skip re-registration and rely on BOOT_COMPLETED firing later.
 */
class BootCompletedReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "BootCompletedReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        Log.d(TAG, "onReceive: action=$action")

        when (action) {
            Intent.ACTION_LOCKED_BOOT_COMPLETED -> {
                // Device is still locked — credential-encrypted storage (SharedPreferences)
                // is not yet available. We can't read the JWT or re-register.
                // BOOT_COMPLETED will fire after unlock and handle re-registration.
                Log.d(TAG, "LOCKED_BOOT_COMPLETED — skipping (storage not available yet)")
            }

            Intent.ACTION_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON" -> {
                Log.d(TAG, "Device booted — restoring Vonage session and FCM registration")
                restoreSessionAndRegisterPush(context.applicationContext)
            }
        }
    }

    /**
     * Restore the Vonage VoiceClient session from the stored JWT, then
     * re-register the FCM push token so incoming call pushes are delivered.
     */
    private fun restoreSessionAndRegisterPush(context: Context) {
        val storedJwt = VonageClientHolder.getStoredJwt(context)
        if (storedJwt.isNullOrEmpty()) {
            Log.d(TAG, "No stored JWT — user never logged in or logged out. Skipping.")
            return
        }

        // Use goAsync() to extend the BroadcastReceiver's lifecycle beyond
        // the default 10-second ANR timeout while we do async network calls.
        val pendingResult = goAsync()

        try {
            // Create a VoiceClient if one doesn't exist (app was killed)
            var client = VonageClientHolder.voiceClient
            if (client == null) {
                Log.d(TAG, "Creating VoiceClient for boot re-registration")
                client = VoiceClient(context)
                VonageClientHolder.voiceClient = client
            }

            // Restore the session
            Log.d(TAG, "Restoring Vonage session...")
            client.createSession(storedJwt) { error, sessionId ->
                if (error != null) {
                    Log.e(TAG, "Session restore failed: ${error.message}")
                    pendingResult.finish()
                    return@createSession
                }

                Log.d(TAG, "Session restored: $sessionId")
                VonageClientHolder.isSessionReady = true

                // Get the current FCM token and re-register with Vonage
                FirebaseMessaging.getInstance().token
                    .addOnSuccessListener { fcmToken ->
                        if (fcmToken.isNullOrEmpty()) {
                            Log.w(TAG, "FCM token is null/empty — cannot register push")
                            pendingResult.finish()
                            return@addOnSuccessListener
                        }

                        Log.d(TAG, "FCM token obtained — registering with Vonage...")

                        // Unregister old device first to avoid max-device-limit
                        val oldDeviceId = VonageClientHolder.getStoredDeviceId(context)
                        if (!oldDeviceId.isNullOrEmpty()) {
                            client.unregisterDevicePushToken(oldDeviceId) { unregError ->
                                if (unregError != null) {
                                    Log.w(TAG, "Old device unregister failed (non-fatal): ${unregError.message}")
                                }
                                registerToken(client, context, fcmToken, pendingResult)
                            }
                        } else {
                            registerToken(client, context, fcmToken, pendingResult)
                        }
                    }
                    .addOnFailureListener { e ->
                        Log.e(TAG, "Failed to get FCM token: ${e.message}")
                        pendingResult.finish()
                    }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Boot re-registration failed: ${e.message}", e)
            pendingResult.finish()
        }
    }

    private fun registerToken(
        client: VoiceClient,
        context: Context,
        fcmToken: String,
        pendingResult: PendingResult
    ) {
        client.registerDevicePushToken(fcmToken) { tokenError, deviceId ->
            if (tokenError != null) {
                Log.e(TAG, "Push token registration failed: ${tokenError.message}")
            } else if (deviceId != null) {
                VonageClientHolder.storeDeviceId(context, deviceId)
                Log.d(TAG, "Push token registered successfully. deviceId=$deviceId")
            }
            pendingResult.finish()
        }
    }
}
