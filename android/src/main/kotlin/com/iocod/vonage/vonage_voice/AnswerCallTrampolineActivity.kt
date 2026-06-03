package com.iocod.vonage.vonage_voice

import android.Manifest
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
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
 *   3. Checks RECORD_AUDIO + READ_PHONE_STATE permissions
 *   4. Sends ACTION_ANSWER to TVConnectionService
 *   5. Launches MainActivity from an Activity context (bypasses background start restriction)
 *   6. Finishes immediately
 *
 * Uses Theme.Vonage.Transparent so the user sees no screen transition. 
 */
class AnswerCallTrampolineActivity : AppCompatActivity() {

    companion object {
        private const val TAG = "AnswerTrampoline"
        const val EXTRA_CALL_ID = "EXTRA_CALL_ID"
        const val EXTRA_CALLER_NAME = "EXTRA_CALLER_NAME"
        const val EXTRA_CALLER_NUMBER = "EXTRA_CALLER_NUMBER"

        private const val REQUEST_CALL_PERMISSIONS = 201

        private val REQUIRED_CALL_PERMISSIONS = arrayOf(
            Manifest.permission.RECORD_AUDIO,
            Manifest.permission.READ_PHONE_STATE,
        )
    }

    private var callId: String = ""
    private var callerName: String = ""
    private var callerNumber: String = ""

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        callId = intent.getStringExtra(EXTRA_CALL_ID) ?: ""
        callerName = intent.getStringExtra(EXTRA_CALLER_NAME) ?: ""
        callerNumber = intent.getStringExtra(EXTRA_CALLER_NUMBER) ?: callerName
        Log.d(TAG, "onCreate: callId=$callId, callerName=$callerName")

        if (callId.isEmpty()) {
            Log.e(TAG, "No callId — finishing")
            finish()
            return
        }

        // Check permissions before answering — without RECORD_AUDIO the call has no audio
        if (!ensureCallPermissions()) {
            Log.w(TAG, "onCreate: Missing permissions — waiting for user grant")
            return // onRequestPermissionsResult will call proceedWithAnswer()
        }

        proceedWithAnswer()
    }

    /**
     * Returns true if all required permissions are granted.
     * If any are missing, requests them (or opens app settings if permanently denied).
     */
    private fun ensureCallPermissions(): Boolean {
        val missing = REQUIRED_CALL_PERMISSIONS.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) return true

        val permanentlyDenied = missing.filter {
            !ActivityCompat.shouldShowRequestPermissionRationale(this, it)
        }

        if (permanentlyDenied.size == missing.size && permanentlyDenied.isNotEmpty()) {
            val prefs = getSharedPreferences("vonage_permissions", Context.MODE_PRIVATE)
            val allPreviouslyRequested = permanentlyDenied.all {
                prefs.getBoolean("requested_$it", false)
            }
            if (allPreviouslyRequested) {
                Log.d(TAG, "All missing permissions permanently denied — opening app settings")
                openAppSettings()
                finish()
                return false
            }
        }

        // Mark as requested
        val prefs = getSharedPreferences("vonage_permissions", Context.MODE_PRIVATE)
        prefs.edit().apply {
            missing.forEach { putBoolean("requested_$it", true) }
            apply()
        }

        Log.d(TAG, "Requesting permissions: $missing")
        ActivityCompat.requestPermissions(this, missing.toTypedArray(), REQUEST_CALL_PERMISSIONS)
        return false
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_CALL_PERMISSIONS) {
            val allGranted = grantResults.isNotEmpty() && grantResults.all {
                it == PackageManager.PERMISSION_GRANTED
            }
            if (allGranted) {
                Log.d(TAG, "Permissions granted — proceeding with answer")
                proceedWithAnswer()
            } else {
                Log.w(TAG, "Permissions denied — cannot answer call")
                finish()
            }
        }
    }

    private fun openAppSettings() {
        try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.fromParts("package", packageName, null)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
        } catch (e: Exception) {
            Log.e(TAG, "openAppSettings: Failed: ${e.message}")
        }
    }

    private fun proceedWithAnswer() {
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

        // Step 2: Check lock state — if locked, store pending data instead of launching
        val keyguardManager = getSystemService(KEYGUARD_SERVICE) as? KeyguardManager
        val isLocked = keyguardManager?.isKeyguardLocked == true

        if (isLocked) {
            Log.d(TAG, "Device is locked — storing pendingAnsweredCallData")
            IncomingCallActivity.pendingAnsweredCallData = mapOf(
                "callId" to callId,
                "callerName" to callerName,
                "callerNumber" to callerNumber,
                "callDirection" to "incoming",
                "isCallAnswered" to true
            )
        } else {
            // Unlocked: Launch MainActivity from this Activity context
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
        }

        // Step 3: Finish immediately (invisible)
        finish()
    }
}
