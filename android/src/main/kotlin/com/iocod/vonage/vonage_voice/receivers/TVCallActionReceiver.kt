package com.iocod.vonage.vonage_voice.receivers

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat
import com.iocod.vonage.vonage_voice.constants.Constants
import com.iocod.vonage.vonage_voice.service.TVConnectionService

class TVCallActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val callId = intent.getStringExtra(Constants.EXTRA_CALL_ID) ?: return

        val serviceIntent = Intent(context, TVConnectionService::class.java).apply {
            action = when (intent.action) {
                Constants.ACTION_NOTIFICATION_ANSWER  -> Constants.ACTION_ANSWER
                Constants.ACTION_NOTIFICATION_DECLINE -> Constants.ACTION_HANGUP
                else -> return
            }
            putExtra(Constants.EXTRA_CALL_ID, callId)
        }
        // Must use startForegroundService — on Android 10+ the
        // notification tap runs in a background context.
        ContextCompat.startForegroundService(context, serviceIntent)
    }
}