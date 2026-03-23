package com.iocod.vonage.vonage_voice

import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import android.view.View
import android.view.WindowManager
import android.widget.ImageButton
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.localbroadcastmanager.content.LocalBroadcastManager
import com.iocod.vonage.vonage_voice.constants.Constants
import com.iocod.vonage.vonage_voice.service.TVConnectionService

/**
 * IncomingCallActivity — native full-screen incoming call UI.
 *
 * This Activity is launched by the notification's fullScreenIntent when:
 *   - Device is locked / screen is off → Android launches it full-screen
 *   - USE_FULL_SCREEN_INTENT permission is granted
 *
 * It handles:
 *   - Showing over the lock screen (FLAG_SHOW_WHEN_LOCKED, FLAG_TURN_SCREEN_ON)
 *   - Waking the screen with FULL_WAKE_LOCK
 *   - Playing ringtone and vibration natively (works even when Flutter is dead)
 *   - Answer / Decline buttons
 *   - Launching Flutter MainActivity after answering
 *   - Finishing when the call is cancelled/ended remotely
 *
 * Adapted from the Twilio Voice plugin's IncomingCallActivity pattern.
 */
class IncomingCallActivity : AppCompatActivity() {

    companion object {
        private const val TAG = "IncomingCallActivity"

        const val EXTRA_CALL_ID = "EXTRA_CALL_ID"
        const val EXTRA_CALLER_NAME = "EXTRA_CALLER_NAME"
        const val EXTRA_CALLER_NUMBER = "EXTRA_CALLER_NUMBER"

        /**
         * When answering from lock screen, store call data here.
         * MainActivity.onResume() picks it up after user unlocks.
         */
        @Volatile
        var pendingAnsweredCallData: Map<String, Any>? = null

        /** Prevents duplicate activity instances */
        @Volatile
        var isActivityAlive = false

        fun createIntent(context: Context, callId: String, callerName: String): Intent {
            return Intent(context, IncomingCallActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS
                putExtra(EXTRA_CALL_ID, callId)
                putExtra(EXTRA_CALLER_NAME, callerName)
                putExtra(EXTRA_CALLER_NUMBER, callerName)
            }
        }
    }

    private var callId: String = ""
    private var callerName: String = "Unknown"
    private var callerNumber: String = ""
    private var wasDeviceLockedOnCreate = false

    private var wakeLock: PowerManager.WakeLock? = null
    private var ringtone: Ringtone? = null
    private var vibrator: Vibrator? = null
    private var isRinging = false

    // Receiver to detect when the call is cancelled/ended remotely
    private val callEndedReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val endedCallId = intent.getStringExtra(Constants.EXTRA_CALL_ID)
            Log.d(TAG, "callEndedReceiver: action=${intent.action}, callId=$endedCallId, our callId=$callId")
            if (endedCallId == callId || intent.action == Constants.BROADCAST_CALL_INVITE_CANCELLED) {
                Log.d(TAG, "Call ended/cancelled — finishing IncomingCallActivity")
                stopRinging()
                finish()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Capture lock state BEFORE setShowWhenLocked changes it
        val keyguardManager = getSystemService(KEYGUARD_SERVICE) as KeyguardManager
        wasDeviceLockedOnCreate = keyguardManager.isKeyguardLocked
        Log.d(TAG, "onCreate: wasDeviceLockedOnCreate=$wasDeviceLockedOnCreate")

        // Show over lock screen
        showOverLockScreen()

        // Wake the screen
        wakeScreen()

        // Extract call info from intent
        callId = intent.getStringExtra(EXTRA_CALL_ID) ?: ""
        callerName = intent.getStringExtra(EXTRA_CALLER_NAME) ?: "Unknown"
        callerNumber = intent.getStringExtra(EXTRA_CALLER_NUMBER) ?: callerName

        if (callId.isEmpty()) {
            Log.e(TAG, "onCreate: callId is empty — finishing")
            finish()
            return
        }

        // Prevent duplicate instances — but allow re-creation if the previous was destroyed
        if (isActivityAlive) {
            Log.w(TAG, "onCreate: Activity already alive — finishing duplicate")
            finish()
            return
        }
        isActivityAlive = true

        Log.d(TAG, "onCreate: callId=$callId, callerName=$callerName")

        // Set up the native UI
        setContentView(R.layout.activity_incoming_call)

        val callerNameText = findViewById<TextView>(R.id.caller_name)
        val callerNumberText = findViewById<TextView>(R.id.caller_number)
        val answerButton = findViewById<ImageButton>(R.id.btn_answer)
        val declineButton = findViewById<ImageButton>(R.id.btn_decline)

        callerNameText.text = callerName
        callerNumberText.text = if (callerNumber != callerName) callerNumber else ""

        answerButton.setOnClickListener { handleAnswer() }
        declineButton.setOnClickListener { handleDecline() }

        // Start ringtone and vibration
        startRinging()

        // Listen for call cancelled / ended events
        val filter = IntentFilter().apply {
            addAction(Constants.BROADCAST_CALL_INVITE_CANCELLED)
            addAction(Constants.BROADCAST_CALL_ENDED)
        }
        LocalBroadcastManager.getInstance(this).registerReceiver(callEndedReceiver, filter)

        // Display cutout handling
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        isActivityAlive = false
        stopRinging()
        releaseWakeLock()
        try {
            LocalBroadcastManager.getInstance(this).unregisterReceiver(callEndedReceiver)
        } catch (_: Exception) {}
    }

    // ── Lock screen handling ──────────────────────────────────────────────

    private fun showOverLockScreen() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }

        @Suppress("DEPRECATION")
        window.addFlags(
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
            WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
            WindowManager.LayoutParams.FLAG_ALLOW_LOCK_WHILE_SCREEN_ON or
            WindowManager.LayoutParams.FLAG_FULLSCREEN
        )
    }

    @Suppress("DEPRECATION")
    private fun wakeScreen() {
        try {
            val powerManager = getSystemService(POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.FULL_WAKE_LOCK or
                PowerManager.ACQUIRE_CAUSES_WAKEUP or
                PowerManager.ON_AFTER_RELEASE,
                "VonageVoice:IncomingCallWakeLock"
            ).apply {
                acquire(60_000L) // 60 seconds — enough for incoming call
            }
            Log.d(TAG, "wakeScreen: FULL_WAKE_LOCK acquired")
        } catch (e: Exception) {
            Log.e(TAG, "wakeScreen: Failed to acquire wake lock: ${e.message}")
        }
    }

    private fun releaseWakeLock() {
        try {
            wakeLock?.let { if (it.isHeld) it.release() }
            wakeLock = null
        } catch (e: Exception) {
            Log.e(TAG, "releaseWakeLock: Failed: ${e.message}")
        }
    }

    // ── Ringtone & vibration ──────────────────────────────────────────────

    private fun startRinging() {
        if (isRinging) return
        isRinging = true

        // Play default ringtone
        try {
            val ringtoneUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            ringtone = RingtoneManager.getRingtone(applicationContext, ringtoneUri)
            ringtone?.let { ring ->
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    val audioAttributes = AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                    ring.audioAttributes = audioAttributes
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    ring.isLooping = true
                }
                ring.play()
                Log.d(TAG, "Ringtone started")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error starting ringtone: ${e.message}")
        }

        // Start vibration
        try {
            vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = getSystemService(VIBRATOR_MANAGER_SERVICE) as VibratorManager
                vibratorManager.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(VIBRATOR_SERVICE) as Vibrator
            }
            vibrator?.let { vib ->
                if (vib.hasVibrator()) {
                    val pattern = longArrayOf(0, 1000, 1000)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        vib.vibrate(VibrationEffect.createWaveform(pattern, 0))
                    } else {
                        @Suppress("DEPRECATION")
                        vib.vibrate(pattern, 0)
                    }
                    Log.d(TAG, "Vibration started")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error starting vibration: ${e.message}")
        }
    }

    private fun stopRinging() {
        if (!isRinging) return
        isRinging = false

        try {
            ringtone?.let { if (it.isPlaying) it.stop() }
            ringtone = null
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping ringtone: ${e.message}")
        }

        try {
            vibrator?.cancel()
            vibrator = null
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping vibration: ${e.message}")
        }
    }

    // ── Button handlers ───────────────────────────────────────────────────

    private fun handleAnswer() {
        Log.d(TAG, "handleAnswer: callId=$callId, wasDeviceLockedOnCreate=$wasDeviceLockedOnCreate")
        stopRinging()

        // Send answer intent to TVConnectionService
        val answerIntent = Intent(this, TVConnectionService::class.java).apply {
            action = Constants.ACTION_ANSWER
            putExtra(Constants.EXTRA_CALL_ID, callId)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(answerIntent)
        } else {
            startService(answerIntent)
        }

        // Dismiss keyguard if locked, then launch MainActivity.
        // MainActivity has setShowWhenLocked(true) and requestDismissKeyguard()
        // so it will appear even over the lock screen.
        if (wasDeviceLockedOnCreate) {
            val keyguardManager = getSystemService(KEYGUARD_SERVICE) as KeyguardManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                keyguardManager.requestDismissKeyguard(this, object : KeyguardManager.KeyguardDismissCallback() {
                    override fun onDismissSucceeded() {
                        Log.d(TAG, "handleAnswer: Keyguard dismissed — launching MainActivity")
                        launchMainActivity()
                        finish()
                    }
                    override fun onDismissError() {
                        Log.e(TAG, "handleAnswer: Keyguard dismiss error — launching anyway")
                        launchMainActivity()
                        finish()
                    }
                    override fun onDismissCancelled() {
                        Log.w(TAG, "handleAnswer: Keyguard dismiss cancelled — launching anyway")
                        launchMainActivity()
                        finish()
                    }
                })
            } else {
                launchMainActivity()
                finish()
            }
        } else {
            Log.d(TAG, "handleAnswer: Device was unlocked — launching MainActivity")
            launchMainActivity()
            finish()
        }
    }

    private fun handleDecline() {
        Log.d(TAG, "handleDecline: callId=$callId")
        stopRinging()

        // Send hangup/reject intent to TVConnectionService
        val declineIntent = Intent(this, TVConnectionService::class.java).apply {
            action = Constants.ACTION_HANGUP
            putExtra(Constants.EXTRA_CALL_ID, callId)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(declineIntent)
        } else {
            startService(declineIntent)
        }

        finish()
    }

    private fun launchMainActivity() {
        try {
            val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            launchIntent?.let { intent ->
                intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                intent.putExtra("fromIncomingCall", true)
                intent.putExtra("callHandle", callId)
                intent.putExtra("callAnswered", true)
                intent.putExtra(Constants.EXTRA_CALL_ID, callId)
                intent.putExtra(Constants.EXTRA_CALL_FROM, callerName)
                intent.putExtra(Constants.EXTRA_CALL_DIRECTION, "incoming")
                startActivity(intent)
                Log.d(TAG, "launchMainActivity: Launched successfully")
            }
        } catch (e: Exception) {
            Log.e(TAG, "launchMainActivity: Failed: ${e.message}")
        }
    }

    // Prevent back button from dismissing the incoming call screen
    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        // Do nothing — user must answer or decline
    }
}
