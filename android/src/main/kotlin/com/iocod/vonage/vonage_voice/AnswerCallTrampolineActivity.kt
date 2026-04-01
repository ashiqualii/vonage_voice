package com.iocod.vonage.vonage_voice

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.appcompat.app.AppCompatActivity
import com.iocod.vonage.vonage_voice.constants.Constants
import com.iocod.vonage.vonage_voice.service.TVConnectionService

/**
 * AnswerCallTrampolineActivity — invisible activity for answering from notification.
 *
 * On Android 12+ (API 31), background activity start restrictions prevent
 * launching the Flutter MainActivity directly from a foreground service or
 * broadcast receiver. This invisible trampoline Activity is launched via
 * PendingIntent.getActivity() from the notification's "Answer" button.
 *
 * Flow:
 *   1. User taps "Answer" on notification
 *   2. System launches this Activity (transparent, no UI)
 *   3. Sends ACTION_ANSWER to TVConnectionService
 *   4. Launches MainActivity from an Activity context (bypasses background start restriction)
 *   5. Finishes immediately
 *
 * Uses Theme.Vonage.Transparent so the user sees no screen transition. 
 */
class AnswerCallTrampolineActivity : AppCompatActivity() {

    companion object {
        private const val TAG = "AnswerTrampoline"
        const val EXTRA_CALL_ID = "EXTRA_CALL_ID"
        const val EXTRA_CALLER_NAME = "EXTRA_CALLER_NAME"
        const val EXTRA_CALLER_NUMBER = "EXTRA_CALLER_NUMBER"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val callId = intent.getStringExtra(EXTRA_CALL_ID) ?: ""
        val callerName = intent.getStringExtra(EXTRA_CALLER_NAME) ?: ""
        val callerNumber = intent.getStringExtra(EXTRA_CALLER_NUMBER) ?: callerName
        Log.d(TAG, "onCreate: callId=$callId, callerName=$callerName")

        if (callId.isEmpty()) {
            Log.e(TAG, "No callId — finishing")
            finish()
            return
        }

        // Step 1: Send ACTION_ANSWER to TVConnectionService
        val answerIntent = Intent(this, TVConnectionService::class.java).apply {
            action = Constants.ACTION_ANSWER
            putExtra(Constants.EXTRA_CALL_ID, callId)
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(answerIntent)
            } else {
                startService(answerIntent)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to send ACTION_ANSWER: ${e.message}")
        }

        // Step 2: Launch MainActivity from this Activity context
        // This works on Android 12+ because we're launching from a foreground Activity.
        try {
            val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            launchIntent?.let { launch ->
                launch.flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                launch.putExtra("fromIncomingCall", true)
                launch.putExtra("callHandle", callId)
                launch.putExtra("callAnswered", true)
                launch.putExtra(Constants.EXTRA_CALL_ID, callId)
                launch.putExtra(Constants.EXTRA_CALL_FROM, callerName)
                launch.putExtra(Constants.EXTRA_CALL_DIRECTION, "incoming")
                startActivity(launch)
                Log.d(TAG, "Launched MainActivity")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to launch MainActivity: ${e.message}")
        }

        // Step 3: Finish immediately (invisible)
        finish()
    }
}
