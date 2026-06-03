package com.iocod.vonage.vonage_voice.call

import android.content.Context
import android.content.Intent
import android.os.Build
import android.telecom.Connection
import android.telecom.DisconnectCause
import androidx.localbroadcastmanager.content.LocalBroadcastManager
import com.iocod.vonage.vonage_voice.IncomingCallActivity
import com.iocod.vonage.vonage_voice.constants.Constants
import com.iocod.vonage.vonage_voice.service.TVConnectionService

/**
 * TVCallInviteConnection — TelecomVoice incoming call invite connection.
 *
 * Represents an incoming call that has arrived via FCM push but has NOT
 * yet been answered or rejected by the user. This is the ringing state.
 *
 * Lifecycle:
 *   1. FCM push arrives → VonageFirebaseMessagingService processes it
 *   2. TVConnectionService creates this connection → system shows incoming call UI
 *   3a. User answers → onAnswer() → startForegroundService(ACTION_ANSWER) → service calls client.answer(callId)
 *   3b. User rejects → onReject() → startForegroundService(ACTION_HANGUP) → service calls client.reject(callId)
 *   3c. Caller cancels → disconnect() called externally → connection destroyed
 *
 * Once answered, TVConnectionService replaces this with a [TVCallConnection]
 * that manages the live call state.
 */
class TVCallInviteConnection(
    private val context: Context,
    val callId: String,
    val from: String,
    val to: String
) : Connection() {

    private val broadcastManager = LocalBroadcastManager.getInstance(context)

    init {
        // Set connection to ringing state immediately on creation
        // so the system UI shows the incoming call screen
        setRinging()
    }

    // ── Connection lifecycle callbacks (called by Android Telecom) ────────

    /**
     * Called when the user answers the call via the system UI,
     * a Bluetooth headset button, or from Flutter via client.answer().
     *
     * Routes ACTION_ANSWER to TVConnectionService via startForegroundService
     * so the service can call VoiceClient.answer(callId) with retry logic.
     */
    override fun onAnswer() {
        android.util.Log.d("TVCallInviteConnection", "onAnswer: callId=$callId")
        val intent = Intent(context, TVConnectionService::class.java).apply {
            action = Constants.ACTION_ANSWER
            putExtra(Constants.EXTRA_CALL_ID, callId)
            putExtra(Constants.EXTRA_CALL_FROM, from)
            putExtra(Constants.EXTRA_CALL_TO, to)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
    }

    /**
     * Called when the user rejects the call via the system UI
     * or from Flutter via client.reject().
     *
     * Routes ACTION_HANGUP to TVConnectionService via startForegroundService
     * so the service can call VoiceClient.reject(callId).
     */
    override fun onReject() {
        android.util.Log.d("TVCallInviteConnection", "onReject: callId=$callId")
        setDisconnected(DisconnectCause(DisconnectCause.REJECTED))
        destroy()
        val intent = Intent(context, TVConnectionService::class.java).apply {
            action = Constants.ACTION_HANGUP
            putExtra(Constants.EXTRA_CALL_ID, callId)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
    }

    /**
     * Called when the system requests an abort — e.g. the caller
     * cancelled before the user answered.
     */
    override fun onAbort() {
        setDisconnected(DisconnectCause(DisconnectCause.CANCELED))
        destroy()
        broadcastEvent(Constants.BROADCAST_CALL_INVITE_CANCELLED)
    }

    /**
     * Called by the Telecom framework for SELF_MANAGED connections after
     * [TelecomManager.addNewIncomingCall]. The system grants a Background
     * Activity Launch (BAL) exemption during this callback, so we can
     * safely call startActivity() to show IncomingCallActivity on the
     * lock screen — no USE_FULL_SCREEN_INTENT or SYSTEM_ALERT_WINDOW needed.
     *
     * If IncomingCallActivity is already alive (placeholder from killed-app
     * path), the singleInstance launch mode + FLAG_ACTIVITY_SINGLE_TOP
     * delivers the real callId via onNewIntent() rather than creating a
     * second instance. The broadcast-based upgrade (BROADCAST_REAL_CALL_READY)
     * is the primary upgrade path; this is the secondary/fallback.
     */
    override fun onShowIncomingCallUi() {
        val activityAlive = IncomingCallActivity.isActivityAlive
        android.util.Log.d("TVCallInviteConnection",
            "onShowIncomingCallUi: callId=$callId, from=$from, isActivityAlive=$activityAlive, " +
            "pid=${android.os.Process.myPid()}")

        if (activityAlive) {
            // The notification's fullScreenIntent already launched the activity
            // on the lock screen with proper keyguard exemption.  Calling
            // startActivity() again from this service context on Samsung A15 /
            // Android 16 would create the activity BEHIND the keyguard (user
            // sees lock screen only).  Deliver callId via onNewIntent() instead.
            android.util.Log.d("TVCallInviteConnection",
                "onShowIncomingCallUi: activity already alive — delivering callId via onNewIntent()")
            try {
                val updateIntent = IncomingCallActivity.createIntent(context, callId, from)
                updateIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                context.startActivity(updateIntent)
            } catch (e: Exception) {
                android.util.Log.e("TVCallInviteConnection",
                    "onShowIncomingCallUi: failed to deliver onNewIntent: ${e.message}")
            }
            return
        }

        // Activity NOT alive — launch it.  This path is the fallback for
        // devices where the notification's fullScreenIntent did NOT fire
        // (e.g. fullScreenIntent permission revoked, DND blocking, etc.).
        try {
            val activityIntent = IncomingCallActivity.createIntent(context, callId, from)
            activityIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(activityIntent)
        } catch (e: Exception) {
            android.util.Log.e("TVCallInviteConnection",
                "onShowIncomingCallUi: failed to launch IncomingCallActivity: ${e.message}")
        }
    }

    // ── Public control methods ────────────────────────────────────────────

    /**
     * Called externally when the remote party cancels the invite
     * (Vonage SDK fires setCallInviteCancelListener).
     * Cleans up this connection and notifies Flutter.
     */
    fun cancel() {
        setDisconnected(DisconnectCause(DisconnectCause.CANCELED))
        destroy()
        broadcastEvent(Constants.BROADCAST_CALL_INVITE_CANCELLED)
    }

    // ── Private broadcast helpers ─────────────────────────────────────────

    /**
     * Broadcast a simple call event with callId attached.
     */

    private fun broadcastEvent(action: String) {
        val intent = Intent(action).apply {
            putExtra(Constants.EXTRA_CALL_ID, callId)
        }
        broadcastManager.sendBroadcast(intent)
    }
}