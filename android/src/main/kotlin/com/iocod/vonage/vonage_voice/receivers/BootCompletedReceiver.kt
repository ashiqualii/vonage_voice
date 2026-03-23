package com.iocod.vonage.vonage_voice.receivers

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * BootCompletedReceiver — re-initializes after device reboot.
 *
 * After a reboot, the app process is killed and FCM token may need
 * re-registration. This receiver fires on BOOT_COMPLETED (and vendor-
 * specific quickboot actions) to ensure the app can receive incoming
 * call push notifications as soon as possible after reboot.
 *
 * directBootAware=true ensures it also receives LOCKED_BOOT_COMPLETED
 * on devices with file-based encryption — the user doesn't need to
 * unlock the device for this receiver to fire.
 *
 * Note: The actual Vonage client re-registration happens when
 * VonageVoicePlugin is initialized by Flutter. This receiver simply
 * ensures the app process is started so that the FCM service is active.
 */
class BootCompletedReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "BootCompletedReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        Log.d(TAG, "onReceive: action=$action")

        when (action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON" -> {
                Log.d(TAG, "Device booted — app process started for FCM delivery")
                // The act of receiving this broadcast starts the app process,
                // ensuring FirebaseMessagingService is registered and can
                // receive incoming call pushes. No further action needed here.
            }
        }
    }
}
