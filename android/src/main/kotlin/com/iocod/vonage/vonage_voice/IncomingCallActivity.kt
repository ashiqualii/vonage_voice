package com.iocod.vonage.vonage_voice

import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.util.Log
import android.view.WindowManager
import android.view.MotionEvent
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.localbroadcastmanager.content.LocalBroadcastManager
import com.iocod.vonage.vonage_voice.constants.Constants
import com.iocod.vonage.vonage_voice.service.TVConnectionService
import com.iocod.vonage.vonage_voice.ui.AnimatedCallAvatarView

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

    // Receiver to detect when the call is cancelled/ended remotely
    private val callEndedReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val endedCallId = intent.getStringExtra(Constants.EXTRA_CALL_ID)
            Log.d(TAG, "callEndedReceiver: action=${intent.action}, callId=$endedCallId, our callId=$callId")
            if (endedCallId == callId || intent.action == Constants.BROADCAST_CALL_INVITE_CANCELLED) {
                Log.d(TAG, "Call ended/cancelled — finishing IncomingCallActivity")
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
        val acceptButtonContainer = findViewById<FrameLayout>(R.id.acceptButton)
        val acceptButtonIcon = findViewById<ImageView>(R.id.acceptButtonCircle)
        val declineButtonContainer = findViewById<FrameLayout>(R.id.declineButton)
        val declineButtonIcon = findViewById<ImageView>(R.id.declineButtonCircle)

        // Bottom sheet views
        val bottomSheetOverlay = findViewById<View>(R.id.callWaitingBottomSheetOverlay)
        val bottomSheet = findViewById<View>(R.id.callWaitingBottomSheet)
        val optionHoldAndAnswer = findViewById<View>(R.id.optionHoldAndAnswer)
        val optionEndAndAnswer = findViewById<View>(R.id.optionEndAndAnswer)
        val optionDecline = findViewById<View>(R.id.optionDecline)

        callerNameText.text = callerName
        callerNumberText.text = if (callerNumber != callerName) callerNumber else ""

        // Add elevation for depth
        acceptButtonContainer.elevation = 12f
        declineButtonContainer.elevation = 12f
        acceptButtonIcon.elevation = 14f
        declineButtonIcon.elevation = 14f

        // Setup swipe/tap animations on both buttons
        setupButtonSwipeAnimation(acceptButtonContainer, acceptButtonIcon) { handleAnswer() }
        setupButtonSwipeAnimation(declineButtonContainer, declineButtonIcon) { handleDecline() }

        // Bottom sheet dismiss on overlay tap
        bottomSheetOverlay.setOnClickListener {
            bottomSheetOverlay.visibility = View.GONE
            bottomSheet.visibility = View.GONE
        }
        optionHoldAndAnswer.setOnClickListener { handleAnswer() }
        optionEndAndAnswer.setOnClickListener { handleAnswer() }
        optionDecline.setOnClickListener { handleDecline() }

        // Ringing is managed by TVConnectionService — no startRinging() here

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

    // ── Button handlers ───────────────────────────────────────────────────

    private fun handleAnswer() {
        Log.d(TAG, "handleAnswer: callId=$callId, wasDeviceLockedOnCreate=$wasDeviceLockedOnCreate")

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

        // Handle lock screen: if device is locked, store pending data and let the
        // user unlock naturally. MainActivity.onResume() picks up pendingAnsweredCallData.
        // If unlocked, dismiss any lingering keyguard then launch MainActivity directly.
        val keyguardManager = getSystemService(KEYGUARD_SERVICE) as KeyguardManager
        val isCurrentlyLocked = keyguardManager.isKeyguardLocked

        if (isCurrentlyLocked) {
            Log.d(TAG, "handleAnswer: Device is locked — storing pendingAnsweredCallData")
            pendingAnsweredCallData = mapOf(
                "callId" to callId,
                "callerName" to callerName,
                "callerNumber" to callerNumber,
                "callDirection" to "incoming",
                "isCallAnswered" to true
            )
            finish()
        } else {
            Log.d(TAG, "handleAnswer: Device is unlocked — launching MainActivity")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                if (keyguardManager.isKeyguardLocked) {
                    keyguardManager.requestDismissKeyguard(this, object : KeyguardManager.KeyguardDismissCallback() {
                        override fun onDismissSucceeded() {
                            launchMainActivity()
                            finish()
                        }
                        override fun onDismissCancelled() {
                            launchMainActivity()
                            finish()
                        }
                        override fun onDismissError() {
                            launchMainActivity()
                            finish()
                        }
                    })
                } else {
                    launchMainActivity()
                    finish()
                }
            } else {
                launchMainActivity()
                finish()
            }
        }
    }

    private fun handleDecline() {
        Log.d(TAG, "handleDecline: callId=$callId")

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

    /**
     * Setup swipe/drag animation on a button.
     * - Tap: immediate bounce + haptic → triggers action
     * - Drag 120dp+: progressive scale up + haptic → triggers action
     */
    @Suppress("ClickableViewAccessibility")
    private fun setupButtonSwipeAnimation(
        container: FrameLayout,
        icon: ImageView,
        onAction: () -> Unit
    ) {
        var startX = 0f
        var startY = 0f
        var isDragging = false
        var hasCompleted = false

        container.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    startX = event.x
                    startY = event.y
                    isDragging = false
                    hasCompleted = false

                    // Press scale-up
                    container.animate().scaleX(1.15f).scaleY(1.15f).setDuration(120).start()
                    icon.animate().scaleX(1.2f).scaleY(1.2f).setDuration(120).start()
                    container.animate().alpha(0.9f).setDuration(120).start()
                    true
                }

                MotionEvent.ACTION_MOVE -> {
                    val dx = kotlin.math.abs(event.x - startX)
                    val dy = kotlin.math.abs(event.y - startY)
                    val total = kotlin.math.sqrt((dx * dx + dy * dy).toDouble()).toFloat()

                    if (dx > 40 || dy > 40) {
                        isDragging = true
                        val scale = 1.15f + (total / 300f).coerceAtMost(0.15f)
                        container.scaleX = scale
                        container.scaleY = scale
                        val iconScale = 1.2f + (total / 300f).coerceAtMost(0.3f)
                        icon.scaleX = iconScale
                        icon.scaleY = iconScale
                        container.alpha = 0.9f + (total / 500f).coerceAtMost(0.1f)

                        if (total > 120 && !hasCompleted) {
                            hasCompleted = true
                            container.performHapticFeedback(android.view.HapticFeedbackConstants.LONG_PRESS)
                            // Bounce back animation
                            container.animate().scaleX(0.9f).scaleY(0.9f).setDuration(80)
                                .withEndAction {
                                    container.animate().scaleX(1f).scaleY(1f).setDuration(100).start()
                                }.start()
                            icon.animate().scaleX(0.95f).scaleY(0.95f).setDuration(80)
                                .withEndAction {
                                    icon.animate().scaleX(1f).scaleY(1f).setDuration(100).start()
                                }.start()
                            container.animate().alpha(1f).setDuration(200).start()
                            onAction()
                            isDragging = false
                            return@setOnTouchListener true
                        }
                    }
                    true
                }

                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    if (!isDragging && !hasCompleted) {
                        hasCompleted = true
                        container.performHapticFeedback(android.view.HapticFeedbackConstants.KEYBOARD_TAP)
                        // Tap bounce
                        container.animate().scaleX(0.95f).scaleY(0.95f).setDuration(100)
                            .withEndAction {
                                container.animate().scaleX(1f).scaleY(1f).setDuration(100).start()
                            }.start()
                        onAction()
                    }
                    // Reset
                    container.animate().scaleX(1f).scaleY(1f).setDuration(200).start()
                    icon.animate().scaleX(1f).scaleY(1f).setDuration(200).start()
                    container.animate().alpha(1f).setDuration(200).start()
                    true
                }

                else -> false
            }
        }
    }

    private fun getInitials(name: String): String {
        if (name.isEmpty()) return "?"
        // If it looks like a phone number, return #
        if (name.startsWith("+") || name.all { it.isDigit() || it == ' ' || it == '-' || it == '(' || it == ')' }) {
            return "#"
        }
        val parts = name.trim().split("\\s+".toRegex())
        return when {
            parts.size >= 2 -> "${parts[0].first().uppercaseChar()}${parts[1].first().uppercaseChar()}"
            parts.isNotEmpty() -> parts[0].first().uppercaseChar().toString()
            else -> "?"
        }
    }
}
