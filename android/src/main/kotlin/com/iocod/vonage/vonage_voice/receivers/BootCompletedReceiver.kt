package com.iocod.vonage.vonage_voice.receivers

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import com.google.firebase.messaging.FirebaseMessaging
import com.iocod.vonage.vonage_voice.service.VonageClientHolder

/**
 * BootCompletedReceiver — ensures Firebase Messaging is initialized after device reboot.
 *
 * After a reboot the Firebase service needs to be woken so the device can
 * receive FCM push messages for incoming calls. This is the ONLY job of this
 * receiver — getting the FCM token re-initializes the Firebase subsystem.
 *
 * The FCM token itself does NOT change on reboot, so no re-registration with
 * Vonage is needed here. When an actual call push arrives, VonageFirebaseMessagingService
 * handles session restore and call processing from scratch.
 *
 * ── DEBUGGING ────────────────────────────────────────────────────────────
 * Filter logcat:   adb logcat -s VonageBoot:V VonageFCM:V TVConnectionService:V
 * Checkpoint tags: [BOOT-1] receiver fired → [BOOT-2] FCM token retrieved
 *                  then on incoming call: [FCM-1]→[FCM-2]→[FCM-3]→[FCM-4]→[FCM-5]
 */
class BootCompletedReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "VonageBoot"
    }

    override fun onReceive(context: Context, intent: Intent) {
        // Log every intent received so we can confirm the receiver is firing at all
        Log.i(TAG, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        Log.i(TAG, "[BOOT-0] onReceive called, action=${intent.action}")
        Log.i(TAG, "[BOOT-0] Device: ${Build.MANUFACTURER} ${Build.MODEL} (Android ${Build.VERSION.RELEASE} / API ${Build.VERSION.SDK_INT})")

        val recognized = intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == Intent.ACTION_LOCKED_BOOT_COMPLETED ||
            intent.action == "android.intent.action.QUICKBOOT_POWERON" ||
            intent.action == "com.htc.intent.action.QUICKBOOT_POWERON"

        if (!recognized) {
            Log.w(TAG, "[BOOT-0] Action not recognized — ignoring")
            return
        }

        Log.i(TAG, "[BOOT-1] ✓ Boot action recognized: ${intent.action}")

        // Check if a JWT is stored — if not, answering an incoming call after
        // reboot will fail even if the notification appears.
        val storedJwt = VonageClientHolder.getStoredJwt(context)
        if (storedJwt.isNullOrEmpty()) {
            Log.w(TAG, "[BOOT-1] ⚠ No stored JWT found — user must login before calls will work after reboot")
        } else {
            Log.i(TAG, "[BOOT-1] ✓ Stored JWT present (${storedJwt.length} chars) — session can be restored on incoming call")
        }

        Log.i(TAG, "[BOOT-1] isSessionReady=${VonageClientHolder.isSessionReady}, voiceClient=${if (VonageClientHolder.voiceClient != null) "set" else "null"}")

        try {
            Log.i(TAG, "[BOOT-2] Triggering FCM token fetch to wake Firebase Messaging...")

            FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                if (task.isSuccessful) {
                    val token = task.result
                    Log.i(TAG, "[BOOT-2] ✓ FCM token retrieved: ${token?.take(20)}... (Firebase Messaging is active)")
                } else {
                    Log.e(TAG, "[BOOT-2] ✗ FCM token fetch failed — incoming calls may not deliver after reboot", task.exception)
                }
            }

            FirebaseMessaging.getInstance().isAutoInitEnabled = true
            Log.i(TAG, "[BOOT-2] FCM autoInit=true — token rotation will be delivered to VonageFirebaseMessagingService")
            Log.i(TAG, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        } catch (e: Exception) {
            Log.e(TAG, "[BOOT-2] ✗ Exception initializing Firebase after boot", e)
        }
    }
}

