package com.iocod.vonage.vonage_voice

import android.Manifest
import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import android.view.WindowManager
import android.view.MotionEvent
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
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

        private const val REQUEST_CALL_PERMISSIONS = 200

        /** Permissions required to answer a call */
        private val REQUIRED_CALL_PERMISSIONS = arrayOf(
            Manifest.permission.RECORD_AUDIO,
            Manifest.permission.READ_PHONE_STATE,
        )

        fun createIntent(context: Context, callId: String, callerName: String): Intent {
            return Intent(context, IncomingCallActivity::class.java).apply {
                // FLAG_ACTIVITY_NO_USER_ACTION is critical for fullScreenIntent on lock screen.
                // Without it, Android shows a heads-up notification instead of full-screen.
                // FLAG_ACTIVITY_CLEAR_TOP is intentionally NOT used — combined with
                // singleInstance launchMode it destroys and recreates the activity.
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                        Intent.FLAG_ACTIVITY_NO_USER_ACTION
                action = "com.iocod.vonage.vonage_voice.INCOMING_CALL"
                putExtra(EXTRA_CALL_ID, callId)
                putExtra(EXTRA_CALLER_NAME, callerName)
                putExtra(EXTRA_CALLER_NUMBER, callerName)
            }
        }

        /**
         * Creates an intent for the placeholder state (no callId yet).
         * Used by buildPlaceholderIncomingNotification() so the incoming
         * call screen appears immediately on lock screen while the Vonage
         * SDK processes the push asynchronously.
         *
         * The activity shows the caller name and a "Connecting..." state.
         * Answer button is disabled until a real callId arrives via onNewIntent().
         */
        fun createPlaceholderIntent(context: Context, callerName: String): Intent {
            return Intent(context, IncomingCallActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                        Intent.FLAG_ACTIVITY_NO_USER_ACTION
                action = "com.iocod.vonage.vonage_voice.INCOMING_CALL"
                // Empty callId signals placeholder state
                putExtra(EXTRA_CALL_ID, "")
                putExtra(EXTRA_CALLER_NAME, callerName)
                putExtra(EXTRA_CALLER_NUMBER, callerName)
            }
        }
    }

    private var callId: String = ""
    private var callerName: String = "Unknown"
    private var callerNumber: String = ""
    private var wasDeviceLockedOnCreate = false
    /** True when launched as a placeholder (no callId yet) */
    private var isPlaceholderMode = false

    private var wakeLock: PowerManager.WakeLock? = null

    // Idempotency flag — prevents double-processing when answer/decline races
    // with callEndedReceiver. Whichever path sets it first wins.
    @Volatile
    private var callHandled = false

    // Receiver to detect when the call is cancelled/ended/answered externally,
    // AND when the real callId arrives (placeholder → real upgrade).
    private val callEndedReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                Constants.BROADCAST_REAL_CALL_READY -> {
                    // ── Placeholder → Real mode upgrade via broadcast ──────────
                    // This is the primary upgrade path for the killed-app scenario.
                    // TVConnectionService sends this as soon as it has a real callId.
                    // Unlike onNewIntent(), this does NOT depend on a fullScreenIntent
                    // re-trigger which Samsung/Xiaomi devices may suppress.
                    val realCallId = intent.getStringExtra(Constants.EXTRA_CALL_ID) ?: return
                    if (isPlaceholderMode && realCallId.isNotEmpty()) {
                        Log.d(TAG, "BROADCAST_REAL_CALL_READY: Upgrading placeholder → real, callId=$realCallId")
                        callId = realCallId
                        isPlaceholderMode = false
                        val newFrom = intent.getStringExtra(Constants.EXTRA_CALL_FROM)
                        if (!newFrom.isNullOrEmpty()) {
                            callerName = newFrom
                            callerNumber = newFrom
                            findViewById<TextView>(R.id.caller_name)?.text = callerName
                        }
                        // Re-enable the answer button
                        findViewById<FrameLayout>(R.id.acceptButton)?.alpha = 1.0f
                    }
                    return
                }
            }

            val endedCallId = intent.getStringExtra(Constants.EXTRA_CALL_ID)
            Log.d(TAG, "callEndedReceiver: action=${intent.action}, callId=$endedCallId, our callId=$callId")

            // Only react to events for OUR call (or blanket cancel broadcast)
            if (endedCallId != callId && intent.action != Constants.BROADCAST_CALL_INVITE_CANCELLED) return

            // If the call was answered externally (Samsung tile, BT headset, notification)
            // while the device is locked, store pending data so MainActivity.onResume()
            // can navigate directly to the active call screen after the user unlocks.
            if (intent.action == Constants.BROADCAST_CALL_ANSWERED && wasDeviceLockedOnCreate) {
                Log.d(TAG, "callEndedReceiver: Call answered externally while locked — storing pendingAnsweredCallData")
                pendingAnsweredCallData = mapOf(
                    "callId" to callId,
                    "callerName" to callerName,
                    "callerNumber" to callerNumber,
                    "callDirection" to "incoming",
                    "isCallAnswered" to true
                )
            }

            Log.d(TAG, "Call ended/cancelled/answered externally — cleaning up")
            callHandled = true
            releaseWakeLock()
            finish()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.i(TAG, "onCreate: START pid=${android.os.Process.myPid()}")

        try {
            onCreateInternal(savedInstanceState)
        } catch (e: Exception) {
            Log.e(TAG, "onCreate: CRASHED — finishing activity", e)
            isActivityAlive = false
            finish()
        }
    }

    private fun onCreateInternal(savedInstanceState: Bundle?) {

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

        // Safety net: if callId is empty (placeholder fullScreenIntent fired before
        // handleIncomingCall wrote the real notification), try to recover from
        // SharedPreferences where handleIncomingCall persists the pending call data.
        // This handles the race where ensureForeground posts a placeholder notification
        // before handleIncomingCall runs, AND covers process-recreation scenarios.
        if (callId.isEmpty()) {
            try {
                val prefs = getSharedPreferences(TVConnectionService.PREFS_PENDING_CALL, MODE_PRIVATE)
                val storedCallId = prefs.getString(TVConnectionService.KEY_PENDING_CALL_ID, null)
                val storedFrom = prefs.getString(TVConnectionService.KEY_PENDING_CALL_FROM, null)
                val storedTs = prefs.getLong(TVConnectionService.KEY_PENDING_CALL_TIMESTAMP, 0)
                val age = System.currentTimeMillis() - storedTs
                if (!storedCallId.isNullOrEmpty() && age < 120_000L) {
                    callId = storedCallId
                    if (!storedFrom.isNullOrEmpty()) {
                        callerName = storedFrom
                        callerNumber = storedFrom
                    }
                    Log.d(TAG, "onCreate: Recovered callId=$callId from SharedPreferences (age=${age}ms)")
                }
            } catch (e: Exception) {
                Log.w(TAG, "onCreate: SharedPreferences recovery failed: ${e.message}")
            }
        }

        // Placeholder mode: launched by the placeholder notification before
        // Vonage SDK has processed the push. Show UI immediately but disable
        // Answer until a real callId arrives via onNewIntent().
        isPlaceholderMode = callId.isEmpty()
        if (isPlaceholderMode) {
            Log.d(TAG, "onCreate: Placeholder mode — no callId yet, waiting for real intent")
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
        setContentView(R.layout.vonage_activity_incoming_call)

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

        // In placeholder mode, dim the answer button until callId arrives
        if (isPlaceholderMode) {
            acceptButtonContainer.alpha = 0.5f
        }

        // Bottom sheet dismiss on overlay tap
        bottomSheetOverlay.setOnClickListener {
            bottomSheetOverlay.visibility = View.GONE
            bottomSheet.visibility = View.GONE
        }
        optionHoldAndAnswer.setOnClickListener { handleAnswer() }
        optionEndAndAnswer.setOnClickListener { handleAnswer() }
        optionDecline.setOnClickListener { handleDecline() }

        // Ringing is managed by TVConnectionService — no startRinging() here

        // Listen for call cancelled / ended / answered-externally / real-call-ready events
        val filter = IntentFilter().apply {
            addAction(Constants.BROADCAST_CALL_INVITE_CANCELLED)
            addAction(Constants.BROADCAST_CALL_ENDED)
            addAction(Constants.BROADCAST_CALL_ANSWERED)
            addAction(Constants.BROADCAST_REAL_CALL_READY)
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

    /**
     * Called when a new intent arrives while the activity is already running
     * (due to singleInstance launch mode + FLAG_ACTIVITY_SINGLE_TOP).
     *
     * This is the mechanism by which the placeholder activity receives the
     * real callId: the real notification's fullScreenIntent fires with a
     * non-empty callId, which is delivered here instead of creating a new activity.
     */
    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        // Persist the latest intent so Android uses it when recreating the task
        // after a process death (singleInstance keeps the task record).
        setIntent(intent)
        val newCallId = intent?.getStringExtra(EXTRA_CALL_ID) ?: ""
        val newCallerName = intent?.getStringExtra(EXTRA_CALLER_NAME)
        Log.d(TAG, "onNewIntent: newCallId=$newCallId, newCallerName=$newCallerName, isPlaceholderMode=$isPlaceholderMode")

        if (newCallId.isNotEmpty() && isPlaceholderMode) {
            // Transition from placeholder to real incoming call
            callId = newCallId
            isPlaceholderMode = false
            if (!newCallerName.isNullOrEmpty()) {
                callerName = newCallerName
                callerNumber = newCallerName
                findViewById<TextView>(R.id.caller_name)?.text = callerName
            }
            // Re-enable the answer button
            findViewById<FrameLayout>(R.id.acceptButton)?.alpha = 1.0f
            Log.d(TAG, "onNewIntent: Placeholder → Real mode, callId=$callId")
        } else if (newCallId.isNotEmpty()) {
            // Activity was already in real mode but received updated callId
            callId = newCallId
            if (!newCallerName.isNullOrEmpty()) {
                callerName = newCallerName
            }
            Log.d(TAG, "onNewIntent: Updated callId=$callId")
        }
    }

    // ── Lock screen handling ──────────────────────────────────────────────

    private fun showOverLockScreen() {
        Log.d(TAG, "showOverLockScreen: Setting up window flags for lock screen display")

        val isMiui = isMiuiDevice()
        Log.d(TAG, "showOverLockScreen: isMiuiDevice=$isMiui")

        // NOTE: FLAG_DISMISS_KEYGUARD is intentionally NOT included.
        // It triggers a system unlock dialog on secure lock screens (PIN/pattern)
        // that steals focus and blocks ALL touch events — user can see the
        // incoming call UI but cannot interact with answer/decline buttons.
        @Suppress("DEPRECATION")
        window.addFlags(
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
            WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
            WindowManager.LayoutParams.FLAG_ALLOW_LOCK_WHILE_SCREEN_ON or
            WindowManager.LayoutParams.FLAG_FULLSCREEN
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            Log.d(TAG, "showOverLockScreen: setShowWhenLocked and setTurnScreenOn called")
        }

        // Display cutout handling for notched devices (Android P+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }

        // MIUI-specific handling — use system overlay window type ONLY when
        // device is locked. On unlocked devices, this creates a visible overlay
        // artifact between the heads-up notification and app content.
        if (isMiui && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val km = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
            val isDeviceCurrentlyLocked = km?.isKeyguardLocked == true
            if (isDeviceCurrentlyLocked) {
                try {
                    if (Settings.canDrawOverlays(this)) {
                        Log.d(TAG, "showOverLockScreen: MIUI device locked — setting TYPE_APPLICATION_OVERLAY")
                        window.setType(WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY)
                    } else {
                        Log.w(TAG, "showOverLockScreen: MIUI device locked — NO overlay permission")
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "showOverLockScreen: Failed to set overlay window type: ${e.message}")
                }
            } else {
                Log.d(TAG, "showOverLockScreen: MIUI device unlocked — skipping TYPE_APPLICATION_OVERLAY")
            }
        }

        // Force full screen brightness — some OEMs keep screen dim even with TURN_SCREEN_ON
        try {
            window.attributes = window.attributes.apply {
                screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_FULL
            }
        } catch (e: Exception) {
            Log.w(TAG, "showOverLockScreen: Failed to set brightness: ${e.message}")
        }
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
        Log.d(TAG, "handleAnswer: callId=$callId, wasDeviceLockedOnCreate=$wasDeviceLockedOnCreate, isPlaceholderMode=$isPlaceholderMode")

        // In placeholder mode (no callId yet), ignore answer taps
        if (isPlaceholderMode || callId.isEmpty()) {
            Log.d(TAG, "handleAnswer: Still in placeholder mode — callId not available yet")
            return
        }

        if (callHandled) {
            Log.d(TAG, "handleAnswer: callHandled=true — already processed, finishing")
            finish()
            return
        }

        // Check permissions before answering — without RECORD_AUDIO the call has no audio
        if (!ensureCallPermissions("handleAnswer")) {
            Log.w(TAG, "handleAnswer: Missing permissions — waiting for user grant")
            return
        }

        callHandled = true

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

        releaseWakeLock()

        val deviceLocked = isDeviceLocked()
        Log.d(TAG, "handleAnswer: isDeviceLocked=$deviceLocked")

        if (deviceLocked) {
            // LOCK SCREEN FLOW: The call is answered (audio connects via service above).
            // We do NOT use requestDismissKeyguard() — on Samsung A15/SDK 36 it works
            // once then silently fails on subsequent calls, blocking the Looper for
            // 15-20 seconds and preventing LocalBroadcastManager from delivering events.
            // Instead: store pending data, finish, let user unlock normally.
            // MainActivity.onResume() detects pendingAnsweredCallData and navigates.
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
            launchMainActivity()
            finish()
        }
    }

    private fun handleDecline() {
        Log.d(TAG, "handleDecline: callId=$callId, isPlaceholderMode=$isPlaceholderMode")

        if (callHandled) {
            Log.d(TAG, "handleDecline: callHandled=true — already processed, finishing")
            finish()
            return
        }
        callHandled = true

        if (isPlaceholderMode || callId.isEmpty()) {
            // No callId yet — send cleanup to stop ringing and foreground service
            Log.d(TAG, "handleDecline: Placeholder mode — sending CLEANUP")
            val cleanupIntent = Intent(this, TVConnectionService::class.java).apply {
                action = Constants.ACTION_CLEANUP
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(cleanupIntent)
            } else {
                startService(cleanupIntent)
            }
        } else {
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
        }

        releaseWakeLock()
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

    // ── Permission handling ─────────────────────────────────────────────

    /**
     * Returns true if all [REQUIRED_CALL_PERMISSIONS] are granted.
     * If any are missing, requests them (or opens app settings if permanently denied)
     * and returns false.
     */
    private fun ensureCallPermissions(callerTag: String): Boolean {
        val missing = REQUIRED_CALL_PERMISSIONS.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) return true

        // Check if all missing permissions are permanently denied ("Don't ask again").
        val permanentlyDenied = missing.filter {
            !ActivityCompat.shouldShowRequestPermissionRationale(this, it)
        }

        if (permanentlyDenied.size == missing.size && permanentlyDenied.isNotEmpty()) {
            val prefs = getSharedPreferences("vonage_permissions", Context.MODE_PRIVATE)
            val allPreviouslyRequested = permanentlyDenied.all {
                prefs.getBoolean("requested_$it", false)
            }
            if (allPreviouslyRequested) {
                Log.d(TAG, "$callerTag: All missing permissions permanently denied, opening app settings")
                openAppSettings()
                return false
            }
        }

        // Mark as requested and show dialog
        val prefs = getSharedPreferences("vonage_permissions", Context.MODE_PRIVATE)
        prefs.edit().apply {
            missing.forEach { putBoolean("requested_$it", true) }
            apply()
        }

        Log.d(TAG, "$callerTag: Requesting missing permissions: $missing")
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
                handleAnswer()
            } else {
                Log.w(TAG, "Permissions denied — cannot answer call")
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

    // ── Lock state detection ──────────────────────────────────────────────

    /**
     * Check if the device is locked using dual-check approach.
     *
     * After setShowWhenLocked(true), isKeyguardLocked returns false from this
     * activity's context — Android considers the keyguard "dismissed" for
     * activities showing over the lock screen, even though the user hasn't
     * entered their PIN/pattern. We use the cached wasDeviceLockedOnCreate
     * value AND a fresh check — both must agree for "locked" result.
     *
     * On MIUI, isKeyguardLocked may return true even when the user is actively
     * using the phone (MIUI's "light" lock state). If the fresh check says
     * unlocked, trust it — the user has clearly authenticated.
     */
    private fun isDeviceLocked(): Boolean {
        val keyguardMgr = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        val freshLocked = keyguardMgr?.isKeyguardLocked == true
        val result = wasDeviceLockedOnCreate && freshLocked
        if (wasDeviceLockedOnCreate != freshLocked) {
            Log.d(TAG, "isDeviceLocked: wasDeviceLockedOnCreate=$wasDeviceLockedOnCreate, freshKeyguardLocked=$freshLocked, returning=$result")
        }
        return result
    }

    // ── MIUI device detection ─────────────────────────────────────────────

    private fun isMiuiDevice(): Boolean {
        return try {
            val prop = Class.forName("android.os.SystemProperties")
            val get = prop.getMethod("get", String::class.java)
            val miuiVersion = get.invoke(null, "ro.miui.ui.version.name") as? String
            val brand = Build.BRAND.lowercase()
            val manufacturer = Build.MANUFACTURER.lowercase()

            val isMiui = !miuiVersion.isNullOrEmpty() ||
                         brand.contains("xiaomi") ||
                         brand.contains("redmi") ||
                         brand.contains("poco") ||
                         manufacturer.contains("xiaomi") ||
                         manufacturer.contains("redmi")
            isMiui
        } catch (e: Exception) {
            val brand = Build.BRAND.lowercase()
            val manufacturer = Build.MANUFACTURER.lowercase()
            brand.contains("xiaomi") || brand.contains("redmi") || brand.contains("poco") ||
            manufacturer.contains("xiaomi") || manufacturer.contains("redmi")
        }
    }

    private fun getInitials(name: String): String {
        if (name.isEmpty()) return "?"
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
