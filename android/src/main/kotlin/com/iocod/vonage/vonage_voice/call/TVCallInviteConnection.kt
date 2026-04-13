package com.iocod.vonage.vonage_voice.call

import android.content.Context
import android.content.Intent
import android.telecom.Connection
import android.telecom.DisconnectCause
import androidx.localbroadcastmanager.content.LocalBroadcastManager
import com.iocod.vonage.vonage_voice.IncomingCallActivity
import com.iocod.vonage.vonage_voice.constants.Constants

/**
 * TVCallInviteConnection — TelecomVoice incoming call invite connection.
 *
 * Represents an incoming call that has arrived via FCM push but has NOT
 * yet been answered or rejected by the user. This is the ringing state.
 *
 * Lifecycle:
 *   1. FCM push arrives → VonageFirebaseMessagingService processes it
 *   2. TVConnectionService creates this connection → system shows incoming call UI
 *   3a. User answers → onAnswer() → broadcasts ACTION_ANSWER → plugin calls client.answer(callId)
 *   3b. User rejects → onReject() → broadcasts ACTION_HANGUP → plugin calls client.reject(callId)
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
     * We broadcast ACTION_ANSWER so TVConnectionService / VonageVoicePlugin
     * can call VoiceClient.answer(callId) on the Vonage SDK.
     */
    override fun onAnswer() {
        broadcastInviteEvent(Constants.ACTION_ANSWER)
    }

    /**
     * Called when the user rejects the call via the system UI
     * or from Flutter via client.reject().
     *
     * We broadcast ACTION_HANGUP so the plugin can call
     * VoiceClient.reject(callId) on the Vonage SDK.
     */
    override fun onReject() {
        setDisconnected(DisconnectCause(DisconnectCause.REJECTED))
        destroy()
        broadcastInviteEvent(Constants.ACTION_HANGUP)
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
     * Broadcast an invite action (answer / reject) with callId attached.
     * TVConnectionService listens for these to trigger Vonage SDK calls.
     */
    private fun broadcastInviteEvent(action: String) {
        val intent = Intent(action).apply {
            putExtra(Constants.EXTRA_CALL_ID, callId)
            putExtra(Constants.EXTRA_CALL_FROM, from)
            putExtra(Constants.EXTRA_CALL_TO, to)
        }
        broadcastManager.sendBroadcast(intent)
    }

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